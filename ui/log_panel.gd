class_name LogPanel
extends Control
## The game log (SPEC §19.1), opened with L: filter by category and squad, with a
## debug toggle for hidden values. A modal: 50% dark overlay; opening it pauses play.

signal closed

var _log: GameLog
var _category := OptionButton.new()
var _squad := OptionButton.new()
var _hidden := CheckBox.new()
var _text := RichTextLabel.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.12, 0.15), 16))
	panel.custom_minimum_size = Vector2(1100, 720)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 16)
	col.add_child(top)
	var title := Label.new()
	title.text = "Log"
	title.add_theme_font_size_override("font_size", 24)
	top.add_child(title)
	_category.add_item("All categories")
	for c in GameLog.CATEGORIES:
		_category.add_item(c.capitalize())
	_category.item_selected.connect(func(_i): _refresh())
	top.add_child(_category)
	_squad.item_selected.connect(func(_i): _refresh())
	top.add_child(_squad)
	_hidden.text = "Show hidden values (debug)"
	_hidden.toggled.connect(func(_on): _refresh())
	top.add_child(_hidden)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(spacer)
	var close := Button.new()
	close.text = "Close (L)"
	close.pressed.connect(func(): closed.emit())
	top.add_child(close)
	_text.size_flags_vertical = SIZE_EXPAND_FILL
	_text.scroll_following = true
	_text.selection_enabled = true
	col.add_child(_text)


func show_log(log: GameLog) -> void:
	_log = log
	_squad.clear()
	_squad.add_item("All squads")
	_squad.set_item_metadata(0, -1)
	var ids := {}
	for e in log.entries:
		if e["squad"] >= 0:
			ids[e["squad"]] = true
	for id in ids.keys():
		_squad.add_item("Squad %d" % id)
		_squad.set_item_metadata(_squad.item_count - 1, id)
	_refresh()


func _refresh() -> void:
	if _log == null:
		return
	var category: String = "" if _category.selected <= 0 else GameLog.CATEGORIES[_category.selected - 1]
	var squad: int = _squad.get_item_metadata(maxi(_squad.selected, 0))
	var lines := PackedStringArray()
	for e in _log.filtered(category, squad):
		lines.append(GameLog.format(e, _hidden.button_pressed))
	_text.text = "\n".join(lines) if not lines.is_empty() else "(nothing logged yet)"


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_L, KEY_ESCAPE]:
		closed.emit()
		get_viewport().set_input_as_handled()
