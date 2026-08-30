class_name CrowdRenderer
extends MultiMeshInstance3D
## Draws the whole crowd as a handful of MultiMeshes, one per level of detail:
## up close every knight gets the full model, far away the same shader draws a
## coarser one. Still one draw call per tier, never one per bot.
##
## Reads BotManager's arrays and writes nothing back. It knows about positions
## and teams; it knows nothing about why a bot is where it is.

## Floats per instance in MultiMesh.buffer: 12 for the transform, 4 for the
## custom data.
const FLOATS_PER_INSTANCE := 16

## Below this squared speed a bot counts as standing still, and its walk cycle
## stops rather than twitching from numerical noise.
const MIN_FACING_SPEED_SQUARED := 0.0001

## How long a corpse takes to topple over, from the moment it dies. Quick and
## snappy on purpose: a slow-motion collapse would be a spectacle for one
## bot, and there can be thousands of these on screen after one meteor.
const FALL_SECONDS := 0.6

## Written to the walk-speed custom-data slot for a corpse instead of 0 —
## never a real speed, so knight.gdshader reads it as "this one is dead" and
## drains its colour towards grey, the one cue that still reads as "not
## alive" from straight overhead, where a lying silhouette can otherwise
## look close enough to a standing one.
const DEAD_SENTINEL := -1.0

## The shader indexes a fixed size palette, so the crowd needs no per-team
## material. Room for more teams than the game currently has.
const MAX_TEAMS := 8

## Irrational strides, so per-bot values spread evenly across the crowd instead
## of banding. Derived from the index rather than stored: a phase that can be
## recomputed for free does not need 40 KB of memory.
const PHASE_STRIDE := 0.6180339887
const VARIATION_STRIDE := 0.7548776662

## Nearest first. Every tier keeps the same proportions (KnightMesh's walk
## cycle landmarks never move), only how round the two prisms are and whether
## the sword/eye/second boot exist. Distance bands live in GameConfig, not
## here: geometry and thresholds are independent knobs.
const LOD_LEVELS := [
	{"id": &"lod_near", "helmet_sides": 6, "body_sides": 4, "details": true},
	{"id": &"lod_medium", "helmet_sides": 5, "body_sides": 4, "details": true},
	{"id": &"lod_far", "helmet_sides": 4, "body_sides": 3, "details": false},
	{"id": &"lod_very_far", "helmet_sides": 3, "body_sides": 3, "details": false},
]

## How many rendered frames between recomputing which tier each bot belongs
## to. Tier membership changes slowly next to camera motion, and resizing four
## MultiMeshes every frame would spend more than it saves — the same "work
## less often when nothing needs it every frame" rule the simulation already
## follows for AI decisions.
const LOD_REFRESH_FRAMES := 6

## One entry per LOD_LEVELS, built once by _ensure_tiers().
class _Tier:
	var node: MultiMeshInstance3D
	var members := PackedInt32Array()
	var buffer := PackedFloat32Array()

## Assigned by Main, which owns the wiring. Null is a valid state — some
## verify tools never wire a camera — and means every bot stays on the
## nearest tier, the single-MultiMesh behaviour this renderer had before LOD.
var camera: Camera3D

## Assigned by Main, which owns the wiring.
var bots: BotManager

var _tiers: Array[_Tier] = []
var _lod_refresh_counter := 0


## Rebuilds every tier for the current crowd. Call after bots have spawned.
func rebuild() -> void:
	if bots == null:
		push_error("CrowdRenderer: no BotManager assigned, cannot render.")
		return

	_ensure_tiers()
	_lod_refresh_counter = 0
	_assign_tiers()
	update_transforms()


