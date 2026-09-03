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
##
## **Pilot for the project's real procedural rig.** Every earlier boss
## (Monster included) only ever moved its whole imported body at once — the
## project's own doc comments called that "no bone touched" and treated a
## true walk cycle as impossible, because none of the eleven boss models
## ship an AnimationPlayer clip. That was only half the fact: checking for
## this pilot (a throwaway inspector dumping Skeleton3D.get_bone_global_rest()
## for real numbers, built and deleted the same way earlier one-shot
## inspectors were) found every checked model IS rigged — a real Skeleton3D
## with named FK bone chains, just with nobody's hand-authored clip attached.
## `Skeleton3D.set_bone_pose_rotation()` poses those bones directly, no clip
## needed — that is what this file's `_animate_legs()`/`_animate_claw()` do.
## The owner chose "duplicate this per boss file, no shared helper" for the
## whole animation effort, matching every other boss's own `_move()`/
## `_sweep()` copy-paste — so the walk-cycle and claw-grab code below is
## Crabylon's own, not a base class other bosses will inherit.
##
## Two separate things the owner asked for, both live here: legs that swing
## in a real step cycle instead of the body just gliding across the ground,
## and a claw that visibly reaches for one specific bot and grabs it, rather
## than the area stomp being the only thing that ever kills anyone up close.
## The stomp itself changed too: it used to fire on the same SWEEP_SECONDS
## clock as everything else (0.2 s), reading as a mower rolling over the
## crowd rather than footfalls — it now fires once per STEP_PERIOD, tied to
## the leg cycle, so a kill under its feet actually lines up with a step
## landing.

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
## Same reasoning as Monster's own — see its ARROW_SAMPLE_STRIDE.
const ARROW_SAMPLE_STRIDE := 8
const ATTACK_RANGE := 82.0
const STOMP_RADIUS := 25.0
const MELEE_RANGE := 38.0
const PANIC_RADIUS := 88.0
const FLEE_DISTANCE := 93.0
const SWEEP_SECONDS := 0.2

const FALL_SECONDS := 1.0

## Real footfalls instead of the old "kill everyone in STOMP_RADIUS every
## SWEEP_SECONDS" mower — see the class doc. One footfall roughly every
## other beat of the leg cycle below (STEP_RATE), not on its own clock, so a
## kill actually lands when a leg would visibly plant.
const STEP_PERIOD := 0.65

## Bone names for the six legs, two FK segments animated each (the third,
## `.003`, is small enough — see the real AABB this pilot measured — that
## leaving it in rest pose does not read as a stiff toe). Two alternating
## tripods, the real gait insects and crabs both use: three legs plant while
## the other three lift and swing, then they trade — not a project
## invention, just the cheapest gait that does not look like the crab is
## dragged across the ground.
const LEG_TRIPOD_A := [
	["leg1.001.R", "leg1.002.R"], ["leg2.001.L", "leg2.002.L"], ["leg3.001.R", "leg3.002.R"],
]
const LEG_TRIPOD_B := [
	["leg1.001.L", "leg1.002.L"], ["leg2.001.R", "leg2.002.R"], ["leg3.001.L", "leg3.002.L"],
]
## Radians/second through the step cycle. Not tied to SPEED: at this scale a
## fixed cadence reads fine, the same "constant rate, not derived from
## velocity" choice Monster's own BOB_RATE already makes.
const STEP_RATE := 5.0
## Swing is around each thigh bone's own local Z axis — measured, not
## guessed: a throwaway inspector dumped every leg/claw bone's real
## Skeleton3D.get_bone_global_rest() basis, and a thigh's local Z lines up
## with world -Y (vertical) to within a few degrees on every leg checked, so
## rotating around it sweeps the leg fore-and-aft in the horizontal plane —
## exactly a step, not a flap. THIGH_SWING is that sweep's amplitude.
## Halved from the first pass (0.32) — an owner report from a real run
## called the whole rig'd roster's stride "too far, jerky" once the rest-
## pose composition bug (see _local_rotation()) was no longer masking how
## big these angles actually read.
const THIGH_SWING := 0.18
## The shin folds around its own local X axis instead — that axis measured
## almost perfectly horizontal in the same dump, while the shin bone itself
## points mostly straight down, so rotating around a horizontal axis lifts
## the foot fore-and-aft rather than sideways. Only folds while `sin(phase)`
## is positive (the "lifted" half of the cycle) so a planted leg stays
## straight instead of also bending.
const SHIN_FOLD := 0.34
## Exact sign of "forward" for either axis was not verified visually (see
## the class doc on why not) — still true, and still a one-line flip if a
## real run shows the legs sweeping backward through a step. A bigger,
## unrelated bug was found and fixed instead first: see _local_rotation()
## below, which every set_bone_pose_rotation() call in this file now goes
## through.

