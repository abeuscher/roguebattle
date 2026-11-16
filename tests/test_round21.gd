extends TestCase
## Playtest round 21 (2026-11-15).

var d := GameData.load_dir()


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": true, "hint": false, "hidden": false, "kind": "", "road": false}


func _state(settings := {}) -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 21
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("player_base", m.player_base))
	m.buildings.append(_b("enemy_base", m.enemy_base))
	m.buildings.append(_b("town", _at(m, 8, 3)))
	m.buildings.append(_b("town", _at(m, 20, 3)))
	return GameState.new(d, m, GameLog.new(), settings)


func test_heal_is_greyed_with_nothing_to_do() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 5, 5), [["Knight", "front"], ["Fighter", "front"]])
	st.army.supplies = {}
	check(st.heal_blocked(s).contains("full health"), "all well: nothing to do")
	s.units[1].hp = 1
	check(st.heal_blocked(s) != "", "hurt, in the open, no supplies: a dead end, so greyed")
	st.army.supplies = {"revive": 2}
	check(st.heal_blocked(s).contains("No supply you have helps"), "a revival helps nobody when no one has fallen")
	st.army.supplies = {"herb": 1}
	check_eq(st.heal_blocked(s), "", "a herb for the hurt one")
	st.army.supplies = {}
	s.hex = st.map.player_base
	check_eq(st.heal_blocked(s), "", "standing at the Player Base: healing for gold")
	check(st.heal_blocked(s, false) != "", "but not before a fight (supplies only)")


func test_the_opinion_leader_can_be_renamed() -> void:
	var st := _state()
	var s := st.add_squad("Ours", st.map.player_base, [["Knight", "front"]])
	st.army.cells[0] = s
	st.opinion_leader = s.leader
	check(not st.rename_leader("   "), "blank keeps the name")
	check(not st.rename_leader("x".repeat(int(d.rules["player_name_max"]) + 1)), "too long keeps the name")
	check(st.rename_leader("  Aldric Vane "), "renamed")
	check_eq(s.leader.name, "Aldric Vane", "trimmed")
	check(s.name.begins_with("Aldric"), "the squad's name follows its leader")


func test_a_leaderless_squad_cant_take_a_building() -> void:
	var st := _state()
	var town := _at(st.map, 8, 3)
	var s := st.add_squad("Raiders", town, [["Knight", "front"]], "enemy")
	s.leader.hp = 0
	for i in roundi(d.rules["capture"]["ticks"]) * 2:
		st._capture()
	check(st.building_at(town)["owner"] != "enemy", "no leader, no capture")


func test_a_leaderless_enemy_heads_only_for_its_base() -> void:
	var st := _state()
	var near := _at(st.map, 20, 3)
	st.building_at(near)["owner"] = "enemy"  # a refuge on the way that a battered squad would stop at
	var s := st.add_squad("Raiders", _at(st.map, 16, 3), [["Knight", "front"], ["Fighter", "front"]], "enemy")
	s.leader.hp = 0
	s.marching_home = true
	st._fall_back(s)
	check_eq(s.refuge, st.map.enemy_base, "home, not the nearer town")
	check_eq(s.path[s.path.size() - 1], st.map.enemy_base, "routed to the Enemy Base")


func test_a_leaderless_squad_steps_round_but_not_far() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 14, 3), [["Knight", "front"], ["Fighter", "front"]])
	s.leader.hp = 0
	s.marching_home = true
	var foe := st.add_squad("Foe", _at(st.map, 9, 3), [["Knight", "front"]], "enemy")
	st.debug_reveal = true
	st._crawl_home(s)
	var hexes := Array(s.path)
	check(not hexes.has(foe.hex), "goes round a seen enemy standing in the way")
	var straight := st.plan(s, PackedInt32Array([st.map.player_base])).size()
	check(s.path.size() <= straight * float(d.ai["dodge"]["crawl_detour"]), "a short detour")


func test_victory_pays_a_reward_and_shows_the_tally() -> void:
	var st := _state()
	st.building_at(_at(st.map, 8, 3))["owner"] = "player"
	st.stats["battles_won"] = 3
	var before := st.gold
	st._end_game("victory", "test")
	var r: Dictionary = d.rules["victory_reward"]
	var expected := st.income() * int(r["days_income"]) + 1 * int(r["per_building"])
	check_eq(st.gold - before, expected, "a day's income plus a sum per place held")
	var summary := st.end_summary()
	check_eq(int(summary["reward"]["total"]), expected, "on the end screen")
	check_eq(int(summary["battles_won"]), 3, "battles won counted")


func test_defeat_pays_no_reward() -> void:
	var st := _state()
	var before := st.gold
	st._end_game("defeat", "test")
	check_eq(st.gold, before, "nothing for a loss")
	check(st.end_summary()["reward"].is_empty(), "no reward section")


func test_stopping_in_the_open_asks_for_the_squad_list_tip() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 4, 5), [["Knight", "front"]])
	st.order_move(s, PackedInt32Array([_at(st.map, 6, 5)]))
	for i in 400:
		st.step()
		if not s.is_moving():
			break
	check(st.stopped_in_open, "stopped on open ground")
	st.stopped_in_open = false
	st.order_move(s, PackedInt32Array([_at(st.map, 8, 3)]))
	for i in 400:
		st.step()
		if not s.is_moving():
			break
	check(not st.stopped_in_open, "stopping on a town to liberate doesn't count")


func test_the_version_is_stamped() -> void:
	check(str(d.version.get("version", "")).begins_with("0."), "a 0.<session> version for the title screen")
	check(str(d.version.get("stamp", "")) != "", "and when it was stamped")
