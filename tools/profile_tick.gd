extends Node
## Where the simulation tick actually goes, phase by phase.
##
## Two things this tool got wrong for a long time and now does not:
##
## It called _decide() and _move() directly and never advanced _time. Dwell is
## stored as a deadline against that clock, so no bot ever decided it wanted to
## be somewhere else and the whole crowd stood still. It was reporting the cost
## of ten thousand knights standing in a field, which is about two thirds of the
## real one.
##
## And it reported means. On a laptop the same deterministic tick measures 15 ms
## on one run and 43 ms on the next, with the crowd in a bit-identical state, so
## a mean is a measure of what else the machine was doing. Medians are reported
## instead, with the worst sample alongside to show how noisy the run was.
##
## **Measure one crowd size per process.** This machine throttles: a pure
## arithmetic loop that touches nothing measures 66 ms at the start of a process
## and 219 ms after three hundred rendered frames, for identical work. Whatever
## is measured second in a process reads high through no fault of its own. Pass
## --count=10000 to measure just one, which is the only way to compare two
## numbers honestly.

const COUNTS := [5000, 10000]
## Ticks run before measuring, so the crowd is walking rather than standing
## where it spawned. Dwell is staggered up to MAX_DWELL, so this has to cover it.
const WARMUP := 120
const SAMPLES := 100


func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var step: float = GameConfig.SIMULATION_TICK_SECONDS

	var wanted := COUNTS
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--count="):
			wanted = [arg.substr(8).to_int()]
	if wanted.size() > 1:
		print("note: measuring %s in one process. The later one reads high; pass" % [wanted])
		print("      --count=N to measure a single size in a cold process.")

	for n in wanted:
		main.rebuild(GameConfig.DEFAULT_MAP_SEED, n)
		var tick := 0
		while tick < WARMUP:
			bots.tick(step, tick)
			tick += 1

		var decide := PackedFloat32Array()
		var move := PackedFloat32Array()
		var grid := PackedFloat32Array()
		var resolve := PackedFloat32Array()
		var whole := PackedFloat32Array()
		for s in SAMPLES:
			# Exactly what tick() does, with the clock advanced the same way, so
			# the phases add up to the thing being measured.
			var a := Time.get_ticks_usec()
			bots._time += step
			bots._decide(tick)
			var b := Time.get_ticks_usec()
			bots._move(step)
			var c := Time.get_ticks_usec()
			bots._grid.rebuild(bots.pos_x, bots.pos_z, bots.count, bots.alive)
			bots._grid_resolution = bots._grid.resolution
			bots._grid_inverse_cell = bots._grid.inverse_cell_size()
			bots._grid_half = bots._grid.half_extent()
			var d := Time.get_ticks_usec()
			bots._resolve_overlaps()
			var e := Time.get_ticks_usec()
			decide.append(b - a)
			move.append(c - b)
			grid.append(d - c)
			resolve.append(e - d)
			whole.append(e - a)
			tick += 1

		var walking := 0
		for i in bots.count:
			if bots.state[i] == BotManager.State.MOVING:
				walking += 1

		print("%6d bots: decide %5.2f  move %5.2f  grid %5.2f  resolve %6.2f  = %6.2f ms median"
			% [n, _median(decide), _median(move), _median(grid), _median(resolve),
				_median(whole)])
		print("        worst sample %.2f ms, %d of %d walking, %.1f%% of the 20 Hz budget"
			% [_worst(whole), walking, bots.count, _median(whole) / 50.0 * 100.0])

		# How crowded is the worst cell? Separation cost goes up with the square
		# of local density, so this is the number that would explain a spike.
		var counts := {}
		for i in bots.count:
			var cx := bots._grid.cell_of(bots.pos_x[i])
			var cz := bots._grid.cell_of(bots.pos_z[i])
			var key := cz * bots._grid.resolution + cx
			counts[key] = counts.get(key, 0) + 1
		var worst := 0
		var total := 0
		for k in counts:
			worst = maxi(worst, counts[k])
			total += counts[k]
		print("        occupied cells %d, worst cell holds %d, average %.2f"
			% [counts.size(), worst, float(total) / counts.size()])
	get_tree().quit()


func _median(samples: PackedFloat32Array) -> float:
	var sorted := samples.duplicate()
	sorted.sort()
	@warning_ignore("integer_division")
	var middle := sorted.size() / 2
	return sorted[middle] / 1000.0


func _worst(samples: PackedFloat32Array) -> float:
	var top := 0.0
	for v in samples:
		top = maxf(top, v)
	return top / 1000.0
