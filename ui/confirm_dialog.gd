class_name ConfirmDialog
extends Control
## A yes/no question over the screen, e.g. "Deploy Noal (Archer) for 60 gold?".
## A modal: 50% dark overlay. Enter confirms, Esc cancels. With no cancel text it's a
## plain notice with one button (either key closes it). An alt text adds a middle
## button (e.g. "Leave without saving").

signal confirmed
signal cancelled
signal alt  # the optional middle button


func setup(question: String, ok_text: String, cancel_text := "Cancel", alt_text := "") -> void:
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
	var text := UiStyle.label(question, 22)
	if question.length() > 60:  # long text wraps instead of stretching the box across the screen
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = 640
	col.add_child(text)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	if cancel_text != "":
		var no := UiStyle.button(cancel_text, 160)
		no.pressed.connect(func(): cancelled.emit())
		row.add_child(no)
	if alt_text != "":
		var other := UiStyle.button(alt_text, 220)
		other.pressed.connect(func(): alt.emit())
		row.add_child(other)
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
