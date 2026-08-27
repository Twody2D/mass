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

## How far a frightened bot runs inland, in metres.
const FLEE_DISTANCE := 140.0

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

	# scare() sends a bot away from a point, so the point to run from is one
	# further out to sea than the bot is. On an island shaped like a dome that
	# direction is downhill, and the opposite of it is the only way that helps.
	# It is an approximation: a bot can still be sent into a valley, and the
	# shore guard in _move() is what stops it walking into the water there.
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
		if _bots.scare(i, _bots.pos_x[i] * 2.0, _bots.pos_z[i] * 2.0, FLEE_DISTANCE):
			running += 1

	_report("Flood +%dm: %d drowned, %d running" % [
		roundi(_world.water_level - _from), _drowned, running])


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
