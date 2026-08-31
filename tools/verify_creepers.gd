extends Node
## Checks the creeper swarm: that it spawns exactly as many as asked, that
## each one walks up, hisses, and only then goes off — BotManager.kill()/
## fling(), the same primitives Meteor's blast and Tornado's toss already
## use — and that a swarm at ten thousand does not go quadratic.
##
## Timings printed by this tool are **information, not a budget** — see
## verify_flood.gd's own note on thermal throttling between runs.

const BOTS := 200
const COUNT := 3
const MAX_TICKS := 900


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
	failures += _check("creepers is registered", events.has_event(&"creepers"))

	print("--- it spawns exactly as many as asked ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	failures += _check("creepers fired", events.trigger(&"creepers", {"count": COUNT}))
	print("  announced      : %s" % events.last_description)
	var found := _find_creepers(events)
	failures += _check("spawned exactly the requested count (%d of %d)" % [found.size(), COUNT],
		found.size() == COUNT)

	# Planted right where one of them starts, so it reaches and explodes
	# well inside the tick budget rather than wandering the whole island.
	var target: Creeper = found[0]
	var spawn := Vector2(target.position.x, target.position.z)
	var victim := _first_alive(bots)
	_place(bots, victim, spawn)

	print("--- it hisses, then explodes ---")
	var hissed := false
	var t := 0
	while t < MAX_TICKS and is_instance_valid(target) and not target.is_queued_for_deletion():
		bots.tick(step, t)
		events.advance(step)
		if is_instance_valid(target) and target._phase == Creeper._Phase.FUSING:
			hissed = true
		t += 1

	failures += _check("it started fusing before it went off", hissed)
	failures += _check("it exploded inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it freed itself rather than lingering", target.is_queued_for_deletion())
	failures += _check("the planted victim died in the blast", bots.alive[victim] == 0)
	failures += _check("it reported detonating", events.last_description.contains("detonates"))

	print("--- bad parameters ---")
	failures += _check("a zero count is refused", not events.trigger(&"creepers", {"count": 0}))
	failures += _check("a negative count is refused", not events.trigger(&"creepers", {"count": -2}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"creepers", {"count": 10})
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  creepers       : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the swarm has not gone quadratic (%.2f ms worst)"
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


func _find_creepers(events: EventManager) -> Array[Creeper]:
	var found: Array[Creeper] = []
	for child in events.get_children():
		if child is Creeper and not child.is_queued_for_deletion():
			found.append(child)
	return found


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
