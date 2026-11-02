class_name MapData
extends RefCounted
## A generated map: terrain per hex in a width x height odd-r rectangle.

# Offset-space steps matching Hex.DIRECTIONS, for even and odd rows.
const _EVEN_ROW := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const _ODD_ROW := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]

var width: int
var height: int
var seed: int
var settings: Dictionary
var terrain: PackedByteArray  # terrain id per hex, index = row * width + col
var neighbors: PackedInt32Array  # 6 per hex in Hex.DIRECTIONS order, -1 off the map


func _init(w: int, h: int) -> void:
	width = w
	height = h
	terrain.resize(w * h)
	neighbors.resize(w * h * 6)
	var i := 0
	for row in h:
		var steps: Array = _ODD_ROW if row & 1 else _EVEN_ROW
		for col in w:
			for s: Vector2i in steps:
				var c := col + s.x
				var r := row + s.y
				neighbors[i] = r * w + c if c >= 0 and c < w and r >= 0 and r < h else -1
				i += 1


func size() -> int:
	return width * height


func index_of(h: Vector2i) -> int:
	var o := Hex.to_offset(h)
	return o.y * width + o.x


func hex_at(index: int) -> Vector2i:
	return Hex.from_offset(Vector2i(index % width, index / width))


func in_bounds(h: Vector2i) -> bool:
	var o := Hex.to_offset(h)
	return o.x >= 0 and o.x < width and o.y >= 0 and o.y < height


## Indices of the in-bounds neighbors of the hex at `index`.
func neighbor_indices(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in 6:
		var n := neighbors[index * 6 + k]
		if n >= 0:
			out.append(n)
	return out
