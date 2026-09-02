extends Node
## Checks the earthquake: that it registers, that whoever stood exactly
## where the first rift opens falls in, that the rift left behind is a real,
## permanent obstacle rather than only a mark, that it now actually carves
## the ground lower rather than just decorating it, that it keeps tearing
## fresh rifts open on its own for DURATION seconds and then stops existing
## (without undoing anything it already did), that it can be triggered again
## without breaking, and that none of it grows out of proportion at ten
## thousand.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 500
const STEP := 0.05  # keep in sync with GameConfig.SIMULATION_TICK_SECONDS


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

	print("--- World's real carve, in isolation ---")
	var flat_point := Vector2(0.0, 0.0)
	var far_point := Vector2(0.0, 200.0)
	var height_before := world.get_height(flat_point.x, flat_point.y)
	var far_before := world.get_height(far_point.x, far_point.y)
	world.carve_rift(PackedVector2Array([Vector2(-20.0, 0.0), Vector2(20.0, 0.0)]), 5.0, 8.0)
	var height_after := world.get_height(flat_point.x, flat_point.y)
	failures += _check("carve_rift actually lowers the real terrain (%.2f -> %.2f)"
		% [height_before, height_after], height_after < height_before - 1.0)
	failures += _check("a point well clear of the carve is unaffected",
		absf(world.get_height(far_point.x, far_point.y) - far_before) < 0.001)
	world.generate(GameConfig.DEFAULT_MAP_SEED)
	failures += _check("regenerating the island restores the original height",
		absf(world.get_height(flat_point.x, flat_point.y) - height_before) < 0.001)

	print("--- it opens ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	# The victim's own position becomes the first rift's forced starting
	# point (see EarthquakeEvent.fire()'s "x"/"z" override) — distance zero
	# from the very first vertex of the very first segment, so it is caught
	# regardless of which direction the rest of the jagged path then takes.
	var victim := 0
	var at := Vector2(bots.pos_x[victim], bots.pos_z[victim])
	var epicentre_height_before := world.get_height(at.x, at.y)
	var start_alive := bots.alive_count

	failures += _check("the earthquake fired",
		events.trigger(&"earthquake", {"x": at.x, "z": at.y}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it reports that the ground keeps tearing",
		events.last_description.contains("tearing"))
	failures += _check("the bot standing at the epicentre fell in", bots.alive[victim] == 0)
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)

	print("--- the first rift is a real pit, not a mark ---")
	failures += _check("the epicentre itself is no longer walkable",
		not world.is_walkable(at.x, at.y))
	var epicentre_height_after := world.get_height(at.x, at.y)
	# A smaller margin than the isolated carve test above: a bot can legally
	# spawn as close as SPAWN_MIN_HEIGHT (0.6 m) to the waterline, where the
	# floor clamp eats into how much of CARVE_DEPTH actually shows.
	failures += _check("and the ground there is actually carved lower (%.2f -> %.2f)"
		% [epicentre_height_before, epicentre_height_after],
		epicentre_height_after < epicentre_height_before - 0.3)

	var quake := _find_quake(events)
	failures += _check("the quake is in flight, not a one-shot", quake != null)

	var fissures := _count_fissures(events)
	failures += _check("one fissure adopted by the first strike (%d)" % fissures, fissures == 1)

	print("--- it keeps tearing on its own ---")
	var step_count := int(Earthquake.STRIKE_INTERVAL_SECONDS / STEP) + 5
	for t in step_count:
		bots.tick(STEP, t)
		events.advance(STEP)
	var fissures_after_one_interval := _count_fissures(events)
	failures += _check("a second strike opened a second rift (%d fissures)"
		% fissures_after_one_interval, fissures_after_one_interval == 2)
	failures += _check("the first rift is still there, not replaced",
		not world.is_walkable(at.x, at.y))

	print("--- and then stops existing, without undoing anything ---")
	var remaining_ticks := int(Earthquake.DURATION / STEP) + 10 - step_count
	for t in remaining_ticks:
		bots.tick(STEP, step_count + t)
		events.advance(STEP)
	failures += _check("the quake has removed itself after its own duration",
		_find_quake(events) == null)
	failures += _check("but the first rift is still an obstacle",
		not world.is_walkable(at.x, at.y))
	failures += _check("and the ground is still carved there",
		world.get_height(at.x, at.y) < epicentre_height_before - 0.3)
	var final_fissures := _count_fissures(events)
	failures += _check("every fissure it tore stayed behind (%d)" % final_fissures,
		final_fissures >= fissures_after_one_interval)

	print("--- triggering again adds more, rather than breaking ---")
	var before := bots.alive_count
	failures += _check("a second, overlapping earthquake is accepted, not refused",
		events.trigger(&"earthquake"))
	failures += _check("it can kill more on top of the first", bots.alive_count <= before)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	var t0 := Time.get_ticks_usec()
	events.trigger(&"earthquake")
	var trigger_cost := (Time.get_ticks_usec() - t0) / 1000.0
	print("  trigger (first strike + one full terrain rebuild): %.3f ms for %d bots"
		% [trigger_cost, 10000])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("triggering it has not gone quadratic (%.2f ms)" % trigger_cost,
		trigger_cost < 500.0)

	var tick_cost := PackedFloat32Array()
	# Long enough to cross several STRIKE_INTERVAL_SECONDS boundaries, so the
	# worst tick sampled here is one that pays for a full terrain rebuild at
	# ten thousand, not just an ordinary tick next to standing rift barriers.
	var strike_ticks := int(Earthquake.STRIKE_INTERVAL_SECONDS / STEP) * 3
	for t in strike_ticks:
		var t1 := Time.get_ticks_usec()
		bots.tick(STEP, t)
		events.advance(STEP)
		tick_cost.append(float(Time.get_ticks_usec() - t1))
	print("  tick with rifts standing (incl. strike ticks): %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(tick_cost), _worst_ms(tick_cost), tick_cost.size()])
	failures += _check("no single tick has gone quadratic (%.2f ms worst)" % _worst_ms(tick_cost),
		_worst_ms(tick_cost) < 500.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_quake(events: EventManager) -> Earthquake:
	for child in events.in_flight():
		if child is Earthquake:
			return child
	return null


func _count_fissures(events: EventManager) -> int:
	var count := 0
	for child in events.get_children():
		if child is Fissure:
			count += 1
	return count


func _median_ms(samples: PackedFloat32Array) -> float:
	if samples.is_empty():
		return 0.0
	var sorted := samples.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	return sorted[middle] / 1000.0


func _worst_ms(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for v in samples:
		top = maxf(top, v)
	return top / 1000.0


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
