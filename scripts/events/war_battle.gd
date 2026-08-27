class_name WarBattle
extends Node
## Two teams walking at each other until one of them is gone.
##
## Runs on the **simulation** clock, like the flood and the zone: who is
## fighting whom, and who is winning, decides who dies, so it has to follow
## from the tick rather than from the frame rate. Pausing holds the armies
## still, and the speed ladder carries the fight along with everything else.
##
## Owns no visuals. Two clumps of team colour converging and thinning out is
## the whole shot; there is nothing here for a camera to be shown that the
## crowd is not already doing by itself.

## How close two knights have to be for BotManager to count them as fighting.
## Close enough to read as blades touching rather than a chase.
const MELEE_RANGE := 2.0

## How often stragglers are pointed at the enemy's current position again:
## bots that arrived at a stale rally point, or that just won a local fight,
## would otherwise sit on the normal wandering AI until its own dwell timer
## picked a random target and walked them off the battlefield. Short enough
## that a knight takes at most one wander leg before being recalled.
const REGROUP_SECONDS := 2.0

var _bots: BotManager
var _team_a := 0
var _team_b := 0
var _damage_per_second := 0.0
var _regroup_timer := 0.0
var _killed := 0
var _on_report := Callable()


## Starts team_a against team_b. Both must currently have someone alive, or
## there is nothing to fight and nobody to march.
static func start(bots: BotManager, team_a: int, team_b: int,
		damage_per_second: float, on_report: Callable) -> WarBattle:
	if bots == null:
		push_error("WarBattle: needs a crowd.")
		return null
	if team_a == team_b:
		push_error("WarBattle: needs two different teams, got %d twice." % team_a)
		return null
	if damage_per_second <= 0.0:
		push_error("WarBattle: needs positive damage, got %f." % damage_per_second)
		return null
	if _team_alive(bots, team_a) == 0 or _team_alive(bots, team_b) == 0:
		push_error("WarBattle: team %d or team %d has nobody left to fight with."
			% [team_a, team_b])
		return null

	var war := WarBattle.new()
	war._bots = bots
	war._team_a = team_a
	war._team_b = team_b
	war._damage_per_second = damage_per_second
	war._on_report = on_report
	return war


func _ready() -> void:
	_send_marchers()


## One simulation step. Returns false once one side has been wiped out.
func advance(delta: float) -> bool:
	_killed += _bots.resolve_combat(_team_a, _team_b, MELEE_RANGE, _damage_per_second, delta)

	_regroup_timer += delta
	if _regroup_timer >= REGROUP_SECONDS:
		_regroup_timer -= REGROUP_SECONDS
		_send_marchers()

	var alive_a := _team_alive(_bots, _team_a)
	var alive_b := _team_alive(_bots, _team_b)
	if alive_a > 0 and alive_b > 0:
		_report("War %d v %d: %d dead, %d v %d left" % [_team_a, _team_b, _killed, alive_a, alive_b])
		return true

	_report(_final_line(alive_a, alive_b))
	queue_free()
	return false


func _final_line(alive_a: int, alive_b: int) -> String:
	if alive_a == 0 and alive_b == 0:
		return "War %d v %d: wiped each other out, %d dead" % [_team_a, _team_b, _killed]
	var winner := _team_a if alive_a > 0 else _team_b
	var loser := _team_b if alive_a > 0 else _team_a
	return "War: team %d wiped out team %d, %d dead" % [winner, loser, _killed]


## Points anyone free to be redirected at wherever the enemy's survivors
## currently are. send_to() already refuses anyone fighting or in the air, so
## this can be called over the whole crowd without checking state here first.
func _send_marchers() -> void:
	var alive_a := _team_alive(_bots, _team_a)
	var alive_b := _team_alive(_bots, _team_b)
	if alive_a == 0 or alive_b == 0:
		return
	var centre_a := _centroid(_bots, _team_a)
	var centre_b := _centroid(_bots, _team_b)
	for i in _bots.count:
		if _bots.alive[i] == 0:
			continue
		if _bots.team[i] == _team_a:
			_bots.send_to(i, centre_b.x, centre_b.y)
		elif _bots.team[i] == _team_b:
			_bots.send_to(i, centre_a.x, centre_a.y)


static func _team_alive(bots: BotManager, team_id: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.team[i] == team_id:
			n += 1
	return n


## Where a team's survivors are, on average. Aiming everyone at the enemy's
## centre of mass rather than at an individual target is what turns "walk
## towards" into two armies converging instead of one bot chasing another.
static func _centroid(bots: BotManager, team_id: int) -> Vector2:
	var sx := 0.0
	var sz := 0.0
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.team[i] == team_id:
			sx += bots.pos_x[i]
			sz += bots.pos_z[i]
			n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(sx / n, sz / n)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
