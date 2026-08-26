extends Node
## Checks that the simulation tick actually moves bots, keeps them on the
## island, and stays deterministic. Also measures what one tick costs at every
## target scale, which is the number the whole design has to live inside.

const TICKS := 200


func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var world: World = main.get_node("World")
	var bots: BotManager = main.get_node("Bots")
	var step: float = GameConfig.SIMULATION_TICK_SECONDS

	# Median rather than mean. A single scheduling hiccup on a laptop drags an
	# average by a factor of several, and chasing that as if it were a
	# regression has already wasted time once.
	print("--- tick cost, median of %d ticks ---" % TICKS)
	for n in [100, 1000, 5000, 10000]:
		main.rebuild(GameConfig.DEFAULT_MAP_SEED, n)
		var samples := PackedFloat64Array()
		samples.resize(TICKS)
		for t in TICKS:
			var t0 := Time.get_ticks_usec()
			bots.tick(step, t)
			samples[t] = float(Time.get_ticks_usec() - t0)
		samples.sort()
		var us: float = samples[TICKS / 2]
		var budget := 100.0 * us / (step * 1000000.0)
		print("  %6d bots : %6.3f ms/tick, %5.1f%% of the 20 Hz tick budget (worst %.2f ms)"
			% [n, us / 1000.0, budget, samples[TICKS - 1] / 1000.0])

	print("--- behaviour at %d bots after %d ticks (%.1f s) ---"
		% [bots.count, TICKS, TICKS * step])

	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	var start_x := bots.pos_x.duplicate()
	var start_z := bots.pos_z.duplicate()
	for t in TICKS:
		bots.tick(step, t)

	var moved := 0
	var over_water := 0
	var off_map := 0
	var bad_state := 0
	var moving := 0
	var travelled := 0.0
	var limit := world.half_extent()
	for i in bots.count:
		var dx: float = bots.pos_x[i] - start_x[i]
		var dz: float = bots.pos_z[i] - start_z[i]
		var distance := sqrt(dx * dx + dz * dz)
		travelled += distance
		if distance > 0.5:
			moved += 1
		if world.get_height(bots.pos_x[i], bots.pos_z[i]) <= GameConfig.WATER_LEVEL:
			over_water += 1
		if absf(bots.pos_x[i]) > limit or absf(bots.pos_z[i]) > limit:
			off_map += 1
		if bots.state[i] != BotManager.State.IDLE and bots.state[i] != BotManager.State.MOVING:
			bad_state += 1
		if bots.state[i] == BotManager.State.MOVING:
			moving += 1

	print("  moved          : %d of %d, average %.1f m travelled"
		% [moved, bots.count, travelled / bots.count])
	print("  moving now     : %d, idle %d" % [moving, bots.count - moving])
	print("  over water     : %d (%.2f%%)" % [over_water, 100.0 * over_water / bots.count])
	failures += _check("almost every bot has moved", moved > bots.count * 0.95)
	failures += _check("nobody left the map (%d)" % off_map, off_map == 0)
	failures += _check("only IDLE and MOVING are used (%d others)" % bad_state, bad_state == 0)
	failures += _check("under 1%% of bots stand over water", over_water < bots.count * 0.01)
	failures += _check("bots are spread across both states", moving > 0 and moving < bots.count)

	# Determinism: same seed, same number of ticks, same result.
	var after_x := bots.pos_x.duplicate()
	main.rebuild(GameConfig.DEFAULT_MAP_SEED, 10000)
	for t in TICKS:
		bots.tick(step, t)
	failures += _check("same seed and ticks reproduce the run exactly", after_x == bots.pos_x)

	# Separation is the whole point of the spatial grid: knights must not stand
	# inside each other.
	var radius: float = GameConfig.SEPARATION_RADIUS
	var grid := SpatialGrid.new()
	grid.configure(GameConfig.MAP_SIZE, SpatialGrid.cell_size_for_radius(radius))
	grid.rebuild(bots.pos_x, bots.pos_z, bots.count)

	var overlapping := 0
	var closest := 1e9
	var nearest_total := 0.0
	var measured := 0
	var last_cell := grid.resolution - 1
	for i in bots.count:
		var x: float = bots.pos_x[i]
		var z: float = bots.pos_z[i]
		var nearest := 1e9
		var first_x := clampi(grid.cell_of(x - radius), 0, last_cell)
		var end_x := clampi(grid.cell_of(x + radius), 0, last_cell)
		var first_z := clampi(grid.cell_of(z - radius), 0, last_cell)
		var end_z := clampi(grid.cell_of(z + radius), 0, last_cell)
		for gz in range(first_z, end_z + 1):
			for gx in range(first_x, end_x + 1):
				var other: int = grid.cell_head[gz * grid.resolution + gx]
				while other != SpatialGrid.EMPTY:
					if other != i:
						var dx: float = x - bots.pos_x[other]
						var dz: float = z - bots.pos_z[other]
						nearest = minf(nearest, sqrt(dx * dx + dz * dz))
					other = grid.next_index[other]
		if nearest < 1e8:
			measured += 1
			nearest_total += nearest
			closest = minf(closest, nearest)
			if nearest < radius * 0.75:
				overlapping += 1

	print("  neighbours     : %d bots have one within %.2f m, average gap %.2f m, closest %.2f m"
		% [measured, radius, nearest_total / maxi(measured, 1), closest])
	failures += _check("almost nobody stands inside somebody else (%d of %d)"
		% [overlapping, bots.count], overlapping < bots.count * 0.01)

	# Facing is kept by the simulation rather than derived from velocity, so it
	# has to stay a unit vector, survive stopping and turn gradually.
	var worst_length_error := 0.0
	for i in bots.count:
		var length: float = sqrt(bots.face_x[i] * bots.face_x[i] + bots.face_z[i] * bots.face_z[i])
		worst_length_error = maxf(worst_length_error, absf(length - 1.0))
	failures += _check("facing stays a unit vector (worst error %.5f)" % worst_length_error,
		worst_length_error < 0.001)

	var before_x := bots.face_x.duplicate()
	var before_z := bots.face_z.duplicate()
	# Only bots parked on both sides of the tick may be judged. One that stops
	# during it turned while still moving, and one that sets off during it is
	# supposed to turn.
	var parked := PackedInt32Array()
	for i in bots.count:
		if bots.vel_x[i] == 0.0 and bots.vel_z[i] == 0.0:
			parked.push_back(i)

	bots.tick(step, TICKS)

	var worst_turn := 0.0
	for i in bots.count:
		var dot: float = clampf(
			before_x[i] * bots.face_x[i] + before_z[i] * bots.face_z[i], -1.0, 1.0)
		worst_turn = maxf(worst_turn, acos(dot))
	failures += _check("nobody spins round in one tick (worst %.1f deg)" % rad_to_deg(worst_turn),
		worst_turn < deg_to_rad(30.0))

	var drifted := 0
	var still_parked := 0
	for i in parked:
		if bots.vel_x[i] != 0.0 or bots.vel_z[i] != 0.0:
			continue
		still_parked += 1
		if not is_equal_approx(before_x[i], bots.face_x[i]) 				or not is_equal_approx(before_z[i], bots.face_z[i]):
			drifted += 1
	failures += _check("a parked bot keeps its heading (%d of %d drifted)"
		% [drifted, still_parked], drifted == 0)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
