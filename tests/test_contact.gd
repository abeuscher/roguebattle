extends TestCase
## Enemy squads, contact, ranged map attacks and sight (SPEC §8.5, §11.1–11.2, §17).

var d := GameData.load_dir()


## A plains strip map with the player base on the left and the enemy base on the right.
func _state(w := 30, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 3
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _ours(st: GameState, col: int, row := 4, members := [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]]) -> Squad:
	return st.add_squad("Ours", _at(st.map, col, row), members)


func _theirs(st: GameState, col: int, row := 4, members := [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]]) -> Squad:
	return st.add_squad("Theirs", _at(st.map, col, row), members, "enemy")


func test_enemy_placement() -> void:
	var m := MapGen.generate(d, 11, {"size": "small"})
	var st := GameState.new(d, m, GameLog.new())
	st.place_enemies()
	var enemies := st.squads.filter(func(s: Squad): return s.side == "enemy")
	check_eq(enemies.size(), 10, "ten enemy squads (§17)")
	var roles := {}
	for s in enemies:
		roles[s.role] = roles.get(s.role, 0) + 1
		check_eq(s.units.size(), 4, "%s: four units" % s.name)
		check(not s.units.any(func(u: Unit): return Battle.base_kind(u.info(d)["back_attack" if u.row == "back" else "front_attack"]) == "Heal"),
				"%s: no healers" % s.name)
		check(s.id > 100, "enemy squads are numbered from 101")
	check_eq(roles, {"leader": 1, "base_guard": 1, "garrison": 4, "raider": 1, "wildcard": 3}, "roles")
	var leader: Squad = enemies.filter(func(s: Squad): return s.role == "leader")[0]
	check_eq(leader.hex, m.enemy_base, "the leader holds the Enemy Base")
	var hexes := {}
	for s in enemies:
		check(not hexes.has(s.hex), "one squad per hex")
		hexes[s.hex] = true
	for s in enemies.filter(func(s: Squad): return s.role == "garrison"):
		check(m.buildings.any(func(b): return b["hex"] == s.hex and b["type"] in ["town", "tower"]), "%s holds a town or tower" % s.name)


func test_adjacency_triggers_battle() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 14)
	st.step()
	check(st.pending == null, "no battle at a distance")
	st.order_move(ours, PackedInt32Array([_at(st.map, 13, 4)]))
	var ticks := 0
	while st.pending == null and ticks < 200:
		st.step()
		ticks += 1
	check(st.pending != null, "moving next to an enemy starts a battle")
	check_eq(Hex.distance(st.map.hex_at(ours.hex), st.map.hex_at(theirs.hex)), 1, "they're adjacent")
	check_eq(st.pending.attacker, 0, "the squad that moved in attacks")
	check(not ours.is_moving(), "orders stop at contact")
	var tick := st.clock.tick
	st.step()
	check_eq(st.clock.tick, tick, "the map holds while a battle is pending")
	var text := st.resolve_pending()
	check(text.contains("fought"), "a summary comes back: " + text)
	check(st.pending == null, "the battle is resolved")


func test_same_side_and_cooldown() -> void:
	var st := _state()
	_ours(st, 10)
	_ours(st, 11)
	st.step()
	check(st.pending == null, "friendly squads don't fight")
	var st2 := _state()
	var o := _ours(st2, 10)
	var t := _theirs(st2, 11)
	st2.step()
	check(st2.pending != null, "standing next to an enemy starts a battle")
	check_eq(st2.pending.attacker, 0, "if neither moved, your squad attacks")
	for u in t.units:  # make sure neither side can push the other away
		u.stats["STR"] = 0
	for u in o.units:
		u.stats["STR"] = 0
	st2.resolve_pending()
	if Hex.distance(st2.map.hex_at(o.hex), st2.map.hex_at(t.hex)) <= 1:
		st2.step()
		check(st2.pending == null, "a pair that just fought waits before fighting again")
		for i in int(d.enemy["contact_cooldown_ticks"]) + 1:
			if st2.pending:
				break
			st2.step()
		check(st2.pending != null, "and fights again after the cooldown if still adjacent")


func test_squads_wait_for_occupied_hexes() -> void:
	var st := _state()
	var a := _ours(st, 5)
	var b := _ours(st, 7)
	st.order_move(a, PackedInt32Array([_at(st.map, 9, 4)]))
	for i in 200:
		st.step()
	check(a.hex != b.hex, "a squad never walks onto another squad's hex")


