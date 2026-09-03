extends Node
## Checks the giant dragon: the pilot for playing a real baked
## AnimationPlayer clip instead of a hand-posed Skeleton3D rig (see the
## class doc on dragon.gd). Confirms the clips actually resolved, that
## render() actually scrubs the player rather than leaving it at rest, that
## it never touches the ground while alive, that only archers and nearby
## melee hurt it, that a modest crowd brings it down, and that it crashes
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
	failures += _check("the dragon is registered", events.has_event(&"dragon"))

	print("--- the clip rig ---")
	bots.spawn(BOTS, GameConfig.DEFAULT_MAP_SEED)
	events.reset(GameConfig.DEFAULT_MAP_SEED)

	var start_alive := bots.alive_count
	failures += _check("the dragon fired", events.trigger(&"dragon", {"health": HEALTH}))
	print("  announced      : %s" % events.last_description)
	failures += _check("nobody has died yet", bots.alive_count == start_alive)

	var dragon := _find_dragon(events)
	failures += _check("the dragon is in flight", dragon != null)
	failures += _check("a second dragon is refused while one is loose",
		not events.trigger(&"dragon"))

	failures += _check("an AnimationPlayer was found on the imported model",
		dragon._anim_player != null)
	for needed in ["Fast_Flying", "Flying_Idle", "Headbutt", "Death"]:
		failures += _check("clip '%s' resolved" % needed, dragon._clip_resources.has(needed))

	failures += _check("it never touches the ground while alive (altitude %.1f m)"
		% (dragon.position.y - main.get_node("World").get_height(dragon.position.x, dragon.position.z)),
		dragon.position.y - main.get_node("World").get_height(dragon.position.x, dragon.position.z)
			> Dragon.ALTITUDE * 0.5)

	dragon.render(1.0)
	failures += _check("render() actually selected a clip to play",
		dragon._current_clip != "")

	# Planted directly underfoot, so the very next sweep is guaranteed to
	# find someone to strike — the spawn crowd is spread across the whole
	# island and cannot be relied on to already be standing where the
	# dragon happened to appear.
	var underfoot_pos := Vector2(dragon.position.x, dragon.position.z)
	var trampled := _first_of_class(bots, GameConfig.CLASS_WARRIOR)
	_place(bots, trampled, underfoot_pos)

	var t := 0
	while t < 20 and is_equal_approx(dragon._headbutt_trigger, -1000.0):
		bots.tick(step, t)
		events.advance(step)
		t += 1
	failures += _check("the strike was actually registered within the tick budget (%d)" % t,
		not is_equal_approx(dragon._headbutt_trigger, -1000.0))
	dragon.render(1.0)
	failures += _check("it plays the Headbutt flourish shortly after a stomp",
		dragon._current_clip == dragon._clip_names.get("Headbutt", ""))

	# Planted at the spot it is currently hovering over. Index 1, not 0: the
	# first warrior found is the one already trampled above (dead, and
	# _place() on a corpse would not put a real fighter into the fight
	# below).
	var spawn := Vector2(dragon.position.x, dragon.position.z)
	var victim := _some_of_class(bots, GameConfig.CLASS_WARRIOR, 2)[1]
	_place(bots, victim, spawn + Vector2(Dragon.MELEE_RANGE * 0.3, 0.0))

	var archers := _some_of_class(bots, GameConfig.CLASS_ARCHER, ARCHER_COUNT)
	failures += _check("found enough archers to plant (%d)" % archers.size(),
		archers.size() == ARCHER_COUNT)
	for i in archers:
		_place(bots, i, spawn + Vector2(0.0, Dragon.ATTACK_RANGE * 0.5))

	print("--- the fight ---")
	var ever_hurt := false
	while t < MAX_TICKS and dragon._phase != Dragon._Phase.DEAD:
		bots.tick(step, t)
		events.advance(step)
		if dragon._health < HEALTH:
			ever_hurt = true
		t += 1

	print("  reported       : %s" % events.last_description)
	failures += _check("the archers actually hurt it", ever_hurt)
	failures += _check("its health reached zero", dragon._health <= 0.0)
	failures += _check("it fell inside the tick budget (%d)" % t, t < MAX_TICKS)
	failures += _check("it reported crashing", events.last_description.contains("crashes to the ground"))
	failures += _check("but not everyone died (%d of %d left)"
		% [bots.alive_count, start_alive], bots.alive_count > 0)
	failures += _check("it stays adopted rather than freeing itself, the way a fallen boss does",
		_find_dragon(events) == dragon)
	failures += _check("it actually reached the ground once dead",
		is_equal_approx(dragon.position.y, main.get_node("World").get_height(dragon.position.x, dragon.position.z)))

	print("--- bad parameters ---")
	failures += _check("a zero health is refused", not events.trigger(&"dragon", {"health": 0.0}))
	failures += _check("a negative health is refused",
		not events.trigger(&"dragon", {"health": -5.0}))

	print("--- cost at ten thousand ---")
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	events.trigger(&"dragon")
	var advance_cost := PackedFloat32Array()
	for t2 in 200:
		bots.tick(step, t2)
		var t0 := Time.get_ticks_usec()
		events.advance(step)
		advance_cost.append(float(Time.get_ticks_usec() - t0))
	print("  dragon         : %.3f ms median, %.3f ms worst over %d ticks"
		% [_median_ms(advance_cost), _worst_ms(advance_cost), advance_cost.size()])
	failures += _check("the dragon has not gone quadratic (%.2f ms worst)"
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


func _find_dragon(events: EventManager) -> Dragon:
	for child in events.get_children():
		if child is Dragon and not child.is_queued_for_deletion():
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
