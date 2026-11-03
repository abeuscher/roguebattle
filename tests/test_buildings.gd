extends TestCase

const SINGLE_LANDMASS := ["continent", "highlands", "river_valley", "deep_forest", "tundra", "volcanic"]

static var _data: GameData
static var _maps := {}


func _init() -> void:
	if _data == null:
		_data = GameData.load_dir()


func _map(preset := "continent", seed := 1, extra := {}) -> MapData:
	var key := "%s/%d/%s" % [preset, seed, JSON.stringify(extra)]
	if not _maps.has(key):
		var overrides := {"preset": preset}
		overrides.merge(extra)
		_maps[key] = MapGen.generate(_data, seed, overrides)
	return _maps[key]


func _of_type(m: MapData, type: String) -> Array:
	return m.buildings.filter(func(b): return b["type"] == type)


func _key(m: MapData, i: int) -> String:
	return _data.terrains[m.terrain[i]]["key"]


func test_counts_follow_density() -> void:
	var m := _map()
	var counts: Dictionary = _data.mapgen["building_counts"]
	for type in ["town", "temple"]:
		check_eq(_of_type(m, type).size(), int(counts[type]), "%s count at medium density" % type)
	check(_of_type(m, "tower").size() >= int(counts["tower"]), "tower count at medium density (more may cover regions)")
	check_eq(_of_type(m, "player_base").size(), 1, "one player base")
	check_eq(_of_type(m, "enemy_base").size(), 1, "one enemy base")
	check_eq(_of_type(m, "hidden_site").size(), int(_data.mapgen["hidden_site_counts"]["medium"]), "hidden sites")
	var sparse := _map("continent", 1, {"building_density": "none", "hidden_sites": "none"})
	check_eq(_of_type(sparse, "town").size(), 0, "no towns at density none")
	check_eq(_of_type(sparse, "hidden_site").size(), 0, "no hidden sites at none")


func test_spacing() -> void:
	var gap := int(_data.mapgen["building_spacing"])
	for preset in SINGLE_LANDMASS:
		var m := _map(preset)
		var spots: Array[Vector2i] = []
		for b in m.buildings:
			spots.append(m.hex_at(b["hex"]))
		for l in m.lairs:
			spots.append(m.hex_at(l["hex"]))
		var too_close := 0
		for a in spots.size():
			for b in range(a + 1, spots.size()):
				if Hex.distance(spots[a], spots[b]) < gap:
					too_close += 1
		check_eq(too_close, 0, "%s: buildings and lairs closer than %d hexes" % [preset, gap])


func test_quadrants_balanced() -> void:
	for seed in [1, 2, 3]:
		var m := _map("continent", seed)
		for type in ["town", "temple"]:
			var q := [0, 0, 0, 0]
			for b in _of_type(m, type):
				var i: int = b["hex"]
				q[(1 if i % m.width >= m.width / 2 else 0) + (2 if i / m.width >= m.height / 2 else 0)] += 1
			check(q.max() - q.min() <= 1, "seed %d %s per quadrant %s" % [seed, type, q])


func test_terrain_rules() -> void:
	for preset in SINGLE_LANDMASS:
		var m := _map(preset)
		for b in m.buildings:
			var key := _key(m, b["hex"])
			check(key in _data.buildings[b["type"]]["terrains"], "%s: %s on %s" % [preset, b["type"], key])
			if b["type"] == "town" or b["type"] == "nomads":
				check(key != "mountain", "%s: %s on a mountain" % [preset, b["type"]])


func test_bases_on_opposite_sides() -> void:
	for seed in [1, 2, 3]:
		var m := _map("continent", seed)
		var px := Hex.to_offset(m.hex_at(m.player_base)).x
		var ex := Hex.to_offset(m.hex_at(m.enemy_base)).x
		check(px < m.width * 0.3, "seed %d: player base in the west (col %d)" % [seed, px])
		check(ex > m.width * 0.7, "seed %d: enemy base in the east (col %d)" % [seed, ex])
	var north := _map("continent", 1, {"spawn_side": "north"})
	check(Hex.to_offset(north.hex_at(north.player_base)).y < north.height * 0.3, "spawn side north")


func test_bases_reachable_on_foot() -> void:
	for preset in ["continent", "islands", "archipelago", "floating_isles", "highlands", "river_valley"]:
		var m := _map(preset)
		var comp: PackedInt32Array = m.components(MapGen.ground_passable(m, _data))[0]
		check(comp[m.player_base] >= 0 and comp[m.player_base] == comp[m.enemy_base], "%s: bases reachable on foot" % preset)


