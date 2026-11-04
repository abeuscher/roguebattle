extends TestCase
## Gold: noon income and upkeep, the liberation bonus, shops, Serfs, herbs, temple
## services and going broke (SPEC §15.1, §16).

var d := GameData.load_dir()


## A plains strip with the Player Base at (2, 3), a town at (8, 3) with a shop, a tower
## at (12, 3) and a temple at (16, 3), and the placeholder army.
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
	st.setup_army()
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
	# Worked by hand. Upkeep (§15.1: stage 1/2/3 = 5/10/20 a unit, all Small):
	#   squad 1: Knight 20 + Fighter 10 + Fighter 10 + Bowman 10 + Acolyte 10 = 60
	#   squad 2: Lancer 20 + Squire 10 + Squire 10 + Slinger 10 + Acolyte 10 = 60
	#   squad 3: Archer 20 + Soldier 20 + Bowman 10 + Apprentice 10 = 60
	#   pool:    Fighter 10 + Bowman 10 + Herald 20 + Serf 5 = 45            total 225
	# Squads 1 and 2 liberate the town and the tower in the morning: 2 × 100 × (0.5 + 50/100) = +200.
	# Noon: income 2 × 50 = +100, upkeep −225.  500 + 200 + 100 − 225 = 575.
	var st := _state()
	check_eq(st.army_upkeep(), 225, "the army's upkeep")
	_place(st, 0, 8)
	_place(st, 1, 12)
	check_eq(st.gold, 500, "starting gold")
	while st.clock.minute_of_day() != 12 * 60:
		st.step()
	check_eq(st.building_at(_at(st.map, 8, 3))["owner"], "player", "the town is ours")
	check_eq(st.building_at(_at(st.map, 12, 3))["owner"], "player", "and the tower")
	check_eq(st.income(), 100, "two buildings: 100 a day")
	check_eq(st.gold, 575, "the day's ledger")
	check(st.noon_report.contains("+100") and st.noon_report.contains("225"), st.noon_report)


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
	check(st.shop_at(s).is_empty(), "no shop while the town is enemy-held")
	town["owner"] = "player"
	check_eq(st.shop_at(s), town, "a shop once it's liberated")
	var stock := st.shop_stock(town)
	check_eq(stock.size(), int(d.rules["economy"]["shop_items"]), "a few items in stock")
	check_eq(st.shop_stock(town), stock, "the same stock each visit")
	var id: String = stock[0]
	var gold := st.gold
	var owned := st.army.items.size()
	check(st.buy_item(town, id), "buy an item")
	check_eq(st.gold, gold - st.item_price(id), "pay its price")
	check_eq(st.army.items.size(), owned + 1, "it joins the inventory")
	check_eq(st.shop_stock(town).size(), stock.size(), "and leaves the shop")
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
	check_eq(st.gold, 0, "upkeep you can't pay leaves you at zero")
