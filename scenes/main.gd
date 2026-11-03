extends Node2D
## Temporary start screen for M1: shows a generated map.
## Wheel zooms at the cursor, drag pans, F fits, R makes a new map.
## Replaced by the battlemap and configurator later in M1.

const MAX_ZOOM := 2.5

var data: GameData
var log: GameLog
var view := MapView.new()
var camera := Camera2D.new()
var label := Label.new()
var _world := Vector2.ONE
var _fit_zoom := 1.0
var _dragging := false


func _ready() -> void:
	data = GameData.load_dir()
	log = GameLog.new("user://logs/game-%s.log" % Time.get_datetime_string_from_system().replace(":", "-"))
	RenderingServer.set_default_clear_color(Color("#12161c"))
	add_child(view)
	add_child(camera)
	var hud := CanvasLayer.new()
	add_child(hud)
	label.position = Vector2(16, 12)
	hud.add_child(label)
	get_viewport().size_changed.connect(_fit)
	_generate(randi())


func _generate(seed: int) -> void:
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed)
	view.show_map(map, data)
	_world = MapView.world_size(map)
	label.text = "Seed %d  ·  %s %dx%d  ·  %d ms  ·  Wheel: zoom  ·  Drag: pan  ·  F: fit  ·  R: new map" % [
			seed, map.settings["preset"], map.width, map.height, Time.get_ticks_msec() - started]
	log.add(0, "system", "Map generated: seed %d, %s" % [seed, JSON.stringify(map.settings)])
	_fit()


func _fit() -> void:
	var screen := get_viewport_rect().size
	_fit_zoom = minf(screen.x / _world.x, screen.y / _world.y)
	camera.zoom = Vector2.ONE * _fit_zoom
	# Hex (0, 0) is centered on the world origin, so the map starts half a hex up and left.
	camera.position = _world / 2.0 - Vector2(MapView.HEX_SIZE * Hex.SQRT3 / 2.0, MapView.HEX_SIZE)


func _zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_point
	camera.zoom = Vector2.ONE * clampf(camera.zoom.x * factor, _fit_zoom * 0.5, MAX_ZOOM)
	camera.force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_point
	camera.position += before - after


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			_zoom_at(mb.position, 1.25)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			_zoom_at(mb.position, 0.8)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		camera.position -= (event as InputEventMouseMotion).relative / camera.zoom.x
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		_zoom_at(g.position, g.factor)
	elif event is InputEventKey and event.is_pressed():
		match (event as InputEventKey).keycode:
			KEY_R:
				_generate(randi())
			KEY_F:
				_fit()
