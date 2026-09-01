class_name Crabylon
extends Node3D
## A giant crab that walks the island sideways — TODO.md's "много вариаций
## забавных и смешных боссов" batch, the first of three built from the same
## CC0 collection Monster/Kraken already draw from (Polygonal Mind's "XYZ
## Collection" — see assets/CREDITS.md). Same "gigant" contract as Monster:
## one object, sim-clock advance()/render(alpha), stomps/gets shot/falls and
## stays down.
##
## The one joke this file adds on top of Monster's own shape: a crab always
## faces perpendicular to wherever it is actually walking, the same real
## animal's sideways gait exaggerated rather than invented — nothing else
## about _move() changes.

## Uniform scale is picked off the model's own widest axis (a crab is wide,
## not tall) — the ratio to GameConfig-scale everything else off, the same
## role Monster's HEIGHT plays for a model that actually is tallest along Y.
const MODEL_PATH := "res://assets/models/030_Crabylon_Art.glb"
const MODEL_WIDTH_UNITS := 2.382452
const WIDTH := 70.0

const SPEED := 8.0
const ARRIVAL_RADIUS := 9.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

const MAX_HEALTH := 6000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 40
const MAX_EFFECTIVE_MELEE := 20
const ATTACK_RANGE := 82.0
const STOMP_RADIUS := 25.0
const MELEE_RANGE := 38.0
const PANIC_RADIUS := 88.0
const FLEE_DISTANCE := 93.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.0

enum _Phase { ALIVE, FALLING, DEAD }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()

var _phase := _Phase.ALIVE
var _target := Vector2.ZERO
var _retarget_timer := 0.0
var _sweep_timer := 0.0
var _fall_elapsed := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Crabylon:
	if world == null or bots == null:
		push_error("Crabylon: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Crabylon: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Crabylon: needs a generator.")
		return null

	var crab := Crabylon.new()
	crab._world = world
	crab._bots = bots
	crab._rng = rng
	crab._health = health
	crab._max_health = health
	crab._on_report = on_report
	crab._on_shake = on_shake
	crab._target = at
	crab.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	crab._previous = crab.position
	crab._current = crab.position
	crab._build()
	if on_shake.is_valid():
		on_shake.call(crab.position, 0.4)
	return crab


func advance(delta: float) -> bool:
	match _phase:
		_Phase.ALIVE:
			_previous = _current
			_move(delta)
			_current = position

			_sweep_timer += delta
			if _sweep_timer >= SWEEP_SECONDS:
				_sweep(_sweep_timer)
				_sweep_timer = 0.0

			if _health <= 0.0:
				_begin_fall()
		_Phase.FALLING:
			_advance_fall(delta)
		_Phase.DEAD:
			pass
	return true


func render(alpha: float) -> void:
	if _phase == _Phase.ALIVE:
		position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


## Identical to Monster's own _move() except for the facing at the end: a
## crab walks sideways, so it faces perpendicular to its direction of
## travel rather than along it.
func _move(delta: float) -> void:
	_retarget_timer -= delta
	var here := Vector2(position.x, position.z)
	if _retarget_timer <= 0.0 or here.distance_to(_target) <= ARRIVAL_RADIUS:
		_pick_target()

	var to_target := _target - here
	var length := to_target.length()
	if length < 0.0001:
		return
	var dir := to_target / length
	var step := minf(SPEED * delta, length)
	var nx := position.x + dir.x * step
	var nz := position.z + dir.y * step
	position = Vector3(nx, _world.get_height(nx, nz), nz)
	# Rotated 90 degrees from the direction of travel — sideways, the way a
	# real crab actually walks, not toward or away from where it is going.
	basis = Basis.looking_at(Vector3(-dir.y, 0.0, dir.x), Vector3.UP)


func _pick_target() -> void:
	_retarget_timer = RETARGET_SECONDS
	for _attempt in TARGET_ATTEMPTS:
		if _bots.count == 0:
			break
		var i := _rng.randi() % _bots.count
		if _bots.alive[i] == 1:
			_target = Vector2(_bots.pos_x[i], _bots.pos_z[i])
			return
	_target = _world.random_land_point(_rng)


func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)

	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1

	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var fighting := BotManager.State.FIGHTING
	var warrior := GameConfig.CLASS_WARRIOR
	var spearman := GameConfig.CLASS_SPEARMAN
	var melee_range_squared := MELEE_RANGE * MELEE_RANGE
	var melee_fighters := 0

	for i in _bots.bots_within(here.x, here.y, PANIC_RADIUS):
		if _bots.alive[i] == 0:
			continue
		var cls: int = _bots.bot_class[i]
		if cls == warrior or cls == spearman:
			var dx := _bots.pos_x[i] - here.x
			var dz := _bots.pos_z[i] - here.y
			if dx * dx + dz * dz <= melee_range_squared:
				_bots.state[i] = fighting
				melee_fighters += 1
				continue
			if _bots.state[i] == fighting:
				_bots.state[i] = idle
				continue
		var bot_state: int = _bots.state[i]
		if bot_state != idle and bot_state != moving:
			continue
		_bots.scare(i, here.x, here.y, FLEE_DISTANCE)

	var archers := 0
	for i in _bots.bots_within(here.x, here.y, ATTACK_RANGE):
		if _bots.alive[i] == 1 and _bots.bot_class[i] == GameConfig.CLASS_ARCHER:
			archers += 1

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var effective_melee := mini(melee_fighters, MAX_EFFECTIVE_MELEE)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND \
		+ effective_melee * MELEE_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Crabylon: %d/%d health, %d archers + %d melee attacking, %d stomped"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped])


func _begin_fall() -> void:
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	if _on_shake.is_valid():
		_on_shake.call(position, 0.6)


func _advance_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / FALL_SECONDS, 0.0, 1.0)
	rotation.x = lerpf(0.0, PI * 0.5, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("Crabylon keels over: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (WIDTH / MODEL_WIDTH_UNITS)
	add_child(body)
