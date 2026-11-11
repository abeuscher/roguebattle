class_name DebugPanel
extends Control
## The debug panel (SPEC §19.2, backtick): every tool, one tab per area. Squad tools
## act on the squad picked at the top; "at the cursor" means the hex under the mouse
## when the panel opened. The rules live in DebugTools; this only shows and passes on.
## A modal: 50% dark overlay. Not part of the real game.

signal closed
signal wide_roster
signal changed  # squads or resources changed: the battlemap refreshes tokens and HUD
signal regenerate(seed: int)
signal replay

const FAIRNESS := {"two_dice": "Two-dice hit roll", "ramping_crits": "Ramping crits",
		"streak_breaker": "Streak breaker", "spread": "Damage spread ±10%"}

var state: GameState
var view: MapView
var cursor := -1
var _squad := OptionButton.new()
var _status := UiStyle.label("", 15, UiStyle.ACCENT)
var _squads: Array[Squad] = []


func setup(game_state: GameState, map_view: MapView, cursor_hex: int) -> void:
	state = game_state
	view = map_view
	cursor = cursor_hex
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): closed.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size = Vector2(720, 0)
	panel.add_child(col)
	var head := HBoxContainer.new()
	var title := UiStyle.label("Debug", 26)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var where := state.map.hex_at(cursor) if cursor >= 0 else Vector2i(-1, -1)
	head.add_child(UiStyle.label("Not part of the real game  ·  cursor hex %s" % (str(Hex.to_offset(where)) if cursor >= 0 else "none"),
			14, Color(0.7, 0.72, 0.76)))
	col.add_child(head)
	col.add_child(_line([UiStyle.label("Squad", 16), _squad]))
	_squad.custom_minimum_size.x = 420
	_fill_squads()
	var tabs := TabContainer.new()
	tabs.custom_minimum_size.y = 300
	col.add_child(tabs)
	for t in [["Map", _map_tab()], ["Time", _time_tab()], ["Units", _units_tab()], ["Resources", _resources_tab()],
			["Battle", _battle_tab()], ["AI", _ai_tab()], ["Simulation", _sim_tab()]]:
		t[1].name = t[0]
		tabs.add_child(t[1])
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	col.add_child(_status)
	var close := UiStyle.button("Close (` or Esc)", 280)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)


# --- Tabs ---------------------------------------------------------------------------

func _map_tab() -> Control:
	var tab := _tab()
	tab.add_child(_check("Reveal all enemies and hidden sites", state.debug_reveal, func(on: bool):
		state.debug_reveal = on
		view.show_secrets = on))
	tab.add_child(_button("Teleport squad to cursor", func():
		var s := _picked()
		if s and cursor >= 0 and s in state.squads:
			DebugTools.teleport(state, s, cursor)
			_done("%s teleported." % s.name)
		else:
			_status.text = "Pick a squad on the map, and open the panel with the mouse over a hex."))
	var seed_box := _spin(0, 999999999, state.map.seed)
	tab.add_child(_line([UiStyle.label("Seed", 16), seed_box, _button("Regenerate", func(): regenerate.emit(int(seed_box.value)))]))
	var overlay := OptionButton.new()
	for m in MapOverlay.MODES:
		overlay.add_item(MapOverlay.NAMES[m])
	overlay.select(MapOverlay.MODES.find(view.overlay))
	overlay.item_selected.connect(func(i: int): view.overlay = MapOverlay.MODES[i])
	tab.add_child(_line([UiStyle.label("Overlay", 16), overlay]))
	tab.add_child(_check("Hex grid", view.show_grid, func(on: bool): view.show_grid = on))
	tab.add_child(_check("Sight radius of your squads", view.paths.show_sight, func(on: bool): view.paths.show_sight = on))
	return tab


