class_name SafeZone
extends Node
## A circle that shrinks, hurts whoever is left outside it, and sends them
## running for the middle.
##
## Runs on the **simulation** clock, like the flood and for the same reason:
## where the boundary is decides who is taking damage, so it has to follow from
## the tick rather than from the frame rate. Pausing holds the wall still, and
## the speed ladder carries it.
##
## Owns its wall. The ring is a child node, so freeing the zone takes the
## boundary off the screen with it, and there is no second place tracking
## whether a wall belongs to a zone that has already finished.

## How often the crowd is swept, in simulation seconds. The wall moves a few
## metres a second, so nobody's situation changes between sweeps; running this
## every tick would be four times the cost for nothing anyone can see.
const SWEEP_SECONDS := 0.2

## Where a frightened bot is sent, as a share of the current radius. Not the
## centre: ten thousand knights aimed at one point pack into a heap, and
## separation costs go up with the square of how tightly packed they are. The
## share is also the head start — by the time a bot has run to 0.85 of the
## radius it was given, the wall has come in far enough that it is standing
## just inside rather than just outside.
const FLEE_TO_SHARE := 0.85

const WALL_COLOR := Color(0.45, 0.85, 1.0)

var _world: World
var _bots: BotManager
var _centre := Vector2.ZERO
var _from := 0.0
var _to := 0.0
var _seconds := 1.0
var _elapsed := 0.0
var _sweep_timer := 0.0
var _damage_per_second := 0.0
var _killed := 0
var _ring: ZoneRing
var _on_report := Callable()


## Starts a zone closing from `from_radius` to `to_radius` around `centre`, over
## `seconds` of simulation time. `on_report` is called with a line for the
## overlay each sweep, so the panel counts down while it happens instead of
## saying nothing for a minute.
static func start(world: World, bots: BotManager, centre: Vector2,
			from_radius: float, to_radius: float, seconds: float,
			damage_per_second: float, on_report: Callable) -> SafeZone:
	if world == null or bots == null:
		push_error("SafeZone: needs a world and a crowd.")
		return null
	if seconds <= 0.0:
		push_error("SafeZone: needs a positive duration, got %f." % seconds)
		return null
	if to_radius <= 0.0 or from_radius <= to_radius:
		push_error("SafeZone: the zone has to shrink, got %f down to %f."
			% [from_radius, to_radius])
		return null
	if damage_per_second <= 0.0:
		push_error("SafeZone: needs positive damage, got %f." % damage_per_second)
		return null

	var zone := SafeZone.new()
	zone._world = world
	zone._bots = bots
	zone._centre = centre
	zone._from = from_radius
	zone._to = to_radius
	zone._seconds = seconds
	zone._damage_per_second = damage_per_second
	zone._on_report = on_report
	zone._ring = ZoneRing.create(centre, from_radius, WALL_COLOR, world.get_height)
	return zone


func _ready() -> void:
	if _ring != null:
		add_child(_ring)


## One simulation step. Returns false once the zone has finished closing.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	## Linear in the radius, so the wall moves at a constant speed. Linear in the
	## area would start slowly and finish in a rush, which is the wrong way round:
	## the crowd needs to see early that it has to move.
	var radius := lerpf(_from, _to, t)
	if _ring != null:
		_ring.set_radius(radius)

	_sweep_timer += delta
	if _sweep_timer >= SWEEP_SECONDS:
		_sweep(radius, _sweep_timer)
		_sweep_timer = 0.0

	if t < 1.0:
		return true

	## One last sweep at the final radius, so the count in the report is the one
	## the boundary actually ended on.
	_sweep(radius, maxf(_sweep_timer, delta))
	_report("Zone closed at r%dm: %d dead, %d inside"
		% [roundi(_to), _killed, _inside_count(radius)])
	queue_free()
	return false


## Hurts whoever is outside the boundary and sends them for the middle.
##
## `elapsed` is the real time since the last sweep rather than SWEEP_SECONDS, so
## the damage does not depend on how the sweeps happened to line up with the
## end of the event.
func _sweep(radius: float, elapsed: float) -> void:
	var amount := _damage_per_second * elapsed
	if amount <= 0.0:
		return
	var outer_squared := radius * radius
	var run_to := radius * FLEE_TO_SHARE
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
		## Anyone already running has somewhere to be, and anyone in the air has no
		## say. The stale target is not a problem: it was set at 0.85 of a radius
		## that has since come in, so a bot arrives just inside the wall rather
		## than behind it, and whatever the wall catches again is idle by then.
		var state: int = _bots.state[i]
		if state != idle and state != moving:
			continue
		## One square root for the bots that need it, none for the ones inside.
		var distance := sqrt(distance_squared)
		_bots.flee(i, -dx, -dz, distance - run_to)
	_killed += dead
	_report("Zone r%dm: %d outside, %d dead" % [roundi(radius), outside, _killed])


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
