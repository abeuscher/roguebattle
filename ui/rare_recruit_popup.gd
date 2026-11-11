class_name RareRecruitPopup
extends Control
## A rare recruit found at a hidden site (playtest round 10): who it is, and Recruit or
## Leave. Leave keeps the site for later. A modal: 50% dark overlay.

signal answered(take: bool)


func setup(state: GameState) -> void:
	var u: Unit = state.pending_rare["unit"]
	var s: Squad = state.pending_rare["squad"]
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 440
	panel.add_child(col)
	col.add_child(UiStyle.label("A rare recruit", 24))
	var who := HBoxContainer.new()
	who.add_theme_constant_override("separation", 14)
	col.add_child(who)
	var pic := TextureRect.new()
	pic.texture = UnitIcons.texture(u.unit_class, 64)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	who.add_child(pic)
	var text := VBoxContainer.new()
	text.size_flags_vertical = SIZE_SHRINK_CENTER
	text.add_child(UiStyle.label(u.name, 20))
	text.add_child(UiStyle.label("%s, level %d" % [u.unit_class, u.level], 16, Color(0.75, 0.78, 0.82)))
	who.add_child(text)
	var line := UiStyle.label("%s has found someone who would join you and wait in the recruit pool at the Player Base." % s.name, 15, Color(0.75, 0.78, 0.82))
	line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(line)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.alignment = BoxContainer.ALIGNMENT_END
	col.add_child(row)
	var leave := UiStyle.button("Leave", 160)
	leave.tooltip_text = "Leave them here for later."
	leave.focus_mode = FOCUS_NONE
	leave.pressed.connect(func(): answered.emit(false))
	row.add_child(leave)
	var take := UiStyle.button("Recruit", 200, true)
	take.pressed.connect(func(): answered.emit(true))
	row.add_child(take)
	take.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		answered.emit(false)
		get_viewport().set_input_as_handled()
