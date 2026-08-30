extends Node
## Checks GameHUD: it is wired the same way DebugHUD/PauseMenu are, the
## leaderboard ranks classes by who has the most survivors, the event feed
## grows and stays bounded as events fire, the minimap plots a sampled dot
## per living bot with north up, F2 hides the panel, and none of it costs
## much even at ten thousand bots.
##
## Whether it actually reads well on screen is not this suite's job — a
## Control drawing itself with _draw() is not observable headless any more
## than a shader is; the same limitation verify_events.gd already accepts
## for the meteor's material.

func _ready() -> void:
	var failures := 0

	var packed: PackedScene = load("res://scenes/main.tscn")
	var main: Node3D = packed.instantiate()
	add_child(main)
	var bots: BotManager = main.get_node("Bots")
	var events: EventManager = main.get_node("Events")
	var world: World = main.get_node("World")
	var game_hud: GameHUD = main.get_node("GameHUD")

	print("--- wiring ---")
	failures += _check("GameHUD is wired to Main", game_hud.main == main)

	bots.spawn(200, GameConfig.DEFAULT_MAP_SEED)

	print("--- leaderboard ---")
	# Kill every one of class 0 and half of class 1, so the ranking has a real
	# answer to check rather than three near-equal counts.
	for i in bots.count:
		if bots.bot_class[i] == 0:
			bots.kill(i)
		elif bots.bot_class[i] == 1 and i % 2 == 0:
			bots.kill(i)
	game_hud._refresh_leaderboard()
	var rows := game_hud._rank_rows.get_children()
	failures += _check("one row per class", rows.size() == GameConfig.class_count())

	var counted := _row_counts(rows)
	failures += _check("ranked strictly by survivors, most first", _is_sorted_desc(counted))
	failures += _check("the wiped-out class ranks last", counted[counted.size() - 1] == 0)

	print("--- event feed ---")
	failures += _check("starts empty", game_hud._feed_lines.is_empty())
	game_hud._on_fired(&"test", "First thing happened")
	game_hud._on_fired(&"test", "Second thing happened")
	failures += _check("newest line leads",
		game_hud._feed_lines[0] == "Second thing happened")
	failures += _check("the label shows it too",
		game_hud._feed_label.text.begins_with("Second thing happened"))
	for i in 10:
		game_hud._on_fired(&"test", "Line %d" % i)
	failures += _check("stays bounded at FEED_LINES (%d)" % GameHUD.FEED_LINES,
		game_hud._feed_lines.size() == GameHUD.FEED_LINES)

	print("--- events actually reach it ---")
	game_hud.main = main
	game_hud._wire_feed()
	events.trigger(&"meteor", {"x": 50.0, "z": 50.0, "radius": 30.0})
	failures += _check("triggering a real event appends to the feed",
		game_hud._feed_lines[0] == events.last_description)

	print("--- minimap ---")
	game_hud._minimap_built = false
	game_hud._refresh_minimap()
	failures += _check("builds a background on first refresh", game_hud._minimap_built)
	failures += _check("remembers the seed it built for",
		game_hud._minimap_seed == GameConfig.map_seed)

	var half := world.half_extent()
	var centre := game_hud._to_minimap(0.0, 0.0, half)
	failures += _check("the map centre lands in the middle of the square",
		centre.is_equal_approx(Vector2(GameHUD.MINIMAP_SIZE, GameHUD.MINIMAP_SIZE) * 0.5))
	var north := game_hud._to_minimap(0.0, -half, half)
	var south := game_hud._to_minimap(0.0, half, half)
	failures += _check("north (-Z) is up, south (+Z) is down", north.y < south.y)

	print("--- ten thousand bots ---")
	bots.spawn(10000, GameConfig.DEFAULT_MAP_SEED)
	var t0 := Time.get_ticks_usec()
	game_hud._refresh_leaderboard()
	var leaderboard_us := Time.get_ticks_usec() - t0
	t0 = Time.get_ticks_usec()
	game_hud._minimap_built = false
	game_hud._refresh_minimap()
	var minimap_us := Time.get_ticks_usec() - t0
	print("  leaderboard    : %.2f ms, minimap %.2f ms at %d bots"
		% [leaderboard_us / 1000.0, minimap_us / 1000.0, bots.count])
	failures += _check("leaderboard stays cheap (%.2f ms)" % (leaderboard_us / 1000.0),
		leaderboard_us < 20000)
	failures += _check("minimap stays cheap (%.2f ms)" % (minimap_us / 1000.0), minimap_us < 20000)

	print("--- F2 hides the panel ---")
	failures += _check("starts visible", game_hud._panel.visible)
	game_hud._unhandled_input(_key_event(KEY_F2))
	failures += _check("F2 hides it", not game_hud._panel.visible)
	game_hud._unhandled_input(_key_event(KEY_F2))
	failures += _check("F2 again shows it", game_hud._panel.visible)

	print("failures       : %d" % failures)
	get_tree().quit(1 if failures > 0 else 0)


func _row_counts(rows: Array) -> Array[int]:
	var counted: Array[int] = []
	for row in rows:
		var count_label: Label = row.get_child(2)
		var alive_part := count_label.text.split(" / ")[0]
		counted.append(int(alive_part))
	return counted


func _is_sorted_desc(values: Array[int]) -> bool:
	for i in values.size() - 1:
		if values[i] < values[i + 1]:
			return false
	return true


func _key_event(keycode: Key) -> InputEventKey:
	var event := InputEventKey.new()
	event.physical_keycode = keycode
	event.pressed = true
	return event


func _check(what: String, ok: bool) -> int:
	print("  %s %s" % ["PASS" if ok else "FAIL", what])
	return 0 if ok else 1
