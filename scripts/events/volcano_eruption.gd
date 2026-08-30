class_name VolcanoEruption
extends Node
## Lava spreading from every vent at once until it reaches its final radius,
## killing whoever it reaches and scaring whoever is next.
##
## Runs on the **simulation** clock, like the flood and the zone: where the
## lava front is decides who dies, so it has to follow from the tick rather
## than from the frame rate. Pausing holds it still, and the speed ladder
## carries it along with everything else.
##
## Does not own its pools. Each LavaPool is adopted straight onto EventManager
## (adopt_visual) by VolcanoEvent, the same way Crater outlives the meteor
## that made it — a cooled pool is meant to still be there once this node has
## finished growing it and freed itself, so this only holds references, not
## parentage.

const SWEEP_SECONDS := 0.2

## How far past a pool's own kill radius a bot starts running from it, in
## metres — the same shape FloodTide's PANIC_MARGIN gives the rising sea.
const PANIC_MARGIN := 12.0
const FLEE_DISTANCE := 55.0

## How often a fresh burst of ash goes up while the lava is still spreading.
## A single burst at ignition (VolcanoEvent's own GroundEjecta/MushroomCloud
## pair) read as one crack in the ground, not an ongoing eruption — the
## owner watched a real run and wanted it to actually keep erupting.
## Reusing MushroomCloud on a timer is the same "measure before building
## infrastructure" call the rest of this event already makes: it is already
## the "soft blobs, not particles" object the meteor's own impact uses, and
## a real column of rising smoke would need a dedicated class for what a
## repeated burst already reads as from any distance a camera would use.
const PLUME_INTERVAL_SECONDS := 2.5
const PLUME_RADIUS_SHARE := 0.5

var _bots: BotManager
var _vents := PackedVector2Array()
## Ground height at each vent, in the same order as _vents — measured once
## by VolcanoEvent rather than carrying a World reference in here just to
## ask it again every plume.
var _vent_heights := PackedFloat32Array()
var _pools: Array[LavaPool] = []
var _to := 0.0
var _seconds := 1.0
var _elapsed := 0.0
var _sweep_timer := 0.0
var _plume_timer := 0.0
var _killed := 0
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_visual := Callable()


## Starts the lava growing towards `final_radius` around every vent, over
## `seconds` of simulation time. `on_report` is called with a line for the
## overlay each sweep, so the panel counts up while it happens; `on_visual`
## adopts each ash burst the same way VolcanoEvent already adopts the
## ignition ones, so this stays a source of decoration, never an owner of it.
static func start(bots: BotManager, vents: PackedVector2Array, vent_heights: PackedFloat32Array,
		pools: Array[LavaPool], final_radius: float, seconds: float,
		rng: RandomNumberGenerator, on_report: Callable, on_visual: Callable) -> VolcanoEruption:
	if bots == null:
		push_error("VolcanoEruption: needs a crowd.")
		return null
	if vents.is_empty():
		push_error("VolcanoEruption: needs at least one vent.")
		return null
	if final_radius <= 0.0:
		push_error("VolcanoEruption: needs a positive final radius, got %f." % final_radius)
		return null
	if seconds <= 0.0:
		push_error("VolcanoEruption: needs a positive duration, got %f." % seconds)
		return null

	var eruption := VolcanoEruption.new()
	eruption._bots = bots
	eruption._vents = vents
	eruption._vent_heights = vent_heights
	eruption._pools = pools
	eruption._to = final_radius
	eruption._seconds = seconds
	eruption._rng = rng
	eruption._on_report = on_report
	eruption._on_visual = on_visual
	return eruption


## One simulation step. Returns false once every pool has reached its final
## radius.
func advance(delta: float) -> bool:
	_elapsed += delta
	var t := clampf(_elapsed / _seconds, 0.0, 1.0)
	var radius := lerpf(0.0, _to, t)
	for pool in _pools:
		if is_instance_valid(pool):
			pool.set_radius(radius)

	_sweep_timer += delta
	if _sweep_timer >= SWEEP_SECONDS:
		_sweep_timer -= SWEEP_SECONDS
		_sweep(radius)

	# Ash keeps venting for as long as there is lava still spreading — an
	# eruption in progress, not a single crack that happened once at the
	# start. Stops on its own once t reaches 1.0 and this node frees itself
	# below; no separate "stop erupting" signal needed.
	_plume_timer += delta
	if _plume_timer >= PLUME_INTERVAL_SECONDS:
		_plume_timer -= PLUME_INTERVAL_SECONDS
		_spawn_plume()

	if t < 1.0:
		return true

	# One last sweep at the final radius, so nobody is left standing in lava
	# because the front grew past them between sweeps.
	_sweep(radius)
	_report("Lava settled at r%dm per vent: %d killed" % [roundi(radius), _killed])
	queue_free()
	return false


## One fresh burst of ash at a random vent, the same MushroomCloud object
## VolcanoEvent already lights at ignition, just smaller and repeated —
## see the class doc for why this reuses it instead of a dedicated column.
func _spawn_plume() -> void:
	if not _on_visual.is_valid() or _vents.is_empty():
		return
	var i := _rng.randi() % _vents.size()
	var vent := _vents[i]
	var at := Vector3(vent.x, _vent_heights[i], vent.y)
	_on_visual.call(MushroomCloud.create(at, _to * PLUME_RADIUS_SHARE, _rng))


## Kills whoever any vent's lava has reached and frightens whoever is next.
## A bot in range of two overlapping vents is simply handled twice — cheap at
## the handful of vents an eruption has, and the second call just points it
## further away from whichever vent is nearer.
func _sweep(radius: float) -> void:
	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var running := 0
	for vent in _vents:
		for i in _bots.bots_within(vent.x, vent.y, radius):
			if _bots.kill(i):
				_killed += 1
		for i in _bots.bots_within(vent.x, vent.y, radius + PANIC_MARGIN):
			if _bots.alive[i] == 0:
				continue
			var state: int = _bots.state[i]
			if state != idle and state != moving:
				continue
			if _bots.scare(i, vent.x, vent.y, FLEE_DISTANCE):
				running += 1
	_report("Lava r%dm: %d killed, %d running" % [roundi(radius), _killed, running])


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
