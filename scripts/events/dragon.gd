class_name Dragon
extends Node3D
## A giant dragon that patrols the sky — the pilot for a new integration
## technique: playing this model's own baked AnimationPlayer clips instead
## of hand-posing a Skeleton3D bone by bone, the way every rigged boss in
## this project so far does. All 11 previous imports come from the same CC0
## pack (Polygonal Mind's "XYZ Collection"), which turned out to be rigged
## everywhere but animated nowhere — a second batch of 10 candidates from
## that same pack confirmed it uniformly, not just unluckily. This model is
## a different CC0 pack entirely (Quaternius, quaternius.com/packs/
## ultimatemonsters.html), animated everywhere, chosen by the owner
## specifically to test that path.
##
## First-ever aerial giant: it never touches the ground while alive. It
## flies at a fixed ALTITUDE above the terrain directly beneath it, using
## the exact same _move()/_pick_target() pattern every ground-bound giant
## here already uses, and the exact same 2D-radius _sweep() (stomp/melee/
## archer/panic) that never actually looked at a giant's own Y position
## anyway — the same abstraction the whole project already leans on for
## every existing boss, not a new one invented for this file. No swoop-and-
## land mechanic: that would be a second, unrelated design question on top
## of the one this pilot actually exists to answer (does baked-clip
## playback fit the advance()/render(alpha) split at all?), so this first
## pass stays the simplest version that still uses the clips meaningfully.
##
## Clip playback is driven by hand — AnimationPlayer.speed_scale pinned to
## 0 right after play(), then seek(t, true) every render() — the same "sim
## decides, render only draws from its own elapsed clock" split every
## hand-posed rig in this project already keeps between advance() and
## render(alpha). Clip names came back from the file as "CharacterArmature|
## Death" etc. (a raw FBX-style armature-prefixed name baked in at export,
## not a Godot AnimationLibrary convention) — resolved once in _build() by
## splitting on "|" rather than hardcoding that prefix, so a re-export with
## a differently named armature would not silently break every lookup.

const MODEL_PATH := "res://assets/models/quaternius_dragon.glb"
## Scaled off wingspan (the model's own widest axis), not nose-to-tail
## length — the widest axis is what actually reads as huge for a flying
## silhouette, the same reasoning Crabylon scales off width instead of
## height. Measured, not guessed: tools/inspect_dragon_tmp.gd (throwaway,
## deleted after use like every other one-shot measurement in this project).
const MODEL_WINGSPAN_UNITS := 4.382037
const WINGSPAN := 70.0

## Height above the terrain directly beneath it. Enough to clear the
## island's own hills and read clearly over the crowd — never adjusted for
## ground undulation beyond following get_height() the same way every
## ground-bound giant already does.
const ALTITUDE := 45.0

const SPEED := 22.0
const ARRIVAL_RADIUS := 12.0
const RETARGET_SECONDS := 4.0
const TARGET_ATTEMPTS := 6

## The purely cosmetic Headbutt flourish, tied to a real stomp landing —
## the same "cosmetic flourish tied to a real game moment" reasoning
## Horsely's own rear-kick already uses, not a fixed metronome.
const HEADBUTT_SECONDS := 0.5

const MAX_HEALTH := 5000.0
const ARCHER_DAMAGE_PER_SECOND := 1.0
const MELEE_DAMAGE_PER_SECOND := 4.0
const MAX_EFFECTIVE_ARCHERS := 35
const MAX_EFFECTIVE_MELEE := 15
## Same reasoning as Monster's own — see its ARROW_SAMPLE_STRIDE.
const ARROW_SAMPLE_STRIDE := 8
const ATTACK_RANGE := 90.0
const STOMP_RADIUS := 20.0
const MELEE_RANGE := 30.0
const PANIC_RADIUS := 85.0
const FLEE_DISTANCE := 90.0
const SWEEP_SECONDS := 0.2

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
var _fall_start_y := 0.0
## Matched to the Death clip's own real length once it is read in _build(),
## not hardcoded — the crash lerp and the clip finish together by
## construction rather than by tuning two numbers to agree.
var _fall_seconds := 0.8
var _health := MAX_HEALTH
var _max_health := MAX_HEALTH
var _stomped := 0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO

