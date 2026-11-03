class_name EditUnits
extends Control
## Edit Units (SPEC §4): the army overview (a 4×4 grid of squad cards) with the recruit
## pool in a gutter on the right; click a card for the squad detail (front and back rows,
## the selected unit's stats, leader and items). Drag units between squads, rows and the
## pool. Squads out in the field are locked until they're back at the Player Base.
## A modal: 50% dark overlay; the battlemap holds the clock while it's open.

signal closed

const KIND_COLORS := {"Melee": Color("#8a4a3a"), "Ranged": Color("#4f7a3a"), "Magic": Color("#3d5a9a"),
		"Breath": Color("#8a5a2a"), "Heal": Color("#9a8a3a"), "Buff": Color("#9a8a3a"), "Debuff": Color("#6a4a8a"),
		"Ward": Color("#3a7a8a"), "Dispel": Color("#3d5a9a")}
const SUPPORT := ["Heal", "Buff", "Debuff", "Ward", "Ranged", "Magic", "Dispel"]

var state: GameState
var army: Army
var data: GameData
var _squad: Squad  # the squad in detail view, or null for the overview
var _cell := -1
var _unit: Unit  # selected in the detail view
var _title := UiStyle.label("Edit Units", 26)
var _main := VBoxContainer.new()
var _pool := VBoxContainer.new()
var _pool_title := UiStyle.label("", 18)
var _status := UiStyle.label("", 16, UiStyle.ACCENT)
var _back: Button


func setup(game_state: GameState) -> void:
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
	_refresh()


## The recruit pool on the right; dropping a unit here sends it to the pool.
func _gutter() -> Control:
	var box := PanelContainer.new()
	box.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.1), 12))
	box.custom_minimum_size.x = 300
	box.set_drag_forwarding(Callable(), _can_drop.bind(-1, "", -1), _drop.bind(-1, "", -1))
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 8)
	box.add_child(col)
	col.add_child(_pool_title)
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
	_unit = _squad.leader if _squad else null
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
	_back.visible = _squad != null
	_title.text = "Edit Units" if _squad == null else "Edit Units  ·  #%d %s" % [_squad.id, _squad.name]
	if _squad:
		_main.add_child(_detail())
	else:
		_main.add_child(_overview())
	_pool_title.text = "Recruit pool (%d)" % army.pool.size()
	for u in army.pool:
		_pool.add_child(_chip(u, "wide", true))
	if army.pool.is_empty():
		_pool.add_child(UiStyle.label("Drag units here to take them out of a squad.", 14, Color(0.6, 0.62, 0.66)))


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
	col.add_child(head)
	var lead := "Leader: %s (%s)" % [s.leader.name, s.leader.unit_class] if s.leader else "No leader: add a unit that can lead"
	col.add_child(_quiet(UiStyle.label(lead, 13, Color(1, 0.88, 0.5) if s.leader else Color("#ff8a70"))))
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
			row.add_child(_chip(u, "compact", not locked))
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
	var facts := "%s  ·  speed %d  ·  slots %s / %d" % [s.travel_name(), s.speed_tier, _num(Squad.slots_filled(data, s.units)), s.capacity(data)]
	if locked:
		facts += "  ·  In the field: edit it back at the Player Base"
	box.add_child(UiStyle.label(facts, 16, Color("#e0a050") if locked else Color(0.75, 0.78, 0.82)))
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
	box.add_child(_unit_panel(locked))
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
		slot.add_child(_chip(u, "slot", not locked))
	return slot


func _unit_panel(locked: bool) -> Control:
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.08, 0.1), 16))
	panel.size_flags_vertical = SIZE_EXPAND_FILL
	var u := _unit
	if u == null:
		panel.add_child(UiStyle.label("Click a unit to see it.", 16, Color(0.6, 0.62, 0.66)))
		return panel
	var c: Dictionary = u.info(data)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	panel.add_child(row)
	# Who it is and its stats
	var who := VBoxContainer.new()
	who.custom_minimum_size.x = 380
	row.add_child(who)
	who.add_child(UiStyle.label(u.name, 24))
	who.add_child(UiStyle.label("%s  ·  stage %d  ·  level %d  ·  XP %d" % [u.unit_class, int(c["stage"]), u.level, u.xp], 16, Color(0.8, 0.82, 0.86)))
	var sq := army.squad_of(u)
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
	who.add_child(UiStyle.label("HP %d / %d" % [u.hp, u.max_hp(data)] + ("  (fallen: needs reviving)" if not u.is_alive() else ""), 16))
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
	does.custom_minimum_size.x = 440
	row.add_child(does)
	does.add_child(UiStyle.label("Front row: %s ×%d" % [c["front_attack"], int(c["front_count"])], 16))
	does.add_child(UiStyle.label("Back row: %s ×%d" % [c["back_attack"], int(c["back_count"])], 16))
	does.add_child(UiStyle.label("%s  ·  %s  ·  speed tier %d%s" % [c["terrain"], c["size"], int(c["speed_tier"]),
			"  ·  " + str(c["element"]) if c["element"] != null else ""], 15, Color(0.8, 0.82, 0.86)))
	if not c["traits"].is_empty():
		does.add_child(_wrapped("Traits: " + ", ".join(c["traits"]), 15))
	if c["leader_aura"] != null:
		does.add_child(_wrapped("Leader aura: %s. %s" % [c["leader_aura"], c.get("leader_aura_text", "")], 15))
	var next := data.next_classes(u.unit_class)
	does.add_child(_wrapped("Promotes to: %s (promotion arrives with levels)" % ", ".join(next) if not next.is_empty() else "Final stage", 15))
	# Items
	var gear := VBoxContainer.new()
	gear.add_theme_constant_override("separation", 8)
	row.add_child(gear)
	gear.add_child(UiStyle.label("Items", 18))
	for slot in data.items["slots"]:
		gear.add_child(_item_picker(u, slot, locked))
	return panel


