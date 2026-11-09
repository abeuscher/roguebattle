class_name EncounterPopup
extends Control
## Shown when one of your squads runs into a hostile one (SPEC §11.1): the map is
## paused and the camera has flown to the fight; Go to fight opens the battle view.
## A modal, with a light shade and the panel in the lower part of the screen so the
## two squads stay in view at its center.

signal go


func setup(b: Battle) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.2)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.anchor_top = 0.62
	center.anchor_bottom = 0.9
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 460
	panel.add_child(col)
	var ours := b.sides[0]
	var who := ours.leader.name.get_slice(" ", 0) if ours.leader else ours.name
	col.add_child(UiStyle.label("%s's party has encountered the enemy" % who, 24))
	col.add_child(UiStyle.label("%s  ·  they look %s" % [b.sides[1].name, b.odds.to_lower()], 17, Color(0.8, 0.82, 0.86)))
	var button := UiStyle.button("Go to fight", 240, true)
	button.pressed.connect(func(): go.emit())
	col.add_child(button)
	button.grab_focus.call_deferred()
