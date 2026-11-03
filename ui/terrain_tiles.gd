class_name TerrainTiles
## Placeholder terrain art drawn in code: one hex tile per terrain, each with a
## whole motif inside the hex, so region borders follow clean hex edges.
## Motif coordinates are designed for a hex of size 32 (center to corner).

const SS := 2  # supersamples per axis, for smooth edges
const BLEED := 1.0  # extra texels around the hex so neighbors overlap without seams


## Texture size in texels for hex size `s`.
static func tile_size(s: float) -> Vector2i:
	return Vector2i(ceili((s + BLEED) * Hex.SQRT3) + 2, ceili((s + BLEED) * 2.0) + 2)


## One texture per terrain id.
static func build(data: GameData, s: float) -> Array[Texture2D]:
	var out: Array[Texture2D] = []
	for t in data.terrains:
		var img := draw_tile(t["key"], Color(t["color"]), s)
		img.generate_mipmaps()
		out.append(ImageTexture.create_from_image(img))
	return out


static func draw_tile(key: String, base: Color, s: float) -> Image:
	var size := tile_size(s)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(base, 0.0))  # clear texels keep the base color, so filtering adds no dark rim
	var c := Vector2(size) / 2.0
	var k := s / 32.0
	var at := func(points: Array) -> PackedVector2Array:
		var out := PackedVector2Array()
		for p: Vector2 in points:
			out.append(c + p * k)
		return out
	_fill(img, _hex(c, s + BLEED), base)
	var dark := base.darkened(0.25)
	match key:
		"plains":
			for p in [Vector2(-10, -7), Vector2(9, -3), Vector2(-1, 10)]:
				for blade in [[-3, -4], [0, -7], [3, -4]]:
					_fill(img, at.call([p + Vector2(blade[0] - 1, 2), p + Vector2(blade[0] + 1, 2),
							p + Vector2(blade[0] * 1.4, blade[1])]), dark)
		"forest":
			_fill(img, at.call([Vector2(-2, 7), Vector2(2, 7), Vector2(2, 15), Vector2(-2, 15)]), Color("#5a3d22"))
			_fill(img, at.call([Vector2(0, -8), Vector2(14, 10), Vector2(-14, 10)]), base.darkened(0.4))
			_fill(img, at.call([Vector2(0, -18), Vector2(11, 1), Vector2(-11, 1)]), base.darkened(0.4))
			_fill(img, at.call([Vector2(0, -18), Vector2(0, 1), Vector2(-11, 1)]), base.darkened(0.2))
		"desert":
			for p in [Vector2(-8, 0), Vector2(9, -7), Vector2(4, 12)]:
				_fill(img, at.call(_arc(p, 8.0, 2.0, PI * 1.15, PI * 1.85)), dark)
		"snow":
			for p in [Vector2(-8, 8), Vector2(8, -2)]:
				_fill(img, at.call(_arc(p, 7.0, 7.0, PI, TAU)), Color("#cbd8e2"))
		"mountain":
			_fill(img, at.call([Vector2(0, -19), Vector2(20, 14), Vector2(-20, 14)]), base.darkened(0.1))
			_fill(img, at.call([Vector2(0, -19), Vector2(20, 14), Vector2(3, 14)]), base.darkened(0.35))
			_fill(img, at.call([Vector2(0, -19), Vector2(6, -9), Vector2(2, -11), Vector2(-1, -8), Vector2(-6, -9)]),
					Color("#f2f4f6"))
		"swamp":
			_fill(img, at.call(_ellipse(Vector2(2, 9), 12, 4.5)), Color("#4d7a80"))
			for x in [-9, -4, 7]:
				_fill(img, at.call([Vector2(x - 0.8, -6), Vector2(x + 0.8, -6), Vector2(x + 0.8, 7), Vector2(x - 0.8, 7)]), dark)
				_fill(img, at.call(_ellipse(Vector2(x, -8), 1.8, 3.8)), Color("#6b4a2a"))
		"lava":
			for p in [Vector2(-8, -6), Vector2(8, 4), Vector2(-3, 11)]:
				_fill(img, at.call(_ellipse(p, 6.5, 4.5)), Color("#5a2614"))
			for p in [Vector2(6, -9), Vector2(-10, 5), Vector2(11, 12)]:
				_fill(img, at.call(_ellipse(p, 2.2, 2.2)), Color("#ffd23f"))
		"cliff":
			for x in [-14, -6, 2, 10]:
				_fill(img, at.call([Vector2(x, 12), Vector2(x + 3, 12), Vector2(x + 9, -12), Vector2(x + 6, -12)]), dark)
	return img


static func _hex(c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60 * i - 30)
		out.append(c + Vector2(cos(a), sin(a)) * s)
	return out


static func _ellipse(c: Vector2, rx: float, ry: float) -> Array:
	var out := []
	for i in 16:
		var a := TAU * i / 16.0
		out.append(c + Vector2(cos(a) * rx, sin(a) * ry))
	return out


## A band along a circle's edge, `width` thick, from angle a0 to a1 (y points down).
static func _arc(c: Vector2, r: float, width: float, a0: float, a1: float) -> Array:
	var outer := []
	var inner := []
	for i in 9:
		var a := lerpf(a0, a1, i / 8.0)
		outer.append(c + Vector2(cos(a), sin(a)) * r)
		inner.push_front(c + Vector2(cos(a), sin(a)) * maxf(r - width, 0.0))
	return outer + inner


## Paints a polygon over the image with antialiased edges.
static func _fill(img: Image, poly: PackedVector2Array, color: Color) -> void:
	var lo := poly[0]
	var hi := poly[0]
	for p in poly:
		lo = lo.min(p)
		hi = hi.max(p)
	var x0 := maxi(0, floori(lo.x))
	var y0 := maxi(0, floori(lo.y))
	var x1 := mini(img.get_width() - 1, ceili(hi.x))
	var y1 := mini(img.get_height() - 1, ceili(hi.y))
	for y in range(y0, y1 + 1):
		for x in range(x0, x1 + 1):
			var hits := 0
			for sy in SS:
				for sx in SS:
					if Geometry2D.is_point_in_polygon(Vector2(x + (sx + 0.5) / SS, y + (sy + 0.5) / SS), poly):
						hits += 1
			if hits > 0:
				var over := Color(color, color.a * hits / float(SS * SS))
				img.set_pixel(x, y, img.get_pixel(x, y).blend(over))
