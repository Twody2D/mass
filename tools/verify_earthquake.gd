extends Node
## Checks the earthquake: that it registers, that whoever stood exactly
## where the ground opens falls in, that the rift left behind is a real,
## permanent obstacle rather than only a mark, that it can be triggered
## again without breaking, and that none of it grows out of proportion at
## ten thousand.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 500


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the earthquake is registered", events.has_event(&"earthquake"))

	print("--- World's rift barrier, in isolation ---")
	# Independent of the event's own random path: the mechanism the crowd
	# actually splits on, checked directly against fixed geometry rather
	# than a randomly placed one.
	failures += _check("a fresh island has an open point nearby",
		world.is_walkable(0.0, 0.0))
	world.add_rift_barrier(Vector2(-20.0, 0.0), Vector2(20.0, 0.0), 5.0)
	failures += _check("the centre of a barrier is not walkable",
		not world.is_walkable(0.0, 0.0))
	failures += _check("a point past the segment's end but still within the width is blocked",
		not world.is_walkable(-25.0, 0.0))
	failures += _check("a point well clear of the barrier is unaffected",
		world.is_walkable(0.0, 50.0))
	world.generate(GameConfig.DEFAULT_MAP_SEED)
	failures += _check("regenerating the island clears every barrier",
		world.is_walkable(0.0, 0.0))

	print("--- it opens ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	# The victim's own position becomes the first rift's forced starting
	# point (see EarthquakeEvent.fire()'s "x"/"z" override) — distance zero
	# from the very first vertex of the very first segment, so it is caught
	# regardless of which direction the rest of the jagged path then takes.
	var victim := 0
	var at := Vector2(bots.pos_x[victim], bots.pos_z[victim])
	var start_alive := bots.alive_count

	failures += _check("the earthquake fired",
		events.trigger(&"earthquake", {"x": at.x, "z": at.y}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it reports rifts and a death toll",
		events.last_description.contains("rifts") and events.last_description.contains("killed"))
	failures += _check("the bot standing at the epicentre fell in", bots.alive[victim] == 0)
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)

	print("--- the rift is left behind ---")
	failures += _check("the epicentre itself is no longer walkable",
		not world.is_walkable(at.x, at.y))

	var fissures := 0
	for child in events.get_children():
		if child is Fissure:
			fissures += 1
	failures += _check("one fissure adopted per rift (%d)" % fissures,
		fissures == EarthquakeEvent.RIFT_COUNT)

	failures += _check("the fissure stays adopted, the same way a crater does", fissures > 0)
	events.advance(GameConfig.SIMULATION_TICK_SECONDS)
	var fissures_after := 0
	for child in events.get_children():
		if child is Fissure:
			fissures_after += 1
	failures += _check("and is still there a tick later", fissures_after == fissures)

	print("--- bad parameters ---")
	failures += _check("zero rifts is refused", not events.trigger(&"earthquake", {"rifts": 0}))

	print("--- triggering again adds more, rather than breaking ---")
	var before := bots.alive_count
	failures += _check("a second earthquake is accepted, not refused",
		events.trigger(&"earthquake"))
	failures += _check("it can kill more on top of the first", bots.alive_count <= before)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	var t0 := Time.get_ticks_usec()
	events.trigger(&"earthquake")
	var trigger_cost := (Time.get_ticks_usec() - t0) / 1000.0
	print("  trigger        : %.3f ms for %d bots" % [trigger_cost, 10000])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("triggering it has not gone quadratic (%.2f ms)" % trigger_cost,
		trigger_cost < 200.0)

	var step := GameConfig.SIMULATION_TICK_SECONDS
	var tick_cost := PackedFloat32Array()
	for t in 30:
		var t1 := Time.get_ticks_usec()
		bots.tick(step, t)
		events.advance(step)
		tick_cost.append(float(Time.get_ticks_usec() - t1))
	print("  tick with rifts standing: %.3f ms median over %d ticks"
		% [_median_ms(tick_cost), tick_cost.size()])
	failures += _check("the rift barriers add nothing noticeable to the per-tick cost (%.2f ms)"
		% _median_ms(tick_cost), _median_ms(tick_cost) < 50.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _median_ms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	return sorted[middle] / 1000.0


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
