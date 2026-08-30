extends Node
## Checks the flood: that the sea actually rises, that the island shrinks with
## it, that whoever it reaches drowns and whoever it is about to reach runs
## uphill, and that none of it grows out of proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget**. A long check
## run heats the laptop, and a throttled core makes every later measurement read
## high: a pure arithmetic loop touching nothing at all measures 66 ms at the
## start of a process and 219 ms after three hundred rendered frames, for
## identical work. The assertions below are loose enough to catch an algorithm
## that has gone quadratic and nothing finer than that. Real numbers come from
## tools/profile_tick.gd, in its own short process.


const BOTS := 2000
## Short and steep, so the whole thing fits in a test rather than half a minute.
## Raised twice after the volcano landform (18 -> 26 -> 45): a fixed rise
## drowns a fixed band of low ground regardless of the mountain, but
## random_land_point() spawns uniformly over *all* land, and the volcano —
## now the island's centrepiece, occupying the most crowded part of the map
## rather than a corner of it — keeps adding land nowhere near that band. The
## same rise drowning a shrinking share of an unchanged crowd is not flooding
## getting weaker, it is the island having more safe high ground than before.
const RISE := 45.0
const SECONDS := 4.0
## Sampling grid for "how much land is left". Coarse on purpose: this is a
## fraction, not a survey.
const SAMPLES := 64


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var step := GameConfig.SIMULATION_TICK_SECONDS

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the flood is registered", events.has_event(&"flood"))

	print("--- the rise ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	# A few ticks so the crowd is walking rather than standing where it spawned.
	for t in 20:
		bots.tick(step, t)

	var start_level := world.water_level
	var start_land := _land_share(world)
	var start_alive := bots.alive_count
	var start_mean := _mean_height(bots)
	print("  water          : %.2f m" % start_level)
	print("  land           : %.1f%%" % (start_land * 100.0))
	print("  alive          : %d, standing at %.2f m on average" % [start_alive, start_mean])

	failures += _check("the flood fired",
		events.trigger(&"flood", {"rise": RISE, "seconds": SECONDS}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces the rise", events.last_description.contains("rising"))
	failures += _check("nothing has moved yet", world.water_level == start_level)
	failures += _check("and nobody has drowned yet", bots.alive_count == start_alive)

	failures += _check("a second flood is refused while one is running",
		not events.trigger(&"flood"))

	# Both clocks, the way Main drives them: the crowd has to be moving or
	# nobody ever runs anywhere.
	var ticks := int(SECONDS / step) + 4
	var midpoint_running := 0
	var midpoint_uphill := 0.0
	for t in ticks:
		bots.tick(step, t)
		events.advance(step)
		if t == ticks / 2:
			midpoint_running = _count_state(bots, BotManager.State.FLEEING)
			midpoint_uphill = _uphill_share(world, bots)

	print("  water          : %.2f m" % world.water_level)
	print("  land           : %.1f%%" % (_land_share(world) * 100.0))
	print("  alive          : %d, standing at %.2f m on average"
		% [bots.alive_count, _mean_height(bots)])
	print("  reported       : %s" % events.last_description)

	failures += _check("the sea reached the level it said (%.2f m)" % world.water_level,
		absf(world.water_level - (start_level + RISE)) < 0.01)
	failures += _check("the ocean plane went with it",
		absf(_ocean_height(world) - world.water_level) < 0.01)
	failures += _check("the island shrank (%.1f%% -> %.1f%%)"
		% [start_land * 100.0, _land_share(world) * 100.0],
		_land_share(world) < start_land)
	failures += _check("people drowned (%d)" % (start_alive - bots.alive_count),
		bots.alive_count < start_alive)
	failures += _check("it reported settling", events.last_description.contains("settled"))

	print("--- who is left ---")
	var below := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.pos_y[i] <= world.water_level:
			below += 1
	failures += _check("nobody alive is under the sea (%d are)" % below, below == 0)

	var flagged := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			flagged += 1
	failures += _check("alive_count matches the flags", flagged == bots.alive_count)

	print("  ran at midpoint: %d" % midpoint_running)
	print("  running uphill : %.1f%%" % (midpoint_uphill * 100.0))
	failures += _check("the coast ran for it (%d)" % midpoint_running, midpoint_running > 0)
	# The whole point of measuring the slope instead of guessing at the map
	# centre. Not every runner: a bot already climbing keeps its old target, and
	# the ground under it can rise past the target while it walks.
	failures += _check("they run uphill, not into the sea (%.1f%%)" % (midpoint_uphill * 100.0),
		midpoint_uphill > 0.9)
	failures += _check("the survivors ended up higher (%.2f m -> %.2f m)"
		% [start_mean, _mean_height(bots)], _mean_height(bots) > start_mean)

	var tides := 0
	for child in events.get_children():
		if child is FloodTide and not child.is_queued_for_deletion():
			tides += 1
	failures += _check("the tide freed itself (%d left)" % tides, tides == 0)

	print("--- bad parameters ---")
	failures += _check("a zero rise is refused", not events.trigger(&"flood", {"rise": 0.0}))
	failures += _check("a negative rise is refused", not events.trigger(&"flood", {"rise": -5.0}))
	failures += _check("a zero duration is refused",
		not events.trigger(&"flood", {"seconds": 0.0}))

	print("--- putting it back ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	failures += _check("a restart puts the sea back",
		absf(world.water_level - GameConfig.WATER_LEVEL) < 0.0001)
	failures += _check("and the plane with it",
		absf(_ocean_height(world) - GameConfig.WATER_LEVEL) < 0.0001)
	failures += _check("the island is whole again",
		absf(_land_share(world) - start_land) < 0.0001)
	failures += _check("and everybody is back", bots.alive_count == BOTS)

	print("--- determinism ---")
	var first := _drown_and_count(main, bots, events, step, ticks)
	var second := _drown_and_count(main, bots, events, step, ticks)
	print("  same seed      : %d | %d survivors" % [first, second])
	failures += _check("the same seed drowns the same people", first == second)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"flood", {"rise": RISE, "seconds": SECONDS})
	var tide := PackedFloat32Array()
	for t in ticks:
		bots.tick(step, t)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		tide.append(float(Time.get_ticks_usec() - t0))
	print("  tide           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(tide), _worst_ms(tide), tide.size()])
	print("  drowned        : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the tide has not gone quadratic (%.2f ms worst)" % _worst_ms(tide),
		_worst_ms(tide) < 200.0)
	failures += _check("it drowned a serious number of them",
		10000 - bots.alive_count > 1000)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Share of a coarse grid over the map that a bot could stand on right now.
func _land_share(world: World) -> float:
	var half := GameConfig.MAP_SIZE * 0.5
	var stepped := GameConfig.MAP_SIZE / float(SAMPLES - 1)
	var land := 0
	for gz in SAMPLES:
		for gx in SAMPLES:
			if world.is_walkable(-half + gx * stepped, -half + gz * stepped):
				land += 1
	return float(land) / float(SAMPLES * SAMPLES)


func _ocean_height(world: World) -> float:
	var ocean: Node3D = world.get_node_or_null("Ocean")
	if ocean == null:
		push_error("verify_flood: the world has no Ocean node.")
		return NAN
	return ocean.position.y


func _mean_height(bots: BotManager) -> float:
	var total := 0.0
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			total += bots.pos_y[i]
			n += 1
	return total / float(n) if n > 0 else 0.0


## Share of the bots currently running whose destination is on higher ground
## than where they are standing.
func _uphill_share(world: World, bots: BotManager) -> float:
	var up := 0
	var total := 0
	for i in bots.count:
		if bots.alive[i] == 0 or bots.state[i] != BotManager.State.FLEEING:
			continue
		total += 1
		if world.get_height(bots.target_x[i], bots.target_z[i]) > bots.pos_y[i]:
			up += 1
	return float(up) / float(total) if total > 0 else 0.0


func _count_state(bots: BotManager, state: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.state[i] == state:
			n += 1
	return n


## A fresh island, a fresh crowd and one flood carried to the end. Returns how
## many were left standing.
func _drown_and_count(main: Node3D, bots: BotManager, events: EventManager,
		step: float, ticks: int) -> int:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	events.trigger(&"flood", {"rise": RISE, "seconds": SECONDS})
	for t in ticks:
		bots.tick(step, t)
		events.advance(step)
	return bots.alive_count



## Median of a set of microsecond samples, in milliseconds.
##
## Never the mean and never the worst. The same deterministic tick measures 15 ms
## on one run of this tool and 43 ms on the next, with the crowd in a
## bit-identical state, because the machine has other things to do. A worst-case
## assertion measures the operating system; a median measures the code.
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
