extends Node
## Checks the giant raptor: that it lunges (moves faster once close to its
## target than while still closing the distance), that only archers and
## nearby melee hurt it, that a modest crowd brings it down, and that it
## falls and stays down once beaten.
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
	failures += _check("the raptor is registered", events.has_event(&"raptor"))

	print("--- it lunges once close ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the raptor fired", events.trigger(&"raptor", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var raptor := _find_raptor(events)
	failures += _check("the raptor is in flight", raptor != null)
	failures += _check("a second raptor is refused while one is loose",
		not events.trigger(&"raptor"))

	# One warm-up tick first: _retarget_timer starts at 0.0, so the very
	# first advance() always calls _pick_target() regardless of what
	# _target already holds — any override set before this tick would just
	# be discarded. After this the timer is a fresh RETARGET_SECONDS, long
	# enough to hold whatever _target is set to below for the two ticks
	# that actually matter to this test.
	bots.tick(step, 0)
	events.advance(step)

	# Far from its target: one tick should cover only SPEED * step.
	var far_before := Vector2(raptor.position.x, raptor.position.z)
	raptor._target = far_before + Vector2(1000.0, 0.0)
	bots.tick(step, 1)
	events.advance(step)
	var far_moved := far_before.distance_to(Vector2(raptor.position.x, raptor.position.z))

	# Placed just inside LUNGE_RANGE of its own target (but outside
	# ARRIVAL_RADIUS, so this does not itself trigger a fresh
	# _pick_target()): the same tick should now cover noticeably more
	# ground.
	var near_before := Vector2(raptor.position.x, raptor.position.z)
	raptor._target = near_before + Vector2(Raptorous.LUNGE_RANGE * 0.5, 0.0)
	bots.tick(step, 2)
	events.advance(step)
	var near_moved := near_before.distance_to(Vector2(raptor.position.x, raptor.position.z))

	print("  far step       : %.3f m | near (lunging) step : %.3f m" % [far_moved, near_moved])
	failures += _check("it covers more ground per tick once inside LUNGE_RANGE",
		near_moved > far_moved * 1.5)

	print("--- the rig ---")
	# Sixth boss on Crabylon's procedural rig, and the first bipedal one
	# (see its own class doc) — a plain two-way alternation, not a grouped
	# gait, since there are only two legs to split. _elapsed is already at
	# 3 ticks from the lunge check above, off a sin() zero-crossing.
	failures += _check("a Skeleton3D was found on the imported model", raptor._skeleton != null)
	failures += _check("both leg bone chains resolved",
		raptor._leg_l[0] >= 0 and raptor._leg_l[1] >= 0
		and raptor._leg_r[0] >= 0 and raptor._leg_r[1] >= 0)
	raptor.render(1.0)
	var l_posed := not raptor._skeleton.get_bone_pose_rotation(raptor._leg_l[0]).is_equal_approx(Quaternion.IDENTITY)
	failures += _check("render() actually poses a leg bone away from rest", l_posed)

	# Planted at the spot it is currently standing on.
	var spawn := Vector2(raptor.position.x, raptor.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(Raptorous.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Raptorous.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	var t := 3
	while t < MAX_TICKS and raptor._phase != Raptorous._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if raptor._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", raptor._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported falling", events.last_description.contains("stumbles and falls"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_raptor(events) == raptor)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"raptor", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"raptor", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"raptor")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  raptor         : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the raptor has not gone quadratic (%.2f ms worst)"
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


func _find_raptor(events: EventManager) -> Raptorous:
	for child in events.get_children():
		if child is Raptorous and not child.is_queued_for_deletion():
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
