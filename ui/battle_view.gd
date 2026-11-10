class_name BattleView
extends Control
## The battle screen (SPEC §4 Battle and Battle result, §11.3). The two squads face off,
## back rows outside, and each action plays out in turn order with a running log.
## Pause, speed, tactic, cards, retreat and skip; at the end a result panel with the outcome
## and, when a beaten enemy is shaken, the offer to drive it off (§11.6).
## A modal: 50% dark overlay; the battlemap holds the clock while it's open.

signal finished(text: String)

const FIELD := Vector2(1400, 600)
const CARD := Vector2(200, 104)
const GAP := 10.0
const HEX := 34.0  # the backdrop's hex size
const PANEL_MARGIN := 16
const PLAY_SIZE := 52.0  # the round Play/Pause button
const CONTROLS_H := 44.0  # the button row's height, reserved while it's hidden
const EDGE := 40.0  # back rows' distance from the field's sides
const ROW_GAP := 34.0  # between a squad's back and front rows
const SIDE_COLORS := [Color("#3b6fd6"), Color("#c8402f")]
const LOG_COLORS := ["#a8c4ff", "#ffaa9a"]
const RESULT_WORDS := {"won": "Won", "lost": "Lost", "retreated": "Retreated", "even": "Draw"}
const RESULT_COLORS := {"won": Color("#7ee08a"), "lost": Color("#ff7a66"), "retreated": Color("#e0b03a"), "even": Color("#e8e0c8")}
const TACTIC_TIPS := {"best": "Each unit hits the target it hurts most", "strong": "Focus the strongest enemy",
		"weak": "Focus the weakest enemy", "leader": "Focus the enemy leader"}

var state: GameState
var battle: Battle
var replay := false  # the debug panel's replay (§19.2): copies of the squads, nothing on the map changes
var _waiting := false  # both squads shown; nothing happens until Fight (an option, on by default)
var _play_btn: Button  # Fight, Pause or Play, at the field's bottom left
var _action := UiStyle.label("", 16)  # the latest action, on the field while the log is hidden
var _panel: PanelContainer  # the whole battle, hidden when the result shows
var _below := VBoxContainer.new()  # log and controls: shown only while paused or waiting
var _view: Dictionary  # data.battle["view"]: pacing
var _ground := Panel.new()
var _field := Control.new()  # cards and floating numbers, placed by hand
var _cards := {}  # Unit -> Card
var _shown := 0  # events played so far
var _wait := 0.0
var _speed := 0
var _paused := false
var _ended := false  # the battle has no turns left
var _done := false  # the result is showing
var _retreat_asked := false
var _cards_btn: Button
var _on_enemy_base := false  # the enemy squad stood on its base when the battle began (a push can move it off)
var _picker: Control  # the hand, shown large; the battle holds while it's open
var _items_btn: Button
var _round := UiStyle.label("", 28, UiStyle.ACCENT)
var _ticker := RichTextLabel.new()
var _controls := HBoxContainer.new()
var _speed_btn: Button
var _retreat_btn: Button
var _tactic := OptionButton.new()


func setup(game_state: GameState, b: Battle, is_replay := false, wait_for_fight := false) -> void:
	state = game_state
	battle = b
	replay = is_replay
	_waiting = wait_for_fight
	_on_enemy_base = b.sides[1].hex == state.map.enemy_base
	_view = state.data.battle["view"]
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	_panel = PanelContainer.new()
	# The panel draws its own background (_draw_panel): all of it while paused, only an
	# even frame around the field while the battle plays, so the space below is see-through.
	var margin := StyleBoxEmpty.new()
	margin.set_content_margin_all(PANEL_MARGIN)
	_panel.add_theme_stylebox_override("panel", margin)
	_panel.draw.connect(_draw_panel)
	center.add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	_panel.add_child(col)
	_ground.custom_minimum_size = FIELD
	_ground.add_theme_stylebox_override("panel", UiStyle.box(Color(battle.terrain["color"]).darkened(0.72), 0))
	_ground.clip_contents = true
	col.add_child(_ground)
	_ground.add_child(_backdrop())
	_ground.add_child(_field)
	_add_tags()
	_round.position = Vector2(FIELD.x / 2.0 - 70, 16)
	_round.custom_minimum_size.x = 140
	_round.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_field.add_child(_round)
	for side in 2:
		for u in battle.sides[side].units:
			_add_card(u, side)
	_layout(false)
	_add_play_button()
	# The log and controls keep their space while hidden, so nothing jumps when they show.
	var below := Control.new()
	col.add_child(below)
	_below.add_theme_constant_override("separation", 10)
	_below.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	below.add_child(_below)
	_ticker.custom_minimum_size = Vector2(FIELD.x, 150)
	_ticker.bbcode_enabled = true
	_ticker.scroll_following = true
	_ticker.add_theme_font_size_override("normal_font_size", 15)
	_below.add_child(_ticker)
	_below.add_child(_controls)
	_build_controls()
	below.custom_minimum_size = Vector2(FIELD.x, _ticker.custom_minimum_size.y + 10 + CONTROLS_H)
	_show_chrome()


