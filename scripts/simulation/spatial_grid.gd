class_name SpatialGrid
extends RefCounted
## Uniform grid over the map, so a bot can find the handful of bots near it
## without looking at the other nine thousand.
##
## Any system that needs "who is close to whom" goes through this. Checking
## every pair is O(N squared), which at ten thousand bots is a hundred million
## comparisons per tick and is exactly what this project forbids.
##
## Built as a linked list rather than a counting sort: a head index per cell and
## a next index per bot. That trades a prefix sum over every cell, which is a
## GDScript loop over hundreds of thousands of entries, for a clear that is a
## single memset in C++ and a build that is one pass over the bots. It is what
## makes small cells affordable.

const EMPTY := -1

var cell_size := 1.0
var resolution := 1

## Index of the first bot in each cell, or EMPTY. Row major, cz * resolution + cx.
var cell_head := PackedInt32Array()
## Index of the next bot in the same cell, or EMPTY.
var next_index := PackedInt32Array()

var _half_extent := 0.0


## Sizes the grid to a square map. The cell must be at least as wide as the
## largest query radius, or a three by three scan will miss neighbours.
func configure(map_size: float, requested_cell_size: float) -> void:
	if map_size <= 0.0 or requested_cell_size <= 0.0:
		push_error("SpatialGrid: map size and cell size must be positive, got %f and %f."
			% [map_size, requested_cell_size])
		return
	resolution = maxi(1, int(ceil(map_size / requested_cell_size)))
	cell_size = map_size / float(resolution)
	_half_extent = map_size * 0.5
	cell_head.resize(resolution * resolution)


## Refills the grid from current positions. Cheap enough to run every tick,
## which is the only way the contents can be trusted.
func rebuild(pos_x: PackedFloat32Array, pos_z: PackedFloat32Array, count: int) -> void:
	cell_head.fill(EMPTY)
	if next_index.size() != count:
		next_index.resize(count)

	var last := resolution - 1
	for i in count:
		var cx := clampi(int((pos_x[i] + _half_extent) / cell_size), 0, last)
		var cz := clampi(int((pos_z[i] + _half_extent) / cell_size), 0, last)
		var cell := cz * resolution + cx
		# Push onto the front of the cell's list.
		next_index[i] = cell_head[cell]
		cell_head[cell] = i


func cell_of(coordinate: float) -> int:
	return clampi(int((coordinate + _half_extent) / cell_size), 0, resolution - 1)


## Cell size chosen so a query of `radius` never spans more than a two by two
## block: a circle of radius r has a bounding box of 2r, which fits in two cells
## of that width whichever way it straddles them. Halves the lookups against the
## usual three by three scan.
static func cell_size_for_radius(radius: float) -> float:
	return radius * 2.0


## Inverse cell size and half extent, exposed so hot loops can do the arithmetic
## inline instead of paying for a call per bot.
func inverse_cell_size() -> float:
	return 1.0 / cell_size


func half_extent() -> float:
	return _half_extent