## Rewrites every instance transform on every tier and uploads each buffer,
## once per rendered frame. `alpha` is how far the frame sits between the
## previous simulation tick and the current one, from 0 to 1.
##
## Without this the crowd would only move when a tick lands, which at 20 Hz
## means holding still for three frames and then jumping. Interpolating costs
## one extra upload per frame per tier and buys motion at the frame rate.
func update_transforms(alpha: float = 1.0) -> void:
	if bots == null or multimesh == null or bots.count == 0:
		return

	_ensure_tiers()
	_lod_refresh_counter += 1
	if _lod_refresh_counter >= LOD_REFRESH_FRAMES:
		_lod_refresh_counter = 0
		_assign_tiers()

	var pos_x := bots.pos_x
	var pos_y := bots.pos_y
	var pos_z := bots.pos_z
	var prev_x := bots.prev_x
	var prev_y := bots.prev_y
	var prev_z := bots.prev_z
	var vel_x := bots.vel_x
	var vel_z := bots.vel_z
	var face_x := bots.face_x
	var face_z := bots.face_z
	var alive := bots.alive
	var dwell_until := bots.dwell_until
	var health := bots.health
	var now := bots.time_now()

	for tier in _tiers:
		_update_tier(tier, alpha, pos_x, pos_y, pos_z, prev_x, prev_y, prev_z,
			vel_x, vel_z, face_x, face_z, alive, dwell_until, health, now)


## For tests and tools: whether each bot's instance, whichever tier currently
## carries it, has a non-degenerate transform right now. Corpses count as
## drawn too — a fallen body is not hidden, only living bots that have not
## spawned yet (or a stale slot before the first tier assignment) collapse to
## a zero basis.
func visible_bots() -> PackedByteArray:
	var visible := PackedByteArray()
	if bots == null:
		return visible
	visible.resize(bots.count)
	const BASIS_FLOATS := [0, 1, 2, 4, 5, 6, 8, 9, 10]
	for tier in _tiers:
		var buffer := tier.buffer
		var b := 0
		for i in tier.members:
			for f in BASIS_FLOATS:
				if buffer[b + f] != 0.0:
					visible[i] = 1
					break
			b += FLOATS_PER_INSTANCE
	return visible


## For tests: which LOD tier currently carries a given bot, or an empty name
## if tiers have never been assigned yet.
func tier_of(bot_index: int) -> StringName:
	for idx in _tiers.size():
		if _tiers[idx].members.has(bot_index):
			return LOD_LEVELS[idx].id
	return &""


## For tests and tools: total instances across every tier. Every bot belongs
## to exactly one tier, so this should always equal bots.count.
func rendered_instance_count() -> int:
	var total := 0
	for tier in _tiers:
		total += tier.node.multimesh.instance_count
	return total


## For tools: instances and triangle cost per tier, right now.
func tier_report() -> Array[Dictionary]:
	var report: Array[Dictionary] = []
	for idx in _tiers.size():
		var tier := _tiers[idx]
		var level: Dictionary = LOD_LEVELS[idx]
		var mesh := tier.node.multimesh.mesh
		report.append({
			"id": level.id,
			"instances": tier.node.multimesh.instance_count,
			"triangles": mesh.get_faces().size() / 3 if mesh != null else 0,
		})
	return report


func _ensure_tiers() -> void:
	if not _tiers.is_empty():
		return

	var material := _build_material()
	for idx in LOD_LEVELS.size():
		var level: Dictionary = LOD_LEVELS[idx]
		var tier := _Tier.new()
		if idx == 0:
			# The renderer is itself a MultiMeshInstance3D: the nearest tier
			# needs no extra node, it just reuses the one Main already wired.
			tier.node = self
		else:
			var mmi := MultiMeshInstance3D.new()
			mmi.name = String(level.id)
			mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			add_child(mmi)
			tier.node = mmi

		var mesh := KnightMesh.build(GameConfig.BOT_HEIGHT, level.helmet_sides, level.body_sides,
			level.details)
		mesh.surface_set_material(0, material)

		var mm := MultiMesh.new()
		mm.transform_format = MultiMesh.TRANSFORM_3D
		# Custom data rather than instance colours: an instance colour would
		# multiply every vertex, tinting steel and leather along with the
		# tabard. The instance carries a team index instead, and the shader
		# applies it only where the mesh asks for it.
		mm.use_colors = false
		mm.use_custom_data = true
		mm.mesh = mesh
		tier.node.multimesh = mm

		_tiers.append(tier)


