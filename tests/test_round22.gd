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


func test_ranged_attacks_on_the_map_hit_softer() -> void:
	var dealt := []
	for ranged in [false, true]:
		var st := _state()
		var a := st.add_squad("Ours", _at(st.map, 10, 3), [["Knight", "front"], ["Archer", "back"]])
		var e := st.add_squad("Them", _at(st.map, 12, 3), [["Knight", "front"]], "enemy")
		var rng := RandomNumberGenerator.new()
		rng.seed = 9
		var b := Battle.new(d, a, e, "plains", true, rng)
		b.ranged_only = ranged
		var archer: Unit = a.units[1]
		var hit := {}
		for i in 40:  # the first hit that lands
			b._attack(archer, "Ranged", e.units[0])
			var last: Dictionary = b.events[-1]
			if last.get("hit", false):
				hit = last
				break
		dealt.append(float(hit.get("damage", 0)))
	var share := float(d.rules["ranged_attack"]["damage"])
	check(dealt[0] > 0.0, "a normal hit lands")
	check(absf(dealt[1] - dealt[0] * share) <= 1.0, "a ranged attack on the map deals x%s (%s vs %s)" % [share, dealt[1], dealt[0]])
