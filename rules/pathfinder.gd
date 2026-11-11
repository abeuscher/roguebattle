class_name Pathfinder
extends RefCounted
## Squad routes (SPEC §6.1, §20), in two steps so long routes stay fast:
## 1. Region to region: the map is cut into BLOCK x BLOCK blocks, each split into
##    the connected areas a squad can walk ("regions"). One search back from the
##    goal's region gives every region its next region toward the goal.
## 2. Hex to hex: A* over hexes, kept to the corridor of blocks along that region
##    route plus a one-block margin. Routes come out within about 10% of the best.
## Costs are the time multipliers from Movement, per travel profile.

const BLOCK := 16
const RING := 1  # blocks of margin around the region route

var map: MapData
var data: GameData
var _blocks_x: int
var _blocks_y: int
var _profiles := {}  # profile key -> Dictionary (see _profile)
var _g := PackedFloat32Array()  # hex search scratch, reset after each search
var _parent := PackedInt32Array()
var _closed := PackedByteArray()
var _corridor := PackedByteArray()  # per block
var _avoid := PackedByteArray()  # per hex: kept out of the current search
var _block_id := PackedInt32Array()  # per hex
var _q := PackedInt32Array()  # axial coordinates per hex, for quick distances
var _r := PackedInt32Array()


func _init(m: MapData, d: GameData) -> void:
	map = m
	data = d
	_blocks_x = ceili(float(map.width) / BLOCK)
	_blocks_y = ceili(float(map.height) / BLOCK)
	_g.resize(map.size())
	_g.fill(INF)
	_parent.resize(map.size())
	_parent.fill(-1)
	_closed.resize(map.size())
	_avoid.resize(map.size())
	_corridor.resize(_blocks_x * _blocks_y)
	_block_id.resize(map.size())
	_q.resize(map.size())
	_r.resize(map.size())
	for i in map.size():
		var h := map.hex_at(i)
		_q[i] = h.x
		_r[i] = h.y
		_block_id[i] = (i / map.width) / BLOCK * _blocks_x + (i % map.width) / BLOCK


## Route from `from` to `to`, both included; empty if there is none. `avoid`: hexes the
## route may not enter (another squad standing in the way).
func find(from: int, to: int, travel_type := "", sky := false, avoid := PackedInt32Array()) -> PackedInt32Array:
	for i in avoid:
		_avoid[i] = 1
	var path := _find(from, to, travel_type, sky)
	for i in avoid:
		_avoid[i] = 0
	return path


func _find(from: int, to: int, travel_type: String, sky: bool) -> PackedInt32Array:
	var p := _profile(travel_type, sky)
	var comp: PackedInt32Array = p["comp"]
	if comp[from] < 0 or comp[to] < 0:
		return PackedInt32Array()
	if from == to:
		return PackedInt32Array([from])
	var guide := _guide(p, comp[to])
	var to_goal: PackedFloat32Array = guide[0]
	var toward: PackedInt32Array = guide[1]
	if to_goal[comp[from]] == INF:
		return PackedInt32Array()
	# Corridor: the blocks along the region route, plus their neighbors.
	var marked := PackedInt32Array()
	var r := comp[from]
	while r >= 0:
		var b: int = p["comp_block"][r]
		for dy in range(-RING, RING + 1):
			for dx in range(-RING, RING + 1):
				var bx := b % _blocks_x + dx
				var by := b / _blocks_x + dy
				if bx >= 0 and by >= 0 and bx < _blocks_x and by < _blocks_y and not _corridor[by * _blocks_x + bx]:
					_corridor[by * _blocks_x + bx] = 1
					marked.append(by * _blocks_x + bx)
		r = toward[r]
	var path := _hex_route(p, from, to, guide)
	for b in marked:
		_corridor[b] = 0
	return path


## Plain A* over the whole map, for comparison in tests.
func find_flat(from: int, to: int, travel_type := "", sky := false) -> PackedInt32Array:
	var p := _profile(travel_type, sky)
	if p["comp"][from] < 0 or p["comp"][to] < 0:
		return PackedInt32Array()
	return _hex_route(p, from, to, [])


## Total time multiplier of a route: the cost of every hex entered after the first.
func route_cost(path: PackedInt32Array, travel_type := "", sky := false) -> float:
	var cost: PackedFloat32Array = _profile(travel_type, sky)["cost"]
	var total := 0.0
	for j in range(1, path.size()):
		total += cost[path[j]]
	return total


## Time multiplier for entering one hex.
func hex_cost(i: int, travel_type := "", sky := false) -> float:
	return _profile(travel_type, sky)["cost"][i]


