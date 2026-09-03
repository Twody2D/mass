class_name RaptorousEvent
extends WorldEvent
## A giant raptor charges the island, sprinting the last stretch to whatever
## it is heading for, until archers drive it back.
##
## Owns no state itself. Triggering it hands a Raptorous to the event
## manager, and the raptor is what walks, lunges, stomps and falls on the
## simulation clock.

func id() -> StringName:
	return &"raptor"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("raptor") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Raptorous.MAX_HEALTH))
	if health <= 0.0:
		push_error("RaptorousEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Raptorous and not child.is_queued_for_deletion():
			push_error("RaptorousEvent: a raptor is already loose.")
			return ""

	var raptor := Raptorous.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"raptor", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Raptorous.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if raptor == null:
		return ""
	events.adopt(raptor)

	return "A giant raptor charges ashore at (%d, %d)" % [roundi(at.x), roundi(at.y)]
