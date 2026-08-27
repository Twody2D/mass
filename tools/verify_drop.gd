extends Node
## Checks Mass Supply Drop: that a crate actually draws a crowd, that more
## than one can be in flight at once (the one event here allowed to overlap
## itself), that a real crush eventually shoves somebody, that bad parameters
## are refused, and that none of it grows out of proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget**. A long check
## run heats the laptop, and a throttled core makes every later measurement read
## high: a pure arithmetic loop touching nothing at all measures 66 ms at the
## start of a process and 219 ms after three hundred rendered frames, for
## identical work. The assertions below are loose enough to catch an algorithm
## that has gone quadratic and nothing finer than that. Real numbers come from
## tools/profile_tick.gd, in its own short process.


const BOTS := 3000
## A crush needs bodies to actually converge into one small circle. Larger
## than the other suites' crowds on purpose, so the test does not depend on
## getting lucky with how a smaller sample happens to scatter.
const MAX_TICKS := 500


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var step := GameConfig.SIMULATION_TICK_SECONDS
	# Independent of the event's own stream: choosing where *this test* points
	# a crate must not perturb what the event itself would have rolled.
	var picker := RandomNumberGenerator.new()
	picker.seed = GameConfig.DEFAULT_MAP_SEED ^ 0x51ed270b

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the drop is registered", events.has_event(&"drop"))

	print("--- one crate ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	for t in 20:
		bots.tick(step, t)

	var start_alive := bots.alive_count
	var point := world.random_land_point(picker)
	failures += _check("the drop fired",
		events.trigger(&"drop", {"x": point.x, "z": point.y}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces one crate", events.last_description.contains("1 crate"))
	failures += _check("nothing has died yet", bots.alive_count == start_alive)

	var crate := _find_crate(events)
	failures += _check("it dropped a crate", crate != null)
	var scramble := _find_scrambles(events)
	failures += _check("exactly one crush is in flight (%d)" % scramble.size(), scramble.size() == 1)

	var gathering := _count_state(bots, BotManager.State.GATHERING)
	print("  gathering      : %d" % gathering)
	failures += _check("the crowd set off for it (%d gathering)" % gathering, gathering > 0)

	print("--- more than one at once ---")
	var second_point := world.random_land_point(picker)
	failures += _check("a second drop is not refused while the first is running",
		events.trigger(&"drop", {"x": second_point.x, "z": second_point.y}))
	failures += _check("both crushes are in flight (%d)" % _find_scrambles(events).size(),
		_find_scrambles(events).size() == 2)

	print("--- bad parameters ---")
	failures += _check("x without z is refused", not events.trigger(&"drop", {"x": 0.0}))
	failures += _check("z without x is refused", not events.trigger(&"drop", {"z": 0.0}))
	failures += _check("zero count is refused", not events.trigger(&"drop", {"count": 0}))
	failures += _check("a count above the cap is refused",
		not events.trigger(&"drop", {"count": 999}))
	failures += _check("none of that started a third crush",
		_find_scrambles(events).size() == 2)

	print("--- running one to the end ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	var run_point := world.random_land_point(picker)
	events.trigger(&"drop", {"x": run_point.x, "z": run_point.y})
	var ever_gathering := false
	var peak_crush := 0
	var t := 0
	var one := _find_scrambles(events)
	while t < MAX_TICKS and not one.is_empty():
		bots.tick(step, t)
		events.advance(step)
		if _count_state(bots, BotManager.State.GATHERING) > 0:
			ever_gathering = true
		peak_crush = maxi(peak_crush, bots.bots_within(run_point.x, run_point.y, 6.0).size())
		one = _find_scrambles(events)
		t += 1

	print("  ended at tick  : %d" % t)
	print("  peak crush     : %d within 6m" % peak_crush)
	print("  reported       : %s" % events.last_description)
	failures += _check("it finished inside the tick budget", t < MAX_TICKS)
	failures += _check("the crush freed itself", _find_scrambles(events).is_empty())
	failures += _check("it reported settling", events.last_description.contains("settled"))
	failures += _check("the crowd actually gathered at some point", ever_gathering)
	failures += _check("a real crush formed (%d peak, need 8)" % peak_crush, peak_crush >= 8)
	failures += _check("it reported at least one shove",
		not events.last_description.contains("0 shoved"))

	print("--- determinism ---")
	var first := _run_and_checksum(main, bots, events, world, step, run_point)
	var second := _run_and_checksum(main, bots, events, world, step, run_point)
	print("  same seed      : %.1f | %.1f total health" % [first, second])
	failures += _check("the same seed does the same damage", is_equal_approx(first, second))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	var big_point := world.random_land_point(picker)
	events.trigger(&"drop", {"x": big_point.x, "z": big_point.y, "count": 1})
	events.trigger(&"drop", {"count": 3})
	var sweep := PackedFloat32Array()
	for t2 in 300:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		sweep.append(float(Time.get_ticks_usec() - t0))
	print("  drop           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(sweep), _worst_ms(sweep), sweep.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the drop has not gone quadratic (%.2f ms worst)" % _worst_ms(sweep),
		_worst_ms(sweep) < 200.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_crate(events: EventManager) -> CrateDrop:
	for child in events.get_children():
		if child is CrateDrop and not child.is_queued_for_deletion():
			return child
	return null


func _find_scrambles(events: EventManager) -> Array:
	var found := []
	for child in events.get_children():
		if child is SupplyScramble and not child.is_queued_for_deletion():
			found.append(child)
	return found


func _count_state(bots: BotManager, state: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.state[i] == state:
			n += 1
	return n


func _health_checksum(bots: BotManager) -> float:
	var total := 0.0
	for i in bots.count:
		total += bots.health[i]
	return total


## A fresh island, a fresh crowd and one drop carried to the end. Returns the
## total health left standing, which moves with every shove that connects,
## not just with a kill.
func _run_and_checksum(main: Node3D, bots: BotManager, events: EventManager,
		world: World, step: float, point: Vector2) -> float:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	events.trigger(&"drop", {"x": point.x, "z": point.y})
	var t := 0
	var one := _find_scrambles(events)
	while t < MAX_TICKS and not one.is_empty():
		bots.tick(step, t)
		events.advance(step)
		one = _find_scrambles(events)
		t += 1
	return _health_checksum(bots)


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
