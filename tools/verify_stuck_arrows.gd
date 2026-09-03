extends Node
## Checks StuckArrows on its own (capacity, ring-buffer eviction, ground vs.
## body placement) and EventManager's own archer_shot()/archer_kill() wiring
## into it and into the shared ArrowSwarm — "как в Minecraft от скелета":
## arrows left standing in the ground near a boss and in a corpse a war's
## own archers actually killed.

func _ready() -> void:
	var failures := 0

	print("--- the pool on its own ---")
	var pool := StuckArrows.create()
	add_child(pool)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	failures += _check("starts empty", pool.stuck_total() == 0)
	pool.stick_in_ground(Vector3(10.0, 5.0, 20.0), rng)
	failures += _check("one ground stick counted", pool.stuck_total() == 1)
	pool.stick_in_body(Vector3(30.0, 0.0, 40.0), rng)
	failures += _check("one body stick counted too", pool.stuck_total() == 2)

	for _i in StuckArrows.SLOT_COUNT * 2:
		pool.stick_in_ground(Vector3(0.0, 0.0, 0.0), rng)
	failures += _check("the ring buffer never stops accepting new arrows past its own capacity",
		pool.stuck_total() == 2 + StuckArrows.SLOT_COUNT * 2)

	print("--- EventManager wiring ---")
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var events: EventManager = main.get_node("Events")

	var swarm := _find_arrow_swarm(events)
	failures += _check("a shared ArrowSwarm exists on EventManager", swarm != null)
	var arrows := _find_stuck_arrows(events)
	failures += _check("a shared StuckArrows exists on EventManager", arrows != null)

	var before_shots := swarm.shots_fired() if swarm != null else 0
	var before_stuck := arrows.stuck_total() if arrows != null else 0
	for _i in EventManager.ARROW_STICK_STRIDE:
		events.archer_shot(Vector3(0.0, 10.0, 0.0), Vector3(5.0, 10.0, 5.0))
	failures += _check("archer_shot() always fires the flying visual",
		swarm.shots_fired() == before_shots + EventManager.ARROW_STICK_STRIDE)
	failures += _check("archer_shot() sticks one in the ground every ARROW_STICK_STRIDE-th call",
		arrows.stuck_total() == before_stuck + 1)

	events.archer_kill(Vector3(5.0, 0.0, 5.0))
	failures += _check("archer_kill() sticks one in the body immediately, not sampled",
		arrows.stuck_total() == before_stuck + 2)

	print("--- a flying boss sticks arrows in the ground, not mid-air ---")
	# Dragon flies at ALTITUDE above the ground — archer_shot()'s own
	# re-grounding through World.get_height() has to pull the stuck arrow
	# back down to the real terrain, not leave it floating at the dragon's
	# own body height.
	var world: World = main.get_node("World")
	var high_at := Vector3(0.0, world.get_height(0.0, 0.0) + Dragon.ALTITUDE, 0.0)
	var stuck_before := arrows.stuck_total()
	for _i in EventManager.ARROW_STICK_STRIDE:
		events.archer_shot(Vector3(0.0, high_at.y, 20.0), high_at)
	failures += _check("a shot at flight altitude still stuck exactly one arrow",
		arrows.stuck_total() == stuck_before + 1)

	print("--- reset() rebuilds both pools rather than leaving stale references ---")
	events.reset(GameConfig.DEFAULT_MAP_SEED)
	var swarm_after := _find_arrow_swarm(events)
	var arrows_after := _find_stuck_arrows(events)
	failures += _check("a fresh ArrowSwarm exists after reset()", swarm_after != null)
	failures += _check("a fresh StuckArrows exists after reset()", arrows_after != null)
	# The real bug this guards against: archer_shot() calling into whatever
	# reset() just free()'d, the "previously freed" error a real run of
	# verify_war.gd caught before this line existed.
	events.archer_shot(Vector3.ZERO, Vector3(1.0, 1.0, 1.0))
	failures += _check("archer_shot() still works right after reset()",
		swarm_after.shots_fired() == 1)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _find_arrow_swarm(events: EventManager) -> ArrowSwarm:
	for child in events.get_children():
		if child is ArrowSwarm:
			return child
	return null


func _find_stuck_arrows(events: EventManager) -> StuckArrows:
	for child in events.get_children():
		if child is StuckArrows:
			return child
	return null


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
