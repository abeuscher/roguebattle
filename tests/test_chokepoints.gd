extends TestCase
## Chokepoints (user, 2026-11-16): barriers across the line between the bases cut the land
## into sections, each border crossed at a set number of places.

var d := GameData.load_dir()


func _map(seed: int, more := {}) -> MapData:
	var o := {"width": 400, "height": 225, "preset": "continent"}
	o.merge(more, true)
	return MapGen.generate(d, seed, o)


func test_sections_follow_the_slider() -> void:
	check_eq(_map(7).sections, 3, "35% (the default) on a normal map: three sections")
	check_eq(_map(7, {"section_pct": 50}).sections, 2, "50%: two")
	var none := _map(7, {"section_pct": 100})
	check(none.sections == 1 and none.chokepoints.is_empty(), "100%: no chokepoints")


func test_every_ground_route_between_the_bases_goes_through_a_crossing() -> void:
	for seed in [3, 7, 11]:
		var m := _map(seed)
		var open := MapGen.ground_passable(m, d)
		var comp: PackedInt32Array = m.components(open)[0]
		check_eq(comp[m.player_base], comp[m.enemy_base], "seed %d: the bases are joined" % seed)
		for i in m.chokepoints:
			open[i] = 0
		comp = m.components(open)[0]
		check(comp[m.player_base] != comp[m.enemy_base], "seed %d: but only through the crossings" % seed)
		check(m.section[m.player_base] != m.section[m.enemy_base], "seed %d: each base in its own section" % seed)


func test_crossings_per_border_follow_the_slider() -> void:
	for n in [1, 3, 5]:
		var m := _map(7, {"section_pct": 50, "crossings": n})
		check_eq(_groups(m), n, "%d crossing(s) on the one border" % n)


func test_small_maps_get_one_barrier_at_most() -> void:
	var m := MapGen.generate(d, 7, {"width": 100, "height": 45, "preset": "continent", "section_pct": 20})
	check(m.sections <= 2, "a 100-wide map: %d sections" % m.sections)


func test_not_on_maps_the_sea_divides() -> void:
	for preset in ["islands", "archipelago", "floating_isles"]:
		check(_map(7, {"preset": preset}).chokepoints.is_empty(), "%s: none" % preset)


func test_the_barrier_fits_the_map() -> void:
	var lava := _map(7, {"preset": "volcanic"})
	var crossings_on_lava := lava.chokepoints.filter(func(i): return d.terrains[lava.terrain[i]]["key"] == "plains")
	check_eq(crossings_on_lava.size(), lava.chokepoints.size(), "volcanic: lava barriers, crossed on plains")


func test_one_terrain_per_section() -> void:
	var m := _map(7, {"one_terrain": true})
	var barrier := ["cliff", "lava", "mountain", "deep", "shallow"]  # barriers and their banks aside
	for sec in m.sections:
		var kinds := {}
		for i in m.size():
			var key: String = d.terrains[m.terrain[i]]["key"]
			if m.section[i] == sec and key not in barrier and not d.terrains[m.terrain[i]].get("water", false):
				kinds[key] = true
		check(kinds.size() <= 1, "section %d is one terrain: %s" % [sec, kinds.keys()])


## Clusters of crossing hexes (each crossing is a few hexes together).
func _groups(m: MapData) -> int:
	var left := {}
	for i in m.chokepoints:
		left[i] = true
	var n := 0
	while not left.is_empty():
		n += 1
		var todo: Array = [left.keys()[0]]
		while not todo.is_empty():
			var i: int = todo.pop_back()
			if not left.has(i):
				continue
			left.erase(i)
			for k in 6:
				var nb := m.neighbors[i * 6 + k]
				if nb >= 0 and left.has(nb):
					todo.append(nb)
	return n
