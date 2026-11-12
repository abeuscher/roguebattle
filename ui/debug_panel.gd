class_name DebugPanel
extends Control
## The debug panel (SPEC §19.2, backtick): every tool, one tab per area, each tab in
## labelled sections. "At the cursor" means the hex under the mouse when the panel
## opened. The rules live in DebugTools; this only shows and passes on. A modal: 50%
## dark overlay. Not part of the real game.

signal closed
signal wide_roster
signal changed  # squads or resources changed: the battlemap refreshes tokens and HUD
signal regenerate(seed: int)
signal replay

const FAIRNESS := {"two_dice": "Two-dice hit roll", "ramping_crits": "Ramping crits",
		"streak_breaker": "Streak breaker", "spread": "Damage spread ±10%"}
const SIZE := Vector2(980, 660)
const LABEL_WIDTH := 150
const MAX_LEVEL := 50
const MUTED := Color(0.62, 0.65, 0.7)
const SECTION := Color(0.135, 0.15, 0.185)
const FIELD := Color(0.07, 0.08, 0.1)
const SIDES := ["player", "enemy", "neutral"]

## The squad being built; kept between openings so it can be placed again.
static var _draft: Squad

var state: GameState
var view: MapView
var cursor := -1
var _squad := OptionButton.new()
var _status := UiStyle.label("", 15, UiStyle.ACCENT)
var _squads: Array[Squad] = []
var _draft_box := VBoxContainer.new()
var _picked_unit: Unit


func setup(game_state: GameState, map_view: MapView, cursor_hex: int) -> void:
	state = game_state
	view = map_view
	cursor = cursor_hex
	if _draft == null:
		_draft = DebugTools.draft(state)
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
	var frame := UiStyle.box(UiStyle.PANEL, 22)
	frame.set_border_width_all(1)
	frame.border_color = UiStyle.OUTLINE.darkened(0.3)
	panel.add_theme_stylebox_override("panel", frame)
	panel.custom_minimum_size = SIZE
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(_header())
	var tabs := TabContainer.new()
	tabs.size_flags_vertical = SIZE_EXPAND_FILL
	_style_tabs(tabs)
	col.add_child(tabs)
	for t in [["Map", _map_tab()], ["Time", _time_tab()], ["Units", _units_tab()], ["Resources", _resources_tab()],
			["Battle", _battle_tab()], ["AI", _ai_tab()], ["Simulation", _sim_tab()]]:
		var scroll := ScrollContainer.new()
		scroll.name = t[0]
		scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
		var pad := MarginContainer.new()
		pad.size_flags_horizontal = SIZE_EXPAND_FILL
		for side in ["left", "right", "top", "bottom"]:
			pad.add_theme_constant_override("margin_" + side, 14)
		pad.add_child(t[1])
		scroll.add_child(pad)
		tabs.add_child(scroll)
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD
	_status.custom_minimum_size.y = 22
	col.add_child(_status)


func _header() -> Control:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 14)
	var title := UiStyle.label("Debug", 26)
	head.add_child(title)
	var where := Hex.to_offset(state.map.hex_at(cursor)) if cursor >= 0 else Vector2i(-1, -1)
	var note := UiStyle.label("Not part of the real game  ·  cursor hex %s" % (str(where) if cursor >= 0 else "none"), 14, MUTED)
	note.size_flags_horizontal = SIZE_EXPAND_FILL
	note.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(note)
	var x := Button.new()
	x.icon = UiStyle.svg("x", 22)
	x.flat = true
	x.tooltip_text = "Close (` or Esc)"
	x.focus_mode = FOCUS_NONE
	x.pressed.connect(func(): closed.emit())
	head.add_child(x)
	return head


# --- Tabs ---------------------------------------------------------------------------

func _map_tab() -> Control:
	var tab := _tab()
	var seen := _section(tab, "Show")
	seen.add_child(_check("Reveal all enemies and hidden sites", state.debug_reveal, func(on: bool):
		state.debug_reveal = on
		view.show_secrets = on))
	seen.add_child(_check("Hex grid", view.show_grid, func(on: bool): view.show_grid = on))
	seen.add_child(_check("Sight radius of your squads", view.paths.show_sight, func(on: bool): view.paths.show_sight = on))
	var overlay := _options(MapOverlay.MODES.map(func(m): return MapOverlay.NAMES[m]), 260)
	overlay.select(MapOverlay.MODES.find(view.overlay))
	overlay.item_selected.connect(func(i: int): view.overlay = MapOverlay.MODES[i])
	seen.add_child(_row("Overlay", [overlay]))
	var gen := _section(tab, "New map")
	var seed_box := _spin(0, 999999999, state.map.seed, 160)
	gen.add_child(_row("Seed", [seed_box, _button("Regenerate", func(): regenerate.emit(int(seed_box.value)))]))
	return tab


