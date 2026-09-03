class_name DragonEvent
extends WorldEvent
## A giant dragon patrols the sky over the island, swooping low to strike
## and harried back by archers, until it crashes.
##
## Owns no state itself. Triggering it hands a Dragon to the event manager,
## and the dragon is what flies, strikes and falls on the simulation clock.

func id() -> StringName:
	return &"dragon"


## params: "x"/"z" to place it, "health" for how much it takes to bring it
## down. All optional, so trigger("dragon") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Dragon.MAX_HEALTH))
	if health <= 0.0:
		push_error("DragonEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Dragon and not child.is_queued_for_deletion():
			push_error("DragonEvent: a dragon is already loose.")
			return ""

	var dragon := Dragon.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"dragon", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Dragon.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if dragon == null:
		return ""
	events.adopt(dragon)

	return "A giant dragon circles overhead near (%d, %d)" % [roundi(at.x), roundi(at.y)]
