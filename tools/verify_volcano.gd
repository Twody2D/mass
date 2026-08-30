extends Node
## Checks the volcano: that it erupts at a real summit, that the burst and
## the lava pools actually appear, that the lava kills whoever it reaches and
## leaves everyone else alone, that the pools outlive the eruption the same
## way a crater outlives a meteor, and that none of it grows out of
## proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 2000
## Short and steep, so the whole thing fits in a test rather than forty
## seconds, and close enough together that a 2000-bot crowd has people near
## more than one vent.
const VENTS := 3
const RADIUS := 30.0
const SECONDS := 4.0


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var step := GameConfig.SIMULATION_TICK_SECONDS

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the volcano is registered", events.has_event(&"volcano"))

	print("--- the eruption ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	# A few ticks so the crowd is walking rather than standing where it spawned.
	for t in 20:
		bots.tick(step, t)

	var start_alive := bots.alive_count
	# No "x"/"z": letting the event pick its own summit is what guarantees one
	# on land, the same reasoning SafeZoneEvent's _high_ground() search has.
	failures += _check("the volcano fired",
		events.trigger(&"volcano", {"vents": VENTS, "radius": RADIUS, "seconds": SECONDS}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces the vents", events.last_description.contains("vents"))
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var eruption := _find_eruption(events)
	failures += _check("the eruption is in flight", eruption != null)

	var pools := _find_pools(events)
	print("  pools          : %d" % pools.size())
	failures += _check("one lava pool per vent", pools.size() == VENTS)
	for pool in pools:
		failures += _check("a fresh pool starts with no radius", pool.radius() == 0.0)

	var bursts := 0
	for child in events.get_children():
		if child is GroundEjecta:
			bursts += 1
	failures += _check("one ground ejecta burst per vent", bursts == VENTS)

	failures += _check("a second eruption is refused while one is running",
		not events.trigger(&"volcano"))

	print("--- the spread ---")
	var ticks := int(SECONDS / step) + 4
	for t in ticks:
		bots.tick(step, t)
		events.advance(step)

	print("  reported       : %s" % events.last_description)
	failures += _check("it reported settling", events.last_description.contains("settled"))
	failures += _check("people died in the lava (%d)" % (start_alive - bots.alive_count),
		bots.alive_count < start_alive)
	failures += _check("but not everyone (%d of %d left)" % [bots.alive_count, start_alive],
		bots.alive_count > 0)

	print("--- who is left ---")
	var flagged := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			flagged += 1
	failures += _check("alive_count matches the flags", flagged == bots.alive_count)

	var still_in_lava := 0
	for i in bots.count:
		if bots.alive[i] == 0:
			continue
		for pool in pools:
			if Vector2(bots.pos_x[i], bots.pos_z[i]).distance_to(
					Vector2(pool.position.x, pool.position.z)) <= pool.radius():
				still_in_lava += 1
				break
	failures += _check("nobody alive is standing inside a pool (%d are)" % still_in_lava,
		still_in_lava == 0)

	for pool in pools:
		failures += _check("a pool grew to the radius it was told (%.1f m)" % pool.radius(),
			absf(pool.radius() - RADIUS) < 1.0)

	failures += _check("the eruption freed itself", _find_eruption(events) == null)
	failures += _check("the pools stayed behind, the way a crater outlives a meteor",
		_find_pools(events).size() == VENTS)

	print("--- bad parameters ---")
	failures += _check("zero vents is refused", not events.trigger(&"volcano", {"vents": 0}))
	failures += _check("a zero radius is refused", not events.trigger(&"volcano", {"radius": 0.0}))
	failures += _check("a zero duration is refused",
		not events.trigger(&"volcano", {"seconds": 0.0}))

	print("--- determinism ---")
	var first := _erupt_and_count(main, bots, events, step, ticks)
	var second := _erupt_and_count(main, bots, events, step, ticks)
	print("  same seed      : %d | %d survivors" % [first, second])
	failures += _check("the same seed burns the same people", first == second)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"volcano", {"vents": VENTS, "radius": RADIUS, "seconds": SECONDS})
	var eruption_cost := PackedFloat32Array()
	for t in ticks:
		bots.tick(step, t)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		eruption_cost.append(float(Time.get_ticks_usec() - t0))
	print("  eruption       : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(eruption_cost), _worst_ms(eruption_cost), eruption_cost.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the eruption has not gone quadratic (%.2f ms worst)"
		% _worst_ms(eruption_cost), _worst_ms(eruption_cost) < 200.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_eruption(events: EventManager) -> VolcanoEruption:
	for child in events.get_children():
		if child is VolcanoEruption and not child.is_queued_for_deletion():
			return child
	return null


func _find_pools(events: EventManager) -> Array[LavaPool]:
	var pools: Array[LavaPool] = []
	for child in events.get_children():
		if child is LavaPool:
			pools.append(child)
	return pools


## A fresh island, a fresh crowd and one eruption carried to the end. Returns
## how many were left standing.
func _erupt_and_count(main: Node3D, bots: BotManager, events: EventManager,
		step: float, ticks: int) -> int:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	events.trigger(&"volcano", {"vents": VENTS, "radius": RADIUS, "seconds": SECONDS})
	for t in ticks:
		bots.tick(step, t)
		events.advance(step)
	return bots.alive_count


## Median of a set of microsecond samples, in milliseconds. Never the mean and
## never the worst — see verify_flood.gd's own note on why.
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
