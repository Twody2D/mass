class_name IslandGenerator
extends RefCounted
## Turns a seed into an island heightmap. Pure data: no nodes, no meshes, no
## engine state, so it can be run and checked on its own.
##
## Shape parameters live here rather than in GameConfig because they only mean
## anything to this algorithm. GameConfig owns the values several systems share
## (map size, resolution, water level, peak height).

## Noise frequency per grid cell. Lower means larger, smoother landforms.
const NOISE_FREQUENCY := 0.008
const NOISE_OCTAVES := 4
const NOISE_LACUNARITY := 2.0
const NOISE_GAIN := 0.5

## Radial falloff as a fraction of the map half-extent: inside FALLOFF_START the
## island is at full elevation, past FALLOFF_END everything is forced to ocean.
## This is what makes the landmass an island instead of an endless continent.
const FALLOFF_START := 0.20
const FALLOFF_END := 1.0

## Elevation of the island before noise is applied, as a fraction of the range.
## The island is a dome first and noisy second: fBm clusters tightly around its
## midpoint, so using noise alone as the elevation yields a scattering of small
## blobs and an ocean where the middle of the island should be.
const ISLAND_BASE := 0.70

## How far noise pushes elevation above and below ISLAND_BASE.
const RELIEF := 0.60

## Masked elevation below this is ocean. Raising it shrinks the island.
const SHORE_THRESHOLD := 0.35

## The radial falloff on its own yields an almost perfect circle. A second, very
## low frequency noise stretches and shrinks the falloff radius per direction,
## which is what turns the outline into bays and headlands. Distorting the
## radius is far more effective here than distorting the elevation noise.
const COAST_FREQUENCY := 0.006
const COAST_VARIATION := 0.30

## How far the seabed is allowed to drop below the water level, in metres.
## Keeping the seabed strictly below 0 avoids z-fighting with the ocean plane.
const SEABED_DEPTH := 2.0


## Builds a resolution x resolution heightmap in metres, row-major (index
## gz * resolution + gx). Values above 0 are land, values below are seabed.
static func generate_heightmap(map_seed: int, resolution: int, peak_height: float) -> PackedFloat32Array:
	if resolution < 2:
		push_error("IslandGenerator: resolution must be at least 2, got %d." % resolution)
		return PackedFloat32Array()
	if peak_height <= 0.0:
		push_error("IslandGenerator: peak_height must be positive, got %f." % peak_height)
		return PackedFloat32Array()

	var noise := FastNoiseLite.new()
	noise.seed = map_seed
	noise.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	noise.frequency = NOISE_FREQUENCY
	noise.fractal_type = FastNoiseLite.FRACTAL_FBM
	noise.fractal_octaves = NOISE_OCTAVES
	noise.fractal_lacunarity = NOISE_LACUNARITY
	noise.fractal_gain = NOISE_GAIN

	# Offset seed so the coast outline is not correlated with the relief.
	var coast := FastNoiseLite.new()
	coast.seed = map_seed + 7919
	coast.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	coast.frequency = COAST_FREQUENCY
	coast.fractal_type = FastNoiseLite.FRACTAL_NONE

	var heights := PackedFloat32Array()
	heights.resize(resolution * resolution)

	var half := (resolution - 1) * 0.5
	# Rescales the above-shore range onto 0..peak_height, so the highest possible
	# elevation lands exactly on peak_height instead of overshooting it.
	var shore_scale := 1.0 / (ISLAND_BASE + RELIEF - SHORE_THRESHOLD)

	for gz in resolution:
		var row := gz * resolution
		var dz := (gz - half) / half
		for gx in resolution:
			# Noise as signed relief in -1..1 rather than as the elevation itself.
			var relief := noise.get_noise_2d(float(gx), float(gz))
			var dx := (gx - half) / half
			var distance := sqrt(dx * dx + dz * dz)
			# Push the shoreline in and out per direction.
			distance *= 1.0 + COAST_VARIATION * coast.get_noise_2d(float(gx), float(gz))
			var mask := 1.0 - smoothstep(FALLOFF_START, FALLOFF_END, distance)
			var elevation := mask * (ISLAND_BASE + RELIEF * relief)
			var height := (elevation - SHORE_THRESHOLD) * shore_scale * peak_height
			heights[row + gx] = maxf(height, -SEABED_DEPTH)

	return heights