## Play or Pause (or Fight, before the battle starts) at the field's bottom left, and
## next to it the latest action, outlined so it reads against the ground.
func _add_play_button() -> void:
	_play_btn = UiStyle.button("", 150, true)
	# No keyboard focus: Space is handled once, in _unhandled_key_input. A focused button
	# would also take Space as a press, so the battle paused and played again at once.
	_play_btn.focus_mode = FOCUS_NONE
	_play_btn.pressed.connect(func():
		if _waiting:
			_start()
		else:
			_toggle_pause())
	_ground.add_child(_play_btn)
	_action.position = Vector2(14 + PLAY_SIZE + 16, FIELD.y - 14 - PLAY_SIZE / 2.0 - 12)
	_action.custom_minimum_size.x = FIELD.x - _action.position.x - 20
	_action.clip_text = true
	_action.add_theme_color_override("font_outline_color", Color(0, 0, 0, 0.85))
	_action.add_theme_constant_override("outline_size", 5)
	_action.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.6))
	_action.add_theme_constant_override("shadow_offset_y", 2)
	_ground.add_child(_action)


## While the battle plays, only the field shows (with the latest action on it); paused
## or waiting to start, the log and controls show under it.
func _show_chrome() -> void:
	var still := _paused or _waiting
	if _waiting:
		_play_btn.text = "Fight (Space)"
		_play_btn.position = Vector2(14, FIELD.y - 58)
	else:
		_round_play_button()
		_play_btn.icon = UiStyle.icon("play" if _paused else "pause", 22)
		_play_btn.tooltip_text = "Play (Space)" if _paused else "Pause (Space)"
	_below.visible = still
	_action.visible = not still
	_panel.queue_redraw()


## The panel's background: the whole panel while paused or waiting; while the battle
## plays, only the field with an even border on all four sides.
func _draw_panel() -> void:
	var r := Rect2(Vector2.ZERO, _panel.size)
	if not (_paused or _waiting):
		r.size.y = FIELD.y + PANEL_MARGIN * 2
	UiStyle.box(UiStyle.PANEL, 0).draw(_panel.get_canvas_item(), r)


## Once the battle starts, Play/Pause is an icon on a small round button.
func _round_play_button() -> void:
	if _play_btn.text == "":
		return
	_play_btn.text = ""
	_play_btn.custom_minimum_size = Vector2(PLAY_SIZE, PLAY_SIZE)
	_play_btn.size = _play_btn.custom_minimum_size
	_play_btn.position = Vector2(14, FIELD.y - 14 - PLAY_SIZE)
	_play_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	for st in ["normal", "hover", "pressed", "disabled"]:
		var box := (_play_btn.get_theme_stylebox(st) as StyleBoxFlat).duplicate() as StyleBoxFlat
		box.set_corner_radius_all(int(PLAY_SIZE / 2.0))
		box.set_content_margin_all(0)
		_play_btn.add_theme_stylebox_override(st, box)


