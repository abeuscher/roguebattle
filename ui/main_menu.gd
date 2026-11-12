class_name MainMenu
extends Control
## The in-game main menu (SPEC §5.3), opened with Esc: save game, save settings,
## options, return to title, quit. A modal: 50% dark overlay; play pauses while it's open.

signal resume
signal save_game
signal save_settings
signal options
signal to_title
signal quit

var _note := UiStyle.label("", 14, UiStyle.ACCENT)


## `save_blocker`: why the game can't be saved now, or "" (SaveGame.blocker).
func setup(save_blocker := "") -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): resume.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiStyle.label("Menu", 26))
	for entry in [["Resume (Esc)", resume], ["Save game", save_game], ["Save settings", save_settings], ["Options", options],
			["Return to title", to_title], ["Quit", quit]]:
		var b := UiStyle.button(entry[0], 280)
		var sig: Signal = entry[1]
		b.pressed.connect(func(): sig.emit())
		if sig == save_game and save_blocker != "":
			b.disabled = true
			b.tooltip_text = save_blocker
		col.add_child(b)
	col.add_child(_note)


func note(text: String) -> void:
	_note.text = text


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		resume.emit()
