extends Node
## Checks the monster: that it rises and walks, that standing underfoot gets
## you stomped, that only archers actually hurt it, that enough of them bring
## it down with a real fall it never gets back up from, and that none of it
## grows out of proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 500
## Low on purpose, so a handful of planted archers finish the fight inside a
## test rather than the real several-thousand default.
const HEALTH := 40.0
const SPAWN := Vector2(0.0, 0.0)
const ARCHER_COUNT := 6
const MAX_TICKS := 400


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
	failures += _check("the monster is registered", events.has_event(&"monster"))

	print("--- it rises ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	var spawn_y := world.get_height(SPAWN.x, SPAWN.y)

	# A warrior planted right where it lands, so the stomp check has a
	# guaranteed victim instead of hoping the crowd wandered there in time.
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, Vector3(SPAWN.x, spawn_y, SPAWN.y))

	# A handful of archers planted just past the stomp radius, so hurting it
	# is really about ranged fire and not an accident of the stomp above.
	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, Vector3(SPAWN.x, spawn_y, SPAWN.y + 30.0))

	var start_alive := bots.alive_count
	failures += _check("the monster fired",
		events.trigger(&"monster", {"x": SPAWN.x, "z": SPAWN.y, "health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var monster := _find_monster(events)
	failures += _check("the monster is in flight", monster != null)

	failures += _check("a second monster is refused while one is loose",
		not events.trigger(&"monster"))

	print("--- the rig ---")
	# Tenth boss on Crabylon's procedural rig, and the first added on top of
	# a boss that already had its own whole-body cosmetic motion — see the
	# class doc. A few ticks first so _elapsed is off a sin() zero-crossing;
	# the fight loop below continues this same tick counter rather than
	# starting over, so nothing here is double-ticked.
	var t := 0
	for _i in 5:
		bots.tick(step, t)
		events.advance(step)
		t += 1
	failures += _check("a Skeleton3D was found on the imported model", monster._skeleton != null)
	var limbs_resolved := true
	for limb in [monster._leg_l, monster._leg_r, monster._arm_l, monster._arm_r]:
		if limb[0] < 0 or limb[1] < 0:
			limbs_resolved = false
	failures += _check("all four limb bone chains resolved", limbs_resolved)
	monster.render(1.0)
	var leg_posed := not monster._skeleton.get_bone_pose_rotation(monster._leg_l[0]).is_equal_approx(Quaternion.IDENTITY)
	failures += _check("render() actually poses a leg bone away from rest", leg_posed)
	var arm_posed := not monster._skeleton.get_bone_pose_rotation(monster._arm_l[0]).is_equal_approx(Quaternion.IDENTITY)
	failures += _check("render() actually poses an arm bone away from rest", arm_posed)

	print("--- the fight ---")
	var ever_hurt := false
	while t < MAX_TICKS and monster._phase != Monster._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if monster._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	print("  ticks          : %d" % t)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", monster._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported falling", events.last_description.contains("falls"))
	failures += _check("the victim underfoot was stomped", bots.alive[victim] == 0)
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)

	print("--- arrows ---")
	var arrows := _find_arrow_swarm(events)
	failures += _check("an ArrowSwarm was adopted as a visual", arrows != null)
	if arrows != null:
		print("  shots fired    : %d" % arrows.shots_fired())
		failures += _check("archers actually fired at least one visible arrow",
			arrows.shots_fired() > 0)

	print("--- after the fall ---")
	failures += _check("it stays adopted rather than freeing itself, the way a crater does",
		_find_monster(events) == monster)
	var health_before := monster._health
	var rotation_before := monster.rotation.x
	bots.tick(step, t)
	events.advance(step)
	failures += _check("a fallen monster does not keep losing health",
		monster._health == health_before)
	failures += _check("and does not keep rotating either",
		monster.rotation.x == rotation_before)

	var flagged := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			flagged += 1
	failures += _check("alive_count matches the flags", flagged == bots.alive_count)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"monster", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"monster", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"monster", {"x": SPAWN.x, "z": SPAWN.y})
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  monster        : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the monster has not gone quadratic (%.2f ms worst)"
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


func _place(bots: BotManager, index: int, at: Vector3) -> void:
	bots.pos_x[index] = at.x
	bots.pos_y[index] = at.y
	bots.pos_z[index] = at.z


func _find_monster(events: EventManager) -> Monster:
	for child in events.get_children():
		if child is Monster and not child.is_queued_for_deletion():
			return child
	return null


func _find_arrow_swarm(events: EventManager) -> ArrowSwarm:
	for child in events.get_children():
		if child is ArrowSwarm:
			return child
	return null


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