## The field's ground: hexes of the battle's terrain, dimmed so the cards stand out.
func _backdrop() -> Control:
	var tile: Texture2D = ImageTexture.create_from_image(TerrainTiles.draw_tile(battle.terrain["key"], Color(battle.terrain["color"]), HEX))
	var back := Control.new()
	back.custom_minimum_size = FIELD
	back.draw.connect(func():
		var step := Vector2(HEX * Hex.SQRT3, HEX * 1.5)
		for row in ceili(FIELD.y / step.y) + 1:
			for col in ceili(FIELD.x / step.x) + 1:
				var at := Vector2(col * step.x + (step.x / 2.0 if row % 2 else 0.0), row * step.y)
				back.draw_texture(tile, at - Vector2(tile.get_size()) / 2.0)
		back.draw_rect(Rect2(Vector2.ZERO, FIELD), Color(0, 0, 0, 0.35)))
	return back


## Each party's name on a small dark tag over its own cards, and in the middle of the
## field a "vs." box with the ground, the time of day and who attacks, stacked.
func _add_tags() -> void:
	var side_w := EDGE * 2 + CARD.x * 2 + ROW_GAP
	for side in 2:
		var tag := _tag([[battle.sides[side].name, 22, Color(LOG_COLORS[side])]])
		tag.position = Vector2(EDGE + (side_w - EDGE * 2 - tag.size.x) / 2.0, 14)
		if side == 1:
			tag.position.x = FIELD.x - tag.position.x - tag.size.x
		_field.add_child(tag)
	var lines := [["vs.", 26, UiStyle.ACCENT]]
	if replay:
		lines.append(["Replay", 15, Color(0.8, 0.82, 0.86)])
	lines.append([battle.terrain["name"], 15, Color(0.8, 0.82, 0.86)])
	lines.append(["Day" if battle.daytime else "Night", 15, Color(0.8, 0.82, 0.86)])
	lines.append(["Ranged attack" if battle.ranged_only else "%s attacks" % battle.sides[battle.attacker].name, 15, Color(0.8, 0.82, 0.86)])
	var mid := _tag(lines)
	mid.position = (FIELD - mid.size) / 2.0 + Vector2(0, 20)
	_field.add_child(mid)


## A small 50%-black box of centered lines, sized to fit them.
func _tag(lines: Array) -> PanelContainer:
	var tag := PanelContainer.new()
	tag.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.5), 8))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 0)
	tag.add_child(col)
	for l in lines:
		var label := UiStyle.label(l[0], l[1], l[2])
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(label)
	tag.size = tag.get_combined_minimum_size()
	return tag


func _build_controls() -> void:
	_controls.add_theme_constant_override("separation", 12)
	_speed_btn = UiStyle.button("", 130)
	_speed_btn.pressed.connect(func():
		_speed = (_speed + 1) % _view["speeds"].size()
		_update_speed())
	_controls.add_child(_speed_btn)
	_update_speed()
	_controls.add_child(UiStyle.label("Tactic", 18))
	for t in Battle.TACTICS:
		_tactic.add_item(t.capitalize())
		_tactic.set_item_tooltip(_tactic.item_count - 1, TACTIC_TIPS[t])
	_tactic.select(Battle.TACTICS.find(battle.tactics[0]))
	_tactic.custom_minimum_size = Vector2(140, 44)
	_tactic.item_selected.connect(func(i: int): battle.tactics[0] = Battle.TACTICS[i])
	_controls.add_child(_tactic)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	_controls.add_child(spacer)
	_retreat_btn = UiStyle.button("", 200)
	_retreat_btn.pressed.connect(func():
		_retreat_asked = true
		_retreat_btn.disabled = true
		_retreat_btn.text = "Retreating...")
	_controls.add_child(_retreat_btn)
	_update_retreat()
	_cards_btn = UiStyle.button("", 160)
	_cards_btn.pressed.connect(_choose_card)
	_controls.add_child(_cards_btn)
	_update_cards()
	_items_btn = UiStyle.button("", 140)
	_items_btn.pressed.connect(_choose_item)
	_controls.add_child(_items_btn)
	_update_items()
	var skip := UiStyle.button("Skip to end", 170)
	skip.pressed.connect(_skip)
	_controls.add_child(skip)
	_no_focus(_controls)
	if replay:
		_retreat_btn.disabled = true
		_cards_btn.disabled = true
		_items_btn.disabled = true


