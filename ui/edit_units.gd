class_name EditUnits
extends Control
## Edit Units (SPEC §4): the army overview (a 4×4 grid of squad cards) with the recruit
## pool in a gutter on the right; click a card for the squad detail (front and back rows).
## Click any unit, in a squad or the pool, for its detail panel over the screen: stats,
## leader, promotion and items, and an About tab for the unit type. Drag units between squads, rows and the
## pool. The gutter's Items tab lists every item the army owns, worn ones greyed with
## who has them; drag a free item onto a unit or an item slot, and drag a worn one back
## to the list to take it off. Squads out in the field are locked until they're back at
## the Player Base. The Player Base's services live here too: deploy a squad waiting at
## base (up to the squad cap), send one standing on the base back in, and pay to heal or
## revive units at base.
## A modal: 50% dark overlay; the battlemap holds the clock while it's open.

signal closed
signal deploy(squad: Squad)  # lay its route on the map, then confirm the cost

const KIND_COLORS := {"Melee": Color("#8a4a3a"), "Ranged": Color("#4f7a3a"), "Magic": Color("#3d5a9a"),
		"Breath": Color("#8a5a2a"), "Heal": Color("#9a8a3a"), "Buff": Color("#9a8a3a"), "Debuff": Color("#6a4a8a"),
		"Ward": Color("#3a7a8a"), "Dispel": Color("#3d5a9a")}
const SUPPORT := ["Heal", "Buff", "Debuff", "Ward", "Ranged", "Magic", "Dispel"]

var state: GameState
var army: Army
var data: GameData
var _squad: Squad  # the squad in detail view, or null for the overview
var _cell := -1
var _unit: Unit  # shown in the unit detail panel, or null
var _unit_tab := "overview"  # the panel's tab: "overview" or "about"
var _modal: Control  # the unit detail panel while open
var _title := UiStyle.label("Edit Units", 26)
var _main := VBoxContainer.new()
var _pool := VBoxContainer.new()
var _tab := "recruits"  # the gutter shows "recruits" or "items"
var _tabs := {}  # tab -> Button
var _targets: Array = []  # [Control, Unit] that take items, dimmed while an item they can't wear is dragged
var _status := UiStyle.label("", 16, UiStyle.ACCENT)
var _gold := UiStyle.label("", 18, UiStyle.ACCENT)
var _back: Button


## Opens on the army overview, or on the squad in `cell`.
func setup(game_state: GameState, cell := -1) -> void:
	state = game_state
	army = state.army
	data = state.data
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 16))
	panel.custom_minimum_size = Vector2(1840, 1000)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	var top := HBoxContainer.new()
	top.add_theme_constant_override("separation", 12)
	col.add_child(top)
	_back = UiStyle.button("Back to army", 190)
	_back.pressed.connect(func(): _open(-1))
	top.add_child(_back)
	_title.size_flags_horizontal = SIZE_EXPAND_FILL
	top.add_child(_title)
	top.add_child(_gold)
	var close := UiStyle.button("Done (U)", 170, true)
	close.pressed.connect(func(): closed.emit())
	top.add_child(close)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(body)
	_main.size_flags_horizontal = SIZE_EXPAND_FILL
	_main.add_theme_constant_override("separation", 12)
	body.add_child(_main)
	body.add_child(_gutter())
	col.add_child(_status)
	_open(cell)


