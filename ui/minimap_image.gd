class_name MinimapImage
## Draws a map as an image: one 2x2 pixel block per hex, odd rows shifted by a pixel.


static func build(map: MapData, data: GameData) -> Image:
	var colors: Array[Color] = []
	for t in data.terrains:
		colors.append(Color(t["color"]))
	var bridge := Color(data.mapgen["bridge_color"])
	var w := map.width * 2 + 1
	var h := map.height * 2
	var bytes := PackedByteArray()
	bytes.resize(w * h * 3)
	for i in map.size():
		var row := i / map.width
		var x := (i % map.width) * 2 + (row & 1)
		var c := bridge if map.road[i] and data.terrains[map.terrain[i]].get("impassable", false) else colors[map.terrain[i]]
		for dy in 2:
			var p := ((row * 2 + dy) * w + x) * 3
			for dx in 2:
				bytes[p] = c.r8
				bytes[p + 1] = c.g8
				bytes[p + 2] = c.b8
				p += 3
	return Image.create_from_data(w, h, false, Image.FORMAT_RGB8, bytes)
