class_name RombophantEvent
extends WorldEvent
## A giant rhinoceros charges into the thickest part of the crowd it can
## find, over and over, until archers drive it back.
##
## Owns no state itself. Triggering it hands a Rombophant to the event
## manager, and the rhino is what charges, stomps and falls on the
## simulation clock.

func id() -> StringName:
	return &"rhino"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("rhino") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Rombophant.MAX_HEALTH))
	if health <= 0.0:
		push_error("RombophantEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Rombophant and not child.is_queued_for_deletion():
			push_error("RombophantEvent: a rhino is already loose.")
			return ""

	var rhino := Rombophant.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"rhino", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Rombophant.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if rhino == null:
		return ""
	events.adopt(rhino)

	return "A giant rhino tramples ashore at (%d, %d)" % [roundi(at.x), roundi(at.y)]
