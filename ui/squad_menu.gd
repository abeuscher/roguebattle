class_name SquadMenu
extends Control
## The squad menu (SPEC §5.3), opened by selecting a squad. A modal: 50% dark
## overlay, and the game stays paused while it's open.

signal move
signal fire
signal return_to_base
signal edit
signal shop
signal use_item
signal closed

var _info := Label.new()


func setup(state: GameState, s: Squad) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.12, 0.15), 18))
	panel.custom_minimum_size = Vector2(440, 0)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := Label.new()
	title.text = "%d · %s" % [s.id, s.name]
	title.add_theme_font_size_override("font_size", 26)
	col.add_child(title)
	if s.is_moving():
		_info.text = "Travel type: %s · Speed tier %d · %s (%d)\nMoving: %d hexes to go, about %s." % [s.travel_name(), s.speed_tier,
				s.alignment_band(state.data).capitalize(), roundi(s.alignment()), s.path.size(), GameState.duration_text(state.route_ticks(s, s.path))]
	else:
		_info.text = "Travel type: %s · Speed tier %d · %s (%d)\nWaiting at %s." % [s.travel_name(), s.speed_tier,
				s.alignment_band(state.data).capitalize(), roundi(s.alignment()), state.map.hex_at(s.hex)]
	col.add_child(_info)
	var roster := UiStyle.label("Slots %d / %d" % [Squad.slots_filled(state.data, s.units), s.capacity(state.data)], 15,
			Color(0.75, 0.78, 0.84))
	for which in ["front", "back"]:
		roster.text += "\n%s row" % which.capitalize()
		for u in s.row(which):
			roster.text += "\n    %s, %s, level %d%s  ·  HP %d/%d" % [u.name, u.unit_class, u.level,
					"  (leader)" if u == s.leader else "", u.hp, u.max_hp(state.data)]
	col.add_child(roster)
	var at_base := s.hex == state.map.player_base
	_button(col, "Edit squad", state.can_edit(s), "Open the squad in Edit Units." if state.can_edit(s) else "Only at the Player Base.") \
			.pressed.connect(func(): edit.emit())
	var herbs := 0
	for id in state.army.supplies:
		herbs += int(state.army.supplies[id])
	_button(col, "Use item", herbs > 0, "Give a herb to a hurt unit." if herbs > 0 else "No supplies: buy herbs at a shop.") 			.pressed.connect(func(): use_item.emit())
	var place := state.shop_at(s)
	var shop_name := "Temple services" if place.get("type", "") == "temple" else "Shop"
	_button(col, shop_name, not place.is_empty(), "Buy here." if not place.is_empty() else "Stand still in a building with a shop (not enemy-held) or a temple.") 			.pressed.connect(func(): shop.emit())
	_button(col, "Move", true, "Click hexes to lay rally points.").pressed.connect(func(): move.emit())
	var targets := state.fire_targets(s)
	var why := ""
	if not state.can_fire(s):
		why = "No ranged or magic units in position."
	elif state.clock.tick < s.fire_ready:
		why = "Reloading: ready in %s." % GameState.duration_text(s.fire_ready - state.clock.tick)
	elif targets.is_empty():
		why = "No visible enemy within %d hexes." % state.fire_range(s)
	_button(col, "Ranged attack", targets.size() > 0, why if why != "" else "Click an enemy squad within %d hexes." % state.fire_range(s)) 			.pressed.connect(func(): fire.emit())
	_button(col, "Return to base", true, "Go into the Player Base." if at_base else "March to the Player Base and go in on arrival.") \
			.pressed.connect(func(): return_to_base.emit())
	_button(col, "Close (Esc)", true, "").pressed.connect(func(): closed.emit())


func _button(parent: Control, text: String, enabled: bool, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 40)
	parent.add_child(b)
	return b


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
