class_name CardsPanel
extends Control
## The hand of cards (SPEC §13), from the battlemap toolbar: each card's effect; Rooster
## and Fox can be played here, the rest in battle. With Foresight it shows the next card.
## In offer mode (a Seer or Oracle drew) it asks which card to take instead.
## A modal laid out like the battle's card picker (user's playtest notes, 2026-11-10):
## a dark shade over the screen, the title, then the cards in a centered wrapping row,
## scrolling only when they don't fit the screen.

signal closed

var state: GameState
var offer := false
var _list := HFlowContainer.new()
var _note := UiStyle.label("", 16, UiStyle.ACCENT)
var _title := UiStyle.label("", 26)
var _scroll := ScrollContainer.new()
var _tiles: Array[Control] = []  # the cards now showing, for sizing the scroll area


func setup(game_state: GameState, is_offer := false) -> void:
	state = game_state
	offer = is_offer
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): if not offer: closed.emit())
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_title if offer else UiStyle.title_row(_title, func(): closed.emit()))
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(_note)
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	col.add_child(_scroll)
	_list.add_theme_constant_override("h_separation", 16)
	_list.add_theme_constant_override("v_separation", 16)
	_list.alignment = FlowContainer.ALIGNMENT_CENTER
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	_scroll.add_child(_list)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_tiles.clear()
	var cards: Dictionary = state.data.cards["cards"]
	if offer:
		_title.text = "Choose a card"
		_note.visible = false
		for id in state.card_offer:
			_row(id, "Take", true, func():
				state.choose_card(id)
				closed.emit())
		_fit()
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
	_fit()


## As wide as the cards need (up to the battle picker's 1250 px), and as tall as their
## rows, scrolling only past what fits on the screen.
func _fit() -> void:
	var n := maxi(1, _tiles.size())
	var width := minf(1250.0, (CardFace.SIZE.x + 16) * n - 16)
	var per_row := maxi(1, floori((width + 16) / (CardFace.SIZE.x + 16)))
	var tile_h := CardFace.SIZE.y
	for t in _tiles:
		tile_h = maxf(tile_h, t.get_combined_minimum_size().y)
	var rows := ceili(_tiles.size() / float(per_row))
	var room := (get_viewport_rect().size.y if is_inside_tree() else 900.0) - 260.0
	_scroll.custom_minimum_size = Vector2(width, minf(maxf(0, rows * (tile_h + 16) - 16), room))


## One card face (CardFace) with its button, or a blank space the button's height
## for a card that can't be played here.
func _row(id: String, button: String, enabled: bool, action: Callable, count := 1) -> void:
	var b := UiStyle.button(button, 188, true)
	if not enabled:
		var gap := Control.new()
		gap.custom_minimum_size.y = b.get_combined_minimum_size().y
		b.free()
		_tiles.append(CardFace.make(state.data, id, count, gap))
	else:
		b.pressed.connect(action)
		_tiles.append(CardFace.make(state.data, id, count, b))
	_list.add_child(_tiles[-1])


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and not offer and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_C]:
		closed.emit()
	get_viewport().set_input_as_handled()
