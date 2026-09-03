class_name WhormbusEvent
extends WorldEvent
## A giant worm crosses the island until archers drive it back, then
## burrows down and stops rather than toppling.
##
## Owns no state itself. Triggering it hands a Whormbus to the event
## manager, and the worm is what walks, stomps and falls on the simulation
## clock.

func id() -> StringName:
	return &"worm"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("worm") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Whormbus.MAX_HEALTH))
	if health <= 0.0:
		push_error("WhormbusEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Whormbus and not child.is_queued_for_deletion():
			push_error("WhormbusEvent: a worm is already loose.")
			return ""

	var worm := Whormbus.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"worm", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Whormbus.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if worm == null:
		return ""
	events.adopt(worm)

	return "A giant worm surfaces at (%d, %d)" % [roundi(at.x), roundi(at.y)]
