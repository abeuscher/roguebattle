class_name CampaignScreen
extends Control
## Start Campaign (SPEC §25.2): the campaigns to choose from, each with its description,
## and "Your name" as the Game summary asks it (the Opinion Leader takes it).

signal back
signal chosen(id: String, player_name: String)


func setup(data: GameData) -> void:
	UiStyle.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 28))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size.x = 560
	panel.add_child(col)
	col.add_child(UiStyle.label("Start a campaign", 34))
	var name_row := HBoxContainer.new()
	var caption := UiStyle.label("Your name", 18, Color(0.7, 0.72, 0.78))
	caption.custom_minimum_size.x = 160
	name_row.add_child(caption)
	var entry := LineEdit.new()
	entry.text = SummaryScreen.random_name(data)
	entry.max_length = int(data.rules["player_name_max"])
	entry.custom_minimum_size.x = 320
	entry.add_theme_font_size_override("font_size", 18)
	entry.tooltip_text = "Your Opinion Leader's name"
	name_row.add_child(entry)
	col.add_child(name_row)
	var first: Button
	for c in Campaign.list_all():
		var go := UiStyle.button(str(c["name"]), 520, first == null)
		go.pressed.connect(func():
			var who := entry.text.strip_edges()
			chosen.emit(str(c["id"]), who if who != "" else SummaryScreen.random_name(data)))
		col.add_child(go)
		var about := UiStyle.label(str(c["description"]), 16, Color(0.75, 0.77, 0.82))
		about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(about)
		if first == null:
			first = go
	var b := UiStyle.button("Back", 160)
	b.pressed.connect(func(): back.emit())
	col.add_child(b)
	if first:
		first.grab_focus.call_deferred()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k and k.pressed and k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		back.emit()
