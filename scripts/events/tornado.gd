class_name Tornado
extends Node3D
## A funnel that wanders the island on no route anyone could predict, tossing
## whoever it passes over — TODO.md item 53. One instance of a Tornado is one
## funnel; TornadoSwarm is what fires several of these at once so the event
## reads as a "world-scale trial" rather than one lone rope of dust — this
## file itself does not know it is one of a crowd.
##
## Unlike Monster and Kraken it is not a boss: nothing kills it and nothing
## fights back, so it has no health. It just runs for DURATION and then blows
## itself out, the same finite-lifetime contract MeteorProjectile and the
## other adopt()-ed effects already use (queue_free() and return false, not
## "stay forever" like Monster's fallen-boss landmark).
##
## Reuses rather than invents: BotManager.fling() is exactly "picked up and
## thrown," the same primitive the meteor's blast already throws survivors
## with, and the funnel itself is BlobMesh puffs on smoke.gdshader, the same
## soft-blob material MushroomCloud already carries.
##
## Runs on the simulation clock, the same two-part advance(delta)/render(alpha)
## split as Monster and Kraken: where it is decides who gets thrown, so that
## has to be reproducible from the seed, not from the frame rate.
##
## Two things make a swarm of these read as real weather instead of one
## funnel copy-pasted several times: every dimension that matters for how
## dangerous and how big a funnel looks scales with `_size`, so a swarm is a
## family of different funnels, not clones — and `_move()` no longer walks a
## dead-straight line to its target, it wanders about that line on its own
## per-instance phase, the same "cheap sine, not a real vortex" trick already
## trusted for camera shake and every other cosmetic wobble in this file.

## Ground to cloud base. Tall next to a knight (2.4 m) on purpose — this is
## meant to be seen from anywhere on the island, the same reasoning the
## meteor's blast radius is a share of the map rather than a fixed size.
const HEIGHT := 220.0
const GROUND_RADIUS := 14.0
const TOP_RADIUS := 60.0
## How the funnel's radius grows with height: >1 keeps it a narrow "rope" for
## most of its height and flares it out sharply near the top, closer to how
## a real funnel cloud reads than a straight cone would.
const FLARE_POWER := 1.4

## The narrow danger zone: close enough to actually be picked up. Wider than
## GROUND_RADIUS on purpose — being grazed by the wall of the funnel is
## enough to be caught, not just standing dead centre under it.
const PICKUP_RADIUS := 24.0
## Toss speeds handed straight to BotManager.fling(), the same call the
## meteor's blast uses on its survivors. More lift than the meteor's own
## KNOCKBACK_LIFT (16): a tornado is defined by picking things up, not just
## pushing them over.
const TOSS_HORIZONTAL := 24.0
const TOSS_VERTICAL := 30.0

## Wider ring that only frightens. Panic is what makes the crowd read the
## funnel as a threat before it actually reaches them, the same reasoning
## Monster's own PANIC_RADIUS exists outside STOMP_RADIUS for.
const PANIC_RADIUS := 85.0
const FLEE_DISTANCE := 90.0

const SWEEP_SECONDS := 0.2

## Fast and erratic on purpose: this is the one giant that is not trying to
## reach anyone. A short retarget interval to a fresh random point (not a
## living bot the way Monster aims itself) is what makes the path
## unpredictable rather than a beeline — the crowd cannot simply run away
## from where it is heading, because nothing here decides that far ahead
## either.
const SPEED := 15.0
const ARRIVAL_RADIUS := 20.0
const RETARGET_SECONDS := 3.0
const RETARGET_ATTEMPTS := 6

## Sideways drift about the straight line to the current target — see the
## class doc. An amplitude in metres/second, not metres: applied through
## delta like the forward step is, so it stays proportional at any tick rate
## instead of teleporting on a slow frame.
const WOBBLE_AMOUNT := 5.0
const WOBBLE_RATE := 1.7

const DURATION := 32.0
## The share of DURATION spent fading out rather than vanishing outright —
## the same trick MushroomCloud's own COOLING/fade uses, just simpler: one
## alpha ramp instead of a temperature curve, because dust has no fire stage
## to cool from.
const FADE_SHARE := 0.12

## Rings from the ground up, as a share of HEIGHT, and the target arc length
## between neighbouring puffs in a ring — used to size each ring's puffs and
## how many it needs, rather than a hand-tuned count per level, so the rings
## stay covered whatever GROUND_RADIUS/TOP_RADIUS end up being.
const RING_LEVELS := [0.05, 0.2, 0.38, 0.58, 0.8, 1.0]
const RING_SPACING := 11.0
## How fast the lowest ring spins, in radians/second; every ring above it
## spins a little slower, the way real debris close to the ground moves
## faster than the cloud it feeds into. Cheap and periodic, the same kind of
## trick already trusted for camera shake and the meteor's sparks — a real
## fluid sim has no place in a toy-scale event.
const SPIN_BASE := 2.6