func _time_tab() -> Control:
	var tab := _tab()
	var hour := _spin(0, 23, floori(state.clock.minute_of_day() / 60.0))
	tab.add_child(_line([UiStyle.label("Hour", 16), hour, _button("Set time of day", func():
		state.clock.set_minute(int(hour.value) * 60)
		_done("Now %s." % state.clock.time_text()))]))
	var hours := _spin(1, 240, 6)
	tab.add_child(_line([UiStyle.label("Hours", 16), hours, _button("Skip", func():
		var n := DebugTools.skip_hours(state, int(hours.value))
		_done("Ran %d minutes; now %s.%s" % [n, state.clock.time_text(), " Stopped early." if n < int(hours.value) * 60 else ""]))]))
	tab.add_child(_check("Freeze the clock (time of day stands still)", state.clock.frozen, func(on: bool): state.clock.frozen = on))
	return tab


func _units_tab() -> Control:
	var tab := _tab()
	var cls := OptionButton.new()
	var names: Array = state.data.units.keys()
	names.sort()
	for c in names:
		cls.add_item(c)
	var count := _spin(1, 9, 5)
	var spawn_level := _spin(1, 50, 1)
	var side := OptionButton.new()
	for s in ["player", "enemy", "neutral"]:
		side.add_item(s.capitalize())
	tab.add_child(_line([cls, UiStyle.label("Units", 16), count, UiStyle.label("Level", 16), spawn_level, side, _button("Spawn at cursor", func():
		if cursor < 0:
			_status.text = "Open the panel with the mouse over a hex."
			return
		var s := DebugTools.spawn(state, names[cls.selected], int(count.value), ["player", "enemy", "neutral"][side.selected], cursor)
		if s and int(spawn_level.value) > 1:
			DebugTools.set_level(state, s, int(spawn_level.value))
		_done("Spawned %s%s." % [s.name, " at level %d" % int(spawn_level.value) if int(spawn_level.value) > 1 else ""] if s else "No free army cell for another squad.")
		_fill_squads())]))
	var level := _spin(1, 50, 5)
	tab.add_child(_line([UiStyle.label("Picked squad: level", 16), level, _button("Set level", func():
		_on_squad(func(s: Squad): DebugTools.set_level(state, s, int(level.value))))]))
	var stat := OptionButton.new()
	for s in Unit.STATS:
		stat.add_item(s)
	var value := _spin(0, 200, 20)
	tab.add_child(_line([stat, value, _button("Set stat", func():
		_on_squad(func(s: Squad): DebugTools.set_stat(state, s, Unit.STATS[stat.selected], int(value.value))))]))
	var align := _spin(0, 100, 50)
	tab.add_child(_line([UiStyle.label("Alignment", 16), align, _button("Set alignment", func():
		_on_squad(func(s: Squad): DebugTools.set_alignment(state, s, int(align.value))))]))
	tab.add_child(_line([_button("Heal and revive all yours", func():
		DebugTools.heal_all(state)
		_done("Every unit of yours is at full HP.")), _button("Remove squad", func():
		_on_squad(func(s: Squad): DebugTools.remove(state, s))
		_fill_squads())]))
	tab.add_child(_button("Wide roster (16 squads)", func(): wide_roster.emit()))
	return tab


func _resources_tab() -> Control:
	var tab := _tab()
	var gold := _spin(1, 100000, 1000)
	tab.add_child(_line([UiStyle.label("Gold", 16), gold, _button("Add gold", func():
		state.gold += int(gold.value)
		state.log.add(state.clock.tick, "system", "Debug: +%d gold." % int(gold.value))
		_done("Gold: %d." % state.gold))]))
	var points := _spin(1, 100, 5)
	tab.add_child(_line([UiStyle.label("Tech points", 16), points, _button("Add tech points", func():
		state.tech_points += int(points.value)
		state.log.add(state.clock.tick, "system", "Debug: +%d tech points." % int(points.value))
		_done("Tech points: %d." % state.tech_points))]))
	var card := OptionButton.new()
	var ids: Array = state.data.cards["cards"].keys()
	for id in ids:
		card.add_item(state.card_name(id))
	tab.add_child(_line([card, _button("Add card", func():
		state.cards.append(ids[card.selected])
		state.log.add(state.clock.tick, "system", "Debug: card %s added." % state.card_name(ids[card.selected]))
		_done("%d cards in hand." % state.cards.size()))]))
	return tab


