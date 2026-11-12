extends TestCase
## Playtest round 11, map, flavor and economy (ROADMAP M4 session 34): temples belong
## to the Gods of Perinea, one card per building, and no noon on day 1.

var d := GameData.load_dir()


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func test_every_temple_has_a_god_and_its_name() -> void:
	var m := MapGen.generate(d, 3, {"preset": "continent"})
	var temples := m.buildings.filter(func(b): return b["type"] == "temple" or b.get("kind", "") == "secret_temple")
	check(not temples.is_empty(), "the map has temples")
	for b in temples:
		check(d.gods["gods"].has(b.get("god", "")), "a god of Perinea: %s" % b.get("god", "none"))
		check_eq(b.get("name", ""), "Temple of %s" % d.gods["gods"][b["god"]]["name"], "named for it")
	var again := MapGen.generate(d, 3, {"preset": "continent"})
	check_eq(again.buildings.filter(func(b): return b.has("god")).map(func(b): return b["god"]), temples.map(func(b): return b["god"]), "seeded with the map")
	var st := GameState.new(d, m, GameLog.new())
	var t: Dictionary = m.buildings.filter(func(b): return b["type"] == "temple")[0]
	check_eq(st.where(t["hex"]), "the " + t["name"], "the game calls it \"the Temple of …\"")
	check_eq(d.gods["gods"].size(), 12, "twelve gods")
	for id in d.gods["gods"]:
		var g: Dictionary = d.gods["gods"][id]
		check(g["domain"] != "" and g["appearance"] != "" and g["manifestation"] != "", "%s has a domain, appearance and manifestation" % g["name"])


func _town_state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 6
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 28, 4)
	m.buildings.append({"type": "town", "hex": _at(m, 10, 4), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false, "name": "Testford"})
	var st := GameState.new(d, m, GameLog.new())
	st.debug_freeze_ai = true
	return st


func _take(st: GameState) -> void:
	for i in int(d.rules["capture"]["ticks"]) + 1:
		st.step()


func test_a_recaptured_building_draws_no_card() -> void:
	var st := _town_state()
	var s := st.add_squad("Ours", _at(st.map, 10, 4), [["Knight", "front"]])
	var cards := st.cards.size()
	var gold := st.gold
	_take(st)
	check_eq(st.cards.size(), cards + 1, "the first liberation draws a card")
	check(st.gold > gold, "and pays the bonus")
	st.building_at(s.hex)["owner"] = "enemy"  # lost
	gold = st.gold
	st.liberations.clear()
	_take(st)
	check_eq(st.building_at(s.hex)["owner"], "player", "retaken")
	check_eq(st.cards.size(), cards + 1, "no second card")
	check(st.gold > gold, "the bonus gold still comes")
	check_eq(str(st.liberations[0]["card"]), "", "the window shows no card")


func test_no_noon_on_day_one() -> void:
	var st := _town_state()
	st.add_squad("Ours", _at(st.map, 3, 4), [["Knight", "front"], ["Fighter", "front"]])
	var gold := st.gold
	while st.clock.minute_of_day() != 12 * 60:
		st.step()
	check_eq(st.clock.day(), 1, "noon of day 1")
	check_eq(st.gold, gold, "no upkeep taken")
	check(st.daily_ledger.is_empty(), "and no ledger")
	st.step()
	while st.clock.minute_of_day() != 12 * 60:
		st.step()
	check_eq(st.clock.day(), 2, "noon of day 2")
	check(not st.daily_ledger.is_empty(), "the first ledger")
	check(st.gold < gold, "upkeep paid")
