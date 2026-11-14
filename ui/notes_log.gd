class_name NotesLog
extends Control
## The notifications log (playtest round 13): every notice the map's banner has shown,
## oldest first, in a ledger book: a parchment page in a leather binding, the day and
## time in a ruled margin. Place names are links: clicking one closes the log and the
## map centres on the place. Opened by the book beside the gold, or N; X, Esc or a click
## outside closes it.

signal closed
signal place_pressed(hex: int)

const PAGE := Color("#efe3c6")
const LEATHER := Color("#4a2e18")
const INK := Color("#2a1c0f")
const FADED := Color("#6b5640")
const RULE := Color(0.45, 0.58, 0.7, 0.35)  # the page's blue ruling
const MARGIN := Color(0.7, 0.2, 0.15, 0.55)  # the red margin line
const WHEN_WIDTH := 132.0


## `notes`: [{when, text, links}] (links: place name -> hex), oldest first.
func setup(notes: Array) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): closed.emit())
	var book := PanelContainer.new()
	var binding := StyleBoxFlat.new()
	binding.bg_color = PAGE
	binding.border_color = LEATHER
	binding.set_border_width_all(12)
	binding.set_corner_radius_all(10)
	binding.set_content_margin_all(30)
	binding.shadow_color = Color(0, 0, 0, 0.5)
	binding.shadow_size = 14
	book.add_theme_stylebox_override("panel", binding)
	var screen := get_viewport_rect().size
	book.custom_minimum_size = Vector2(minf(1000, screen.x - 80), minf(780, screen.y - 80))  # a big book, within the screen
	center.add_child(book)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	book.add_child(col)
	var title := UiStyle.label("Ledger of Notices", 28, INK)
	title.add_theme_font_override("font", UiStyle.title_font())
	var x := UiStyle.close_x(func(): closed.emit(), "Close (N or Esc)")
	x.add_theme_color_override("icon_normal_color", INK)
	x.add_theme_color_override("icon_hover_color", LEATHER)
	var top := HBoxContainer.new()
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(title)
	top.add_child(x)
	col.add_child(top)
	col.add_child(_row(_cell("When", 15, FADED, true), _cell("Entry", 15, FADED, true), 2))
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(scroll)
	var lines := VBoxContainer.new()
	lines.add_theme_constant_override("separation", 0)
	lines.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(lines)
	if notes.is_empty():
		lines.add_child(_row(_cell("", 16, FADED), _cell("Nothing to record yet.", 16, FADED), 1))
	for n in notes:
		lines.add_child(_row(_cell(n["when"], 15, FADED), _entry(n["text"], n["links"]), 1))
	# Open at the latest entry, once the page has its height.
	scroll.ready.connect(func():
		await get_tree().process_frame
		scroll.scroll_vertical = int(scroll.get_v_scroll_bar().max_value))


## One ledger line: the when, the red margin, the entry, and the blue rule under it.
func _row(when: Control, entry: Control, rule_px: int) -> Control:
	var line := VBoxContainer.new()
	line.add_theme_constant_override("separation", 6)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	when.custom_minimum_size.x = WHEN_WIDTH
	row.add_child(when)
	var margin := ColorRect.new()
	margin.color = MARGIN
	margin.custom_minimum_size.x = 2
	row.add_child(margin)
	entry.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(entry)
	line.add_child(row)
	var rule := ColorRect.new()
	rule.color = MARGIN if rule_px > 1 else RULE
	rule.custom_minimum_size.y = rule_px
	line.add_child(rule)
	return line


func _cell(text: String, px: int, color: Color, heading := false) -> Label:
	var l := UiStyle.label(text, px, color)
	if heading:
		l.add_theme_font_override("font", UiStyle.title_font())
	l.size_flags_vertical = SIZE_SHRINK_BEGIN
	return l


## The entry's text with its place names as links.
func _entry(text: String, links: Dictionary) -> RichTextLabel:
	var r := RichTextLabel.new()
	r.bbcode_enabled = true
	r.fit_content = true
	r.scroll_active = false
	r.add_theme_font_size_override("normal_font_size", 17)
	r.add_theme_color_override("default_color", INK)
	var out := text.replace("[", "[lb]")
	for name in links:
		out = out.replace(name, "[url=%d][color=#7a2a14][u]%s[/u][/color][/url]" % [links[name], name])
	r.text = out
	r.meta_clicked.connect(func(meta: Variant): place_pressed.emit(int(str(meta))))
	r.meta_hover_started.connect(func(_m): r.mouse_default_cursor_shape = CURSOR_POINTING_HAND)
	r.meta_hover_ended.connect(func(_m): r.mouse_default_cursor_shape = CURSOR_ARROW)
	return r


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_N, KEY_ESCAPE]:
		closed.emit()
		get_viewport().set_input_as_handled()
