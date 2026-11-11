class_name TownLostPopup
extends Control
## Shown when the enemy retakes a building of yours (playtest round 9): names it and the
## reputation it cost. A modal: 50% dark overlay; the map centres on the place first.

signal closed


func setup(state: GameState, entry: Dictionary) -> void:
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
	col.custom_minimum_size.x = 420
	panel.add_child(col)
	var where := state.where(entry["building"]["hex"])
	col.add_child(UiStyle.label("%s is lost" % (where.left(1).to_upper() + where.substr(1)), 24))
	col.add_child(UiStyle.label("The enemy has retaken %s." % where, 16))
	col.add_child(UiStyle.label("Reputation %d." % int(entry["reputation"]), 16, Color("#e0604a")))
	var ok := UiStyle.button("Continue", 200, true)
	ok.size_flags_horizontal = SIZE_SHRINK_END
	ok.pressed.connect(func(): closed.emit())
	col.add_child(ok)
	ok.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_ENTER]:
		closed.emit()
		get_viewport().set_input_as_handled()
