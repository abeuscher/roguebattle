class_name DebugPanel
extends Control
## The start of the debug panel (SPEC §19.2, backtick): for now just the wide
## roster tool for playtesting unit variety. M4 session 6 fills in the rest.
## A modal: 50% dark overlay.

signal closed
signal wide_roster


func setup() -> void:
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
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 320
	panel.add_child(col)
	col.add_child(UiStyle.label("Debug", 26))
	col.add_child(UiStyle.label("Not part of the real game.", 14, Color(0.7, 0.72, 0.76)))
	var wide := UiStyle.button("Wide roster (16 squads)", 280)
	wide.pressed.connect(func(): wide_roster.emit())
	col.add_child(wide)
	var close := UiStyle.button("Close (Esc)", 280)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_QUOTELEFT, KEY_ESCAPE]:
		closed.emit()
		get_viewport().set_input_as_handled()
