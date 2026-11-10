class_name MapCamera
extends Camera2D
## Battlemap camera (SPEC §5.2): wheel zooms at the cursor over a wide range, drag pans.

signal view_changed

const MAX_ZOOM := 2.5

var world := Vector2.ONE  # size of the map in world units
var _fit_zoom := 1.0
var _dragging := false


## Shows the whole map.
func fit() -> void:
	var screen := get_viewport_rect().size
	_fit_zoom = minf(screen.x / world.x, screen.y / world.y)
	zoom = Vector2.ONE * _fit_zoom
	# Hex (0, 0) is centered on the world origin, so the map starts half a hex up and left.
	position = world / 2.0 - Vector2(MapView.HEX_SIZE * Hex.SQRT3 / 2.0, MapView.HEX_SIZE)
	view_changed.emit()


func center_on(world_point: Vector2) -> void:
	position = world_point
	view_changed.emit()


## Glides to a point, zooming and panning together, until the view spans `map_share`
## of the whole map, or stays as close as it is if already closer (it never pulls
## back). Returns the tween, so the caller can wait for it to land.
func fly_to(world_point: Vector2, map_share: float, seconds: float) -> Tween:
	var from_pos := position
	var from_zoom := zoom.x
	var to_zoom := clampf(maxf(from_zoom, _fit_zoom / map_share), _fit_zoom * 0.5, MAX_ZOOM)
	# Keep the view on the map: near an edge, stop short of centering exactly.
	var half := get_viewport_rect().size / to_zoom / 2.0
	var origin := -Vector2(MapView.HEX_SIZE * Hex.SQRT3 / 2.0, MapView.HEX_SIZE)
	for axis in 2:
		if half[axis] * 2.0 < world[axis]:
			world_point[axis] = clampf(world_point[axis], origin[axis] + half[axis], origin[axis] + world[axis] - half[axis])
	var t := create_tween().set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	t.tween_method(func(k: float):
		position = from_pos.lerp(world_point, k)
		zoom = Vector2.ONE * lerpf(from_zoom, to_zoom, k)
		view_changed.emit(), 0.0, 1.0, seconds)
	return t


func zoom_at(screen_point: Vector2, factor: float) -> void:
	var before := get_canvas_transform().affine_inverse() * screen_point
	zoom = Vector2.ONE * clampf(zoom.x * factor, _fit_zoom * 0.5, MAX_ZOOM)
	force_update_scroll()
	var after := get_canvas_transform().affine_inverse() * screen_point
	position += before - after
	view_changed.emit()


## The part of the world on screen.
func visible_rect() -> Rect2:
	var size := get_viewport_rect().size / zoom.x
	return Rect2(get_screen_center_position() - size / 2.0, size)


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		var wheel := mb.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]
		if wheel and get_viewport().gui_get_hovered_control() != null:
			return  # over a popup or the HUD: the wheel is theirs (scrolling), never a map zoom too
		if mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_UP:
			zoom_at(mb.position, 1.25)
		elif mb.pressed and mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			zoom_at(mb.position, 0.8)
		elif mb.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE]:
			_dragging = mb.pressed
	elif event is InputEventMouseMotion and _dragging:
		position -= (event as InputEventMouseMotion).relative / zoom.x
		view_changed.emit()
	elif event is InputEventMagnifyGesture:
		var g := event as InputEventMagnifyGesture
		zoom_at(g.position, g.factor)