## The recruit pool on the right; dropping a unit here sends it to the pool.
func _gutter() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.1), 12))
	box.custom_minimum_size.x = 300
	box.set_drag_forwarding(Callable(), _can_drop.bind(-1, "", -1), _drop.bind(-1, "", -1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for t in ["recruits", "items"]:
		var b := UiStyle.button("", 134)
		b.toggle_mode = true
		b.pressed.connect(func():
			_tab = t
			_refresh())
		tabs.add_child(b)
		_tabs[t] = b
	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.mouse_filter = MOUSE_FILTER_PASS
	col.add_child(scroll)
	_pool.add_theme_constant_override("separation", 6)
	scroll.add_child(_pool)
	return box


func _open(cell: int) -> void:
	_cell = cell
	_squad = army.cells[cell] if cell >= 0 else null
	_unit = null
	_status.text = ""
	_refresh()


func _refresh() -> void:
	if _squad and _squad not in army.squads():  # emptied by a move
		_squad = null
		_cell = -1
	for c in _main.get_children():
		c.queue_free()
	for c in _pool.get_children():
		c.queue_free()
	if _modal:
		_modal.queue_free()
		_modal = null
	_targets.clear()
	_back.visible = _squad != null
	_gold.text = "Gold %d  ·  Upkeep %d a day  ·  On the map %d / %d" % [state.gold, state.army_upkeep(), state.player_squads().size(), state.squad_cap()]
	_title.text = "Edit Units" if _squad == null else "Edit Units  ·  #%d %s" % [_squad.id, _squad.name]
	if _squad:
		_main.add_child(_detail())
	else:
		_main.add_child(_overview())
	_tabs["recruits"].text = "Recruits (%d)" % army.pool.size()
	_tabs["items"].text = "Items (%d)" % army.items.size()
	for t in _tabs:
		_tabs[t].set_pressed_no_signal(t == _tab)
	if _tab == "items":
		_item_list()
	else:
		for u in army.pool:
			_pool.add_child(_chip(u, "wide", true, -1, "", -1))
		if army.pool.is_empty():
			_pool.add_child(UiStyle.label("Drag units here to take them out of a squad.", 14, Color(0.6, 0.62, 0.66)))
	if _unit:
		_show_unit()


# --- Overview -----------------------------------------------------------------------

func _overview() -> Control:
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 12)
	grid.add_theme_constant_override("v_separation", 12)
	for i in army.cells.size():
		grid.add_child(_card(i))
	return grid


func _card(cell: int) -> Control:
	var s: Squad = army.cells[cell]
	var locked := s != null and not state.can_edit(s)
	var card := PanelContainer.new()
	var style := UiStyle.box(Color(0.13, 0.15, 0.19) if s else Color(0.09, 0.1, 0.12), 10)
	style.set_border_width_all(2)
	style.border_color = UiStyle.OUTLINE if s else Color(0.2, 0.22, 0.26)
	card.add_theme_stylebox_override("panel", style)
	card.custom_minimum_size = Vector2(368, 206)
	card.set_drag_forwarding(Callable(), _can_drop.bind(cell, "", -1), _drop.bind(cell, "", -1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	card.add_child(col)
	if s == null:
		col.add_child(_quiet(UiStyle.label("#%d" % (cell + 1), 18, Color(0.45, 0.47, 0.52))))
		var l := _quiet(UiStyle.label("Empty: drop a unit here to form a squad.", 14, Color(0.45, 0.47, 0.52)))
		col.add_child(l)
		return card
	card.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	card.tooltip_text = "Click to open the squad"
	card.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			_open(cell))
	var head := HBoxContainer.new()
	head.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_child(_quiet(UiStyle.label("#%d  %s" % [s.id, s.name], 18)))
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	spacer.mouse_filter = MOUSE_FILTER_IGNORE
	head.add_child(spacer)
	var where := "In the field" if locked else ("On the map" if s in state.squads else "At base")
	head.add_child(_quiet(UiStyle.label(where, 13, Color("#e0a050") if locked else Color(0.6, 0.65, 0.7))))
	var go := _base_button(s, true)
	if go:
		head.add_child(go)
	col.add_child(head)
	var lead := "Led by %s" % s.leader.name if s.leader else "No leader: add a unit that can lead"
	col.add_child(_quiet(UiStyle.label(lead, 13, Color(0.7, 0.73, 0.78) if s.leader else Color("#ff8a70"))))
	for r in ["front", "back"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 4)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.custom_minimum_size.y = 52
		row.add_child(_quiet(UiStyle.label(r.capitalize(), 12, Color(0.55, 0.58, 0.62))))
		row.get_child(0).custom_minimum_size.x = 38
		var units := s.row(r)
		units.sort_custom(func(a: Unit, b: Unit): return a.col < b.col)
		for u in units:
			row.add_child(_chip(u, "compact", not locked, cell, "", -1))
		col.add_child(row)
	col.add_child(_quiet(UiStyle.label("%s  ·  speed %d  ·  slots %s / %d" % [s.travel_name(), s.speed_tier,
			_num(Squad.slots_filled(data, s.units)), s.capacity(data)], 13, Color(0.7, 0.73, 0.78))))
	return card


# --- Squad detail -----------------------------------------------------------------------

func _detail() -> Control:
	var s := _squad
	var locked := not state.can_edit(s)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 8)
	var facts := "%s  ·  speed %d  ·  slots %s / %d  ·  %s (%d)" % [s.travel_name(), s.speed_tier, _num(Squad.slots_filled(data, s.units)), s.capacity(data),
			s.alignment_band(data).capitalize(), roundi(s.alignment())]
	if locked:
		facts += "  ·  In the field: edit it back at the Player Base"
	var bar := HBoxContainer.new()
	bar.add_theme_constant_override("separation", 12)
	box.add_child(bar)
	bar.add_child(UiStyle.label(facts, 16, Color("#e0a050") if locked else Color(0.75, 0.78, 0.82)))
	var go := _base_button(s, false)
	if go:
		bar.add_child(go)
	if state.is_broke():
		var sell := _small("Sell for %d g" % state.sell_value(s), false)
		sell.tooltip_text = "You're out of gold: the squad leaves the army and its items return to the inventory."
		sell.pressed.connect(func():
			state.sell_squad(s)
			_open(-1))
		bar.add_child(sell)
	var cost := 0
	for u in s.units:
		cost += state.heal_cost(u) + state.revive_cost(u)
	if cost > 0 and not locked and s not in state.squads:
		var all := _small("Heal and revive all (%d g)" % cost, false)
		all.disabled = cost > state.gold
		all.tooltip_text = "Not enough gold." if all.disabled else "Heals every hurt unit to full and revives the fallen."
		all.pressed.connect(func():
			for u in s.units:
				state.restore(u)
			_refresh())
		bar.add_child(all)
	var cols := s.capacity(data)
	for u in s.units:
		cols = maxi(cols, u.col + 1)
	for r in ["front", "back"]:
		box.add_child(UiStyle.label("%s row" % r.capitalize(), 16))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		for c in cols:
			row.add_child(_slot(s, r, c, locked))
		box.add_child(row)
	box.add_child(UiStyle.label("Click a unit for its details. Drag units to rearrange them.", 14, Color(0.55, 0.58, 0.62)))
	return box


func _slot(s: Squad, r: String, c: int, locked: bool) -> Control:
	var slot := PanelContainer.new()
	var style := UiStyle.box(Color(0.09, 0.1, 0.12), 3)
	style.set_border_width_all(1)
	style.border_color = Color(0.25, 0.27, 0.32)
	slot.add_theme_stylebox_override("panel", style)
	slot.custom_minimum_size = Vector2(156, 112)
	if not locked:
		slot.set_drag_forwarding(Callable(), _can_drop.bind(_cell, r, c), _drop.bind(_cell, r, c))
	var u := s.at(r, c)
	if u:
		slot.add_child(_chip(u, "slot", not locked, _cell, r, c))
	return slot


## The unit detail panel over the whole screen, the same from a squad or the pool. Close
## with the button or Esc.
func _show_unit() -> void:
	var u := _unit
	var sq := army.squad_of(u)
	var locked := sq != null and not state.can_edit(sq)
	_modal = Control.new()
	_modal.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(_modal)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_modal.add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	_modal.add_child(center)
	var panel := PanelContainer.new()
	var style := UiStyle.box(UiStyle.PANEL, 24)
	style.set_border_width_all(2)
	style.border_color = UiStyle.OUTLINE
	panel.add_theme_stylebox_override("panel", style)
	panel.custom_minimum_size = Vector2(1700, 900)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 16)
	col.add_child(head)
	head.add_child(UiStyle.label(u.name, 30))
	var where := "%s of #%d %s" % ["Leader" if sq.leader == u else "In", sq.id, sq.name] if sq else "In the recruit pool"
	var sub := UiStyle.label("%s  ·  %s" % [u.unit_class, where], 18, Color(0.75, 0.78, 0.82))
	sub.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(sub)
	var close := UiStyle.button("Close (Esc)", 190, true)
	close.pressed.connect(_close_unit)
	head.add_child(close)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 6)
	col.add_child(tabs)
	for t in [["overview", "Overview"], ["about", "About the %s" % u.unit_class]]:
		var b := UiStyle.button(t[1], 200)
		b.toggle_mode = true
		b.set_pressed_no_signal(_unit_tab == t[0])
		b.pressed.connect(func():
			_unit_tab = t[0]
			_refresh())
		tabs.add_child(b)
	var body: Control = _unit_overview(u, sq, locked) if _unit_tab == "overview" else _unit_about(u)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(body)
	col.add_child(UiStyle.label(_status.text, 16, UiStyle.ACCENT))


