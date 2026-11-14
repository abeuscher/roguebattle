class_name UiStyle
## Shared look for placeholder screens and panels.

const BACKGROUND := Color("#12161c")
const PANEL := Color(0.1, 0.12, 0.15)
const ACCENT := Color("#ffe08a")
const TITLE := Color("#f4ead2")  # window titles
const ACTION := Color("#f2a93b")  # the main way forward on a screen
const OUTLINE := Color(0.42, 0.46, 0.53)
const ICON_SIZE := 20


static func box(color: Color, margin: int) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = color
	b.set_content_margin_all(margin)
	b.set_corner_radius_all(4)
	return b


## A picture filling its parent, scaled to cover and pinned to the bottom right (the top
## and left crop first), under the window color laid on from the top left: `fade` is
## [[where 0-1 along the diagonal, opacity], ...].
static func picture_behind(texture: Texture2D, fade: Array) -> Control:
	var box := Control.new()
	box.clip_contents = true
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var pic := TextureRect.new()
	pic.texture = texture
	pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	pic.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(pic)
	var g := Gradient.new()
	g.offsets = PackedFloat32Array()
	g.colors = PackedColorArray()
	for p in fade:
		g.add_point(float(p[0]), Color(PANEL, float(p[1])))
	var shade := TextureRect.new()
	var gt := GradientTexture2D.new()
	gt.gradient = g
	gt.fill_from = Vector2.ZERO
	gt.fill_to = Vector2.ONE
	shade.texture = gt
	shade.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_IGNORE
	box.add_child(shade)
	box.resized.connect(func():
		var t := texture.get_size()
		var s := maxf(box.size.x / t.x, box.size.y / t.y)
		pic.size = t * s
		pic.position = box.size - pic.size)
	return box


## Click-off-to-close for a modal: a left click on its shade (outside the popup) runs
## `action`. The full-screen container that centers the popup lets clicks through to it.
static func close_on_click(shade: Control, center: Control, action: Callable) -> void:
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
			action.call())


## "Do not show this window again" (user's notes, 2026-11-10): a checkbox for a window
## that only informs. Ticking it turns the player option `id` off (and saves); the same
## switch is on the Options screen.
static func dont_show_again(options: Dictionary, id: String, text := "Do not show this window again") -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.add_theme_font_size_override("font_size", 15)
	c.focus_mode = Control.FOCUS_NONE
	c.button_pressed = not bool(options.get(id, true))
	c.toggled.connect(func(on: bool):
		options[id] = not on
		PlayerOptions.save_values(options))
	return c


## The X at a modal's top right that closes it (playtest round 9: replaces the Close
## buttons at the bottom). `tip` names the key that also closes it.
## The close button (playtest round 12): a 34 px square with its own soft background,
## lighter on hover, darker and gold when pressed, so it reads as a button.
static func close_x(action: Callable, tip := "Close (Esc)") -> Button:
	var x := Button.new()
	x.icon = svg("x", 20)
	x.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	x.custom_minimum_size = Vector2(34, 34)
	for state in [["normal", Color(1, 1, 1, 0.07), Color(1, 1, 1, 0.0)], ["hover", Color(1, 1, 1, 0.18), Color(1, 1, 1, 0.35)],
			["pressed", Color(0, 0, 0, 0.35), ACCENT], ["focus", Color(0, 0, 0, 0), Color(0, 0, 0, 0)]]:
		var look := StyleBoxFlat.new()
		look.bg_color = state[1]
		look.border_color = state[2]
		look.set_border_width_all(1)
		look.set_corner_radius_all(8)
		x.add_theme_stylebox_override(state[0], look)
	x.add_theme_color_override("icon_hover_color", Color.WHITE)
	x.add_theme_color_override("icon_pressed_color", ACCENT)
	x.add_theme_color_override("icon_normal_color", Color(0.85, 0.87, 0.9))
	x.tooltip_text = tip
	x.focus_mode = Control.FOCUS_NONE
	x.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	x.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	x.pressed.connect(action)
	return x


## The title font (Cinzel, playtest round 12): carved capitals that set a window's title
## apart from its content.
static func title_font() -> Font:
	var f := FontVariation.new()
	f.base_font = load("res://ui/fonts/Cinzel.ttf")
	f.variation_opentype = {TextServerManager.get_primary_interface().name_to_tag("wght"): 650}
	return f