func _time_tab() -> Control:
	var tab := _tab()
	var clock := _section(tab, "Clock")
	var hour := _spin(0, 23, floori(state.clock.minute_of_day() / 60.0))
	clock.add_child(_row("Hour", [hour, _button("Set time of day", func():
		state.clock.set_minute(int(hour.value) * 60)
		_done("Now %s." % state.clock.time_text()))]))
	var hours := _spin(1, 240, 6)
	clock.add_child(_row("Hours", [hours, _button("Skip ahead", func():
		var n := DebugTools.skip_hours(state, int(hours.value))
		_done("Ran %d minutes; now %s.%s" % [n, state.clock.time_text(), " Stopped early." if n < int(hours.value) * 60 else ""]))]))
	clock.add_child(_check("Freeze the clock (time of day stands still)", state.clock.frozen, func(on: bool): state.clock.frozen = on))
	return tab


func _units_tab() -> Control:
	var tab := _tab()
	var build := _section(tab, "Build a squad")
	var names: Array = state.data.units.keys()
	names.sort()
	var cls := _options(names, 240)
	var levels := []
	for i in MAX_LEVEL:
		levels.append("Level %d" % (i + 1))
	var level := _options(levels, 120)
	build.add_child(_row("Unit", [cls, level, _button("Add", func():
		if DebugTools.add_unit(state, _draft, names[cls.selected], level.selected + 1):
			_status.text = "Added a level %d %s." % [level.selected + 1, names[cls.selected]]
		else:
			_status.text = "No room in the squad for a %s." % names[cls.selected]
		_show_draft())]))
	build.add_child(_draft_box)
	_draft_box.add_theme_constant_override("separation", 8)
	_show_draft()
	var side := _options(SIDES.map(func(s: String): return s.capitalize()), 140)
	build.add_child(_row("Side", [side, _button("Place at cursor", func():
		if cursor < 0:
			_status.text = "Open the panel with the mouse over a hex."
			return
		var placed = DebugTools.place(state, _draft, SIDES[side.selected], cursor)
		if placed is String:  # a popup, not just the status line, which was easy to miss (user's notes, 2026-11-11)
			_status.text = placed
			_alert("Can't place this squad", placed)
			return
		_draft = DebugTools.draft(state)  # an empty builder, ready for the next squad
		_picked_unit = null
		_show_draft()
		_done("Placed %s. The builder is empty again." % placed.name)
		_fill_squads(), true), _button("Clear", func():
		_draft = DebugTools.draft(state)
		_picked_unit = null
		_show_draft())]))
	var picked := _section(tab, "A squad on the map")
	_squad.custom_minimum_size.x = 420
	_style_field(_squad)
	_fill_squads()
	picked.add_child(_row("Squad", [_squad]))
	var align := _spin(0, 100, 50)
	picked.add_child(_row("Alignment", [align, _button("Set alignment", func():
		_on_squad(func(s: Squad): DebugTools.set_alignment(state, s, int(align.value))))]))
	picked.add_child(_row("", [_button("Teleport to cursor", func():
		var s := _picked()
		if s and cursor >= 0 and s in state.squads:
			DebugTools.teleport(state, s, cursor)
			_done("%s teleported." % s.name)
		else:
			_status.text = "Pick a squad on the map, and open the panel with the mouse over a hex."), _button("Remove squad", func():
		_on_squad(func(s: Squad): DebugTools.remove(state, s))
		_fill_squads())]))
	var army := _section(tab, "Your army")
	army.add_child(_row("", [_button("Heal and revive all yours", func():
		DebugTools.heal_all(state)
		_done("Every unit of yours is at full HP.")), _button("Wide roster (16 squads)", func(): wide_roster.emit())]))
	return tab


