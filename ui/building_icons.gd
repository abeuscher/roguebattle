class_name BuildingIcons
## Placeholder building and lair icons drawn in code, one texture per type.
## Coordinates are designed for a hex of size 32 (center to corner). Icons carry no
## flags: the owner's flag is drawn over them (BuildingMarker), standing on TOPS.

## Where each icon's roof or wall top is, centered, for the owner's flag pole.
const TOPS := {"town": Vector2(0, -15), "tower": Vector2(0, -16), "temple": Vector2(0, -15), "nomads": Vector2(0, -13),
		"player_base": Vector2(0, -6), "enemy_base": Vector2(0, -6)}


static func build(s: float) -> Dictionary:
	var out := {}
	for type in ["player_base", "enemy_base", "town", "tower", "temple", "nomads", "hidden_site", "lair"]:
		var img := draw(type, s)
		img.generate_mipmaps()
		out[type] = ImageTexture.create_from_image(img)
	return out


static func draw(type: String, s: float) -> Image:
	var size := TerrainTiles.tile_size(s) * 2  # icons may stand taller than a hex
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.1, 0.1, 0.1, 0.0))
	var c := Vector2(size) / 2.0
	var k := s / 32.0
	var poly := func(points: Array, color: Color) -> void:
		var out := PackedVector2Array()
		for p: Vector2 in points:
			out.append(c + p * k)
		TerrainTiles.fill(img, out, color)
	var box := func(x0: float, y0: float, x1: float, y1: float, color: Color) -> void:
		poly.call([Vector2(x0, y0), Vector2(x1, y0), Vector2(x1, y1), Vector2(x0, y1)], color)
	poly.call(TerrainTiles.ellipse(Vector2(0, 12), 16, 5), Color(0, 0, 0, 0.3))  # ground shadow
	var outline := Color("#2a2420")
	match type:
		"town":
			box.call(-11, -3, 11, 12, outline)
			box.call(-10, -2, 10, 11, Color("#ead9b5"))
			poly.call([Vector2(-14, -2), Vector2(0, -15), Vector2(14, -2)], outline)
			poly.call([Vector2(-12, -3), Vector2(0, -13.5), Vector2(12, -3)], Color("#b5482f"))
			box.call(-3, 3, 3, 11, Color("#5b3a24"))
		"tower":
			box.call(-8, -16, 8, 12, outline)
			box.call(-7, -12, 7, 11, Color("#77727f"))
			for x in [-7, -1.5, 4]:
				box.call(x, -16, x + 3, -12, Color("#77727f"))
			box.call(-2, -6, 2, 0, Color("#3a3045"))
		"temple":
			box.call(-14, 8, 14, 13, outline)
			box.call(-13, 9, 13, 12, Color("#f1ede2"))
			for x in [-11, -4.5, 2, 8.5]:
				box.call(x, -4, x + 3, 9, Color("#f1ede2"))
			poly.call([Vector2(-15, -4), Vector2(0, -15), Vector2(15, -4)], outline)
			poly.call([Vector2(-13, -5), Vector2(0, -13.5), Vector2(13, -5)], Color("#f1ede2"))
		"nomads":
			poly.call([Vector2(-14, 12), Vector2(0, -13), Vector2(14, 12)], outline)
			poly.call([Vector2(-12, 11), Vector2(0, -11), Vector2(12, 11)], Color("#d3ad6e"))
			poly.call([Vector2(-4, 11), Vector2(0, 2), Vector2(4, 11)], Color("#5b3a24"))
		"player_base", "enemy_base":
			var stone := Color("#9aa3b0") if type == "player_base" else Color("#6e6668")
			box.call(-17, -6, 17, 13, outline)
			box.call(-16, -5, 16, 12, stone)
			for x in [-17, 9]:
				box.call(x, -16, x + 8, 13, outline)
				box.call(x + 1, -15, x + 7, 12, stone)
			box.call(-4, 3, 4, 12, Color("#3a2c22"))
		"hidden_site":
			poly.call([Vector2(0, -12), Vector2(10, 0), Vector2(0, 12), Vector2(-10, 0)], Color(outline, 0.6))
			poly.call([Vector2(0, -10), Vector2(8, 0), Vector2(0, 10), Vector2(-8, 0)], Color("#f2c94c", 0.6))
		"lair":
			poly.call(TerrainTiles.ellipse(Vector2(0, 4), 14, 10), outline)
			poly.call(TerrainTiles.ellipse(Vector2(0, 4), 12.5, 8.5), Color("#7a6f63"))
			poly.call(TerrainTiles.ellipse(Vector2(0, 7), 7, 6), Color("#1d1715"))
	return img
