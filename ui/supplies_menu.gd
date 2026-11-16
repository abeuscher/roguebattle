class_name SuppliesMenu
extends Control
## Heal (squad menu; "Use item" until playtest round 13), anywhere on the map: a Herb
## for a hurt unit, a Revival Draught for a fallen one. Since round 19 the squad shows as
## Edit Units shows it, a tile per unit with its HP bar, the supplies left as icon × count. Standing in a temple the enemy
## doesn't hold, the paid healing and reviving is underneath. Cure potions are for
## battle and don't show here. Also opened from the encounter popup, before a battle
## starts (`battle` set; supplies only). A modal: 50% dark overlay.

signal closed

var state: GameState
var squad: Squad
var battle: Battle  # the battle about to start, when opened from the encounter popup
var _list := VBoxContainer.new()


func setup(game_state: GameState, s: Squad, before: Battle = null) -> void:
	state = game_state
	squad = s
	battle = before
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
	col.custom_minimum_size.x = 520
	_list.add_theme_constant_override("separation", 8)
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Heal  ·  %s" % s.name, 24), func(): closed.emit()))
	col.add_child(_list)
	_refresh()


## `acted`: after a supply or a temple heal was used. Once that leaves everyone well, the
## window closes and the view under it comes back with Heal greyed (round 19 before a
## fight; round 20 wherever it was opened from).
func _refresh(acted := false) -> void:
	for c in _list.get_children():
		c.queue_free()
	if acted and squad.all_well(state.data):
		if battle:
			Sound.event("all_better")
		closed.emit()
		return
	# What's left, as icon × count (round 19).
	var stock := HBoxContainer.new()
	stock.add_theme_constant_override("separation", 22)
	_list.add_child(stock)
	var kinds := []
	for id in state.data.items["consumables"]:
		var item: Dictionary = state.data.items["consumables"][id]
		if item["where"] not in ["map", "any"]:
			continue
		kinds.append(id)
		var have := HBoxContainer.new()
		have.add_theme_constant_override("separation", 6)
		have.tooltip_text = "%s: %s" % [item["name"], item["text"]]
		have.mouse_filter = MOUSE_FILTER_PASS
		have.add_child(ItemIcons.rect(id, 32))
		have.add_child(UiStyle.label("× %d" % int(state.army.supplies.get(id, 0)), 18, UiStyle.ACCENT))
		stock.add_child(have)
	var temple := battle == null and state.heals_here(squad)
	if temple:
		stock.add_child(UiStyle.label(state.place_label(state.building_at(squad.hex)) + ": healing for gold", 15, Color(0.75, 0.78, 0.84)))
	# The squad as Edit Units shows it: a tile per unit with its HP bar, front row above back,
	# and under each tile what can be done for it.
	var cols := squad.capacity(state.data)
	for u in squad.units:
		cols = maxi(cols, u.col + 1)
	for r in ["front", "back"]:
		_list.add_child(UiStyle.label("%s row" % r.capitalize(), 15, Color(0.75, 0.78, 0.84)))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_list.add_child(row)
		for c in cols:
			row.add_child(_tile(squad.at(r, c), kinds, temple))
	if squad.all_well(state.data):
		_list.add_child(UiStyle.label("Everyone in %s is at full health." % squad.name, 15, Color(0.6, 0.62, 0.66)))


## One unit's tile and its buttons (a supply that helps it; in a temple, healing for gold),
## or an empty slot.
func _tile(u: Unit, kinds: Array, temple: bool) -> Control:
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 4)
	# Room for the most buttons a tile can have (a supply, and in a temple its healing), kept
	# when they go, so the rows below don't jump up after a heal (round 20).
	col.custom_minimum_size = Vector2(148, 122 + (2 if temple else 1) * (44 + 4))
	if u == null:
		var empty := Panel.new()
		var style := UiStyle.box(Color(0.09, 0.1, 0.12), 3)
		style.set_border_width_all(1)
		style.border_color = Color(0.25, 0.27, 0.32)
		empty.add_theme_stylebox_override("panel", style)
		empty.custom_minimum_size = Vector2(148, 122)
		col.add_child(empty)
		return col
	var chip := EditUnits.Chip.new()
	chip.setup(state.data, u, "slot", squad, EditUnits.KIND_COLORS)
	chip.mouse_default_cursor_shape = CURSOR_ARROW
	chip.tooltip_text = "%s (%s), level %d. HP %d/%d." % [u.name, u.unit_class, u.level, u.hp, u.max_hp(state.data)]
	col.add_child(chip)
	for id in kinds:
		if not state.supply_helps(u, id):
			continue
		var item: Dictionary = state.data.items["consumables"][id]
		var b := UiStyle.button(item["name"], 148)
		b.icon = ItemIcons.item(id, 22)
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = int(state.army.supplies.get(id, 0)) <= 0
		b.tooltip_text = "None left." if b.disabled else "Use a %s: %s" % [item["name"], item["text"]]
		b.pressed.connect(func():
			if battle:
				state.use_supply_before_battle(battle, u, id)
			else:
				state.use_supply(u, id)
			_refresh(true))
		col.add_child(b)
	var cost := state.heal_cost(u) + state.revive_cost(u) if temple else 0
	if cost > 0:
		var b := UiStyle.button("%s  %d g" % ["Revive" if not u.is_alive() else "Heal to full", cost], 148)
		b.add_theme_font_size_override("font_size", 14)
		b.disabled = cost > state.gold
		b.tooltip_text = "Not enough gold." if b.disabled else "The temple heals or revives them to full HP."
		b.pressed.connect(func():
			state.restore(u)
			_refresh(true))
		col.add_child(b)
	return col


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
