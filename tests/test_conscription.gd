extends TestCase
## Single map mode's conscription and Warbands, and its longer enemy builds (SPEC §18,
## ROADMAP M4 session 21).

var d := GameData.load_dir()


## A plains strip with a town at (8, 3), a tower at (12, 3) and the bases at either end.
func _state(mode := "single") -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 6
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("player_base", m.player_base))
	m.buildings.append(_b("enemy_base", m.enemy_base))
	for e in [["town", 8], ["tower", 12]]:
		m.buildings.append(_b(e[0], _at(m, e[1], 3)))
	return GameState.new(d, m, GameLog.new(), {"mode": mode, "xp_rate": 150, "squad_cap": 6})


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


## A player squad at a column, in army cell 0 so it counts toward the army's median level.
func _ours(st: GameState, col: int) -> Squad:
	var s := st.add_squad("Ours", _at(st.map, col, 3), [["Knight", "front"], ["Fighter", "front"], ["Acolyte", "back"]])
	st.army.cells[0] = s
	return s


func _take(st: GameState) -> void:
	for i in int(d.rules["capture"]["ticks"]):
		st.step()


func _serf() -> String:
	return d.lines[d.lines.keys().filter(func(k: String): return k.is_valid_int())[0]][0][0]


func test_a_town_sends_fighters_and_a_serf() -> void:
	for seed_ in 6:
		var st := _state()
		st.rng = RngStreams.new(seed_)
		var s := _ours(st, 8)
		var before := st.army.pool.size()
		_take(st)
		check_eq(st.building_at(s.hex)["owner"], "player", "liberated (seed %d)" % seed_)
		var got: Array = st.liberations[-1]["recruits"]
		check(got.size() >= 2 and got.size() <= 4, "1-3 fighters and a Serf, got %d (seed %d)" % [got.size(), seed_])
		check_eq(st.army.pool.size(), before + got.size(), "they join the recruit pool")
		check_eq(got.filter(func(u: Unit): return u.unit_class == _serf()).size(), 1, "exactly one Serf (seed %d)" % seed_)
		check(got.slice(0, got.size() - 1).all(func(u: Unit): return u.unit_class != _serf()), "the rest are fighters")


func test_the_pool_without_a_leader_gets_one() -> void:
	var st := _state()
	_ours(st, 8)
	check(st.army.pool.is_empty(), "the pool starts empty")
	_take(st)
	var got: Array = st.liberations[-1]["recruits"]
	check(got[0].info(d)["can_lead"], "the first fighter is a leader when no one in the pool can lead")


func test_a_pool_with_a_leader_gets_plain_fighters() -> void:
	var st := _state()
	_ours(st, 8)
	st.army.pool.append(Unit.roll(d, "Knight", st.rng.get_stream("test"), st.names))
	_take(st)
	var got: Array = st.liberations[-1]["recruits"]
	check(got.all(func(u: Unit): return not u.info(d)["can_lead"]), "no leader added: the pool already has one")


func test_fighters_come_at_the_armys_median_level() -> void:
	var st := _state()
	var s := _ours(st, 8)
	for k in s.units.size():
		s.units[k].level = [2, 5, 7][k]
	check_eq(st.median_level("player"), 5, "median of 2, 5, 7")
	_take(st)
	var got: Array = st.liberations[-1]["recruits"]
	for u in got:
		check_eq(u.level, 1 if u.unit_class == _serf() else 5, "%s's level" % u.unit_class)


func test_towers_and_campaign_mode_pay_nothing() -> void:
	var st := _state()
	_ours(st, 12)
	_take(st)
	check_eq(st.building_at(_at(st.map, 12, 3))["owner"], "player", "tower liberated")
	check(st.liberations[-1]["recruits"].is_empty(), "a tower sends no conscripts")
	var camp := _state("campaign")
	_ours(camp, 8)
	_take(camp)
	check(camp.liberations[-1]["recruits"].is_empty(), "the campaign start has no conscription")


func test_each_town_pays_each_side_once() -> void:
	var st := _state()
	var s := _ours(st, 8)
	_take(st)
	var town := st.building_at(s.hex)
	town["owner"] = "neutral"
	_take(st)
	check_eq(town["owner"], "player", "taken again")
	check(st.liberations[-1]["recruits"].is_empty(), "the second time pays nothing")
	town["owner"] = "player"
	st.squads.erase(s)
	st.add_squad("Them", s.hex, [["Knight", "front"], ["Fighter", "front"]], "enemy")
	_take(st)
	check_eq(town["owner"], "enemy", "the enemy takes it")
	var n := st.enemy_pool.size()
	check(n >= 1 and n <= 2, "the enemy gets 1-2 recruits, got %d" % n)
	check(st.enemy_pool.all(func(u: Unit): return u.unit_class != _serf()), "and no Serf")
	town["owner"] = "player"
	_take(st)
	check_eq(st.enemy_pool.size(), n, "the enemy is paid once too")


func test_a_full_enemy_pool_forms_a_warband() -> void:
	var st := _state()
	st.enemy_start_squads = 2
	var r := st.rng.get_stream("test")
	for c in ["Fighter", "Squire", "Knight", "Bowman", "Fighter", "Squire"]:
		st.enemy_pool.append(Unit.roll(d, c, r, st.names))
	st._form_warbands()
	var bands := st.squads.filter(func(o: Squad): return o.side == "enemy")
	check_eq(bands.size(), 1, "one Warband formed")
	var w: Squad = bands[0]
	check_eq(w.units.size(), int(d.rules["single_map"]["conscription"]["warband_size"]), "a squad's worth")
	check_eq(w.leader.unit_class, "Knight", "led by the one who can lead")
	check_eq([w.role, w.hex], ["field", st.map.enemy_base], "a field squad at the Enemy Base")
	check_eq(st.enemy_pool.size(), 1, "the spare stays in the pool")


func test_warbands_stop_at_the_cap() -> void:
	var st := _state()
	st.enemy_start_squads = 2  # cap: 3
	for k in 3:
		st.add_squad("Them %d" % k, st.map.enemy_base, [["Knight", "front"]], "enemy")
	var r := st.rng.get_stream("test")
	for c in ["Knight", "Fighter", "Squire", "Bowman", "Fighter"]:
		st.enemy_pool.append(Unit.roll(d, c, r, st.names))
	st._form_warbands()
	check_eq(st.squads.size(), 3, "no Warband past 1.5x the starting squads")
	check_eq(st.enemy_pool.size(), 5, "the recruits wait")


func test_enemy_builds_are_longer_in_single_map_mode() -> void:
	var single := _state()
	single.place_enemies()
	for s in single.squads:
		check(s.units.size() >= 5 and s.units.size() <= 6, "%s has %d units" % [s.name, s.units.size()])
	var camp := _state("campaign")
	camp.place_enemies()
	for s in camp.squads:
		check_eq(s.units.size(), 4, "campaign builds stay at 4")
