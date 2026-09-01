class_name Rhombolion
extends Node3D
## A giant lion that stalks the island — the second of the third boss
## batch, from the same CC0 collection every other giant here draws from
## (assets/CREDITS.md). Same "gigant" contract as Monster: one object,
## sim-clock advance()/render(alpha), stomps/gets shot/falls and stays
## down. A balanced predator — neither the fastest nor the tankiest of the
## roster.
##
## The one twist this file adds: it roars on a cycle. For ROAR_DURATION_
## SECONDS out of every ROAR_INTERVAL_SECONDS, PANIC_RADIUS and
## FLEE_DISTANCE both widen by ROAR_RADIUS_MULT — a lion's roar terrifies
## from further away than its claws actually reach, unlike every other
## giant here, whose panic radius is one constant number. STOMP_RADIUS/
## MELEE_RANGE/ATTACK_RANGE are untouched: the roar only frightens wider,
## it does not hit harder.

## Uniform scale off the model's own longest axis — measured, not guessed,
## the same reasoning Titanoboo/Raptorous/Whormbus/Horsely scale off
## length instead of height.
const MODEL_PATH := "res://assets/models/010_Rhombolion_Art.glb"
const MODEL_LENGTH_UNITS := 2.439761
const LENGTH := 60.0

const SPEED := 10.0
const ARRIVAL_RADIUS := 8.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## The roar cycle — see the class doc. A third of every interval spent
## roaring, so the wider panic reads as a recurring event, not a rare one.
const ROAR_INTERVAL_SECONDS := 6.0
const ROAR_DURATION_SECONDS := 2.0
const ROAR_RADIUS_MULT := 1.6

const MAX_HEALTH := 6500.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 40
const MAX_EFFECTIVE_MELEE := 20
const ATTACK_RANGE := 70.0
const STOMP_RADIUS := 22.0
const MELEE_RANGE := 33.0
const PANIC_RADIUS := 75.0
const FLEE_DISTANCE := 80.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.5

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
## Real time since start, advanced every tick — drives the roar cycle via
## fmod(), the same continuously-growing clock Titanoboo's own _elapsed is.
var _elapsed := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Rhombolion:
	if world == null or bots == null:
		push_error("Rhombolion: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Rhombolion: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Rhombolion: needs a generator.")
		return null

	var lion := Rhombolion.new()
	lion._world = world
	lion._bots = bots
	lion._rng = rng
	lion._health = health
	lion._max_health = health
	lion._on_report = on_report
	lion._on_shake = on_shake
	lion._target = at
	lion.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	lion._previous = lion.position
	lion._current = lion.position
	lion._build()
	if on_shake.is_valid():
		on_shake.call(lion.position, 0.4)
	return lion


func advance(delta: float) -> bool:
	_elapsed += delta
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


## Whether right now falls inside a roar — see the class doc.
func _roaring() -> bool:
	return fmod(_elapsed, ROAR_INTERVAL_SECONDS) < ROAR_DURATION_SECONDS


func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)
	var roaring := _roaring()
	var panic_radius := PANIC_RADIUS * ROAR_RADIUS_MULT if roaring else PANIC_RADIUS
	var flee_distance := FLEE_DISTANCE * ROAR_RADIUS_MULT if roaring else FLEE_DISTANCE

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

	for i in _bots.bots_within(here.x, here.y, panic_radius):
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
		_bots.scare(i, here.x, here.y, flee_distance)

	var archers := 0
	for i in _bots.bots_within(here.x, here.y, ATTACK_RANGE):
		if _bots.alive[i] == 1 and _bots.bot_class[i] == GameConfig.CLASS_ARCHER:
			archers += 1

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var effective_melee := mini(melee_fighters, MAX_EFFECTIVE_MELEE)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND \
		+ effective_melee * MELEE_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Rhombolion: %d/%d health, %d archers + %d melee attacking, %d stomped%s"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped,
			" (roaring)" if roaring else ""])


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
		_report("Rhombolion keels over: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (LENGTH / MODEL_LENGTH_UNITS)
	add_child(body)
