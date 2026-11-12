extends TestCase
## Gold: noon income and upkeep, the liberation bonus, shops, Serfs, herbs, temple
## services and going broke (SPEC §15.1, §16).

var d := _data()


## This strip holds 2 towns and towers; counting 2 as the reference makes the map's
## upkeep scale 1, so the ledger below can be worked by hand (round 10's scaling has
## its own tests, which use the real reference).
func _data() -> GameData:
	var g := GameData.load_dir()
	g.rules["upkeep"]["reference_buildings"] = 2
	return g


## A plains strip with the Player Base at (2, 3), a town at (8, 3) with a shop, a tower
## at (12, 3) and a temple at (16, 3), and three known squads (not the random Map 1
## squads, so the ledger below can be worked by hand).
func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 8
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("player_base", _at(m, 2, 3)))
	m.buildings.append(_b("town", _at(m, 8, 3)))
	m.buildings[-1]["shop"] = true
	m.buildings.append(_b("tower", _at(m, 12, 3)))
	m.buildings.append(_b("temple", _at(m, 16, 3)))
	var st := GameState.new(d, m, GameLog.new())
	st.army.cells[0] = st._form(1, "", m.player_base, [["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"], ["Bowman", "back"], ["Acolyte", "back"]], "player")
	st.squads.append(st.army.cells[0])
	st.army.cells[1] = st._form(2, "", -1, [["Lancer", "front"], ["Squire", "front"], ["Squire", "front"], ["Slinger", "back"], ["Acolyte", "back"]], "player")
	st.army.cells[2] = st._form(3, "", -1, [["Archer", "back"], ["Soldier", "front"], ["Bowman", "back"], ["Apprentice", "back"]], "player")
	return st


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


## Puts an army squad on the map at a hex without paying to deploy it.
func _place(st: GameState, cell: int, col: int) -> Squad:
	var s: Squad = st.army.cells[cell]
	if s not in st.squads:
		st.squads.append(s)
	s.hex = _at(st.map, col, 3)
	return s


func test_a_days_ledger() -> void:
	# Worked by hand. Upkeep (§15.1: stage 1/2/3 = 5/10/20 a unit, all Small, scale 1 here):
	#   squad 1: Knight 20 + Fighter 10 + Fighter 10 + Bowman 10 + Acolyte 10 = 60
	#   squad 2: Lancer 20 + Squire 10 + Squire 10 + Slinger 10 + Acolyte 10 = 60
	#   squad 3: Archer 20 + Soldier 20 + Bowman 10 + Apprentice 10 = 60, but it stays at base: free
	# Starting gold: 2 days × 6 squads × 6 units × 10 = 720.
	# Squads 1 and 2 liberate the town and the tower in the morning: 2 × 100 × (0.5 + 50/100) = +200.
	# Noon: income 2 × 50 = +100, upkeep −120.  720 + 200 + 100 − 120 = 900.
	var st := _state()
	check_eq(st.army_upkeep(), 60, "only squad 1 is on the map")
	for c in 2:  # neutral squads, so liberating doesn't move reputation and the second bonus is 100 too
		for u in _place(st, c, 8 if c == 0 else 12).units:
			u.alignment = 50
	check_eq(st.army_upkeep(), 120, "squads 1 and 2 on the map; squad 3 at base is free")
	check_eq(st.gold, 720, "starting gold")
	while st.clock.minute_of_day() != 12 * 60:
		st.step()
	check_eq(st.building_at(_at(st.map, 8, 3))["owner"], "player", "the town is ours")
	check_eq(st.building_at(_at(st.map, 12, 3))["owner"], "player", "and the tower")
	check_eq(st.income(), 100, "two buildings: 100 a day")
	check_eq(st.gold, 900, "the day's ledger")
	check(st.noon_report.contains("+100") and st.noon_report.contains("120"), st.noon_report)


func test_liberation_bonus_scales_with_reputation() -> void:
	var st := _state()
	st.reputation = 100
	check_eq(st.liberation_bonus(), 150, "100 × (0.5 + 1)")
	st.reputation = 0
	check_eq(st.liberation_bonus(), 50, "100 × 0.5")


