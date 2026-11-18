extends TestCase
## Scrolls, the map's magic (user, 2026-11-16 and 2026-11-18): Invisibility, Decoy and
## Teleport, read from the squad menu; one from each temple's first liberation, and some
## shops sell one.

var d := GameData.load_dir()


## A plains strip, your base on the left, a town at (8, 4) and a temple at (16, 4).
func _state(w := 40, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 3
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	m.buildings.append(_b("player_base", m.player_base))
	m.buildings.append(_b("town", _at(m, 8, 4)))
	m.buildings.append(_b("temple", _at(m, 16, 4)))
	return GameState.new(d, m, GameLog.new())


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false, "owner": "neutral"}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _ours(st: GameState, col: int) -> Squad:
	return st.add_squad("Ours", _at(st.map, col, 4), [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]])


func _theirs(st: GameState, col: int, role := "field") -> Squad:
	var s := st.add_squad("Theirs", _at(st.map, col, 4), [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]], "enemy")
	s.role = role
	return s


func test_a_temple_gives_a_scroll_the_first_time() -> void:
	var st := _state()
	var s := _ours(st, 16)
	for i in 200:
		st.step()
	var temple := st.building_at(_at(st.map, 16, 4))
	check_eq(temple["owner"], "player", "the temple is taken")
	var entry: Dictionary = st.liberations[-1]
	check(str(entry.get("scroll", "")).begins_with("scroll_"), "its window names a scroll: %s" % entry.get("scroll", ""))
	check_eq(st.scrolls().size(), 1, "and it's in your supplies")
	temple["owner"] = "enemy"
	st.liberations.clear()
	for i in 200:
		st.step()
	check(st.liberations.size() == 1 and str(st.liberations[0].get("scroll", "")) == "", "taken again: no second scroll")
	check_eq(int(st.scrolls()[0][1]), 1, "still one")


func test_some_shops_sell_one_scroll() -> void:
	var st := _state()
	var with_scroll := 0
	var shops := 40
	for i in shops:
		var b := _b("town", i)
		b["shop"] = true
		var stock := st.shop_stock(b)
		var kinds: Array = stock.keys().filter(func(id): return data_scroll(id))
		check(kinds.size() <= 1, "at most one scroll kind a shop")
		with_scroll += kinds.size()
		check(stock.has("herb"), "the usual supplies are still there")
	var share := with_scroll / float(shops)
	check(share > 0.1 and share < 0.7, "about %.0f%% of shops carry one (%.0f%% here)" % [100 * float(d.rules["economy"]["shop_scroll_chance"]), 100 * share])


func data_scroll(id: String) -> bool:
	return d.items["consumables"].has(id) and d.items["consumables"][id].has("scroll")


func test_invisibility_slips_past_the_enemy() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 14)
	theirs.follow = ours
	check(not st.read_invisibility(ours), "no scroll, no reading")
	st.army.supplies["scroll_invisibility"] = 1
	check(st.read_invisibility(ours), "read")
	check(st.unseen(ours) and st.army.supplies["scroll_invisibility"] == 0, "unseen, the scroll spent")
	check(theirs.follow == null, "a squad chasing it loses it")
	st.debug_freeze_ai = true
	st.order_move(ours, PackedInt32Array([_at(st.map, 20, 4)]))
	for i in 300:
		st.step()
		check(st.pending == null, "no fight passing the enemy")
		if st.pending:
			break
	check_eq(ours.hex, _at(st.map, 20, 4), "it walks straight past and through")
	check(st.unseen(ours), "still unseen")
	st.order_move(ours, PackedInt32Array([theirs.hex]))
	var ticks := 0
	while st.pending == null and ticks < 300:
		st.step()
		ticks += 1
	check(st.pending != null, "ordered onto the enemy, it fights")
	check(not st.unseen(ours), "and shows itself")


func test_invisibility_wears_off_and_ends_on_taking_a_place() -> void:
	var st := _state()
	var ours := _ours(st, 8)
	st.army.supplies["scroll_invisibility"] = 2
	st.read_invisibility(ours)
	st.step()
	check(not st.unseen(ours), "starting to take the town shows it")
	var away := _ours(st, 30)
	st.read_invisibility(away)
	st.clock.tick += int(d.items["consumables"]["scroll_invisibility"]["ticks"])
	check(not st.unseen(away), "and it wears off")


func test_decoy_sends_an_enemy_away() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 15)
	var lord := _theirs(st, 17, "leader")
	check(theirs in st.decoy_targets() and lord not in st.decoy_targets(), "the enemy's leader can't be fooled")
	st.army.supplies["scroll_decoy"] = 2
	d.items["consumables"]["scroll_decoy"]["chance"] = 0.0
	var r := st.read_decoy(ours, theirs)
	check(r["read"] and not r["worked"], "it can simply fail")
	check(not theirs.is_moving() and st.army.supplies["scroll_decoy"] == 1, "the scroll spent, nothing else")
	d.items["consumables"]["scroll_decoy"]["chance"] = 1.0
	r = st.read_decoy(ours, theirs)
	d.items["consumables"]["scroll_decoy"]["chance"] = 0.6
	check(r["worked"], "fooled")
	var dest := theirs.path[theirs.path.size() - 1]
	var from := st.map.hex_at(ours.hex)
	check(Hex.distance(st.map.hex_at(dest), from) > Hex.distance(st.map.hex_at(_at(st.map, 15, 4)), from), "it marches away from your squad")
	check_eq(Hex.distance(st.map.hex_at(dest), st.map.hex_at(_at(st.map, 15, 4))), int(d.items["consumables"]["scroll_decoy"]["hexes"]), "about 12 hexes off")
	for i in 30:
		st.step()
	check(theirs.is_moving() and theirs.path[theirs.path.size() - 1] == dest, "and keeps going, no plans of its own")
	check(theirs.decoy_until > st.clock.tick + int(d.items["consumables"]["scroll_decoy"]["ticks"]), "waiting there a while after it arrives")


func test_teleport_to_a_place_you_hold() -> void:
	var st := _state()
	var ours := _ours(st, 30)
	st.army.supplies["scroll_teleport"] = 1
	var town := _at(st.map, 8, 4)
	check(town not in st.teleport_targets(ours), "not to a town you don't hold")
	st.building_at(town)["owner"] = "player"
	check(town in st.teleport_targets(ours), "a town you hold")
	ours.path = PackedInt32Array([_at(st.map, 31, 4)])
	check(st.read_teleport(ours, town), "read")
	check(ours.hex == town and not ours.is_moving(), "there at once, its march dropped")
	check_eq(int(st.army.supplies["scroll_teleport"]), 0, "the scroll spent")
	check(not st.read_teleport(ours, _at(st.map, 16, 4)), "none left")


func test_scrolls_are_not_used_on_units_or_in_battle() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	st.army.supplies["scroll_teleport"] = 1
	check(not st.supply_helps(ours.units[0], "scroll_teleport"), "not a unit's supply")
	check_eq(d.items["consumables"]["scroll_teleport"]["where"], "scroll", "read only from the squad menu")
	var e := _theirs(st, 11)
	st.pending = st.start_battle(ours, e, e)
	check(st.scroll_block(ours) != "", "not while a fight waits")
