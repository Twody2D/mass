class_name Earthquake
extends Node
## The ground keeps tearing for DURATION seconds instead of once and being
## done — the owner watched a real run and asked for the quake to actually
## last, and for the scars to be real pits, not marks on top of undisturbed
## ground.
##
## Unlike the earthquake's own first version (everything happened once,
## synchronously, inside EarthquakeEvent.fire()), this owns an ongoing
## sim-clock loop the same way Monster/Kraken/Tornado do:
## EarthquakeEvent.fire() only builds the first rift, so pressing the key
## still feels instant, then hands the rest of the 30 seconds to this object
## via EventManager.adopt(). No singleton guard, unlike those three — an
## earthquake is not one character with an identity, so nothing stops two
## overlapping (the original version already allowed retriggering it
## freely, and there was no complaint about that to fix).
##
## Every strike carves real depth into World's own heightmap
## (World.carve_rift()) rather than faking a hole with a decal on top of it
## — get_height() reads straight off that same array, so every other system
## already sees the real, lower ground for free. Fissure is unchanged: it
## still just colours whatever ground is there when it is built, which is
## now the floor of a real pit instead of undisturbed terrain.
##
## Removes itself from the simulation after DURATION, but every rift it
## tore stays exactly as permanent as the very first version's did —
## World._rift_segments and the carved heightmap are never cleared short of
## a fresh generate().

## How long the ground keeps tearing. TODO.md asked for "30 секунд".
const DURATION := 30.0
## How often a fresh rift opens somewhere new. ~45 strikes over DURATION —
## raised from the first version's 3.5 s, then again from 2.0 s to a third of
## that, after two separate real-run reports both asked for it to hit
## faster: "почти непрерывно", then explicitly "в раза 3 быстрее".
const STRIKE_INTERVAL_SECONDS := 2.0 / 3.0

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
## Metres of real depth World.carve_rift() cuts at the centreline. Shallow
## enough next to TERRAIN_HEIGHT-scale hills that it reads as a crack in the
## ground rather than a canyon, deep enough to leave an unmistakable pit —
## a person standing at its lip should not be able to see the far side's
## floor.
const CARVE_DEPTH := 5.0
const SHAKE_STRENGTH := 0.6

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()
var _on_effect := Callable()

var _elapsed := 0.0
var _strike_timer := 0.0
var _strikes := 0
var _killed_total := 0


## Starts a quake at `at` (the first rift's forced starting point — the rest
## of its path, and every later strike, comes from the seeded stream) and
## tears it open immediately, so triggering the event still feels instant.
static func start(world: World, bots: BotManager, at: Vector2, rng: RandomNumberGenerator,
		on_report: Callable, on_shake: Callable, on_effect: Callable) -> Earthquake:
	if world == null or bots == null:
		push_error("Earthquake: needs a world and a crowd.")
		return null
	if rng == null:
		push_error("Earthquake: needs a generator.")
		return null

	var quake := Earthquake.new()
	quake._world = world
	quake._bots = bots
	quake._rng = rng
	quake._on_report = on_report
	quake._on_shake = on_shake
	quake._on_effect = on_effect
	quake._strike(at)
	return quake


## One simulation step. Returns false once DURATION has run out — see the
## class doc for why that does not undo anything this already did.
func advance(delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= DURATION:
		return false
	_strike_timer += delta
	if _strike_timer >= STRIKE_INTERVAL_SECONDS:
		_strike_timer -= STRIKE_INTERVAL_SECONDS
		_strike(_world.random_land_point(_rng))
	return true


## Tears one jagged rift open at `at`: kills whoever is standing on it,
## blocks the path permanently, carves it into the real terrain, and drops
## a Fissure to colour the new pit's floor.
func _strike(at: Vector2) -> void:
	_strikes += 1
	var path := _build_path(at, _rng)
	var killed := 0
	for i in path.size() - 1:
		var a := path[i]
		var b := path[i + 1]
		killed += _kill_along(a, b)
		_world.add_rift_barrier(a, b, HALF_WIDTH)
	_world.carve_rift(path, HALF_WIDTH, CARVE_DEPTH)
	_killed_total += killed

	# path can now be just the start point on its own — see _build_path()'s
	# own note — if the very first step would already have crossed the
	# coast. Fissure.create() needs at least two points to draw a ribbon
	# along; a rift that never opened has nothing to draw.
	if _on_effect.is_valid() and path.size() >= 2:
		_on_effect.call(Fissure.create(path, HALF_WIDTH, _world.get_height, _rng))
	if _on_shake.is_valid():
		_on_shake.call(Vector3(at.x, _world.get_height(at.x, at.y), at.y), SHAKE_STRENGTH)

	_report("Earthquake: rift %d torn open near (%d, %d), %d killed (%d total)"
		% [_strikes, roundi(at.x), roundi(at.y), killed, _killed_total])


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


## A jagged walk of up to SEGMENTS_PER_RIFT segments from `start`: a random
## heading to begin, then each further segment turns by up to MAX_TURN from
## the last — the same "cheap, correlated wobble instead of independent
## noise" reasoning Crater's own edge jitter already uses, just walked along
## a line instead of sampled around a circle.
##
## Stops the instant a step would land in water rather than walking through
## it regardless — found on a real run: `start` is only ever guaranteed to
## be land, not far from the coast, and an unconstrained 275 m walk crosses
## it easily. carve_rift() clamps its own floor to water_level + 0.1, so a
## segment that crossed the coast was not digging a pit under the sea, it
## was pushing the seabed *up* to just above the waterline — a ridge poking
## through the flat ocean plane, the "hole" the owner actually saw. A rift
## that stops at the shoreline instead is shorter on that side, not longer
## on the wrong side of it.
func _build_path(start: Vector2, rng: RandomNumberGenerator) -> PackedVector2Array:
	var path := PackedVector2Array()
	path.append(start)
	var heading := rng.randf() * TAU
	var here := start
	for _i in SEGMENTS_PER_RIFT:
		heading += rng.randf_range(-MAX_TURN, MAX_TURN)
		var next := here + Vector2(cos(heading), sin(heading)) * SEGMENT_LENGTH
		if _world.get_height(next.x, next.y) <= _world.water_level:
			break
		here = next
		path.append(here)
	return path


## Kills whoever is within KILL_RADIUS of the segment a-b, measuring against
## the segment itself rather than either endpoint — the same point-to-
## segment distance World.is_walkable() now checks for the barrier this
## segment becomes.
func _kill_along(a: Vector2, b: Vector2) -> int:
	var killed := 0
	var radius_squared := KILL_RADIUS * KILL_RADIUS
	var ab := b - a
	var length_squared := ab.length_squared()
	for i in _bots.count:
		if _bots.alive[i] == 0:
			continue
		var p := Vector2(_bots.pos_x[i], _bots.pos_z[i])
		var closest := a
		if length_squared >= 0.0001:
			var t := clampf((p - a).dot(ab) / length_squared, 0.0, 1.0)
			closest = a + ab * t
		if p.distance_squared_to(closest) <= radius_squared and _bots.kill(i):
			killed += 1
	return killed