func _close_unit() -> void:
	_unit = null
	_status.text = ""
	_refresh()


## The About tab: room for the unit type's art and description, with what the sheet says.
func _unit_about(u: Unit) -> Control:
	var c: Dictionary = u.info(data)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	var art := PanelContainer.new()
	var frame := UiStyle.box(Color(0.07, 0.08, 0.1), 0)
	frame.set_border_width_all(2)
	frame.border_color = Color(0.25, 0.27, 0.32)
	art.add_theme_stylebox_override("panel", frame)
	art.custom_minimum_size = Vector2(420, 420)
	art.size_flags_vertical = SIZE_SHRINK_BEGIN
	var art_note := UiStyle.label("Art coming later", 16, Color(0.4, 0.42, 0.47))
	art_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	art_note.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	art.add_child(art_note)
	row.add_child(art)
	var text := VBoxContainer.new()
	text.add_theme_constant_override("separation", 10)
	row.add_child(text)
	text.add_child(UiStyle.label(u.unit_class, 26))
	text.add_child(UiStyle.label("%s  ·  stage %d  ·  %s  ·  %s  ·  leans %s" % [c["role"], int(c["stage"]), c["size"], c["terrain"],
			str(c["alignment_lean"]).to_lower()], 17, Color(0.8, 0.82, 0.86)))
	text.add_child(_wrapped("No description of the %s yet." % u.unit_class if c.get("notes") == null else str(c["notes"]), 17))
	text.add_child(UiStyle.label("Lines", 18, Color(0.65, 0.68, 0.72)))
	for line_id in c["lines"]:
		var stages := PackedStringArray()
		for stage in data.lines[line_id]:
			stages.append(" / ".join(PackedStringArray(stage)))
		text.add_child(_wrapped("  >  ".join(stages), 16))
	return row


