class_name GameHUD
extends CanvasLayer
## The part of the UI meant to be seen on camera, not just by whoever is
## steering: which class has the most survivors, what has happened lately,
## and where the crowd actually is on the island.
##
## Sits beside DebugHUD rather than inside it — DebugHUD is instrumentation
## for whoever is driving, this is instrumentation for whoever is watching.
## F2 hides it the same way F1 hides DebugHUD.

## The overlay is cosmetic, so it refreshes at a fixed low rate instead of
## every frame — the same reasoning DebugHUD already uses.
const REFRESH_INTERVAL := 0.1

## The minimap redraws less often still: it is the most expensive of the
## three widgets, and nothing about troop positions needs the same rate as a
## number ticking over.
const MINIMAP_REFRESH_INTERVAL := 0.2

const MINIMAP_SIZE := 168.0
## Samples per side for the island silhouette. Cheap and built once per seed,
## not once per frame — a coarse read of the coastline is all a 168 px square
## can show anyway.
const MINIMAP_BACKGROUND_RESOLUTION := 48
## However large the crowd gets, the minimap only ever plots this many dots.
## A stride skips the rest: more than a few hundred points is not
## distinguishable on a panel this size, and drawing all ten thousand would
## be the same "one node per bot" mistake the crowd renderer exists to avoid,
## just moved into 2D.
const MINIMAP_MAX_DOTS := 600
const MINIMAP_LAND := Color(0.32, 0.5, 0.26)
const MINIMAP_WATER := Color(0.08, 0.24, 0.4)

## How many past announcements the feed keeps, newest first.
const FEED_LINES := 6

## Assigned by Main, which owns the wiring.
var main: Node

var _panel: Control
var _rank_rows: VBoxContainer
var _feed_label: Label
var _minimap: _MinimapView

var _elapsed := 0.0
var _minimap_elapsed := 0.0
var _minimap_seed := 0
var _minimap_built := false
var _feed_lines: Array[String] = []


func _ready() -> void:
	_build()


## `main` is not assigned yet when this node's own _ready() runs — Main
## wires it after every child has already had _ready() called, the same
## ordering DebugHUD works around with the same null check.
func _process(delta: float) -> void:
	if main == null:
		return
	_wire_feed()

	_elapsed += delta
	if _elapsed >= REFRESH_INTERVAL:
		_elapsed = 0.0
		_refresh_leaderboard()

	_minimap_elapsed += delta
	if _minimap_elapsed >= MINIMAP_REFRESH_INTERVAL:
		_minimap_elapsed = 0.0
		_refresh_minimap()


func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not event.is_pressed() or event.is_echo():
		return
	if (event as InputEventKey).physical_keycode == KEY_F2:
		_panel.visible = not _panel.visible
		get_viewport().set_input_as_handled()


func _wire_feed() -> void:
	var events: EventManager = main.events
	if events != null and not events.fired.is_connected(_on_fired):
		events.fired.connect(_on_fired)


func _on_fired(_id: StringName, description: String) -> void:
	_feed_lines.push_front(description)
	if _feed_lines.size() > FEED_LINES:
		_feed_lines.resize(FEED_LINES)
	_feed_label.text = "\n".join(_feed_lines)


## Class standings: living vs. spawned, ranked by who has the most left. Not
## sourced from a running per-class tally — class assignment never changes
## after spawn, so a fresh count over the crowd every refresh is one pass
## over arrays the renderer already walks this often anyway, and it needs no
## bookkeeping of its own to stay correct through kills, culls and respawns.
func _refresh_leaderboard() -> void:
	var bots: BotManager = main.bots
	if bots == null or _rank_rows == null:
		return

	var classes := GameConfig.class_count()
	var alive := PackedInt32Array()
	var total := PackedInt32Array()
	alive.resize(classes)
	total.resize(classes)
	for i in bots.count:
		var c := bots.bot_class[i]
		total[c] += 1
		if bots.alive[i] == 1:
			alive[c] += 1

	var order: Array[int] = []
	for c in classes:
		order.append(c)
	order.sort_custom(func(a: int, b: int) -> bool: return alive[a] > alive[b])

	# Classes are few enough (GameConfig.class_count(), not the crowd) that
	# rebuilding the rows outright is simpler than diffing them in place, and
	# costs nothing next to what the count itself already did.
	for child in _rank_rows.get_children():
		child.queue_free()
	for rank in classes:
		var class_id := order[rank]
		_rank_rows.add_child(_leaderboard_row(rank + 1, class_id, alive[class_id], total[class_id]))


func _leaderboard_row(rank: int, class_id: int, alive_count: int, total_count: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)

	var rank_label := Label.new()
	rank_label.text = "#%d" % rank
	rank_label.custom_minimum_size.x = 24
	rank_label.modulate = Color(1, 1, 1, 0.5)
	row.add_child(rank_label)

	var swatch := ColorRect.new()
	swatch.color = _class_color(class_id)
	swatch.custom_minimum_size = Vector2(14, 14)
	row.add_child(swatch)

	var count_label := Label.new()
	count_label.text = "%d / %d" % [alive_count, total_count]
	row.add_child(count_label)

	return row


func _class_color(class_id: int) -> Color:
	var classes: Array = GameConfig.CLASS_COLORS
	return classes[class_id] if class_id >= 0 and class_id < classes.size() else Color.WHITE


