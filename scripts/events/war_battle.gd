class_name WarBattle
extends Node
## Two armies walking at each other until one of them is gone.
##
## "Team" no longer exists as a crowd-wide axis — class (warrior/spearman/
## archer) replaced it, and a class is a role, not a side to fight for. The
## two armies here are `BotManager.war_side` instead: a spatial split (which
## half of the war island a bot spawned on), meaningful only on that
## dedicated map, where every bot gets a side. Both armies still have all
## three classes in them.
##
## Runs on the **simulation** clock, like the flood and the zone: who is
## fighting whom, and who is winning, decides who dies, so it has to follow
## from the tick rather than from the frame rate. Pausing holds the armies
## still, and the speed ladder carries the fight along with everything else.
##
## Two clumps of bots converging from opposite ends of the map and thinning
## out is most of the shot — read through where they start and where they
## meet, not through a team colour, which class already spends on
## something else. The one visual this file does own: forwarding a sampled
## few of each tick's real archer contributions (BotManager.resolve_combat()
## already computes them for the damage tally) to EventManager's shared
## arrow pools, on_archer_shot()/on_archer_kill() — the same "the sim
## already knows, the visual layer just samples it" split every boss's own
## archer-fire code already follows.

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
var _world: World
var _team_a := 0
var _team_b := 0
var _damage_per_second := 0.0
var _regroup_timer := 0.0
var _killed := 0
var _on_report := Callable()
var _on_archer_shot := Callable()
var _on_archer_kill := Callable()


## Starts team_a against team_b. Both must currently have someone alive, or
## there is nothing to fight and nobody to march. `on_archer_shot`/
## `on_archer_kill` are optional — a caller that does not care about the
## arrow visuals (every existing test) can simply not pass them.
static func start(bots: BotManager, world: World, team_a: int, team_b: int,
		damage_per_second: float, on_report: Callable,
		on_archer_shot: Callable = Callable(), on_archer_kill: Callable = Callable()) -> WarBattle:
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
	war._world = world
	war._team_a = team_a
	war._team_b = team_b
	war._damage_per_second = damage_per_second
	war._on_report = on_report
	war._on_archer_shot = on_archer_shot
	war._on_archer_kill = on_archer_kill
	return war


func _ready() -> void:
	_send_marchers()


## One simulation step. Returns false once one side has been wiped out.
func advance(delta: float) -> bool:
	var shots := PackedVector3Array()
	var kills := PackedVector3Array()
	_killed += _bots.resolve_combat(_team_a, _team_b, MELEE_RANGE, _damage_per_second, delta,
		shots, kills)
	if _on_archer_shot.is_valid():
		var pair := 0
		while pair + 1 < shots.size():
			_on_archer_shot.call(shots[pair], shots[pair + 1])
			pair += 2
	if _on_archer_kill.is_valid():
		for at in kills:
			_on_archer_kill.call(at)

	_regroup_timer += delta
	if _regroup_timer >= REGROUP_SECONDS:
		_regroup_timer -= REGROUP_SECONDS
		_send_marchers()

	var alive_a := _team_alive(_bots, _team_a)
	var alive_b := _team_alive(_bots, _team_b)
	if alive_a > 0 and alive_b > 0:
		_report("War: %d dead, %d v %d left" % [_killed, alive_a, alive_b])
		return true

	_report(_final_line(alive_a, alive_b))
	queue_free()
	return false


func _final_line(alive_a: int, alive_b: int) -> String:
	if alive_a == 0 and alive_b == 0:
		return "War: wiped each other out, %d dead" % _killed
	var winner := _team_a if alive_a > 0 else _team_b
	var loser := _team_b if alive_a > 0 else _team_a
	return "War: side %d wiped out side %d, %d dead" % [winner, loser, _killed]


## Points anyone free to be redirected at wherever the enemy's survivors
## currently are. send_to() already refuses anyone fighting or in the air, so
## this can be called over the whole crowd without checking state here first.
##
## The route is asked for once per side, from centroid to centroid, not once
## per marching bot: World.route_waypoint() searches a couple hundred
## regions, cheap for one call and not remotely cheap for the thousands a
## full army would cost if every bot asked for its own. Every bot on a side
## walks the same routed point — an approximation next to routing each one
## from where it actually stands, but the whole reason to route at all is to
## stop an army cutting across open water, not to give each straggler its
## own perfect path.
func _send_marchers() -> void:
	var alive_a := _team_alive(_bots, _team_a)
	var alive_b := _team_alive(_bots, _team_b)
	if alive_a == 0 or alive_b == 0:
		return
	var centre_a := _centroid(_bots, _team_a)
	var centre_b := _centroid(_bots, _team_b)
	var to_b := centre_b
	var to_a := centre_a
	if _world != null:
		to_b = _world.route_waypoint(centre_a, centre_b)
		to_a = _world.route_waypoint(centre_b, centre_a)
	for i in _bots.count:
		if _bots.alive[i] == 0:
			continue
		if _bots.war_side[i] == _team_a:
			_bots.send_to(i, to_b.x, to_b.y)
		elif _bots.war_side[i] == _team_b:
			_bots.send_to(i, to_a.x, to_a.y)


static func _team_alive(bots: BotManager, team_id: int) -> int:
	var n := 0
	for i in bots.count:
		if bots.alive[i] == 1 and bots.war_side[i] == team_id:
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
		if bots.alive[i] == 1 and bots.war_side[i] == team_id:
			sx += bots.pos_x[i]
			sz += bots.pos_z[i]
			n += 1
	if n == 0:
		return Vector2.ZERO
	return Vector2(sx / n, sz / n)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)