## The Overview tab: who it is and its stats, what it does and its promotion, and its items.
func _unit_overview(u: Unit, sq: Squad, locked: bool) -> Control:
	var c: Dictionary = u.info(data)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	# Who it is and its stats
	var who := VBoxContainer.new()
	who.add_theme_constant_override("separation", 8)
	who.custom_minimum_size.x = 440
	row.add_child(who)
	who.add_child(UiStyle.label("%s  ·  stage %d  ·  level %d  ·  XP %d / %d" % [u.unit_class, int(c["stage"]), u.level, u.xp,
			Progression.level_cost(data, u)], 17, Color(0.8, 0.82, 0.86)))
	if sq and sq.leader == u:
		who.add_child(UiStyle.label("Leads %s" % sq.name, 16, Color(1, 0.88, 0.5)))
	elif sq and c["can_lead"] and not locked:
		var lead := UiStyle.button("Make leader", 180)
		lead.pressed.connect(func():
			if not army.set_leader(u):
				_status.text = "%s can't lead %s: the squad would have too few slots." % [u.name, sq.name]
			_refresh())
		who.add_child(lead)
	elif not c["can_lead"]:
		who.add_child(UiStyle.label("Can't lead", 14, Color(0.6, 0.62, 0.66)))
	var hp_line := HBoxContainer.new()
	hp_line.add_theme_constant_override("separation", 12)
	who.add_child(hp_line)
	hp_line.add_child(UiStyle.label("HP %d / %d" % [u.hp, u.max_hp(data)] + ("  (fallen)" if not u.is_alive() else ""), 16))
	var cost := state.heal_cost(u) + state.revive_cost(u)
	if cost > 0:
		var fix := _small("%s (%d g)" % ["Revive" if not u.is_alive() else "Heal to full", cost], false)
		fix.disabled = not state.at_base(u) or cost > state.gold
		fix.tooltip_text = "Only at the Player Base." if not state.at_base(u) else ("Not enough gold." if cost > state.gold else "")
		fix.pressed.connect(func():
			state.restore(u)
			_refresh())
		hp_line.add_child(fix)
	who.add_child(UiStyle.label("Alignment %d (%s)  ·  Charisma %d" % [u.alignment, u.alignment_band(data), u.charisma], 16))
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 24)
	for s in Unit.STATS:
		var bonus := u.stat(data, s) - int(u.stats[s])
		grid.add_child(UiStyle.label(s, 15, Color(0.65, 0.68, 0.72)))
		grid.add_child(UiStyle.label("%d%s" % [u.stat(data, s), " (%+d)" % bonus if bonus != 0 else ""], 15, Color("#9fe09a") if bonus > 0 else Color.WHITE))
	who.add_child(grid)
	# What it does
	var does := VBoxContainer.new()
	does.add_theme_constant_override("separation", 8)
	does.custom_minimum_size.x = 480
	row.add_child(does)
	does.add_child(UiStyle.label("Front row: %s ×%d" % [c["front_attack"], int(c["front_count"])], 16))
	does.add_child(UiStyle.label("Back row: %s ×%d" % [c["back_attack"], int(c["back_count"])], 16))
	does.add_child(UiStyle.label("%s  ·  %s  ·  speed tier %d%s" % [c["terrain"], c["size"], int(c["speed_tier"]),
			"  ·  " + str(c["element"]) if c["element"] != null else ""], 15, Color(0.8, 0.82, 0.86)))
	if not c["traits"].is_empty():
		does.add_child(_wrapped("Traits: " + ", ".join(c["traits"]), 15))
	if c["leader_aura"] != null:
		does.add_child(_wrapped("Leader aura: %s. %s" % [c["leader_aura"], c.get("leader_aura_text", "")], 15))
	does.add_child(_promotion(u, locked))
	# Items
	var gear := VBoxContainer.new()
	gear.add_theme_constant_override("separation", 8)
	row.add_child(gear)
	gear.add_child(UiStyle.label("Items", 18))
	for slot in data.items["slots"]:
		gear.add_child(_item_box(u, slot, locked))
	if locked:
		return row
	gear.add_child(UiStyle.label("Free items that fit: drag one onto a slot, or click it", 14, Color(0.55, 0.58, 0.62)))
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(420, 380)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	gear.add_child(scroll)
	var list := VBoxContainer.new()
	list.add_theme_constant_override("separation", 6)
	list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(list)
	var free := army.items.filter(func(i: Dictionary): return army.holder(i) == null and army.fits(u, i))
	if free.is_empty():
		list.add_child(UiStyle.label("None. Shops and hidden sites will have more.", 14, Color(0.55, 0.58, 0.62)))
	for item in free:
		list.add_child(_item_row(item, func():
			army.equip(u, item)
			_refresh()))
	return row


