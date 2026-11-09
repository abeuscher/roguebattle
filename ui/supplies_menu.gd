class_name SuppliesMenu
extends Control
## Use item (squad menu), anywhere on the map: a Herb for a hurt unit, a Revival
## Draught for a fallen one. Cure potions are for battle and don't show here.
## A modal: 50% dark overlay.

signal closed

var state: GameState
var squad: Squad
var _list := VBoxContainer.new()


func setup(game_state: GameState, s: Squad) -> void:
	state = game_state
	squad = s
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
	col.custom_minimum_size.x = 520
	panel.add_child(col)
	col.add_child(UiStyle.label("Use item  ·  %s" % s.name, 24))
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)
	var close := UiStyle.button("Close (Esc)", 180)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var any := false
	for id in state.data.items["consumables"]:
		var item: Dictionary = state.data.items["consumables"][id]
		if item["where"] != "map":
			continue
		var have := int(state.army.supplies.get(id, 0))
		_list.add_child(UiStyle.label("%s: %s  You have %d." % [item["name"], item["text"], have], 16, UiStyle.ACCENT))
		for u in squad.units:
			if not state.supply_helps(u, id):
				continue
			any = true
			var row := HBoxContainer.new()
			var l := UiStyle.label("%s (%s): HP %d/%d" % [u.name, u.unit_class, u.hp, u.max_hp(state.data)], 16)
			l.size_flags_horizontal = SIZE_EXPAND_FILL
			row.add_child(l)
			var b := UiStyle.button("Use %s" % item["name"], 150)
			b.disabled = have <= 0
			b.pressed.connect(func():
				state.use_supply(u, id)
				_refresh())
			row.add_child(b)
			_list.add_child(row)
	if not any:
		_list.add_child(UiStyle.label("No one in %s is hurt or fallen." % squad.name, 15, Color(0.6, 0.62, 0.66)))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
