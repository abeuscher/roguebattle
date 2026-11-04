class_name ShopScreen
extends Control
## A shop (SPEC §4 Shop, §15.1, §16), opened from the squad menu when the squad stands
## in a building with a shop: Serfs at towns and nomad camps, herbs, and the shop's few
## items. In a temple it offers healing and revival for the squad instead.
## A modal: 50% dark overlay.

signal closed

var state: GameState
var squad: Squad
var building: Dictionary
var _list := VBoxContainer.new()
var _gold := UiStyle.label("", 18, UiStyle.ACCENT)


func setup(game_state: GameState, s: Squad, b: Dictionary) -> void:
	state = game_state
	squad = s
	building = b
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
	col.custom_minimum_size.x = 640
	panel.add_child(col)
	var head := HBoxContainer.new()
	col.add_child(head)
	var title := UiStyle.label("%s  ·  %s" % [state.data.buildings[b["type"]]["name"], s.name], 24)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	head.add_child(_gold)
	_list.add_theme_constant_override("separation", 8)
	col.add_child(_list)
	var close := UiStyle.button("Close (Esc)", 180)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)
	_refresh()


func _refresh() -> void:
	for c in _list.get_children():
		c.queue_free()
	_gold.text = "Gold %d" % state.gold
	var data := state.data
	if building["type"] == "temple":
		_heading("Services")
		var any := false
		for u in squad.units:
			var cost := state.heal_cost(u) + state.revive_cost(u)
			if cost > 0:
				any = true
				_row("%s (%s): HP %d/%d" % [u.name, u.unit_class, u.hp, u.max_hp(data)], "%s  %d g" % ["Revive" if not u.is_alive() else "Heal", cost], cost,
						func(): state.restore(u))
		if not any:
			_note("Everyone in %s is in good health." % squad.name)
	if not building.get("shop", false):
		return
	if state.sells_serfs(building):
		_heading("Recruits")
		var price := int(data.rules["economy"]["serf_price"])
		_row("Serf: joins the recruit pool at the Player Base", "Hire  %d g" % price, price, func(): state.buy_serf(building))
	_heading("Supplies")
	for id in data.items["consumables"]:
		var c: Dictionary = data.items["consumables"][id]
		_row("%s: %s  (you have %d)" % [c["name"], c["text"], int(state.army.supplies.get(id, 0))], "Buy  %d g" % int(c["price"]), int(c["price"]),
				func(): state.buy_supply(building, id))
	_heading("Items")
	var stock := state.shop_stock(building)
	if stock.is_empty():
		_note("Sold out.")
	for id in stock.duplicate():
		var item: Dictionary = data.items["items"][id]
		var parts := []
		for st in item["stats"]:
			parts.append("%s %+d" % [st, int(item["stats"][st])])
		_row("%s: %s" % [item["name"], ", ".join(parts)], "Buy  %d g" % state.item_price(id), state.item_price(id),
				func(): state.buy_item(building, id))


func _heading(text: String) -> void:
	_list.add_child(UiStyle.label(text, 18, Color(0.65, 0.68, 0.72)))


func _note(text: String) -> void:
	_list.add_child(UiStyle.label(text, 15, Color(0.6, 0.62, 0.66)))


func _row(text: String, button: String, price: int, buy: Callable) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	var l := UiStyle.label(text, 16)
	l.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(l)
	var b := UiStyle.button(button, 150)
	b.disabled = price > state.gold
	b.tooltip_text = "Not enough gold." if b.disabled else ""
	b.pressed.connect(func():
		buy.call()
		_refresh())
	row.add_child(b)
	_list.add_child(row)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