## A modal's title bar (playtest round 12): its own band, the title in the title font,
## the close button at its right, and a thin gold rule under it. A Label title takes the
## title font and a warm white unless it already has its own color. `extras` (gold, a
## squad's markers) sit between the title and the close button. An empty `action`
## (`Callable()`) leaves the close button off, for a window that needs an answer.
static func title_row(title: Control, action: Callable, tip := "Close (Esc)", extras: Array = []) -> Control:
	var bar := VBoxContainer.new()
	bar.add_theme_constant_override("separation", 0)
	var band := PanelContainer.new()
	var look := StyleBoxFlat.new()
	look.bg_color = Color(1, 1, 1, 0.045)
	look.set_corner_radius_all(8)
	look.content_margin_left = 14
	look.content_margin_right = 6
	look.content_margin_top = 6
	look.content_margin_bottom = 6
	band.add_theme_stylebox_override("panel", look)
	bar.add_child(band)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	band.add_child(row)
	if title is Label:
		title.add_theme_font_override("font", title_font())
		if not title.has_theme_color_override("font_color") or title.get_theme_color("font_color") == Color.WHITE:
			title.add_theme_color_override("font_color", TITLE)
		title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(title)
	for e in extras:
		row.add_child(e)
	if action.is_valid():
		row.add_child(close_x(action, tip))
	else:
		look.content_margin_right = 14
		look.content_margin_top = 10
		look.content_margin_bottom = 10
	var rule := ColorRect.new()
	rule.color = Color(ACCENT, 0.35)
	rule.custom_minimum_size.y = 1
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var gap := Control.new()
	gap.custom_minimum_size.y = 6
	bar.add_child(gap)
	bar.add_child(rule)
	return bar


## A heading inside a window, under the title bar: small capitals in the title font and
## a muted gold, to group what follows (playtest round 12).
static func section(text: String) -> Label:
	var l := label(text.to_upper(), 13, Color(ACCENT, 0.75))
	l.add_theme_font_override("font", title_font())
	return l


## The game's name in the title font (Fleur De Leah, trial pick 2026-11-12), centred.
static func game_name(font_size: int) -> Label:
	var l := label("Rogue Empire", font_size, Color("#f4ead2"))
	l.add_theme_font_override("font", load("res://ui/fonts/FleurDeLeah-Regular.ttf"))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	return l


static func label(text: String, font_size := 16, color := Color.WHITE) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", font_size)
	l.add_theme_color_override("font_color", color)
	return l


## An outlined button. `action` fills it with the action color, for the main way forward.
## `icon_kind` is one of icon()'s kinds.
static func button(text: String, min_width := 220.0, action := false, icon_kind := "") -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(min_width, 44)
	b.add_theme_font_size_override("font_size", 18)
	var fill := ACTION if action else Color(0.15, 0.17, 0.21)
	var edge := ACTION.lightened(0.25) if action else OUTLINE
	var text_color := Color(0.1, 0.08, 0.04) if action else Color.WHITE
	b.add_theme_stylebox_override("normal", _outlined(fill, edge))
	b.add_theme_stylebox_override("hover", _outlined(fill.lightened(0.12), ACCENT))
	b.add_theme_stylebox_override("pressed", _outlined(fill.darkened(0.2), ACCENT))
	b.add_theme_stylebox_override("focus", _outlined(Color(0, 0, 0, 0), ACCENT))
	b.add_theme_stylebox_override("disabled", _outlined(fill.darkened(0.4), edge.darkened(0.4)))
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(state, text_color)
	b.add_theme_color_override("font_disabled_color", text_color.darkened(0.5) if not action else text_color)
	if icon_kind != "":
		b.icon = icon(icon_kind)
	return b


static func _outlined(fill: Color, edge: Color) -> StyleBoxFlat:
	var s := box(fill, 8)
	s.set_border_width_all(2)
	s.border_color = edge
	return s