func test_sight() -> void:
	var st := _state()
	var walker := _ours(st, 5)  # plains squad on plains: 7 + 1
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 8, "7, +1 on its travel terrain")
	st.map.terrain[_at(st.map, 10, 4)] = d.terrain_ids["mountain"]
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 6, "-2 into mountains")
	st.map.terrain[_at(st.map, 10, 4)] = d.terrain_ids["forest"]
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 7, "-1 into forest")
	st.map.terrain[walker.hex] = d.terrain_ids["swamp"]
	st.map.terrain[_at(st.map, 10, 4)] = d.terrain_ids["mountain"]
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 5, "7 - 1 - 2 = 4, clamped to 5")
	var flyer := st.add_squad("Wings", _at(st.map, 3, 2), [["Eagle Knight", "front"], ["Eagle Rider", "front"]])
	check(flyer.sky, "a flying squad")
	check_eq(st.sight(flyer, _at(st.map, 9, 2)), 10, "7 + 2 + 1 = 10, the cap")


func test_hidden_enemies() -> void:
	var st := _state(40)
	_ours(st, 2)
	var far := _theirs(st, 25)
	var near := _theirs(st, 8)
	check(not st.is_visible(far), "an enemy beyond sight is hidden")
	check(st.is_visible(near), "an enemy within sight shows")
	check(st.is_visible(st.squads[0]), "your own squads always show")


func test_hidden_sites_reveal() -> void:
	var st := _state(40)
	st.map.buildings.append({"type": "hidden_site", "hex": _at(st.map, 20, 4), "shop": false, "hint": false, "hidden": true, "kind": "treasure", "road": false})
	var ours := _ours(st, 2)
	st.step()
	check(st.revealed.is_empty(), "a hidden site out of sight stays hidden")
	ours.hex = _at(st.map, 15, 4)
	st.step()
	check(st.revealed.has(st.map.buildings.size() - 1), "it reveals once in sight")


func test_fire_range() -> void:
	var st := _state()
	var archers := _ours(st, 10)
	var near := _theirs(st, 12)
	var far := _theirs(st, 13)
	check_eq(st.fire_range(archers), 2, "2 hexes on flat ground")
	check(near in st.fire_targets(archers) and far not in st.fire_targets(archers), "targets within 2")
	st.map.terrain[archers.hex] = d.terrain_ids["mountain"]
	check_eq(st.fire_range(archers), 3, "3 from mountains")
	check(far in st.fire_targets(archers), "now 3 hexes away is in range")
	st.map.terrain[archers.hex] = d.terrain_ids["plains"]
	st.map.buildings.append({"type": "tower", "hex": archers.hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	check_eq(st.fire_range(archers), 3, "3 from a tower")
	var melee := _ours(st, 11, 7, [["Knight", "front"], ["Fighter", "front"]])
	check(not st.can_fire(melee), "a squad without ranged or magic units can't fire")
	check(st.fire_targets(melee).is_empty(), "so it has no targets")


func test_ranged_attack() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 12)
	var spot := theirs.hex
	var text := st.fire(ours, theirs)
	check(text.contains("fired on"), "a summary comes back: " + text)
	check_eq(theirs.hex, spot, "no push-back after a ranged attack")
	check(st.fire_targets(ours).is_empty(), "the squad must reload")
	check_eq(ours.fire_ready, st.clock.tick + int(d.rules["ranged_attack"]["cooldown_ticks"]), "120-tick cooldown")
	for i in int(d.rules["ranged_attack"]["cooldown_ticks"]):
		st.clock.step()
	check(not st.fire_targets(ours).is_empty(), "ready again after the cooldown")


func test_only_ranged_units_act() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 12)
	var b := st.start_battle(ours, theirs, theirs)
	b.ranged_only = true
	for side in 2:
		for u in b.sides[side].living():
			b._join(u)
	b.run()
	for e in b.events:
		if e["type"] == "attack":
			check(b.fires_at_range(e["unit"]), "%s (%s) acted in a ranged attack" % [e["unit"].name, e["unit"].unit_class])
	var out := b.finish()
	check_eq(out["pushed"], -1, "no push-back")
