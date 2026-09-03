class_name Rombophant
extends Node3D
## A giant rhinoceros that charges the island — the third of the third
## boss batch, from the same CC0 collection every other giant here draws
## from (assets/CREDITS.md). Same "gigant" contract as Monster: one
## object, sim-clock advance()/render(alpha), stomps/gets shot/falls and
## stays down. Slow and by far the tankiest of the whole roster — heavier
## even than Monster itself.
##
## The one twist this file adds: it does not aim at one random living bot
## the way every other giant here does. _pick_target() picks a random
## living bot as an anchor, then looks at everyone else within
## CHARGE_SCAN_RADIUS of that anchor and aims at their average position
## instead — a rhino charges into the thickest part of a herd, not at one
## individual animal in it. Falls back to the anchor itself if nobody else
## is nearby, and to a random land point if the crowd is gone, the same
## two-step fallback every other giant's own _pick_target() already has.
##
## **Fourth boss on Crabylon's procedural rig** (see that file's own class
## doc for how this was discovered, and Horsely/Rhombolion's for why the
## axis has to be re-measured per model). This model's bone names
## (`thigh.R`/`front_thigh.R`/`front_shin.R`) match Horsely's own
## convention, not Rhombolion's humanoid one — and measuring confirmed the
## same swing axis too: every leg bone's local X lines up with world
## horizontal (zero Y component) on every bone checked, so rotation happens
## around local X here, the same as Horsely. Worth noting precisely because
## it is the first time two different models agreed rather than each
## needing its own answer — still measured fresh rather than assumed, the
## agreement is a result, not a shortcut taken.

## Uniform scale off the model's own longest axis — measured, not guessed,
## the same reasoning Titanoboo/Raptorous/Whormbus/Horsely/Rhombolion
## scale off length instead of height.
const MODEL_PATH := "res://assets/models/027_Rombophant_Art.glb"
const MODEL_LENGTH_UNITS := 1.540505
const LENGTH := 72.0

const SPEED := 5.5
const ARRIVAL_RADIUS := 9.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## How far around a randomly anchored bot to average positions when
## picking a target — see the class doc. A little under twice its own
## body length: wide enough to catch "a cluster," not so wide it just
## reduces to the crowd's overall centroid.
const CHARGE_SCAN_RADIUS := LENGTH * 1.4

## By far the tankiest boss in the roster — heavier even than Monster.
const MAX_HEALTH := 11000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 55
## Same reasoning as Monster's own — see its ARROW_SAMPLE_STRIDE.
const ARROW_SAMPLE_STRIDE := 8
const MAX_EFFECTIVE_MELEE := 28
const ATTACK_RANGE := 84.0
const STOMP_RADIUS := 26.0
const MELEE_RANGE := 40.0
const PANIC_RADIUS := 90.0
const FLEE_DISTANCE := 96.0
const SWEEP_SECONDS := 0.2

## Slowest fall of the whole roster: the biggest, heaviest body takes the
## longest to finish toppling.
const FALL_SECONDS := 2.0

## Diagonal-pair trot, the same gait shape Horsely/Rhombolion's own legs
## use. Two segments animated per leg (thigh/shin), the third (foot) stays
## in rest.
const LEG_DIAGONAL_A := [
	["front_thigh.R", "front_shin.R"], ["thigh.L", "shin.L"],
]
const LEG_DIAGONAL_B := [
	["front_thigh.L", "front_shin.L"], ["thigh.R", "shin.R"],
]
## Slower cadence than the others — matches this boss's own SPEED (5.5,
## slowest of the whole rig'd roster so far).
const STEP_RATE := 3.5
## Rotation is around local X, same axis as Horsely's own rig — see the
## class doc on why this is confirmation, not an assumption.
## Halved from the first pass — see Crabylon's own note on the real-run
## report that called the stride too far and jerky.
const THIGH_SWING := 0.16
const SHIN_FOLD := 0.3
## Sign of "forward" not verified visually — see Crabylon's own note on why
## not (the headless screenshot save hang).

enum _Phase { ALIVE, FALLING, DEAD }

var _world: World
var _bots: BotManager
var _rng: RandomNumberGenerator
var _on_report := Callable()
var _on_shake := Callable()
var _on_archer_shot := Callable()

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

