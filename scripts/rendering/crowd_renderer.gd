class_name CrowdRenderer
extends MultiMeshInstance3D
## Draws the whole crowd as a single MultiMesh: one mesh, one material, one draw
## call for ten thousand knights.
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

## Assigned by Main, which owns the wiring.
var bots: BotManager

## One persistent buffer, uploaded whole in a single assignment. Writing 10 000
## transforms into an array and handing it over once costs a fraction of 10 000
## set_instance_transform() calls across the script/engine boundary.
var _buffer := PackedFloat32Array()


## Rebuilds the MultiMesh for the current crowd. Call after bots have spawned.
func rebuild() -> void:
	if bots == null:
		push_error("CrowdRenderer: no BotManager assigned, cannot render.")
		return

	if multimesh == null:
		multimesh = MultiMesh.new()
		multimesh.transform_format = MultiMesh.TRANSFORM_3D
		# Custom data rather than instance colours: an instance colour would
		# multiply every vertex, tinting steel and leather along with the
		# tabard. The instance carries a team index instead, and the shader
		# applies it only where the mesh asks for it.
		multimesh.use_colors = false
		multimesh.use_custom_data = true
		multimesh.mesh = _build_knight()

	multimesh.instance_count = bots.count
	_buffer.resize(bots.count * FLOATS_PER_INSTANCE)
	_write_custom_data()
	update_transforms()


## Rewrites every instance transform and uploads the buffer, once per rendered
## frame. `alpha` is how far the frame sits between the previous simulation tick
## and the current one, from 0 to 1.
##
## Without this the crowd would only move when a tick lands, which at 20 Hz
## means holding still for three frames and then jumping. Interpolating costs
## one extra upload per frame and buys motion at the frame rate.
func update_transforms(alpha: float = 1.0) -> void:
	if bots == null or multimesh == null or bots.count == 0:
		return

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

	var b := 0
	for i in bots.count:
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
		_buffer[b] = cos_yaw
		_buffer[b + 1] = 0.0
		_buffer[b + 2] = sin_yaw
		_buffer[b + 3] = prev_x[i] + (pos_x[i] - prev_x[i]) * alpha
		_buffer[b + 4] = 0.0
		_buffer[b + 5] = 1.0
		_buffer[b + 6] = 0.0
		_buffer[b + 7] = prev_y[i] + (pos_y[i] - prev_y[i]) * alpha
		_buffer[b + 8] = -sin_yaw
		_buffer[b + 9] = 0.0
		_buffer[b + 10] = cos_yaw
		_buffer[b + 11] = prev_z[i] + (pos_z[i] - prev_z[i]) * alpha
		# Current speed drives the walk cycle in the shader, so a standing
		# knight stands still instead of marching on the spot.
		_buffer[b + 15] = speed
		b += FLOATS_PER_INSTANCE

	multimesh.buffer = _buffer


## Per-bot data the shader needs.
##
##   x  team index          written once at spawn
##   y  walk cycle phase    written once at spawn
##   z  visual variation    written once at spawn, reserved
##   w  current speed       rewritten every frame by update_transforms()
func _write_custom_data() -> void:
	var b := 12
	for i in bots.count:
		_buffer[b] = float(bots.team[i])
		_buffer[b + 1] = fmod(i * PHASE_STRIDE, 1.0)
		_buffer[b + 2] = fmod(i * VARIATION_STRIDE, 1.0)
		_buffer[b + 3] = 0.0
		b += FLOATS_PER_INSTANCE


func _build_knight() -> Mesh:
	var mesh := KnightMesh.build(GameConfig.BOT_HEIGHT)

	var material := ShaderMaterial.new()
	material.shader = load("res://assets/materials/knight.gdshader")

	# The palette is uploaded once. Colours are authored in sRGB and converted
	# here, because everything the shader writes to ALBEDO is linear.
	var palette := PackedColorArray()
	palette.resize(MAX_TEAMS)
	var teams: Array = GameConfig.TEAM_COLORS
	for i in MAX_TEAMS:
		var source: Color = teams[i] if i < teams.size() else Color.WHITE
		palette[i] = source.srgb_to_linear()
	material.set_shader_parameter("team_colors", palette)
	material.set_shader_parameter("bot_height", GameConfig.BOT_HEIGHT)
	material.set_shader_parameter("reference_speed", GameConfig.BOT_MOVE_SPEED)

	mesh.surface_set_material(0, material)
	return mesh
