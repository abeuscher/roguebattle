extends TestCase

static var _data: GameData
static var _map: MapData


func _init() -> void:
	if _data == null:
		_data = GameData.load_dir()
		_map = MapGen.generate(_data, 12345)


func _count(map: MapData, key: String) -> int:
	return map.terrain.count(_data.terrain_ids[key])


func _land_count(map: MapData) -> int:
	return map.size() - _count(map, "shallow") - _count(map, "deep")


func test_size() -> void:
	check_eq(_map.width, 400, "small width")
	check_eq(_map.height, 225, "small height")


func test_same_seed_same_map() -> void:
	check(MapGen.generate(_data, 12345).terrain == _map.terrain, "same seed rebuilds the same map")
	check(MapGen.generate(_data, 54321).terrain != _map.terrain, "another seed gives another map")


func test_land_fraction() -> void:
	var land := float(_land_count(_map)) / _map.size()
	var target: float = _map.settings["land_pct"] / 100.0
	check(absf(land - target) < 0.08, "land %.2f vs target %.2f" % [land, target])


func test_terrain_amounts() -> void:
	var land := float(_land_count(_map))
	var fractions: Dictionary = _data.mapgen["amount_fractions"]
	for key in _map.settings["terrain_amounts"]:
		var want: float = fractions[_map.settings["terrain_amounts"][key]]
		var got := _count(_map, key) / land
		check(absf(got - want) < 0.01, "%s: %.3f of land, want %.3f" % [key, got, want])
	check(_count(_map, "plains") / land > 0.3, "plains are the default ground")


func test_amount_none_removes_terrain() -> void:
	var m := MapGen.generate(_data, 7, {"terrain_amounts": {"lava": "none", "desert": "high"}})
	check_eq(_count(m, "lava"), 0, "no lava when set to none")
	check(_count(m, "desert") > _count(_map, "desert"), "high desert beats low desert")


func test_border_is_water() -> void:
	var land_on_edge := 0
	for col in _map.width:
		for row in [0, _map.height - 1]:
			var t := _map.terrain[row * _map.width + col]
			if t != _data.terrain_ids["shallow"] and t != _data.terrain_ids["deep"]:
				land_on_edge += 1
	check_eq(land_on_edge, 0, "continent does not touch top or bottom edge")


func test_shallows_border_land() -> void:
	var deep: int = _data.terrain_ids["deep"]
	var shallow: int = _data.terrain_ids["shallow"]
	for i in _map.size():
		if _map.terrain[i] == deep:
			for n in _map.neighbor_indices(i):
				if _map.terrain[n] != deep and _map.terrain[n] != shallow:
					check(false, "deep water touches land at %s" % _map.hex_at(i))
					return
