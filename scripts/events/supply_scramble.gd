class_name SupplyScramble
extends Node
## One crate: the crowd runs for it, and once enough of them are pressed
## together around it, a handful get shoved out of the crush — sometimes
## hurt, always sent flying a short way, the same knockback a meteor throws
## people with, only softer.
##
## Runs on the **simulation** clock, like every other event with a landing:
## when the crate has come down and the crush starts decides who gets hurt,
## so it has to follow the tick rather than the frame rate. Pausing holds the
## crowd and the crush still, and the speed ladder carries both along.
##
## Owns no visuals. The falling crate is decoration on its own clock — see
## CrateDrop — because unlike a meteor, the landing point here never depends
## on where anything is on the way down.

## Kept equal to CrateDrop.FALL_SECONDS, so the crowd's idea of "landed" and
## the crate's own fall agree. Not read from CrateDrop directly: the two
## classes do not know about each other, on purpose — the crate cannot touch
## a bot, and this cannot touch a mesh.
const FALL_SECONDS := 4.0

## How far the announcement reaches. Wide: the whole point of a supply drop
## is a crowd converging from all over, not a local scuffle nobody notices.
const GATHER_RADIUS := 220.0

## A crush is whoever is standing within SCRUM_RADIUS of the crate once there
## are at least SCRUM_CROWD of them; short of that it is just a queue.
const SCRUM_RADIUS := 6.0
const SCRUM_CROWD := 8

## How long the crush keeps working over the crate once it has landed, and
## how often it is resolved. Slower than the zone or the flood: nobody is
## dying to a clock here, just occasionally getting shoved.
const SCRUM_SECONDS := 18.0
const SWEEP_SECONDS := 0.5
const SHOVED_PER_SWEEP := 3

## Gentler than a meteor's knockback on purpose: this is a shove out of a
## crowd, not a blast. See MeteorEvent.KNOCKBACK_SPEED for the comparison.
const SHOVE_SPEED := 9.0
const SHOVE_LIFT := 4.0

const HURT_CHANCE := 0.35
const HURT_AMOUNT := 18.0

var _bots: BotManager
var _world: World
var _rng: RandomNumberGenerator
var _point := Vector2.ZERO
var _elapsed := 0.0
var _sweep_timer := 0.0
var _landed := false
var _sent := 0
var _shoved := 0
var _hurt := 0
var _killed := 0
var _on_report := Callable()


## Starts a crate coming down on `point`. `rng` drives who gets shoved each
## sweep — shared with the rest of the event stream, so a seed still decides
## everything about a run.
static func start(bots: BotManager, world: World, point: Vector2, rng: RandomNumberGenerator,
		on_report: Callable) -> SupplyScramble:
	if bots == null or rng == null:
		push_error("SupplyScramble: needs a crowd and a random stream.")
		return null

	var drop := SupplyScramble.new()
	drop._bots = bots
	drop._world = world
	drop._point = point
	drop._rng = rng
	drop._on_report = on_report
	return drop


func _ready() -> void:
	_send_runners()


## One simulation step. Returns false once the crush has run its course.
func advance(delta: float) -> bool:
	_elapsed += delta
	if not _landed and _elapsed >= FALL_SECONDS:
		_landed = true
		_report("Crate down at (%d, %d): %d running for it"
			% [roundi(_point.x), roundi(_point.y), _sent])

	if _landed:
		_sweep_timer += delta
		if _sweep_timer >= SWEEP_SECONDS:
			_sweep_timer -= SWEEP_SECONDS
			_scrum()
		if _elapsed >= FALL_SECONDS + SCRUM_SECONDS:
			_report("Crate at (%d, %d) settled: %d shoved, %d hurt, %d killed"
				% [roundi(_point.x), roundi(_point.y), _shoved, _hurt, _killed])
			queue_free()
			return false

	return true


## Sends everyone in reach running for the crate. Called once: the point
## never moves, so there is nothing later worth re-aiming a straggler at that
## this call did not already offer it.
##
## The route is asked for once, not once per runner — the same reasoning
## WarBattle's own _send_marchers() uses, and for the same reason: a crate
## that draws over a thousand runners at once must not turn into a thousand
## independent region searches. One runner's own position stands in for
## "roughly where the crowd converging on this crate is coming from"; this
## only ever needs to catch open water between the gathering crowd and the
## crate, not route each runner individually.
func _send_runners() -> void:
	var nearby := _bots.bots_within(_point.x, _point.y, GATHER_RADIUS)
	if nearby.is_empty():
		return
	var waypoint := _point
	if _world != null:
		var from := Vector2(_bots.pos_x[nearby[0]], _bots.pos_z[nearby[0]])
		waypoint = _world.route_waypoint(from, _point)
	for i in nearby:
		if _bots.gather_at(i, waypoint.x, waypoint.y):
			_sent += 1


## Shoves a handful of whoever is pressed into the crush out of it, once
## there are enough of them for it to be a crush rather than a queue.
func _scrum() -> void:
	var nearby := _bots.bots_within(_point.x, _point.y, SCRUM_RADIUS)
	if nearby.size() < SCRUM_CROWD:
		return

	var shoved_now := 0
	while shoved_now < SHOVED_PER_SWEEP and nearby.size() > 0:
		var pick := _rng.randi() % nearby.size()
		var i: int = nearby[pick]
		nearby.remove_at(pick)
		if not _bots.fling(i, _point.x, _point.y, SHOVE_SPEED, SHOVE_LIFT):
			continue
		_shoved += 1
		shoved_now += 1
		if _rng.randf() < HURT_CHANCE:
			_hurt += 1
			if _bots.damage(i, HURT_AMOUNT):
				_killed += 1


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
