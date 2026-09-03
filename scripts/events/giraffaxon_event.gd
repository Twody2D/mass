class_name GiraffaxonEvent
extends WorldEvent
## A giant giraffe stomps the island until archers drive it off.
##
## Owns no state itself. Triggering it hands a Giraffaxon to the event
## manager, and the giraffe is what walks, swings its neck and falls on the
## simulation clock.

func id() -> StringName:
	return &"giraffe"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("giraffe") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Giraffaxon.MAX_HEALTH))
	if health <= 0.0:
		push_error("GiraffaxonEvent: health must be positive, got %f." % health)
		return ""

	for child in events.get_children():
		if child is Giraffaxon and not child.is_queued_for_deletion():
			push_error("GiraffaxonEvent: a giraffe is already loose.")
			return ""

	var giraffe := Giraffaxon.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"giraffe", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Giraffaxon.ATTACK_RANGE, strength),
		func(from: Vector3, to: Vector3) -> void: events.archer_shot(from, to))
	if giraffe == null:
		return ""
	events.adopt(giraffe)

	return "A giant giraffe stomps in at (%d, %d)" % [roundi(at.x), roundi(at.y)]