## The squad being built: front and back rows of slots, the units in them, and a
## Remove button for the one clicked.
func _show_draft() -> void:
	for c in _draft_box.get_children():
		c.queue_free()
	if _picked_unit not in _draft.units:
		_picked_unit = null
	var cols := _draft.capacity(state.data)
	for u in _draft.units:
		cols = maxi(cols, u.col + 1)
	for r in ["front", "back"]:
		var line := HBoxContainer.new()
		line.add_theme_constant_override("separation", 6)
		var name_label := UiStyle.label(r.capitalize(), 15, MUTED)
		name_label.custom_minimum_size.x = LABEL_WIDTH
		line.add_child(name_label)
		for c in cols:
			line.add_child(_draft_slot(_draft.at(r, c)))
		_draft_box.add_child(line)
	var leader := _draft.leader
	var facts := "Slots %s / %d  ·  %s" % [EditUnits._num(Squad.slots_filled(state.data, _draft.units)), _draft.capacity(state.data),
			"Leader: %s (%s)" % [leader.name.get_slice(" ", 0), leader.unit_class] if leader else "No leader yet: add a unit that can lead"]
	if _draft.units.is_empty():
		facts = "Empty. Pick a unit and a level, then Add. Click a unit in the squad to remove it."
	var info := UiStyle.label(facts, 14, MUTED)
	var bits: Array = [info]
	if _picked_unit:
		var u := _picked_unit
		bits = [_button("Remove %s" % u.name.get_slice(" ", 0), func():
			DebugTools.remove_unit(state, _draft, u)
			_status.text = "Removed %s (%s)." % [u.name, u.unit_class]
			_show_draft()), info]
	_draft_box.add_child(_row("", bits))


func _draft_slot(u: Unit) -> Control:
	var slot := PanelContainer.new()
	var style := UiStyle.box(FIELD, 3)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.27, 0.32)
	slot.add_theme_stylebox_override("panel", style)
	slot.custom_minimum_size = Vector2(110, 76)
	if u:
		var chip := EditUnits.Chip.new()
		chip.setup(state.data, u, "menu", _draft, EditUnits.KIND_COLORS)
		chip.selected = u == _picked_unit
		chip.mouse_default_cursor_shape = CURSOR_POINTING_HAND
		chip.tooltip_text = "%s (%s), level %d. Click to select, then Remove." % [u.name, u.unit_class, u.level]
		chip.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and e.pressed:
				_picked_unit = null if _picked_unit == u else u
				_show_draft())
		slot.add_child(chip)
	return slot


func _resources_tab() -> Control:
	var tab := _tab()
	var add := _section(tab, "Add")
	var gold := _spin(1, 100000, 1000)
	add.add_child(_row("Gold", [gold, _button("Add gold", func():
		state.gold += int(gold.value)
		state.log.add(state.clock.tick, "system", "Debug: +%d gold." % int(gold.value))
		_done("Gold: %d." % state.gold))]))
	var points := _spin(1, 100, 5)
	add.add_child(_row("Tech points", [points, _button("Add tech points", func():
		state.tech_points += int(points.value)
		state.log.add(state.clock.tick, "system", "Debug: +%d tech points." % int(points.value))
		_done("Tech points: %d." % state.tech_points))]))
	var ids: Array = state.data.cards["cards"].keys()
	var card := _options(ids.map(func(id): return state.card_name(id)), 200)
	add.add_child(_row("Card", [card, _button("Add card", func():
		state.cards.append(ids[card.selected])
		state.log.add(state.clock.tick, "system", "Debug: card %s added." % state.card_name(ids[card.selected]))
		_done("%d cards in hand." % state.cards.size()))]))
	return tab


func _battle_tab() -> Control:
	var tab := _tab()
	var outcome := _section(tab, "Outcome")
	var kinds := ["", "win", "loss", "draw"]
	var force := _options(["Off: fight normally", "Win", "Loss", "Draw"], 220)
	force.select(kinds.find(state.debug_force))
	force.item_selected.connect(func(i: int): state.debug_force = kinds[i])
	outcome.add_child(_row("Force every battle", [force]))
	outcome.add_child(_row("", [_button("Replay the last battle (same rolls)", func():
		if state.last_battle.has("battle"):
			replay.emit()
		else:
			_status.text = "No battle yet.")]))
	var shown := _section(tab, "Display")
	shown.add_child(_check("Show hidden numbers (log and battle view)", state.log.show_hidden, func(on: bool): state.log.show_hidden = on))
	var fair := _section(tab, "Fairness rules (§12.1)")
	for k in FAIRNESS:
		fair.add_child(_check(FAIRNESS[k], state.debug_fairness[k], func(on: bool): state.debug_fairness[k] = on))
	return tab


