class_name VolcanoEvent
extends WorldEvent
## The mountain erupts: a cluster of vents at the island's summit throws up
## ejecta, then spreads lava that pushes the crowd onto whatever high ground
## the lava has not yet swallowed.
##
## The intended replacement for the retired Zone (see TODO.md, "Отключено и
## на пересмотре"): a boundary that closes in on the crowd, only jagged and
## irregular rather than one circle, because it grows outward from several
## points instead of shrinking around one. Reuses GroundEjecta for the burst
## and the crater floor shader for the lava itself, rather than inventing new
## techniques for either half.
##
## Owns no state itself. Triggering it hands the eruption's ejecta and lava
## pools to the event manager directly (adopt_visual — a burst and a pool
## have nobody to kill by themselves) and a VolcanoEruption to grow the lava
## and do the killing (adopt, the simulation clock).

## How many vents open at once. Few enough that each pool is still
## individually visible before they merge into one lake.
const VENT_COUNT := 4

## How far a vent may land from the summit, in metres. Close enough together
## that the eruption reads as one mountainside tearing open, not several
## unrelated craters scattered across the map.
const VENT_SPREAD := 50.0
const VENT_ATTEMPTS := 6

## Candidates tried for the summit. Higher than SafeZoneEvent's own
## _high_ground(): that only wants decent high ground to put a wall around,
## this is meant to be the actual highest point on the island.
const SUMMIT_CANDIDATES := 24

## Final lava radius per vent, as a share of the map, so the eruption keeps
## its bite whatever MAP_SIZE becomes. At VENT_SPREAD apart, four pools at
## this radius have merged into one lake well before the event ends.
const FINAL_RADIUS_SHARE := 0.11
const SPREAD_SECONDS := 40.0

## Ejecta burst radius per vent, as a share of that vent's final lava radius.
const EJECTA_RADIUS_SHARE := 0.35
const SHAKE_STRENGTH := 0.55


func id() -> StringName:
	return &"volcano"


## params: "x"/"z" to place the summit, "vents" for how many, "radius" for
## the final lava radius per vent, "seconds" for how long it takes to reach
## it. All optional, so trigger("volcano") on its own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var rng := events.rng()

	var summit: Vector2
	if params.has("x") and params.has("z"):
		summit = Vector2(float(params["x"]), float(params["z"]))
	else:
		summit = _find_summit(world, rng)

	var vent_count := int(params.get("vents", VENT_COUNT))
	if vent_count <= 0:
		push_error("VolcanoEvent: needs at least one vent, got %d." % vent_count)
		return ""
	var final_radius := float(params.get("radius", GameConfig.MAP_SIZE * FINAL_RADIUS_SHARE))
	if final_radius <= 0.0:
		push_error("VolcanoEvent: radius must be positive, got %f." % final_radius)
		return ""
	var seconds := float(params.get("seconds", SPREAD_SECONDS))
	if seconds <= 0.0:
		push_error("VolcanoEvent: seconds must be positive, got %f." % seconds)
		return ""

	# Two eruptions at once would each be growing lava the other has no idea
	# about. Refusing is better than two lava fronts silently double-counting
	# the same bots.
	for child in events.get_children():
		if child is VolcanoEruption and not child.is_queued_for_deletion():
			push_error("VolcanoEvent: the mountain is already erupting.")
			return ""

	var vents := _scatter_vents(world, rng, summit, vent_count)

	var pools: Array[LavaPool] = []
	for vent in vents:
		var burst_at := Vector3(vent.x, world.get_height(vent.x, vent.y), vent.y)
		events.adopt_visual(GroundEjecta.create(burst_at, final_radius * EJECTA_RADIUS_SHARE, rng,
			world.get_height))
		var pool := LavaPool.create(vent, rng, world.get_height)
		if pool != null:
			events.adopt_visual(pool)
			pools.append(pool)

	events.shake(Vector3(summit.x, world.get_height(summit.x, summit.y), summit.y),
		final_radius * vents.size(), SHAKE_STRENGTH)

	var eruption := VolcanoEruption.start(events.bots, vents, pools, final_radius, seconds,
		func(line: String) -> void: events.report(&"volcano", line))
	if eruption == null:
		return ""
	events.adopt(eruption)

	return "Volcano erupts: %d vents, lava to r%dm over %ds" % [
		vents.size(), roundi(final_radius), roundi(seconds)]


## The highest of a generous handful of random land points. Cheap on purpose,
## the same reasoning SafeZoneEvent's own version of this search already
## uses: this is height lookups picking somewhere good, not a search for the
## true global maximum.
func _find_summit(world: World, rng: RandomNumberGenerator) -> Vector2:
	var best := world.random_land_point(rng)
	var best_height := world.get_height(best.x, best.y)
	for i in SUMMIT_CANDIDATES - 1:
		var point := world.random_land_point(rng)
		var height := world.get_height(point.x, point.y)
		if height > best_height:
			best = point
			best_height = height
	return best


## Vents scattered near the summit rather than stacked on top of each other.
## Always includes the summit itself as the first vent, so an eruption never
## comes up with fewer than one even if every scattered attempt lands in
## the water.
func _scatter_vents(world: World, rng: RandomNumberGenerator, summit: Vector2,
		count: int) -> PackedVector2Array:
	var vents := PackedVector2Array()
	vents.append(summit)
	for _n in count - 1:
		for _attempt in VENT_ATTEMPTS:
			var angle := rng.randf() * TAU
			var distance := rng.randf() * VENT_SPREAD
			var point := summit + Vector2(cos(angle), sin(angle)) * distance
			if world.is_walkable(point.x, point.y):
				vents.append(point)
				break
	return vents