const BLOB_SIDES := 10
const BLOB_RINGS := 7
const BLOB_JITTER := 0.24
const BLOB_VARIANTS := 6
const BLOB_MESH_SEED := 0x70de0

const DUST_LOW := Color(0.40, 0.36, 0.30)
const DUST_HIGH := Color(0.58, 0.58, 0.60)

static var _blobs: Array[ArrayMesh] = []

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()

## Scales HEIGHT/GROUND_RADIUS/TOP_RADIUS/PICKUP_RADIUS/PANIC_RADIUS/
## FLEE_DISTANCE directly, and the toss speeds by its square root (a funnel
## twice as wide is not twice as strong a throw) — see start()'s own doc.
## 1.0 reproduces the original single-funnel numbers exactly.
var _size := 1.0
var _height := 0.0
var _ground_radius := 0.0
var _top_radius := 0.0
var _pickup_radius := 0.0
var _panic_radius := 0.0
var _flee_distance := 0.0
var _toss_horizontal := 0.0
var _toss_vertical := 0.0
## Per-instance phase for the sideways wobble in _move() — without it every
## funnel in a swarm would drift the same way at the same moment, reading as
## one shared gust rather than several independent funnels.
var _wobble_phase := 0.0

var _elapsed := 0.0
var _target := Vector2.ZERO
var _retarget_timer := 0.0
var _sweep_timer := 0.0
var _tossed := 0
var _material: ShaderMaterial
var _rings: Array[Node3D] = []
## Where the last two ticks put it, so a frame can be drawn between them —
## see the class doc.
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


## Builds a tornado touching down at `at`, ready to be adopted by the event
## manager. `on_report` is called with a line for the overlay. `size_mult`
## scales this funnel against the others in its swarm — see `_size`'s own
## doc; defaults to 1.0 for a single stand-alone tornado.
static func start(world: World, bots: BotManager, at: Vector2,
		rng: RandomNumberGenerator, on_report: Callable, size_mult: float = 1.0) -> Tornado:
	if world == null or bots == null:
		push_error("Tornado: needs a world and a crowd.")
		return null
	if rng == null:
		push_error("Tornado: needs a generator.")
		return null
	if size_mult <= 0.0:
		push_error("Tornado: size_mult must be positive, got %f." % size_mult)
		return null

	var tornado := Tornado.new()
	tornado._world = world
	tornado._bots = bots
	tornado._rng = rng
	tornado._on_report = on_report
	tornado._target = at
	tornado._size = size_mult
	tornado._height = HEIGHT * size_mult
	tornado._ground_radius = GROUND_RADIUS * size_mult
	tornado._top_radius = TOP_RADIUS * size_mult
	tornado._pickup_radius = PICKUP_RADIUS * size_mult
	tornado._panic_radius = PANIC_RADIUS * size_mult
	tornado._flee_distance = FLEE_DISTANCE * size_mult
	tornado._toss_horizontal = TOSS_HORIZONTAL * sqrt(size_mult)
	tornado._toss_vertical = TOSS_VERTICAL * sqrt(size_mult)
	tornado._wobble_phase = rng.randf() * TAU
	tornado.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	tornado._previous = tornado.position
	tornado._current = tornado.position
	tornado._build(rng)
	tornado._report("A tornado touches down at (%d, %d)" % [roundi(at.x), roundi(at.y)])
	return tornado


## One simulation step. Returns false and frees itself once DURATION has run
## out — a temporary hazard, not a landmark like a fallen boss.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := _elapsed / DURATION
	if t >= 1.0:
		_report("Tornado blows itself out: %d tossed" % _tossed)
		queue_free()
		return false

	_previous = _current
	_move(delta)
	_current = position
	_spin(delta)

	_sweep_timer += delta
	if _sweep_timer >= SWEEP_SECONDS:
		_sweep()
		_sweep_timer = 0.0

	var fade_start := 1.0 - FADE_SHARE
	var alpha := 1.0 if t < fade_start else clampf((1.0 - t) / FADE_SHARE, 0.0, 1.0)
	_material.set_shader_parameter("alpha", alpha)
	return true


## Draws this frame between the last two ticks, the same interpolation
## Monster and MeteorProjectile already use.
func render(alpha: float) -> void:
	position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


