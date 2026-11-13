class_name RecruitPopup
extends Control
## A neutral squad met on the map (SPEC §16): shown the class, not the count, and
## asked to Recruit or Fight. After Recruit, the same panel shows how it went before
## any battle starts. A modal: 50% dark overlay. After a won fight ("beaten", round 9)
## it asks once more: Recruit, or Let them go (the fight signal).

signal recruit
signal fight
signal done  # the result was read

var _col := VBoxContainer.new()
var _title: Label


var _beaten := false


func setup(class_name_: String, beaten := false) -> void:
	_beaten = beaten
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
	_col.add_theme_constant_override("separation", 10)
	_col.custom_minimum_size = Vector2(320, 150)
	panel.add_child(_col)
	_title = UiStyle.label(("The %s band is beaten" if beaten else "A band of %s") % class_name_, 22)
	_col.add_child(UiStyle.title_row(_title, Callable()))
	var ask := UiStyle.label("Try once more to recruit them? They would join with the HP they have left." if beaten
			else "Recruit them, or fight?", 14, Color(0.7, 0.72, 0.76))
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask.custom_minimum_size.x = 280
	_col.add_child(ask)
	var recruit_button := UiStyle.button("Recruit", 280)
	recruit_button.pressed.connect(func(): recruit.emit())
	_col.add_child(recruit_button)
	var fight_button := UiStyle.button("Let them go" if beaten else "Fight", 280)
	fight_button.pressed.connect(func(): fight.emit())
	_col.add_child(fight_button)


## Swaps the question for the outcome, in the same panel.
func show_result(joined: bool, text: String) -> void:
	for c in _col.get_children():
		if c != _title:
			c.queue_free()
	_title.text = "They join you!" if joined else "They refuse"
	var body := UiStyle.label(text, 14, Color(0.7, 0.72, 0.76))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 280
	_col.add_child(body)
	var ok := UiStyle.button("Continue" if joined or _beaten else "To battle", 280, true)
	ok.pressed.connect(func(): done.emit())
	_col.add_child(ok)
