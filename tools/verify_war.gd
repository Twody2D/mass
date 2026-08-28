extends Node
## Checks Team War: that two teams actually march at each other, that only
## the two at war are touched, that the fight ends with one side gone, that
## the biggest-two auto-pick looks at who is actually left rather than just
## team index, and that none of it grows out of proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget**. A long check
## run heats the laptop, and a throttled core makes every later measurement read
## high: a pure arithmetic loop touching nothing at all measures 66 ms at the
## start of a process and 219 ms after three hundred rendered frames, for
## identical work. The assertions below are loose enough to catch an algorithm
## that has gone quadratic and nothing finer than that. Real numbers come from
## tools/profile_tick.gd, in its own short process.


## Small and high-damage on purpose: this suite wants the fight to actually
## finish inside a check, not just start one. A slow duel would make this the
## kind of compressed-duration bug that made an earlier check meaningless (see
## TODO.md) — except here the fix is to make the real event fast, since a war
## has no fixed duration to begin with.
const BOTS := 400
const TEAM_A := 0
const TEAM_B := 1
const DAMAGE := 40.0
## A war has no fixed duration: both sides are scattered uniformly across the
## whole island at spawn, not placed on opposite sides of it, so the slowest
## straggler can be a couple of hundred metres from the point everyone is
## converging on. Generous rather than tight, and progress is printed as it
## runs so a real hang is visible rather than a bare timeout.
const MAX_TICKS := 4000
const PROGRESS_EVERY := 400


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
	failures += _check("the war is registered", events.has_event(&"war"))

	print("--- two armies close in ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	# A few ticks so the crowd is walking rather than standing where it spawned.
	for t in 20:
		bots.tick(step, t)

	var start_alive := bots.alive_count
	var start_a := _team_alive(bots, TEAM_A)
	var start_b := _team_alive(bots, TEAM_B)
	var bystanders := start_alive - start_a - start_b
	print("  teams          : %d v %d (%d bystanders)" % [start_a, start_b, bystanders])

	failures += _check("the war fired",
		events.trigger(&"war", {"team_a": TEAM_A, "team_b": TEAM_B, "damage": DAMAGE}))
	print("  announced      : %s" % events.last_description)
	failures += _check("it announces both teams",
		events.last_description.contains("team %d" % TEAM_A)
			and events.last_description.contains("team %d" % TEAM_B))
	failures += _check("a second war is refused while one is running",
		not events.trigger(&"war"))

	var war := _find_war(events)
	failures += _check("the war is in flight", war != null)
	failures += _check("it was wired to the world, for routing marchers around water",
		war._world == main.get_node("World"))

	print("--- marching orders ---")
	# One tick is enough for _ready()'s first _send_marchers() to have run.
	bots.tick(step, 20)
	events.advance(step)
	var marching := _count_state_for_teams(bots, BotManager.State.MOVING)
	print("  marching       : %d of %d combatants" % [marching, start_a + start_b])
	failures += _check("the armies set off (%d marching)" % marching, marching > 0)
	failures += _check("bystanders were not drafted (%d fighting already)" % 0,
		_count_state_for(bots, TEAM_A, BotManager.State.FIGHTING)
			+ _count_state_for(bots, TEAM_B, BotManager.State.FIGHTING) == 0)

	print("--- the fight ---")
	var t := 21
	## Whether combat was ever seen, not whether it happens to be visible on one
	## sampled tick: a bot whose only nearby enemy dies in the same tick reverts
	## straight from FIGHTING to IDLE without a tick in between to be caught on,
	## so the very tick a fight is decided can show nobody fighting at all. The
	## same lesson as the compressed-duration bug in verify_zone — sample across
	## the event's actual shape, not at one instant chosen for convenience.
	var ever_fighting := false
	var midpoint_bystanders_untouched := true
	var midpoint_taken := false
	while t < MAX_TICKS and is_instance_valid(war) and not war.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		if not ever_fighting and _count_state_for_teams(bots, BotManager.State.FIGHTING) > 0:
			ever_fighting = true
		if not midpoint_taken and (_team_alive(bots, TEAM_A) < start_a
				or _team_alive(bots, TEAM_B) < start_b):
			midpoint_taken = true
			midpoint_bystanders_untouched = (start_alive - start_a - start_b) \
				== (bots.alive_count - _team_alive(bots, TEAM_A) - _team_alive(bots, TEAM_B))
		if t % PROGRESS_EVERY == 0:
			print("  t=%d          : %d v %d left" % [t, _team_alive(bots, TEAM_A), _team_alive(bots, TEAM_B)])
		t += 1

	var alive_a := _team_alive(bots, TEAM_A)
	var alive_b := _team_alive(bots, TEAM_B)
	print("  reported       : %s" % events.last_description)
	print("  ended at tick  : %d (%d v %d left)" % [t, alive_a, alive_b])
	failures += _check("people actually fought (saw someone FIGHTING)", ever_fighting)
	failures += _check("casualties happened (%d v %d -> %d v %d)"
		% [start_a, start_b, alive_a, alive_b],
		alive_a < start_a or alive_b < start_b)
	failures += _check("it finished inside the tick budget", t < MAX_TICKS)
	failures += _check("one side was actually wiped out (%d v %d)" % [alive_a, alive_b],
		alive_a == 0 or alive_b == 0)
	failures += _check("it reported the outcome", events.last_description.contains("wiped"))
	failures += _check("the war freed itself", _find_war(events) == null)

	print("--- who else it touched ---")
	failures += _check("bystanders were untouched mid-fight", midpoint_bystanders_untouched)
	var bystanders_now := bots.alive_count - alive_a - alive_b
	failures += _check("bystanders are still all there (%d of %d)" % [bystanders_now, bystanders],
		bystanders_now == bystanders)
	var stray_fighting := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.team[i] != TEAM_A and bots.team[i] != TEAM_B \
				and bots.state[i] == BotManager.State.FIGHTING:
			stray_fighting += 1
	failures += _check("nobody outside the war ever fought (%d were)" % stray_fighting,
		stray_fighting == 0)

	print("--- bad parameters ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	failures += _check("the same team twice is refused",
		not events.trigger(&"war", {"team_a": 2, "team_b": 2}))
	failures += _check("zero damage is refused",
		not events.trigger(&"war", {"team_a": 0, "team_b": 1, "damage": 0.0}))
	failures += _check("negative damage is refused",
		not events.trigger(&"war", {"team_a": 0, "team_b": 1, "damage": -5.0}))
	failures += _check("naming only one team is refused",
		not events.trigger(&"war", {"team_a": 0}))
	failures += _check("a team with nobody left is refused",
		not events.trigger(&"war", {"team_a": 0, "team_b": 999}))
	failures += _check("and none of that started a war", _find_war(events) == null)

	print("--- the biggest two, not just team 0 and 1 ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	for t2 in 20:
		bots.tick(step, t2)
	# Thin team 0 out below the others, so the auto-pick has to actually look
	# at who is left rather than defaulting to the first two indices.
	var trimmed := 0
	var target_trim := _team_alive(bots, 0) - 5
	for i in bots.count:
		if trimmed >= target_trim:
			break
		if bots.alive[i] == 1 and bots.team[i] == 0:
			bots.kill(i)
			trimmed += 1
	print("  team 0 left    : %d (of %d others each)" % [_team_alive(bots, 0), _team_alive(bots, 1)])
	failures += _check("the auto-pick fired", events.trigger(&"war"))
	print("  announced      : %s" % events.last_description)
	failures += _check("it picked two teams that are not team 0 (%s)" % events.last_description,
		not events.last_description.contains("team 0 "))

	print("--- determinism ---")
	var first := _fight_and_count(main, bots, events, step)
	var second := _fight_and_count(main, bots, events, step)
	print("  same seed      : %d | %d survivors" % [first, second])
	failures += _check("the same seed produces the same casualties", first == second)

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"war", {"team_a": TEAM_A, "team_b": TEAM_B, "damage": DAMAGE})
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


func _team_alive(bots: BotManager, team_id: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.team[i] == team_id:
			n += 1
	return n


func _count_state_for(bots: BotManager, team_id: int, state: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.team[i] == team_id and bots.state[i] == state:
			n += 1
	return n


func _count_state_for_teams(bots: BotManager, state: int) -> int:
	return _count_state_for(bots, TEAM_A, state) + _count_state_for(bots, TEAM_B, state)


## A fresh island, a fresh crowd and one war carried to the end (or to the tick
## budget, whichever comes first). Returns how many were left standing overall.
func _fight_and_count(main: Node3D, bots: BotManager, events: EventManager, step: float) -> int:
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	for t in 20:
		bots.tick(step, t)
	events.trigger(&"war", {"team_a": TEAM_A, "team_b": TEAM_B, "damage": DAMAGE})
	var t := 20
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
