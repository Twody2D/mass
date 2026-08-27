class_name PauseMenu
extends CanvasLayer
## Escape menu: stops the simulation, hands back the cursor and offers the few
## controls worth having on camera.
##
## Deliberately not a second home for simulation logic. Every button calls the
## same Main it would be calling from anywhere else; this is a view.
##
## The debug overlay keeps its keyboard shortcuts for working quickly. This is
## the one that can be pointed at on video.

const COUNT_PRESETS := [100, 1000, 5000, 10000]
const SPEED_LADDER := [0.25, 0.5, 1.0, 2.0, 4.0, 8.0]

const PANEL_WIDTH := 340
const BUTTON_HEIGHT := 40

## Assigned by Main, which owns the wiring.
var main: Node
var camera: FreeCamera

var _root: Control
var _speed_label: Label
var _count_buttons: Array[Button] = []
## Whether the simulation was already paused when the menu opened, so closing it
## does not quietly resume a run the user had stopped on purpose.
var _was_paused := false


func _ready() -> void:
	_build()
	_root.visible = false


func is_open() -> bool:
	return _root != null and _root.visible


func open() -> void:
	if is_open():
		return
	_was_paused = main.paused
	main.paused = true
	if camera != null:
		camera.capture_mouse(false)
	_refresh()
	_root.visible = true


func close() -> void:
	if not is_open():
		return
	_root.visible = false
	main.paused = _was_paused
	if camera != null:
		camera.capture_mouse(true)


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).physical_keycode != KEY_ESCAPE:
		return
	if is_open():
		close()
	else:
		open()
	get_viewport().set_input_as_handled()


func _refresh() -> void:
	_speed_label.text = "%.2fx" % main.sim_speed
	for i in _count_buttons.size():
		# The current size is shown as pressed rather than spelled out again.
		_count_buttons[i].button_pressed = GameConfig.bot_count == COUNT_PRESETS[i]


func _restart_with(seed_value: int, count: int) -> void:
	GameConfig.map_seed = seed_value
	GameConfig.bot_count = count
	main.restart()
	_refresh()


func _step_speed(direction: int) -> void:
	var nearest := 0
	for i in SPEED_LADDER.size():
		if absf(SPEED_LADDER[i] - main.sim_speed) < absf(SPEED_LADDER[nearest] - main.sim_speed):
			nearest = i
	main.sim_speed = SPEED_LADDER[clampi(nearest + direction, 0, SPEED_LADDER.size() - 1)]
	_refresh()


func _build() -> void:
	_root = Control.new()
	_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_root)

	# A dim sheet over the world, so the menu reads as a stop rather than as a
	# panel that happens to be in the way.
	var shade := ColorRect.new()
	shade.set_anchors_preset(Control.PRESET_FULL_RECT)
	shade.color = Color(0.03, 0.04, 0.06, 0.62)
	_root.add_child(shade)

	var centre := CenterContainer.new()
	centre.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(centre)

	var panel := PanelContainer.new()
	centre.add_child(panel)

	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 22)
	panel.add_child(padding)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	column.custom_minimum_size.x = PANEL_WIDTH
	padding.add_child(column)

	var title := Label.new()
	title.text = "MASS"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_size_override("font_size", 34)
	column.add_child(title)

	var subtitle := Label.new()
	subtitle.text = "пауза"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.modulate = Color(1, 1, 1, 0.5)
	column.add_child(subtitle)

	column.add_child(_spacer(8))
	column.add_child(_button("Продолжить", close))
	column.add_child(_button("Начать заново", func() -> void:
		_restart_with(GameConfig.map_seed, GameConfig.bot_count)))
	column.add_child(_button("Новый остров", func() -> void:
		_restart_with(randi(), GameConfig.bot_count)))

	column.add_child(_spacer(8))
	column.add_child(_caption("События"))
	# Closing on the way out: an event fired behind a dimmed menu is an event
	# nobody sees.
	column.add_child(_button("Метеорит", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"meteor")))
	column.add_child(_button("Потоп", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"flood")))

	column.add_child(_spacer(8))
	column.add_child(_caption("Рыцарей"))
	var counts := HBoxContainer.new()
	counts.add_theme_constant_override("separation", 6)
	column.add_child(counts)
	for count: int in COUNT_PRESETS:
		var button := Button.new()
		button.text = str(count)
		button.toggle_mode = true
		button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		# Restarting is the only way a new count takes effect, so the button
		# does exactly that rather than leaving a pending setting behind.
		button.pressed.connect(func() -> void: _restart_with(GameConfig.map_seed, count))
		counts.add_child(button)
		_count_buttons.append(button)

	column.add_child(_spacer(8))
	column.add_child(_caption("Скорость симуляции"))
	var speed_row := HBoxContainer.new()
	speed_row.add_theme_constant_override("separation", 6)
	column.add_child(speed_row)
	speed_row.add_child(_small_button("−", func() -> void: _step_speed(-1)))
	_speed_label = Label.new()
	_speed_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_speed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_speed_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	speed_row.add_child(_speed_label)
	speed_row.add_child(_small_button("+", func() -> void: _step_speed(1)))

	column.add_child(_spacer(12))
	column.add_child(_button("Выйти", func() -> void: get_tree().quit()))

	var hint := Label.new()
	hint.text = "Esc — вернуться в игру"
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.modulate = Color(1, 1, 1, 0.4)
	column.add_child(hint)


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	button.pressed.connect(action)
	return button


func _small_button(text: String, action: Callable) -> Button:
	var button := _button(text, action)
	button.custom_minimum_size = Vector2(BUTTON_HEIGHT, BUTTON_HEIGHT)
	return button


func _caption(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.modulate = Color(1, 1, 1, 0.55)
	return label


func _spacer(height: int) -> Control:
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, height)
	return spacer
