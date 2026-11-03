class_name TerrainTiles
## Placeholder terrain art drawn in code: one hex tile per terrain, each with a
## whole motif inside the hex, so region borders follow clean hex edges.
## Motif coordinates are designed for a hex of size 32 (center to corner).

const SS := 2  # supersamples per axis, for smooth edges
const BLEED := 1.0  # extra texels around the hex so neighbors overlap without seams
const RELIEF_SHORT := 0.3  # drop depth for coasts and cliffs, in hex sizes
const RELIEF_DEEP := 0.9  # drop depth for floating isles
const OBJECT_CELLS := 4  # tree A, tree B, peak A, peak B


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


## A plank deck drawn over the hex, for bridges.
static func bridge(color: Color, s: float) -> Texture2D:
	var size := tile_size(s)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(color, 0.0))
	var c := Vector2(size) / 2.0
	fill(img, hex_points(c, s * 0.8), color)
	var k := s / 32.0
	for y in [-12, -4, 4, 12]:
		fill(img, PackedVector2Array([c + Vector2(-21, y - 0.7) * k, c + Vector2(21, y - 0.7) * k,
				c + Vector2(21, y + 0.7) * k, c + Vector2(-21, y + 0.7) * k]), color.darkened(0.35))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Road art: index 0-5 run from the hex center to the edge facing Hex.DIRECTIONS[k],
## index 6 is the center disc. A road hex draws the disc plus one piece per road neighbor.
static func road_pieces(color: Color, s: float) -> Array[Texture2D]:
	var size := tile_size(s)
	var c := Vector2(size) / 2.0
	var half_width := s * 0.14
	var out: Array[Texture2D] = []
	for k in 7:
		var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
		img.fill(Color(color, 0.0))
		if k < 6:
			var to := Hex.to_pixel(Hex.DIRECTIONS[k], s) * 0.5 * 1.04  # just past the edge so pieces meet
			var side := to.orthogonal().normalized() * half_width
			fill(img, PackedVector2Array([c + side, c + to + side, c + to - side, c - side]), color)
		else:
			fill(img, PackedVector2Array(ellipse(c, half_width, half_width)), color)
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
	fill(img, hex_points(c, s + BLEED), base)
	var dark := base.darkened(0.25)
	match key:
		"plains":
			for p in [Vector2(-10, -7), Vector2(9, -3), Vector2(-1, 10)]:
				for blade in [[-3, -4], [0, -7], [3, -4]]:
					fill(img, at.call([p + Vector2(blade[0] - 1, 2), p + Vector2(blade[0] + 1, 2),
							p + Vector2(blade[0] * 1.4, blade[1])]), dark)
		"forest":  # floor only; trees are objects (MapView)
			for p in [Vector2(-12, -8), Vector2(10, -10), Vector2(-4, 4), Vector2(13, 8), Vector2(-14, 12), Vector2(3, 15)]:
				fill(img, at.call(ellipse(p, 2.5, 1.6)), dark)
		"desert":
			for p in [Vector2(-8, 0), Vector2(9, -7), Vector2(4, 12)]:
				fill(img, at.call(_arc(p, 8.0, 2.0, PI * 1.15, PI * 1.85)), dark)
		"snow":
			for p in [Vector2(-8, 8), Vector2(8, -2)]:
				fill(img, at.call(_arc(p, 7.0, 7.0, PI, TAU)), Color("#cbd8e2"))
		"mountain":  # rocky floor only; peaks are objects (MapView)
			for p in [Vector2(-11, -9), Vector2(9, -6), Vector2(-3, 7), Vector2(12, 11), Vector2(-13, 10)]:
				fill(img, at.call(ellipse(p, 3.0, 2.0)), dark)
				fill(img, at.call(ellipse(p + Vector2(-0.8, -0.8), 1.6, 1.0)), base.lightened(0.2))
		"swamp":
			var water := Color("#4d7a80")
			for p in [Vector2(-10, -6), Vector2(9, -2), Vector2(-1, 10)]:  # laid out like the grass
				fill(img, at.call(ellipse(p + Vector2(0.8, 0.8), 4.5, 4.5)), water.darkened(0.35))  # bevel shadow
				fill(img, at.call(ellipse(p, 4.5, 4.5)), water)
				fill(img, at.call(ellipse(p + Vector2(-1.5, -1.5), 1.6, 1.2)), water.lightened(0.35))  # glint
		"lava":
			for p in [Vector2(-8, -6), Vector2(8, 4), Vector2(-3, 11)]:
				fill(img, at.call(ellipse(p, 6.5, 4.5)), Color("#5a2614"))
			for p in [Vector2(6, -9), Vector2(-10, 5), Vector2(11, 12)]:
				fill(img, at.call(ellipse(p, 2.2, 2.2)), Color("#ffd23f"))
		"frozen_lake":
			var glint := base.lightened(0.6)
			for p in [Vector2(-9, -5), Vector2(7, 6)]:
				fill(img, at.call([p + Vector2(-6, 3), p + Vector2(-5, 4.5), p + Vector2(6, -3), p + Vector2(5, -4.5)]), glint)
				fill(img, at.call([p + Vector2(-1, 5), p + Vector2(0, 6), p + Vector2(5, 2.5), p + Vector2(4, 1.5)]), glint)
		"cliff":
			for x in [-14, -6, 2, 10]:
				fill(img, at.call([Vector2(x, 12), Vector2(x + 3, 12), Vector2(x + 9, -12), Vector2(x + 6, -12)]), dark)
	return img


