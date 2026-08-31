class_name EarthquakeEvent
extends WorldEvent
## The ground rips open along a handful of jagged rifts: whoever was
## standing on one falls in, and the rifts themselves are left behind as a
## real obstacle, not just a mark — TODO.md item 52.
##
## Unlike Meteor/Flood/Volcano/Monster/Kraken, this owns no ongoing
## simulation object at all: there is nothing left to decide once the rifts
## have opened, so everything here happens once, synchronously, inside
## fire(). What is adopted afterwards (Fissure, one per rift) is pure
## decoration plus the one thing that is not decoration at all —
## World.add_rift_barrier() makes the same path permanently unwalkable,
## which is what actually splits the crowd. Nothing here needs to know how
## a bot reacts to that: it already rerolls a wander target that fails
## is_walkable(), the same way it already avoids the sea.

## How many separate rifts tear open at once. TODO.md says "разломами" —
## plural — not one straight crack.
const RIFT_COUNT := 3
## How many straight segments make up one rift's jagged path.
const SEGMENTS_PER_RIFT := 5
const SEGMENT_LENGTH := 55.0
## Maximum turn between one segment and the next, radians each way — a
## lightning-bolt path rather than a straight line or a random scribble.
const MAX_TURN := 0.7
## Half-width of the rift, both for the visual ribbon and the barrier that
## makes it impassable.
const HALF_WIDTH := 6.0
## Slightly more forgiving than HALF_WIDTH: someone can be standing at the
## very edge of where the ground is about to open, not just its exact
## centreline.
const KILL_RADIUS := HALF_WIDTH + 3.0
const SHAKE_STRENGTH := 0.6


func id() -> StringName:
	return &"earthquake"


## params: "x"/"z" to force the first rift's starting point (the rest of its
## path, and every other rift, still comes from the seeded stream); "rifts"
## for how many tear open. All optional, so trigger("earthquake") on its
## own works.
func fire(events: EventManager, params: Dictionary) -> String:
	var world := events.world
	var bots := events.bots
	var rng := events.rng()

	var rift_count := int(params.get("rifts", RIFT_COUNT))
	if rift_count <= 0:
		push_error("EarthquakeEvent: needs at least one rift, got %d." % rift_count)
		return ""

	var killed := 0
	var epicenter := Vector2.ZERO
	for n in rift_count:
		var start: Vector2
		if n == 0 and params.has("x") and params.has("z"):
			start = Vector2(float(params["x"]), float(params["z"]))
		else:
			start = world.random_land_point(rng)
		if n == 0:
			epicenter = start

		var path := _build_path(start, rng)
		for i in path.size() - 1:
			var a := path[i]
			var b := path[i + 1]
			killed += _kill_along(bots, a, b, KILL_RADIUS)
			world.add_rift_barrier(a, b, HALF_WIDTH)
		events.adopt_visual(Fissure.create(path, HALF_WIDTH, world.get_height, rng))

	events.shake(Vector3(epicenter.x, world.get_height(epicenter.x, epicenter.y), epicenter.y),
		SEGMENT_LENGTH * SEGMENTS_PER_RIFT * rift_count, SHAKE_STRENGTH)

	return "Earthquake at (%d, %d): %d rifts torn open, %d killed" \
		% [roundi(epicenter.x), roundi(epicenter.y), rift_count, killed]


## A jagged walk of SEGMENTS_PER_RIFT segments from `start`: a random
## heading to begin, then each further segment turns by up to MAX_TURN from
## the last — the same "cheap, correlated wobble instead of independent
## noise" reasoning Crater's own edge jitter already uses, just walked along
## a line instead of sampled around a circle.
func _build_path(start: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var path := PackedVector2Array()
	path.append(start)
	var heading := rng.randf() * TAU
	var here := start
	for _i in SEGMENTS_PER_RIFT:
		heading += rng.randf_range(-MAX_TURN, MAX_TURN)
		here += Vector2(cos(heading), sin(heading)) * SEGMENT_LENGTH
		path.append(here)
	return path


## Kills whoever is within `radius` of the segment a-b, measuring against
## the segment itself rather than either endpoint — the same point-to-
## segment distance World.is_walkable() now checks for the barrier this
## segment becomes. A single pass over every bot, once, at the moment the
## rift opens: the same cost class _collect_land_cells() already pays over
## the heightmap, not a per-tick check.
func _kill_along(bots: BotManager, a: Vector2, b: Vector2, radius: float) -> int:
	var killed := 0
	var radius_squared := radius * radius
	var ab := b - a
	var length_squared := ab.length_squared()
	for i in bots.count:
		if bots.alive[i] == 0:
			continue
		var p := Vector2(bots.pos_x[i], bots.pos_z[i])
		var closest := a
		if length_squared >= 0.0001:
			var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
			closest = a + ab * t
		if p.distance_squared_to(closest) <= radius_squared and bots.kill(i):
			killed += 1
	return killed
