class_name LiberationPopup
extends Control
## Shown when the player liberates a building (SPEC §6.5): names what was taken;
## a card drawn there, or a Seer/Oracle's choice of one, shows in this same dialog
## instead of a separate one (§13). A modal: 50% dark overlay.

signal closed

const CARD_SCALE := 1.2  # the drawn card, larger than elsewhere (playtest round 13)
const GROW := 1.15  # the window this much bigger than its contents need, so more of its picture shows

var state: GameState
var _offering := false
var _panel: PanelContainer


## `drawn_card` is the card id if one went straight into the hand, or "" if there
## was none or it's an offer instead (read from `game_state.card_offer`).
func setup(game_state: GameState, building: Dictionary, drawn_card: String, options := {}, recruits: Array = []) -> void:
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
	_panel = panel
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	col.custom_minimum_size.x = 420 if not recruits.is_empty() or _offering else 0  # no conscripts: just fit the card (round 11)
	var art: Dictionary = state.data.buildings[building["type"]].get("art", {})
	if ResourceLoader.exists(str(art.get("file", ""))):  # the building's picture behind it all (user, 2026-11-14)
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 0))
		panel.add_child(UiStyle.picture_behind(load(art["file"]), art.get("fade", [])))
		var pad := MarginContainer.new()
		for side in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 22)
		pad.add_child(col)
		panel.add_child(pad)
	else:
		panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
		panel.add_child(col)
	var what: String = building.get("name", state.data.buildings[building["type"]]["name"])
	var rewards: bool = state.data.buildings[building["type"]].get("liberation", true)
	var title := UiStyle.label("%s %s!" % [what, "liberated" if rewards else "taken"], 24)
	col.add_child(UiStyle.title_row(title, Callable() if _offering else func(): closed.emit()))
	# Round 9 layout: the card and View all cards on the left, the conscripts in an
	# equal-width column on the right.
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 28)
	col.add_child(body)
	var left := VBoxContainer.new()
	left.add_theme_constant_override("separation", 10)
	left.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(left)
	if not rewards:  # a temple (round 11): what holding it means, and its god
		_temple(left, building)
	elif drawn_card != "":
		left.add_child(UiStyle.section("You draw"))
		var face := CardFace.make(state.data, drawn_card, 1, null, CARD_SCALE)
		face.size_flags_horizontal = SIZE_SHRINK_BEGIN if not recruits.is_empty() else SIZE_SHRINK_CENTER
		left.add_child(face)
	elif _offering:
		left.add_child(UiStyle.section("Choose a card"))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		left.add_child(row)
		for id in state.card_offer:
			var take := UiStyle.button("Take", 150, true)
			take.pressed.connect(func():
				state.choose_card(id)
				closed.emit())
			row.add_child(CardFace.make(state.data, id, 1, take))
	if not recruits.is_empty():  # single map mode's conscription
		var right := VBoxContainer.new()
		right.add_theme_constant_override("separation", 10)
		right.size_flags_horizontal = SIZE_EXPAND_FILL
		right.custom_minimum_size.x = CardFace.SIZE.x
		body.add_child(right)
		right.add_child(UiStyle.section("Conscripts"))
		right.add_child(UiStyle.label("They join the recruit pool at the Player Base.", 14, Color(0.7, 0.72, 0.76)))
		for u in recruits:
			right.add_child(_conscript(u))
	var gap := Control.new()  # the extra room (GROW) goes here, keeping the bottom row at the bottom
	gap.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(gap)
	var bottom := HBoxContainer.new()
	col.add_child(bottom)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	if not _offering:
		bottom.add_child(UiStyle.dont_show_again(options, "show_liberations"))
	bottom.add_child(spacer)
	if rewards:
		bottom.add_child(_hand())
	_grow.call_deferred()


## Once laid out, the window grows by GROW (playtest round 13).
func _grow() -> void:
	_panel.custom_minimum_size = _panel.size * GROW


## Where a player tip points (PlayerTips): the window itself.
func anchor(name: String) -> Rect2:
	return _panel.get_global_rect() if name == "panel" else Rect2()


## A temple taken: its god, and what holding it gives.
func _temple(col: VBoxContainer, building: Dictionary) -> void:
	if building.has("god"):
		var g: Dictionary = state.data.gods["gods"][building["god"]]
		col.add_child(UiStyle.label("%s, god of %s" % [g["name"], g["domain"]], 18, Color("#f4ead2")))
	var l := UiStyle.label(state.data.buildings[building["type"]].get("taken_text", ""), 15, Color(0.75, 0.78, 0.82))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 380
	col.add_child(l)


## One conscript: class icon, then name over class and level.
func _conscript(u: Unit) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	var pic := TextureRect.new()
	pic.texture = UnitIcons.texture(u.unit_class, 44)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	row.add_child(pic)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 0)
	text.add_child(UiStyle.label(u.name, 16))
	text.add_child(UiStyle.label("%s, level %d" % [u.unit_class, u.level], 14, Color(0.75, 0.78, 0.82)))
	row.add_child(text)
	return row


## "View all cards": the hand as card faces (the Cards window, view-only) over this one.
## View all cards: a hand of cards with the count, at the bottom right (playtest round 13).
func _hand() -> Button:
	var view := UiStyle.button(str(state.cards.size()), 92)
	view.icon = UiStyle.svg("cards-fan", 34, UiStyle.ACCENT)
	view.custom_minimum_size.y = 50
	view.focus_mode = FOCUS_NONE
	view.tooltip_text = "View all cards (%d)" % state.cards.size()
	view.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	view.disabled = state.cards.is_empty()
	view.pressed.connect(func():
		var hand := CardsPanel.new()
		add_child(hand)
		hand.setup(state, false, true)
		hand.closed.connect(hand.queue_free))
	return view


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		if not _offering:  # a card choice needs an answer
			closed.emit()
		get_viewport().set_input_as_handled()
