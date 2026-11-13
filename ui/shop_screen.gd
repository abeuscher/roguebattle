class_name ShopScreen
extends Control
## A shop (SPEC §4 Shop, §15.1, §16; overhauled in playtest round 12 to work like a
## familiar RPG shop), opened from the squad menu when the squad stands in a building
## with a shop. The shopkeeper greets you; Buy lists Serfs (towns and nomad camps),
## supplies and the shop's few items with their stock (restocked at noon); Sell lists
## the items nobody wears and the supplies you carry, for half their base price. Pick
## a line and the panel on the right says what it does, who in the squad can use it
## and how it compares to what they hold, with a quantity, your gold before and after,
## and the Buy or Sell button. In a temple, Healing heals or revives the squad. Prices
## follow reputation and the squad's Smuggler or Fence (§10).
## A modal: 50% dark overlay.

signal closed

const KIND_COLORS := {"weapon": Color("#8a4a3a"), "armor": Color("#56657a"), "jewelry": Color("#7a4f8a"),
		"supply": Color("#3f7a4a"), "serf": Color("#8a7346"), "service": Color("#3d6a8a")}
const MUTED := Color(0.62, 0.65, 0.7)
const LIST_WIDTH := 540.0
const DETAIL_WIDTH := 360.0

var state: GameState
var squad: Squad
var building: Dictionary
var _tab := ""  # "buy", "sell" or "heal"
var _picked := ""  # the key of the line picked (see _lines), kept across refreshes
var _qty := 1
var _gold := UiStyle.label("", 18, UiStyle.ACCENT)
var _tabs := HBoxContainer.new()
var _list := VBoxContainer.new()
var _detail := VBoxContainer.new()


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
	UiStyle.close_on_click(shade, center, func(): closed.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var where: String = b.get("name", state.data.buildings[b["type"]]["name"])
	_gold.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(UiStyle.title_row(UiStyle.label("%s  ·  %s" % [where, s.name], 24), func(): closed.emit(), "Close (Esc)", [_gold]))
	col.add_child(_keeper())
	_tabs.add_theme_constant_override("separation", 8)
	col.add_child(_tabs)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 18)
	col.add_child(body)
	var scroll := ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(LIST_WIDTH, 380)
	body.add_child(scroll)
	_list.add_theme_constant_override("separation", 6)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	scroll.add_child(_list)
	var side := PanelContainer.new()
	var look := UiStyle.box(Color(1, 1, 1, 0.04), 16)
	look.set_corner_radius_all(10)
	side.add_theme_stylebox_override("panel", look)
	side.custom_minimum_size.x = DETAIL_WIDTH
	body.add_child(side)
	_detail.add_theme_constant_override("separation", 10)
	side.add_child(_detail)
	_tab = "buy" if b.get("shop", false) else "heal"
	_refresh()


## The shopkeeper: a portrait slot, their name, and their greeting.
func _keeper() -> Control:
	var k := state.shopkeeper(building)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 14)
	var frame := PanelContainer.new()
	var look := UiStyle.box(Color("#2a2433"), 0)
	look.border_color = Color(UiStyle.ACCENT, 0.5)
	look.set_border_width_all(2)
	look.set_corner_radius_all(10)
	frame.add_theme_stylebox_override("panel", look)
	frame.custom_minimum_size = Vector2(64, 64)
	var initial := UiStyle.label(str(k["name"]).left(1), 30, UiStyle.ACCENT)  # the portrait slot, until there's art
	initial.add_theme_font_override("font", UiStyle.title_font())
	initial.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	initial.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(initial)
	row.add_child(frame)
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 2)
	words.size_flags_vertical = SIZE_SHRINK_CENTER
	var role := "keeper of the temple" if building["type"] == "temple" else "shopkeeper"
	words.add_child(UiStyle.label("%s, %s" % [k["name"], role], 17, UiStyle.TITLE))
	var says := UiStyle.label("“%s”" % k["greeting"], 16, MUTED)
	says.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	says.custom_minimum_size.x = LIST_WIDTH + DETAIL_WIDTH - 80
	words.add_child(says)
	row.add_child(words)
	return row


