extends Node
## Checks World.route_waypoint(): a clear line goes straight to the
## destination, a line that would cut across open water gets redirected onto
## a walkable route instead, and BotManager.send_to()/gather_at() actually
## use the routed point rather than the raw one they were given.
##
## Ordinary wander is not this suite's job — it never calls route_waypoint()
## and stays exactly as covered by verify_movement.gd. This is only the path
## a long-distance send (Team War's march, a supply drop's runners) takes.

## Raised from 400 after the volcano landform: it added a lot of land, which
## made the island's coastline more convex overall and a blocked line-of-
## sight pair correspondingly rarer to stumble on by chance, not less real —
## 400 attempts started missing on this seed, 4000 still reliably finds one.
const SEARCH_ATTEMPTS := 4000
const FAR_ENOUGH := 500.0

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")

	bots.spawn(200, GameConfig.DEFAULT_MAP_SEED)

	print("--- a clear line goes straight to the destination ---")
	var near_a := Vector2(bots.pos_x[0], bots.pos_z[0])
	var near_b := near_a + Vector2(20.0, 15.0)
	if not world.is_walkable(near_b.x, near_b.y):
		near_b = near_a + Vector2(-20.0, -15.0)
	var direct := world.route_waypoint(near_a, near_b)
	failures += _check("a short clear hop is not redirected", direct.is_equal_approx(near_b))

	print("--- a blocked line is redirected onto a walkable route ---")
	# Searched rather than hand-picked: which pairs of points on this island
	# have water between them depends on the seed's coastline, not on
	# anything this suite can compute in advance. Far-apart pairs on a
	# non-convex coastline are likely to be blocked; deterministic because the
	# search itself is seeded.
	var rng := RandomNumberGenerator.new()
	rng.seed = GameConfig.DEFAULT_MAP_SEED ^ 0x1234
	var blocked_a := Vector2.ZERO
	var blocked_b := Vector2.ZERO
	var found := false
	for attempt in SEARCH_ATTEMPTS:
		var a := world.random_land_point(rng)
		var b := world.random_land_point(rng)
		if a.distance_to(b) < FAR_ENOUGH:
			continue
		if not _line_clear(world, a, b):
			blocked_a = a
			blocked_b = b
			found = true
			break
	failures += _check("found a real blocked pair on this island (%d attempts)" % SEARCH_ATTEMPTS,
		found)

	if found:
		var redirected := world.route_waypoint(blocked_a, blocked_b)
		failures += _check("the redirect is not the original, blocked destination",
			not redirected.is_equal_approx(blocked_b))
		failures += _check("the redirect itself lands on walkable ground",
			world.is_walkable(redirected.x, redirected.y))
		failures += _check("the redirect is real progress towards the goal",
			redirected.distance_to(blocked_b) < blocked_a.distance_to(blocked_b))

		print("--- send_to() and gather_at() aim exactly where they are told ---")
		# Routing lives one level up from here now — WarBattle and
		# SupplyScramble each ask World.route_waypoint() once per group and
		# hand every bot in it the same already-routed point, rather than
		# BotManager asking again per bot. Asking per bot was tried first and
		# cost thousands of independent region searches in a single tick for
		# what is, every time, the same handful of shared destinations — see
		# the "found by test" note in TODO.md. What belongs at this level is
		# just that send_to()/gather_at() forward the point faithfully.
		var index := 5
		bots.pos_x[index] = blocked_a.x
		bots.pos_z[index] = blocked_a.y
		bots.send_to(index, redirected.x, redirected.y)
		failures += _check("send_to() aims exactly where it is told",
			Vector2(bots.target_x[index], bots.target_z[index]).is_equal_approx(redirected))

		var gather_index := 6
		bots.pos_x[gather_index] = blocked_a.x
		bots.pos_z[gather_index] = blocked_a.y
		bots.gather_at(gather_index, redirected.x, redirected.y)
		failures += _check("gather_at() aims exactly where it is told too",
			Vector2(bots.target_x[gather_index], bots.target_z[gather_index]).is_equal_approx(redirected))
	else:
		print("  (skipped: no blocked pair found on this island/seed)")

	print("--- a normal, close send is unaffected ---")
	var idle_index := 7
	bots.pos_x[idle_index] = near_a.x
	bots.pos_z[idle_index] = near_a.y
	bots.send_to(idle_index, near_b.x, near_b.y)
	var idle_target := Vector2(bots.target_x[idle_index], bots.target_z[idle_index])
	failures += _check("a clear send lands exactly on the point given",
		idle_target.is_equal_approx(near_b))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


## Same sampling World's own _line_clear() does. Kept here rather than made
## public on World: this suite is the one place outside World that needs to
## ask the question directly, in order to go looking for a pair
## route_waypoint() ought to redirect.
func _line_clear(world: World, from: Vector2, to: Vector2) -> bool:
	var distance := from.distance_to(to)
	if distance < 0.001:
		return true
	var steps := clampi(int(ceil(distance / 32.0)), 1, 64)
	for i in steps + 1:
		var p := from.lerp(to, float(i) / steps)
		if not world.is_walkable(p.x, p.y):
			return false
	return true


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
