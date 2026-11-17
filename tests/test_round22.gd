extends TestCase
## Playtest round 22 (2026-11-16).

var d := GameData.load_dir()


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": true, "hint": false, "hidden": false, "kind": "", "road": false}


func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 22
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("player_base", m.player_base))
	m.buildings.append(_b("enemy_base", m.enemy_base))
	m.buildings.append(_b("town", _at(m, 8, 3)))
	return GameState.new(d, m, GameLog.new(), {})


func test_a_new_enemy_squad_never_shares_an_id() -> void:
	var st := _state()
	var a := st.add_squad("A", _at(st.map, 20, 3), [["Knight", "front"]], "enemy")
	var b := st.add_squad("B", _at(st.map, 21, 3), [["Knight", "front"]], "enemy")
	st.squads.erase(a)  # wiped out: off the board, waiting to come back
	st.returning.append({"squad": a, "at": 999})
	var c := st.add_squad("C", _at(st.map, 22, 3), [["Knight", "front"]], "enemy")
	check(c.id != b.id and c.id != a.id, "the newcomer's id is its own (it once took B's, and they shared a token)")
	var n := st.add_squad("N", _at(st.map, 23, 3), [["Knight", "front"]], "neutral")
	check(n.id not in [a.id, b.id, c.id], "neutrals too")
	check(c.id >= 100 and n.id >= 100, "above the player's cell numbers")


func test_poison_lingers_after_a_battle_until_cured() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", _at(st.map, 10, 3), [["Knight", "front"], ["Fighter", "front"]])
	var foe := st.add_squad("Them", _at(st.map, 11, 3), [["Soldier", "front"]], "enemy")
	var b := st.start_battle(ours, foe, foe)
	var hurt: Unit = ours.units[1]
	b._status[hurt]["poison"] = null
	foe.units[0].hp = 0
	st.end_battle(b)
	var cfg: Dictionary = d.rules["lingering_poison"]
	check_eq(hurt.poison_left, int(cfg["ticks"]), "still poisoned at the end: it lingers")
	check(not ours.all_well(d), "a poisoned squad isn't well, even at full HP")
	var before := hurt.hp
	for i in int(cfg["every"]):
		st._linger_poison()
	check(hurt.hp < before, "loses HP on the map")
	st.army.supplies = {"antidote": 1}
	check(st.supply_helps(hurt, "antidote"), "an Antidote helps on the map")
	check(st.use_supply(hurt, "antidote"), "used")
	check_eq(hurt.poison_left, 0, "cured")


func test_poison_can_kill_and_the_squad_heads_home() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", _at(st.map, 10, 3), [["Knight", "front"], ["Fighter", "front"]])
	var lead: Unit = ours.leader
	lead.hp = 1
	lead.poison_left = int(d.rules["lingering_poison"]["ticks"])
	for i in int(d.rules["lingering_poison"]["every"]):
		st._linger_poison()
	check(not lead.is_alive(), "it died of poison")
	check(ours.marching_home, "a squad that loses its leader to poison marches home")
	check(st.notices.any(func(n: String): return n.contains("poison")), "and you're told")