## Battle-view buttons never take keyboard focus: Space is handled once, in
## _unhandled_key_input. A focused button would take Space as a press too (Cards
## pressed again opened a second, unclosable card picker).
func _no_focus(node: Node) -> void:
	if node is Control:
		(node as Control).focus_mode = FOCUS_NONE
	for c in node.get_children():
		_no_focus(c)


func _update_speed() -> void:
	var v := float(_view["speeds"][_speed])
	_speed_btn.text = "Speed ×%s" % (str(int(v)) if v == int(v) else str(v))


func _update_retreat() -> void:
	_retreat_btn.text = "Retreat (%d%%)" % roundi(battle.retreat_chance(0) * 100)
	_retreat_btn.disabled = battle.ranged_only
	_retreat_btn.tooltip_text = "No retreat from a ranged attack" if battle.ranged_only \
			else "On success the squad steps back 1 hex and each unit loses 1 charisma. On failure it loses its next action."


## The battle cards in the hand, counted (§13).
func _battle_cards() -> Dictionary:
	var out := {}
	for id in state.cards:
		if state.data.cards["cards"][id]["where"] == "battle":
			out[id] = out.get(id, 0) + 1
	return out


func _update_cards() -> void:
	var n := 0
	for id in _battle_cards():
		n += _battle_cards()[id]
	_cards_btn.text = "Cards (%d)" % n
	_cards_btn.disabled = n == 0
	_cards_btn.tooltip_text = "No battle cards in hand." if n == 0 else "Play a card before the next action."


## The hand, large in the middle of the screen. The battle holds while it's open, so
## there's time to choose (user's playtest notes, 2026-11-09). Playing a card closes it.
func _choose_card() -> void:
	if _picker:
		return
	_picker = Control.new()
	_picker.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_picker)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_picker.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_picker.add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	center.add_child(col)
	var title := UiStyle.label("Play a card  ·  the battle waits", 26)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 16)
	row.add_theme_constant_override("v_separation", 16)
	row.alignment = FlowContainer.ALIGNMENT_CENTER
	row.custom_minimum_size.x = minf(1250.0, (CardFace.SIZE.x + 16) * _battle_cards().size())
	col.add_child(row)
	for id in _battle_cards():
		row.add_child(_card_tile(id, int(_battle_cards()[id])))
	var close := UiStyle.button("Close (Esc)", 200)
	close.pressed.connect(_close_picker)
	_no_focus.call_deferred(_picker)
	close.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(close)


## One card face (CardFace) with a Play button.
func _card_tile(id: String, count: int) -> Control:
	var play := UiStyle.button("Play", 188, true)
	play.pressed.connect(func():
		_close_picker()
		_now(func(): return state.play_battle_card(battle, id))
		_update_cards())
	return CardFace.make(state.data, id, count, play)


func _close_picker() -> void:
	if _picker:
		_picker.queue_free()
		_picker = null
	_update_cards()


## Cure potions (§15.1) that would help one of your units right now.
func _update_items() -> void:
	var uses := state.battle_supply_uses(battle)
	_items_btn.text = "Items (%d)" % uses.size()
	_items_btn.disabled = replay or uses.is_empty()
	_items_btn.tooltip_text = "Cure potions for a status one of your units has." if not uses.is_empty() \
			else "No cure potion fits a status your units have."


func _choose_item() -> void:
	var menu := PopupMenu.new()
	menu.add_theme_font_size_override("font_size", 18)
	var uses := state.battle_supply_uses(battle)
	for i in uses.size():
		var item: Dictionary = state.data.items["consumables"][uses[i][0]]
		menu.add_item("%s on %s (%s)  ·  you have %d" % [item["name"], uses[i][1].name, item["cures"],
				int(state.army.supplies.get(uses[i][0], 0))], i)
	menu.id_pressed.connect(func(i: int):
		_now(func(): return state.use_battle_supply(battle, uses[i][0], uses[i][1]))
		_update_items())
	menu.popup_hide.connect(menu.queue_free)
	add_child(menu)
	menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()) - Vector2i(0, 40 * uses.size() + 20), Vector2i.ZERO))


