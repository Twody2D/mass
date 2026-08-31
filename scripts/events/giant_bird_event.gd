class_name GiantBirdEvent
extends WorldEvent
## A giant chicken drops out of the sky somewhere on the island.
##
## Owns no state itself. Triggering it hands a GiantBird to the event
## manager, and the bird is what falls, walks, stomps and topples on the
## simulation clock — the same shape MonsterEvent/KrakenEvent already use.

func id() -> StringName:
	return &"chicken"


## params: "x"/"z" for where it lands, "health" for how much it takes to
## chase off. All optional, so trigger("chicken") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", GiantBird.MAX_HEALTH))
	if health <= 0.0:
		push_error("GiantBirdEvent: health must be positive, got %f." % health)
		return ""

	# One chicken at a time, the same reasoning MonsterEvent/KrakenEvent
	# already refuse a second giant for.
	for child in events.get_children():
		if child is GiantBird and not child.is_queued_for_deletion():
			push_error("GiantBirdEvent: a chicken is already loose.")
			return ""

	var bird := GiantBird.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"chicken", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, GiantBird.ATTACK_RANGE, strength))
	if bird == null:
		return ""
	events.adopt(bird)

	return "A giant chicken plummets toward (%d, %d)" % [roundi(at.x), roundi(at.y)]
