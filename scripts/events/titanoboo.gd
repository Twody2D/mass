class_name Titanoboo
extends Node3D
## A giant snake that slithers across the island — the second of the "many
## silly bosses" batch, from the same CC0 collection Monster/Kraken/Crabylon
## already draw from (assets/CREDITS.md). Same "gigant" contract as Monster:
## one object, sim-clock advance()/render(alpha), stomps/gets shot/falls and
## stays down. Faster and more fragile than the others — a snake is meant to
## be hard to pin down, not a wall to grind through.
##
## The one joke this file adds: a visible slither. _move() drives the real,
## authoritative position exactly like Monster's own; render() adds a small
## sine wave perpendicular to the direction of travel on top of the
## interpolated position, purely cosmetic — nothing that decides who gets
## stomped ever sees the wiggle, only the camera does.
##
## **Eighth boss on Crabylon's procedural rig, and the first with no legs at
## all — a travelling body curve instead of a gait.** The model's own
## Skeleton3D (the same throwaway inspector every prior pilot used,
## tools/inspect_model_tmp.gd, built/run/deleted) carries a clean six-bone
## `spine.001-006` chain plus a separate three-bone `tail.001-003`, both
## with a rest-pose local Z that lines up with world -Y almost exactly —
## the same vertical-aligned axis Crabylon's own legs found, not the
## horizontal one every legged rig since has used. Rotating around it
## sweeps the body left-right in the horizontal plane instead of pitching
## it up-down, exactly what a snake's body needs and exactly why Crabylon's
## own finding (measure fresh, do not assume horizontal) mattered again
## here. `_animate_rig()` gives each of the nine bones (spine then tail, one
## continuous index) its own phase-shifted bend; because pose rotations
## compose down a bone chain, nine small joint bends stack into one
## travelling S-curve along the whole body, the shape this file's own
## existing whole-object WIGGLE never actually produced — that wiggle
## offset the entire rigid model sideways as one piece, a path wobble, not
## a body bending. Both stay: the wobble and the curve are two different,
## real things a slithering snake does at once, not a replacement of one
## fake for one real. `frontleg`/`middleleg`/`backleg` bones also exist on
## this model (a stylised wyrm, not a legless snake) — left at rest, the
## same "only the parts that matter" scope every rig pilot has kept.
## Cumulative bend and its sign are unverified for the same reason every
## rig pilot's sign has been: the headless screenshot-save hang.

## Uniform scale off the model's own longest axis — a snake is long, not
## tall, the same reasoning Crabylon scales off width instead of height.
const MODEL_PATH := "res://assets/models/023_Titanoboo_Art.glb"
const MODEL_LENGTH_UNITS := 3.247936
const LENGTH := 90.0

const SPEED := 13.0
const ARRIVAL_RADIUS := 11.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## Purely cosmetic — see the class doc. Amplitude as a share of LENGTH, so a
## rescaled snake keeps the same proportions of wiggle to body.
const WIGGLE_AMPLITUDE := 6.0
const WIGGLE_RATE := 3.0

## Travelling body curve — see the class doc. Rides WIGGLE_RATE so the
## skeletal curve and the whole-body wobble share one visual rhythm instead
## of beating against each other at two independent frequencies.
const SPINE := ["spine.001", "spine.002", "spine.003", "spine.004", "spine.005", "spine.006"]
const TAIL := ["tail.001", "tail.002", "tail.003"]
const CURVE_AMPLITUDE := 0.22
const CURVE_PHASE_STEP := 0.7

const MAX_HEALTH := 4000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 30
const MAX_EFFECTIVE_MELEE := 15
const ATTACK_RANGE := 105.0
const STOMP_RADIUS := 32.0
const MELEE_RANGE := 50.0
const PANIC_RADIUS := 112.0
const FLEE_DISTANCE := 120.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.4

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
var _elapsed := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _facing := Vector2(0.0, 1.0)
var _previous := Vector3.ZERO
var _current := Vector3.ZERO