## Costs and the region graph for one travel profile, built on first use.
func _profile(travel_type: String, sky: bool) -> Dictionary:
	var key := "sky" if sky else travel_type
	if _profiles.has(key):
		return _profiles[key]
	var cost := PackedFloat32Array()
	cost.resize(map.size())
	for i in map.size():
		cost[i] = Movement.hex_multiplier(map, data, i, travel_type, sky)
	# Regions: connected passable areas within each block.
	var comp := PackedInt32Array()
	comp.resize(map.size())
	comp.fill(-1)
	var comp_block := PackedInt32Array()
	var sum := PackedVector2Array()  # position totals, for centers
	var count := PackedInt32Array()
	var cost_sum := PackedFloat32Array()
	for start in map.size():
		if comp[start] >= 0 or cost[start] == INF:
			continue
		var id := comp_block.size()
		var block := _block_id[start]
		comp_block.append(block)
		sum.append(Vector2.ZERO)
		count.append(0)
		cost_sum.append(0.0)
		comp[start] = id
		var stack := PackedInt32Array([start])
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			sum[id] += Vector2(_q[i], _r[i])
			count[id] += 1
			cost_sum[id] += cost[i]
			for k in range(i * 6, i * 6 + 6):
				var n := map.neighbors[k]
				if n >= 0 and comp[n] < 0 and cost[n] != INF and _block_id[n] == block:
					comp[n] = id
					stack.append(n)
	var center_q := PackedInt32Array()
	var center_r := PackedInt32Array()
	var mean_cost := PackedFloat32Array()
	for id in comp_block.size():
		var c := (sum[id] / count[id]).round()
		center_q.append(int(c.x))
		center_r.append(int(c.y))
		mean_cost.append(cost_sum[id] / count[id])
	# Links between regions that touch across a block border, priced by distance x terrain.
	# The terrain price is the cheaper of the two regions' average and the cheapest
	# border crossing: a road crossing the border makes the link as cheap as the road.
	var links: Array[Dictionary] = []
	links.resize(comp_block.size())
	for id in comp_block.size():
		links[id] = {}
	for i in map.size():
		var a := comp[i]
		if a < 0:
			continue
		var col := i % map.width
		var row := i / map.width
		if col % BLOCK != 0 and col % BLOCK != BLOCK - 1 and row % BLOCK != 0 and row % BLOCK != BLOCK - 1:
			continue  # interior hexes only touch their own block
		for k in range(i * 6, i * 6 + 6):
			var n := map.neighbors[k]
			if n < 0 or comp[n] < 0 or comp[n] == a:
				continue
			var b := comp[n]
			var dq := center_q[a] - center_q[b]
			var dr := center_r[a] - center_r[b]
			var price := minf((mean_cost[a] + mean_cost[b]) * 0.5, (cost[i] + cost[n]) * 0.5)
			var link := (absi(dq) + absi(dq + dr) + absi(dr)) / 2.0 * price
			if link < links[a].get(b, INF):
				links[a][b] = link
	var profile := {"cost": cost, "comp": comp, "comp_block": comp_block, "center_q": center_q,
			"center_r": center_r, "links": links}
	_profiles[key] = profile
	return profile


## Dijkstra back from the goal region: [cost to goal per region, next region toward the goal].
func _guide(p: Dictionary, goal: int) -> Array:
	var links: Array[Dictionary] = p["links"]
	var n: int = links.size()
	var to_goal := PackedFloat32Array()
	to_goal.resize(n)
	to_goal.fill(INF)
	var toward := PackedInt32Array()
	toward.resize(n)
	toward.fill(-1)
	var done := PackedByteArray()
	done.resize(n)
	to_goal[goal] = 0.0
	var heap := MinHeap.new()
	heap.push(goal, 0.0)
	while not heap.is_empty():
		var r := heap.pop()
		if done[r]:
			continue
		done[r] = 1
		for other in links[r]:
			var c: float = to_goal[r] + links[r][other]
			if c < to_goal[other]:
				to_goal[other] = c
				toward[other] = r
				heap.push(other, c)
	return [to_goal, toward]


## A* over hexes. With a guide it stays in the corridor and aims, from each region,
## at the next region's center plus that region's cost to the goal. Without one it
## searches the whole map by straight-line distance.
func _hex_route(p: Dictionary, from: int, to: int, guide: Array) -> PackedInt32Array:
	var cost: PackedFloat32Array = p["cost"]
	var guided := not guide.is_empty()
	var nb := map.neighbors
	var tq := _q[to]
	var tr := _r[to]
	var touched := PackedInt32Array([from])
	var heap := MinHeap.new()
	_g[from] = 0.0
	heap.push(from, 0.0)
	while not heap.is_empty():
		var i := heap.pop()
		if i == to:
			break
		if _closed[i]:
			continue
		_closed[i] = 1
		for k in range(i * 6, i * 6 + 6):
			var n := nb[k]
			if n < 0 or _closed[n] or cost[n] == INF or _avoid[n] or (guided and not _corridor[_block_id[n]]):
				continue
			var g := _g[i] + cost[n]
			if g < _g[n]:
				if _g[n] == INF:
					touched.append(n)
				_g[n] = g
				_parent[n] = i
				var dq := _q[n] - tq
				var dr := _r[n] - tr
				var h := (absi(dq) + absi(dq + dr) + absi(dr)) / 2.0  # straight for the goal
				heap.push(n, g + h)
	var path := PackedInt32Array()
	if _g[to] < INF:
		var i := to
		while i != from:
			path.append(i)
			i = _parent[i]
		path.append(from)
		path.reverse()
	for i in touched:
		_g[i] = INF
		_parent[i] = -1
		_closed[i] = 0
	return path
