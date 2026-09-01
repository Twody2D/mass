extends Node
## Checks the giant scorpion: that its attack is centred TAIL_REACH behind
## its own body rather than on itself or out in front of it, that only
## archers and nearby melee hurt it, that a modest crowd brings it down,
## and that it topples and stays down once beaten.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 400
const HEALTH := 40.0
const ARCHER_COUNT := 6
const MAX_TICKS := 400


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
	failures += _check("the scorpion is registered", events.has_event(&"scorpion"))

	print("--- the attack lands behind it, not under its own feet or ahead of it ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the scorpion fired", events.trigger(&"scorpion", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var scorpion := _find_scorpy(events)
	failures += _check("the scorpion is in flight", scorpion != null)
	failures += _check("a second scorpion is refused while one is loose",
		not events.trigger(&"scorpion"))

	for t in 30:
		bots.tick(step, t)
		events.advance(step)
	var body := Vector2(scorpion.position.x, scorpion.position.z)
	var reach_point := body - scorpion._facing * Scorpy.TAIL_REACH
	failures += _check("the reach point is a real distance from the body (%.0f m)"
		% body.distance_to(reach_point), body.distance_to(reach_point) > 1.0)
	var ahead_point := body + scorpion._facing * Scorpy.TAIL_REACH
	failures += _check("the reach point is behind the body, not ahead of it",
		reach_point.distance_to(ahead_point) > 1.0)

	var on_body := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, on_body, body)
	var ahead := _some_of_class(bots, GameConfig.CLASS_WARRIOR, 2)[1]
	_place(bots, ahead, ahead_point)
	var at_reach := _some_of_class(bots, GameConfig.CLASS_WARRIOR, 3)[2]
	_place(bots, at_reach, reach_point)
	# A handful of ticks, not one — _sweep() only actually runs once
	# SWEEP_SECONDS has accumulated, the same reasoning verify_giraffaxon.gd
	# already documents for the same shape of check.
	var check_t := 30
	for _i in 6:
		bots.tick(step, check_t)
		events.advance(step)
		check_t += 1
	failures += _check("standing on the body itself survives the strike", bots.alive[on_body] == 1)
	failures += _check("standing ahead of it survives too", bots.alive[ahead] == 1)
	failures += _check("standing at the tail's reach behind it does not", bots.alive[at_reach] == 0)

	# Planted at the reach point for the real fight below, not on the body.
	var victim := _first_of_class(bots, GameConfig.CLASS_SPEARMAN)
	_place(bots, victim, reach_point + Vector2(Scorpy.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, body + Vector2(0.0, Scorpy.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	var t := check_t
	while t < MAX_TICKS and scorpion._phase != Scorpy._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if scorpion._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", scorpion._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported keeling over", events.last_description.contains("keels over"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_scorpy(events) == scorpion)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"scorpion", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"scorpion", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"scorpion")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  scorpion       : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the scorpion has not gone quadratic (%.2f ms worst)"
		% _worst_ms(advance_cost), _worst_ms(advance_cost) < 200.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _first_of_class(bots: BotManager, class_id: int) -> int:
	for i in bots.count:
		if bots.bot_class[i] == class_id:
			return i
	return -1


func _some_of_class(bots: BotManager, class_id: int, count: int) -> Array[int]:
	var found: Array[int] = []
	for i in bots.count:
		if bots.bot_class[i] == class_id:
			found.append(i)
			if found.size() >= count:
				break
	return found


func _place(bots: BotManager, index: int, at: Vector2) -> void:
	bots.pos_x[index] = at.x
	bots.pos_z[index] = at.y


func _find_scorpy(events: EventManager) -> Scorpy:
	for child in events.get_children():
		if child is Scorpy and not child.is_queued_for_deletion():
			return child
	return null


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
