class_name RecruitPopup
extends Control
## A neutral squad met on the map (SPEC §16): shown the class, not the count, and
## asked to Recruit, Sneak past (playtest round 14) or Fight. After Recruit, the same panel shows how it went before
## any battle starts. A modal: 50% dark overlay. After a won fight ("beaten", round 9)
## it asks once more: Recruit, or Let them go (the fight signal).

signal recruit
signal fight
signal sneak  # try to slip past (playtest round 14); only at the first meeting
signal done  # the result was read
signal glossary(unit_class: String)  # "What are they?": the class's glossary entry

var _col := VBoxContainer.new()
var _panel: PanelContainer
var _title: Label
var _title_row: Control  # the title's bar, kept when the result replaces the question


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
	_panel = panel
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	_col.add_theme_constant_override("separation", 10)
	_col.custom_minimum_size = Vector2(320, 150)
	panel.add_child(_col)
	_title = UiStyle.label(("The %s band is beaten" if beaten else "A band of %s") % class_name_, 22)
	_title_row = UiStyle.title_row(_title, Callable(), "", [UiStyle.help(func(): glossary.emit(class_name_), "The %s in the unit glossary" % class_name_)])
	_col.add_child(_title_row)
	var ask := UiStyle.label("Try once more to recruit them? They would join with the HP they have left." if beaten
			else "Recruit them, sneak past, or fight?", 14, Color(0.7, 0.72, 0.76))
	ask.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	ask.custom_minimum_size.x = 280
	_col.add_child(ask)
	var recruit_button := UiStyle.button("Recruit", 280)
	recruit_button.pressed.connect(func(): recruit.emit())
	_col.add_child(recruit_button)
	if not beaten:
		var sneak_button := UiStyle.button("Sneak past", 280)
		sneak_button.tooltip_text = "Slip by unseen: the better your squad's agility against theirs, the likelier.
Spotted, they strike first."
		sneak_button.pressed.connect(func(): sneak.emit())
		_col.add_child(sneak_button)
	var fight_button := UiStyle.button("Let them go" if beaten else "Fight", 280)
	fight_button.pressed.connect(func(): fight.emit())
	_col.add_child(fight_button)


## Swaps the question for the outcome, in the same panel: `title` over `text`, and a
## button that reads `button`.
func show_result(title: String, text: String, button: String) -> void:
	for c in _col.get_children():
		if c != _title_row:
			c.queue_free()
	_title.text = title
	var body := UiStyle.label(text, 16, Color(0.85, 0.87, 0.9))
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = 320
	_col.add_child(body)
	var ok := UiStyle.button(button, 280, true)
	ok.pressed.connect(func(): done.emit())
	_col.add_child(ok)


## Where a player tip points (Battlemap._offer_tip): "panel", the window.
func anchor(name: String) -> Rect2:
	return _panel.get_global_rect() if name == "panel" else Rect2()