## Plays a card or a cure potion at once (user's playtest notes, 2026-11-10): `act`
## changes the battle and records its events; they move ahead of whatever of the current
## action is still to be shown, and show now, so the card comes before any more attacks.
func _now(act: Callable) -> void:
	var from := battle.events.size()
	if not act.call():
		return
	var fresh := battle.events.slice(from)
	battle.events.resize(from)
	for k in fresh.size():
		battle.events.insert(_shown + k, fresh[k])
	for k in fresh.size():
		_wait = maxf(_wait, _play(battle.events[_shown], true))
		_shown += 1


## Once every event so far has shown, each card's HP matches its unit's: an action's
## events computed before a card was played can otherwise leave the shown HP off.
func _sync_hp() -> void:
	for u in _cards:
		if is_instance_valid(_cards[u]) and _cards[u].hp != u.hp:
			_cards[u].hp = u.hp


## Fight pressed: the battle starts playing.
func _start() -> void:
	_waiting = false
	_show_chrome()


## Pauses a playing battle (the game window lost focus); does nothing otherwise.
func pause() -> void:
	if not _paused and not _waiting and not _done:
		_toggle_pause()


func _toggle_pause() -> void:
	_paused = not _paused
	_show_chrome()


# --- Playing the battle ---------------------------------------------------------------

func _process(delta: float) -> void:
	if battle == null or _done or _paused or _waiting or _picker:
		return
	_wait -= delta * float(_view["speeds"][_speed])
	if _wait > 0.0:
		return
	if _shown == battle.events.size():
		_sync_hp()
	if _shown < battle.events.size():
		_wait = _play(battle.events[_shown], true)
		_shown += 1
		if battle.events[_shown - 1]["type"] == "status":
			_update_items()
	elif _ended or battle.is_over():
		_finish()
	elif _retreat_asked:
		_retreat_asked = false
		battle.retreat(0)
		_update_retreat()
	else:
		_ended = not battle.step()


func _skip() -> void:
	_start()
	battle.run()
	while _shown < battle.events.size():
		_play(battle.events[_shown], false)
		_shown += 1
	_finish()


## Shows one event; returns how long to wait before the next (at speed ×1).
func _play(e: Dictionary, animate: bool) -> float:
	_log(e)
	var beat := float(_view["beat"])
	match e["type"]:
		"round":
			_round.text = "Round %d" % e["round"]
			return float(_view["round_pause"])
		"attack":
			var card: Card = _cards[e["target"]]
			if animate:
				_lunge(_cards[e["unit"]], card)
			if not e["hit"]:
				_float(card, "miss", Color(0.8, 0.8, 0.8), animate)
				return beat
			card.hp = maxi(0, card.hp - int(e["damage"]))
			_float(card, "-%d%s" % [e["damage"], "!" if e["crit"] else ""], Color("#ffd24a") if e["crit"] else Color("#ff6b5a"), animate, 30 if e["crit"] else 24)
			if animate:
				card.flash(Color(1, 0.2, 0.15))
			return beat
		"heal":
			var card: Card = _cards[e["target"]]
			card.hp += int(e["amount"])  # cards can heal above full for the battle
			_float(card, "+%d" % e["amount"], Color("#7ee08a"), animate)
			if animate:
				card.flash(Color(0.3, 1, 0.4))
		"status":
			var card: Card = _cards[e["unit"]]
			card.hp = clampi(card.hp + int(e.get("amount", 0)), 0, card.max_hp)
			card.statuses = battle.statuses_of(e["unit"])
			var word: String = "resisted" if e.get("resisted", false) else str(e["status"]).replace("_up", " up").replace("_", " ")
			_float(card, word, Color("#d7a6ff"), animate, 18)
		"move":
			_layout(animate)
		"raise":
			_add_card(e["target"], battle.side_of(e["target"]))
			_layout(animate)
		"card":
			var c: Dictionary = state.data.cards["cards"][e["card"]]
			var l := UiStyle.label(c["name"], 40, UiStyle.ACCENT)
			l.add_theme_color_override("font_outline_color", Color.BLACK)
			l.add_theme_constant_override("outline_size", 8)
			l.position = Vector2(FIELD.x / 2.0 - 80, FIELD.y / 2.0 - 60)
			_field.add_child(l)
			if animate:
				var t := l.create_tween()
				t.tween_property(l, "modulate:a", 0.0, beat * 2.0 / _speed_now()).set_delay(beat * 0.6 / _speed_now())
				t.tween_callback(l.queue_free)
			else:
				l.queue_free()
			return beat * 1.2
		"card_hit":
			var card: Card = _cards[e["target"]]
			card.hp = maxi(0, card.hp - int(e["damage"]))
			_float(card, "-%d" % e["damage"], Color("#ff6b5a"), animate)
			if animate:
				card.flash(Color(1, 0.2, 0.15))
			return beat * 0.5
		"wait":
			return beat * 0.6
	return beat * 0.8


