extends Node
## Checks the giant snake: that only archers and nearby melee hurt it, that
## the cosmetic slither never moves the authoritative position anything is
## measured against, that a modest crowd brings it down, and that it topples
## and stays down once beaten.
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
	failures += _check("the snake is registered", events.has_event(&"snake"))

	print("--- the slither is cosmetic only ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the snake fired", events.trigger(&"snake", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var snake := _find_snake(events)
	failures += _check("the snake is in flight", snake != null)
	failures += _check("a second snake is refused while one is loose",
		not events.trigger(&"snake"))

	for t in 10:
		bots.tick(step, t)
		events.advance(step)
	var current_before := snake._current
	var previous_before := snake._previous
	snake.render(0.3)
	var rendered := Vector3(snake.position)
	snake.render(0.3)
	var rendered_again := Vector3(snake.position)
	failures += _check("render() does not mutate the authoritative _current/_previous",
		snake._current == current_before and snake._previous == previous_before)
	failures += _check("the wiggle stays within its own amplitude (%.1f m from _current)"
		% snake._current.distance_to(rendered), snake._current.distance_to(rendered) <=
		Titanoboo.WIGGLE_AMPLITUDE + 0.01)
	failures += _check("the same alpha and elapsed time give the same wiggle",
		rendered.distance_to(rendered_again) < 0.001)

	# Planted at the spot it is currently standing on.
	var spawn := Vector2(snake.position.x, snake.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(Titanoboo.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Titanoboo.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	var t := 10
	while t < MAX_TICKS and snake._phase != Titanoboo._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if snake._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", snake._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported keeling over", events.last_description.contains("keels over"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_snake(events) == snake)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"snake", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"snake", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"snake")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  snake          : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the snake has not gone quadratic (%.2f ms worst)"
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


func _find_snake(events: EventManager) -> Titanoboo:
	for child in events.get_children():
		if child is Titanoboo and not child.is_queued_for_deletion():
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
