class_name CardsPanel
extends Control
## The hand of cards (SPEC §13), from the battlemap toolbar: each card's effect; Rooster
## and Fox can be played here, the rest in battle. With Foresight it shows the next card.
## In offer mode (a Seer or Oracle drew) it asks which card to take instead.
## A modal: 50% dark overlay.

signal closed

var state: GameState
var offer := false
var _list := VBoxContainer.new()
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
	col.custom_minimum_size.x = 760
	panel.add_child(col)
	col.add_child(_title)
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.y = 520
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(scroll)
	_list.add_theme_constant_override("separation", 8)
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
	if state.foresight():
		_list.add_child(UiStyle.label("Foresight: the next card drawn will be %s." % state.card_name(state.next_card), 16, UiStyle.ACCENT))
	if state.cards.is_empty():
		_list.add_child(UiStyle.label("No cards. Liberate buildings and find hidden sites to draw more.", 16, Color(0.6, 0.62, 0.66)))
	var counts := {}
	for id in state.cards:
		counts[id] = counts.get(id, 0) + 1
	for id in counts:
		var on_map: bool = cards[id]["where"] == "map"
		_row(id, "Play" if on_map else "In battle", on_map, func():
			state.play_map_card(id)
			_refresh(), counts[id])


func _row(id: String, button: String, enabled: bool, action: Callable, count := 1) -> void:
	var c: Dictionary = state.data.cards["cards"][id]
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var text := VBoxContainer.new()
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	text.add_child(UiStyle.label("%s%s  ·  %s" % [c["name"], "  ×%d" % count if count > 1 else "", c["group"]], 18))
	var l := UiStyle.label(c["text"], 15, Color(0.8, 0.82, 0.86))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	text.add_child(l)
	row.add_child(text)
	var b := UiStyle.button(button, 140, enabled)
	b.disabled = not enabled
	b.tooltip_text = "" if enabled else "Play it during a battle."
	b.pressed.connect(action)
	row.add_child(b)
	_list.add_child(row)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not offer and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_C]:
		closed.emit()
	get_viewport().set_input_as_handled()
