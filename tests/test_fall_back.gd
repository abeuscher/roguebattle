extends TestCase
## Battered enemy squads fall back to the nearest town they hold, and squads that keep
## losing lose heart (user, 2026-11-13; ai.json refuge_types, battle.json broken).

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(40, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 3
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 38, 4)
	m.buildings.append({"type": "enemy_base", "hex": m.enemy_base, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	m.buildings.append({"type": "town", "hex": _at(m, 15, 4), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	st.map.buildings[1]["owner"] = "enemy"
	return st


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _battered(st: GameState, col: int) -> Squad:
	var s := st.add_squad("Warband", _at(st.map, col, 4), [["Soldier", "front"], ["Fighter", "front"], ["Squire", "front"], ["Bowman", "back"]], "enemy")
	s.role = "field"
	s.units[1].hp = 0
	s.units[2].hp = 0
	return s


func test_falls_back_to_the_nearest_town_it_holds() -> void:
	var st := _state()
	var s := _battered(st, 10)
	st.step()
	check(s.marching_home, "half its units down: it falls back")
	check_eq(s.refuge, _at(st.map, 15, 4), "to the town it holds, not the far base")
	for i in 200:
		st.step()
	check_eq(s.hex, _at(st.map, 15, 4), "and gets there")
	for i in int(d.enemy["base_revive_ticks"]) * 2 + 5:
		st.step()
	check_eq(s.living().size(), s.units.size(), "where its fallen come back")
	check(not s.marching_home, "then it's done falling back")


func test_a_town_with_your_squad_on_it_is_no_refuge() -> void:
	var st := _state()
	st.add_squad("Ours", _at(st.map, 15, 4), [["Knight", "front"]])
	var s := _battered(st, 10)
	check_eq(st.enemy_refuge(s), st.map.enemy_base, "the base instead")
	st.map.buildings[1]["owner"] = "neutral"
	st.squads.remove_at(0)
	check_eq(st.enemy_refuge(s), st.map.enemy_base, "nor a town it doesn't hold")


func test_losing_heart() -> void:
	var st := _state()
	var cfg: Dictionary = d.battle["broken"]
	var o := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]])
	var t := st.add_squad("Theirs", _at(st.map, 6, 4), [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]], "enemy")
	for i in int(cfg["losses"]) - 1:
		st._lost_battle(t)
	check(not st.is_broken(t), "not yet")
	var calm := st.start_battle(o, t, t)
	st._lost_battle(t)
	check(st.is_broken(t), "%d losses in a day: it loses heart" % int(cfg["losses"]))
	check(st.notices.any(func(n: String): return n.contains("lost heart")), "and you're told")
	var shaken := st.start_battle(o, t, t)
	check(shaken.broken[1] and not shaken.broken[0], "the battle knows which side")
	var front := t.units[0]
	check(shaken.expected_damage(o.units[0], front, "Melee") > calm.expected_damage(o.units[0], front, "Melee"), "its front row takes more")
	check(shaken.stat(front, "PDEF") <= calm.stat(front, "PDEF"), "no defense bonus")
	for i in int(cfg["window_ticks"]):
		st.clock.step()
	check(not st.is_broken(t), "it recovers once the losses are a day old")


## The last stand (user, 2026-11-14): your squad on the Enemy Base, a leaderless guard
## marching home goes straight at it rather than freezing beside it.
func test_a_squad_heads_home_even_with_your_squad_on_the_base() -> void:
	var st := _state()
	st.map.buildings[1]["owner"] = "neutral"  # no town to fall back to
	var ours := st.add_squad("Ours", st.map.enemy_base, [["Knight", "front"], ["Fighter", "front"]])
	ours.capture_wait = 1000000  # (it would take the base and win before they meet)
	var s := _battered(st, 30)
	s.role = "base_guard"
	s.leader.hp = 0
	s.marching_home = true
	st.step()
	var start := Hex.distance(st.map.hex_at(s.hex), st.map.hex_at(st.map.enemy_base))
	for i in 300:
		st.step()
		if st.pending:
			break
	check(st.pending != null or Hex.distance(st.map.hex_at(s.hex), st.map.hex_at(st.map.enemy_base)) < start, "it gets closer and meets your squad (from %d hexes)" % start)
	check(st.pending != null and ours in st.pending.sides and s in st.pending.sides, "a fight at the base")
