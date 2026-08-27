class_name FloodTide
extends Node
## A sea that is rising. Moves the water line, drowns whoever it reaches, and
## sends whoever it is about to reach running uphill.
##
## Runs on the **simulation** clock, not on frame time: where the water is
## decides who dies, so it has to follow from the tick rather than from the
## frame rate. Pausing holds the sea still and the speed ladder carries it.
##
## Has no visuals of its own. The rising ocean plane is the visual, and it
## belongs to World, which is the one place that knows where the water is.

## How often the crowd is swept, in simulation seconds. The water rises about a
## metre a second, so a bot's fate does not change between sweeps; running this
## every tick would be four times the cost for nothing visible.
const SWEEP_SECONDS := 0.2

## How far above the water a bot starts running, in metres. Wide enough that the
## coast empties ahead of the sea rather than after it.
const PANIC_MARGIN := 5.0

## How far a frightened bot runs uphill in one go, in metres. Deliberately no
## further than the slope was measured over (World.UPHILL_STENCIL is 64 m): the
## direction is only true locally, and a bot sent 140 m up a 64 m hill arrives
## on the far side of it, going down. It re-picks on the next sweep it is caught
## by, so the crowd climbs in short hops rather than in one blind sprint.
const FLEE_DISTANCE := 55.0

var _world: World
var _bots: BotManager
var _from := 0.0
var _to := 0.0
var _seconds := 1.0
var _elapsed := 0.0
var _sweep_timer := 0.0
var _drowned := 0
var _on_report := Callable()


## Starts the sea rising from wherever it is now to `to_level`, over `seconds`
## of simulation time. `on_report` is called with a line for the overlay each
## time the crowd is swept, so the panel counts up while it happens instead of
## saying nothing for half a minute.
static func start(world: World, bots: BotManager, to_level: float, seconds: float,
		on_report: Callable) -> FloodTide:
	if world == null or bots == null:
		push_error("FloodTide: needs a world and a crowd.")
		return null
	if seconds <= 0.0:
		push_error("FloodTide: needs a positive duration, got %f." % seconds)
		return null
	if to_level <= world.water_level:
		push_error("FloodTide: %f is not above the current water line at %f."
			% [to_level, world.water_level])
		return null

	var tide := FloodTide.new()
	tide._world = world
	tide._bots = bots
	tide._from = world.water_level
	tide._to = to_level
	tide._seconds = seconds
	tide._on_report = on_report
	return tide


## One simulation step. Returns false once the sea has reached its level.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	# Linear, because a flood is a constant inflow. Easing it would look like
	# the sea changing its mind.
	_world.set_water_level(lerpf(_from, _to, t))

	_sweep_timer += delta
	if _sweep_timer >= SWEEP_SECONDS:
		_sweep_timer -= SWEEP_SECONDS
		_sweep()

	if t < 1.0:
		return true

	# One last sweep at the final level, so nobody is left standing in the sea
	# because the tide ran out between sweeps.
	_sweep()
	_report("Flood settled at +%dm: %d drowned" % [roundi(_to - _from), _drowned])
	queue_free()
	return false


## Drowns whoever the water has reached and frightens whoever is next.
func _sweep() -> void:
	_drowned += _bots.drown()

	# Uphill, measured from the ground, not guessed from the map centre. The
	# first version sent everyone towards the middle of the island on the theory
	# that a dome is highest there; it is not. The falloff that makes the island
	# an island is flat inside a fifth of its radius, so the middle is whatever
	# the noise made it, quite often a lake — and that is where the crowd
	# obediently ran, into the water it was fleeing.
	var edge := _world.water_level + PANIC_MARGIN
	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var running := 0
	for i in _bots.count:
		if _bots.alive[i] == 0 or _bots.pos_y[i] > edge:
			continue
		var state: int = _bots.state[i]
		# Anyone already running has somewhere to be, and anyone in the air has
		# no say. Re-scaring the same bot every sweep would also cost far more
		# than the first one did.
		if state != idle and state != moving:
			continue
		var up := _world.uphill(_bots.pos_x[i], _bots.pos_z[i])
		if up == Vector2.ZERO:
			# Standing somewhere genuinely flat. Away from the middle of the sea
			# is the best guess left, and it is only ever the fallback.
			if _bots.scare(i, 0.0, 0.0, FLEE_DISTANCE):
				running += 1
			continue
		if _bots.flee(i, up.x, up.y, FLEE_DISTANCE):
			running += 1

	_report("Flood +%dm: %d drowned, %d running" % [
		roundi(_world.water_level - _from), _drowned, running])


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
