class_name CrabylonEvent
extends WorldEvent
## A giant crab walks the island sideways until archers drive it back.
##
## Owns no state itself. Triggering it hands a Crabylon to the event
## manager, and the crab is what walks, stomps and falls on the simulation
## clock.

func id() -> StringName:
	return &"crab"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("crab") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Crabylon.MAX_HEALTH))
	if health <= 0.0:
		push_error("CrabylonEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Crabylon and not child.is_queued_for_deletion():
			push_error("CrabylonEvent: a crab is already loose.")
			return ""

	var crab := Crabylon.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"crab", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Crabylon.ATTACK_RANGE, strength))
	if crab == null:
		return ""
	events.adopt(crab)

	return "A giant crab scuttles ashore at (%d, %d)" % [roundi(at.x), roundi(at.y)]
