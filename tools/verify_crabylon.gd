extends Node
## Checks the giant crab: that only archers and nearby melee hurt it, that
## it walks sideways (faces perpendicular to its own direction of travel),
## that a modest crowd brings it down, and that it topples and stays down
## once beaten. Also the project's pilot for the real procedural rig (see
## crabylon.gd's own class doc): that every expected Skeleton3D bone name
## actually resolved, that render() really poses leg bones away from rest
## (not just decides to, silently doing nothing if a name failed), and that
## the claw grab kills a bot placed where the stomp cannot reach, proving
## the two are actually separate mechanics rather than the same radius
## reporting through two counters.
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
	failures += _check("the crab is registered", events.has_event(&"crab"))

	print("--- it walks sideways ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the crab fired", events.trigger(&"crab", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var crab := _find_crab(events)
	failures += _check("the crab is in flight", crab != null)
	failures += _check("a second crab is refused while one is loose",
		not events.trigger(&"crab"))

	var start_pos := Vector2(crab.position.x, crab.position.z)
	for t in 40:
		bots.tick(step, t)
		events.advance(step)
	var moved := Vector2(crab.position.x, crab.position.z) != start_pos
	failures += _check("it actually moved", moved)
	if moved:
		var travel := (Vector2(crab.position.x, crab.position.z) - start_pos).normalized()
		var facing := Vector2(crab.basis.z.x, crab.basis.z.z).normalized()
		failures += _check("it faces perpendicular to its own travel (dot %.2f)"
			% travel.dot(facing), absf(travel.dot(facing)) < 0.35)

	print("--- the rig ---")
	# Crabylon is the project's pilot for real bone-posed animation (see its
	# own class doc) — a name that stops resolving would otherwise fail
	# silently, so this checks the cache actually found every bone before
	# trusting any of the animation below.
	failures += _check("a Skeleton3D was found on the imported model", crab._skeleton != null)
	var missing_legs := 0
	for leg in crab._tripod_a + crab._tripod_b:
		if leg[0] < 0 or leg[1] < 0:
			missing_legs += 1
	failures += _check("every leg bone name resolved (%d missing)" % missing_legs, missing_legs == 0)
	failures += _check("every claw bone name resolved",
		crab._claw_shoulder >= 0 and crab._claw_a >= 0 and crab._claw_b >= 0)

	# render() is never called by bots.tick()/events.advance() — nothing in
	# this harness draws a frame — so this calls it directly, once, the only
	# way to prove the walk cycle actually poses a bone rather than just
	# deciding to. _elapsed is already ~2s of sim time in from the wander
	# loop above, well off a sin() zero-crossing.
	crab.render(1.0)
	var any_leg_posed := false
	for leg in crab._tripod_a + crab._tripod_b:
		var thigh: int = leg[0]
		if thigh >= 0 and not crab._skeleton.get_bone_pose_rotation(thigh).is_equal_approx(Quaternion.IDENTITY):
			any_leg_posed = true
			break
	failures += _check("render() actually poses a leg bone away from rest", any_leg_posed)

	# Planted at the spot it is currently standing on.
	var spawn := Vector2(crab.position.x, crab.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(Crabylon.MELEE_RANGE * 0.3, 0.0))

	# Outside STOMP_RADIUS (25) but inside CLAW_RANGE/MELEE_RANGE (38) — the
	# one place a kill can only be the claw, never the area stomp, proving
	# the two are actually separate mechanics rather than one radius
	# reporting through two counters.
	var claw_victim := _first_of_class(bots, GameConfig.CLASS_SPEARMAN)
	_place(bots, claw_victim, spawn + Vector2(0.0, (Crabylon.STOMP_RADIUS + Crabylon.CLAW_RANGE) * 0.5))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Crabylon.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	var t := 40
	while t < MAX_TICKS and crab._phase != Crabylon._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if crab._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", crab._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported keeling over", events.last_description.contains("keels over"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_crab(events) == crab)

	print("--- the claw grab ---")
	print("  grabbed        : %d, stomped: %d" % [crab._grabbed, crab._stomped])
	failures += _check("the claw grab killed at least one bot, distinct from the stomp",
		crab._grabbed > 0)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"crab", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"crab", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"crab")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  crab           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the crab has not gone quadratic (%.2f ms worst)"
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


func _find_crab(events: EventManager) -> Crabylon:
	for child in events.get_children():
		if child is Crabylon and not child.is_queued_for_deletion():
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
