extends Node
## Checks the giant chicken: that it actually falls before it can be fought,
## that only archers and nearby melee hurt it, that a modest crowd brings it
## down inside a short, comedic fight rather than a real boss encounter, and
## that it topples and stays down once beaten.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 400
## Low on purpose, so a handful of planted attackers finish the fight inside
## a test rather than the real several-hundred default health.
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
	failures += _check("the chicken is registered", events.has_event(&"chicken"))

	print("--- it falls before it can be fought ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the chicken fired", events.trigger(&"chicken", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var bird := _find_bird(events)
	failures += _check("the chicken is in flight", bird != null)
	failures += _check("it starts above the ground, still falling",
		bird.position.y > bird._ground_y and bird._phase == GiantBird._Phase.DROPPING)
	failures += _check("a second chicken is refused while one is loose",
		not events.trigger(&"chicken"))

	var t := 0
	while t < MAX_TICKS and bird._phase == GiantBird._Phase.DROPPING:
		bots.tick(step, t)
		events.advance(step)
		t += 1
	failures += _check("it landed inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it is standing on the ground it landed on",
		is_equal_approx(bird.position.y, bird._ground_y))

	# Planted at the spot it actually landed on, not a guessed coordinate.
	var spawn := Vector2(bird.position.x, bird.position.z)
	var victim := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, victim, spawn + Vector2(GiantBird.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, GiantBird.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	while t < MAX_TICKS and bird._phase != GiantBird._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if bird._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	print("  ticks          : %d" % t)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", bird._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported keeling over", events.last_description.contains("keels over"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)

	print("--- after it falls ---")
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_bird(events) == bird)
	var health_before := bird._health
	bots.tick(step, t)
	events.advance(step)
	failures += _check("a fallen chicken does not keep losing health",
		bird._health == health_before)

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"chicken", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"chicken", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"chicken")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  chicken        : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the chicken has not gone quadratic (%.2f ms worst)"
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


func _find_bird(events: EventManager) -> GiantBird:
	for child in events.get_children():
		if child is GiantBird and not child.is_queued_for_deletion():
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