## Promotion (§9.4): a button per class the unit can become now, or when it can next promote.
func _promotion(u: Unit, locked: bool) -> Control:
	var box := VBoxContainer.new()
	var options := Progression.promotion_options(data, u)
	if options.is_empty():
		var next := data.next_classes(u.unit_class)
		box.add_child(_wrapped("Final stage." if next.is_empty() else
				"Promotes at level %d to: %s." % [Progression.next_promotion_level(data, u), ", ".join(next)], 15))
		return box
	box.add_child(UiStyle.label("Ready to promote:", 15, Color("#7ee08a")))
	var row := HFlowContainer.new()
	row.add_theme_constant_override("h_separation", 8)
	row.add_theme_constant_override("v_separation", 8)
	box.add_child(row)
	for c in options:
		var b := _small("Promote to %s" % c, false, true)
		b.disabled = locked or not state.at_base(u)
		b.tooltip_text = "Promote at the Player Base." if b.disabled else _promotion_tip(u, c)
		b.pressed.connect(func():
			var why := state.promote(u, c)
			_status.text = why
			_refresh())
		row.add_child(b)
	return box


func _promotion_tip(u: Unit, c: String) -> String:
	var parts := []
	for s in Unit.STATS:
		var diff := int(data.units[c]["base_stats"][s]) - int(data.units[u.unit_class]["base_stats"][s])
		if diff != 0:
			parts.append("%s %+d" % [s, diff])
	var info: Dictionary = data.units[c]
	return "%s: %s. Front %s, back %s." % [c, ", ".join(parts), info["front_attack"], info["back_attack"]]


## One of the unit's item slots: the item worn (drag it away, or ×), or an empty outline.
func _item_box(u: Unit, slot: String, locked: bool) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var l := UiStyle.label(slot.capitalize(), 15, Color(0.65, 0.68, 0.72))
	l.custom_minimum_size.x = 70
	line.add_child(l)
	var box := PanelContainer.new()
	var item: Dictionary = u.items.get(slot, {})
	var style := UiStyle.box(Color(0.15, 0.17, 0.21) if item else Color(0, 0, 0, 0), 8)
	style.set_border_width_all(2 if item else 1)
	style.border_color = UiStyle.OUTLINE if item else Color(0.3, 0.32, 0.37)
	box.add_theme_stylebox_override("panel", style)
	box.custom_minimum_size = Vector2(330, 44)
	line.add_child(box)
	var inner := HBoxContainer.new()
	inner.mouse_filter = MOUSE_FILTER_IGNORE
	box.add_child(inner)
	var text := _quiet(UiStyle.label(_item_label(item["id"]) if item else "Empty", 15, Color.WHITE if item else Color(0.45, 0.47, 0.52)))
	text.size_flags_horizontal = SIZE_EXPAND_FILL
	inner.add_child(text)
	if locked:
		return line
	box.set_drag_forwarding(_drag_item.bind(item, u) if item else Callable(), _can_drop_item.bind(u, slot), _drop_item.bind(u))
	_targets.append([box, u, slot])
	if item:
		box.mouse_default_cursor_shape = CURSOR_DRAG
		box.tooltip_text = "Drag to another unit, or back to the Items tab to take it off."
		var off := Button.new()
		off.text = "×"
		off.flat = true
		off.tooltip_text = "Take it off"
		off.pressed.connect(func():
			army.unequip(u, slot)
			_refresh())
		inner.add_child(off)
	return line


## The gutter's Items tab: every item by slot, free ones first.
func _item_list() -> void:
	for id in data.items["consumables"]:
		_pool.add_child(UiStyle.label("%ss: %d" % [data.items["consumables"][id]["name"], int(army.supplies.get(id, 0))], 15, UiStyle.ACCENT))
	if army.items.is_empty():
		_pool.add_child(UiStyle.label("No items yet. Shops and hidden sites will have some.", 14, Color(0.6, 0.62, 0.66)))
	for slot in data.items["slots"]:
		var of_slot := army.items.filter(func(i: Dictionary): return data.items["items"][i["id"]]["slot"] == slot)
		if of_slot.is_empty():
			continue
		of_slot.sort_custom(func(a: Dictionary, b: Dictionary):
			var fa := army.holder(a) == null
			var fb := army.holder(b) == null
			return fa and not fb if fa != fb else a["id"] < b["id"])
		_pool.add_child(UiStyle.label(slot.to_upper(), 13, Color(0.6, 0.62, 0.66)))
		for item in of_slot:
			_pool.add_child(_item_row(item))


