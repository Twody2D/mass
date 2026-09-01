class_name TrophyWeapon
extends Node3D
## The comically oversized prize a bot gets for being first to reach a supply
## crate — TODO.md's Drop redesign: "видимый бафф и особое оружие, которое
## визуально во много раз больше самого персонажа, чтобы это было забавным."
##
## Not part of the crowd's own MultiMesh — a bot rendered through a shared,
## batched mesh cannot carry a different weapon than every other instance in
## its tier, the same reason Monster/Kraken/Tornado/Creeper are each their
## own Node3D rather than an addition to KnightMesh. At most a handful of
## these exist at once (one per crate anybody has actually claimed), nowhere
## near the "no nodes per bot" rule, which is about the ten-thousand-strong
## crowd, not a handful of trophies.
##
## Tracks whoever won it every simulation tick, the same advance(delta)/
## render(alpha) interpolation split every other moving event actor uses — a
## bot's own position only updates on the tick, so drawing this on the same
## two-part schedule is what keeps it glued to its owner instead of lagging
## a frame behind a smoothly-interpolated crowd.
##
## Lives exactly as long as the buff it represents (BotManager.buff_until)
## and no longer — the two are driven by the same duration at the call
## site, not by watching each other, so there is nothing to keep in sync.

## A multiple of BOT_HEIGHT — big enough to be absurd next to a 2.4 m
## knight, the whole point of it.
const LENGTH_SHARE := 3.4

const BLADE_COLOR := Color(1.0, 0.82, 0.22)
const GUARD_COLOR := Color(0.5, 0.36, 0.06)

var _bots: BotManager
var _owner_index := -1
var _duration := 0.0
var _elapsed := 0.0
var _previous := Vector3.ZERO
var _current := Vector3.ZERO


## Builds a trophy tracking `owner_index` for `duration` seconds, ready to be
## adopted by the event manager.
static func start(bots: BotManager, owner_index: int, duration: float) -> TrophyWeapon:
	if bots == null or not bots.is_valid_index(owner_index):
		push_error("TrophyWeapon: needs a crowd and a valid bot index.")
		return null
	if duration <= 0.0:
		push_error("TrophyWeapon: needs a positive duration, got %f." % duration)
		return null

	var trophy := TrophyWeapon.new()
	trophy._bots = bots
	trophy._owner_index = owner_index
	trophy._duration = duration
	trophy._build()
	trophy._sync()
	trophy._previous = trophy.position
	trophy._current = trophy.position
	return trophy


## One simulation step. Returns false once the buff it represents has run out
## or its owner has died holding it.
func advance(delta: float) -> bool:
	_elapsed += delta
	if _elapsed >= _duration or _bots.alive[_owner_index] == 0:
		queue_free()
		return false
	_previous = _current
	_sync()
	_current = position
	return true


func render(alpha: float) -> void:
	position = _previous.lerp(_current, clampf(alpha, 0.0, 1.0))


## Held aloft overhead and tipped out to the side, so it reads against the
## sky instead of hiding behind the bot's own oversized helmet.
func _sync() -> void:
	var i := _owner_index
	var h: float = GameConfig.BOT_HEIGHT
	position = Vector3(_bots.pos_x[i], _bots.pos_y[i] + h * 1.05, _bots.pos_z[i])
	basis = Basis.looking_at(Vector3(_bots.face_x[i], 0.0, _bots.face_z[i]), Vector3.UP)
	rotate_object_local(Vector3.FORWARD, deg_to_rad(25.0))


func _build() -> void:
	var h: float = GameConfig.BOT_HEIGHT
	var length := h * LENGTH_SHARE

	var blade_material := StandardMaterial3D.new()
	blade_material.albedo_color = BLADE_COLOR
	blade_material.emission_enabled = true
	blade_material.emission = BLADE_COLOR
	blade_material.emission_energy_multiplier = 1.4
	blade_material.roughness = 0.3

	var blade := MeshInstance3D.new()
	blade.mesh = BoxMesh.new()
	(blade.mesh as BoxMesh).size = Vector3(h * 0.09, length, h * 0.16)
	blade.position = Vector3(0.0, length * 0.5, 0.0)
	blade.material_override = blade_material
	add_child(blade)

	var guard_material := StandardMaterial3D.new()
	guard_material.albedo_color = GUARD_COLOR
	guard_material.roughness = 0.6
	var guard := MeshInstance3D.new()
	guard.mesh = BoxMesh.new()
	(guard.mesh as BoxMesh).size = Vector3(h * 0.55, h * 0.13, h * 0.16)
	guard.material_override = guard_material
	add_child(guard)