## White hex (with bleed) for colored overlays, or a thin white ring for grid lines.
static func hex_shape(s: float, ring: bool) -> Texture2D:
	var size := tile_size(s)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := Vector2(size) / 2.0
	if ring:
		var outer := hex_points(c, s + 0.6)
		var inner := hex_points(c, s - 1.2)
		for k in 6:  # one quad per edge
			fill(img, PackedVector2Array([outer[k], outer[(k + 1) % 6], inner[(k + 1) % 6], inner[k]]), Color.WHITE)
	else:
		fill(img, hex_points(c, s + BLEED), Color.WHITE)
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Size of a relief texture: the hex plus room for the deepest drop below it.
static func relief_size(s: float) -> Vector2i:
	return Vector2i(tile_size(s).x, ceili(s * 2.0 * (1.0 + RELIEF_DEEP)) + 2)



## The face hanging below a hex's lower edge, shaded darker toward the bottom.
## side 0 = lower-right edge (toward Hex.DIRECTIONS[5]), 1 = lower-left (toward [4]).
## White, so each instance can be tinted.
static func relief(s: float, side: int, depth: float) -> Texture2D:
	var size := relief_size(s)
	var img := Image.create_empty(size.x, size.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(1, 1, 1, 0))
	var c := Vector2(size) / 2.0
	var w := s * Hex.SQRT3 / 2.0
	var a := c + (Vector2(w, s * 0.5) if side == 0 else Vector2(0, s))
	var b := c + (Vector2(0, s) if side == 0 else Vector2(-w, s * 0.5))
	var d := s * depth
	var bands := 4
	for j in bands:
		var top := Vector2(0, d * j / bands)
		var bottom := Vector2(0, d * (j + 1) / bands + 0.6)
		var shade := 1.0 - 0.12 * j
		fill(img, PackedVector2Array([a + top, b + top, b + bottom, a + bottom]), Color(shade, shade, shade))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


## Upright objects drawn over the terrain: trees and peaks, two variants each,
## side by side in one atlas so they can share a MultiMesh and keep their draw order.


static func object_cell(s: float) -> Vector2i:
	return Vector2i(ceili(s * 2.4), ceili(s * 3.2))