func _refresh() -> void:
	_gold.text = "Gold %d" % state.gold
	for c in _tabs.get_children():
		c.queue_free()
	var tabs := []
	if building["type"] == "temple":
		tabs.append(["heal", "Healing"])
	if building.get("shop", false):
		tabs.append_array([["buy", "Buy"], ["sell", "Sell"]])
	for t in tabs:
		_tabs.add_child(_tab_button(t[0], t[1]))
	for c in _list.get_children():
		c.queue_free()
	var lines := _lines()
	if _picked == "" or not lines.any(func(l): return l.get("key", "") == _picked):
		_picked = ""
		for l in lines:
			if l.has("key"):
				_picked = l["key"]
				break
		_qty = 1
	for l in lines:
		if l.has("heading"):
			_list.add_child(UiStyle.section(l["heading"]))
		elif l.has("note"):
			var n := UiStyle.label(l["note"], 15, MUTED)
			n.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			_list.add_child(n)
		else:
			_list.add_child(_line(l))
	_show_detail(lines.filter(func(l): return l.get("key", "") == _picked))


func _tab_button(id: String, text: String) -> Button:
	var b := UiStyle.button(text, 130, id == _tab)
	b.focus_mode = FOCUS_NONE
	b.pressed.connect(func():
		if _tab != id:
			_tab = id
			_picked = ""
			_refresh())
	return b


## The lines of the current tab, in order: {heading} and {note} entries, and goods:
## {key, kind, name, info, price, max, act}, where act(n) buys, sells or heals n.
func _lines() -> Array:
	var data := state.data
	var out := []
	match _tab:
		"heal":
			out.append({"heading": "Healing"})
			for u in squad.units:
				var cost := state.heal_cost(u) + state.revive_cost(u)
				if cost > 0:
					out.append({"key": "heal:%d" % squad.units.find(u), "kind": "service", "name": "%s %s" % ["Revive" if not u.is_alive() else "Heal", u.name],
							"info": "%s · HP %d/%d" % [u.unit_class, u.hp, u.max_hp(data)], "price": cost, "max": 1, "unit": u,
							"act": func(_n: int): state.restore(u)})
			if out.size() == 1:
				out.append({"note": "Everyone in %s is in good health." % squad.name})
		"buy":
			var stock := state.shop_stock(building)
			if state.sells_serfs(building):
				out.append({"heading": "Recruits"})
				var p := state.serf_price(squad)
				out.append({"key": "serf", "kind": "serf", "name": "Serf", "info": "Joins the recruit pool at the Player Base", "price": p, "max": 10,
						"act": func(n: int):
							for i in n:
								state.buy_serf(building, squad)})
			out.append({"heading": "Supplies"})
			for id in data.items["consumables"]:
				if stock.has(id):
					var c: Dictionary = data.items["consumables"][id]
					out.append({"key": "supply:" + id, "kind": "supply", "id": id, "name": c["name"], "info": c["text"], "price": state.supply_price(id, squad),
							"max": int(stock[id]), "left": int(stock[id]), "act": func(n: int):
								for i in n:
									state.buy_supply(building, id, squad)})
			out.append({"heading": "Equipment"})
			for id in stock:
				if data.items["items"].has(id):
					var it: Dictionary = data.items["items"][id]
					out.append({"key": "item:" + id, "kind": it["slot"], "id": id, "name": it["name"], "info": _stats_text(it["stats"]), "price": state.item_price(id, squad),
							"max": int(stock[id]), "left": int(stock[id]), "act": func(n: int):
								for i in n:
									state.buy_item(building, id, squad)})
		"sell":
			var free := {}  # item id -> the free items of it
			for item in state.free_items():
				if not free.has(item["id"]):
					free[item["id"]] = []
				free[item["id"]].append(item)
			out.append({"heading": "Equipment nobody wears"})
			for id in free:
				var it: Dictionary = data.items["items"][id]
				var items: Array = free[id]
				out.append({"key": "sell_item:" + id, "kind": it["slot"], "id": id, "name": it["name"], "info": _stats_text(it["stats"]), "price": state.sell_price(id),
						"max": items.size(), "left": items.size(), "act": func(n: int):
							for item in items.slice(0, n):
								state.sell_item(building, item)})
			if free.is_empty():
				out.append({"note": "Nothing to sell: worn equipment comes off in Edit Units first."})
			out.append({"heading": "Supplies"})
			var any := false
			for id in data.items["consumables"]:
				var have := int(state.army.supplies.get(id, 0))
				if have > 0:
					any = true
					var c: Dictionary = data.items["consumables"][id]
					out.append({"key": "sell_supply:" + id, "kind": "supply", "id": id, "name": c["name"], "info": c["text"], "price": state.sell_price(id),
							"max": have, "left": have, "act": func(n: int):
								for i in n:
									state.sell_supply(building, id)})
			if not any:
				out.append({"note": "No supplies to sell."})
	return out


