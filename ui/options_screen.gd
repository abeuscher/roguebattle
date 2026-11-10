class_name OptionsScreen
extends Control
## Options (SPEC §4 Start, §5.3 menu): the player's own switches, one per entry in
## data/options.json, saved the moment they change. A modal: 50% dark overlay.

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
	col.add_child(UiStyle.label("Options", 26))
	for id in data.options["options"]:
		var o: Dictionary = data.options["options"][id]
		var c := CheckBox.new()
		c.text = o["label"]
		c.tooltip_text = o.get("tip", "")
		c.add_theme_font_size_override("font_size", 18)
		c.button_pressed = bool(values[id])
		c.toggled.connect(func(on: bool):
			values[id] = on
			PlayerOptions.save_values(values))
		col.add_child(c)
		if o.has("tip"):
			col.add_child(UiStyle.label(o["tip"], 14, Color(0.65, 0.68, 0.72)))
	var close := UiStyle.button("Close (Esc)", 200)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)
	close.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
