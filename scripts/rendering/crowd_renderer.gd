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

## Below this squared speed a bot is treated as standing still and keeps facing
## forward, rather than spinning from numerical noise.
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


## Rewrites every instance transform and uploads the buffer. Called once per
## frame from the simulation clock, however many ticks that frame ran.
func update_transforms() -> void:
	if bots == null or multimesh == null or bots.count == 0:
		return

	var pos_x := bots.pos_x
	var pos_y := bots.pos_y
	var pos_z := bots.pos_z
	var vel_x := bots.vel_x
	var vel_z := bots.vel_z

	var b := 0
	for i in bots.count:
		# Facing without trigonometry: the normalised velocity already is the
		# sine and cosine of the yaw, so 10 000 atan2/sin/cos calls per tick
		# turn into one square root and two divisions.
		var vx := vel_x[i]
		var vz := vel_z[i]
		var speed_squared := vx * vx + vz * vz
		var sin_yaw := 0.0
		var cos_yaw := 1.0
		if speed_squared > MIN_FACING_SPEED_SQUARED:
			var inverse := 1.0 / sqrt(speed_squared)
			sin_yaw = vx * inverse
			cos_yaw = vz * inverse

		# Rows of the 3x4 transform, as MultiMesh.buffer expects them. The
		# knight is modelled standing on its own origin, so the position needs
		# no vertical offset.
		_buffer[b] = cos_yaw
		_buffer[b + 1] = 0.0
		_buffer[b + 2] = sin_yaw
		_buffer[b + 3] = pos_x[i]
		_buffer[b + 4] = 0.0
		_buffer[b + 5] = 1.0
		_buffer[b + 6] = 0.0
		_buffer[b + 7] = pos_y[i]
		_buffer[b + 8] = -sin_yaw
		_buffer[b + 9] = 0.0
		_buffer[b + 10] = cos_yaw
		_buffer[b + 11] = pos_z[i]
		b += FLOATS_PER_INSTANCE

	multimesh.buffer = _buffer


## Per-bot data the shader needs, written once at spawn and then left alone by
## update_transforms(), which only touches the first twelve floats of each slot.
##
##   x  team index
##   y  animation phase, so the crowd does not move as one
##   z  visual variation, reserved
##   w  spare
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

	mesh.surface_set_material(0, material)
	return mesh
