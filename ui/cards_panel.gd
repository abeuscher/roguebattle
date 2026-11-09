class_name CardsPanel
extends Control
## The hand of cards (SPEC §13), from the battlemap toolbar: each card's effect; Rooster
## and Fox can be played here, the rest in battle. With Foresight it shows the next card.
## In offer mode (a Seer or Oracle drew) it asks which card to take instead.
## A modal: 50% dark overlay.

signal closed

var state: GameState
var offer := false
var _list := HFlowContainer.new()
var _note := UiStyle.label("", 16, UiStyle.ACCENT)
var _title := UiStyle.label("", 24)


func setup(game_state: GameState, is_offer := false) -> void:
	state = game_state
	offer = is_offer
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
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = (CardFace.SIZE.x + 12) * 5 + 12
	panel.add_child(col)
	col.add_child(_title)
	col.add_child(_note)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = CardFace.SIZE.y * 2 + 24
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list.add_theme_constant_override("h_separation", 12)
	_list.add_theme_constant_override("v_separation", 12)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_list)
	if not offer:
		var close := UiStyle.button("Close (Esc)", 180)
		close.pressed.connect(func(): closed.emit())
		col.add_child(close)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	var cards: Dictionary = state.data.cards["cards"]
	if offer:
		_title.text = "Choose a card"
		for id in state.card_offer:
			_row(id, "Take", true, func():
				state.choose_card(id)
				closed.emit())
		return
	_title.text = "Cards (%d)" % state.cards.size()
	_note.text = ""
	if state.foresight():
		_note.text = "Foresight: the next card drawn will be %s." % state.card_name(state.next_card)
	if state.cards.is_empty():
		_note.text += ("
" if _note.text != "" else "") + "No cards. Liberate buildings and find hidden sites to draw more."
	_note.visible = _note.text != ""
	var counts := {}
	for id in state.cards:
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var on_map: bool = cards[id]["where"] == "map"
		_row(id, "Play" if on_map else "In battle", on_map, func():
			state.play_map_card(id)
			_refresh(), counts[id])


## One card face (CardFace) with its button, or a blank space the button's height
## for a card that can't be played here.
func _row(id: String, button: String, enabled: bool, action: Callable, count := 1) -> void:
	var b := UiStyle.button(button, 140, true)
	if not enabled:
		var gap := Control.new()
		gap.custom_minimum_size.y = b.get_combined_minimum_size().y
		b.free()
		_list.add_child(CardFace.make(state.data, id, count, gap))
		return
	b.pressed.connect(action)
	_list.add_child(CardFace.make(state.data, id, count, b))


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not offer and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_C]:
		closed.emit()
	get_viewport().set_input_as_handled()
