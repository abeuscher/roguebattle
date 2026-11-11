class_name EnemyPopup
extends Control
## An enemy squad you've fought (user's playtest notes, 2026-11-10): its units as they
## stood when your last fight with it ended, front row above back, each with its class
## icon, class and level; fallen ones greyed. A modal: 50% dark overlay.

signal closed


func setup(state: GameState, s: Squad) -> void:
	var seen: Dictionary = state.intel[s.id]
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
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 480
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("%s  ·  %s" % [s.name, s.role.replace("_", " ").capitalize()], 26), func(): closed.emit()))
	var ago := state.clock.tick - int(seen["tick"])
	col.add_child(UiStyle.label("As your squad saw it at your last fight, %s ago." % GameState.duration_text(ago) if ago > 0
			else "As your squad saw it at your last fight.", 15, Color(0.75, 0.78, 0.84)))
	for r in ["front", "back"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		col.add_child(UiStyle.label(r.capitalize() + " row", 15, UiStyle.ACCENT))
		col.add_child(row)
		var any := false
		for u in seen["units"]:
			if u["row"] != r:
				continue
			any = true
			row.add_child(_unit(u))
		if not any:
			row.add_child(UiStyle.label("Empty", 15, Color(0.6, 0.62, 0.66)))


## One unit: icon, then class and level (and a star for the leader); greyed if it fell.
func _unit(u: Dictionary) -> Control:
	var box := VBoxContainer.new()
	box.custom_minimum_size.x = 104
	var pic := TextureRect.new()
	pic.texture = UnitIcons.texture(u["class"], 56)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(pic)
	var name := UiStyle.label("%s%s" % [u["class"], " ★" if u.get("leader", false) else ""], 15)
	name.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(name)
	var level := UiStyle.label("Level %d%s" % [u["level"], "" if u["alive"] else ", fallen"], 14, Color(0.75, 0.78, 0.84))
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(level)
	if not u["alive"]:
		box.modulate = Color(1, 1, 1, 0.45)
	box.tooltip_text = "%s, level %d%s" % [u["class"], u["level"], "" if u["alive"] else " (fallen when last seen)"]
	return box


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
