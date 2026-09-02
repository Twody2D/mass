extends Node
## Checks the giant rhino: that it aims at a nearby herd's average
## position rather than at one bot's exact spot, that only archers and
## nearby melee hurt it, that a modest crowd brings it down, and that it
## topples and stays down once beaten.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const HERD_SIZE := 8
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
	failures += _check("the rhino is registered", events.has_event(&"rhino"))

	print("--- it charges the local herd, not one bot ---")
	# A small, tight crowd, every one of them close enough together that
	# bots_within(CHARGE_SCAN_RADIUS) finds the same group no matter which
	# one _pick_target()'s own random anchor happens to land on — the
	# result should not depend on that choice at all.
	bots.spawn(HERD_SIZE, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	failures += _check("the rhino fired", events.trigger(&"rhino", {"health": HEALTH}))
	var rhino := _find_rombophant(events)
	failures += _check("the rhino is in flight", rhino != null)

	var cluster_centre := Vector2(rhino.position.x, rhino.position.z)
	var expected := Vector2.ZERO
	for i in bots.count:
		# A few metres of deterministic per-bot spread, well inside
		# CHARGE_SCAN_RADIUS (%.0f m) but enough that no two bots share
		# exactly the same spot.
		var p := cluster_centre + Vector2(cos(float(i) * 1.7) * 3.0, sin(float(i) * 1.7) * 3.0)
		_place(bots, i, p)
		expected += p
	expected /= bots.count

	rhino._pick_target()
	print("  target         : %s (expected herd centroid ~%s)" % [rhino._target, expected])
	failures += _check("it aimed at the herd's centroid, not one bot's exact spot (%.0f m away)"
		% rhino._target.distance_to(expected), rhino._target.distance_to(expected) < 1.0)
	var on_one_bot := false
	for i in bots.count:
		if rhino._target.distance_to(Vector2(bots.pos_x[i], bots.pos_z[i])) < 0.05:
			on_one_bot = true
	failures += _check("...and specifically not sitting exactly on any single bot", not on_one_bot)

	print("--- the fight ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, BOTS)
	for w in events.get_children():
		if w is Rombophant:
			w.free()

	var start_alive := bots.alive_count
	failures += _check("the rhino fired again for the real fight",
		events.trigger(&"rhino", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	rhino = _find_rombophant(events)
	failures += _check("the rhino is in flight", rhino != null)
	failures += _check("a second rhino is refused while one is loose",
		not events.trigger(&"rhino"))

	var spawn := Vector2(rhino.position.x, rhino.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(Rombophant.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Rombophant.ATTACK_RANGE * 0.5))

	print("--- the rig ---")
	# Fourth boss on Crabylon's procedural rig (see its own class doc) —
	# this model's bone names and swing axis both matched Horsely's rather
	# than needing their own answer, confirmed by measurement, not assumed.
	# _elapsed is forced off zero directly (the same reasoning
	# verify_rhombolion.gd's own rig check uses) rather than ticking just to
	# get past a sin() zero-crossing.
	failures += _check("a Skeleton3D was found on the imported model", rhino._skeleton != null)
	var missing_legs := 0
	for leg in rhino._diagonal_a + rhino._diagonal_b:
		if leg[0] < 0 or leg[1] < 0:
			missing_legs += 1
	failures += _check("every leg bone name resolved (%d missing)" % missing_legs, missing_legs == 0)
	rhino._elapsed = 1.3
	rhino.render(1.0)
	var any_leg_posed := false
	for leg in rhino._diagonal_a + rhino._diagonal_b:
		var thigh: int = leg[0]
		if thigh >= 0 and not rhino._skeleton.get_bone_pose_rotation(thigh).is_equal_approx(Quaternion.IDENTITY):
			any_leg_posed = true
			break
	failures += _check("render() actually poses a leg bone away from rest", any_leg_posed)
	rhino._elapsed = 0.0

	var ever_hurt := false
	var t := 0
	while t < MAX_TICKS and rhino._phase != Rombophant._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if rhino._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", rhino._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported keeling over", events.last_description.contains("keels over"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_rombophant(events) == rhino)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"rhino", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"rhino", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"rhino")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  rhino          : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the rhino has not gone quadratic (%.2f ms worst)"
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


func _find_rombophant(events: EventManager) -> Rombophant:
	for child in events.get_children():
		if child is Rombophant and not child.is_queued_for_deletion():
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
