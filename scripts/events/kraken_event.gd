class_name KrakenEvent
extends WorldEvent
## A giant surfaces along the coast until archers drive it back under.
##
## TODO.md item 51: "the same giant as Monster, but at the water's edge,
## reaching tentacles for whoever stands close to the shore." Owns no state
## itself — triggering it hands a Kraken to the event manager, and the
## kraken is what patrols, drags under and sinks on the simulation clock.

func id() -> StringName:
	return &"kraken"


## params: "x"/"z" to place it, "health" for how much it takes to sink it.
## All optional, so trigger("kraken") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var at: Vector2
	if params.has("x") and params.has("z"):
		at = Vector2(float(params["x"]), float(params["z"]))
	else:
		at = world.random_coast_point(rng)

	var health := float(params.get("health", Kraken.MAX_HEALTH))
	if health <= 0.0:
		push_error("KrakenEvent: health must be positive, got %f." % health)
		return ""

	# Two krakens would each be dragging bots under and taking damage
	# independently — the same reasoning MonsterEvent already refuses a
	# second giant for.
	for child in events.get_children():
		if child is Kraken and not child.is_queued_for_deletion():
			push_error("KrakenEvent: a kraken is already loose.")
			return ""

	var kraken := Kraken.start(world, events.bots, at, health, rng,
		func(line: String) -> void: events.report(&"kraken", line),
		func(shake_at: Vector3, strength: float) -> void:
			events.shake(shake_at, Kraken.ATTACK_RANGE, strength))
	if kraken == null:
		return ""
	events.adopt(kraken)

	return "A kraken surfaces at (%d, %d)" % [roundi(at.x), roundi(at.y)]
