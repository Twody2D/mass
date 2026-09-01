extends Node
## Renders the main scene and saves a PNG. The only way to catch problems that
## look fine in the data and wrong on screen.
##
## Optional camera override, passed after a bare --:
##   godot --path . res://tools/screenshot.tscn -- --bots=1000 --cam=0,20,380 --look=0,25,100
##
## --meteor drops one on bot 0 and frames it, so the flash can be seen rather
## than trusted. Combine with --wait to pick a moment in the 0.9 s it lives.
## --flood takes a duration the same way (--flood=6) so a minute long rise
## can be caught inside a screenshot. --zone always runs 200 ticks past the
## trigger so at least one jump can be seen, and its own number (--zone=6)
## shortens how long each jump position lasts rather than the whole event,
## which now jumps several times rather than running once.
## --war loads the dedicated war island (the same reasoning --volcano loads
## its own map for) and has no fixed duration to shrink, so its number
## instead picks how many ticks to run after triggering it (--war=600 for
## well into the fight).
## --drop takes the same kind of number, in ticks after the crate lands
## (--drop=200 for well into the crush).
## --volcano takes a duration the same way --flood/--zone do (--volcano=8 to
## catch the lava mid-spread instead of waiting out the real 40 s).
## --monster has no fixed duration either, so its number is ticks to run
## after it rises (--monster=100 to get well into the fight).
## --kraken works the same way as --monster: its number is ticks to run
## after it surfaces (--kraken=80 to get well into the fight).
## --earthquake has nothing to wait out — the rifts open and the deaths
## happen the instant it fires — so it takes no number at all.
## --tornado works the same way as --monster/--kraken: its number is ticks to
## run after it touches down (--tornado=60 to get well into the wandering).
## --chicken works the same way as --monster/--kraken: its number is ticks to
## run after it is triggered (--chicken=150 to get well past the landing and
## into the fight).
## --creepers takes how many to spawn (--creepers=4), defaulting to
## CreeperSwarm.COUNT; its ticks are fixed (CREEPER_WAIT_TICKS below) since
## there is no single actor to frame on.
## --scene=res://scenes/boss_arena.tscn loads any other scene by path;
## --volcano is really just a shorthand for --scene=res://scenes/volcano.tscn.

