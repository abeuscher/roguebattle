class_name ConfirmDialog
extends Control
## A yes/no question over the screen, e.g. "Deploy Noal (Archer) for 60 gold?".
## A modal: 50% dark overlay. Enter confirms, Esc cancels.

signal confirmed
signal cancelled


func setup(question: String, ok_text: String) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): cancelled.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 24))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 20)
	panel.add_child(col)
	col.add_child(UiStyle.label(question, 22))
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var no := UiStyle.button("Cancel", 160)
	no.pressed.connect(func(): cancelled.emit())
	row.add_child(no)
	var yes := UiStyle.button(ok_text, 180, true)
	yes.pressed.connect(func(): confirmed.emit())
	row.add_child(yes)
	yes.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	match (event as InputEventKey).keycode:
		KEY_ESCAPE:
			cancelled.emit()
		KEY_ENTER, KEY_KP_ENTER:
			confirmed.emit()
	get_viewport().set_input_as_handled()