func test_shop() -> void:
	var st := _state()
	var s := _place(st, 0, 8)
	var town := st.building_at(s.hex)
	check_eq(st.shop_at(s), town, "a neutral town's shop is open (towns start neutral)")
	town["owner"] = "enemy"
	check(st.shop_at(s).is_empty(), "no shop while the town is enemy-held")
	town["owner"] = "player"
	check_eq(st.shop_at(s), town, "a shop once it's liberated")
	var stock := st.shop_stock(town)
	var items: Array = stock.keys().filter(func(k): return d.items["items"].has(k) and not d.items["items"][k].get("rare", false))
	check(items.size() >= 1 and items.size() <= int(d.rules["economy"]["shop_items"][1]), "a few items in stock")
	check_eq(st.shop_stock(town), stock, "the same stock each visit")
	var id: String = items[0]
	var left := int(stock[id])
	var gold := st.gold
	var owned := st.army.items.size()
	check(st.buy_item(town, id), "buy an item")
	check_eq(st.gold, gold - st.item_price(id), "pay its price")
	check_eq(st.army.items.size(), owned + 1, "it joins the inventory")
	check_eq(int(st.shop_stock(town)[id]), left - 1, "one fewer in the shop")
	check(st.buy_supply(town, "herb"), "buy a herb")
	check_eq(int(st.army.supplies["herb"]), 1, "one herb")
	var pool := st.army.pool.size()
	var serf := st.buy_serf(town)
	check(serf != null and serf.unit_class == "Serf", "hire a Serf at a town")
	check_eq(st.army.pool.size(), pool + 1, "into the recruit pool")
	st.gold = 10
	check(not st.buy_supply(town, "herb"), "not without the gold")
	s.hex = _at(st.map, 12, 3)
	st.building_at(s.hex)["owner"] = "player"
	st.building_at(s.hex)["shop"] = true
	check(not st.sells_serfs(st.shop_at(s)), "towers don't sell Serfs")


func test_herb() -> void:
	var st := _state()
	var u: Unit = st.army.cells[0].units[1]
	st.army.supplies["herb"] = 1
	check(not st.use_supply(u, "herb"), "a unit at full HP doesn't need it")
	u.hp = 1
	check(st.use_supply(u, "herb"), "use it")
	check_eq(u.hp, mini(31, u.max_hp(d)), "+30 HP")
	check_eq(int(st.army.supplies["herb"]), 0, "it's used up")


func test_temple_services() -> void:
	var st := _state()
	var s := _place(st, 0, 16)
	var u := s.units[1]
	u.hp = 1
	check(st.can_service(u) and st.restore(u), "pay to heal in a temple")
	s.hex = _at(st.map, 6, 3)
	u.hp = 1
	check(not st.restore(u), "not out in the open")


func test_going_broke() -> void:
	var st := _state()
	var s: Squad = st.army.cells[2]
	var sword := st.army.add_item("sword")
	st.army.equip(s.leader, sword)
	check(not st.sell_squad(s), "squads sell only when you're broke")
	st.gold = 0
	var value := st.sell_value(s)
	check_eq(value, 50 * (3 + 3 + 2 + 2), "50 × stage per unit")
	check(st.sell_squad(s), "sell it")
	check_eq(st.gold, value, "for its value")
	check(s not in st.army.squads(), "it leaves the army")
	check(st.army.holder(sword) == null, "its items go back to the inventory")
	st.gold = 0
	st.clock.tick = 12 * 60 - 1
	st.step()
	check_eq(st.gold, -st.upkeep(st.army.cells[0]), "upkeep you can't pay puts you in debt (round 9)")
	check_eq(st.debt_noons, 1, "the first noon in debt")


func test_the_noon_ledger_lists_every_gold_change() -> void:
	# The same day as test_a_days_ledger: two liberation bonuses, income, three squads' upkeep.
	var st := _state()
	for c in 2:
		for u in _place(st, c, 8 if c == 0 else 12).units:
			u.alignment = 50
	while st.clock.minute_of_day() != 12 * 60:
		st.step()
	var day := st.daily_ledger
	check(not day.is_empty(), "noon leaves a ledger for the UI")
	var total := 0
	for line in day["lines"]:
		total += int(line[1])
	check_eq(total, st.gold - st.starting_gold(), "the lines add up to the day's change in gold")
	check_eq(day["lines"].filter(func(l): return str(l[0]).begins_with("Liberation bonus")).size(), 2, "both liberation bonuses")
	check_eq(day["lines"].filter(func(l): return str(l[0]).begins_with("Upkeep")).size(), 2, "upkeep squad by squad, for the two on the map")
	check_eq(int(day["gold"]), st.gold, "gold now")
	check(st.ledger.is_empty(), "a fresh ledger for the next day")


func test_purchases_go_in_the_ledger() -> void:
	var st := _state()
	var town := st.building_at(_at(st.map, 8, 3))
	check(st.buy_supply(town, "herb"), "buy a herb")
	check_eq(st.ledger.back()[0], "Bought a Herb", "named")
	check_eq(int(st.ledger.back()[1]), -st.supply_price("herb"), "its price, as a cost")