func _item_picker(u: Unit, slot: String, locked: bool) -> Control:
	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 10)
	var l := UiStyle.label(slot.capitalize(), 15, Color(0.65, 0.68, 0.72))
	l.custom_minimum_size.x = 70
	line.add_child(l)
	var pick := OptionButton.new()
	pick.custom_minimum_size = Vector2(260, 38)
	var ids: Array[String] = [""]
	pick.add_item("None")
	if u.items.has(slot):
		ids.append(u.items[slot])
		pick.add_item(_item_label(u.items[slot]))
		pick.select(1)
	for id in army.choices(u, slot):
		if id != u.items.get(slot, ""):
			ids.append(id)
			pick.add_item("%s  (%d)" % [_item_label(id), int(army.stash[id])])
	pick.disabled = locked
	pick.item_selected.connect(func(i: int):
		army.equip(u, slot, ids[i])
		_refresh())
	line.add_child(pick)
	return line


func _item_label(id: String) -> String:
	var item: Dictionary = data.items["items"][id]
	var parts := []
	for s in item["stats"]:
		parts.append("%s %+d" % [s, int(item["stats"][s])])
	if item.has("range"):
		parts.append("range +%d" % int(item["range"]))
	return "%s: %s" % [item["name"], ", ".join(parts)]


# --- Units and dragging -------------------------------------------------------------

func _chip(u: Unit, mode: String, draggable: bool) -> Control:
	var chip := Chip.new()
	chip.setup(data, u, mode, army.squad_of(u), KIND_COLORS)
	chip.selected = u == _unit and mode != "compact"
	if draggable:
		chip.set_drag_forwarding(_drag.bind(u), Callable(), Callable())
	chip.tooltip_text = "%s (%s), level %d. HP %d/%d.%s" % [u.name, u.unit_class, u.level, u.hp, u.max_hp(data),
			" Drag to move." if draggable else ""]
	chip.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT and mode != "compact" and _squad:
			_unit = u
			_refresh())
	return chip


func _drag(_at: Vector2, u: Unit) -> Variant:
	var preview := Chip.new()
	preview.setup(data, u, "compact", null, KIND_COLORS)
	preview.modulate.a = 0.85
	set_drag_preview(preview)
	return {"unit": u}


func _can_drop(_at: Vector2, what: Variant, cell: int, _r: String, _c: int) -> bool:
	if not (what is Dictionary and what.has("unit")):
		return false
	var target: Squad = army.cells[cell] if cell >= 0 else null
	return target == null or state.can_edit(target)


## A drop on a card picks the row from the unit's attacks; a drop on a slot uses that slot.
func _drop(_at: Vector2, what: Variant, cell: int, r: String, c: int) -> void:
	var u: Unit = what["unit"]
	if r == "":
		r = preferred_row(data, u)
	if army.move(u, cell, r, c):
		_status.text = ""
		if _squad and u in _squad.units:
			_unit = u
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
	if key == KEY_U or (key == KEY_ESCAPE and _squad == null):
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

	func setup(data: GameData, u: Unit, chip_mode: String, squad: Squad, colors: Dictionary) -> void:
		unit = u
		mode = chip_mode
		leader = squad != null and squad.leader == u
		max_hp = u.max_hp(data)
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
		var edge := Color(1, 0.88, 0.5) if leader else (Color.WHITE if selected else Color(0.32, 0.35, 0.4))
		draw_rect(r, edge, false, 3.0 if selected else 2.0)
		var ink := Color.WHITE if not dead else Color(0.5, 0.5, 0.52)
		var share := float(unit.hp) / max_hp
		var fill := Color("#5fbf5a") if share > 0.5 else (Color("#e0b03a") if share > 0.25 else Color("#d9533f"))
		match mode:
			"compact":
				draw_string(font, Vector2(8, 20), unit.unit_class, HORIZONTAL_ALIGNMENT_LEFT, size.x - 10, 11, ink)
				draw_string(font, Vector2(8, 34), "Lv %d" % unit.level, HORIZONTAL_ALIGNMENT_LEFT, -1, 10, ink.darkened(0.3))
				draw_rect(Rect2(6, size.y - 9, size.x - 12, 4), Color(0.05, 0.05, 0.06))
				draw_rect(Rect2(6, size.y - 9, (size.x - 12) * share, 4), fill)
			_:
				var w := size.x - 20
				draw_string(font, Vector2(12, 21), unit.unit_class + ("  (leader)" if leader and mode == "wide" else ""), HORIZONTAL_ALIGNMENT_LEFT, w, 15, ink)
				draw_string(font, Vector2(12, 38), unit.name, HORIZONTAL_ALIGNMENT_LEFT, w, 12, ink.darkened(0.25))
				if mode == "slot":
					draw_string(font, Vector2(12, 56), line, HORIZONTAL_ALIGNMENT_LEFT, w, 12, ink.darkened(0.25))
					if leader:
						draw_string(font, Vector2(12, 74), "Leader", HORIZONTAL_ALIGNMENT_LEFT, w, 12, Color(1, 0.88, 0.5))
				var y := size.y - 12
				draw_rect(Rect2(12, y, size.x - 24, 5), Color(0.05, 0.05, 0.06))
				draw_rect(Rect2(12, y, (size.x - 24) * share, 5), fill)
				if mode == "slot" or mode == "wide":
					draw_string(font, Vector2(size.x - 80, 21 if mode == "wide" else 74), "%d/%d" % [unit.hp, max_hp] if not dead else "Fallen",
							HORIZONTAL_ALIGNMENT_RIGHT, 68, 11, ink.darkened(0.2))
