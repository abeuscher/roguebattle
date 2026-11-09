class_name CardFace
## A card drawn as a card (SPEC §13): the animal's line drawing on parchment at the
## top, its name, then what it does at the bottom, with an optional button under that.
## Drawings are data/card_art/<card id>.svg; a card without one just shows its text.

const SIZE := Vector2(210, 360)
const ART_DIR := "res://data/card_art/"
const PARCHMENT := Color("#efe3c6")

static var _art := {}  # card id -> Texture2D, or null when there's no drawing


static func make(data: GameData, id: String, count := 1, button: Button = null) -> PanelContainer:
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
