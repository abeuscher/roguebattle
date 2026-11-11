class_name LiberationPopup
extends Control
## Shown when the player liberates a building (SPEC §6.5): names what was taken;
## a card drawn there, or a Seer/Oracle's choice of one, shows in this same dialog
## instead of a separate one (§13). A modal: 50% dark overlay.

signal closed
signal go_to  # "Go to city": close, and the map glides to the place

var state: GameState
var _offering := false


## `drawn_card` is the card id if one went straight into the hand, or "" if there
## was none or it's an offer instead (read from `game_state.card_offer`).
func setup(game_state: GameState, building: Dictionary, drawn_card: String, options := {}) -> void:
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
	UiStyle.close_on_click(shade, center, func(): if not _offering: closed.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 420
	panel.add_child(col)
	var what: String = building.get("name", state.data.buildings[building["type"]]["name"])
	col.add_child(UiStyle.label("%s liberated!" % what, 24))
	if drawn_card != "":
		col.add_child(UiStyle.label("You draw:", 16, Color(0.7, 0.72, 0.76)))
		var face := CardFace.make(state.data, drawn_card)
		face.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
		col.add_child(face)
	elif _offering:
		col.add_child(UiStyle.label("Choose a card:", 16, Color(0.7, 0.72, 0.76)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		col.add_child(row)
		for id in state.card_offer:
			var take := UiStyle.button("Take", 150, true)
			take.pressed.connect(func():
				state.choose_card(id)
				closed.emit())
			row.add_child(CardFace.make(state.data, id, 1, take))
	_hand(col)
	if not _offering:
		col.add_child(UiStyle.dont_show_again(options, "show_liberations"))
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(buttons)
	if not _offering:
		var close := UiStyle.button("Close (Esc)", 180)
		close.pressed.connect(func(): closed.emit())
		buttons.add_child(close)
		var go := UiStyle.button("Go to city" if building.has("name") else "Go to it", 180, true)
		go.pressed.connect(func(): go_to.emit())
		buttons.add_child(go)


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


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		if not _offering:  # a card choice needs an answer
			closed.emit()
		get_viewport().set_input_as_handled()