## A small white icon drawn in code: "copy", "apply", "open", "closed", "play", "pause", "clock", "calendar",
## or an alignment: "holy" (a sun), "neutral" (a half-filled circle), "evil" (a horned head).
## An icon from ui/icons/<name>.svg (Lucide, an open icon set, ISC licence; swap the
## files to change the look), drawn `px` pixels square in `color`.
static func svg(name: String, px := ICON_SIZE, color := Color.WHITE) -> Texture2D:
	var text := FileAccess.get_file_as_string("res://ui/icons/%s.svg" % name)
	var img := Image.new()
	if text == "" or img.load_svg_from_string(text.replace("currentColor", "#" + color.to_html(false)), px / 24.0) != OK:
		return null
	return ImageTexture.create_from_image(img)


static func icon(kind: String, n := ICON_SIZE) -> ImageTexture:
	var img := Image.create(n, n, false, Image.FORMAT_RGBA8)
	for y in n:
		for x in n:
			var p := Vector2(x + 0.5, y + 0.5) / n
			if _icon_covers(kind, p):
				img.set_pixel(x, y, Color.WHITE)
	return ImageTexture.create_from_image(img)


static func _icon_covers(kind: String, p: Vector2) -> bool:
	match kind:
		"copy":  # two overlapping sheets
			return _frame(p, Rect2(0.32, 0.32, 0.6, 0.6)) \
					or (_frame(p, Rect2(0.08, 0.08, 0.6, 0.6)) and not Rect2(0.32, 0.32, 0.6, 0.6).has_point(p))
		"apply":  # a check mark
			return _near(p, Vector2(0.12, 0.52), Vector2(0.4, 0.8)) or _near(p, Vector2(0.4, 0.8), Vector2(0.9, 0.22))
		"open":
			return Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.15, 0.3), Vector2(0.85, 0.3), Vector2(0.5, 0.75)]))
		"closed":
			return Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.3, 0.15), Vector2(0.75, 0.5), Vector2(0.3, 0.85)]))
		"play":  # a triangle pointing right, nudged right so it looks centered
			return Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.24, 0.12), Vector2(0.88, 0.5), Vector2(0.24, 0.88)]))
		"pause":  # two bars
			return Rect2(0.2, 0.14, 0.2, 0.72).has_point(p) or Rect2(0.6, 0.14, 0.2, 0.72).has_point(p)
		"clock":  # a ring with two hands
			var d := p.distance_to(Vector2(0.5, 0.5))
			return (d > 0.36 and d < 0.47) or _near(p, Vector2(0.5, 0.5), Vector2(0.5, 0.24)) or _near(p, Vector2(0.5, 0.5), Vector2(0.7, 0.5))
		"calendar":  # a page with a header band and two rings
			return _frame(p, Rect2(0.1, 0.2, 0.8, 0.72)) or Rect2(0.1, 0.2, 0.8, 0.2).has_point(p) \
					or Rect2(0.26, 0.06, 0.1, 0.2).has_point(p) or Rect2(0.64, 0.06, 0.1, 0.2).has_point(p) \
					or Rect2(0.28, 0.54, 0.14, 0.12).has_point(p) or Rect2(0.58, 0.54, 0.14, 0.12).has_point(p)
		"holy":  # a sun
			var v := p - Vector2(0.5, 0.5)
			if v.length() < 0.2:
				return true
			for i in 8:
				var dir := Vector2.from_angle(i * PI / 4.0)
				if _near(p, Vector2(0.5, 0.5) + dir * 0.3, Vector2(0.5, 0.5) + dir * 0.44):
					return true
			return false
		"neutral":  # a ring, its left half filled
			var d := p.distance_to(Vector2(0.5, 0.5))
			return (d > 0.32 and d < 0.43) or (d < 0.43 and p.x < 0.5)
		"evil":  # a horned head
			return p.distance_to(Vector2(0.5, 0.62)) < 0.27 \
					or Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.27, 0.52), Vector2(0.44, 0.4), Vector2(0.16, 0.08)])) \
					or Geometry2D.is_point_in_polygon(p, PackedVector2Array([Vector2(0.73, 0.52), Vector2(0.56, 0.4), Vector2(0.84, 0.08)]))
	return false


static func _frame(p: Vector2, r: Rect2) -> bool:
	return r.has_point(p) and not r.grow(-0.1).has_point(p)


static func _near(p: Vector2, a: Vector2, b: Vector2) -> bool:
	return p.distance_to(Geometry2D.get_closest_point_to_segment(p, a, b)) < 0.08


## A full-screen backdrop for a screen.
static func backdrop(parent: Control) -> void:
	parent.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = BACKGROUND
	bg.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	parent.add_child(bg)
