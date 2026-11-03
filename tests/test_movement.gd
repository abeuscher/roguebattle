extends TestCase

var d := GameData.load_dir()


func _map_with(keys: Array) -> MapData:
	var m := MapData.new(keys.size(), 1)
	for i in keys.size():
		m.terrain[i] = d.terrain_ids[keys[i]]
	return m


func test_difficulty_multipliers() -> void:
	var m := _map_with(["plains", "forest", "mountain", "deep", "frozen_lake"])
	check_eq(Movement.hex_multiplier(m, d, 0), 1.0, "plains x1")
	check_eq(Movement.hex_multiplier(m, d, 1), 1.5, "forest x1.5")
	check_eq(Movement.hex_multiplier(m, d, 2), 2.0, "mountain x2")
	check_eq(Movement.hex_multiplier(m, d, 3), INF, "deep water impassable")
	check_eq(Movement.hex_multiplier(m, d, 4), 1.5, "frozen lake like snow")


func test_travel_type_counts_as_easy() -> void:
	var m := _map_with(["forest", "frozen_lake", "mountain"])
	check_eq(Movement.hex_multiplier(m, d, 0, "forest"), 1.0, "forest natives x1 in forest")
	check_eq(Movement.hex_multiplier(m, d, 1, "snow"), 1.0, "snow natives x1 on frozen lakes")
	check_eq(Movement.hex_multiplier(m, d, 2, "forest"), 2.0, "forest natives x2 on mountains")


func test_roads_and_sky() -> void:
	var m := _map_with(["forest", "deep", "mountain"])
	m.road[0] = 1
	m.road[1] = 1
	check_eq(Movement.hex_multiplier(m, d, 0), 1.5 * 0.75, "road through forest")
	check_eq(Movement.hex_multiplier(m, d, 1), 0.75, "bridge over deep water")
	check_eq(Movement.hex_multiplier(m, d, 0, "", true), 1.0, "sky ignores roads")
	check_eq(Movement.hex_multiplier(m, d, 2, "", true), 1.0, "sky ignores terrain")
