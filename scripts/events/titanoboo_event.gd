class_name TitanobooEvent
extends WorldEvent
## A giant snake slithers across the island until archers drive it off.
##
## Owns no state itself. Triggering it hands a Titanoboo to the event
## manager, and the snake is what slithers, bites and falls on the
## simulation clock.

func id() -> StringName:
	return &"snake"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("snake") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Titanoboo.MAX_HEALTH))
	if health <= 0.0:
		push_error("TitanobooEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Titanoboo and not child.is_queued_for_deletion():
			push_error("TitanobooEvent: a snake is already loose.")
			return ""

	var snake := Titanoboo.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"snake", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Titanoboo.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if snake == null:
		return ""
	events.adopt(snake)

	return "A giant snake slithers in at (%d, %d)" % [roundi(at.x), roundi(at.y)]