func _ai_tab() -> Control:
	var tab := _tab()
	var ai := _section(tab, "Enemy and neutral AI")
	ai.add_child(_check("Show each enemy and neutral squad's role and target", view.paths.show_ai, func(on: bool): view.paths.show_ai = on))
	ai.add_child(_check("Freeze enemy and neutral AI", state.debug_freeze_ai, func(on: bool): state.debug_freeze_ai = on))
	return tab


func _sim_tab() -> Control:
	var tab := _tab()
	var sim := _section(tab, "Simulate battles")
	var all := _all_squads()
	var labels := all.map(func(s: Squad): return _squad_label(s))
	var a := _options(labels, 460)
	var b := _options(labels, 460)
	b.select(mini(1, all.size() - 1))
	var trials := _spin(10, 2000, 200)
	var report := UiStyle.label("", 15)
	report.autowrap_mode = TextServer.AUTOWRAP_WORD
	sim.add_child(_row("Squad A", [a]))
	sim.add_child(_row("Squad B", [b]))
	sim.add_child(_row("Battles", [trials, _button("Run", func():
		if all.is_empty():
			return
		var sa: Squad = all[a.selected]
		var sb: Squad = all[b.selected]
		var r := BattleSim.run(state.data, DebugTools.build_of(sa), DebugTools.build_of(sb), int(trials.value), state.clock.tick)
		report.text = BattleSim.report(sa.name, sb.name, r) + "\n(Freshly rolled units of the same classes and rows, not these exact units.)", true)]))
	sim.add_child(report)
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


## A notice over the panel with one OK button.
func _alert(title: String, text: String) -> void:
	var box := ConfirmDialog.new()
	add_child(box)
	box.setup("%s
%s" % [title, text], "OK", "")
	box.confirmed.connect(box.queue_free)
	box.cancelled.connect(box.queue_free)


func _done(text: String) -> void:
	_status.text = text
	changed.emit()


func _tab() -> VBoxContainer:
	var v := VBoxContainer.new()
	v.size_flags_horizontal = SIZE_EXPAND_FILL
	v.add_theme_constant_override("separation", 14)
	return v


## A titled group on a slightly lighter card; returns the box to fill with rows.
func _section(tab: Control, title: String) -> VBoxContainer:
	var card := PanelContainer.new()
	var style := UiStyle.box(SECTION, 14)
	style.set_border_width_all(1)
	style.border_color = Color(0.22, 0.25, 0.3)
	card.add_theme_stylebox_override("panel", style)
	tab.add_child(card)
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 10)
	card.add_child(v)
	v.add_child(UiStyle.label(title.to_upper(), 13, UiStyle.ACCENT))
	return v


## A label in a fixed-width column, then the controls.
func _row(text: String, controls: Array) -> HBoxContainer:
	var h := HBoxContainer.new()
	h.add_theme_constant_override("separation", 10)
	var l := UiStyle.label(text, 15, MUTED)
	l.custom_minimum_size.x = LABEL_WIDTH
	l.size_flags_vertical = SIZE_SHRINK_CENTER
	h.add_child(l)
	for c in controls:
		if c is Label:
			c.size_flags_vertical = SIZE_SHRINK_CENTER
		h.add_child(c)
	return h


func _button(text: String, action: Callable, main := false) -> Button:
	var b := UiStyle.button(text, 0, main)
	b.custom_minimum_size.y = 36
	b.add_theme_font_size_override("font_size", 15)
	for s in ["normal", "hover", "pressed", "focus", "disabled"]:
		var box: StyleBoxFlat = b.get_theme_stylebox(s).duplicate()
		box.content_margin_left = 14
		box.content_margin_right = 14
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		b.add_theme_stylebox_override(s, box)
	b.pressed.connect(action)
	return b