## The claw grab: a slower, separate cycle from the legs, aimed at one
## specific bot rather than an area. Reuses MELEE_RANGE as its own reach —
## a claw that cannot grab anyone the melee sweep would not also have
## reached would read as a second, unrelated hitbox.
const CLAW_RANGE := MELEE_RANGE
const CLAW_SECONDS := 0.9
const CLAW_COOLDOWN := 2.5
## Reach is around the upper arm's own local Z axis, for the same measured
## reason the thigh swing is: it lines up with world -Y, so rotating around
## it yaws the whole arm sideways in the horizontal plane, toward wherever
## the current target actually is instead of a fixed spot.
const CLAW_REACH_ANGLE := 0.85
## The two claw-tip bones (claw.001.R/claw.002.R are siblings, not a chain —
## the real "fingers") rotate the same measured way, in opposite directions,
## to open and close.
const CLAW_OPEN_ANGLE := 0.3

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
var _step_timer := 0.0
var _fall_elapsed := 0.0
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _grabbed := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO

## Sim-clock seconds since spawn, driving the leg cycle and the claw's own
## reach/open timing — the same "sim decides, render only draws from
## _elapsed" split Monster's own _animate_body() already uses.
var _elapsed := 0.0
var _skeleton: Skeleton3D
## Bone indices per leg, [thigh, shin] each, in LEG_TRIPOD_A/B order —
## resolved once in _build() so the walk cycle never does a string lookup
## per tick. -1 for any name find_bone() could not resolve; _animate_legs()
## skips those rather than erroring every frame, but _build() already
## push_error()s once up front so a broken rig is never silent.
var _tripod_a: Array = []
var _tripod_b: Array = []
var _claw_shoulder := -1
var _claw_a := -1
var _claw_b := -1

var _claw_target := -1
var _claw_trigger := -1000.0
var _claw_cooldown_timer := 0.0
## Last direction of actual travel — see _find_claw_target()'s own note on
## why this, not basis.z, is what "forward" has to mean for the claw.
var _travel_dir := Vector2.DOWN


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable,
		on_archer_shot: Callable = Callable()) -> Crabylon:
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
	crab._on_archer_shot = on_archer_shot
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
			_elapsed += delta
			_previous = _current
			_move(delta)
			_current = position

			_step_timer += delta
			if _step_timer >= STEP_PERIOD:
				_stomp_step()
				_step_timer = 0.0

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
		_animate_claw()


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
	_travel_dir = dir
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


## Real footfalls, on their own STEP_PERIOD clock instead of every
## SWEEP_SECONDS tick — see the class doc on why the old "kill everyone in
## STOMP_RADIUS every 0.2s" read as a mower rather than footsteps.
func _stomp_step() -> void:
	var here := Vector2(position.x, position.z)
	var before := _stomped
	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1
	if _stomped > before and _on_shake.is_valid():
		_on_shake.call(position, 0.15)


func _sweep(elapsed: float) -> void:
	var here := Vector2(position.x, position.z)

	var idle := BotManager.State.IDLE
	var moving := BotManager.State.MOVING
	var fighting := BotManager.State.FIGHTING
	var warrior := GameConfig.CLASS_WARRIOR
	var spearman := GameConfig.CLASS_SPEARMAN
	var melee_range_squared := MELEE_RANGE * MELEE_RANGE
	var melee_fighters := 0
	var turn := 1.0 - exp(-BotManager.TURN_RESPONSE * elapsed)

	for i in _bots.bots_within(here.x, here.y, PANIC_RADIUS):
		if _bots.alive[i] == 0:
			continue
		var cls: int = _bots.bot_class[i]
		if cls == warrior or cls == spearman:
			var dx := _bots.pos_x[i] - here.x
			var dz := _bots.pos_z[i] - here.y
			if dx * dx + dz * dz <= melee_range_squared:
				_bots.state[i] = fighting
				_bots.face_point(i, here.x, here.y, turn)
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

	# The claw grab: decided here, on the sim clock — see the class doc on
	# why _animate_claw() (render-only) never has to be called for the kill
	# itself to happen on schedule.
	_claw_cooldown_timer -= elapsed
	if _claw_target == -1 and _claw_cooldown_timer <= 0.0:
		_claw_target = _find_claw_target(here)
		if _claw_target != -1:
			_claw_trigger = _elapsed
	elif _claw_target != -1 and _bots.alive[_claw_target] == 0:
		# Died to something else mid-reach (an archer, the stomp) — let go
		# rather than snapping shut on empty air a moment later.
		_claw_target = -1
		_claw_cooldown_timer = CLAW_COOLDOWN
	if _claw_target != -1 and _elapsed - _claw_trigger >= CLAW_SECONDS:
		if _bots.kill(_claw_target):
			_grabbed += 1
		_claw_target = -1
		_claw_cooldown_timer = CLAW_COOLDOWN

	_report("Crabylon: %d/%d health, %d archers + %d melee attacking, %d stomped, %d grabbed"
		% [ceili(_health), int(_max_health), archers, melee_fighters, _stomped, _grabbed])