## An owned item: free ones drag onto units (or run `on_click`, if given); worn ones say
## who has them and open that unit.
func _item_row(item: Dictionary, on_click := Callable()) -> Control:
	var who := army.holder(item)
	var row := PanelContainer.new()
	var style := UiStyle.box(Color(0.15, 0.17, 0.21) if who == null else Color(0.1, 0.11, 0.13), 8)
	style.set_border_width_all(1)
	style.border_color = UiStyle.OUTLINE if who == null else Color(0.22, 0.24, 0.28)
	row.add_theme_stylebox_override("panel", style)
	var col := VBoxContainer.new()
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 0)
	row.add_child(col)
	col.add_child(_quiet(UiStyle.label(_item_label(item["id"]), 15, Color.WHITE if who == null else Color(0.5, 0.52, 0.56))))
	if who == null:
		row.mouse_default_cursor_shape = CURSOR_DRAG
		row.tooltip_text = "Drag onto a unit or an item slot." + (" Click to equip." if on_click.is_valid() else "")
		row.set_drag_forwarding(_drag_item.bind(item, null), Callable(), Callable())
		if on_click.is_valid():
			row.gui_input.connect(func(e: InputEvent):
				if e is InputEventMouseButton and not e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
					on_click.call())
		return row
	var sq := army.squad_of(who)
	var where := "#%d %s" % [sq.id, sq.name] if sq else "recruit pool"
	col.add_child(_quiet(UiStyle.label("On %s (%s), %s" % [who.name, who.unit_class, where], 12, Color(0.5, 0.52, 0.56))))
	row.tooltip_text = "Click to go to %s." % who.name
	row.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	row.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			if sq:
				_open(sq.id - 1)
			_unit = who
			_refresh())
	return row


func _item_label(id: String) -> String:
	var item: Dictionary = data.items["items"][id]
	var parts := []
	for s in item["stats"]:
		parts.append("%s %+d" % [s, int(item["stats"][s])])
	if item.has("range"):
		parts.append("range +%d" % int(item["range"]))
	return "%s: %s" % [item["name"], ", ".join(parts)]


# --- Base actions ---------------------------------------------------------------------

## Deploy for a squad at base, Return for one standing on the Player Base; null otherwise.
func _base_button(s: Squad, compact: bool) -> Button:
	if s in state.squads:
		if not state.can_edit(s):
			return null
		var back := _small("Return", compact)
		back.tooltip_text = "Take the squad off the map, into the Player Base."
		back.pressed.connect(func():
			state.return_to_base(s)
			_refresh())
		return back
	var go := _small("Deploy", compact, true)
	var why := state.deploy_blocker(s)
	go.disabled = why != ""
	go.tooltip_text = why if why != "" else "Pick where it should head on the map; deploying costs %d gold." % state.deploy_cost(s)
	go.pressed.connect(func(): deploy.emit(s))
	return go


func _small(text: String, compact: bool, action := false) -> Button:
	var b := UiStyle.button(text, 0.0, action)
	b.custom_minimum_size = Vector2(0, 28 if compact else 36)
	b.add_theme_font_size_override("font_size", 13 if compact else 15)
	return b


# --- Units and dragging -------------------------------------------------------------

## A unit; dropping a unit on it acts like dropping on its place (cell, row, position),
## and dropping an item on it equips the item.
func _chip(u: Unit, mode: String, draggable: bool, cell: int, r: String, c: int) -> Control:
	var chip := Chip.new()
	chip.setup(data, u, mode, army.squad_of(u), KIND_COLORS)
	chip.selected = u == _unit and mode != "compact"
	if draggable:
		chip.set_drag_forwarding(_drag.bind(u), _can_drop_on_chip.bind(u, cell, r, c), _drop_on_chip.bind(u, cell, r, c))
		_targets.append([chip, u, ""])
	chip.tooltip_text = "%s (%s), level %d. HP %d/%d.%s" % [u.name, u.unit_class, u.level, u.hp, u.max_hp(data),
			" Drag to move." if draggable else ""]
	chip.gui_input.connect(func(e: InputEvent):
		if not (e is InputEventMouseButton and e.button_index == MOUSE_BUTTON_LEFT and not e.pressed):
			return  # on release, so pressing to drag doesn't rebuild the screen under the drag
		if mode == "compact":  # in a squad card: open the squad behind the unit's panel
			_open(cell)
		_unit = u
		_refresh())
	return chip


func _drag(_at: Vector2, u: Unit) -> Variant:
	var preview := Chip.new()
	preview.setup(data, u, "compact", null, KIND_COLORS)
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"unit": u}


