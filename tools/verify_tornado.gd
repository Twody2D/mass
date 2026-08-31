extends Node
## Checks the tornado: that it wanders under its own random retargeting
## instead of sitting still, that standing where it touches down gets you
## thrown through BotManager.fling() — the same primitive the meteor's blast
## survivors are thrown with — that it blows itself out and frees itself
## rather than staying forever like a fallen boss, and that none of it goes
## quadratic at ten thousand.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 300
## Enough 20 Hz ticks to cover the full DURATION (32 s) plus a comfortable
## margin, so a run that never blows itself out fails loudly instead of
## looping forever.
const MAX_TICKS := 900
const MOVED_THRESHOLD := 60.0


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
	failures += _check("the tornado is registered", events.has_event(&"tornado"))

	print("--- it touches down ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	failures += _check("the tornado fired", events.trigger(&"tornado"))
	print("  announced      : %s" % events.last_description)

	var tornado := _find_tornado(events)
	failures += _check("the tornado is in flight", tornado != null)
	failures += _check("a second tornado is refused while one is loose",
		not events.trigger(&"tornado"))

	# Planted right where it touched down: nothing has ticked yet, so this is
	# still exactly where the event actually put it.
	var spawn := Vector2(tornado.position.x, tornado.position.z)
	var victim := _first_alive(bots)
	_place(bots, victim, spawn)

	print("--- it wanders and it catches whoever it touches down on ---")
	var start_pos := spawn
	var last_pos := spawn
	var caught := false
	var t := 0
	while t < MAX_TICKS and is_instance_valid(tornado) and not tornado.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		last_pos = Vector2(tornado.position.x, tornado.position.z)
		if bots.state[victim] == BotManager.State.FLUNG:
			caught = true
		t += 1

	failures += _check("the victim standing where it touched down got thrown", caught)
	failures += _check("it actually moved rather than sitting still (%.0f m)"
		% start_pos.distance_to(last_pos), start_pos.distance_to(last_pos) > MOVED_THRESHOLD)

	print("--- it blows itself out ---")
	failures += _check("it ran for less than the tick budget (%d ticks)" % t, t < MAX_TICKS)
	failures += _check("it queued itself for deletion rather than staying forever",
		tornado.is_queued_for_deletion())
	failures += _check("it is gone from the event manager's live children",
		_find_tornado(events) == null)
	failures += _check("it reported blowing itself out",
		events.last_description.contains("blows itself out"))

	print("--- an explicit spawn point is honoured ---")
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	failures += _check("triggering with x/z succeeds",
		events.trigger(&"tornado", {"x": 40.0, "z": -60.0}))
	var placed := _find_tornado(events)
	failures += _check("it touched down exactly there", placed != null
		and Vector2(placed.position.x, placed.position.z).is_equal_approx(Vector2(40.0, -60.0)))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"tornado")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  tornado        : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the tornado has not gone quadratic (%.2f ms worst)"
		% _worst_ms(advance_cost), _worst_ms(advance_cost) < 200.0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _first_alive(bots: BotManager) -> int:
	for i in bots.count:
		if bots.alive[i] == 1:
			return i
	return -1


func _place(bots: BotManager, index: int, at: Vector2) -> void:
	bots.pos_x[index] = at.x
	bots.pos_z[index] = at.y


func _find_tornado(events: EventManager) -> Tornado:
	for child in events.get_children():
		if child is Tornado and not child.is_queued_for_deletion():
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
