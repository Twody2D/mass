extends Node

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var step: float = GameConfig.SIMULATION_TICK_SECONDS

	for n in [5000, 10000]:
		main.rebuild(GameConfig.DEFAULT_MAP_SEED, n)
		var decide := 0
		var move := 0
		var grid := 0
		var resolve := 0
		for t in 100:
			var a := Time.get_ticks_usec()
			bots._decide(t)
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
			decide += b - a
			move += c - b
			grid += d - c
			resolve += e - d
		print("%6d bots: decide %5.2f  move %5.2f  grid %5.2f  resolve %6.2f  ms/tick"
			% [n, decide / 100000.0, move / 100000.0, grid / 100000.0, resolve / 100000.0])

		# How crowded is the worst cell?
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
