class_name RecruitPopup
extends Control
## A neutral squad met on the map (SPEC §16): shown the class, not the count, and
## asked to Recruit or Fight. A modal: 50% dark overlay.

signal recruit
signal fight


func setup(class_name_: String) -> void:
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
	col.add_child(UiStyle.label("A band of %s" % class_name_, 22))
	col.add_child(UiStyle.label("Recruit them, or fight?", 14, Color(0.7, 0.72, 0.76)))
	var recruit_button := UiStyle.button("Recruit", 280)
	recruit_button.pressed.connect(func(): recruit.emit())
	col.add_child(recruit_button)
	var fight_button := UiStyle.button("Fight", 280)
	fight_button.pressed.connect(func(): fight.emit())
	col.add_child(fight_button)
