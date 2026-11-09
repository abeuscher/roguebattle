class_name LiberationPopup
extends Control
## Shown when the player liberates a building (SPEC §6.5): names what was taken;
## a card drawn there, or a Seer/Oracle's choice of one, shows in this same dialog
## instead of a separate one (§13). A modal: 50% dark overlay.

signal closed

var state: GameState
var _offering := false


## `drawn_card` is the card id if one went straight into the hand, or "" if there
## was none or it's an offer instead (read from `game_state.card_offer`).
func setup(game_state: GameState, building: Dictionary, drawn_card: String) -> void:
	state = game_state
	_offering = drawn_card == "" and not state.card_offer.is_empty()
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
	col.custom_minimum_size.x = 420
	panel.add_child(col)
	var what: String = state.data.buildings[building["type"]]["name"]
	col.add_child(UiStyle.label("%s liberated!" % what, 24))
	if drawn_card != "":
		_card(col, drawn_card, "You draw ", "", Callable())
	elif _offering:
		col.add_child(UiStyle.label("Choose a card:", 16, Color(0.7, 0.72, 0.76)))
		for id in state.card_offer:
			_card(col, id, "", "Take", func():
				state.choose_card(id)
				closed.emit())
	_hand(col)
	if not _offering:
		var close := UiStyle.button("Close (Esc)", 280)
		close.pressed.connect(func(): closed.emit())
		col.add_child(close)


## A "View all cards" toggle that lists the current hand inside this dialog.
func _hand(col: VBoxContainer) -> void:
	var toggle := UiStyle.button("View all cards (%d)" % state.cards.size(), 280)
	toggle.disabled = state.cards.is_empty()
	col.add_child(toggle)
	var list := VBoxContainer.new()
	list.visible = false
	col.add_child(list)
	var counts := {}
	for id in state.cards:
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var c: Dictionary = state.data.cards["cards"][id]
		var l := UiStyle.label("%s%s  ·  %s" % [c["name"], "  ×%d" % counts[id] if counts[id] > 1 else "", c["text"]], 14, Color(0.8, 0.82, 0.86))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		list.add_child(l)
	toggle.pressed.connect(func():
		list.visible = not list.visible
		toggle.text = ("Hide cards (%d)" if list.visible else "View all cards (%d)") % state.cards.size())


func _card(col: VBoxContainer, id: String, prefix: String, button_text: String, action: Callable) -> void:
	var c: Dictionary = state.data.cards["cards"][id]
	col.add_child(UiStyle.label("%s%s" % [prefix, c["name"]], 18))
	var l := UiStyle.label(c["text"], 14, Color(0.8, 0.82, 0.86))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(l)
	if button_text != "":
		var b := UiStyle.button(button_text, 150)
		b.pressed.connect(action)
		col.add_child(b)


func _unhandled_key_input(event: InputEvent) -> void:
	if not _offering and event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
