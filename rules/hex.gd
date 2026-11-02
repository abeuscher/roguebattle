class_name Hex
## Pointy-top hexes in axial coordinates (q, r), stored as Vector2i.
## Maps are rectangles in "odd-r" offset layout: odd rows sit half a hex right.

const DIRECTIONS: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1),
	Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1),
]
const SQRT3 := 1.7320508075688772


static func neighbor(h: Vector2i, dir: int) -> Vector2i:
	return h + DIRECTIONS[dir]


static func distance(a: Vector2i, b: Vector2i) -> int:
	var d := a - b
	return (absi(d.x) + absi(d.x + d.y) + absi(d.y)) / 2


static func to_offset(h: Vector2i) -> Vector2i:
	return Vector2i(h.x + (h.y - (h.y & 1)) / 2, h.y)


static func from_offset(o: Vector2i) -> Vector2i:
	return Vector2i(o.x - (o.y - (o.y & 1)) / 2, o.y)


## Hex center in pixels, for hexes `size` from center to corner.
static func to_pixel(h: Vector2i, size: float) -> Vector2:
	return Vector2(size * SQRT3 * (h.x + h.y * 0.5), size * 1.5 * h.y)


static func from_pixel(p: Vector2, size: float) -> Vector2i:
	var q := (SQRT3 / 3.0 * p.x - p.y / 3.0) / size
	var r := (2.0 / 3.0 * p.y) / size
	return round_axial(q, r)


static func round_axial(q: float, r: float) -> Vector2i:
	var s := -q - r
	var rq := roundf(q)
	var rr := roundf(r)
	var rs := roundf(s)
	var dq := absf(rq - q)
	var dr := absf(rr - r)
	var ds := absf(rs - s)
	if dq > dr and dq > ds:
		rq = -rr - rs
	elif dr > ds:
		rr = -rq - rs
	return Vector2i(int(rq), int(rr))
