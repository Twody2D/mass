extends Node
## Checks the giant worm: that only archers and nearby melee hurt it, that a
## modest crowd brings it down, and that once beaten it sinks straight down
## (no legs to topple onto) rather than rotating over like every other
## giant here, stopping partway rather than vanishing entirely.
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
	failures += _check("the worm is registered", events.has_event(&"worm"))

	print("--- it surfaces and moves ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the worm fired", events.trigger(&"worm", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var worm := _find_whormbus(events)
	failures += _check("the worm is in flight", worm != null)
	failures += _check("a second worm is refused while one is loose",
		not events.trigger(&"worm"))

	var start_pos := Vector2(worm.position.x, worm.position.z)
	for t in 40:
		bots.tick(step, t)
		events.advance(step)
	failures += _check("it actually moved",
		Vector2(worm.position.x, worm.position.z) != start_pos)

	# Planted at the spot it is currently standing on.
	var spawn := Vector2(worm.position.x, worm.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(Whormbus.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Whormbus.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	var t := 40
	while t < MAX_TICKS and worm._phase != Whormbus._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if worm._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", worm._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported burrowing down",
		events.last_description.contains("burrows down"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_whormbus(events) == worm)

	print("--- it sinks rather than topples ---")
	failures += _check("it never rotates the way a legged giant's fall does",
		is_zero_approx(worm.rotation.x))
	var sank := worm._fall_start_y - worm.position.y
	print("  sank by        : %.1f m of a possible %.1f m (LENGTH * SINK_SHARE)"
		% [sank, Whormbus.LENGTH * Whormbus.SINK_SHARE])
	failures += _check("it sank close to LENGTH * SINK_SHARE",
		absf(sank - Whormbus.LENGTH * Whormbus.SINK_SHARE) < 0.5)
	failures += _check("it stopped under half its own length down, staying a visible landmark",
		sank < Whormbus.LENGTH * 0.5)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"worm", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"worm", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"worm")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  worm           : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the worm has not gone quadratic (%.2f ms worst)"
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


func _find_whormbus(events: EventManager) -> Whormbus:
	for child in events.get_children():
		if child is Whormbus and not child.is_queued_for_deletion():
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
