class_name ConfiguratorScreen
extends Control
## The configurator (SPEC §4, §6): every map setting, the seed with a randomize
## button, a live minimap preview, victory and defeat toggles, squad cap and the
## fairness toggle, plus the share code. The preview generates on a worker thread
## so the screen stays responsive on large maps.

signal back
signal next(map: MapData)  # the previewed map, or null if it doesn't match the settings yet

var data: GameData
var config: GameConfig
var _controls := {}  # field key -> control
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
	for side in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + side, 28)
	add_child(margin)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 32)
	margin.add_child(columns)
	columns.add_child(_build_form())
	columns.add_child(_build_side())
	_refresh_controls()


func _build_form() -> Control:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(880, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var col := VBoxContainer.new()
	col.size_flags_horizontal = SIZE_EXPAND_FILL
	col.add_theme_constant_override("separation", 6)
	scroll.add_child(col)
	col.add_child(UiStyle.label("Configure the map", 32))
	var group := ""
	for f in data.config_fields:
		if f["group"] != group:
			group = f["group"]
			var heading := UiStyle.label(group, 20, UiStyle.ACCENT)
			heading.custom_minimum_size.y = 40
			heading.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
			col.add_child(heading)
		var row := HBoxContainer.new()
		var name := UiStyle.label(f["label"], 16)
		name.custom_minimum_size.x = 340
		row.add_child(name)
		var control := _control_for(f)
		control.custom_minimum_size.x = 320
		row.add_child(control)
		col.add_child(row)
	return scroll


func _control_for(f: Dictionary) -> Control:
	var key: String = f["key"]
	var opts := GameConfig.options(f)
	if opts.size() == 2 and opts[0] is bool:
		var box := CheckBox.new()
		box.toggled.connect(func(on: bool): _changed(key, on))
		_controls[key] = box
		return box
	if f.has("range"):
		var row := HBoxContainer.new()
		var slider := HSlider.new()
		slider.min_value = f["range"][0]
		slider.max_value = f["range"][1]
		slider.step = f["range"][2]
		slider.size_flags_horizontal = SIZE_EXPAND_FILL
		slider.size_flags_vertical = SIZE_SHRINK_CENTER
		var value := UiStyle.label("", 16)
		value.custom_minimum_size.x = 48
		slider.value_changed.connect(func(v: float):
			value.text = str(int(v))
			_changed(key, v))
		row.add_child(slider)
		row.add_child(value)
		_controls[key] = slider
		return row
	var pick := OptionButton.new()
	for i in opts.size():
		pick.add_item(str(f["labels"][i]) if f.has("labels") else str(opts[i]).capitalize())
	pick.item_selected.connect(func(i: int): _changed(key, opts[i]))
	_controls[key] = pick
	return pick


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
	seed_row.add_child(UiStyle.label("Seed", 18))
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
	code_row.add_child(UiStyle.label("Share code", 18))
	_code.custom_minimum_size.x = 360
	_code.text_submitted.connect(func(_t): _apply_code())
	code_row.add_child(_code)
	var copy := UiStyle.button("Copy", 90)
	copy.pressed.connect(func():
		DisplayServer.clipboard_set(_code.text)
		_status.text = "Share code copied.")
	code_row.add_child(copy)
	var apply := UiStyle.button("Apply", 90)
	apply.pressed.connect(_apply_code)
	code_row.add_child(apply)
	col.add_child(code_row)
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(spacer)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	var b := UiStyle.button("Back", 160)
	b.pressed.connect(func(): back.emit())
	buttons.add_child(b)
	var go := UiStyle.button("Next", 200)
	go.pressed.connect(func(): next.emit(_built_map if _built_key == _key() else null))
	buttons.add_child(go)
	col.add_child(buttons)
	return col


func _changed(key: String, value: Variant) -> void:
	config.set_value(key, value)
	if key == "preset":
		_refresh_controls()  # the map type resets land, islands and terrain
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
			c.value = v
			(c.get_parent().get_child(1) as Label).text = str(int(v))
		elif c is OptionButton:
			c.selected = GameConfig._index_of(GameConfig.options(f), v)
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
