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

	for tier in _tiers:
		_update_tier(tier, alpha, pos_x, pos_y, pos_z, prev_x, prev_y, prev_z,
			vel_x, vel_z, face_x, face_z, alive)


## For tests and tools: whether each bot's instance, whichever tier currently
## carries it, has a non-degenerate transform right now. Same "zero basis
## means hidden" contract _update_tier() itself relies on, exposed once so a
## caller does not have to know tiers exist to ask "is bot i drawn".
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
		face_x: PackedFloat32Array, face_z: PackedFloat32Array, alive: PackedByteArray) -> void:
	var buffer := tier.buffer
	var b := 0
	for i in tier.members:
		if alive[i] == 0:
			# A dead bot keeps its slot, so the instance is collapsed to a point
			# instead of removed. Every triangle becomes degenerate and is thrown
			# away before rasterising, which costs less than reshaping the tier.
			buffer[b] = 0.0
			buffer[b + 1] = 0.0
			buffer[b + 2] = 0.0
			buffer[b + 4] = 0.0
			buffer[b + 5] = 0.0
			buffer[b + 6] = 0.0
			buffer[b + 8] = 0.0
			buffer[b + 9] = 0.0
			buffer[b + 10] = 0.0
			buffer[b + 15] = 0.0
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
