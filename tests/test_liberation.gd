extends TestCase
## Liberation, building defense, daily rest, nomads and hints (SPEC §6.5, §7).

var d := GameData.load_dir()


## A plains strip with a town at (8, 3), a tower at (12, 3), a temple at (16, 3) and nomads at (20, 3).
func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 6
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("player_base", _at(m, 2, 3)))
	for e in [["town", 8], ["tower", 12], ["temple", 16], ["nomads", 20]]:
		m.buildings.append(_b(e[0], _at(m, e[1], 3)))
	return GameState.new(d, m, GameLog.new())


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _squad(st: GameState, col: int, members := [["Knight", "front"], ["Fighter", "front"], ["Acolyte", "back"]]) -> Squad:
	return st.add_squad("Ours", _at(st.map, col, 3), members)


func test_owners() -> void:
	var st := _state()
	check_eq(st.building_at(_at(st.map, 8, 3))["owner"], "neutral", "towns start neutral (2026-11-10)")
	check_eq(st.building_at(_at(st.map, 16, 3))["owner"], "neutral", "temples belong to no one")
	check_eq(st.building_at(_at(st.map, 2, 3))["owner"], "player", "the Player Base is yours")


func test_capture_takes_60_ticks() -> void:
	var st := _state()
	var s := _squad(st, 8)
	var town := st.building_at(s.hex)
	for i in 59:
		st.step()
	check_eq(town["owner"], "neutral", "not yet after 59 ticks")
	check(st.capture_progress(town) > 0.9, "almost there")
	st.step()
	check_eq(town["owner"], "player", "liberated after 60 ticks")


func test_sappers_capture_twice_as_fast() -> void:
	var st := _state()
	var s := _squad(st, 12, [["Knight", "front"], ["Sapper", "front"]])
	var tower := st.building_at(s.hex)
	for i in 30:
		st.step()
	check_eq(tower["owner"], "player", "a squad with a Sapper takes a tower in 30 ticks")


func test_only_ground_units_capture() -> void:
	var st := _state()
	var s := _squad(st, 8, [["Eagle Knight", "front"], ["Eagle Rider", "front"]])
	check(s.sky, "an all-flying squad")
	for i in 100:
		st.step()
	check_eq(st.building_at(s.hex)["owner"], "neutral", "can't liberate a town")
	var t := _squad(st, 12)
	for i in 30:
		st.step()
	st.order_move(t, PackedInt32Array([_at(st.map, 14, 3)]))
	for i in 40:
		st.step()
	check_eq(st.building_at(_at(st.map, 12, 3))["owner"], "neutral", "leaving resets the timer")
	check_eq(t.capture_ticks, 0.0, "back to zero")


func test_defense_by_alignment() -> void:
	var st := _state()
	var s := _squad(st, 8)
	for u in s.units:
		u.alignment = 80
	check_eq(s.alignment_band(d), "holy", "a holy squad")
	check_eq(st.building_defense(s), 0.15, "in a town it matches: 15%")
	s.hex = _at(st.map, 12, 3)
	check_eq(st.building_defense(s), 0.10, "in a tower it doesn't: 10%")
	s.hex = _at(st.map, 16, 3)
	check_eq(st.building_defense(s), 0.05, "temples give 5%")
	s.hex = _at(st.map, 2, 3)
	check_eq(st.building_defense(s), 0.15, "your own base 15%")
	s.hex = _at(st.map, 5, 3)
	check_eq(st.building_defense(s), 0.0, "open ground: none")
	var e := st.add_squad("Them", _at(st.map, 9, 3), [["Knight", "front"]], "enemy")
	s.hex = _at(st.map, 8, 3)
	var b := st.start_battle(s, e, s)
	check_eq(b.defense[0], 0.15, "the battle uses it")


func test_rest_per_day() -> void:
	var st := _state()
	var s := _squad(st, 16)  # temple: 5%
	var u := s.units[1]
	u.hp = 1
	var field := _squad(st, 5)  # open ground: nothing
	field.units[1].hp = 1
	st.clock.tick = GameClock.TICKS_PER_DAY - 1
	st.step()
	check_eq(u.hp, 1 + roundi(u.max_hp(d) * 0.05), "a temple heals 5% a day")
	check_eq(field.units[1].hp, 1, "no rest in the open")


func test_nomads_move() -> void:
	var st := _state()
	var start := _at(st.map, 20, 3)
	for spot in st.nomad_spots(start):
		var dist := Hex.distance(st.map.hex_at(start), st.map.hex_at(spot))
		check(dist >= 4 and dist <= 6, "4–6 hexes away (%d)" % dist)
	st.map.terrain[_at(st.map, 24, 3)] = d.terrain_ids["mountain"]
	check(_at(st.map, 24, 3) not in st.nomad_spots(start), "never onto mountains")
	var away := 0
	for i in 200:
		st._move_nomads()
		var b: Dictionary = st.map.buildings[4]
		away += 1 if b["away"] else 0
	check(away > 20 and away < 70, "about 20%% of moves stay out of sight (%d of 200)" % away)


func test_town_hint() -> void:
	var st := _state()
	var town: Dictionary = st.map.buildings[1]
	town["hint"] = true
	check_eq(st.hint(town), "", "nothing hidden nearby")
	st.map.buildings.append(_b("hidden_site", _at(st.map, 8, 8)))
	st.map.buildings[-1]["hidden"] = true
	check(st.hint(town).contains("south") and st.hint(town).contains("5 hexes"), st.hint(town))