## Sim-clock seconds since spawn — drives the leg cycle's phase, the same
## role _elapsed plays in Horsely/Rhombolion.
var _elapsed := 0.0
## Bone rig — see the class doc. -1 for any name find_bone() could not
## resolve; _build() push_error()s once up front if that happens rather
## than animating nothing silently.
var _skeleton: Skeleton3D
var _diagonal_a: Array = []
var _diagonal_b: Array = []


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable,
		on_archer_shot: Callable = Callable()) -> Rombophant:
	if world == null or bots == null:
		push_error("Rombophant: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Rombophant: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Rombophant: needs a generator.")
		return null

	var rhino := Rombophant.new()
	rhino._world = world
	rhino._bots = bots
	rhino._rng = rng
	rhino._health = health
	rhino._max_health = health
	rhino._on_report = on_report
	rhino._on_shake = on_shake
	rhino._on_archer_shot = on_archer_shot
	rhino._target = at
	rhino.position = Vector3(at.x, world.get_height(at.x, at.y), at.y)
	rhino._previous = rhino.position
	rhino._current = rhino.position
	rhino._build()
	if on_shake.is_valid():
		on_shake.call(rhino.position, 0.4)
	return rhino


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
		_animate_legs()


## Diagonal-pair trot — see LEG_DIAGONAL_A/B's own doc. Render-clock only,
## purely cosmetic: no leg bone being posed ever changes who gets stomped,
## that is still _sweep() on the sim clock regardless of whether this ever
## runs.
func _animate_legs() -> void:
	if _skeleton == null:
		return
	var phase := _elapsed * STEP_RATE
	_animate_diagonal(_diagonal_a, phase)
	_animate_diagonal(_diagonal_b, phase + PI)


func _animate_diagonal(pair: Array, phase: float) -> void:
	# Sign flipped — see Rhombolion's own note: measured, after the body-
	# facing fix, that the lift phase moved the tip away from the head, not
	# toward it.
	var swing := -sin(phase)
	var lift := maxf(0.0, swing)
	for leg in pair:
		var thigh: int = leg[0]
		var shin: int = leg[1]
		if thigh >= 0:
			_skeleton.set_bone_pose_rotation(thigh,
				_local_rotation(thigh, Vector3(1.0, 0.0, 0.0), swing * THIGH_SWING))
		if shin >= 0:
			_skeleton.set_bone_pose_rotation(shin,
				_local_rotation(shin, Vector3(1.0, 0.0, 0.0), -lift * SHIN_FOLD))


## See Crabylon's own _local_rotation() for why this composition is
## necessary: Skeleton3D's pose replaces a bone's rest orientation outright
## rather than adding to it, so every posed rotation here has to be composed
## with get_bone_rest() or the leg snaps away from its actual bind shape.
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
	basis = Basis.looking_at(Vector3(dir.x, 0.0, dir.y), Vector3.UP)


## Charges the local herd, not one bot — see the class doc.
func _pick_target() -> void:
	_retarget_timer = RETARGET_SECONDS
	for _attempt in TARGET_ATTEMPTS:
		if _bots.count == 0:
			break
		var i := _rng.randi() % _bots.count
		if _bots.alive[i] != 1:
			continue
		var anchor := Vector2(_bots.pos_x[i], _bots.pos_z[i])
		var nearby := _bots.bots_within(anchor.x, anchor.y, CHARGE_SCAN_RADIUS)
		var sx := 0.0
		var sz := 0.0
		var n := 0
		for j in nearby:
			if _bots.alive[j] == 1:
				sx += _bots.pos_x[j]
				sz += _bots.pos_z[j]
				n += 1
		_target = Vector2(sx / n, sz / n) if n > 0 else anchor
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
			if _on_archer_shot.is_valid() and archers % ARROW_SAMPLE_STRIDE == 0:
				_on_archer_shot.call(Vector3(_bots.pos_x[i], _bots.pos_y[i], _bots.pos_z[i]), position)

	var effective_archers := mini(archers, MAX_EFFECTIVE_ARCHERS)
	var effective_melee := mini(melee_fighters, MAX_EFFECTIVE_MELEE)
	var damage := effective_archers * ARCHER_DAMAGE_PER_SECOND \
		+ effective_melee * MELEE_DAMAGE_PER_SECOND
	_health = maxf(0.0, _health - damage * elapsed)

	_report("Rombophant: %d/%d health, %d archers + %d melee attacking, %d stomped"
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
		_report("Rombophant keels over: %d stomped before archers brought it down" % _stomped)


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
		push_error("Rombophant: model has no Skeleton3D, legs will not animate.")
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
	for leg in LEG_DIAGONAL_A:
		_diagonal_a.append([_skeleton.find_bone(leg[0]), _skeleton.find_bone(leg[1])])
	for leg in LEG_DIAGONAL_B:
		_diagonal_b.append([_skeleton.find_bone(leg[0]), _skeleton.find_bone(leg[1])])

	var missing := 0
	for leg in _diagonal_a:
		if leg[0] < 0 or leg[1] < 0:
			missing += 1
	for leg in _diagonal_b:
		if leg[0] < 0 or leg[1] < 0:
			missing += 1
	if missing > 0:
		push_error("Rombophant: %d expected rig bones were not found; some animation will be missing."
			% missing)