func _check(text: String, on: bool, action: Callable) -> CheckBox:
	var c := CheckBox.new()
	c.text = text
	c.button_pressed = on
	c.add_theme_font_size_override("font_size", 15)
	c.add_theme_constant_override("h_separation", 10)
	var off := UiStyle.svg("square", 22, MUTED)
	var yes := UiStyle.svg("square-check-big", 22, UiStyle.ACCENT)
	c.add_theme_icon_override("unchecked", off)
	c.add_theme_icon_override("checked", yes)
	c.add_theme_icon_override("unchecked_disabled", off)
	c.add_theme_icon_override("checked_disabled", yes)
	for s in ["normal", "pressed", "hover", "hover_pressed", "focus"]:
		var box := StyleBoxFlat.new()
		box.bg_color = Color(1, 1, 1, 0.05) if s.begins_with("hover") else Color(0, 0, 0, 0)
		box.set_corner_radius_all(6)
		box.content_margin_left = 4
		box.content_margin_right = 8
		box.content_margin_top = 3
		box.content_margin_bottom = 3
		c.add_theme_stylebox_override(s, box)
	c.toggled.connect(action)
	return c


func _options(items: Array, width: int) -> OptionButton:
	var o := OptionButton.new()
	for t in items:
		o.add_item(str(t))
	o.custom_minimum_size.x = width
	_style_field(o)
	return o


func _spin(lo: int, hi: int, value: int, width := 110) -> SpinBox:
	var s := SpinBox.new()
	s.min_value = lo
	s.max_value = hi
	s.value = value
	s.update_on_text_changed = true  # a typed number counts without pressing Enter
	s.custom_minimum_size = Vector2(width, 36)
	var edit := s.get_line_edit()
	edit.add_theme_font_size_override("font_size", 15)
	edit.add_theme_stylebox_override("normal", _field_box(UiStyle.OUTLINE.darkened(0.2)))
	edit.add_theme_stylebox_override("focus", _field_box(UiStyle.ACCENT, true))
	return s


## Dropdowns read as fields: a dark well with a thin outline.
func _style_field(o: OptionButton) -> void:
	o.custom_minimum_size.y = 36
	o.add_theme_font_size_override("font_size", 15)
	o.add_theme_stylebox_override("normal", _field_box(UiStyle.OUTLINE.darkened(0.2)))
	o.add_theme_stylebox_override("hover", _field_box(UiStyle.OUTLINE.lightened(0.2)))
	o.add_theme_stylebox_override("pressed", _field_box(UiStyle.ACCENT))
	o.add_theme_stylebox_override("focus", _field_box(UiStyle.ACCENT, true))
	o.get_popup().add_theme_font_size_override("font_size", 15)


func _field_box(edge: Color, see_through := false) -> StyleBoxFlat:
	var b := StyleBoxFlat.new()
	b.bg_color = Color(0, 0, 0, 0) if see_through else FIELD
	b.set_border_width_all(1)
	b.border_color = edge
	b.set_corner_radius_all(6)
	b.content_margin_left = 10
	b.content_margin_right = 10
	b.content_margin_top = 4
	b.content_margin_bottom = 4
	return b


func _style_tabs(tabs: TabContainer) -> void:
	tabs.add_theme_font_size_override("font_size", 16)
	tabs.add_theme_color_override("font_selected_color", UiStyle.ACCENT)
	tabs.add_theme_color_override("font_unselected_color", MUTED)
	tabs.add_theme_color_override("font_hovered_color", Color.WHITE)
	for s in ["tab_selected", "tab_unselected", "tab_hovered"]:
		var b := StyleBoxFlat.new()
		b.bg_color = {"tab_selected": Color(0.16, 0.18, 0.22), "tab_unselected": Color(0, 0, 0, 0), "tab_hovered": Color(1, 1, 1, 0.05)}[s]
		b.corner_radius_top_left = 6
		b.corner_radius_top_right = 6
		b.content_margin_left = 16
		b.content_margin_right = 16
		b.content_margin_top = 8
		b.content_margin_bottom = 8
		if s == "tab_selected":
			b.border_width_top = 2
			b.border_color = UiStyle.ACCENT
		tabs.add_theme_stylebox_override(s, b)
	var body := StyleBoxFlat.new()
	body.bg_color = Color(0.16, 0.18, 0.22)
	body.set_corner_radius_all(6)
	body.corner_radius_top_left = 0
	tabs.add_theme_stylebox_override("panel", body)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_QUOTELEFT, KEY_ESCAPE]:
		closed.emit()
		get_viewport().set_input_as_handled()