## Bone rig — see the class doc. -1 for any name find_bone() could not
## resolve; _build() push_error()s once up front if that happens rather
## than animating nothing silently.
var _skeleton: Skeleton3D
var _spine: Array = []
var _tail_chain: Array = []


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable) -> Titanoboo:
	if world == null or bots == null:
		push_error("Titanoboo: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Titanoboo: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Titanoboo: needs a generator.")
		return null

	var snake := Titanoboo.new()
	snake._world = world
	snake._bots = bots
	snake._rng = rng
	snake._health = health
	snake._max_health = health
	snake._on_report = on_report
	snake._on_shake = on_shake
	snake._target = at
	snake.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	snake._previous = snake.position
	snake._current = snake.position
	snake._build()
	if on_shake.is_valid():
		on_shake.call(snake.position, 0.4)
	return snake


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


## The interpolated position plus a sideways wiggle, perpendicular to
## whichever way the snake last faced. Cosmetic only — see the class doc.
func render(alpha: float) -> void:
	if _phase != _Phase.ALIVE:
		return
	var base := _previous.lerp(_current, clampf(alpha, 0.0, 1.0))
	var wiggle := sin(_elapsed * WIGGLE_RATE) * WIGGLE_AMPLITUDE
	position = base + Vector3(-_facing.y, 0.0, _facing.x) * wiggle
	_animate_rig()


## Render-clock only, purely cosmetic — see the class doc. No spine bone
## being posed ever changes who gets stomped; that is still _sweep() on the
## sim clock regardless of whether this ever runs.
func _animate_rig() -> void:
	if _skeleton == null:
		return
	var index := 0
	for bone in _spine:
		_pose_curve(bone, index)
		index += 1
	for bone in _tail_chain:
		_pose_curve(bone, index)
		index += 1


func _pose_curve(bone: int, index: int) -> void:
	if bone < 0:
		return
	var bend := sin(_elapsed * WIGGLE_RATE + index * CURVE_PHASE_STEP) * CURVE_AMPLITUDE
	_skeleton.set_bone_pose_rotation(bone, _local_rotation(bone, Vector3(0.0, 0.0, 1.0), bend))


## See Crabylon's own _local_rotation() for why this composition is
## necessary: Skeleton3D's pose replaces a bone's rest orientation outright
## rather than adding to it, so every posed rotation here has to be composed
## with get_bone_rest() or the spine snaps away from its actual bind shape.
func _local_rotation(bone: int, axis: Vector3, angle: float) -> Quaternion:
	return _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(axis, angle)


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
	_facing = dir
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

	_report("Titanoboo: %d/%d health, %d archers + %d melee attacking, %d stomped"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped])


## See Monster's own push() for what this is and why it no-ops once FALLING.
func push(offset: Vector2) -> void:
	if _phase != _Phase.ALIVE:
		return
	_previous.x += offset.x
	_previous.z += offset.y
	_current.x += offset.x
	_current.z += offset.y
	position = _current


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
		_report("Titanoboo keels over: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (LENGTH / MODEL_LENGTH_UNITS)
	# See Crabylon's own _build() for why: this model's head bone sits on +Z
	# in rest pose too, the opposite of what _move()'s Basis.looking_at()
	# assumes, and the whole imported body walked backward for it.
	body.rotation.y = PI
	add_child(body)
	_skeleton = _find_skeleton(body)
	if _skeleton == null:
		push_error("Titanoboo: model has no Skeleton3D, the body will not curve.")
		return
	_cache_bones()


func _find_skeleton(node: Node) -> Skeleton3D:
	if node is Skeleton3D:
		return node
	for child in node.get_children():
		var found := _find_skeleton(child)
		if found != null:
			return found
	return null


func _cache_bones() -> void:
	_spine = []
	for bone_name in SPINE:
		_spine.append(_skeleton.find_bone(bone_name))
	_tail_chain = []
	for bone_name in TAIL:
		_tail_chain.append(_skeleton.find_bone(bone_name))

	var missing := 0
	for bone in _spine:
		if bone < 0:
			missing += 1
	for bone in _tail_chain:
		if bone < 0:
			missing += 1
	if missing > 0:
		push_error("Titanoboo: %d expected rig bones were not found; some animation will be missing."
			% missing)
