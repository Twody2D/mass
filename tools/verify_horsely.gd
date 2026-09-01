extends Node
## Checks the giant horse: that it rears (a cosmetic pitch) right after
## each stomp and settles back to standing afterward, that only archers
## and nearby melee hurt it, that a modest crowd brings it down, and that
## it falls and stays down once beaten.
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
	failures += _check("the horse is registered", events.has_event(&"horse"))

	print("--- it rears right after it stomps, and settles back down ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the horse fired", events.trigger(&"horse", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var horse := _find_horsely(events)
	failures += _check("the horse is in flight", horse != null)
	failures += _check("a second horse is refused while one is loose",
		not events.trigger(&"horse"))

	failures += _check("it starts settled, not mid-rear (t=0 pitch %.3f)" % horse.rotation.x,
		is_zero_approx(horse.rotation.x))

	# Planted directly underfoot, so the very next sweep is guaranteed to
	# find someone to rear over — the spawn crowd is spread across the
	# whole island and cannot be relied on to already be standing where
	# the horse happened to land.
	var underfoot_pos := Vector2(horse.position.x, horse.position.z)
	var trampled := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, trampled, underfoot_pos)

	# Tick until the trample is actually registered (_rear_trigger moves off
	# its starting sentinel), not a fixed count — SWEEP_SECONDS decides
	# exactly when the first sweep lands, and checking too many ticks past
	# it would catch the rear-kick already decaying back down again.
	var t := 0
	while t < 20 and is_equal_approx(horse._rear_trigger, -1000.0):
		bots.tick(step, t)
		events.advance(step)
		t += 1
	failures += _check("the trample was actually registered within the tick budget (%d)" % t,
		not is_equal_approx(horse._rear_trigger, -1000.0))
	horse.render(1.0)
	var peak := horse.rotation.x
	print("  right after a stomp : pitch %.3f (peak %.3f)" % [peak, Horsely.REAR_KICK_ANGLE])
	failures += _check("it is rearing shortly after a stomp", peak > 0.01)

	# Testing "does it settle back down" through more simulated ticks would
	# be testing when the crowd next happens to be underfoot, not the decay
	# curve itself — _sweep() fires every SWEEP_SECONDS regardless of
	# contact, and SWEEP_SECONDS (0.2s) is shorter than REAR_KICK_SECONDS
	# (0.3s), so a horse standing in a real crowd never actually finishes
	# settling before the next rear. Pushing _rear_trigger itself into the
	# past and reading render() directly tests the decay math on its own
	# terms instead.
	horse._rear_trigger = horse._elapsed - Horsely.REAR_KICK_SECONDS - 0.1
	horse.render(1.0)
	print("  settled after       : pitch %.4f" % horse.rotation.x)
	failures += _check("it settles back to standing once the rear-kick window passes",
		is_zero_approx(horse.rotation.x))

	# Planted at the spot it is currently standing on. Index 1, not 0: the
	# first warrior found is the one already trampled above (dead, and
	# `_place()` on a corpse would not put a real fighter into the fight
	# below).
	var spawn := Vector2(horse.position.x, horse.position.z)
	var victim := _some_of_class(bots, GameConfig.CLASS_WARRIOR, 2)[1]
	_place(bots, victim, spawn + Vector2(Horsely.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Horsely.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	while t < MAX_TICKS and horse._phase != Horsely._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if horse._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", horse._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported falling", events.last_description.contains("stumbles and falls"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_horsely(events) == horse)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"horse", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"horse", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"horse")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  horse          : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the horse has not gone quadratic (%.2f ms worst)"
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


func _find_horsely(events: EventManager) -> Horsely:
	for child in events.get_children():
		if child is Horsely and not child.is_queued_for_deletion():
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
