extends Node
## Checks War on its own dedicated map: that the two armies (BotManager.
## war_side, a spawn-position split — see the class doc on WarBattle) march
## at each other, that the fight ends with one side gone, that the same seed
## produces the same casualties, and that none of it grows out of proportion
## at ten thousand.
##
## Timings printed by this tool are **information, not a budget**. A long check
## run heats the laptop, and a throttled core makes every later measurement read
## high: a pure arithmetic loop touching nothing at all measures 66 ms at the
## start of a process and 219 ms after three hundred rendered frames, for
## identical work. The assertions below are loose enough to catch an algorithm
## that has gone quadratic and nothing finer than that. Real numbers come from
## tools/profile_tick.gd, in its own short process.

const SIDE_A := 0
const SIDE_B := 1
## Small and high-damage on purpose: this suite wants the fight to actually
## finish inside a check, not just start one.
const BOTS := 400
const DAMAGE := 40.0
const MAX_TICKS := 4000
const PROGRESS_EVERY := 400


func _ready() -> void:
	var failures := 0

	# war_island.tscn, not main.tscn: War is only registered on its own
	# dedicated map (EventManager.war_enabled) — see the class docs on
	# TeamWarEvent/WarBattle for why bot_class's replacement of team left
	# nothing to fight over anywhere else.
	var packed: PackedScene = load("res://scenes/war_island.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var step := GameConfig.SIMULATION_TICK_SECONDS

	print("--- the registry ---")
	print("  known events   : ", events.known())
	failures += _check("the war is registered", events.has_event(&"war"))

	print("--- two armies, split by where they spawned ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	# Arriving on this map auto-triggers a war (Main.auto_trigger_event) —
	# reset clears the record and frees it, so the fight below is a fresh,
	# known one rather than colliding with one already running.
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	var start_a := _side_alive(bots, SIDE_A)
	var start_b := _side_alive(bots, SIDE_B)
	print("  sides          : %d v %d (of %d total)" % [start_a, start_b, start_alive])
	failures += _check("every bot landed on a side (%d + %d == %d)" % [start_a, start_b, start_alive],
		start_a + start_b == start_alive)

	failures += _check("the war fired", events.trigger(&"war", {"damage": DAMAGE}))
	print("  announced      : %s" % events.last_description)
	failures += _check("a second war is refused while one is running",
		not events.trigger(&"war"))

	var war := _find_war(events)
	failures += _check("the war is in flight", war != null)
	failures += _check("it was wired to the world, for routing marchers around water",
		war._world == main.get_node("World"))

	print("--- marching orders ---")
	# One tick is enough for _ready()'s first _send_marchers() to have run.
	bots.tick(step, 0)
	events.advance(step)
	var marching := _count_state(bots, BotManager.State.MOVING)
	print("  marching       : %d of %d combatants" % [marching, start_alive])
	failures += _check("the armies set off (%d marching)" % marching, marching > 0)

	print("--- the fight ---")
	var t := 1
	## Whether combat was ever seen, not whether it happens to be visible on one
	## sampled tick — see verify_zone's own note on sampling across an event's
	## whole shape rather than at one instant chosen for convenience.
	var ever_fighting := false
	while t < MAX_TICKS and is_instance_valid(war) and not war.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		if not ever_fighting and _count_state(bots, BotManager.State.FIGHTING) > 0:
			ever_fighting = true
		if t % PROGRESS_EVERY == 0:
			print("  t=%d          : %d v %d left" % [t, _side_alive(bots, SIDE_A), _side_alive(bots, SIDE_B)])
		t += 1

	var alive_a := _side_alive(bots, SIDE_A)
	var alive_b := _side_alive(bots, SIDE_B)
	print("  reported       : %s" % events.last_description)
	print("  ended at tick  : %d (%d v %d left)" % [t, alive_a, alive_b])
	failures += _check("people actually fought (saw someone FIGHTING)", ever_fighting)
	failures += _check("casualties happened (%d v %d -> %d v %d)"
		% [start_a, start_b, alive_a, alive_b],
		alive_a < start_a or alive_b < start_b)
	failures += _check("it finished inside the tick budget", t < MAX_TICKS)
	failures += _check("one side was actually wiped out (%d v %d)" % [alive_a, alive_b],
		alive_a == 0 or alive_b == 0)
	failures += _check("it reported the outcome",
		events.last_description.contains("wiped") or events.last_description.contains("v west"))
	failures += _check("the war freed itself", _find_war(events) == null)

	print("--- bad parameters ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	for w in events.get_children():
		if w is WarBattle:
			w.free()
	failures += _check("zero damage is refused", not events.trigger(&"war", {"damage": 0.0}))
	failures += _check("negative damage is refused", not events.trigger(&"war", {"damage": -5.0}))
	failures += _check("and none of that started a war", _find_war(events) == null)

	print("--- determinism ---")
	var first := _fight_and_count(main, bots, events, step)
	var second := _fight_and_count(main, bots, events, step)
	print("  same seed      : %d | %d survivors" % [first, second])
	failures += _check("the same seed produces the same casualties", first == second)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	for w in events.get_children():
		if w is WarBattle:
			w.free()
	events.trigger(&"war", {"damage": DAMAGE})
	var combat := PackedFloat32Array()
	for t3 in 200:
		bots.tick(step, t3)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		combat.append(float(Time.get_ticks_usec() - t0))
	print("  war            : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(combat), _worst_ms(combat), combat.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the war has not gone quadratic (%.2f ms worst)" % _worst_ms(combat),
		_worst_ms(combat) < 200.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_war(events: EventManager) -> WarBattle:
	for child in events.get_children():
		if child is WarBattle and not child.is_queued_for_deletion():
			return child
	return null


func _side_alive(bots: BotManager, side_id: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.war_side[i] == side_id:
			n += 1
	return n


func _count_state(bots: BotManager, state: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.state[i] == state:
			n += 1
	return n


## A fresh island, a fresh crowd and one war carried to the end (or to the
## tick budget, whichever comes first). Returns how many were left standing.
func _fight_and_count(main: Node3D, bots: BotManager, events: EventManager, step: float) -> int:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	for w in events.get_children():
		if w is WarBattle:
			w.free()
	events.trigger(&"war", {"damage": DAMAGE})
	var t := 0
	var war := _find_war(events)
	while t < MAX_TICKS and is_instance_valid(war) and not war.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		t += 1
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