## Writes a falling or fallen corpse's transform: the standing yaw basis,
## rotated an extra `angle` around the model's own local X axis, pivoting at
## its origin — which KnightMesh already puts at the feet (see its own
## "standing on the origin" comment). A rotation about that point needs no
## translation fix-up: the feet stay exactly where the bot died and the rest
## of the body swings down around them, the same cheap "no real physics"
## trick this project already uses for a knocked-over camera or a cracked
## meteor.
##
## `elapsed` measures time since death, for the fall's own progress.
## `ground_cos` is cos() of the pitch BotManager.kill() already solved the
## corpse should settle at — 1.0 for flat ground, less (down to -1.0) the
## steeper the real terrain drops away in the direction it fell — so the
## body's far end lands on the slope instead of assuming flat ground and
## clipping into a hillside or hanging in the air over a drop. The fall
## direction (which side of facing it topples towards) is BotManager's own
## call, baked into ground_cos already; this only needs its sign back, via
## the same index parity BotManager used to pick it.
func _write_corpse(buffer: PackedFloat32Array, b: int, index: int, x: float, y: float, z: float,
		sin_yaw: float, cos_yaw: float, elapsed: float, ground_cos: float) -> void:
	# Quadratic ease-in: slow to leave standing, fast into the ground — a
	# toppling body picks up speed, it does not coast to a stop.
	var t := clampf(elapsed / FALL_SECONDS, 0.0, 1.0)
	var eased := t * t
	var direction := 1.0 if index % 2 == 0 else -1.0

	# Interpolating cos(pitch) directly, rather than the angle, skips every
	# cos()/sin() call this would otherwise need — a lerp and one sqrt, for
	# every corpse, every frame, for as long as any of them are on screen,
	# which after a big enough event is most of the crowd.
	var ca := lerpf(1.0, ground_cos, eased)
	var sa := sqrt(maxf(0.0, 1.0 - ca * ca)) * direction

	# M_yaw * R_pitch(local X), derived once on paper rather than composed at
	# runtime with Godot's Basis.
	buffer[b] = cos_yaw
	buffer[b + 1] = sin_yaw * sa
	buffer[b + 2] = sin_yaw * ca
	buffer[b + 3] = x
	buffer[b + 4] = 0.0
	buffer[b + 5] = ca
	buffer[b + 6] = -sa
	buffer[b + 7] = y
	buffer[b + 8] = -sin_yaw
	buffer[b + 9] = cos_yaw * sa
	buffer[b + 10] = cos_yaw * ca
	buffer[b + 11] = z
	buffer[b + 15] = DEAD_SENTINEL


## For tests: the world-space direction the model's own local +Y axis
## currently points, for whichever tier is carrying `bot_index`. A standing
## bot reads close to (0, 1, 0); a fully fallen one reads close to its own
## facing direction, with a near-zero Y — the one part of "did this actually
## topple over" that does not require eyes on a rendered frame.
func local_up_of(bot_index: int) -> Vector3:
	for tier in _tiers:
		var members := tier.members
		var slot := members.find(bot_index)
		if slot == -1:
			continue
		var b := slot * FLOATS_PER_INSTANCE
		var buffer := tier.buffer
		return Vector3(buffer[b + 1], buffer[b + 5], buffer[b + 9])
	return Vector3.ZERO


func _build_material() -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/knight.gdshader")

	# The palette is uploaded once. Colours are authored in sRGB and converted
	# here, because everything the shader writes to ALBEDO is linear. Shared
	# across every tier's mesh: the uniforms are identical, only the geometry
	# differs.
	var palette := PackedColorArray()
	palette.resize(MAX_TEAMS)
	var teams: Array = GameConfig.TEAM_COLORS
	for i in MAX_TEAMS:
		var source: Color = teams[i] if i < teams.size() else Color.WHITE
		palette[i] = source.srgb_to_linear()
	material.set_shader_parameter("team_colors", palette)
	material.set_shader_parameter("bot_height", GameConfig.BOT_HEIGHT)
	material.set_shader_parameter("reference_speed", GameConfig.BOT_MOVE_SPEED)
	return material


