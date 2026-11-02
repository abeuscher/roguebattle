extends Control
## Temporary start screen for M1: shows a generated map.
## Wheel zooms at the cursor, drag pans, F fits, R makes a new map.
## Replaced by the battlemap and configurator later in M1.

const MAX_ZOOM := 32.0

var data: GameData
var log: GameLog
var view := TextureRect.new()
var label := Label.new()
var _fit_zoom := 1.0
var _dragging := false


func _ready() -> void:
	data = GameData.load_dir()
	log = GameLog.new("user://logs/game-%s.log" % Time.get_datetime_string_from_system().replace(":", "-"))
	set_anchors_preset(PRESET_FULL_RECT)
	clip_contents = true
	var bg := ColorRect.new()
	bg.color = Color("#12161c")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	bg.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bg)
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	view.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(view)
	label.position = Vector2(16, 12)
	add_child(label)
	resized.connect(_fit)
	_generate(randi())


func _generate(seed: int) -> void:
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed)
	view.texture = ImageTexture.create_from_image(MinimapImage.build(map, data))
	view.size = view.texture.get_size()
	label.text = "Seed %d  ·  %s %dx%d  ·  %d ms  ·  Wheel: zoom  ·  Drag: pan  ·  F: fit  ·  R: new map" % [
			seed, map.settings["preset"], map.width, map.height, Time.get_ticks_msec() - started]
	log.add(0, "system", "Map generated: seed %d, %s" % [seed, JSON.stringify(map.settings)])
	_fit()


func _fit() -> void:
	if view.texture == null:
		return
	var tex := view.texture.get_size()
	_fit_zoom = minf(size.x / tex.x, size.y / tex.y)
	view.scale = Vector2.ONE * _fit_zoom
	view.position = (size - tex * _fit_zoom) / 2.0


func _zoom_at(point: Vector2, factor: float) -> void:
	var z := clampf(view.scale.x * factor, _fit_zoom * 0.5, _fit_zoom * MAX_ZOOM)
	var on_image := (point - view.position) / view.scale.x
	view.scale = Vector2.ONE * z
	view.position = point - on_image * z


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.25)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 0.8)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		view.position += (event as InputEventMouseMotion).relative
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.position, g.factor)


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	match (event as InputEventKey).keycode:
		KEY_R:
			_generate(randi())
		KEY_F:
			_fit()
