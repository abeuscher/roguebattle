class_name Minimap
extends Control
## The minimap (SPEC §5.2): the whole map with visible buildings, a frame showing
## what's on screen, and click or drag to jump there.

signal jump(world_point: Vector2)

const WIDTH := 380.0
const DOT_COLORS := {"player_base": Color("#3b6fd6"), "enemy_base": Color("#c8342c"),
		"town": Color("#f4ead2"), "tower": Color("#6d3a8c"), "temple": Color("#ffffff"), "nomads": Color("#2f8f6a")}

var _texture: Texture2D
var _view := Rect2()  # in minimap pixels
var _px_per_world := Vector2.ONE  # minimap image pixels per world unit
var _scale := 1.0  # screen pixels per minimap image pixel


func set_map(map: MapData, data: GameData) -> void:
	var img := MinimapImage.build(map, data)
	for b in map.buildings:  # visible buildings as small dots
		if DOT_COLORS.has(b["type"]):
			var o := Hex.to_offset(map.hex_at(b["hex"]))
			var r := 3 if b["type"].ends_with("base") else 1
			img.fill_rect(Rect2i(o.x * 2 + (o.y & 1) - r + 1, o.y * 2 - r + 1, r * 2, r * 2), DOT_COLORS[b["type"]])
	_texture = ImageTexture.create_from_image(img)
	# Same layout as the map view's underlay: 2 pixels per hex across, 2 per row down.
	_px_per_world = Vector2(1.0 / (MapView.HEX_SIZE * Hex.SQRT3 / 2.0), 1.0 / (MapView.HEX_SIZE * 0.75))
	_scale = WIDTH / img.get_width()
	custom_minimum_size = Vector2(WIDTH, img.get_height() * _scale)
	size = custom_minimum_size
	queue_redraw()


## Updates the on-screen frame from the camera's visible world rect.
func set_view(world_rect: Rect2) -> void:
	_view = Rect2(_to_minimap(world_rect.position), world_rect.size * _px_per_world * _scale)
	queue_redraw()


func _to_minimap(world_point: Vector2) -> Vector2:
	return (world_point * _px_per_world + Vector2.ONE) * _scale


func _to_world(local: Vector2) -> Vector2:
	return (local / _scale - Vector2.ONE) / _px_per_world


func _draw() -> void:
	if _texture == null:
		return
	draw_rect(Rect2(Vector2(-3, -3), size + Vector2(6, 6)), Color(0.07, 0.09, 0.11, 0.9))
	draw_texture_rect(_texture, Rect2(Vector2.ZERO, size), false)
	var frame := _view.intersection(Rect2(Vector2.ZERO, size))
	if frame.has_area():
		draw_rect(frame, Color(1, 1, 1, 0.9), false, 1.5)


func _gui_input(event: InputEvent) -> void:
	var pressed: bool = event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT
	var dragged: bool = event is InputEventMouseMotion and event.button_mask & MOUSE_BUTTON_MASK_LEFT != 0
	if pressed or dragged:
		jump.emit(_to_world(event.position))
		accept_event()
