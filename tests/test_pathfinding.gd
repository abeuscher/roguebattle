extends TestCase

static var _data: GameData
static var _small: MapData
static var _medium: MapData


func _init() -> void:
	if _data == null:
		_data = GameData.load_dir()
		_small = MapGen.generate(_data, 4)
		_medium = MapGen.generate(_data, 4, {"size": "medium"})


## Random pairs of hexes the profile can stand on, `min_apart` hexes or more apart.
func _pairs(m: MapData, pf: Pathfinder, n: int, min_apart: int, travel := "", sky := false) -> Array:
	var rng := RandomNumberGenerator.new()
	rng.seed = 77
	var out := []
	while out.size() < n:
		var a := rng.randi_range(0, m.size() - 1)
		var b := rng.randi_range(0, m.size() - 1)
		if pf.hex_cost(a, travel, sky) < INF and pf.hex_cost(b, travel, sky) < INF \
				and Hex.distance(m.hex_at(a), m.hex_at(b)) >= min_apart:
			out.append([a, b])
	return out


func _valid(m: MapData, pf: Pathfinder, path: PackedInt32Array, a: int, b: int, travel := "", sky := false) -> bool:
	if path.is_empty() or path[0] != a or path[path.size() - 1] != b:
		return false
	for j in range(1, path.size()):
		if Hex.distance(m.hex_at(path[j - 1]), m.hex_at(path[j])) != 1 or pf.hex_cost(path[j], travel, sky) == INF:
			return false
	return true


func test_routes_are_valid_and_near_optimal() -> void:
	var pf := Pathfinder.new(_small, _data)
	for profile in [["", false], ["forest", false], ["", true]]:
		var worst := 1.0
		for pair in _pairs(_small, pf, 25, 40, profile[0], profile[1]):
			var path := pf.find(pair[0], pair[1], profile[0], profile[1])
			var flat := pf.find_flat(pair[0], pair[1], profile[0], profile[1])
			check(_valid(_small, pf, path, pair[0], pair[1], profile[0], profile[1]), "%s route is valid" % [profile])
			if not flat.is_empty():
				worst = maxf(worst, pf.route_cost(path, profile[0], profile[1]) / pf.route_cost(flat, profile[0], profile[1]))
		check(worst <= 1.12, "%s: two-step route within 12%% of the best (worst %.3f)" % [profile, worst])


func test_unreachable_and_trivial() -> void:
	var pf := Pathfinder.new(_small, _data)
	var deep := _small.terrain.find(_data.terrain_ids["deep"])
	var land := _small.player_base
	check(pf.find(land, deep).is_empty(), "ground squads can't reach deep water")
	check(not pf.find(land, deep, "", true).is_empty(), "flyers can")
	check_eq(pf.find(land, land), PackedInt32Array([land]), "route to self")


func test_roads_are_preferred() -> void:
	var pf := Pathfinder.new(_small, _data)
	var a := _small.player_base
	var b := -1
	for bld in _small.buildings:
		if bld["type"] == "town" and Hex.distance(_small.hex_at(bld["hex"]), _small.hex_at(a)) > 20:
			b = bld["hex"]
			break
	var path := pf.find(a, b)
	var on_road := 0
	for i in path:
		if _small.road[i]:
			on_road += 1
	check(on_road > path.size() / 2, "a route between road-linked buildings mostly uses roads (%d of %d)" % [on_road, path.size()])


func test_long_routes_are_fast() -> void:
	var pf := Pathfinder.new(_medium, _data)
	pf.find(0, 0)  # build the region graph first; it's built once per profile
	var pairs := _pairs(_medium, pf, 100, 300)
	var started := Time.get_ticks_msec()
	var found := 0
	for pair in pairs:
		if not pf.find(pair[0], pair[1]).is_empty():
			found += 1
	var ms := Time.get_ticks_msec() - started
	check_eq(found, 100, "every long route found")
	check(ms < 25000, "100 long routes on a medium map in %d ms (budget 25000)" % ms)
	print("    100 long medium routes: %d ms" % ms)


func test_squad_moves_at_tier_speed() -> void:
	var m := MapData.new(20, 3)
	for i in m.size():
		m.terrain[i] = _data.terrain_ids["plains"]
	m.seed = 1
	m.settings = {"preset": "continent", "size": "small"}
	var state := GameState.new(_data, m, GameLog.new())
	var s := state.add_squad("Test", m.index_of(Hex.from_offset(Vector2i(0, 1))), "", 2)
	var goal := m.index_of(Hex.from_offset(Vector2i(10, 1)))
	check(state.order_move(s, PackedInt32Array([goal])), "order accepted")
	check_eq(s.path.size(), 10, "ten hexes to go")
	var per_hex := 0.6 * 4.8  # tier 2: 0.6 s per hex at 4.8 ticks per second
	var ticks := 0
	while s.is_moving() and ticks < 1000:
		state.step()
		ticks += 1
	check_eq(ticks, ceili(per_hex * 10 - 0.0001), "ten plains hexes at tier 2")
	check_eq(s.hex, goal, "arrived")
	check(state.log.filtered("map", s.id).size() == 2, "order and arrival logged")
	# Forest costs x1.5 for a non-native, and roads x0.75.
	m.terrain[m.index_of(Hex.from_offset(Vector2i(11, 1)))] = _data.terrain_ids["forest"]
	m.road[m.index_of(Hex.from_offset(Vector2i(12, 1)))] = 1
	state.pathfinder = Pathfinder.new(m, _data)  # costs are cached per profile
	check_eq(state.step_ticks(s, m.index_of(Hex.from_offset(Vector2i(11, 1)))), per_hex * 1.5, "forest step")
	check_eq(state.step_ticks(s, m.index_of(Hex.from_offset(Vector2i(12, 1)))), per_hex * 0.75, "road step")
