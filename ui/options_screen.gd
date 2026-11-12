class_name OptionsScreen
extends Control
## Options (SPEC §4 Start, §5.3 menu): the player's own switches, one per entry in
## data/options.json, saved the moment they change; volume entries are sliders (SPEC §24)
## and apply to the sound at once. A modal: 50% dark overlay.

signal closed

var data: GameData
var values: Dictionary


## `option_values` is the live dictionary the game reads, so changes apply at once.
func setup(game_data: GameData, option_values: Dictionary) -> void:
	data = game_data
	values = option_values
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): closed.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 560
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Options", 26), func(): closed.emit()))
	for id in data.options["options"]:
		var o: Dictionary = data.options["options"][id]
		if o.get("remembered", false):
			continue
		if o.get("type", "") == "volume":
			col.add_child(_volume(id, o))
			continue
		var c := CheckBox.new()
		c.text = o["label"]
		c.tooltip_text = o.get("tip", "")
		c.add_theme_font_size_override("font_size", 18)
		c.button_pressed = bool(values[id])
		c.toggled.connect(func(on: bool):
			values[id] = on
			PlayerOptions.save_values(values)
			Sound.apply_options(values))
		col.add_child(c)
		if id == "mute":  # the end of the sound settings
			col.add_child(HSeparator.new())
		if o.has("tip"):
			col.add_child(UiStyle.label(o["tip"], 14, Color(0.65, 0.68, 0.72)))


## A volume: its name, a 0-100 slider and the number.
func _volume(id: String, o: Dictionary) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var name := UiStyle.label(o["label"], 18)
	name.custom_minimum_size.x = 170
	row.add_child(name)
	var slider := HSlider.new()
	slider.min_value = 0
	slider.max_value = 100
	slider.step = 5
	slider.value = float(values[id])
	slider.size_flags_horizontal = SIZE_EXPAND_FILL
	slider.size_flags_vertical = SIZE_SHRINK_CENTER
	slider.tooltip_text = o.get("tip", "")
	row.add_child(slider)
	var number := UiStyle.label(str(int(values[id])), 18, Color(0.75, 0.78, 0.82))
	number.custom_minimum_size.x = 40
	number.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(number)
	slider.value_changed.connect(func(v: float):
		values[id] = int(v)
		number.text = str(int(v))
		Sound.apply_options(values)
		PlayerOptions.save_values(values))  # a small file; clicks on the track and keys save too
	return row


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
