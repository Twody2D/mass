extends Node
## Renders the main scene and saves a PNG. The only way to catch problems that
## look fine in the data and wrong on screen.
##
## Optional camera override, passed after a bare --:
##   godot --path . res://tools/screenshot.tscn -- --bots=1000 --cam=0,20,380 --look=0,25,100

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)

	var cam: Camera3D = main.get_node("Camera3D")
	var world: Node3D = main.get_node("World")
	var crowd: CrowdRenderer = main.get_node("Crowd")
	var out := "res://tools/output/screenshot.png"
	var follow := -1

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bots="):
			main.rebuild(GameConfig.map_seed, arg.substr(7).to_int())
		if arg.begins_with("--cam="):
			cam.position = _parse_vector(arg.substr(6))
		elif arg.begins_with("--look="):
			cam.look_at(_parse_vector(arg.substr(7)), Vector3.UP)
		elif arg.begins_with("--follow="):
			follow = arg.substr(9).to_int()
		elif arg.begins_with("--out="):
			out = "res://tools/output/%s" % arg.substr(6)

	# Framing a single bot needs to happen after the crowd exists, and the bot
	# stands wherever the island put it rather than at the origin.
	var bots: BotManager = main.get_node("Bots")
	if follow >= 0 and bots.is_valid_index(follow):
		var target := Vector3(bots.pos_x[follow], bots.pos_y[follow], bots.pos_z[follow])
		cam.position = target + Vector3(1.7, 1.3, 2.7)
		cam.look_at(target + Vector3(0.0, 0.9, 0.0), Vector3.UP)

	print("bots           : %d, %d triangles each"
		% [crowd.multimesh.instance_count, crowd.multimesh.mesh.get_faces().size() / 3])
	print("camera at      : ", cam.global_position)
	print("camera forward : ", -cam.global_transform.basis.z)
	print("ground below   : %.2f m" % world.get_height(cam.global_position.x, cam.global_position.z))

	for i in 8:
		await RenderingServer.frame_post_draw
	DirAccess.make_dir_recursive_absolute("res://tools/output")
	var img := get_viewport().get_texture().get_image()
	img.save_png(out)
	print("saved          : ", out)
	get_tree().quit()


func _parse_vector(text: String) -> Vector3:
	var parts := text.split(",")
	if parts.size() != 3:
		push_error("screenshot: expected x,y,z but got \"%s\"." % text)
		return Vector3.ZERO
	return Vector3(parts[0].to_float(), parts[1].to_float(), parts[2].to_float())
