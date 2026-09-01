class_name SupplyScramble
extends Node
## One crate: the crowd runs for it, and once enough of them are pressed
## together around it, a handful get shoved out of the crush — sometimes
## hurt, always sent flying a short way, the same knockback a meteor throws
## people with, only softer. The first bot to actually reach it claims a
## reward: BotManager.buff() and a TrophyWeapon to show for it — the
## redesign this event needed once the owner called a crush with no winner
## "давка без победителя и без зрелищного момента."
##
## Runs on the **simulation** clock, like every other event with a landing:
## when the crate has come down and the crush starts decides who gets hurt,
## so it has to follow the tick rather than the frame rate. Pausing holds the
## crowd and the crush still, and the speed ladder carries both along.
##
## Owns no visuals of its own. The falling crate is decoration on its own
## clock — see CrateDrop — because unlike a meteor, the landing point here
## never depends on where anything is on the way down. The trophy is
## decoration too, but it has to track a specific bot rather than sit still,
## so SupplyDropEvent builds and adopts it through the same on_trophy
## callback shape Monster/Kraken already use for on_shake — this file never
## needs to know EventManager exists.

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

## How close counts as "actually reached the crate," tighter than the crush
## radius below — this is a claim, not just being caught up in the crowd
## around it. Whoever is closest here the first time landing is checked wins;
## there is only ever one, on purpose, the same "one clear winner is a
## spectacle, several buffed bots in a crowd is not" reasoning that kept
## Tornado to a single funnel rather than several at once.
const WINNER_RADIUS := 5.0
## How long the buff (and the trophy weapon showing it) lasts.
const BUFF_SECONDS := 25.0

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
var _winner := -1
var _on_report := Callable()
var _on_trophy := Callable()


## Starts a crate coming down on `point`. `rng` drives who gets shoved each
## sweep — shared with the rest of the event stream, so a seed still decides
## everything about a run. `on_trophy` is called `(winner_index: int,
## seconds: float)` the moment someone claims it, so the caller can build and
## adopt the TrophyWeapon this file does not know how to hand to the scene.
static func start(bots: BotManager, world: World, point: Vector2, rng: RandomNumberGenerator,
		on_report: Callable, on_trophy: Callable) -> SupplyScramble:
	if bots == null or rng == null:
		push_error("SupplyScramble: needs a crowd and a random stream.")
		return null

	var drop := SupplyScramble.new()
	drop._bots = bots
	drop._world = world
	drop._point = point
	drop._rng = rng
	drop._on_report = on_report
	drop._on_trophy = on_trophy
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
		if _winner == -1:
			_check_winner()
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


## Checked every tick from landing until somebody actually reaches the
## crate: the closest living bot within WINNER_RADIUS claims it, gets
## buffed, and gets a trophy to show for it. Cheap to check every tick
## rather than only on a sweep — bots_within() over a 5 m radius costs
## nothing next to the tick it already runs inside, and a winner claimed a
## sweep-interval late would read as the event hesitating.
func _check_winner() -> void:
	var nearby := _bots.bots_within(_point.x, _point.y, WINNER_RADIUS)
	if nearby.is_empty():
		return

	var best := -1
	var best_distance_squared := INF
	for i in nearby:
		if _bots.alive[i] == 0:
			continue
		var dx := _bots.pos_x[i] - _point.x
		var dz := _bots.pos_z[i] - _point.y
		var distance_squared := dx * dx + dz * dz
		if distance_squared < best_distance_squared:
			best = i
			best_distance_squared = distance_squared
	if best == -1:
		return

	_winner = best
	_bots.buff(_winner, BUFF_SECONDS)
	if _on_trophy.is_valid():
		_on_trophy.call(_winner, BUFF_SECONDS)
	_report("Bot %d claims the crate at (%d, %d) — a legendary weapon and a burst of speed"
		% [_winner, roundi(_point.x), roundi(_point.y)])


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
