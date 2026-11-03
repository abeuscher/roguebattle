class_name MapData
extends RefCounted
## A generated map: terrain per hex in a width x height odd-r rectangle.

const ROAD_STANDALONE := 64

# Offset-space steps matching Hex.DIRECTIONS, for even and odd rows.
const _EVEN_ROW := [Vector2i(1, 0), Vector2i(0, -1), Vector2i(-1, -1), Vector2i(-1, 0), Vector2i(-1, 1), Vector2i(0, 1)]
const _ODD_ROW := [Vector2i(1, 0), Vector2i(1, -1), Vector2i(0, -1), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(1, 1)]

var width: int
var height: int
var seed: int
var settings: Dictionary
var terrain: PackedByteArray  # terrain id per hex, index = row * width + col
## Nonzero = road; a road on impassable terrain is a bridge. Bits 0-5 mark which
## neighbors (Hex.DIRECTIONS order) the road runs to; ROAD_STANDALONE marks a road
## hex with no links yet (a lone river bridge).
var road: PackedByteArray
var rivers: Array[PackedInt32Array] = []  # hex indices from source to mouth
## Each: {type, hex, shop, hint, hidden, kind, road}. Bases are buildings too.
var buildings: Array[Dictionary] = []
var lairs: Array[Dictionary] = []  # each: {hex, home (unit terrain), danger 0..1}
var player_base := -1
var enemy_base := -1
var neighbors: PackedInt32Array  # 6 per hex in Hex.DIRECTIONS order, -1 off the map


func _init(w: int, h: int) -> void:
	width = w
	height = h
	terrain.resize(w * h)
	road.resize(w * h)
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


## Lays road along a path of adjacent hexes, linking each step.
func lay_road(path: PackedInt32Array) -> void:
	if path.size() == 1:
		road[path[0]] |= ROAD_STANDALONE
	for j in path.size() - 1:
		link_road(path[j], path[j + 1])


## Joins two adjacent hexes by road.
func link_road(a: int, b: int) -> void:
	for k in 6:
		if neighbors[a * 6 + k] == b:
			road[a] |= 1 << k
			road[b] |= 1 << ((k + 3) % 6)  # the opposite direction
			return


## Which quarter of the map a hex is in: 0 NW, 1 NE, 2 SW, 3 SE.
func quadrant(index: int) -> int:
	return (1 if index % width >= width / 2 else 0) + (2 if index / width >= height / 2 else 0)


## Steps from the nearest marked hex, up to `limit`; -1 beyond it (and 0 on marked hexes).
func distance_from(marked: PackedByteArray, limit: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(size())
	dist.fill(-1)
	var frontier := PackedInt32Array()
	for i in size():
		if marked[i]:
			dist[i] = 0
			frontier.append(i)
	for step in range(1, limit + 1):
		var next := PackedInt32Array()
		for i in frontier:
			for k in range(i * 6, i * 6 + 6):
				var n := neighbors[k]
				if n >= 0 and dist[n] < 0:
					dist[n] = step
					next.append(n)
		frontier = next
	return dist


## Connected regions of marked hexes: [component id per hex (-1 if unmarked), sizes].
func components(marked: PackedByteArray) -> Array:
	var comp := PackedInt32Array()
	comp.resize(size())
	comp.fill(-1)
	var sizes := PackedInt32Array()
	for start in size():
		if not marked[start] or comp[start] >= 0:
			continue
		var id := sizes.size()
		var count := 0
		var stack := PackedInt32Array([start])
		comp[start] = id
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			count += 1
			for k in range(i * 6, i * 6 + 6):
				var n := neighbors[k]
				if n >= 0 and marked[n] and comp[n] < 0:
					comp[n] = id
					stack.append(n)
		sizes.append(count)
	return [comp, sizes]


## Indices of the in-bounds neighbors of the hex at `index`.
func neighbor_indices(index: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for k in 6:
		var n := neighbors[index * 6 + k]
		if n >= 0:
			out.append(n)
	return out
