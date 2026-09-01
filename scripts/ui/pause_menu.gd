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
var camera: CameraRig

## Four separate level-switch buttons rather than one generic list — each
## has a distinct role, not just "another scene": `back_scene` is "leave
## this level" (the ordinary island, from anywhere else); `volcano_scene`
## is also what DebugHUD's V key jumps to when the volcano event is not
## registered here, so it has to name the volcano map specifically rather
## than whichever scene happens to be first; `arena_scene` is the boss
## arena; `war_scene` is the war island, also what DebugHUD's W key jumps
## to when the war event is not registered here, the same reasoning as V/
## volcano_scene. Empty means no such button: plain exports rather than a
## check against `main`, because _build() runs before Main has wired this
## node to anything (child _ready() runs before the parent's).
@export var back_scene_path: String = ""
@export var back_scene_label: String = ""
@export var volcano_scene_path: String = ""
@export var volcano_scene_label: String = ""
@export var arena_scene_path: String = ""
@export var arena_scene_label: String = ""
@export var war_scene_path: String = ""
@export var war_scene_label: String = ""

var _root: Control
var _speed_label: Label
var _seed_label: Label
var _seed_edit: LineEdit
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
	_seed_label.text = str(GameConfig.map_seed)
	for i in _count_buttons.size():
		# The current size is shown as pressed rather than spelled out again.
		_count_buttons[i].button_pressed = GameConfig.bot_count == COUNT_PRESETS[i]


func _restart_with(seed_value: int, count: int) -> void:
	GameConfig.map_seed = seed_value
	GameConfig.bot_count = count
	main.restart()
	_refresh()


## Applies whatever is typed in the seed field, if it actually parses as one —
## garbage input is left alone rather than silently restarting on seed 0.
## Clears the field back to its placeholder afterwards so it always shows the
## current seed rather than what was just typed into it.
func _apply_typed_seed() -> void:
	var text := _seed_edit.text.strip_edges()
	if not text.is_valid_int():
		return
	_restart_with(text.to_int(), GameConfig.bot_count)
	_seed_edit.text = ""


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
	if back_scene_path != "":
		column.add_child(_button(back_scene_label, func() -> void:
			get_tree().change_scene_to_file(back_scene_path)))
	if volcano_scene_path != "":
		column.add_child(_button(volcano_scene_label, func() -> void:
			get_tree().change_scene_to_file(volcano_scene_path)))
	if arena_scene_path != "":
		column.add_child(_button(arena_scene_label, func() -> void:
			get_tree().change_scene_to_file(arena_scene_path)))
	if war_scene_path != "":
		column.add_child(_button(war_scene_label, func() -> void:
			get_tree().change_scene_to_file(war_scene_path)))

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
	column.add_child(_button("Зона", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"zone")))
	column.add_child(_button("Сброс груза", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"drop")))
	column.add_child(_button("Краб", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"crab")))
	column.add_child(_button("Змея", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"snake")))
	column.add_child(_button("Жираф", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"giraffe")))
	column.add_child(_button("Случайный босс", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"boss")))
	column.add_child(_button("Монстр", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"monster")))
	column.add_child(_button("Кракен", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"kraken")))
	column.add_child(_button("Землетрясение", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"earthquake")))
	column.add_child(_button("Смерч", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"tornado")))
	column.add_child(_button("Гигантская курица", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"chicken")))
	column.add_child(_button("Криперы", func() -> void:
		close()
		var events: EventManager = main.events
		if events != null:
			events.trigger(&"creepers")))

	column.add_child(_spacer(8))
	column.add_child(_caption("Сид карты"))
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 6)
	column.add_child(seed_row)
	_seed_label = Label.new()
	_seed_label.custom_minimum_size.x = 90
	_seed_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_seed_label.modulate = Color(1, 1, 1, 0.75)
	seed_row.add_child(_seed_label)
	_seed_edit = LineEdit.new()
	_seed_edit.placeholder_text = "точный сид"
	_seed_edit.custom_minimum_size = Vector2(0, BUTTON_HEIGHT)
	_seed_edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_seed_edit.text_submitted.connect(func(_text: String) -> void: _apply_typed_seed())
	seed_row.add_child(_seed_edit)
	seed_row.add_child(_small_button("OK", _apply_typed_seed))

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