func _ready() -> void:
	# The volcano lives on its own dedicated map now (see ARCHITECTURE.md,
	# "Volcano as its own map") — main.tscn has no mountain to erupt, so
	# --volcano loads that scene instead, the same way it always has just
	# under a different name. --scene= is the general escape hatch for any
	# other map (the boss arena, in particular), checked first so it wins
	# over --volcano if both are somehow given.
	var scene_path := "res://scenes/main.tscn"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--volcano"):
			scene_path = "res://scenes/volcano.tscn"
		elif arg.begins_with("--war"):
			# War is only registered on its own dedicated map, the same
			# reasoning --volcano already picks scenes/volcano.tscn for.
			scene_path = "res://scenes/war_island.tscn"
		elif arg.begins_with("--scene="):
			scene_path = arg.substr(8)
	var packed: PackedScene = load(scene_path)
	var main: Node3D = packed.instantiate()
	add_child(main)

	var cam: CameraRig = main.get_node("Camera3D")
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
	var zone := false
	var zone_seconds := 0.0
	var war := false
	var war_ticks := 200
	var drop := false
	var drop_ticks := 100
	var volcano := false
	var volcano_seconds := 0.0
	var monster := false
	var monster_ticks := 0
	var kraken := false
	var kraken_ticks := 0
	var earthquake := false
	var tornado := false
	var tornado_ticks := 0
	var chicken := false
	var chicken_ticks := 0
	var creepers := false
	var creeper_count := 0
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
		elif arg.begins_with("--zone"):
			zone = true
			if arg.begins_with("--zone="):
				zone_seconds = arg.substr(7).to_float()
		elif arg.begins_with("--war"):
			war = true
			if arg.begins_with("--war="):
				war_ticks = arg.substr(6).to_int()
		elif arg.begins_with("--drop"):
			drop = true
			if arg.begins_with("--drop="):
				drop_ticks = arg.substr(7).to_int()
		elif arg.begins_with("--volcano"):
			volcano = true
			if arg.begins_with("--volcano="):
				volcano_seconds = arg.substr(10).to_float()
		elif arg.begins_with("--monster"):
			monster = true
			if arg.begins_with("--monster="):
				monster_ticks = arg.substr(10).to_int()
		elif arg.begins_with("--kraken"):
			kraken = true
			if arg.begins_with("--kraken="):
				kraken_ticks = arg.substr(9).to_int()
		elif arg == "--earthquake":
			earthquake = true
		elif arg.begins_with("--tornado"):
			tornado = true
			if arg.begins_with("--tornado="):
				tornado_ticks = arg.substr(10).to_int()
		elif arg.begins_with("--chicken"):
			chicken = true
			if arg.begins_with("--chicken="):
				chicken_ticks = arg.substr(10).to_int()
		elif arg.begins_with("--creepers"):
			creepers = true
			if arg.begins_with("--creepers="):
				creeper_count = arg.substr(11).to_int()
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

	if zone:
		var events: EventManager = main.get_node("Events")
		var params := {}
		# --zone= shortens how long each jump's position lasts, so a five
		# position event (and at least one real jump) can be caught inside a
		# screenshot the same way it used to shrink the old wall's one-shot
		# travel time.
		if zone_seconds > 0.0:
			params["interval"] = zone_seconds
		events.trigger(&"zone", params)
		# Run past the trigger by hand, the same reasoning --monster/--war
		# already have — unlike those, always, not just when a number is
		# given: this event now jumps partway through its own life, and a
		# screenshot taken at the instant of triggering never shows one.
		for t in 200:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			## The whole island: the shot is a wall of light standing on it, and
			## where the wall is relative to the coast is the whole information.
			var reach: float = GameConfig.MAP_SIZE
			cam.position = Vector3(0.0, reach * 0.30, reach * 0.44)
			cam.look_at(Vector3(0.0, reach * 0.02, 0.0), Vector3.UP)

	if war:
		var events: EventManager = main.get_node("Events")
		# Arriving on this map already starts a war on its own
		# (Main.auto_trigger_event, the same as --volcano's own eruption) —
		# clear it first so a fresh, known fight is what actually runs,
		# rather than silently refusing "a war is already being fought."
		events.reset(GameConfig.map_seed)
		events.trigger(&"war")
		print("event          : %s" % events.last_description)
		# Run past the trigger by hand: unlike the other events, a war has no
		# fixed duration to wait out, only a number of ticks to walk forward.
		for t in war_ticks:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			# The two armies start on opposite halves of the map (war_side is
			# a spawn-position split) and converge — the shot is that whole
			# span, the same wide view as the other slow, island-scale events.
			var reach: float = GameConfig.MAP_SIZE
			cam.position = Vector3(0.0, reach * 0.30, reach * 0.44)
			cam.look_at(Vector3(0.0, reach * 0.02, 0.0), Vector3.UP)

	if drop:
		var events: EventManager = main.get_node("Events")
		# Aimed at bot 0 rather than at random, same reasoning as --meteor: a
		# shot of an empty beach with a crate on it proves nothing.
		var drop_at := Vector3(bots_node.pos_x[0], bots_node.pos_y[0], bots_node.pos_z[0])
		events.trigger(&"drop", {"x": drop_at.x, "z": drop_at.z, "count": 1})
		print("event          : %s" % events.last_description)
		# Past the fall itself and then drop_ticks further in, so the shot can
		# land anywhere from "still falling" to "deep in the crush".
		var run_ticks := int(SupplyScramble.FALL_SECONDS / GameConfig.SIMULATION_TICK_SECONDS) \
			+ drop_ticks
		for t in run_ticks:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			# Close rather than the whole island: the shot is the crush around
			# one crate, not where it sits relative to the coast.
			cam.position = drop_at + Vector3(0.0, 55.0, 70.0)
			cam.look_at(drop_at, Vector3.UP)

	if volcano:
		var events: EventManager = main.get_node("Events")
		var params := {}
		if volcano_seconds > 0.0:
			params["seconds"] = volcano_seconds
		# Arriving on this map already starts a default-timed eruption on its
		# own (Main.auto_trigger_event) before this line runs. Clear it so a
		# requested duration is not silently refused by "already erupting",
		# and so the shot is a freshly-triggered, known eruption either way.
		events.reset(GameConfig.map_seed)
		events.trigger(&"volcano", params)
		print("event          : %s" % events.last_description)
		if not framed:
			# Found from wherever the summit search actually put it, the same
			# reasoning --drop frames on the crate rather than guessing: a
			# volcano can land anywhere the island has high ground.
			var at := Vector3.ZERO
			for child in events.get_children():
				if child is LavaPool:
					at = child.position
					break
			var reach: float = GameConfig.MAP_SIZE * VolcanoEvent.FINAL_RADIUS_SHARE
			cam.position = at + Vector3(0.0, reach * 3.0, reach * 4.0)
			cam.look_at(at, Vector3.UP)

	if monster:
		var events: EventManager = main.get_node("Events")
		events.trigger(&"monster")
		print("event          : %s" % events.last_description)
		# Run past the trigger by hand, the same reasoning --war already has:
		# neither has a fixed duration to wait out with --wait.
		for t in monster_ticks:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			var giant: Node3D = null
			for child in events.get_children():
				if child is Monster:
					giant = child
					break
			var at: Vector3 = giant.global_position if giant != null else Vector3.ZERO
			cam.position = at + Vector3(0.0, Monster.HEIGHT * 1.2, Monster.HEIGHT * 2.5)
			cam.look_at(at + Vector3(0.0, Monster.HEIGHT * 0.4, 0.0), Vector3.UP)

	if kraken:
		var events: EventManager = main.get_node("Events")
		events.trigger(&"kraken")
		print("event          : %s" % events.last_description)
		# Run past the trigger by hand, the same reasoning --monster already has.
		for t in kraken_ticks:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			var giant: Node3D = null
			for child in events.get_children():
				if child is Kraken:
					giant = child
					break
			var at: Vector3 = giant.global_position if giant != null else Vector3.ZERO
			cam.position = at + Vector3(0.0, Kraken.HEIGHT * 0.9, Kraken.HEIGHT * 2.2)
			cam.look_at(at, Vector3.UP)

	if earthquake:
		var events: EventManager = main.get_node("Events")
		events.trigger(&"earthquake")
		print("event          : %s" % events.last_description)
		if not framed:
			# Framed on the first rift found rather than a guessed point, the
			# same reasoning --volcano frames on the lava pool it actually got.
			var at := Vector3.ZERO
			for child in events.get_children():
				if child is Fissure:
					var start := (child as Fissure).start_point()
					at = Vector3(start.x, world.get_height(start.x, start.y), start.y)
					break
			cam.position = at + Vector3(0.0, 90.0, 130.0)
			cam.look_at(at, Vector3.UP)

	if tornado:
		var events: EventManager = main.get_node("Events")
		events.trigger(&"tornado")
		print("event          : %s" % events.last_description)
		# Run past the trigger by hand, the same reasoning --monster/--kraken
		# already have.
		for t in tornado_ticks:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			var giant: Node3D = null
			for child in events.get_children():
				if child is Tornado:
					giant = child
					break
			var at: Vector3 = giant.global_position if giant != null else Vector3.ZERO
			cam.position = at + Vector3(0.0, Tornado.HEIGHT * 0.55, Tornado.HEIGHT * 1.1)
			cam.look_at(at + Vector3(0.0, Tornado.HEIGHT * 0.35, 0.0), Vector3.UP)

	if chicken:
		var events: EventManager = main.get_node("Events")
		events.trigger(&"chicken")
		print("event          : %s" % events.last_description)
		# Run past the trigger by hand, the same reasoning --monster/--kraken/
		# --tornado already have.
		for t in chicken_ticks:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			var giant: Node3D = null
			for child in events.get_children():
				if child is GiantBird:
					giant = child
					break
			var at: Vector3 = giant.global_position if giant != null else Vector3.ZERO
			cam.position = at + Vector3(0.0, GiantBird.HEIGHT * 1.1, GiantBird.HEIGHT * 2.4)
			cam.look_at(at + Vector3(0.0, GiantBird.HEIGHT * 0.4, 0.0), Vector3.UP)

	if creepers:
		var events: EventManager = main.get_node("Events")
		var params := {}
		if creeper_count > 0:
			params["count"] = creeper_count
		# Aimed at bot 0 rather than at random, same reasoning as --meteor/
		# --drop: a shot of empty terrain with a few dots wandering it proves
		# nothing. Every creeper spawns at its own random point regardless —
		# this only decides where the camera looks.
		var creeper_at := Vector3(bots_node.pos_x[0], bots_node.pos_y[0], bots_node.pos_z[0])
		events.trigger(&"creepers", params)
		print("event          : %s" % events.last_description)
		# Fixed wait rather than a --creepers= number: there is no single
		# actor to frame progress on, only whether any are still ticking.
		for t in 100:
			bots_node.tick(GameConfig.SIMULATION_TICK_SECONDS, ticks + t)
			events.advance(GameConfig.SIMULATION_TICK_SECONDS)
		print("event          : %s" % events.last_description)
		if not framed:
			cam.position = creeper_at + Vector3(0.0, 90.0, 130.0)
			cam.look_at(creeper_at, Vector3.UP)

	# Whatever placed the camera above did it by setting position/look_at
	# directly, which the active mode knows nothing about. Without this it
	# would be overwritten on the very next _process(): the mode recomputes
	# its transform from its own last-known state, not from wherever the
	# camera visually is.
	cam.sync_active_mode()

	print("sim            : paused=%s tick=%d speed=%.2f" % [main.paused, main.tick_count, main.sim_speed])
	print("bot 0          : vel=(%.2f, %.2f)" % [bots_node.vel_x[0], bots_node.vel_z[0]])
	for entry in crowd.tier_report():
		print("bots (%-12s): %d, %d triangles each"
			% [entry.id, entry.instances, entry.triangles])
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
