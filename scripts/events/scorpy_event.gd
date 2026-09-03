class_name ScorpyEvent
extends WorldEvent
## A giant scorpion stalks the island, striking with a tail curled forward
## over its own back, until archers drive it back.
##
## Owns no state itself. Triggering it hands a Scorpy to the event manager,
## and the scorpion is what walks, stomps and falls on the simulation
## clock.

func id() -> StringName:
	return &"scorpion"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("scorpion") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Scorpy.MAX_HEALTH))
	if health <= 0.0:
		push_error("ScorpyEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Scorpy and not child.is_queued_for_deletion():
			push_error("ScorpyEvent: a scorpion is already loose.")
			return ""

	var scorpion := Scorpy.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"scorpion", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Scorpy.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if scorpion == null:
		return ""
	events.adopt(scorpion)

	return "A giant scorpion skitters ashore at (%d, %d)" % [roundi(at.x), roundi(at.y)]