## Sim-clock seconds since spawn — drives which clip plays and the
## Headbutt flourish's own decay window.
var _elapsed := 0.0
var _headbutt_trigger := -1000.0

var _anim_player: AnimationPlayer
## short clip name ("Death", "Fast_Flying", ...) -> the exact play()-ready
## name ("CharacterArmature/CharacterArmature|Death"), and the same key ->
## the actual Animation resource, cached once in _cache_clips() so neither
## a string lookup nor a resource lookup happens per frame.
var _clip_names: Dictionary = {}
var _clip_resources: Dictionary = {}
var _current_clip := ""


static func start(world: World, bots: BotManager, at: Vector2, health: float,
		rng: RandomNumberGenerator, on_report: Callable, on_shake: Callable,
		on_archer_shot: Callable = Callable()) -> Dragon:
	if world == null or bots == null:
		push_error("Dragon: needs a world and a crowd.")
		return null
	if health <= 0.0:
		push_error("Dragon: needs positive health, got %f." % health)
		return null
	if rng == null:
		push_error("Dragon: needs a generator.")
		return null

	var dragon := Dragon.new()
	dragon._world = world
	dragon._bots = bots
	dragon._rng = rng
	dragon._health = health
	dragon._max_health = health
	dragon._on_report = on_report
	dragon._on_shake = on_shake
	dragon._on_archer_shot = on_archer_shot
	dragon._target = at
	dragon.position = Vector3(at.x, world.get_height(at.x, at.y) + ALTITUDE, at.y)
	dragon._previous = dragon.position
	dragon._current = dragon.position
	dragon._build()
	if on_shake.is_valid():
		on_shake.call(dragon.position, 0.3)
	return dragon


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
	match _phase:
		_Phase.ALIVE:
			position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))
			_animate_alive()
		_Phase.FALLING:
			_animate_fall()
		_Phase.DEAD:
			pass


## Fast_Flying while actually covering ground, Flying_Idle once close
## enough to its target to be about to retarget, Headbutt for a short
## flourish right after a real stomp landed — see HEADBUTT_SECONDS's own
## doc. Render-clock only, purely cosmetic: no clip being scrubbed here
## ever changes who gets stomped, that is still _sweep() on the sim clock
## regardless of whether this ever runs.
func _animate_alive() -> void:
	if _anim_player == null:
		return
	if _elapsed - _headbutt_trigger < HEADBUTT_SECONDS:
		_scrub("Headbutt", _elapsed - _headbutt_trigger)
		return
	var here := Vector2(position.x, position.z)
	if here.distance_to(_target) > ARRIVAL_RADIUS:
		_scrub("Fast_Flying", fmod(_elapsed, _clip_length("Fast_Flying")))
	else:
		_scrub("Flying_Idle", fmod(_elapsed, _clip_length("Flying_Idle")))


