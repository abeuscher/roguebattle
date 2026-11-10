class_name DeployMenu
extends Control
## Deploy Squad (from the battlemap toolbar): the squads waiting at the Player Base,
## each with its deploy cost; squads that can't go say why. Picking one starts laying
## its route. A modal: 50% dark overlay.

signal picked(squad: Squad)
signal closed


func setup(state: GameState) -> void:
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
	panel.custom_minimum_size.x = 640
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiStyle.label("Deploy Squad", 26))
	col.add_child(UiStyle.label("Gold %d  ·  On the map %d / %d" % [state.gold, state.player_squads().size(), state.squad_cap()],
			16, UiStyle.ACCENT))
	var waiting := state.army.squads().filter(func(s: Squad): return s not in state.squads)
	if waiting.is_empty():
		col.add_child(UiStyle.label("Every squad is already on the map.", 16, Color(0.6, 0.62, 0.66)))
	for s in waiting:
		var why := state.deploy_blocker(s)
		var b := UiStyle.button("#%d %s  ·  %d units  ·  %s, speed %d  ·  %d gold" % [s.id, s.name, s.units.size(),
				s.travel_name(), s.speed_tier, state.deploy_cost(s)], 600)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = why != ""
		b.tooltip_text = why if why != "" else "Then pick where it should head."
		b.pressed.connect(func(): picked.emit(s))
		col.add_child(b)
		if why != "":
			col.add_child(UiStyle.label("    " + why, 14, Color("#e0a050")))
	var close := UiStyle.button("Close (Esc)", 180)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_D]:
		closed.emit()
		get_viewport().set_input_as_handled()
