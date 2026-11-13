extends TestCase
## Quick start (user's playtest notes, 2026-11-13; rules.json quick_start).

var d := GameData.load_dir()


func _state(seed: int) -> GameState:
	var c := GameConfig.quick(d, seed)
	var s := GameState.new(d, MapGen.generate(d, c.seed, c.map_overrides()), GameLog.new(), c.game_settings())
	s.setup_army()
	s.place_enemies()
	return s


func test_settings() -> void:
	var c := GameConfig.quick(d, 5)
	var m: Dictionary = d.rules["quick_start"]["map"]
	for k in m:
		check_eq(c.values[k], m[k], "quick start sets %s" % k)
	check_eq(c.values["mode"], "quick", "Quick start mode")
	check(GameConfig.from_code(d, c.to_code()).values == c.values, "the share code keeps Quick start")


func test_small_map_has_its_buildings() -> void:
	var mins: Dictionary = d.rules["quick_start"]["buildings"]
	for seed in [1, 2, 3, 4]:
		var c := GameConfig.quick(d, seed)
		var map := MapGen.generate(d, seed, c.map_overrides())
		for type in mins:
			var n := map.buildings.filter(func(b): return b["type"] == type).size()
			check(n >= int(mins[type]), "seed %d: at least %d %s (%d)" % [seed, mins[type], type, n])


func test_army_is_ready_in_squads() -> void:
	var cfg: Dictionary = d.rules["quick_start"]
	for seed in [1, 2, 3]:
		var s := _state(seed)
		var cells := s.army.cells.filter(func(o): return o != null)
		check_eq(cells.size(), int(cfg["squads"]), "seed %d: squads ready" % seed)
		check_eq(s.player_squads().size(), 1, "only the Opinion Leader's squad starts on the map")
		check(s.opinion_leader == cells[0].leader, "squad 1 is the Opinion Leader's")
		var with_large := 0
		for q: Squad in cells:
			check(q.leader != null, "every squad has a leader")
			var front := q.units.filter(func(u: Unit): return Map1Setup._is_front_line(d, u.unit_class)).size()
			check(front >= int(cfg["front_min"]), "%s has %d front-line units" % [q.name, front])
			var healers := q.units.filter(func(u: Unit): return String(u.info(d)["role"]).to_lower().contains("healer")).size()
			check(healers >= int(cfg["healer_min"]), "%s has a healer" % q.name)
			if q.units.any(func(u: Unit): return u.info(d)["size"] == "Large"):
				with_large += 1
		check_eq(with_large, int(cfg["large_squads"]), "one squad has a monster")
		check_eq(s.army.pool.size(), int(cfg["serfs"]) + int(cfg["recruits"]), "Serfs and recruits in the pool")


func test_enemy_garrison_holds_the_nearest_town() -> void:
	for seed in [1, 2, 3]:
		var s := _state(seed)
		var home := s.map.hex_at(s.map.player_base)
		var towns := s.map.buildings.filter(func(b): return b["type"] == "town" and not b["hidden"])
		towns.sort_custom(func(a, b): return Hex.distance(home, s.map.hex_at(a["hex"])) < Hex.distance(home, s.map.hex_at(b["hex"])))
		var town: Dictionary = towns[0]
		check_eq(town["owner"], "enemy", "seed %d: the enemy holds the nearest town" % seed)
		check(town["shop"], "and it has a shop")
		check(Hex.distance(home, s.map.hex_at(town["hex"])) <= int(d.rules["quick_start"]["town_near_base"][1]), "close to home")
		var g := s.squads.filter(func(o: Squad): return o.side == "enemy" and o.hex == town["hex"])
		check_eq(g.size(), 1, "one enemy squad stands there")
		check_eq(g[0].role, "garrison", "as a garrison")
		check_eq(EnemyAI.target_hex(s, g[0]), -1, "which stays put")
