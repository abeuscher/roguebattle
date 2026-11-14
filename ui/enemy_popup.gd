class_name EnemyPopup
extends Control
## An enemy squad you've met in battle, clicked on the map while it's in sight (user's
## playtest notes, 2026-11-10; round 14): its units as they are now, front row above
## back, each as UnitPeek shows it (class, level, an HP bar, the attack from its row, a
## glossary link; no attribute numbers). Out of sight it can't be clicked at all.
## A modal: 50% dark overlay.

signal closed
signal glossary(unit_class: String)


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
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 520
	panel.add_child(col)
	var role := s.role.replace("_", " ").capitalize()
	col.add_child(UiStyle.title_row(UiStyle.label(s.name + ("  ·  " + role if role != "" else ""), 26), func(): closed.emit()))
	col.add_child(UiStyle.label("You've fought them before; in sight now, you can see how they stand.", 15, Color(0.75, 0.78, 0.84)))
	for r in ["front", "back"]:
		col.add_child(UiStyle.label(r.capitalize() + " row", 15, UiStyle.ACCENT))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		col.add_child(row)
		var units := s.row(r)
		units.sort_custom(func(a: Unit, b: Unit): return a.col < b.col)
		for u in units:
			row.add_child(UnitPeek.make(state.data, u, func(c: String): glossary.emit(c), u == s.leader))
		if units.is_empty():
			row.add_child(UiStyle.label("Empty", 15, Color(0.6, 0.62, 0.66)))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