func _log(e: Dictionary) -> void:
	var line := battle.log_line(e)
	if state.log.show_hidden and not e.get("hidden", {}).is_empty():
		line += "  " + JSON.stringify(e["hidden"])
	_action.text = line
	line = line.replace("[", "[lb]")
	if e["type"] == "round":
		_ticker.append_text("[color=#ffe08a]%s[/color]\n" % line)
	else:
		_ticker.append_text("[color=%s]%s[/color]\n" % [LOG_COLORS[maxi(0, e["side"])], line])


func _add_card(u: Unit, side: int) -> void:
	var c := Card.new()
	c.unit = u
	c.color = SIDE_COLORS[side]
	c.leader = u == battle.sides[side].leader
	c.hp = u.hp
	c.max_hp = u.max_hp(state.data)
	var kind := battle.attack_kind(u)
	c.title = u.unit_class
	c.subtitle = "" if u.name == u.unit_class else u.name
	c.attack = "%s ×%d" % [kind, battle.attack_count(u)]
	c.size = CARD
	_field.add_child(c)
	_cards[u] = c


## Places every card: each squad's back row at the outside, front rows facing each other;
## a row's units stack top to bottom by position.
func _layout(animate: bool) -> void:
	for side in 2:
		for r in ["front", "back"]:
			var units := battle.sides[side].row(r)
			units.sort_custom(func(a: Unit, b: Unit): return a.col < b.col)
			var inner: bool = r == "front"
			var x := EDGE + (CARD.x + ROW_GAP if inner else 0.0)
			if side == 1:
				x = FIELD.x - x - CARD.x
			var top := (FIELD.y - units.size() * (CARD.y + GAP) + GAP) / 2.0 + 20.0
			for i in units.size():
				var c: Card = _cards[units[i]]
				var at := Vector2(x, top + i * (CARD.y + GAP))
				c.home = at
				if animate:
					create_tween().tween_property(c, "position", at, 0.3 / _speed_now())
				else:
					c.position = at


func _speed_now() -> float:
	return float(_view["speeds"][_speed])


func _lunge(c: Card, target: Card) -> void:
	var step := 40.0 * signf(target.home.x - c.home.x)
	var t := c.create_tween()
	var d := float(_view["beat"]) * 0.3 / _speed_now()
	t.tween_property(c, "position:x", c.home.x + step, d).set_ease(Tween.EASE_OUT)
	t.tween_property(c, "position:x", c.home.x, d).set_ease(Tween.EASE_IN)


## A number or word that rises from a card and fades.
func _float(c: Card, text: String, color: Color, animate: bool, font_size := 24) -> void:
	if not animate:
		return
	var l := UiStyle.label(text, font_size, color)
	l.add_theme_color_override("font_outline_color", Color.BLACK)
	l.add_theme_constant_override("outline_size", 6)
	l.position = c.home + Vector2(CARD.x / 2.0 - 16, 24)
	_field.add_child(l)
	var d := float(_view["beat"]) * 1.4 / _speed_now()
	var t := l.create_tween().set_parallel()
	t.tween_property(l, "position:y", l.position.y - 44, d)
	t.tween_property(l, "modulate:a", 0.0, d).set_delay(d * 0.4)
	t.chain().tween_callback(l.queue_free)


