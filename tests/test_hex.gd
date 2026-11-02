extends TestCase


func test_distance() -> void:
	check_eq(Hex.distance(Vector2i(0, 0), Vector2i(0, 0)), 0, "same hex")
	for d in Hex.DIRECTIONS:
		check_eq(Hex.distance(Vector2i(3, -2), Vector2i(3, -2) + d), 1, "neighbor %s" % d)
	check_eq(Hex.distance(Vector2i(0, 0), Vector2i(3, -1)), 3, "far hex")
	check_eq(Hex.distance(Vector2i(-2, 4), Vector2i(2, -1)), 5, "far hex 2")


func test_offset_round_trip() -> void:
	for row in range(-3, 4):
		for col in range(-3, 4):
			var o := Vector2i(col, row)
			check_eq(Hex.to_offset(Hex.from_offset(o)), o, "offset round trip %s" % o)


func test_pixel_round_trip() -> void:
	for q in range(-5, 6):
		for r in range(-5, 6):
			var h := Vector2i(q, r)
			var p := Hex.to_pixel(h, 16.0)
			check_eq(Hex.from_pixel(p, 16.0), h, "center of %s" % h)
			check_eq(Hex.from_pixel(p + Vector2(6, -5), 16.0), h, "inside %s" % h)


func test_map_neighbors() -> void:
	var m := MapData.new(10, 6)
	check_eq(m.neighbor_indices(0).size(), 2, "corner (0,0) neighbors")
	check_eq(m.neighbor_indices(m.index_of(Hex.from_offset(Vector2i(4, 3)))).size(), 6, "inner neighbors")
	for i in m.size():
		check_eq(m.index_of(m.hex_at(i)), i, "index round trip %d" % i)
