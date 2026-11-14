class_name CardFace
## A card drawn as a card (SPEC §13): the card's picture (data/card_art/<card id>.jpg,
## its name already on the banner) with what it does written on the blank parchment
## under the name, and an optional button (or a blank space of the same height) under
## the card. A card with no picture yet gets a stand-in: its old line drawing
## (<card id>.svg) on parchment at the top, its name, then its text.

const SIZE := Vector2(210, 393)  # the picture's 752x1408, scaled to 210 wide
const ART_DIR := "res://data/card_art/"
const PARCHMENT := Color("#efe3c6")
const INK := Color("#1f140a")

static var _art := {}  # card id -> Texture2D, or null when there's no drawing


## A played card leaves the board (playtest round 13): a copy of `tile` (a card made by
## make) over it in `host` grows and fades out, then is gone. The tile itself can go at
## once. How large and how long are in cards.json's "played_fade".
static func fade_away(host: Control, tile: Control, data: GameData, id: String) -> void:
	var look: Dictionary = data.cards["played_fade"]
	var copy := make(data, id)
	_ignore_mouse(copy)
	copy.z_index = 100
	host.add_child(copy)
	copy.size = copy.get_combined_minimum_size()
	copy.global_position = tile.global_position
	copy.pivot_offset = copy.size / 2
	var t := copy.create_tween().set_parallel().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	t.tween_property(copy, "scale", Vector2.ONE * float(look["scale"]), float(look["seconds"]))
	t.tween_property(copy, "modulate:a", 0.0, float(look["seconds"]))
	t.chain().tween_callback(copy.queue_free)


static func _ignore_mouse(c: Control) -> void:
	c.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for k in c.get_children():
		if k is Control:
			_ignore_mouse(k)


## `scale`: the card larger or smaller than SIZE (the liberation window's is 1.2).
static func make(data: GameData, id: String, count := 1, button: Control = null, scale := 1.0) -> Control:
	var path := ART_DIR + id + ".jpg"
	if not ResourceLoader.exists(path):
		return _stand_in(data, id, count, button)
	var c: Dictionary = data.cards["cards"][id]
	var tile := VBoxContainer.new()
	tile.add_theme_constant_override("separation", 6)
	var pic := TextureRect.new()
	pic.texture = load(path)
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.stretch_mode = TextureRect.STRETCH_SCALE
	pic.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS  # smooth at a quarter of its size
	pic.custom_minimum_size = SIZE * scale
	pic.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	tile.add_child(pic)
	var box: Array = data.cards["art_text_box"]["rect"]
	var back := Panel.new()  # a plain parchment patch, so the text isn't read over cracks and stains
	var paper := StyleBoxFlat.new()
	paper.bg_color = Color(PARCHMENT, 0.92)
	paper.set_corner_radius_all(6)
	back.add_theme_stylebox_override("panel", paper)
	back.anchor_left = box[0] - 0.03
	back.anchor_top = box[1]
	back.anchor_right = box[2] + 0.03
	back.anchor_bottom = box[3]
	pic.add_child(back)
	var text := UiStyle.label(c["text"], roundi(14 * scale), INK)
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	text.set_anchors_preset(Control.PRESET_FULL_RECT)
	text.anchor_left = box[0]
	text.anchor_top = box[1]
	text.anchor_right = box[2]
	text.anchor_bottom = box[3]
	pic.add_child(text)
	if count > 1:
		var badge := PanelContainer.new()
		var look := UiStyle.box(Color("#2a2433"), 4)
		look.border_color = UiStyle.ACCENT
		look.set_border_width_all(2)
		look.set_corner_radius_all(8)
		badge.add_theme_stylebox_override("panel", look)
		badge.add_child(UiStyle.label("×%d" % count, 18, UiStyle.ACCENT))
		badge.position = Vector2(SIZE.x * scale - 50, 6)
		pic.add_child(badge)
	if button:
		button.custom_minimum_size.x = SIZE.x * scale - 22
		button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		tile.add_child(button)
	return tile


## The old face, for a card with no picture yet.
static func _stand_in(data: GameData, id: String, count: int, button: Control) -> Control:
	var c: Dictionary = data.cards["cards"][id]
	var tile := PanelContainer.new()
	var look := UiStyle.box(Color("#2a2433"), 10)
	look.border_color = UiStyle.ACCENT
	look.set_border_width_all(2)
	look.set_corner_radius_all(10)
	tile.add_theme_stylebox_override("panel", look)
	tile.custom_minimum_size = SIZE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	tile.add_child(col)
	var tex := art(id)
	if tex:
		var frame := PanelContainer.new()
		var paper := UiStyle.box(PARCHMENT, 4)
		paper.set_corner_radius_all(6)
		frame.add_theme_stylebox_override("panel", paper)
		var pic := TextureRect.new()
		pic.texture = tex
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = Vector2(170, 170)
		frame.add_child(pic)
		col.add_child(frame)
	var heading := UiStyle.label(c["name"] + ("  ×%d" % count if count > 1 else ""), 22, UiStyle.ACCENT)
	heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(heading)
	var text := UiStyle.label(c["text"], 14, Color(0.88, 0.89, 0.92))
	text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	text.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	text.custom_minimum_size.x = SIZE.x - 24
	text.size_flags_vertical = Control.SIZE_EXPAND_FILL
	col.add_child(text)
	if button:
		button.custom_minimum_size.x = SIZE.x - 24
		col.add_child(button)
	return tile


## The card's drawing, rasterized once at 2× for crisp edges.
static func art(id: String) -> Texture2D:
	if not _art.has(id):
		_art[id] = null
		var path := ART_DIR + id + ".svg"
		if FileAccess.file_exists(path):
			var img := Image.new()
			if img.load_svg_from_string(FileAccess.get_file_as_string(path), 2.0) == OK:
				_art[id] = ImageTexture.create_from_image(img)
	return _art[id]
