extends Node
## Checks the giant lion: that its roar cycle actually widens PANIC_RADIUS/
## FLEE_DISTANCE while active and leaves them at their base value outside
## it, that only archers and nearby melee hurt it, that a modest crowd
## brings it down, and that it topples and stays down once beaten.
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
	failures += _check("the lion is registered", events.has_event(&"lion"))

	print("--- the roar widens panic, only while it lasts ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the lion fired", events.trigger(&"lion", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var lion := _find_rhombolion(events)
	failures += _check("the lion is in flight", lion != null)
	failures += _check("a second lion is refused while one is loose",
		not events.trigger(&"lion"))

	# A bystander sitting between the base PANIC_RADIUS and the roar-widened
	# one: safe on a quiet sweep, scared on a roaring one. Directly driving
	# _elapsed and calling _sweep() rather than ticking the real clock the
	# right number of times, the same reasoning verify_horsely.gd's settle
	# check uses — the roar cycle's own boundaries are the thing under
	# test, not how many ticks it takes to reach them.
	var here := Vector2(lion.position.x, lion.position.z)
	var ring_distance := (Rhombolion.PANIC_RADIUS + Rhombolion.PANIC_RADIUS * Rhombolion.ROAR_RADIUS_MULT) * 0.5
	var bystander := _first_of_class(bots, GameConfig.CLASS_ARCHER)
	_place(bots, bystander, here + Vector2(ring_distance, 0.0))

	bots.state[bystander] = BotManager.State.IDLE
	lion._elapsed = Rhombolion.ROAR_DURATION_SECONDS + 0.5
	failures += _check("not roaring at this point in the cycle", not lion._roaring())
	lion._sweep(step)
	failures += _check("the ring bystander is left alone on a quiet sweep (%.0f m out)"
		% ring_distance, bots.state[bystander] != BotManager.State.FLEEING)

	bots.state[bystander] = BotManager.State.IDLE
	lion._elapsed = 0.5
	failures += _check("roaring at this point in the cycle", lion._roaring())
	lion._sweep(step)
	failures += _check("the same bystander is scared once the roar reaches that far",
		bots.state[bystander] == BotManager.State.FLEEING)
	failures += _check("the report says it is roaring",
		events.last_description.contains("roaring"))

	print("--- the fight ---")
	# Reset _elapsed so the roar cycle does not confuse the cost measurement
	# below, and replant a fresh victim/archers away from the bystander,
	# which may now be mid-flight.
	lion._elapsed = 0.0
	var spawn := Vector2(lion.position.x, lion.position.z)
	var victim := _some_of_class(bots, GameConfig.CLASS_WARRIOR, 1)[0]
	_place(bots, victim, spawn + Vector2(Rhombolion.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT + 1)
	archers.remove_at(0)  # the first is `bystander`, already placed on the roar ring
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Rhombolion.ATTACK_RANGE * 0.5))

	var ever_hurt := false
	var t := 0
	while t < MAX_TICKS and lion._phase != Rhombolion._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if lion._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", lion._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported keeling over", events.last_description.contains("keels over"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_rhombolion(events) == lion)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"lion", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"lion", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"lion")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  lion           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the lion has not gone quadratic (%.2f ms worst)"
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


func _find_rhombolion(events: EventManager) -> Rhombolion:
	for child in events.get_children():
		if child is Rhombolion and not child.is_queued_for_deletion():
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