func test_roads_connect_visible_buildings() -> void:
	for preset in SINGLE_LANDMASS:
		var m := _map(preset)
		var comp: PackedInt32Array = m.components(m.road)[0]
		var networks := {}
		for b in m.buildings:
			if b["type"] in MapPlaces.VISIBLE:
				check(m.road[b["hex"]] == 1, "%s: %s has no road" % [preset, b["type"]])
				networks[comp[b["hex"]]] = true
		check_eq(networks.size(), 1, "%s: road networks linking visible buildings" % preset)


func test_roads_stay_off_sea_lava_and_cliffs() -> void:
	for preset in ["continent", "river_valley", "volcanic", "highlands", "floating_isles"]:
		var m := _map(preset)
		var river := {}
		for path in m.rivers:
			for i in path:
				river[i] = true
		for i in m.size():
			if not m.road[i]:
				continue
			var key := _key(m, i)
			check(key not in ["lava", "cliff"], "%s: road on %s" % [preset, key])
			if key in ["deep", "shallow"]:
				check(river.has(i), "%s: road on open water at %s" % [preset, m.hex_at(i)])
				if not river.has(i):
					return


func test_no_roads_setting() -> void:
	var m := _map("continent", 1, {"road_coverage": "none"})
	var land_roads := 0
	for i in m.size():
		if m.road[i] and not _data.terrains[m.terrain[i]].get("impassable", false):
			land_roads += 1
	check_eq(land_roads, 0, "road coverage none leaves only river bridges")
	check(_map("continent", 1, {"road_coverage": "full"}).road.count(1) > _map().road.count(1), "full coverage adds roads")


func test_hidden_sites_off_road() -> void:
	for seed in [1, 2]:
		var m := _map("continent", seed)
		for b in _of_type(m, "hidden_site"):
			check(b["hidden"], "hidden site is hidden")
			check(b["kind"] in _data.buildings["hidden_site"]["kinds"], "hidden site kind")
			if not b["road"]:
				check(m.road[b["hex"]] == 0, "hidden site without a road lies off-road")


func test_lairs() -> void:
	var m := _map()
	var gap := int(_data.mapgen["lair_road_gap"])
	var near_road := m.distance_from(m.road, gap - 1)
	check(m.lairs.size() >= int(_data.mapgen["lair_counts"]["low"]), "lairs at low density")
	for l in m.lairs:
		check(_key(m, l["hex"]) in _data.mapgen["lair_terrains"][l["home"]], "lair sits in its home terrain")
		check(l["danger"] >= 0.0 and l["danger"] <= 1.0, "danger in 0..1")
	# Lairs from the density count keep away from roads; region-cover lairs may not.
	var far := m.lairs.filter(func(l): return near_road[l["hex"]] < 0)
	check(far.size() >= int(_data.mapgen["lair_counts"]["low"]), "lairs away from roads")
	var near: Dictionary = m.lairs.reduce(func(a, l): return a if a["danger"] <= l["danger"] else l)
	var deep: Dictionary = m.lairs.reduce(func(a, l): return a if a["danger"] >= l["danger"] else l)
	check(Hex.distance(m.hex_at(near["hex"]), m.hex_at(m.player_base)) < Hex.distance(m.hex_at(deep["hex"]), m.hex_at(m.player_base)),
			"danger rises with distance from the player base")


func test_sizable_regions_covered() -> void:
	for preset in SINGLE_LANDMASS:
		var m := _map(preset)
		var region := MapPlaces.terrain_regions(m, _data)
		var sizes := {}
		for r in region:
			if r >= 0:
				sizes[r] = sizes.get(r, 0) + 1
		var covered := {}
		for b in m.buildings:
			covered[region[b["hex"]]] = true
		for l in m.lairs:
			covered[region[l["hex"]]] = true
		var threshold := float(_data.mapgen["sizable_region_share"]) * m.size()
		var missing := sizes.keys().filter(func(r): return sizes[r] >= threshold and not covered.has(r))
		check(missing.is_empty(), "%s: %d sizable regions without a building or lair" % [preset, missing.size()])


func test_buildings_seeded() -> void:
	var a := MapGen.generate(_data, 9)
	var b := MapGen.generate(_data, 9)
	check_eq(JSON.stringify(a.buildings), JSON.stringify(b.buildings), "same seed, same buildings")
	check(a.road == b.road, "same seed, same roads")
