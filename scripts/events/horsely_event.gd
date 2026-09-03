class_name HorselyEvent
extends WorldEvent
## A giant horse gallops across the island, rearing with every stomp, until
## archers drive it back.
##
## Owns no state itself. Triggering it hands a Horsely to the event
## manager, and the horse is what runs, stomps and falls on the simulation
## clock.

func id() -> StringName:
	return &"horse"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("horse") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Horsely.MAX_HEALTH))
	if health <= 0.0:
		push_error("HorselyEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Horsely and not child.is_queued_for_deletion():
			push_error("HorselyEvent: a horse is already loose.")
			return ""

	var horse := Horsely.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"horse", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Horsely.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if horse == null:
		return ""
	events.adopt(horse)

	return "A giant horse gallops ashore at (%d, %d)" % [roundi(at.x), roundi(at.y)]
