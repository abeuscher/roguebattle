class_name ConfiguratorScreen
extends Control
## The configurator (SPEC §4, §6): every map setting, the seed with a randomize
## button, a live minimap preview, victory and defeat toggles, squad cap and the
## fairness toggle, plus the share code. The preview generates on a worker thread
## so the screen stays responsive on large maps.

signal back
signal next(map: MapData)  # the previewed map, or null if it doesn't match the settings yet

const OPEN_SECTIONS := ["Game mode", "Size", "Land shape", "Terrain"]  # the rest start collapsed
const SLIDER_COLOR := Color(0.78, 0.8, 0.85)

var data: GameData
var config: GameConfig
var _controls := {}  # field key -> control
var _sections := {}  # heading button -> its section
var _toggle_all: Button
var _preview := Minimap.new()
var _status := UiStyle.label("", 15, Color(0.7, 0.72, 0.78))
var _seed := LineEdit.new()
var _code := LineEdit.new()
var _thread: Thread
var _dirty := true
var _building_key := ""
var _built_key := ""
var _built_map: MapData
var _started_at := 0


func setup(game_data: GameData, game_config: GameConfig) -> void:
	data = game_data
	config = game_config
	UiStyle.backdrop(self)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	for side in ["left", "right", "top"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	margin.add_theme_constant_override("margin_bottom", 64)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	margin.add_child(columns)
	columns.add_child(_build_form())
	columns.add_child(_build_side())
	_refresh_controls()


func _build_form() -> Control:
	var form := VBoxContainer.new()
	form.custom_minimum_size.x = 880
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	var title_row := HBoxContainer.new()
	var title := UiStyle.label("Custom Map", 32)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	title_row.add_child(title)
	_toggle_all = UiStyle.button("", 170)
	_toggle_all.size_flags_vertical = SIZE_SHRINK_CENTER
	_toggle_all.pressed.connect(func(): _show_sections(not _all_open()))
	title_row.add_child(_toggle_all)
	form.add_child(title_row)  # stays put while the settings scroll
	form.add_child(scroll)
	var group := ""
	var section: VBoxContainer
	for f in data.config_fields:
		if f["group"] != group:
			group = f["group"]
			section = VBoxContainer.new()
			section.add_theme_constant_override("separation", 6)
			section.visible = group in OPEN_SECTIONS
			col.add_child(_section_heading(group, section))
			col.add_child(section)
		var row := HBoxContainer.new()
		var name := UiStyle.label(f["label"], 16)
		name.custom_minimum_size.x = 340
		row.add_child(name)
		var control := _control_for(f)
		control.custom_minimum_size.x = 480
		row.add_child(control)
		section.add_child(row)
	_update_headings()
	return form


## A heading that shows or hides its section when clicked.
func _section_heading(group: String, section: Control) -> Button:
	var b := Button.new()
	b.text = group
	b.flat = true
	b.alignment = HORIZONTAL_ALIGNMENT_LEFT
	b.custom_minimum_size.y = 40
	b.add_theme_font_size_override("font_size", 20)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color",
			"icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
		b.add_theme_color_override(state, UiStyle.ACCENT)
	b.add_theme_stylebox_override("focus", StyleBoxEmpty.new())
	b.pressed.connect(func():
		section.visible = not section.visible
		_update_headings())
	_sections[b] = section
	return b


func _show_sections(open: bool) -> void:
	for section in _sections.values():
		section.visible = open
	_update_headings()


func _all_open() -> bool:
	return _sections.values().all(func(s: Control): return s.visible)


## Heading arrows follow their sections; the corner button offers whichever helps more.
func _update_headings() -> void:
	for heading in _sections:
		heading.icon = UiStyle.icon("open" if _sections[heading].visible else "closed")
	_toggle_all.text = "Collapse all" if _all_open() else "Expand all"


## On/off fields get a check box; every other field a slider over its options,
## with the chosen value read out on the right.
func _control_for(f: Dictionary) -> Control:
	var key: String = f["key"]
	var opts := GameConfig.options(f)
	if opts.size() == 2 and opts[0] is bool:
		var box := CheckBox.new()
		box.toggled.connect(func(on: bool): _changed(key, on))
		_controls[key] = box
		return box
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var slider := HSlider.new()
	slider.max_value = opts.size() - 1
	slider.step = 1
	var filled := UiStyle.box(SLIDER_COLOR, 0)
	filled.content_margin_top = 3
	filled.content_margin_bottom = 3
	var empty := filled.duplicate() as StyleBoxFlat
	empty.bg_color = Color(SLIDER_COLOR, 0.3)
	slider.add_theme_stylebox_override("slider", empty)
	slider.add_theme_stylebox_override("grabber_area", filled)
	slider.add_theme_stylebox_override("grabber_area_highlight", filled)
	if f.has("options"):  # a dot at each choice
		slider.draw.connect(func(): _draw_stops(slider))
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	var value := UiStyle.label("", 16)
	value.custom_minimum_size.x = 200
	slider.value_changed.connect(func(i: float):
		value.text = _readout(f, int(i))
		_changed(key, opts[int(i)]))
	row.add_child(slider)
	row.add_child(value)
	_controls[key] = slider
	return row


## Dots where the slider can stop, full color up to the chosen one and faded past it.
## The grabber covers the chosen stop.
func _draw_stops(slider: HSlider) -> void:
	var grab := slider.get_theme_icon("grabber").get_width()
	var y := slider.size.y / 2.0
	for i in int(slider.max_value) + 1:
		if i == int(slider.value):
			continue
		var x := grab / 2.0 + (slider.size.x - grab) * i / slider.max_value
		var color := SLIDER_COLOR if i < slider.value else Color(SLIDER_COLOR, 0.55)
		slider.draw_circle(Vector2(x, y), 5.0, color)


## How a slider shows option i: its label, its number (width/height also name a
## matching Small/Medium/Large), or its name.
func _readout(f: Dictionary, i: int) -> String:
	if f.has("labels"):
		return str(f["labels"][i])
	var v: Variant = GameConfig.options(f)[i]
	if v is String:
		return v.capitalize()
	if f["key"] in ["width", "height"]:
		var width := int(v) if f["key"] == "width" else int(config.values["width"])
		var height := int(v) if f["key"] == "height" else int(config.values["height"])
		var name := GameConfig.size_name(data, width, height)
		return str(int(v)) + ("  ·  %s" % name if name != "Custom" else "")
	return str(int(v)) if float(v) == floorf(float(v)) else str(v)


func _build_side() -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.add_child(UiStyle.label("Preview", 22))
	_preview.width = 760
	_preview.mouse_filter = MOUSE_FILTER_IGNORE
	_preview.custom_minimum_size = Vector2(760, 430)
	col.add_child(_preview)
	col.add_child(_status)
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 10)
	var seed_label := UiStyle.label("Seed", 18)
	seed_label.custom_minimum_size.x = 110
	seed_row.add_child(seed_label)
	_seed.custom_minimum_size.x = 260
	_seed.text_submitted.connect(func(_t): _read_seed())
	_seed.focus_exited.connect(_read_seed)
	seed_row.add_child(_seed)
	var randomize := UiStyle.button("Randomize", 160)
	randomize.pressed.connect(func():
		config.seed = randi()
		_refresh_controls()
		_dirty = true)
	seed_row.add_child(randomize)
	col.add_child(seed_row)
	var code_row := HBoxContainer.new()
	code_row.add_theme_constant_override("separation", 10)
	var code_label := UiStyle.label("Share code", 18)
	code_label.custom_minimum_size.x = 110
	code_row.add_child(code_label)
	_code.custom_minimum_size.x = 360
	_code.text_submitted.connect(func(_t): _apply_code())
	code_row.add_child(_code)
	var copy := UiStyle.button("Copy", 120, false, "copy")
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_code.text)
		_status.text = "Share code copied.")
	code_row.add_child(copy)
	var apply := UiStyle.button("Apply", 120, false, "apply")
	apply.pressed.connect(_apply_code)
	code_row.add_child(apply)
	col.add_child(code_row)
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 16)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var b := UiStyle.button("Back", 160)
	b.pressed.connect(func(): back.emit())
	buttons.add_child(b)
	var go := UiStyle.button("Next", 240, true)
	go.pressed.connect(func(): next.emit(_built_map if _built_key == _key() else null))
	buttons.add_child(go)
	col.add_child(buttons)
	return col


