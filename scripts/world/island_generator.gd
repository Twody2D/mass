class_name IslandGenerator
extends RefCounted
## Turns a seed into an island heightmap. Pure data: no nodes, no meshes, no
## engine state, so it can be run and checked on its own.
##
## Shape parameters live here rather than in GameConfig because they only mean
## anything to this algorithm. GameConfig owns the values several systems share
## (map size, resolution, water level, peak height).

## Noise frequency per grid cell. Lower means larger, smoother landforms.
const NOISE_FREQUENCY := 0.010
const NOISE_OCTAVES := 5
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
const ISLAND_BASE := 0.55

## How far noise pushes elevation above and below ISLAND_BASE.
const RELIEF := 0.55

## Mountains. Ridged noise, 1 - |fbm|, creases where plain fBm makes blobs, and
## a crease is what reads as a mountain range rather than as a lumpy field. This
## is the layer that gives the island somewhere to run to: without it the map is
## a smooth dome, and a crowd fleeing a flood has no high ground to aim at.
##
## Faded by the coastal mask a second time, so the shore stays beaches and the
## mountains stay inland.
const RIDGE_FREQUENCY := 0.010
const RIDGE_OCTAVES := 3
const RIDGE_WEIGHT := 0.65
## Above 1 sharpens the ridges into peaks; at 1 they are rounded hills.
const RIDGE_SHARPNESS := 2.5

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

## How many heightmap cells at the very edge of the grid are forced to sea,
## no matter what the noise or the volcano computed there. FALLOFF_END = 1.0
## already means the *ordinary* terrain is always at or below zero on the
## last row/column, but nothing enforced that for an *additive* landform on
## top of it — VOLCANO_RADIUS is chosen to stay short of half_extent with a
## margin, yet a bad seed's jitter still put walkable land on the grid's
## last column once (back when the volcano's own position had jitter to be
## bad with), and random_land_point()'s own jitter (see World.gd) can push a
## sample half a cell past whatever the grid itself calls land, which is how
## a spawned or fleeing knight ended up standing outside half_extent(). A
## hard sea band at the border is the one fix that holds regardless of where
## any current or future landform lands.
const EDGE_SEA_CELLS := 4

## The volcano: one guaranteed landform baked into every island, not a rare
## outcome of the noise. VolcanoEvent used to hunt for "the highest of two
## dozen random samples" and erupt whatever ordinary hill that happened to be
## — which is why an eruption looked like a few puddles appearing on a random
## slope instead of a mountain. This adds an explicit cone-with-a-crater on
## top of the normal terrain, in real metres, independent of TERRAIN_HEIGHT:
## a real landmark that is there from the first frame, not only during an
## eruption.
##
## Height at the rim, in metres — well over the ordinary ridge cap (140 m),
## so it reads as the island's one real mountain. A first attempt at moving
## the volcano to the map's centre raised this to 340 m with a 380 m radius
## to match, on the reasoning that a centred landform could afford a bigger
## footprint — a real screenshot showed the mountain had swallowed the
## entire island edge to edge instead of leaving anything to "generate
## around" it. VOLCANO_RADIUS below is the number that actually matters for
## that; this is sized to keep the flank near 50° at that radius rather than
## being picked first.
const VOLCANO_HEIGHT := 230.0
## Footprint radius: the cone reaches zero added height by here, blending
## into whatever the ordinary terrain was doing at that distance. Kept well
## under a typical island's own radius (roughly 300-400 m depending on the
## coastline noise) so the mountain reads as *a* landmark at the island's
## centre — with a real coastline, beaches and ordinary rolling ground
## around it — rather than *being* the island.
const VOLCANO_RADIUS := 200.0
## Crater bowl radius, measured from the very centre.
const VOLCANO_CRATER_RADIUS := 40.0
## How far below the rim the crater floor sits.
const VOLCANO_CRATER_DEPTH := 55.0


## Where the volcano's crater sits: dead centre of the map, every seed. The
## owner asked for the mountain to be *the* centre of the island's geography
## — everything else generated around it — not a landform tucked off to one
## side. An earlier version placed it a few hundred metres off-centre
## specifically to avoid disturbing (0, 0), which several tools (notably
## verify_reaction.gd's "fling away from the origin" test) had quietly
## assumed was ordinary terrain; that assumption no longer holds by design,
## so the tools were fixed to stop relying on it instead of the mountain
## being moved back off-centre to dodge them.
##
## Kept as a function of the seed (trivial as that function now is) rather
## than a bare constant so callers do not need to know it is fixed — nothing
## outside this file should assume the centre is always (0, 0), only that
## this function says where it is.
static func volcano_center(_map_seed: int) -> Vector2:
	return Vector2.ZERO


