extends TestCase
## Shop stock and restocking, the Revival Draught, cure potions in battle (SPEC §15.1,
## user's playtest notes 2026-11-08), and player options.

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 8
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append({"type": "town", "hex": _at(m, 8, 3), "shop": true, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	st.map.buildings[0]["owner"] = "player"
	st.army.cells[0] = st._form(1, "", _at(m, 8, 3), [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]], "player")
	st.squads.append(st.army.cells[0])
	st.gold = 100000
	return st


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _cures() -> Array:
	return d.items["consumables"].keys().filter(func(id): return d.items["consumables"][id].has("cures"))


func test_stock_has_quantities_and_a_few_cures() -> void:
	var st := _state()
	var stock := st.shop_stock(st.map.buildings[0])
	check_eq(int(stock["herb"]), int(d.items["consumables"]["herb"]["stock"]), "a full shelf of herbs")
	check_eq(int(stock["revive"]), int(d.items["consumables"]["revive"]["stock"]), "and revives")
	check_eq(_cures().filter(func(id): return stock.has(id)).size(), int(d.rules["economy"]["shop_cures"]), "a few of the cure potions")
	for id in stock:
		if d.items["items"].has(id):
			var lo := 1 if d.items["items"][id].get("rare", false) else int(d.rules["economy"]["item_stock"][0])
			check(int(stock[id]) >= lo and int(stock[id]) <= int(d.rules["economy"]["item_stock"][1]), "%s: in stock" % id)


func test_sells_out_then_restocks_at_noon() -> void:
	var st := _state()
	var town := st.map.buildings[0]
	var full := int(st.shop_stock(town)["herb"])
	for i in full:
		check(st.buy_supply(town, "herb"), "buy herb %d" % (i + 1))
	check(not st.buy_supply(town, "herb"), "sold out")
	check_eq(int(st.army.supplies["herb"]), full, "carrying them all")
	var item: String = st.shop_stock(town).keys().filter(func(k): return d.items["items"].has(k))[0]
	while int(st.shop_stock(town)[item]) > 0:
		st.buy_item(town, item)
	check(not st.buy_item(town, item), "items sell out too")
	while st.clock.minute_of_day() != GameClock.NOON:
		st.step()
	check_eq(int(st.shop_stock(town)["herb"]), full, "herbs back at noon")
	check(int(st.shop_stock(town)[item]) > 0, "items back at noon")


func test_a_cure_the_shop_lacks_cant_be_bought() -> void:
	var st := _state()
	var town := st.map.buildings[0]
	var missing: Array = _cures().filter(func(id): return not st.shop_stock(town).has(id))
	check(not missing.is_empty(), "not every cure is stocked")
	check(not st.buy_supply(town, missing[0]), "can't buy one that isn't on the shelf")


func test_revival_draught_anywhere_on_the_map() -> void:
	var st := _state()
	var s: Squad = st.army.cells[0]
	var u := s.units[1]
	st.army.supplies["revive"] = 1
	check(not st.use_supply(u, "revive"), "no use on a living unit")
	u.hp = 0
	check(not st.use_supply(u, "herb"), "a herb can't raise the fallen")
	check(st.use_supply(u, "revive"), "revive")
	check_eq(u.hp, u.max_hp(d), "back at full HP")
	check_eq(int(st.army.supplies["revive"]), 0, "used up")


func test_reviving_the_leader_cancels_the_march_home() -> void:
	var st := _state()
	var s: Squad = st.army.cells[0]
	s.leader.hp = 0
	s.marching_home = true
	st.order_move(s, PackedInt32Array([st.map.player_base]))
	st.army.supplies["revive"] = 1
	check(st.use_supply(s.leader, "revive"), "revive the leader")
	check(not s.marching_home and not s.is_moving(), "the march home is off")


func test_cure_potion_in_battle() -> void:
	var st := _state()
	var foe := st.add_squad("Foe", _at(st.map, 9, 3), [["Soldier", "front"], ["Fighter", "front"]], "enemy")
	var b := st.start_battle(st.army.cells[0], foe, foe)
	var u: Unit = st.army.cells[0].units[0]
	check(st.battle_supply_uses(b).is_empty(), "nothing to cure, nothing to use")
	b.add_status(u, "poison")
	check(st.battle_supply_uses(b).is_empty(), "no antidote carried")
	st.army.supplies["antidote"] = 2
	st.army.supplies["eye_drops"] = 1
	var uses := st.battle_supply_uses(b)
	check_eq(uses.size(), 1, "only the antidote fits")
	check_eq(uses[0][0], "antidote", "antidote")
	check(not st.use_battle_supply(b, "eye_drops", u), "eye drops don't cure poison")
	check(st.use_battle_supply(b, "antidote", u), "the antidote works")
	check(not b.has_status(u, "poison"), "poison gone")
	check_eq(int(st.army.supplies["antidote"]), 1, "one antidote left")
	check_eq(int(st.army.supplies["eye_drops"]), 1, "eye drops untouched")


func test_options_defaults_and_saving() -> void:
	var path := "user://test_options.json"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(path)
	var v := PlayerOptions.load_values(d, path)
	check_eq(v["battle_wait_for_fight"], true, "battles wait for Fight by default")
	v["battle_wait_for_fight"] = false
	PlayerOptions.save_values(v, path)
	check_eq(PlayerOptions.load_values(d, path)["battle_wait_for_fight"], false, "the choice is kept")
	DirAccess.remove_absolute(path)
