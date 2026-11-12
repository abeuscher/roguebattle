class_name PortalMenu
extends Control
## A temple's portal (session 059): the other temples you hold, each with how far and
## which way; picking one steps the squad there at once. A modal: 50% dark overlay.

signal picked(hex: int)
signal closed


func setup(state: GameState, s: Squad) -> void:
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
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 20))
	panel.custom_minimum_size.x = 520
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Portal", 26), func(): closed.emit()))
	col.add_child(UiStyle.label("%s can step at once to another temple you hold." % s.name, 16, Color(0.7, 0.72, 0.76)))
	var at := state.map.hex_at(s.hex)
	for hex in state.portal_targets(s):
		var where := state.where(hex)
		var b := UiStyle.button("%s  ·  %d hexes %s" % [where.left(1).to_upper() + where.substr(1),
				Hex.distance(at, state.map.hex_at(hex)), GameState.direction(at, state.map.hex_at(hex))], 480)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.pressed.connect(func(): picked.emit(hex))
		col.add_child(b)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
