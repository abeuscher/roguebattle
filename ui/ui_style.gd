class_name UiStyle
## Shared look for placeholder screens and panels.

const BACKGROUND := Color("#12161c")
const PANEL := Color(0.1, 0.12, 0.15)
const ACCENT := Color("#ffe08a")


static func box(color: Color, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_content_margin_all(margin)
	b.set_corner_radius_all(4)
	return b


static func label(text: String, font_size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


static func button(text: String, min_width := 220.0) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 44)
	b.add_theme_font_size_override("font_size", 18)
	return b


## A full-screen backdrop for a screen.
static func backdrop(parent: Control) -> void:
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
