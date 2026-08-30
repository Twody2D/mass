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
##
## The mountain itself is not built here: IslandGenerator bakes a real cone
## and crater into the heightmap for every seed (World.volcano_center()), so
## an eruption fills an actual bowl and spills down an actual slope instead
## of growing puddles on whatever ordinary terrain happened to be tallest.
## This only lights the vents already sitting in that crater.

## How many vents open at once. Few enough that each pool is still
## individually visible before they merge into one lake.
const VENT_COUNT := 4

## How far a vent may land from the crater's centre, in metres. Kept inside
## IslandGenerator's own crater bowl (VOLCANO_CRATER_RADIUS) so every vent
## opens inside the real crater instead of on the outer flank — the lava
## fills the bowl first and only then spills down the mountainside, which is
## the point of having a real crater there at all.
const VENT_SPREAD := IslandGenerator.VOLCANO_CRATER_RADIUS * 0.75
const VENT_ATTEMPTS := 6

## Ash thrown up per vent the instant it opens, reusing MushroomCloud as-is —
## the same "soft blobs, not particles" object the meteor's own impact uses,
## just smaller. Not part of VolcanoEruption's ongoing state: one burst per
## vent at ignition is the moment worth punctuating, not a loop to maintain
## for the whole 40 seconds the lava takes to spread.
const ASH_BURST_SHARE := 0.55

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
		summit = world.volcano_center()

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
	var vent_heights := PackedFloat32Array()

	var pools: Array[LavaPool] = []
	for vent in vents:
		var vent_height := world.get_height(vent.x, vent.y)
		vent_heights.append(vent_height)
		var burst_at := Vector3(vent.x, vent_height, vent.y)
		var ejecta_radius := final_radius * EJECTA_RADIUS_SHARE
		events.adopt_visual(GroundEjecta.create(burst_at, ejecta_radius, rng, world.get_height))
		events.adopt_visual(MushroomCloud.create(burst_at, ejecta_radius * ASH_BURST_SHARE, rng))
		var pool := LavaPool.create(vent, final_radius, rng, world.get_height)
		if pool != null:
			events.adopt_visual(pool)
			pools.append(pool)

	events.shake(Vector3(summit.x, world.get_height(summit.x, summit.y), summit.y),
		final_radius * vents.size(), SHAKE_STRENGTH)

	var eruption := VolcanoEruption.start(events.bots, vents, vent_heights, pools, final_radius,
		seconds, rng, func(line: String) -> void: events.report(&"volcano", line),
		events.adopt_visual)
	if eruption == null:
		return ""
	events.adopt(eruption)

	return "Volcano erupts: %d vents, lava to r%dm over %ds" % [
		vents.size(), roundi(final_radius), roundi(seconds)]


## Vents scattered inside the crater rather than stacked on top of each
## other. Always includes the centre itself as the first vent, so an
## eruption never comes up with fewer than one even if every scattered
## attempt somehow fails is_walkable().
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
