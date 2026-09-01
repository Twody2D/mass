class_name SafeZone
extends Node
## A safe circle that jumps to a fresh random spot every JUMP_INTERVAL_SECONDS
## instead of smoothly shrinking toward one point — the redesign TODO.md asked
## for once Volcano's advancing lava front took over the "boundary closes in
## on a fixed centre" story this event used to tell, mechanically identical to
## Flood.
##
## A jump does the opposite of what a shrinking wall does: instead of everyone
## converging on one shrinking safe patch, most of the crowd is suddenly
## *outside* a new one somewhere else on the island and has to scramble there —
## structurally the same "boundary decides who is taking damage" contract, but
## the crowd's problem every JUMP_INTERVAL_SECONDS is "where is safe now,"
## not "how much closer is safe getting."
##
## Runs on the **simulation** clock, like the flood and for the same reason:
## the boundary decides who is taking damage, so it has to follow from the
## tick rather than the frame rate. Pausing holds the wall still, and the
## speed ladder carries it.
##
## Owns its wall. The ring is a child node, so freeing the zone takes the
## boundary off the screen with it.

## How often the crowd is swept, in simulation seconds — cheap enough that a
## sweep between jumps costs nothing worth saving on.
const SWEEP_SECONDS := 0.2

## Where a frightened bot is sent, as a share of the current radius. Not the
## centre: ten thousand knights aimed at one point pack into a heap, and
## separation costs go up with the square of how tightly packed they are.
const FLEE_TO_SHARE := 0.85

const WALL_COLOR := Color(0.45, 0.85, 1.0)

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _centre := Vector2.ZERO
var _radius := 0.0
var _radius_start := 0.0
var _radius_end := 0.0
var _jump_count := 0
var _jump_index := 0
var _jump_interval := 0.0
var _jump_timer := 0.0
var _sweep_timer := 0.0
var _damage_per_second := 0.0
var _killed := 0
var _ring: ZoneRing
var _on_report := Callable()
var _on_shake := Callable()


## Starts a zone at `centre`, `radius_start` wide, jumping `jump_count - 1`
## more times (so `jump_count` total positions are ever safe), tightening
## linearly to `radius_end` by the last one, `jump_interval` seconds apart.
## `on_report` gets a line for the overlay each sweep; `on_shake` is called
## `(at, strength)` on every jump, so the camera can feel the wall arrive
## somewhere new the same way it feels a meteor land.
static func start(world: World, bots: BotManager, rng: RandomNumberGenerator,
			centre: Vector2, radius_start: float, radius_end: float,
			jump_count: int, jump_interval: float, damage_per_second: float,
			on_report: Callable, on_shake: Callable) -> SafeZone:
	if world == null or bots == null:
		push_error("SafeZone: needs a world and a crowd.")
		return null
	if rng == null:
		push_error("SafeZone: needs a generator.")
		return null
	if radius_end <= 0.0 or radius_start < radius_end:
		push_error("SafeZone: needs a start radius at least as big as the end, got %f down to %f."
			% [radius_start, radius_end])
		return null
	if jump_count < 1:
		push_error("SafeZone: needs at least one position, got %d jumps." % jump_count)
		return null
	if jump_interval <= 0.0:
		push_error("SafeZone: needs a positive interval, got %f." % jump_interval)
		return null
	if damage_per_second <= 0.0:
		push_error("SafeZone: needs positive damage, got %f." % damage_per_second)
		return null

	var zone := SafeZone.new()
	zone._world = world
	zone._bots = bots
	zone._rng = rng
	zone._centre = centre
	zone._radius = radius_start
	zone._radius_start = radius_start
	zone._radius_end = radius_end
	zone._jump_count = jump_count
	zone._jump_interval = jump_interval
	zone._damage_per_second = damage_per_second
	zone._on_report = on_report
	zone._on_shake = on_shake
	zone._ring = ZoneRing.create(centre, radius_start, WALL_COLOR, world.get_height)
	return zone


func _ready() -> void:
	if _ring != null:
		add_child(_ring)


## One simulation step. Returns false once the zone has jumped for the last
## time and its final position has run its own full interval.
func advance(delta: float) -> bool:
	_jump_timer += delta
	if _jump_timer >= _jump_interval:
		_jump_timer -= _jump_interval
		_jump_index += 1
		if _jump_index >= _jump_count:
			_sweep(maxf(_sweep_timer, delta))
			_report("Zone vanishes: %d dead, %d inside at the end"
				% [_killed, _inside_count(_radius)])
			queue_free()
			return false
		_jump()

	_sweep_timer += delta
	if _sweep_timer >= SWEEP_SECONDS:
		_sweep(_sweep_timer)
		_sweep_timer = 0.0
	return true


## Picks a fresh centre and a tighter radius, the same linear "constant speed
## across the whole event" reasoning the old shrinking wall used, just
## sampled once per jump instead of every tick.
func _jump() -> void:
	_centre = _world.random_land_point(_rng)
	var t := float(_jump_index) / float(_jump_count - 1) if _jump_count > 1 else 1.0
	_radius = lerpf(_radius_start, _radius_end, t)
	if _ring != null:
		_ring.set_centre(_centre)
		_ring.set_radius(_radius)
	if _on_shake.is_valid():
		_on_shake.call(Vector3(_centre.x, _world.get_height(_centre.x, _centre.y), _centre.y), 0.4)
	_report("Zone jumps to (%d, %d), r%dm" % [roundi(_centre.x), roundi(_centre.y), roundi(_radius)])


## Hurts whoever is outside the boundary and sends them for the middle. Same
## shape as the old shrinking wall's own sweep — see SafeZoneEvent's history
## in TODO.md — just against a centre that can jump out from under the crowd
## rather than one that only ever gets closer to wherever they already are.
func _sweep(elapsed: float) -> void:
	var amount := _damage_per_second * elapsed
	if amount <= 0.0:
		return
	var outer_squared := _radius * _radius
	var run_to := _radius * FLEE_TO_SHARE
	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var outside := 0
	var dead := 0
	for i in _bots.count:
		if _bots.alive[i] == 0:
			continue
		var dx := _bots.pos_x[i] - _centre.x
		var dz := _bots.pos_z[i] - _centre.y
		var distance_squared := dx * dx + dz * dz
		if distance_squared <= outer_squared:
			continue
		outside += 1
		if _bots.damage(i, amount):
			dead += 1
			continue
		var state: int = _bots.state[i]
		if state != idle and state != moving:
			continue
		var distance := sqrt(distance_squared)
		_bots.flee(i, -dx, -dz, distance - run_to)
	_killed += dead
	_report("Zone r%dm at (%d, %d): %d outside, %d dead"
		% [roundi(_radius), roundi(_centre.x), roundi(_centre.y), outside, _killed])


func _inside_count(radius: float) -> int:
	var outer_squared := radius * radius
	var inside := 0
	for i in _bots.count:
		if _bots.alive[i] == 0:
			continue
		var dx := _bots.pos_x[i] - _centre.x
		var dz := _bots.pos_z[i] - _centre.y
		if dx * dx + dz * dz <= outer_squared:
			inside += 1
	return inside


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
