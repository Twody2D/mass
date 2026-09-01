class_name Whormbus
extends Node3D
## A giant worm that burrows across the island — the third of a second
## "many silly bosses" batch, from the same CC0 collection Monster/Kraken/
## Crabylon/Titanoboo/Giraffaxon/Raptorous/Scorpy already draw from (assets/
## CREDITS.md). Same "gigant" contract as Monster: one object, sim-clock
## advance()/render(alpha), stomps/gets shot/falls and stays down. Slow and
## relentless — no legs to be fast or nimble with.
##
## The one twist this file adds: it does not topple over when beaten, the
## way every legged giant here does — it has no legs to topple onto. It
## sinks straight down instead, burrowing away mid-death. Still a landmark
## afterwards, the same contract as every other fallen giant: it stops
## partway down (SINK_SHARE, not all the way), leaving the front half of
## the body visible rather than vanishing entirely.

## Uniform scale off the model's own longest axis — measured, not guessed,
## the same reasoning Titanoboo scales off length instead of height.
const MODEL_PATH := "res://assets/models/006_Whormbus_Art.glb"
const MODEL_LENGTH_UNITS := 1.60983
const LENGTH := 78.0

const SPEED := 5.0
const ARRIVAL_RADIUS := 10.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

const MAX_HEALTH := 7000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 40
const MAX_EFFECTIVE_MELEE := 20
const ATTACK_RANGE := 91.0
const STOMP_RADIUS := 28.0
const MELEE_RANGE := 43.0
const PANIC_RADIUS := 98.0
const FLEE_DISTANCE := 104.0
const SWEEP_SECONDS := 0.2

## Slowest fall of the batch on purpose: sinking into the ground reads best
## unhurried, the opposite of Raptorous's abrupt stumble.
const FALL_SECONDS := 2.2
## Share of LENGTH it sinks by — under half, so the front of the body stays
## above ground as a landmark rather than disappearing entirely (see the
## class doc).
const SINK_SHARE := 0.45

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
var _fall_start_y := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Whormbus:
	if world == null or bots == null:
		push_error("Whormbus: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Whormbus: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Whormbus: needs a generator.")
		return null

	var worm := Whormbus.new()
	worm._world = world
	worm._bots = bots
	worm._rng = rng
	worm._health = health
	worm._max_health = health
	worm._on_report = on_report
	worm._on_shake = on_shake
	worm._target = at
	worm.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	worm._previous = worm.position
	worm._current = worm.position
	worm._build()
	if on_shake.is_valid():
		on_shake.call(worm.position, 0.4)
	return worm


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
	basis = Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)


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

	_report("Whormbus: %d/%d health, %d archers + %d melee attacking, %d stomped"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped])


func _begin_fall() -> void:
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	_fall_start_y = position.y
	if _on_shake.is_valid():
		_on_shake.call(position, 0.6)


## Sinks straight down instead of toppling — see the class doc. No legs to
## pivot around the way every other giant here does, so there is nothing to
## rotate: only position.y moves, down by SINK_SHARE of LENGTH.
func _advance_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / FALL_SECONDS, 0.0, 1.0)
	position.y = lerpf(_fall_start_y, _fall_start_y - LENGTH * SINK_SHARE, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("Whormbus burrows down and stops moving: %d stomped before archers brought it down"
			% _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (LENGTH / MODEL_LENGTH_UNITS)
	add_child(body)