## Rebuilds the background only when the seed has actually changed, and
## otherwise just re-plots the dots. A sampled stride keeps the point count
## bounded regardless of crowd size; the camera marker is one more circle.
func _refresh_minimap() -> void:
	var world: World = main.world
	var bots: BotManager = main.bots
	if world == null or bots == null or _minimap == null:
		return

	if not _minimap_built or _minimap_seed != GameConfig.map_seed:
		_minimap.set_background(_build_minimap_background(world))
		_minimap_seed = GameConfig.map_seed
		_minimap_built = true

	var half := world.half_extent()
	var points := PackedVector2Array()
	var colors := PackedColorArray()
	var stride := maxi(1, bots.count / MINIMAP_MAX_DOTS)
	var i := 0
	while i < bots.count:
		if bots.alive[i] == 1:
			points.append(_to_minimap(bots.pos_x[i], bots.pos_z[i], half))
			colors.append(_class_color(bots.bot_class[i]))
		i += stride

	var marker := Vector2(-1.0, -1.0)
	var camera: CameraRig = main.camera
	if camera != null:
		var p := camera.global_position
		marker = _to_minimap(p.x, p.z, half)

	_minimap.set_points(points, colors, marker)


## World XZ to minimap pixels, north up: the same "up is -Z" convention
## Top already fixed the camera to, so what the minimap shows lines up with
## what a Top or Director shot of the same moment looks like.
func _to_minimap(x: float, z: float, half: float) -> Vector2:
	var span := half * 2.0
	if span <= 0.0:
		return Vector2.ZERO
	return Vector2(
		(x + half) / span * MINIMAP_SIZE,
		(z + half) / span * MINIMAP_SIZE)


func _build_minimap_background(world: World) -> ImageTexture:
	var r := MINIMAP_BACKGROUND_RESOLUTION
	var image := Image.create(r, r, false, Image.FORMAT_RGB8)
	var half := world.half_extent()
	var span := half * 2.0
	for gy in r:
		var z := -half + (gy + 0.5) / float(r) * span
		for gx in r:
			var x := -half + (gx + 0.5) / float(r) * span
			image.set_pixel(gx, gy, MINIMAP_LAND if world.is_walkable(x, z) else MINIMAP_WATER)
	return ImageTexture.create_from_image(image)


func _build() -> void:
	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_TOP_RIGHT)
	for side in ["right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 12)
	add_child(margin)
	_panel = margin

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 10)
	# Anchored top-right and left-growing children would otherwise overflow
	# past the screen edge as their content changes width.
	column.alignment = BoxContainer.ALIGNMENT_END
	margin.add_child(column)

	column.add_child(_build_leaderboard())
	column.add_child(_build_feed())
	column.add_child(_build_minimap())


func _build_leaderboard() -> Control:
	var panel := PanelContainer.new()
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(padding)

	var column := VBoxContainer.new()
	padding.add_child(column)

	var title := Label.new()
	title.text = "Классы"
	title.modulate = Color(1, 1, 1, 0.6)
	column.add_child(title)

	_rank_rows = VBoxContainer.new()
	_rank_rows.add_theme_constant_override("separation", 4)
	column.add_child(_rank_rows)

	return panel


func _build_feed() -> Control:
	var panel := PanelContainer.new()
	panel.custom_minimum_size.x = MINIMAP_SIZE

	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 10)
	panel.add_child(padding)

	var column := VBoxContainer.new()
	padding.add_child(column)

	var title := Label.new()
	title.text = "События"
	title.modulate = Color(1, 1, 1, 0.6)
	column.add_child(title)

	_feed_label = Label.new()
	_feed_label.autowrap_mode = TextServer.AUTOWRAP_WORD
	column.add_child(_feed_label)

	return panel


func _build_minimap() -> Control:
	var panel := PanelContainer.new()
	var padding := MarginContainer.new()
	for side in ["left", "right", "top", "bottom"]:
		padding.add_theme_constant_override("margin_" + side, 6)
	panel.add_child(padding)

	_minimap = _MinimapView.new()
	_minimap.map_size = MINIMAP_SIZE
	_minimap.custom_minimum_size = Vector2(MINIMAP_SIZE, MINIMAP_SIZE)
	padding.add_child(_minimap)

	return panel


## Draws the island silhouette, one dot per sampled bot and a marker at the
## camera, all inside a single _draw() call rather than one node per dot —
## the same reason the crowd itself is one MultiMesh, only in 2D.
class _MinimapView extends Control:
	const MARKER_COLOR := Color(1.0, 1.0, 1.0, 0.9)
	const EMPTY_COLOR := Color(0.08, 0.24, 0.4)
	const DOT_RADIUS := 1.6
	const MARKER_RADIUS := 5.0

	## Named apart from Control's own `size` (a Vector2 the layout owns) —
	## this is just how wide the square this view draws itself into is.
	var map_size := 0.0

	var _background: ImageTexture
	var _points := PackedVector2Array()
	var _colors := PackedColorArray()
	var _marker := Vector2(-1.0, -1.0)

	func set_background(texture: ImageTexture) -> void:
		_background = texture
		queue_redraw()

	func set_points(points: PackedVector2Array, colors: PackedColorArray, marker: Vector2) -> void:
		_points = points
		_colors = colors
		_marker = marker
		queue_redraw()

	func _draw() -> void:
		var square := Rect2(Vector2.ZERO, Vector2(map_size, map_size))
		if _background != null:
			draw_texture_rect(_background, square, false)
		else:
			draw_rect(square, EMPTY_COLOR)
		for i in _points.size():
			draw_circle(_points[i], DOT_RADIUS, _colors[i])
		if _marker.x >= 0.0:
			draw_arc(_marker, MARKER_RADIUS, 0.0, TAU, 12, MARKER_COLOR, 1.5)