## One good in the list: a swatch for its kind, its name and a line about it, how many
## (stock, or how many you have when selling), and the price. Click to pick it.
func _line(l: Dictionary) -> Control:
	var b := Button.new()
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(LIST_WIDTH - 16, 52)
	b.mouse_default_cursor_shape = CURSOR_POINTING_HAND
	var picked: bool = l["key"] == _picked
	for st in ["normal", "hover", "pressed"]:
		var look := StyleBoxFlat.new()
		look.bg_color = Color(1, 1, 1, 0.1 if picked else (0.07 if st == "hover" else 0.03))
		look.border_color = UiStyle.ACCENT if picked else Color(1, 1, 1, 0.12 if st == "hover" else 0.0)
		look.set_border_width_all(1)
		look.set_corner_radius_all(8)
		b.add_theme_stylebox_override(st, look)
	b.pressed.connect(func():
		_picked = l["key"]
		_qty = 1
		_refresh())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	row.offset_left = 10
	row.offset_right = -12
	row.mouse_filter = MOUSE_FILTER_IGNORE
	b.add_child(row)
	row.add_child(_swatch(l["kind"], l["name"], 34))
	var words := VBoxContainer.new()
	words.add_theme_constant_override("separation", 0)
	words.size_flags_horizontal = SIZE_EXPAND_FILL
	words.alignment = BoxContainer.ALIGNMENT_CENTER
	words.add_child(UiStyle.label(l["name"], 16))
	var info := UiStyle.label(l["info"], 13, MUTED)
	info.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	info.custom_minimum_size.x = 260
	words.add_child(info)
	row.add_child(words)
	if l.has("left"):
		var left: int = l["left"]
		var q := UiStyle.label(("×%d" % left) if left > 0 else "Sold out", 15, UiStyle.ACCENT if left > 0 else MUTED)
		q.size_flags_vertical = SIZE_SHRINK_CENTER
		row.add_child(q)
	var price := UiStyle.label("%d g" % l["price"], 16, UiStyle.TITLE)
	price.custom_minimum_size.x = 64
	price.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	price.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(price)
	for n in row.find_children("*", "Control", true, false):
		(n as Control).mouse_filter = MOUSE_FILTER_IGNORE
	return b


## A rounded swatch in the kind's color with the good's first letter (until there's art).
func _swatch(kind: String, title: String, px: int) -> Control:
	var frame := PanelContainer.new()
	var look := UiStyle.box(KIND_COLORS.get(kind, Color.GRAY), 0)
	look.set_corner_radius_all(int(px / 4.0))
	frame.add_theme_stylebox_override("panel", look)
	frame.custom_minimum_size = Vector2(px, px)
	frame.size_flags_vertical = SIZE_SHRINK_CENTER
	var letter := UiStyle.label(title.left(1), int(px * 0.5), Color(1, 1, 1, 0.9))
	letter.add_theme_font_override("font", UiStyle.title_font())
	letter.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	letter.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	frame.add_child(letter)
	return frame