func _drag_item(_at: Vector2, item: Dictionary, from: Unit) -> Variant:
	var preview := UiStyle.label(data.items["items"][item["id"]]["name"], 16)
	preview.add_theme_stylebox_override("normal", UiStyle.box(Color(0.15, 0.17, 0.21, 0.9), 8))
	set_drag_preview(preview)
	var slot: String = data.items["items"][item["id"]]["slot"]
	for t in _targets:
		var ok: bool = army.fits(t[1], item) and (t[2] == "" or t[2] == slot)
		t[0].modulate = Color.WHITE if ok else Color(1, 1, 1, 0.3)
	return {"item": item, "from": from}


func _notification(what: int) -> void:
	if what == NOTIFICATION_DRAG_END:
		for t in _targets:
			if is_instance_valid(t[0]):
				t[0].modulate = Color.WHITE


func _can_drop_item(_at: Vector2, what: Variant, u: Unit, slot := "") -> bool:
	if not (what is Dictionary and what.has("item")):
		return false
	var s := army.squad_of(u)
	return army.fits(u, what["item"]) and (slot == "" or data.items["items"][what["item"]["id"]]["slot"] == slot) \
			and (s == null or state.can_edit(s))


func _drop_item(_at: Vector2, what: Variant, u: Unit) -> void:
	army.equip(u, what["item"])
	_status.text = ""
	_refresh()


func _can_drop_on_chip(at: Vector2, what: Variant, u: Unit, cell: int, r: String, c: int) -> bool:
	if what is Dictionary and what.has("item"):
		return _can_drop_item(at, what, u)
	return _can_drop(at, what, cell, r, c) and what["unit"] != u


func _drop_on_chip(at: Vector2, what: Variant, u: Unit, cell: int, r: String, c: int) -> void:
	if what.has("item"):
		_drop_item(at, what, u)
	elif cell == -1:
		_drop(at, what, -1, "", -1)
	else:
		_drop(at, what, cell, u.row if r != "" else "", u.col if r != "" else -1)


func _can_drop(_at: Vector2, what: Variant, cell: int, _r: String, _c: int) -> bool:
	if what is Dictionary and what.has("item"):
		return cell == -1 and what["from"] != null  # a worn item dropped on the gutter comes off
	if not (what is Dictionary and what.has("unit")):
		return false
	var target: Squad = army.cells[cell] if cell >= 0 else null
	return target == null or state.can_edit(target)


## A drop on a card picks the row from the unit's attacks; a drop on a slot uses that slot.
func _drop(_at: Vector2, what: Variant, cell: int, r: String, c: int) -> void:
	if what.has("item"):
		var from: Unit = what["from"]
		army.unequip(from, data.items["items"][what["item"]["id"]]["slot"])
		_refresh()
		return
	var u: Unit = what["unit"]
	if r == "":
		r = preferred_row(data, u)
	if army.move(u, cell, r, c):
		_status.text = ""
	else:
		var s: Squad = army.cells[cell]
		_status.text = "%s doesn't fit: %s has %s of %d slots filled." % [u.name, s.name, _num(Squad.slots_filled(data, s.units)), s.capacity(data)]
	_refresh()


## Back row for units that heal, support or attack from range there; front otherwise.
static func preferred_row(game_data: GameData, u: Unit) -> String:
	var c: Dictionary = u.info(game_data)
	var back := Battle.base_kind(c["back_attack"])
	if back in SUPPORT and (Battle.base_kind(c["front_attack"]) == "Melee" or int(c["back_count"]) >= int(c["front_count"])):
		return "back"
	return "front"


static func _num(v: float) -> String:
	return str(int(v)) if v == int(v) else str(v)


func _quiet(c: Control) -> Control:
	c.mouse_filter = MOUSE_FILTER_IGNORE
	return c


func _wrapped(text: String, font_size: int) -> Label:
	var l := UiStyle.label(text, font_size, Color(0.8, 0.82, 0.86))
	l.autowrap_mode = TextServer.AUTOWRAP_WORD
	l.custom_minimum_size.x = 420
	return l


func _unhandled_key_input(event: InputEvent) -> void:
	if not event.is_pressed():
		return
	var key := (event as InputEventKey).keycode
	if key == KEY_ESCAPE and _unit:
		_close_unit()
	elif key == KEY_U or (key == KEY_ESCAPE and _squad == null):
		closed.emit()
	elif key == KEY_ESCAPE:
		_open(-1)
	get_viewport().set_input_as_handled()