# --- The result ---------------------------------------------------------------------

## The battle field goes away and the result shows on its own (user's playtest notes,
## 2026-11-09): Won or Lost once at the top, then your squad and the enemy side by side
## (HP lost, units lost), XP, the offer to drive the enemy off, and Continue.
func _finish() -> void:
	_done = true
	var out := battle.finish() if replay else state.resolve_pending()
	var player := battle.sides[0]
	var enemy := battle.sides[1]
	var result := GameState.battle_result(out)
	_panel.hide()
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var box := PanelContainer.new()
	var style := UiStyle.box(UiStyle.PANEL, 28)
	style.set_border_width_all(2)
	style.border_color = UiStyle.OUTLINE
	box.add_theme_stylebox_override("panel", style)
	center.add_child(box)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 16)
	col.custom_minimum_size.x = 620
	box.add_child(col)
	var title := UiStyle.label(RESULT_WORDS[result], 40, RESULT_COLORS[result])
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var line := GameState.neutral_line(battle, out)
	if replay:
		line = ("Replay. " + line).strip_edges()
	if line != "":
		var l := UiStyle.label(line, 17, Color(0.8, 0.82, 0.86))
		l.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(l)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 24)
	col.add_child(sides)
	for side in 2:
		sides.add_child(_side_stats(side, out))
	if not out.get("xp", {}).is_empty():
		var amounts: Array = out["xp"].values()
		col.add_child(UiStyle.label("XP: +%d each" % amounts[0] if amounts.min() == amounts.max() else "XP: +%d to +%d" % [amounts.min(), amounts.max()], 17))
	for level_up in out.get("level_ups", []):
		col.add_child(UiStyle.label(level_up, 17, Color("#7ee08a")))
	var note := UiStyle.label("", 17, UiStyle.ACCENT)
	note.visible = false
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	var chance := state.drive_off_chance(player, enemy)
	var can_drive: bool = chance > 0.0 and not out["wiped"][1] and out["retreated"] < 0 and out["hp_lost"][1] > out["hp_lost"][0] and enemy in state.squads
	for hint in _hints(out, can_drive):
		var h := UiStyle.label(hint, 16, Color(0.8, 0.82, 0.86))
		h.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		col.add_child(h)
	if can_drive:
		var drive := UiStyle.button("Demand they flee (%d%%)" % roundi(chance * 100), 280)
		drive.tooltip_text = "On success the enemy squad leaves the map for good, with no XP."
		drive.pressed.connect(func():
			drive.disabled = true
			note.visible = true
			note.text = "The enemy flees the map." if state.drive_off(player, enemy) else "The enemy refuses to flee.")
		buttons.add_child(drive)
	col.add_child(note)
	var go := UiStyle.button("Continue", 200, true)
	go.pressed.connect(func(): finished.emit(out.get("text", "Replay finished.")))
	buttons.add_child(go)
	col.add_child(buttons)
	go.grab_focus.call_deferred()


## What the player can do next with a beaten enemy (user's decision, 2026-11-10): when
## "Demand they flee" is on offer and what it does; that it will be once the enemy's
## spirit breaks; and, on the Enemy Base, that its fallen come back only slowly.
func _hints(out: Dictionary, can_drive: bool) -> Array[String]:
	var enemy := battle.sides[1]
	var player := battle.sides[0]
	var out_hints: Array[String] = []
	if replay or enemy.side == "neutral" or out["wiped"][1] or enemy not in state.squads:
		return out_hints
	var warlord := " It's also a way to beat the Warlord without wiping out his whole squad." if enemy.role == "leader" else ""
	if can_drive:
		out_hints.append("Their spirit is broken. Your leader can demand they flee: if they agree, they leave the map for good (no XP for it). The chance is your leader's charisma." + warlord)
	elif GameState.battle_result(out) == "won" and player.leader and player.leader.is_alive():
		out_hints.append("Their spirit holds for now. Keep beating them and it will break; then your leader can demand they flee." + warlord)
	if _on_enemy_base and enemy.living().size() < enemy.units.size():
		out_hints.append("On their base, the enemy's fallen come back only one at a time, one every %s, and the living don't heal. Strike again soon." 				% GameState.duration_text(int(state.data.enemy["base_revive_ticks"])))
	return out_hints