## The right-hand panel for the picked good: what it is, who can use it, the quantity,
## the gold before and after, and the button.
func _show_detail(picked: Array) -> void:
	for c in _detail.get_children():
		c.queue_free()
	if picked.is_empty():
		var n := UiStyle.label("Pick something on the left." if _tab != "heal" else "Nothing to do here.", 15, MUTED)
		_detail.add_child(n)
		return
	var l: Dictionary = picked[0]
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	head.add_child(_swatch(l["kind"], l["name"], 48))
	var title := UiStyle.label(l["name"], 22, UiStyle.TITLE)
	title.add_theme_font_override("font", UiStyle.title_font())
	title.size_flags_vertical = SIZE_SHRINK_CENTER
	head.add_child(title)
	_detail.add_child(head)
	var about := UiStyle.label(_about(l), 15, Color(0.85, 0.87, 0.9))
	about.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	about.custom_minimum_size.x = DETAIL_WIDTH - 32
	_detail.add_child(about)
	if l.has("id") and state.data.items["items"].has(l["id"]):
		_detail.add_child(UiStyle.section("In %s" % squad.name))
		for t in _compare(l["id"]):
			var line := UiStyle.label(t, 14, MUTED)
			line.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			line.custom_minimum_size.x = DETAIL_WIDTH - 32
			_detail.add_child(line)
	var spacer := Control.new()
	spacer.size_flags_vertical = SIZE_EXPAND_FILL
	_detail.add_child(spacer)
	var selling := _tab == "sell"
	var each: int = l["price"]
	var most: int = l["max"] if selling else mini(l["max"], maxi(0, state.gold) / maxi(1, each))
	_qty = clampi(_qty, 1, maxi(1, most))
	if int(l["max"]) > 1:
		_detail.add_child(_quantity(most))
	var total := each * _qty
	var after := state.gold + total if selling else state.gold - total
	var sums := UiStyle.label("Gold %d  →  %d" % [state.gold, after], 17, UiStyle.ACCENT if after >= 0 else Color("#e0604a"))
	_detail.add_child(sums)
	var verb: String = {"buy": "Buy", "sell": "Sell", "heal": "Pay"}[_tab]
	var go := UiStyle.button("%s  %d g" % [verb, total], DETAIL_WIDTH - 32, true)
	go.disabled = most < 1 or (not selling and (total > state.gold or int(l.get("left", 1)) == 0))
	go.tooltip_text = "Sold out until noon." if int(l.get("left", 1)) == 0 else ("Not enough gold." if go.disabled and not selling else "")
	go.pressed.connect(func():
		l["act"].call(_qty)
		_qty = 1
		_refresh())
	_detail.add_child(go)


## The −, the count and the + of a quantity picker, up to `most`.
func _quantity(most: int) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.add_child(UiStyle.label("Quantity", 15, MUTED))
	var less := UiStyle.button("−", 44)
	less.disabled = _qty <= 1
	less.pressed.connect(func():
		_qty -= 1
		_refresh())
	row.add_child(less)
	var n := UiStyle.label(str(_qty), 18)
	n.custom_minimum_size.x = 30
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	n.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(n)
	var more := UiStyle.button("+", 44)
	more.disabled = _qty >= most
	more.pressed.connect(func():
		_qty += 1
		_refresh())
	row.add_child(more)
	return row


## What a good does, in a sentence or two.
func _about(l: Dictionary) -> String:
	var data := state.data
	match l["kind"]:
		"serf":
			return "A Serf to train up: joins the recruit pool at the Player Base, ready for Edit Units."
		"service":
			return "%s. Back to full HP." % l["info"]
		"supply":
			var c: Dictionary = data.items["consumables"][l["id"]]
			return "%s Used %s." % [c["text"], "in battle (the Items button)" if c["where"] == "battle" else "anywhere on the map (the squad menu)"]
	var it: Dictionary = data.items["items"][l["id"]]
	var who: String = {"melee": "Units with a melee attack can use it.", "archer": "Archers can use it."}.get(it["use"], "Anyone can use it.")
	return "%s, worn as %s. %s%s" % [_stats_text(it["stats"]), it["slot"], who, "  Very rare: only one on the map." if it.get("rare", false) else ""]


## Each unit in the squad: can they use the item, and what changes against what they
## wear in its slot.
func _compare(id: String) -> Array:
	var data := state.data
	var it: Dictionary = data.items["items"][id]
	var out := []
	for u in squad.units:
		var who := "%s (%s)" % [u.name.get_slice(" ", 0), u.unit_class]
		if not u.can_use(data, id):
			out.append("%s: can't use it" % who)
			continue
		var worn: Dictionary = u.items.get(it["slot"], {})
		if worn.is_empty():
			out.append("%s: %s (nothing worn there)" % [who, _stats_text(it["stats"])])
			continue
		var before: Dictionary = data.items["items"][worn["id"]]["stats"]
		var diff := {}
		for st in Unit.STATS:
			var d := int(it["stats"].get(st, 0)) - int(before.get(st, 0))
			if d != 0:
				diff[st] = d
		var worn_name: String = data.items["items"][worn["id"]]["name"]
		out.append("%s: %s against their %s" % [who, _stats_text(diff) if not diff.is_empty() else "no change", worn_name])
	return out


static func _stats_text(stats: Dictionary) -> String:
	var parts := []
	for st in stats:
		parts.append("%s %+d" % [st, int(stats[st])])
	return ", ".join(parts)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
