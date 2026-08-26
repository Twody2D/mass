class_name DebugHUD
extends CanvasLayer
## Minimal debug overlay: what the simulation is doing, and the keys to steer it.
##
## Keyboard driven on purpose. The camera claims the right mouse button for
## looking around, and on camera a keypress is faster than aiming at a widget.
## The panel builds itself from ROWS rather than living in a scene file, so
## adding a readout is one line instead of an edit in two places.

## Speeds cycled by the bracket keys. A ladder rather than repeated doubling, so
## the values stay round and predictable on camera.
const SPEED_LADDER := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]

## Bot counts bound to the number keys, from the reference ladder.
const COUNT_PRESETS := [100, 1000, 5000, 10000]

## The overlay is cosmetic, so it refreshes at a fixed low rate instead of every
## frame. Ten updates a second reads fine and costs nothing.
const REFRESH_INTERVAL := 0.1

const ROWS := [
	"FPS",
	"Alive",
	"Total",
	"Sim speed",
	"Sim time",
	"Tick",
	"Seed",
	"State",
]

const HINTS := "P pause    R restart    N new seed    [ ] speed    1-4 count    F1 hide"

## Assigned by Main, which owns the wiring.
var main: Node

var _values: Array[Label] = []
var _panel: Control
var _elapsed := 0.0


func _ready() -> void:
	_build()
	_refresh()


func _process(delta: float) -> void:
	_elapsed += delta
	if _elapsed < REFRESH_INTERVAL:
		return
	_elapsed = 0.0
	_refresh()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	var key := (event as InputEventKey).physical_keycode
	match key:
		KEY_P:
			main.paused = not main.paused
		KEY_R:
			main.restart()
		KEY_N:
			GameConfig.map_seed = randi()
			main.restart()
		KEY_BRACKETLEFT:
			_step_speed(-1)
		KEY_BRACKETRIGHT:
			_step_speed(1)
		KEY_F1:
			_panel.visible = not _panel.visible
		KEY_1, KEY_2, KEY_3, KEY_4:
			GameConfig.bot_count = COUNT_PRESETS[key - KEY_1]
			main.restart()
		_:
			return
	_refresh()
	get_viewport().set_input_as_handled()


func _step_speed(direction: int) -> void:
	# Snap to the nearest rung first, so the ladder still works after a speed
	# set from anywhere else.
	var nearest := 0
	for i in SPEED_LADDER.size():
		if absf(SPEED_LADDER[i] - main.sim_speed) < absf(SPEED_LADDER[nearest] - main.sim_speed):
			nearest = i
	main.sim_speed = SPEED_LADDER[clampi(nearest + direction, 0, SPEED_LADDER.size() - 1)]


func _refresh() -> void:
	if main == null or _values.is_empty():
		return
	var bots: BotManager = main.bots
	var alive := bots.alive_count if bots != null else 0
	var total := bots.count if bots != null else 0
	_values[0].text = "%d" % Engine.get_frames_per_second()
	_values[1].text = str(alive)
	_values[2].text = str(total)
	_values[3].text = "%.2fx" % main.sim_speed
	_values[4].text = "%.1f s" % main.sim_time
	_values[5].text = str(main.tick_count)
	_values[6].text = str(GameConfig.map_seed)
	_values[7].text = "paused" if main.paused else "running"


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_LEFT)
	for side in ["left", "top"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_panel = margin

	var panel := PanelContainer.new()
	margin.add_child(panel)

	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(padding)

	var column := VBoxContainer.new()
	padding.add_child(column)

	var grid := HBoxContainer.new()
	grid.add_theme_constant_override("separation", 16)
	column.add_child(grid)

	var names := VBoxContainer.new()
	var values := VBoxContainer.new()
	# A fixed name column keeps the values from jittering as text changes width.
	names.custom_minimum_size.x = 78
	grid.add_child(names)
	grid.add_child(values)

	for row in ROWS:
		var name_label := Label.new()
		name_label.text = row
		name_label.modulate = Color(1, 1, 1, 0.6)
		names.add_child(name_label)

		var value_label := Label.new()
		values.add_child(value_label)
		_values.append(value_label)

	var hint := Label.new()
	hint.text = HINTS
	hint.modulate = Color(1, 1, 1, 0.45)
	column.add_child(hint)