func _changed(key: String, value: Variant) -> void:
	config.set_value(key, value)
	if key in ["preset", "land_pct"]:
		_refresh_controls()  # the map type resets land, islands and terrain; it also caps Land %
	elif key in ["width", "height", "mode"]:
		_refresh_controls()  # the other one's "· Small/Medium/Large" hint may now match or not; the squad cap follows size and mode
	_code.text = config.to_code()
	if config.field(key)["target"] == "map":
		_dirty = true


## Shows the config's values without triggering change handlers.
func _refresh_controls() -> void:
	for f in data.config_fields:
		var c: Control = _controls[f["key"]]
		var v: Variant = config.values[f["key"]]
		c.set_block_signals(true)
		if c is CheckBox:
			c.button_pressed = v
		elif c is HSlider:
			var i := GameConfig._index_of(GameConfig.options(f), v)
			c.value = i
			(c.get_parent().get_child(1) as Label).text = _readout(f, i)
		c.set_block_signals(false)
	_seed.text = str(config.seed)
	_code.text = config.to_code()


func _read_seed() -> void:
	if _seed.text.is_valid_int() and int(_seed.text) != config.seed:
		config.seed = int(_seed.text) & 0xffffffff
		_dirty = true
	_refresh_controls()


func _apply_code() -> void:
	var read := GameConfig.from_code(data, _code.text)
	if read == null:
		_status.text = "That isn't a valid share code."
		return
	config.values = read.values
	config.seed = read.seed
	_refresh_controls()
	_dirty = true
	_status.text = "Share code applied."


func _key() -> String:
	return "%d %s" % [config.seed, JSON.stringify(config.map_overrides())]


func _process(_delta: float) -> void:
	if _thread and not _thread.is_alive():
		var map: MapData = _thread.wait_to_finish()
		_thread = null
		_built_map = map
		_built_key = _building_key
		_preview.set_map(map, data)
		_status.text = "Preview ready (%.1f s)." % ((Time.get_ticks_msec() - _started_at) / 1000.0)
	if _dirty and _thread == null:
		_dirty = false
		_building_key = _key()
		var seed := config.seed
		var overrides := config.map_overrides()
		var d := data
		_started_at = Time.get_ticks_msec()
		_status.text = "Generating preview…"
		_thread = Thread.new()
		_thread.start(func(): return MapGen.generate(d, seed, overrides))


func _exit_tree() -> void:
	if _thread:
		_thread.wait_to_finish()