## Nearest living melee-class bot between STOMP_RADIUS and CLAW_RANGE, and in
## front of the claw's own shoulder — a warrior or spearman specifically, the
## same classes MELEE_RANGE already singles out to stand and fight instead of
## fleeing, so the claw always reaches for someone already standing its
## ground rather than snatching a fleeing archer out of a panicked crowd.
## Excluding anyone already inside STOMP_RADIUS is not just flavour: without
## it the claw would routinely lock onto whoever the footstep sweep was about
## to kill anyway, lose the race, and sit out its own CLAW_COOLDOWN before
## trying again — found exactly that way, as a real race in
## verify_crabylon.gd's own claw check, not reasoned out in advance.
##
## The front-facing check was missing entirely until an owner report from a
## real run: bots_within() is a plain radius query with no idea which way the
## crab is even facing, so the claw could — and did — reach straight through
## its own carapace for someone standing directly behind it. A dot product
## keeps this a single cheap check per candidate rather than a real vision
## cone.
##
## "Forward" is _travel_dir, not -basis.z. A first version used the body's
## own facing, but _move() deliberately points that perpendicular to travel
## (see its own note — a crab's real sideways gait) while _pick_target()
## still chases bots in the travel direction itself. That mismatch meant the
## bot the crab was actually walking toward was, by construction, never in
## the claw's accepted cone — only something incidentally off to the current
## facing side was. A real run reported exactly that: the crab crawling
## toward the crowd without ever looking at or grabbing whoever it was
## heading for. The claw now reaches toward wherever the crab is actually
## going, independent of which way its decorative sideways-facing body
## happens to point.
func _find_claw_target(here: Vector2) -> int:
	var warrior := GameConfig.CLASS_WARRIOR
	var spearman := GameConfig.CLASS_SPEARMAN
	var stomp_radius_sq := STOMP_RADIUS * STOMP_RADIUS
	var forward := _travel_dir
	var best := -1
	var best_distance_sq := INF
	for i in _bots.bots_within(here.x, here.y, CLAW_RANGE):
		if _bots.alive[i] == 0:
			continue
		var cls: int = _bots.bot_class[i]
		if cls != warrior and cls != spearman:
			continue
		var dx := _bots.pos_x[i] - here.x
		var dz := _bots.pos_z[i] - here.y
		if dx * forward.x + dz * forward.y <= 0.0:
			continue
		var d := dx * dx + dz * dz
		if d <= stomp_radius_sq:
			continue
		if d < best_distance_sq:
			best_distance_sq = d
			best = i
	return best


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
	_release_fighters()
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	if _on_shake.is_valid():
		_on_shake.call(position, 0.6)


## Anyone still fighting this boss when it dies would otherwise keep the
## FIGHTING state (and knight.gdshader's sword/spear-swing animation)
## forever: _sweep()'s own "no longer in range" branch is the only thing
## that ever clears it, and _begin_fall() is the last point in this
## object's life a _sweep() still ran. PANIC_RADIUS rather than MELEE_RANGE
## on purpose — always the larger of the two (see _sweep()), so it is
## guaranteed to reach every bot _sweep() could ever have marked FIGHTING
## against this boss.
func _release_fighters() -> void:
	var here := Vector2(position.x, position.z)
	var fighting := BotManager.State.FIGHTING
	for i in _bots.bots_within(here.x, here.y, PANIC_RADIUS):
		if _bots.state[i] == fighting:
			_bots.state[i] = BotManager.State.IDLE


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


## Walk cycle: two alternating tripods (PI out of phase with each other),
## each thigh sweeping fore-and-aft around its own local Z axis and its shin
## folding around its own local X — see LEG_TRIPOD_A/B's own doc for where
## those axes came from. Render-clock only, purely cosmetic: no leg bone
## being posed ever changes who gets stomped, that is still _stomp_step() on
## the sim clock regardless of whether this ever runs.
func _animate_legs() -> void:
	if _skeleton == null:
		return
	var phase := _elapsed * STEP_RATE
	_animate_tripod(_tripod_a, phase)
	_animate_tripod(_tripod_b, phase + PI)


func _animate_tripod(tripod: Array, phase: float) -> void:
	var swing := sin(phase)
	var lift := maxf(0.0, swing)
	for leg in tripod:
		var thigh: int = leg[0]
		var shin: int = leg[1]
		if thigh >= 0:
			_skeleton.set_bone_pose_rotation(thigh,
				_local_rotation(thigh, Vector3(0.0, 0.0, 1.0), swing * THIGH_SWING))
		if shin >= 0:
			_skeleton.set_bone_pose_rotation(shin,
				_local_rotation(shin, Vector3(1.0, 0.0, 0.0), -lift * SHIN_FOLD))