## One side's column: its name (the other side is always "Enemy"), HP lost, units lost.
func _side_stats(side: int, out: Dictionary) -> Control:
	var s := battle.sides[side]
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, 0.25), 14))
	box.size_flags_horizontal = SIZE_EXPAND_FILL
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 6)
	box.add_child(col)
	col.add_child(UiStyle.label(s.name if side == 0 else "Enemy", 20, Color(LOG_COLORS[side])))
	col.add_child(UiStyle.label("HP lost: %d%%" % roundi(out["hp_lost"][side] * 100), 17))
	col.add_child(UiStyle.label("Units lost: %d" % s.living(false).size(), 17))
	if out["leader_dead"][side] and not out["wiped"][side] and side == 0:
		col.add_child(UiStyle.label("Leader fell: marching home", 15, Color(0.8, 0.82, 0.86)))
	return box


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var key := (event as InputEventKey).keycode
	if _picker:
		if key == KEY_ESCAPE:
			_close_picker()
	elif key == KEY_SPACE and _waiting:
		_start()
	elif key == KEY_SPACE and not _done:
		_toggle_pause()
	get_viewport().set_input_as_handled()


## One unit on the field: class, name, attack, HP bar and statuses.
class Card extends Control:
	var unit: Unit
	var color := Color.WHITE
	var leader := false
	var title := ""
	var subtitle := ""
	var attack := ""
	var home := Vector2.ZERO
	var max_hp := 1
	var hp := 0:
		set(v):
			hp = v
			queue_redraw()
	var statuses: Array = []:
		set(v):
			statuses = v
			queue_redraw()
	var _flash := Color(0, 0, 0, 0)

	func flash(c: Color) -> void:
		_flash = c
		var t := create_tween()
		t.tween_method(func(a: float):
			_flash.a = a
			queue_redraw(), 0.7, 0.0, 0.35)

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var dead := hp <= 0
		var r := Rect2(Vector2.ZERO, size)
		draw_rect(r, Color(0.13, 0.15, 0.19) if not dead else Color(0.1, 0.1, 0.11))
		draw_rect(Rect2(0, 0, 6, size.y), color if not dead else color.darkened(0.6))
		draw_rect(r, Color(1, 0.88, 0.5) if leader and not dead else Color(0.35, 0.38, 0.44), false, 2.0)
		var ink := Color.WHITE if not dead else Color(0.45, 0.45, 0.48)
		draw_string(font, Vector2(16, 24), title, HORIZONTAL_ALIGNMENT_LEFT, size.x - 70, 17, ink)
		if leader:
			draw_string(font, Vector2(size.x - 62, 22), "Leader", HORIZONTAL_ALIGNMENT_RIGHT, 52, 12, Color(1, 0.88, 0.5))
		draw_string(font, Vector2(16, 42), subtitle, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13, ink.darkened(0.3))
		var line3 := ", ".join(statuses) if not statuses.is_empty() else attack
		draw_string(font, Vector2(16, 60), line3, HORIZONTAL_ALIGNMENT_LEFT, size.x - 24, 13,
				Color("#d7a6ff") if not statuses.is_empty() else ink.darkened(0.2))
		var bar := Rect2(16, 70, size.x - 32, 14)
		draw_rect(bar, Color(0.05, 0.05, 0.06))
		var share := minf(1.0, float(hp) / max_hp)
		var fill := Color("#5fbf5a") if share > 0.5 else (Color("#e0b03a") if share > 0.25 else Color("#d9533f"))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * share, bar.size.y)), fill)
		draw_string(font, Vector2(16, 98), "Fallen" if dead else "%d / %d HP" % [hp, max_hp], HORIZONTAL_ALIGNMENT_LEFT, -1, 13, ink)
		if _flash.a > 0.0:
			draw_rect(r, _flash)
