extends Node
## Checks the kraken: that it surfaces on the coast, that standing close to
## it gets you dragged under, that only archers actually hurt it, that
## enough of them sink it with a real, permanent end, and that none of it
## grows out of proportion at ten thousand.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 500
## Low on purpose, so a handful of planted archers finish the fight inside a
## test rather than the real several-thousand default.
const HEALTH := 40.0
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
	failures += _check("the kraken is registered", events.has_event(&"kraken"))

	print("--- it surfaces ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	# No "x"/"z": letting the event pick its own coastal point is what
	# guarantees one that is actually on the coastline, the same reasoning
	# VolcanoEvent's own summit search already has.
	failures += _check("the kraken fired",
		events.trigger(&"kraken", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var kraken := _find_kraken(events)
	failures += _check("the kraken is in flight", kraken != null)

	failures += _check("a second kraken is refused while one is loose",
		not events.trigger(&"kraken"))

	# Planted at the spot the kraken actually surfaced, not a guessed
	# coordinate — a coastal point is only known once the event has picked
	# one. Nothing has ticked yet, so this is still safe.
	var spawn := Vector2(kraken.position.x, kraken.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(Kraken.TENTACLE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Kraken.ATTACK_RANGE * 0.5))

	print("--- the rig ---")
	# Eleventh boss on Crabylon's procedural rig — see the class doc. A few
	# ticks first so _elapsed is off a sin() zero-crossing; the fight loop
	# below continues this same tick counter rather than starting over, so
	# nothing here is double-ticked.
	var t := 0
	for _i in 5:
		bots.tick(step, t)
		events.advance(step)
		t += 1
	failures += _check("a Skeleton3D was found on the imported model", kraken._skeleton != null)
	failures += _check("all five tentacle groups resolved (%d)" % kraken._tentacles.size(),
		kraken._tentacles.size() == 5)
	var all_resolved := true
	for group in kraken._tentacles:
		for bone in group:
			if bone < 0:
				all_resolved = false
	failures += _check("every tentacle bone name resolved", all_resolved)
	kraken.render(1.0)
	var any_posed := false
	for group in kraken._tentacles:
		for bone in group:
			if bone >= 0 and not kraken._skeleton.get_bone_pose_rotation(bone).is_equal_approx(Quaternion.IDENTITY):
				any_posed = true
				break
	failures += _check("render() actually bends at least one tentacle bone away from rest", any_posed)
	failures += _check("two different tentacles are not stuck posing identically (independent phases)",
		not kraken._skeleton.get_bone_pose_rotation(kraken._tentacles[0][0]).is_equal_approx(
			kraken._skeleton.get_bone_pose_rotation(kraken._tentacles[1][0])))

	print("--- the fight ---")
	var ever_hurt := false
	while t < MAX_TICKS and kraken._phase != Kraken._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if kraken._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	print("  ticks          : %d" % t)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", kraken._health <= 0.0)
	failures += _check("it sank inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported sinking", events.last_description.contains("sinks"))
	failures += _check("the victim near the tideline was dragged under",
		bots.alive[victim] == 0)
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)

	print("--- after it sinks ---")
	failures += _check("it stays adopted rather than freeing itself, the way a crater does",
		_find_kraken(events) == kraken)
	var health_before := kraken._health
	var y_before := kraken.position.y
	bots.tick(step, t)
	events.advance(step)
	failures += _check("a sunk kraken does not keep losing health",
		kraken._health == health_before)
	failures += _check("and does not keep sinking either",
		kraken.position.y == y_before)

	var flagged := 0
	for i in bots.count:
		if bots.alive[i] == 1:
			flagged += 1
	failures += _check("alive_count matches the flags", flagged == bots.alive_count)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"kraken", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"kraken", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"kraken")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  kraken         : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	print("  dead           : %d of 10000" % (10000 - bots.alive_count))
	failures += _check("the kraken has not gone quadratic (%.2f ms worst)"
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


func _find_kraken(events: EventManager) -> Kraken:
	for child in events.get_children():
		if child is Kraken and not child.is_queued_for_deletion():
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