## Reach-and-snap, drawn from the same _claw_trigger/_claw_target the sim
## clock already set in _sweep() — purely cosmetic, the grab's kill already
## happened on schedule whether or not this ever runs (see render()'s own
## call site, and why verify_crabylon.gd does not depend on this method to
## prove the grab actually works).
func _animate_claw() -> void:
	if _skeleton == null or _claw_shoulder < 0:
		return
	var reach := 0.0
	var open := 0.0
	if _claw_target != -1:
		var t := clampf((_elapsed - _claw_trigger) / CLAW_SECONDS, 0.0, 1.0)
		reach = sin(minf(t, 0.75) / 0.75 * PI * 0.5) * CLAW_REACH_ANGLE
		open = CLAW_OPEN_ANGLE * (1.0 - smoothstep(0.65, 1.0, t))
	_skeleton.set_bone_pose_rotation(_claw_shoulder,
		_local_rotation(_claw_shoulder, Vector3(0.0, 0.0, 1.0), reach))
	if _claw_a >= 0:
		_skeleton.set_bone_pose_rotation(_claw_a, _local_rotation(_claw_a, Vector3(0.0, 0.0, 1.0), open))
	if _claw_b >= 0:
		_skeleton.set_bone_pose_rotation(_claw_b, _local_rotation(_claw_b, Vector3(0.0, 0.0, 1.0), -open))


## Skeleton3D's pose does not add a delta on top of a bone's rest orientation
## — it replaces the pose outright, and defaults to the rest orientation
## itself when untouched (get_bone_pose_rotation() right after
## reset_bone_poses() reads back bit-identical to get_bone_rest()'s own
## rotation). Every rotation this file poses has to be composed with that
## rest orientation, or the bone snaps to whatever `axis` and `angle` alone
## describe and loses its actual bind shape entirely — found as a real bug,
## not reasoned out in advance: a throwaway geometric probe (built the same
## way every other one-shot measurement in this project has been) showed the
## uncomposed pose moving a leg's tip to a wildly different radius from the
## body than its own rest position, while the composed version stays close
## to it across a full swing. This is very likely what the owner saw as legs
## passing through the body on a real run.
func _local_rotation(bone: int, axis: Vector3, angle: float) -> Quaternion:
	return _skeleton.get_bone_rest(bone).basis.get_rotation_quaternion() * Quaternion(axis, angle)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (WIDTH / MODEL_WIDTH_UNITS)
	# Measured, not guessed, after a real run showed every one of this
	# project's imported bosses walking backward: a throwaway inspector
	# (tools/inspect_facing_tmp.gd, built and deleted the same way every
	# other one-shot bone measurement in this project has been) checked
	# where each model's own head/neck bone sits in rest pose, and every
	# single one — this model included — has it on +Z, not the -Z every
	# _move() assumes (Basis.looking_at(dir, UP) aligns -Z with the
	# direction of travel). The whole imported body is turned around here,
	# once, rather than flipping the sign in every leg's own swing — the
	# legs were already measured correctly relative to THIS model's own
	# facing, it was the facing itself that was backward.
	body.rotation.y = PI
	add_child(body)
	_skeleton = _find_skeleton(body)
	if _skeleton == null:
		push_error("Crabylon: model has no Skeleton3D, legs and claw will not animate.")
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


## Resolves every bone name LEG_TRIPOD_A/B and the claw constants need,
## once, so the walk cycle and claw never do a string lookup per tick. Warns
## once, loudly, rather than silently animating nothing, if the model this
## ships with ever changes and a name stops resolving — the same "no quiet
## errors" rule this project holds every other missing-id/index case to.
func _cache_bones() -> void:
	for leg in LEG_TRIPOD_A:
		_tripod_a.append([_skeleton.find_bone(leg[0]), _skeleton.find_bone(leg[1])])
	for leg in LEG_TRIPOD_B:
		_tripod_b.append([_skeleton.find_bone(leg[0]), _skeleton.find_bone(leg[1])])
	_claw_shoulder = _skeleton.find_bone("frontarm.001.R")
	_claw_a = _skeleton.find_bone("claw.001.R")
	_claw_b = _skeleton.find_bone("claw.002.R")

	var missing := 0
	for leg in _tripod_a:
		if leg[0] < 0 or leg[1] < 0:
			missing += 1
	for leg in _tripod_b:
		if leg[0] < 0 or leg[1] < 0:
			missing += 1
	if _claw_shoulder < 0 or _claw_a < 0 or _claw_b < 0:
		missing += 1
	if missing > 0:
		push_error("Crabylon: %d expected rig bones were not found; some animation will be missing."
			% missing)
