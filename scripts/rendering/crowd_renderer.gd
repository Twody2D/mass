class_name CrowdRenderer
extends MultiMeshInstance3D
## Draws the whole crowd as a single MultiMesh: one mesh, one material, one draw
## call for ten thousand bots.
##
## Reads BotManager's arrays and writes nothing back. It knows about positions
## and teams; it knows nothing about why a bot is where it is.

## Floats per instance in MultiMesh.buffer: 12 for the transform, 4 for colour.
const FLOATS_PER_INSTANCE := 16

## Below this squared speed a bot is treated as standing still and keeps facing
## forward, rather than spinning from numerical noise.
const MIN_FACING_SPEED_SQUARED := 0.0001

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
		multimesh.use_colors = true
		multimesh.mesh = _build_bot_mesh()

	multimesh.instance_count = bots.count
	_buffer.resize(bots.count * FLOATS_PER_INSTANCE)
	_write_colors()
	update_transforms()


## Rewrites every instance transform and uploads the buffer. Called once per
## simulation tick, not once per frame.
func update_transforms() -> void:
	if bots == null or multimesh == null or bots.count == 0:
		return

	var pos_x := bots.pos_x
	var pos_y := bots.pos_y
	var pos_z := bots.pos_z
	var vel_x := bots.vel_x
	var vel_z := bots.vel_z
	var lift := GameConfig.BOT_HEIGHT * 0.5

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

		# Rows of the 3x4 transform, as MultiMesh.buffer expects them.
		_buffer[b] = cos_yaw
		_buffer[b + 1] = 0.0
		_buffer[b + 2] = sin_yaw
		_buffer[b + 3] = pos_x[i]
		_buffer[b + 4] = 0.0
		_buffer[b + 5] = 1.0
		_buffer[b + 6] = 0.0
		_buffer[b + 7] = pos_y[i] + lift
		_buffer[b + 8] = -sin_yaw
		_buffer[b + 9] = 0.0
		_buffer[b + 10] = cos_yaw
		_buffer[b + 11] = pos_z[i]
		b += FLOATS_PER_INSTANCE

	multimesh.buffer = _buffer


## Team colours never change, so they are written once and then left alone by
## update_transforms(), which only touches the first twelve floats of each slot.
func _write_colors() -> void:
	var colors: Array = GameConfig.TEAM_COLORS
	var linear := PackedColorArray()
	linear.resize(colors.size())
	for t in colors.size():
		# Instance colours reach the shader as linear, same as vertex colours.
		linear[t] = (colors[t] as Color).srgb_to_linear()

	var b := 12
	for i in bots.count:
		var color := linear[bots.team[i]]
		_buffer[b] = color.r
		_buffer[b + 1] = color.g
		_buffer[b + 2] = color.b
		_buffer[b + 3] = color.a
		b += FLOATS_PER_INSTANCE


func _build_bot_mesh() -> Mesh:
	var mesh := CapsuleMesh.new()
	mesh.radius = GameConfig.BOT_RADIUS
	mesh.height = GameConfig.BOT_HEIGHT
	# As coarse as a capsule goes. At this scale the silhouette is all that
	# survives anyway, and every triangle is paid for ten thousand times.
	mesh.radial_segments = 6
	mesh.rings = 1

	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 0.9
	mesh.material = material
	return mesh
