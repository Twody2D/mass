extends Node
## Renders the main scene and saves a PNG. The only way to catch problems that
## look fine in the data and wrong on screen.
##
## Optional camera override, passed after a bare --:
##   godot --path . res://tools/screenshot.tscn -- --bots=1000 --cam=0,20,380 --look=0,25,100
##
## --meteor drops one on bot 0 and frames it, so the flash can be seen rather
## than trusted. Combine with --wait to pick a moment in the 0.9 s it lives.

func _ready() -> void:
	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)

	var cam: Camera3D = main.get_node("Camera3D")
	var world: Node3D = main.get_node("World")
	var crowd: CrowdRenderer = main.get_node("Crowd")
	var out := "res://tools/output/screenshot.png"
	var follow := -1
	var ticks := 0
	var wait := 0.0
	var open_menu := false
	var meteor := false
	var meteor_at := Vector3.ZERO
	var flood := false
	var flood_seconds := 0.0
	var framed := false

	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--bots="):
			main.rebuild(GameConfig.map_seed, arg.substr(7).to_int())
		if arg.begins_with("--cam="):
			cam.position = _parse_vector(arg.substr(6))
			framed = true
		elif arg.begins_with("--look="):
			cam.look_at(_parse_vector(arg.substr(7)), Vector3.UP)
			framed = true
		elif arg.begins_with("--meteor"):
			meteor = true
		elif arg.begins_with("--flood"):
			flood = true
			# --flood=6 rises in six seconds instead of the default half minute,
			# so a still can be taken without waiting through the whole thing.
			if arg.begins_with("--flood="):
				flood_seconds = arg.substr(8).to_float()
		elif arg == "--menu":
			open_menu = true
		elif arg.begins_with("--wait="):
			wait = arg.substr(7).to_float()
		elif arg.begins_with("--ticks="):
			ticks = arg.substr(8).to_int()
		elif arg.begins_with("--follow="):
			follow = arg.substr(9).to_int()
		elif arg.begins_with("--out="):
			out = "res://tools/output/%s" % arg.substr(6)

	# Advancing the simulation by hand gives a repeatable pose, which a race
	# against however many frames the window happens to render does not.
	var bots_node: BotManager = main.get_node("Bots")
	for t in ticks:
		bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, t)

	# Framing a single bot needs to happen after the crowd exists, and the bot
	# stands wherever the island put it rather than at the origin.
	var bots: BotManager = main.get_node("Bots")
	if follow >= 0 and bots.is_valid_index(follow):
		var target := Vector3(bots.pos_x[follow], bots.pos_y[follow], bots.pos_z[follow])
		# Framed in units of the bot, so the shot survives a change of scale.
		var h: float = GameConfig.BOT_HEIGHT
		cam.position = target + Vector3(0.9, 0.55, 1.5) * h
		cam.look_at(target + Vector3(0.0, 0.5 * h, 0.0), Vector3.UP)

	# Fired after the ticks, so the crowd it lands on has spread out. Aimed at
	# bot 0 rather than at random: a shot of an empty beach proves nothing.
	if meteor:
		var events: EventManager = main.get_node("Events")
		meteor_at = Vector3(bots_node.pos_x[0], bots_node.pos_y[0], bots_node.pos_z[0])
		events.trigger(&"meteor", {"x": meteor_at.x, "z": meteor_at.z})
		print("event          : %s" % events.last_description)
		if not framed:
			# Framed off the blast radius, so the shot still holds the whole thing
			# when the meteor is resized. It has to fit the sky it comes out of,
			# the ground it hits and the column that stands up afterwards.
			var reach: float = GameConfig.MAP_SIZE * MeteorEvent.BLAST_SHARE_OF_MAP
			cam.position = meteor_at + Vector3(0.0, reach * 1.1, reach * 2.9)
			cam.look_at(meteor_at + Vector3(0.0, reach * 0.9, 0.0), Vector3.UP)

	if flood:
		var events: EventManager = main.get_node("Events")
		var params := {}
		if flood_seconds > 0.0:
			params["seconds"] = flood_seconds
		events.trigger(&"flood", params)
		print("event          : %s" % events.last_description)
		if not framed:
			# The whole island, because the shot is the coastline disappearing
			# rather than anything happening at one point on it.
			var reach: float = GameConfig.MAP_SIZE
			cam.position = Vector3(0.0, reach * 0.25, reach * 0.42)
			cam.look_at(Vector3(0.0, reach * 0.015, 0.0), Vector3.UP)

	print("sim            : paused=%s tick=%d speed=%.2f" % [main.paused, main.tick_count, main.sim_speed])
	print("bot 0          : vel=(%.2f, %.2f)" % [bots_node.vel_x[0], bots_node.vel_z[0]])
	print("bots           : %d, %d triangles each"
		% [crowd.multimesh.instance_count, crowd.multimesh.mesh.get_faces().size() / 3])
	print("camera at      : ", cam.global_position)
	print("camera forward : ", -cam.global_transform.basis.z)
	print("ground below   : %.2f m" % world.get_height(cam.global_position.x, cam.global_position.z))

	if open_menu:
		(main.get_node("PauseMenu") as PauseMenu).open()

	# The walk cycle is driven by TIME, so capturing at different moments is the
	# only way to see whether the legs actually move.
	var deadline := Time.get_ticks_msec() + int(wait * 1000.0)
	for i in 8:
		await RenderingServer.frame_post_draw
	while Time.get_ticks_msec() < deadline:
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