func _animate_fall() -> void:
	var t := clampf(_fall_elapsed / _fall_seconds, 0.0, 1.0)
	_scrub("Death", t * _clip_length("Death"))


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
	position = Vector3(nx, _world.get_height(nx, nz) + ALTITUDE, nz)
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

	var before := _stomped
	for i in _bots.bots_within(here.x, here.y, STOMP_RADIUS):
		if _bots.kill(i):
			_stomped += 1
	if _stomped > before:
		_headbutt_trigger = _elapsed
		if _on_shake.is_valid():
			_on_shake.call(position, 0.2)

	var idle := BotManager.State.IDLE
	var moving_state := BotManager.State.MOVING
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
		if bot_state != idle and bot_state != moving_state:
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

	_report("Dragon: %d/%d health, %d archers + %d melee attacking, %d stomped"
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
	_release_fighters()
	_phase = _Phase.FALLING
	_fall_elapsed = 0.0
	_fall_start_y = position.y
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


## Crashes straight down to the ground while the Death clip plays out, both
## finishing together — see _fall_seconds's own doc. No legs to topple
## onto, the same reasoning Whormbus's own sink already used, just falling
## from the sky instead of sinking into the earth.
func _advance_fall(delta: float) -> void:
	_fall_elapsed += delta
	var t := clampf(_fall_elapsed / _fall_seconds, 0.0, 1.0)
	var ground := _world.get_height(position.x, position.z)
	position.y = lerpf(_fall_start_y, ground, t * t)
	if t >= 1.0:
		_phase = _Phase.DEAD
		_report("Dragon crashes to the ground: %d stomped before archers brought it down" % _stomped)


func _report(line: String) -> void:
	if _on_report.is_valid():
		_on_report.call(line)


func _build() -> void:
	var body: Node3D = load(MODEL_PATH).instantiate()
	body.scale = Vector3.ONE * (WINGSPAN / MODEL_WINGSPAN_UNITS)
	# Measured the same way every other imported boss was: Head sits on +Z
	# in rest pose (tools/inspect_dragon_tmp.gd, built and deleted after
	# use), the opposite of what _move()'s Basis.looking_at(dir, UP) assumes.
	body.rotation.y = PI
	add_child(body)
	_anim_player = _find_anim_player(body)
	if _anim_player == null:
		push_error("Dragon: model has no AnimationPlayer, it will not animate.")
		return
	_cache_clips()


func _find_anim_player(node: Node) -> AnimationPlayer:
	if node is AnimationPlayer:
		return node
	for child in node.get_children():
		var found := _find_anim_player(child)
		if found != null:
			return found
	return null


## Resolves every clip once. The file's own clip names came back armature-
## prefixed ("CharacterArmature|Death") rather than plain — parsed by
## splitting on "|" instead of hardcoding that prefix, so a re-export with
## a differently named armature would not silently break every lookup.
## Reads the Death clip's own real length into _fall_seconds here too — see
## that field's own doc.
func _cache_clips() -> void:
	for lib_name in _anim_player.get_animation_library_list():
		var lib: AnimationLibrary = _anim_player.get_animation_library(lib_name)
		for raw_name in lib.get_animation_list():
			var short: String = String(raw_name).split("|")[-1]
			var full: String = ("%s/%s" % [lib_name, raw_name]) if lib_name != "" else String(raw_name)
			_clip_names[short] = full
			_clip_resources[short] = lib.get_animation(raw_name)

	if _clip_resources.has("Death"):
		_fall_seconds = maxf((_clip_resources["Death"] as Animation).length, 0.1)

	var missing := 0
	for needed in ["Fast_Flying", "Flying_Idle", "Headbutt", "Death"]:
		if not _clip_resources.has(needed):
			missing += 1
	if missing > 0:
		push_error("Dragon: %d expected clips were not found; some animation will be missing." % missing)


func _clip_length(short_name: String) -> float:
	if not _clip_resources.has(short_name):
		return 1.0
	return maxf((_clip_resources[short_name] as Animation).length, 0.0001)


## Scrubs to `local_time` inside `short_name`'s own clip. speed_scale is
## pinned to 0 right after play() so the AnimationPlayer's own real-time
## process never advances it — render(alpha) fully controls clip time from
## its own elapsed clock instead, the same "sim decides, render only draws"
## split every hand-posed rig in this project already keeps.
func _scrub(short_name: String, local_time: float) -> void:
	if not _clip_names.has(short_name):
		return
	var full: String = _clip_names[short_name]
	if _current_clip != full:
		_anim_player.play(full)
		_anim_player.speed_scale = 0.0
		_current_clip = full
	_anim_player.seek(local_time, true)
