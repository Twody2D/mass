extends Node
## Checks that the escape menu actually stops the world and hands back the
## pointer, and that closing it puts everything back the way it was.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var menu: PauseMenu = main.get_node("PauseMenu")
	var camera: CameraRig = main.get_node("Camera3D")
	var bots: BotManager = main.get_node("Bots")

	failures += _check("menu is wired to Main and the camera",
		menu.main == main and menu.camera == camera)
	failures += _check("menu starts closed", not menu.is_open())

	_press(menu, KEY_ESCAPE)
	failures += _check("escape opens the menu", menu.is_open())
	failures += _check("opening pauses the simulation", main.paused)
	failures += _check("opening hands back the pointer", not camera.is_mouse_captured())
	var ticks_before: int = main.tick_count
	for i in 5:
		main._physics_process(0.1)
	failures += _check("an open menu stops the clock", main.tick_count == ticks_before)

	_press(menu, KEY_ESCAPE)
	failures += _check("escape closes the menu", not menu.is_open())
	failures += _check("closing resumes the simulation", not main.paused)
	failures += _check("closing takes the pointer back", camera.is_mouse_captured())

	# A run the user paused on purpose must not be resumed by the menu.
	main.paused = true
	_press(menu, KEY_ESCAPE)
	_press(menu, KEY_ESCAPE)
	failures += _check("a deliberately paused run stays paused", main.paused)
	main.paused = false

	# The camera must sit still while the pointer is elsewhere.
	_press(menu, KEY_ESCAPE)
	var camera_before: Vector3 = camera.position
	for i in 10:
		camera._process(0.016)
	failures += _check("the camera does not fly with the menu open",
		camera.position.is_equal_approx(camera_before))
	_press(menu, KEY_ESCAPE)

	# Buttons are the same operations, reached with a pointer.
	menu.open()
	menu._restart_with(GameConfig.map_seed, 5000)
	failures += _check("a count button respawns the crowd (%d)" % bots.count, bots.count == 5000)
	failures += _check("restarting resets the clock", main.tick_count == 0)

	var seed_before: int = GameConfig.map_seed
	menu._restart_with(12345, 100)
	failures += _check("a new island takes the new seed", GameConfig.map_seed == 12345
		and seed_before != 12345 and bots.count == 100)

	menu._seed_edit.text = "777"
	menu._apply_typed_seed()
	failures += _check("typing an exact seed applies it (%d)" % GameConfig.map_seed,
		GameConfig.map_seed == 777)
	failures += _check("the field clears after applying", menu._seed_edit.text == "")
	failures += _check("the label shows the seed that is now live",
		menu._seed_label.text == "777")

	menu._seed_edit.text = "not a number"
	menu._apply_typed_seed()
	failures += _check("garbage input is ignored, not applied as seed 0",
		GameConfig.map_seed == 777)

	var speed_before: float = main.sim_speed
	menu._step_speed(1)
	failures += _check("speed steps up (%.2f to %.2f)" % [speed_before, main.sim_speed],
		main.sim_speed > speed_before)
	for i in 20:
		menu._step_speed(-1)
	failures += _check("speed stops at the bottom (%.2f)" % main.sim_speed,
		is_equal_approx(main.sim_speed, PauseMenu.SPEED_LADDER[0]))

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _press(menu: PauseMenu, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	menu._unhandled_input(event)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