## Added height at world position (x, z) from the volcano centred at
## `center`: a bowl at the very middle rising to a rim at
## VOLCANO_CRATER_RADIUS, then a cone flank falling to zero at VOLCANO_RADIUS.
## Zero outside the footprint, so it never disturbs terrain far from it.
##
## The flank is a plain straight line from rim to base, not a curve: a
## power curve steeper than 1 (the first version's choice) is at its
## steepest exactly at the rim, which is precisely where a knight — or a
## verify_reaction.gd fling arc — is most likely to be standing right after
## an eruption starts. A constant slope the whole way down reads as an
## actual mountainside instead of a spike, and is the same ~45° everywhere,
## not a knife edge at the top.
static func _volcano_offset(x: float, z: float, center: Vector2) -> float:
	var distance := Vector2(x, z).distance_to(center)
	if distance >= VOLCANO_RADIUS:
		return 0.0
	var rim := VOLCANO_HEIGHT
	if distance <= VOLCANO_CRATER_RADIUS:
		var floor_height := rim - VOLCANO_CRATER_DEPTH
		var t := distance / VOLCANO_CRATER_RADIUS
		return lerpf(floor_height, rim, smoothstep(0.0, 1.0, t))
	var t2 := (distance - VOLCANO_CRATER_RADIUS) / (VOLCANO_RADIUS - VOLCANO_CRATER_RADIUS)
	return lerpf(rim, 0.0, t2)


## Builds a resolution x resolution heightmap in metres, row-major (index
## gz * resolution + gx). Values above 0 are land, values below are seabed.
##
## `bake_volcano` defaults to true so a direct call (verify_world.gd's own
## heightmap check, in particular) keeps exercising the mountain without
## having to know the flag exists. World.gd itself always passes its own
## `bake_volcano` export explicitly — the ordinary island (scenes/main.tscn)
## sets it false, the dedicated volcano map (scenes/volcano.tscn) sets it
## true. See ARCHITECTURE.md, "Volcano as its own map".
##
## `flat` drops the relief and ridge noise entirely, leaving only the
## radial falloff mask — a smooth dome tapering to the shore, no hills or
## creases at all. Built for the boss arena (scenes/boss_arena.tscn): a
## fight with Monster or Kraken is easier to shoot and easier for the
## crowd to actually reach when nothing on the ground gets in the way.
static func generate_heightmap(map_seed: int, resolution: int, peak_height: float,
		map_size: float, bake_volcano: bool = true, flat: bool = false) -> PackedFloat32Array:
	if resolution < 2:
		push_error("IslandGenerator: resolution must be at least 2, got %d." % resolution)
		return PackedFloat32Array()
	if peak_height <= 0.0:
		push_error("IslandGenerator: peak_height must be positive, got %f." % peak_height)
		return PackedFloat32Array()
	if map_size <= 0.0:
		push_error("IslandGenerator: map_size must be positive, got %f." % map_size)
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
	# Third stream, offset again: the ridges must not line up with either the
	# relief or the coastline.
	var ridge := FastNoiseLite.new()
	ridge.seed = map_seed + 104729
	ridge.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	ridge.frequency = RIDGE_FREQUENCY
	ridge.fractal_type = FastNoiseLite.FRACTAL_FBM
	ridge.fractal_octaves = RIDGE_OCTAVES

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
	var shore_scale := 1.0 / (ISLAND_BASE + RELIEF + RIDGE_WEIGHT - SHORE_THRESHOLD)
	var half_extent := map_size * 0.5
	var volcano_at := volcano_center(map_seed)

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
			# 1 - |noise| folds the field at zero, turning its zero crossings into
			# creases. Raised to a power the creases sharpen into peaks.
			var creased := pow(1.0 - absf(ridge.get_noise_2d(float(gx), float(gz))),
				RIDGE_SHARPNESS)
			var elevation: float
			if flat:
				elevation = mask * ISLAND_BASE
			else:
				elevation = mask * (ISLAND_BASE + RELIEF * relief + RIDGE_WEIGHT * creased * mask)
			var height := (elevation - SHORE_THRESHOLD) * shore_scale * peak_height
			# Added in real metres, after the shore rescale, so the volcano's
			# own height does not get folded back down by shore_scale along
			# with everything else — it is meant to dwarf peak_height, not to
			# be relative to it.
			if bake_volcano:
				height += _volcano_offset(dx * half_extent, dz * half_extent, volcano_at)
			height = maxf(height, -SEABED_DEPTH)
			var edge_distance := mini(mini(gx, gz), mini(resolution - 1 - gx, resolution - 1 - gz))
			if edge_distance < EDGE_SEA_CELLS:
				height = -SEABED_DEPTH
			heights[row + gx] = height

	return heights