static func objects(s: float) -> Texture2D:
	var cell := object_cell(s)
	var img := Image.create_empty(cell.x * OBJECT_CELLS, cell.y, false, Image.FORMAT_RGBA8)
	img.fill(Color(0.2, 0.3, 0.2, 0))
	for n in OBJECT_CELLS:
		var k := s / 32.0 * (1.3 if n < 2 else 1.0)  # trees drawn a little larger than a hex
		var c := Vector2(cell.x * (n + 0.5), cell.y * 0.5)  # the hex center
		var poly := func(points: Array, color: Color) -> void:
			var out := PackedVector2Array()
			for p: Vector2 in points:
				out.append(c + p * k)
			fill(img, out, color)
		match n:
			0:  # pine
				poly.call(ellipse(Vector2(0, 13), 12, 3.5), Color(0, 0, 0, 0.25))
				poly.call([Vector2(-2.5, 4), Vector2(2.5, 4), Vector2(2.5, 13), Vector2(-2.5, 13)], Color("#4a321c"))
				for tier in [[-7, 9, 16], [-17, 0, 13], [-27, -9, 9.5]]:
					poly.call([Vector2(0, tier[0] - 1.5), Vector2(tier[2] + 1.5, tier[1] + 1), Vector2(-tier[2] - 1.5, tier[1] + 1)], Color("#1c3a1a"))
					poly.call([Vector2(0, tier[0]), Vector2(tier[2], tier[1]), Vector2(-tier[2], tier[1])], Color("#2e5e2b"))
					poly.call([Vector2(0, tier[0]), Vector2(0, tier[1]), Vector2(-tier[2], tier[1])], Color("#3d7a38"))
			1:  # broadleaf
				poly.call(ellipse(Vector2(0, 13), 12, 3.5), Color(0, 0, 0, 0.25))
				poly.call([Vector2(-2.5, 2), Vector2(2.5, 2), Vector2(2.5, 13), Vector2(-2.5, 13)], Color("#4a321c"))
				for blob in [[Vector2(-6, -6), 8.0], [Vector2(6, -7), 8.0], [Vector2(0, -15), 9.0]]:
					poly.call(ellipse(blob[0], blob[1] + 1.5, blob[1] + 1.5), Color("#1c3a1a"))
				for blob in [[Vector2(-6, -6), 8.0], [Vector2(6, -7), 8.0], [Vector2(0, -15), 9.0]]:
					poly.call(ellipse(blob[0], blob[1], blob[1]), Color("#35702f"))
				poly.call(ellipse(Vector2(-4, -15), 4.5, 3.5), Color("#4b8a42"))
			2, 3:  # peaks; variant 3 has a second peak behind
				var rock := Color("#8a7f72")
				var outline := Color("#3c352e")
				if n == 3:
					poly.call([Vector2(10, -24), Vector2(30, 14), Vector2(-8, 14)], outline)
					poly.call([Vector2(10, -22), Vector2(28, 13), Vector2(-6, 13)], rock.darkened(0.25))
				var top := Vector2(-3, -30) if n == 3 else Vector2(0, -32)
				poly.call([top + Vector2(0, -2), Vector2(26, 15), Vector2(-26, 15)], outline)
				poly.call([top, Vector2(24, 14), Vector2(-24, 14)], rock)
				poly.call([top, Vector2(24, 14), Vector2(top.x + 4, 14)], rock.darkened(0.3))
				var cap := 0.3  # snowcap covers the top 30% of the peak
				var l := top.lerp(Vector2(-24, 14), cap)
				var r := top.lerp(Vector2(24, 14), cap)
				poly.call([top, r, r.lerp(l, 0.33) + Vector2(0, 3), r.lerp(l, 0.66) - Vector2(0, 1), l], Color("#f2f4f6"))
	img.generate_mipmaps()
	return ImageTexture.create_from_image(img)


static func hex_points(c: Vector2, s: float) -> PackedVector2Array:
	var out := PackedVector2Array()
	for i in 6:
		var a := deg_to_rad(60 * i - 30)
		out.append(c + Vector2(cos(a), sin(a)) * s)
	return out


static func ellipse(c: Vector2, rx: float, ry: float) -> Array:
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
static func fill(img: Image, poly: PackedVector2Array, color: Color) -> void:
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
