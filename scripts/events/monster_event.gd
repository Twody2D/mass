class_name MonsterEvent
extends WorldEvent
## A giant walks the island until archers bring it down.
##
## The first event whose outcome depends on which class the crowd is made
## of, not just on how many of it are left — warriors and spearmen can only
## run, and an archer standing at range is the one thing here that actually
## hurts it. That dependency is exactly why this waited for classes (48) to
## exist before it could be written at all.
##
## Owns no state itself. Triggering it hands a Monster to the event manager,
## and the monster is what walks, stomps and falls on the simulation clock.

func id() -> StringName:
	return &"monster"


## params: "x"/"z" to place it, "health" for how much it takes to bring down.
## All optional, so trigger("monster") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_land_point(rng)

	var health := float(params.get("health", Monster.MAX_HEALTH))
	if health <= 0.0:
		push_error("MonsterEvent: health must be positive, got %f." % health)
		return ""

	# Two giants would each be stomping and taking damage independently,
	# which reads as one, confusingly resilient monster rather than two.
	for child in events.get_children():
		if child is Monster and not child.is_queued_for_deletion():
			push_error("MonsterEvent: a monster is already loose.")
			return ""

	var monster := Monster.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"monster", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Monster.ATTACK_RANGE, strength))
	if monster == null:
		return ""
	events.adopt(monster)

	return "A monster rises at (%d, %d)" % [roundi(at.x), roundi(at.y)]
