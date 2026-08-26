extends Node
## Drives the debug HUD with synthetic key presses and checks that each one
## actually changes the simulation, not just the label next to it.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var hud: DebugHUD = main.get_node("DebugHUD")
	var bots: BotManager = main.get_node("Bots")

	failures += _check("HUD is wired to Main", hud.main == main)

	# Pause must stop the clock, not merely relabel it.
	_press(hud, KEY_P)
	failures += _check("P pauses", main.paused)
	var ticks_before: int = main.tick_count
	for i in 5:
		main._physics_process(0.1)
	failures += _check("a paused simulation does not tick", main.tick_count == ticks_before)
	_press(hud, KEY_P)
	failures += _check("P resumes", not main.paused)
	for i in 5:
		main._physics_process(0.1)
	failures += _check("a running simulation ticks", main.tick_count > ticks_before)

	# Speed ladder, including its ends.
	var speed_before: float = main.sim_speed
	_press(hud, KEY_BRACKETRIGHT)
	failures += _check("] speeds up (%.2f -> %.2f)" % [speed_before, main.sim_speed],
		main.sim_speed > speed_before)
	_press(hud, KEY_BRACKETLEFT)
	failures += _check("[ slows down, back to %.2f" % main.sim_speed,
		is_equal_approx(main.sim_speed, speed_before))
	for i in 20:
		_press(hud, KEY_BRACKETRIGHT)
	failures += _check("speed stops at the top of the ladder (%.2f)" % main.sim_speed,
		is_equal_approx(main.sim_speed, DebugHUD.SPEED_LADDER[-1]))
	for i in 20:
		_press(hud, KEY_BRACKETLEFT)
	failures += _check("speed stops at the bottom (%.2f)" % main.sim_speed,
		is_equal_approx(main.sim_speed, DebugHUD.SPEED_LADDER[0]))

	# Bot count presets must actually respawn the crowd.
	_press(hud, KEY_3)
	failures += _check("3 respawns at %d bots (%d)" % [DebugHUD.COUNT_PRESETS[2], bots.count],
		bots.count == DebugHUD.COUNT_PRESETS[2])
	_press(hud, KEY_1)
	failures += _check("1 respawns at %d bots (%d)" % [DebugHUD.COUNT_PRESETS[0], bots.count],
		bots.count == DebugHUD.COUNT_PRESETS[0])

	# Restart must reset the clock.
	for i in 5:
		main._physics_process(0.1)
	_press(hud, KEY_R)
	failures += _check("R resets the clock", main.tick_count == 0 and main.sim_time == 0.0)

	# A new seed must produce a different island.
	var seed_before: int = GameConfig.map_seed
	var first_x: float = bots.pos_x[0]
	_press(hud, KEY_N)
	failures += _check("N changes the seed (%d -> %d)" % [seed_before, GameConfig.map_seed],
		GameConfig.map_seed != seed_before)
	failures += _check("N respawns somewhere else", not is_equal_approx(first_x, bots.pos_x[0]))

	_press(hud, KEY_F1)
	failures += _check("F1 hides the panel", not hud._panel.visible)
	_press(hud, KEY_F1)
	failures += _check("F1 shows it again", hud._panel.visible)

	# Readouts must reflect the simulation, not stale text.
	hud._refresh()
	failures += _check("Total reads %d" % bots.count, hud._values[2].text == str(bots.count))
	failures += _check("Seed reads %d" % GameConfig.map_seed,
		hud._values[6].text == str(GameConfig.map_seed))
	failures += _check("State reads running", hud._values[7].text == "running")

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _press(hud: DebugHUD, key: Key) -> void:
	var event := InputEventKey.new()
	event.physical_keycode = key
	event.pressed = true
	hud._unhandled_input(event)


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