## Sorts every bot into the tier its distance from the camera belongs to, then
## resizes each tier's MultiMesh and rewrites its per-bot custom data — team,
## walk phase, visual variation. Unlike a single MultiMesh, that data cannot
## be written once at spawn: which slot a bot lands in shifts every time tier
## membership is recomputed.
func _assign_tiers() -> void:
	if bots == null:
		return
	_ensure_tiers()

	for tier in _tiers:
		tier.members.resize(0)

	if camera == null:
		var near_members := PackedInt32Array()
		near_members.resize(bots.count)
		for i in bots.count:
			near_members[i] = i
		_tiers[0].members = near_members
	else:
		var cam_pos := camera.global_position
		var pos_x := bots.pos_x
		var pos_y := bots.pos_y
		var pos_z := bots.pos_z
		var thresholds := [
			GameConfig.LOD_NEAR_DISTANCE * GameConfig.LOD_NEAR_DISTANCE,
			GameConfig.LOD_MEDIUM_DISTANCE * GameConfig.LOD_MEDIUM_DISTANCE,
			GameConfig.LOD_FAR_DISTANCE * GameConfig.LOD_FAR_DISTANCE,
		]
		for i in bots.count:
			var dx := pos_x[i] - cam_pos.x
			var dy := pos_y[i] - cam_pos.y
			var dz := pos_z[i] - cam_pos.z
			var dist_sq := dx * dx + dy * dy + dz * dz
			var tier_index := thresholds.size()
			for t in thresholds.size():
				if dist_sq < thresholds[t]:
					tier_index = t
					break
			_tiers[tier_index].members.append(i)

	for tier in _tiers:
		tier.node.multimesh.instance_count = tier.members.size()
		tier.buffer.resize(tier.members.size() * FLOATS_PER_INSTANCE)
		_write_tier_custom_data(tier)


func _write_tier_custom_data(tier: _Tier) -> void:
	var buffer := tier.buffer
	var b := 12
	for i in tier.members:
		buffer[b] = float(bots.team[i])
		buffer[b + 1] = fmod(i * PHASE_STRIDE, 1.0)
		buffer[b + 2] = fmod(i * VARIATION_STRIDE, 1.0)
		buffer[b + 3] = 0.0
		b += FLOATS_PER_INSTANCE


func _update_tier(tier: _Tier, alpha: float, pos_x: PackedFloat32Array, pos_y: PackedFloat32Array,
		pos_z: PackedFloat32Array, prev_x: PackedFloat32Array, prev_y: PackedFloat32Array,
		prev_z: PackedFloat32Array, vel_x: PackedFloat32Array, vel_z: PackedFloat32Array,
		face_x: PackedFloat32Array, face_z: PackedFloat32Array, alive: PackedByteArray,
		dwell_until: PackedFloat32Array, health: PackedFloat32Array, now: float) -> void:
	var buffer := tier.buffer
	var b := 0
	for i in tier.members:
		if alive[i] == 0:
			_write_corpse(buffer, b, i, pos_x[i], pos_y[i], pos_z[i], face_x[i], face_z[i],
				now - dwell_until[i], health[i])
			b += FLOATS_PER_INSTANCE
			continue

		# Facing without trigonometry: the simulation keeps it as a unit vector,
		# which already is the sine and cosine of the yaw. No atan2, no sin, no
		# cos, ten thousand times a frame.
		var sin_yaw := face_x[i]
		var cos_yaw := face_z[i]

		var vx := vel_x[i]
		var vz := vel_z[i]
		var speed_squared := vx * vx + vz * vz
		var speed := 0.0
		if speed_squared > MIN_FACING_SPEED_SQUARED:
			speed = sqrt(speed_squared)

		# Rows of the 3x4 transform, as MultiMesh.buffer expects them. The
		# knight is modelled standing on its own origin, so the position needs
		# no vertical offset.
		buffer[b] = cos_yaw
		buffer[b + 1] = 0.0
		buffer[b + 2] = sin_yaw
		buffer[b + 3] = prev_x[i] + (pos_x[i] - prev_x[i]) * alpha
		buffer[b + 4] = 0.0
		buffer[b + 5] = 1.0
		buffer[b + 6] = 0.0
		buffer[b + 7] = prev_y[i] + (pos_y[i] - prev_y[i]) * alpha
		buffer[b + 8] = -sin_yaw
		buffer[b + 9] = 0.0
		buffer[b + 10] = cos_yaw
		buffer[b + 11] = prev_z[i] + (pos_z[i] - prev_z[i]) * alpha
		# Current speed drives the walk cycle in the shader, so a standing
		# knight stands still instead of marching on the spot.
		buffer[b + 15] = speed
		b += FLOATS_PER_INSTANCE

	tier.node.multimesh.buffer = buffer