## A unit as a small square (squad cards), a wide row (pool) or a slot-sized card (detail).
class Chip extends Control:
	var unit: Unit
	var mode := "wide"
	var leader := false
	var max_hp := 1
	var color := Color.GRAY
	var line := ""
	var selected := false
	var promotable := false  # shows a green arrow (§4: a badge on any unit ready to promote)

	func setup(data: GameData, u: Unit, chip_mode: String, squad: Squad, colors: Dictionary) -> void:
		unit = u
		mode = chip_mode
		leader = squad != null and squad.leader == u
		max_hp = u.max_hp(data)
		promotable = not Progression.promotion_options(data, u).is_empty()
		var kind := Battle.base_kind(u.info(data)["front_attack" if u.row == "front" or squad == null else "back_attack"])
		color = colors.get(kind, Color.GRAY)
		var c: Dictionary = u.info(data)
		line = "Lv %d  ·  %s" % [u.level, c["front_attack"] if u.row == "front" or squad == null else c["back_attack"]]
		custom_minimum_size = {"compact": Vector2(62, 48), "wide": Vector2(272, 58), "slot": Vector2(148, 104)}[mode]
		mouse_default_cursor_shape = CURSOR_DRAG

	func _draw() -> void:
		var font := ThemeDB.fallback_font
		var r := Rect2(Vector2.ZERO, size)
		var dead := not unit.is_alive()
		draw_rect(r, color.darkened(0.55) if not dead else Color(0.12, 0.12, 0.13))
		draw_rect(Rect2(0, 0, 4, size.y), color if not dead else Color(0.3, 0.3, 0.32))
		draw_rect(r, Color.WHITE if selected else Color(0.32, 0.35, 0.4), false, 3.0 if selected else 2.0)
		var ink := Color.WHITE if not dead else Color(0.5, 0.5, 0.52)
		var share := float(unit.hp) / max_hp
		var fill := Color("#5fbf5a") if share > 0.5 else (Color("#e0b03a") if share > 0.25 else Color("#d9533f"))
		match mode:
			"compact":
				draw_string(font, Vector2(8, 20), unit.unit_class, HORIZONTAL_ALIGNMENT_LEFT, size.x - (22 if leader else 10), 11, ink)
				if leader:
					_star(Vector2(size.x - 10, 15), 6.0)
				if promotable:
					_arrow(Vector2(size.x - 10, 33), 5.0)
				draw_string(font, Vector2(8, 34), "Lv %d" % unit.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink.darkened(0.3))
				draw_rect(Rect2(6, size.y - 9, size.x - 12, 4), Color(0.05, 0.05, 0.06))
				draw_rect(Rect2(6, size.y - 9, (size.x - 12) * share, 4), fill)
			_:
				var w := size.x - 20
				draw_string(font, Vector2(12, 21), unit.unit_class, HORIZONTAL_ALIGNMENT_LEFT, w - (20 if leader else 0), 15, ink)
				if leader:
					_star(Vector2(size.x - 16, 16), 8.0)
				if promotable:
					_arrow(Vector2(size.x - (36 if leader else 16), 16), 7.0)
				draw_string(font, Vector2(12, 38), unit.name, HORIZONTAL_ALIGNMENT_LEFT, w, 12, ink.darkened(0.25))
				if mode == "slot":
					draw_string(font, Vector2(12, 56), line, HORIZONTAL_ALIGNMENT_LEFT, w, 12, ink.darkened(0.25))
				var y := size.y - 12
				draw_rect(Rect2(12, y, size.x - 24, 5), Color(0.05, 0.05, 0.06))
				draw_rect(Rect2(12, y, (size.x - 24) * share, 5), fill)
				if mode == "slot" or mode == "wide":
					draw_string(font, Vector2(size.x - 80, 38 if mode == "wide" else 74), "%d/%d" % [unit.hp, max_hp] if not dead else "Fallen",
							HORIZONTAL_ALIGNMENT_RIGHT, 68, 11, ink.darkened(0.2))

	## Ready to promote: a green up arrow.
	func _arrow(at: Vector2, r: float) -> void:
		var points := PackedVector2Array([at + Vector2(0, -r), at + Vector2(r, 0), at + Vector2(r * 0.4, 0), at + Vector2(r * 0.4, r),
				at + Vector2(-r * 0.4, r), at + Vector2(-r * 0.4, 0), at + Vector2(-r, 0)])
		draw_colored_polygon(points, Color("#7ee08a"))
		points.append(points[0])
		draw_polyline(points, Color(0.05, 0.2, 0.08), 1.0)

	## The leader's mark: a gold five-pointed star.
	func _star(at: Vector2, radius: float) -> void:
		var points := PackedVector2Array()
		for i in 10:
			var a := -PI / 2.0 + i * PI / 5.0
			points.append(at + Vector2(cos(a), sin(a)) * (radius if i % 2 == 0 else radius * 0.45))
		draw_colored_polygon(points, Color(1, 0.84, 0.35))
		points.append(points[0])
		draw_polyline(points, Color(0.25, 0.18, 0.05), 1.0)
