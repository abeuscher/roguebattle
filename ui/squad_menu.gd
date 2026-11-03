class_name SquadMenu
extends Control
## The squad menu (SPEC §5.3), opened by selecting a squad. A modal: 50% dark
## overlay, and the game stays paused while it's open.

signal move
signal return_to_base
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
		_info.text = "Travel type: %s · Speed tier %d\nMoving: %d hexes to go, about %s." % [s.travel_name(), s.speed_tier,
				s.path.size(), GameState.duration_text(state.route_ticks(s, s.path))]
	else:
		_info.text = "Travel type: %s · Speed tier %d\nWaiting at %s." % [s.travel_name(), s.speed_tier, state.map.hex_at(s.hex)]
	col.add_child(_info)
	var at_base := s.hex == state.map.player_base
	_button(col, "Edit squad", false, "Edit Units arrives in M3.")
	_button(col, "Use item", false, "Items arrive in M3.")
	_button(col, "Move", true, "Click hexes to lay rally points.").pressed.connect(func(): move.emit())
	_button(col, "Return to base", not at_base, "").pressed.connect(func(): return_to_base.emit())
	_button(col, "Deploy", false, "Deployment arrives in M3." if at_base else "Only at the Player Base.")
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