func _battle_tab() -> Control:
	var tab := _tab()
	var force := OptionButton.new()
	var kinds := ["", "win", "loss", "draw"]
	for k in ["Off: fight normally", "Win", "Loss", "Draw"]:
		force.add_item(k)
	force.select(kinds.find(state.debug_force))
	force.item_selected.connect(func(i: int): state.debug_force = kinds[i])
	tab.add_child(_line([UiStyle.label("Force every battle", 16), force]))
	tab.add_child(_button("Replay the last battle (same rolls)", func():
		if state.last_battle.has("battle"):
			replay.emit()
		else:
			_status.text = "No battle yet."))
	tab.add_child(_check("Show hidden numbers (log and battle view)", state.log.show_hidden, func(on: bool): state.log.show_hidden = on))
	tab.add_child(UiStyle.label("Fairness rules (§12.1)", 16))
	for k in FAIRNESS:
		tab.add_child(_check(FAIRNESS[k], state.debug_fairness[k], func(on: bool): state.debug_fairness[k] = on))
	return tab


func _ai_tab() -> Control:
	var tab := _tab()
	tab.add_child(_check("Show each enemy and neutral squad's role and target", view.paths.show_ai, func(on: bool): view.paths.show_ai = on))
	tab.add_child(_check("Freeze enemy and neutral AI", state.debug_freeze_ai, func(on: bool): state.debug_freeze_ai = on))
	return tab


func _sim_tab() -> Control:
	var tab := _tab()
	var a := OptionButton.new()
	var b := OptionButton.new()
	var all := _all_squads()
	for s in all:
		a.add_item(_squad_label(s))
		b.add_item(_squad_label(s))
	b.select(mini(1, all.size() - 1))
	var trials := _spin(10, 2000, 200)
	var report := UiStyle.label("", 15)
	report.autowrap_mode = TextServer.AUTOWRAP_WORD
	report.custom_minimum_size.x = 660
	tab.add_child(_line([UiStyle.label("A", 16), a]))
	tab.add_child(_line([UiStyle.label("B", 16), b]))
	tab.add_child(_line([UiStyle.label("Battles", 16), trials, _button("Run", func():
		if all.is_empty():
			return
		var sa: Squad = all[a.selected]
		var sb: Squad = all[b.selected]
		var r := BattleSim.run(state.data, DebugTools.build_of(sa), DebugTools.build_of(sb), int(trials.value), state.clock.tick)
		report.text = BattleSim.report(sa.name, sb.name, r) + "\n(Freshly rolled units of the same classes and rows, not these exact units.)")]))
	tab.add_child(report)
	return tab


# --- Helpers ------------------------------------------------------------------------

## Squads on the map, then your squads at base.
func _all_squads() -> Array[Squad]:
	var out: Array[Squad] = state.squads.duplicate()
	for s in state.army.squads():
		if s not in out:
			out.append(s)
	return out


func _fill_squads() -> void:
	_squads = _all_squads()
	_squad.clear()
	for s in _squads:
		_squad.add_item(_squad_label(s))


func _squad_label(s: Squad) -> String:
	return "#%d %s  ·  %s%s" % [s.id, s.name, s.side, "" if s in state.squads else " (at base)"]


func _picked() -> Squad:
	return _squads[_squad.selected] if _squad.selected >= 0 and _squad.selected < _squads.size() else null


func _on_squad(action: Callable) -> void:
	var s := _picked()
	if s == null:
		_status.text = "No squad picked."
		return
	action.call(s)
	_done("Done: %s." % s.name)


func _done(text: String) -> void:
	_status.text = text
	changed.emit()


func _tab() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 8)
	return v


func _line(controls: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	for c in controls:
		h.add_child(c)
	return h


func _button(text: String, action: Callable) -> Button:
	var b := Button.new()
	b.text = text
	b.pressed.connect(action)
	return b


func _check(text: String, on: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.toggled.connect(action)
	return c


func _spin(lo: int, hi: int, value: int) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.update_on_text_changed = true  # a typed number counts without pressing Enter
	s.custom_minimum_size.x = 110
	return s


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_QUOTELEFT, KEY_ESCAPE]:
		closed.emit()
		get_viewport().set_input_as_handled()
