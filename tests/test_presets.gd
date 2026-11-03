extends TestCase

const PRESETS := ["continent", "islands", "archipelago", "floating_isles", "highlands",
		"river_valley", "deep_forest", "tundra", "volcanic"]

static var _data: GameData
static var _maps := {}


func _init() -> void:
	if _data == null:
		_data = GameData.load_dir()


func _map(preset: String, seed := 1) -> MapData:
	var key := "%s/%d" % [preset, seed]
	if not _maps.has(key):
		_maps[key] = MapGen.generate(_data, seed, {"preset": preset})
	return _maps[key]


func _count(m: MapData, key: String) -> int:
	return m.terrain.count(_data.terrain_ids[key])


func _is_ground(t: int) -> bool:
	var info: Dictionary = _data.terrains[t]
	return not info.get("water", false) and not info.get("impassable", false)


func _land_count(m: MapData) -> int:
	var n := 0
	for t in m.terrain:
		if _is_ground(t):
			n += 1
	return n


## Landmasses, ignoring roads and counting every non-water hex as land.
func _landmasses(m: MapData, min_size: int) -> int:
	var land := PackedByteArray()
	land.resize(m.size())
	for i in m.size():
		land[i] = 0 if _data.terrains[m.terrain[i]].get("water", false) or m.terrain[i] == _data.terrain_ids["air_gap"] else 1
	var sizes: PackedInt32Array = MapGen.components(m, land)[1]
	return Array(sizes).filter(func(s): return s >= min_size).size()


func test_all_land_reachable_on_foot() -> void:
	for preset in PRESETS:
		for seed in [1, 2]:
			var m := _map(preset, seed)
			var comp: PackedInt32Array = MapGen.components(m, MapGen.ground_passable(m, _data))[0]
			var regions := {}
			for i in m.size():
				if _is_ground(m.terrain[i]):
					regions[comp[i]] = true
			check_eq(regions.size(), 1, "%s seed %d: ground regions" % [preset, seed])


func test_presets_are_seeded() -> void:
	for preset in PRESETS:
		check(MapGen.generate(_data, 1, {"preset": preset}).terrain == _map(preset).terrain,
				"%s: same seed rebuilds the same map" % preset)


func test_islands() -> void:
	for seed in [1, 2, 3]:
		var n := _landmasses(_map("islands", seed), 150)
		check(n >= 2 and n <= 4, "islands seed %d: %d large islands, want 2-4" % [seed, n])


func test_archipelago() -> void:
	var m := _map("archipelago")
	check(_landmasses(m, 6) >= 15, "archipelago: many islands (%d)" % _landmasses(m, 6))
	check(_count(m, "shallow") > _count(m, "deep") * 0.15, "archipelago: plenty of shallows")


func test_floating_isles() -> void:
	for seed in [1, 2]:
		var m := _map("floating_isles", seed)
		var n := _landmasses(m, 150)
		check(n >= 3 and n <= 5, "floating isles seed %d: %d isles, want 3-5" % [seed, n])
		check_eq(_count(m, "deep") + _count(m, "shallow"), 0, "floating isles: no water")
		var bridges := 0
		for i in m.size():
			if m.road[i]:
				check_eq(m.terrain[i], _data.terrain_ids["air_gap"], "floating isles: bridges span air gaps")
				bridges += 1
		check(bridges > 0, "floating isles: has bridges")


func test_highlands() -> void:
	var m := _map("highlands")
	check(_count(m, "mountain") > _land_count(m) * 0.3, "highlands: mostly mountains")
	check(_count(m, "cliff") > 0, "highlands: has cliffs")


func test_river_valley() -> void:
	var m := _map("river_valley")
	check(m.rivers.size() >= 4, "river valley: %d rivers, want 4+" % m.rivers.size())
	for path in m.rivers:
		var crossings := 0
		for i in path:
			if m.road[i] or m.terrain[i] == _data.terrain_ids["shallow"]:
				crossings += 1
		check(path.size() < 30 or crossings > 0, "river valley: long river without a crossing")
		var mouth := path[path.size() - 1]
		var reaches_water := false
		for n in m.neighbor_indices(mouth):
			if _data.terrains[m.terrain[n]].get("water", false) and n not in path:
				reaches_water = true
		check(reaches_water, "river valley: river ends at water")


func test_deep_forest_and_tundra() -> void:
	var forest := _map("deep_forest")
	check(_count(forest, "forest") > _land_count(forest) * 0.5, "deep forest: mostly forest")
	var tundra := _map("tundra")
	check(_count(tundra, "snow") > _land_count(tundra) * 0.45, "tundra: mostly snow")
	check_eq(_count(tundra, "desert"), 0, "tundra: no desert")


func test_volcanic() -> void:
	var m := _map("volcanic")
	check(_count(m, "lava") > _count(_map("continent"), "lava") * 2, "volcanic: much more lava than continent")