## Wanders to a fresh random point on land rather than seeking the crowd —
## see the class doc on why that is what makes the route unpredictable
## instead of a beeline.
func _move(delta: float) -> void:
	_retarget_timer -= delta
	var here := Vector2(position.x, position.z)
	if _retarget_timer <= 0.0 or here.distance_to(_target) <= ARRIVAL_RADIUS:
		_target = _world.random_land_point(_rng)
		_retarget_timer = RETARGET_SECONDS

	var to_target := _target - here
	var length := to_target.length()
	if length < 0.0001:
		return
	var dir := to_target / length
	var step := minf(SPEED * delta, length)
	# Sideways drift perpendicular to the heading — see the class doc. Scaled
	# by delta like the forward step, not the raw sine value, so the funnel
	# actually meanders instead of snapping toward wherever the sine curve
	# currently points.
	var perp := Vector2(-dir.y, dir.x)
	var wobble := sin(_elapsed * WOBBLE_RATE + _wobble_phase) * WOBBLE_AMOUNT * delta
	var nx := position.x + dir.x * step + perp.x * wobble
	var nz := position.z + dir.y * step + perp.y * wobble
	position = Vector3(nx, _world.get_height(nx, nz), nz)


func _spin(delta: float) -> void:
	for i in _rings.size():
		var level: float = RING_LEVELS[i]
		var rate := SPIN_BASE / (1.0 + level * 1.5)
		_rings[i].rotate_y(rate * delta)


## Frightens everyone within PANIC_RADIUS still free to run, and throws
## whoever is inside PICKUP_RADIUS through BotManager.fling() — the same
## primitive the meteor's blast throws survivors with, not a new mechanic.
func _sweep() -> void:
	var here := Vector2(position.x, position.z)
	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING

	for i in _bots.bots_within(here.x, here.y, _panic_radius):
		if _bots.alive[i] == 0:
			continue
		var bot_state: int = _bots.state[i]
		if bot_state == idle or bot_state == moving:
			_bots.scare(i, here.x, here.y, _flee_distance)

	for i in _bots.bots_within(here.x, here.y, _pickup_radius):
		if _bots.alive[i] == 0:
			continue
		if _bots.fling(i, here.x, here.y, _toss_horizontal, _toss_vertical):
			_tossed += 1

	_report("Tornado at (%d, %d): %d tossed so far" % [roundi(here.x), roundi(here.y), _tossed])


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build(rng: RandomNumberGenerator) -> void:
	_material = ShaderMaterial.new()
	_material.shader = load("res://assets/materials/smoke.gdshader")
	_material.set_shader_parameter("tint", Vector3(DUST_LOW.r, DUST_LOW.g, DUST_LOW.b))
	_material.set_shader_parameter("alpha", 1.0)
	_material.set_shader_parameter("glow", 0.0)

	for level in RING_LEVELS.size():
		var share: float = RING_LEVELS[level]
		var radius := lerpf(_ground_radius, _top_radius, pow(share, FLARE_POWER))
		var count := maxi(4, roundi(TAU * radius / RING_SPACING))
		var puff_radius := (TAU * radius / count) * 0.7

		var ring := Node3D.new()
		ring.position.y = _height * share
		add_child(ring)
		_rings.append(ring)

		for i in count:
			var angle := TAU * float(i) / float(count) + rng.randf() * 0.3
			var reach := radius * rng.randf_range(0.92, 1.08)
			var puff := _puff(rng, puff_radius * rng.randf_range(0.85, 1.2), share)
			puff.position = Vector3(sin(angle) * reach,
				rng.randf_range(-puff_radius, puff_radius) * 0.4, cos(angle) * reach)
			ring.add_child(puff)


## One blob of dust: a shared shape, turned to its own angle, tinted by how
## high up its ring is — pale cloud-grey near the top, dark dirt near the
## ground, the same "shade carries height" trick MushroomCloud's stem uses.
func _puff(rng: RandomNumberGenerator, size: float, height_share: float) -> MeshInstance3D:
	var pool := _pool()
	var puff := MeshInstance3D.new()
	puff.mesh = pool[rng.randi() % pool.size()]
	puff.material_override = _material
	puff.rotation = Vector3(rng.randf() * TAU, rng.randf() * TAU, rng.randf() * TAU)
	puff.scale = Vector3.ONE * size
	var shade := DUST_LOW.lerp(DUST_HIGH, height_share)
	puff.set_instance_shader_parameter("shade", Vector3(shade.r, shade.g, shade.b))
	return puff


## The shared blobs, carved the first time a tornado is built. Unit radius:
## size is a scale on the instance, the same pooling MushroomCloud already
## uses so this costs nothing on the second tornado of the session onward.
static func _pool() -> Array[ArrayMesh]:
	if not _blobs.is_empty():
		return _blobs
	for i in BLOB_VARIANTS:
		_blobs.append(BlobMesh.build(1.0, BLOB_MESH_SEED + i, Color.WHITE, Color.WHITE,
			BLOB_SIDES, BLOB_RINGS, BLOB_JITTER, true))
	return _blobs
