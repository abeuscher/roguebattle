class_name MapPlaces
extends RefCounted
## Map layers 4-7 (SPEC §6.5-6.8): bases, buildings, roads, nomads, hidden
## sites and lairs. Bases come first because roads must link them (§6.6).

const VISIBLE := ["player_base", "enemy_base", "town", "tower", "temple"]

var map: MapData
var data: GameData
var s: Dictionary
var rng: RandomNumberGenerator
var cfg: Dictionary  # data.mapgen
var _area := 1.0  # the map's land relative to mapgen.json's reference_land: scales every count
var _blocked: PackedByteArray  # hexes too close to a building or lair for another
var _road_cost: PackedFloat32Array  # per terrain id; < 0 where roads can't go
var _river: PackedByteArray
var _water: PackedByteArray  # per terrain id
var _g: PackedFloat32Array  # pathfinding scratch
var _parent: PackedInt32Array
var _closed: PackedByteArray
var _net: PackedByteArray  # road hexes on a network that links a visible building (not a lone river bridge)


static func place_all(m: MapData, game_data: GameData, settings: Dictionary, map_rng: RandomNumberGenerator) -> void:
	var p := MapPlaces.new()
	p.map = m
	p.data = game_data
	p.s = settings
	p.rng = map_rng
	p.cfg = game_data.mapgen
	p._setup()
	p._bases()
	p._buildings()
	p._roads()
	p._nomads()
	p._hidden_sites()
	p._lairs()
	p._cover_regions()
	p._town_names()
	p._tower_names()
	p._temple_gods()
	p._shops_min()


func _setup() -> void:
	_blocked.resize(map.size())
	_river.resize(map.size())
	for path in map.rivers:
		for i in path:
			_river[i] = 1
	for t in data.terrains:
		_road_cost.append(float(t.get("road_cost", -1.0)))
	_water = MapGen.terrain_flags(data, "water")
	var land := 0
	for i in map.size():
		if not _water[map.terrain[i]]:
			land += 1
	_area = land / float(cfg["reference_land"])
	_g.resize(map.size())
	_g.fill(INF)
	_parent.resize(map.size())
	_parent.fill(-1)
	_closed.resize(map.size())


func _count(base: float) -> int:
	return roundi(base * _area)


## A building count raised to the settings' building_min for that type (Quick start's
## small map), unless buildings are off.
func _at_least(type: String, n: int) -> int:
	if s["building_density"] == "none":
		return n
	return maxi(n, int(s["building_min"].get(type, 0)))


func _allowed(type: String) -> PackedByteArray:
	var out := PackedByteArray()
	out.resize(data.terrains.size())
	for key in data.buildings[type]["terrains"]:
		out[data.terrain_ids[key]] = 1
	return out


func _add(type: String, i: int, extra: Dictionary = {}) -> Dictionary:
	var b := {"type": type, "hex": i, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false}
	b.merge(extra, true)
	map.buildings.append(b)
	_occupy(i)
	return b


## Blocks every hex closer than the building spacing to `i`.
func _occupy(i: int) -> void:
	var r := int(cfg["building_spacing"]) - 1
	var c := map.hex_at(i)
	for dq in range(-r, r + 1):
		for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
			var h := c + Vector2i(dq, dr)
			if map.in_bounds(h):
				_blocked[map.index_of(h)] = 1


func _pick(candidates: PackedInt32Array) -> int:
	for attempt in 300:
		var i := candidates[rng.randi_range(0, candidates.size() - 1)]
		if not _blocked[i]:
			return i
	for i in candidates:  # crowded: take any free one
		if not _blocked[i]:
			return i
	return -1


# --- Bases (layer 7 settings) ------------------------------------------------

func _bases() -> void:
	var allowed := _allowed("player_base")
	var along := PackedFloat32Array()  # position along the spawn axis
	var across := PackedFloat32Array()
	var cand := PackedInt32Array()
	var horizontal: bool = s["spawn_side"] in ["west", "east"]
	for i in map.size():
		if allowed[map.terrain[i]]:
			var row := i / map.width
			var x := i % map.width + 0.5 * (row & 1)
			cand.append(i)
			along.append(x / map.width if horizontal else float(row) / map.height)
			across.append(float(row) / map.height if horizontal else x / map.width)
	var near_first: bool = s["spawn_side"] in ["west", "north"]
	map.player_base = _base_spot(cand, along, across, near_first)
	_add("player_base", map.player_base)
	map.enemy_base = _base_spot(cand, along, across, not near_first)
	_add("enemy_base", map.enemy_base)


## A hex in the outer strip of candidates on one side, near the middle of that side.
func _base_spot(cand: PackedInt32Array, along: PackedFloat32Array, across: PackedFloat32Array, low_side: bool) -> int:
	var sorted := along.duplicate()
	sorted.sort()
	var k := maxi(1, int(sorted.size() * float(cfg["base_strip"])))
	var cut := sorted[k - 1] if low_side else sorted[sorted.size() - k]
	var best := -1
	var best_score := INF
	for j in cand.size():
		if (along[j] <= cut) == low_side or along[j] == cut:
			var score := absf(across[j] - 0.5) + rng.randf() * 0.15
			if score < best_score and not _blocked[cand[j]]:
				best_score = score
				best = cand[j]
	return best


# --- Towns, towers, temples (layer 4) ----------------------------------------

func _buildings() -> void:
	var scale := float(cfg["density_scale"][s["building_density"]])
	var mountain: int = data.terrain_ids["mountain"]
	var types := ["temple", "town", "tower"]  # pickiest first
	# One pass over the map: candidate hexes per type and quadrant.
	var mask := PackedByteArray()  # per terrain: bit j set if types[j] may stand there
	mask.resize(data.terrains.size())
	var high_flags := PackedByteArray()
	var pools: Array = []  # per type: 4 quadrant pools
	var high_pools: Array = []
	for j in types.size():
		var allowed := _allowed(types[j])
		for t in allowed.size():
			if allowed[t]:
				mask[t] |= 1 << j
		high_flags.append(1 if data.buildings[types[j]].get("high_ground", false) else 0)
		pools.append([PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()])
		high_pools.append([PackedInt32Array(), PackedInt32Array(), PackedInt32Array(), PackedInt32Array()])
	for i in map.size():
		var bits := mask[map.terrain[i]]
		if bits == 0:
			continue
		var q := map.quadrant(i)
		for j in types.size():
			if bits & (1 << j):
				pools[j][q].append(i)
				if high_flags[j] and _near_terrain(i, mountain):
					high_pools[j][q].append(i)
	for j in types.size():
		var type: String = types[j]
		var n := _at_least(type, _count(float(cfg["building_counts"][type]) * scale))
		if n == 0:
			continue
		if type == "town" and s["town_near_base"].size() == 2 and _town_near_base(pools[j]):
			n -= 1
		var high := high_flags[j] == 1
		var by_quadrant: Array = pools[j]
		var high_ground: Array = high_pools[j]
		# Spread evenly: every quadrant gets n / 4, the remainder goes to random quadrants.
		var counts := [n / 4, n / 4, n / 4, n / 4]
		var order := [0, 1, 2, 3]
		_shuffle(order)
		for extra in n % 4:
			counts[order[extra]] += 1
		for q in 4:
			var pool: PackedInt32Array = high_ground[q] if high and high_ground[q].size() > 0 else by_quadrant[q]
			for placed in counts[q]:
				if pool.is_empty():
					break
				var i := _pick(pool)
				if i < 0:
					break
				var info: Dictionary = data.buildings[type]
				_add(type, i, {"shop": rng.randf() < float(info.get("shop_chance", 0.0)),
						"hint": rng.randf() < float(info.get("hint_chance", 0.0))})


## Places one town between town_near_base's two distances from the Player Base (Quick
## start's first fight, close to home). False if no candidate hex is that far.
func _town_near_base(by_quadrant: Array) -> bool:
	var home := map.hex_at(map.player_base)
	var near := PackedInt32Array()
	for pool: PackedInt32Array in by_quadrant:
		for i in pool:
			var dist := Hex.distance(home, map.hex_at(i))
			if dist >= int(s["town_near_base"][0]) and dist <= int(s["town_near_base"][1]):
				near.append(i)
	var i := _pick(near) if near.size() > 0 else -1
	if i < 0:
		return false
	var info: Dictionary = data.buildings["town"]
	_add("town", i, {"shop": rng.randf() < float(info.get("shop_chance", 0.0)), "hint": rng.randf() < float(info.get("hint_chance", 0.0))})
	return true


func _near_terrain(i: int, t: int) -> bool:
	if map.terrain[i] == t:
		return true
	for k in range(i * 6, i * 6 + 6):
		var n := map.neighbors[k]
		if n >= 0 and map.terrain[n] == t:
			return true
	return false


func _shuffle(a: Array) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = a[i]
		a[i] = a[j]
		a[j] = t


# --- Roads (layer 5) -----------------------------------------------------------

## Where a road may run: ground with a road cost, river crossings, existing bridges.
## Roads stop at the open sea, lava and cliffs (§6.6).
func _road_ok() -> PackedByteArray:
	var ok := PackedByteArray()
	ok.resize(map.size())
	for i in map.size():
		var t := map.terrain[i]
		ok[i] = 1 if map.road[i] or _river[i] or (_road_cost[t] >= 0.0 and not _water[t]) else 0
	return ok


func _roads() -> void:
	var loops := float(cfg["road_loops"][s["road_coverage"]])
	if s["road_coverage"] == "none":
		return
	var region: PackedInt32Array = map.components(_road_ok())[0]
	var groups := {}
	for b in map.buildings:
		if b["type"] in VISIBLE and region[b["hex"]] >= 0:
			var r := region[b["hex"]]
			if not groups.has(r):
				groups[r] = PackedInt32Array()
			groups[r].append(b["hex"])
	var edges: Array = []  # [length, a, b]
	for r in groups:
		edges.append_array(_network(groups[r], loops))
	edges.sort_custom(func(x, y): return x[0] < y[0])  # short roads first, so long ones reuse them
	for e in edges:
		map.lay_road(_road_path(e[1], e[2]))


## Minimum spanning tree over the nodes (by hex distance), plus `loops` x nodes extra short links.
func _network(nodes: PackedInt32Array, loops: float) -> Array:
	var n := nodes.size()
	var hexes: Array[Vector2i] = []
	for i in nodes:
		hexes.append(map.hex_at(i))
	var edges: Array = []
	var linked := {}
	var in_tree := PackedByteArray()
	in_tree.resize(n)
	var best := PackedInt32Array()
	var from := PackedInt32Array()
	best.resize(n)
	best.fill(1 << 30)
	from.resize(n)
	best[0] = 0
	for step in n:
		var u := -1
		for v in n:
			if not in_tree[v] and (u < 0 or best[v] < best[u]):
				u = v
		in_tree[u] = 1
		if step > 0:
			edges.append([best[u], nodes[from[u]], nodes[u]])
			linked[Vector2i(mini(from[u], u), maxi(from[u], u))] = true
		for v in n:
			var d := Hex.distance(hexes[u], hexes[v])
			if not in_tree[v] and d < best[v]:
				best[v] = d
				from[v] = u
	# Extra links make loops: each node's nearest non-linked neighbors, shortest first.
	var extra: Array = []
	for u in n:
		var near: Array = []
		for v in n:
			if v != u and not linked.has(Vector2i(mini(u, v), maxi(u, v))):
				near.append([Hex.distance(hexes[u], hexes[v]), u, v])
		near.sort_custom(func(x, y): return x[0] < y[0])
		extra.append_array(near.slice(0, 2))
	extra.sort_custom(func(x, y): return x[0] < y[0])
	var want := roundi(n * loops)
	for e in extra:
		if want <= 0:
			break
		var key := Vector2i(mini(e[1], e[2]), maxi(e[1], e[2]))
		if not linked.has(key):
			linked[key] = true
			edges.append([e[0], nodes[e[1]], nodes[e[2]]])
			want -= 1
	return edges


## Cheapest road route between two hexes (weighted A*). Existing roads are cheap to reuse.
func _road_path(a: int, b: int) -> PackedInt32Array:
	var target := map.hex_at(b)
	var touched := PackedInt32Array([a])
	var heap := MinHeap.new()
	_g[a] = 0.0
	heap.push(a, 0.0)
	while not heap.is_empty():
		var i := heap.pop()
		if i == b:
			break
		if _closed[i]:
			continue  # stale entry; each hex is expanded once
		_closed[i] = 1
		for k in range(i * 6, i * 6 + 6):
			var n := map.neighbors[k]
			if n < 0 or _closed[n]:
				continue
			var t := map.terrain[n]
			var step: float
			if map.road[n]:
				step = 0.3
			elif _road_cost[t] >= 0.0 and (not _water[t] or _river[n]):
				step = _road_cost[t]
			else:
				continue
			var g := _g[i] + step
			if g < _g[n]:
				if _g[n] == INF:
					touched.append(n)
				_g[n] = g
				_parent[n] = i
				heap.push(n, g + 2.0 * Hex.distance(map.hex_at(n), target))  # weighted: roads needn't be optimal
	var path := PackedInt32Array()
	if _g[b] < INF:
		var i := b
		while i != a:
			path.append(i)
			i = _parent[i]
		path.append(a)
	for i in touched:  # reset scratch for the next search
		_g[i] = INF
		_parent[i] = -1
		_closed[i] = 0
	return path


# --- Nomads, hidden sites (layer 4, after roads) -------------------------------

func _nomads() -> void:
	var n := _at_least("nomads", _count(float(cfg["building_counts"]["nomads"]) * float(cfg["density_scale"][s["building_density"]])))
	if n == 0:
		return
	var allowed := _allowed("nomads")
	var near_road := map.distance_from(map.road, 1)
	var remote_at := int(cfg["nomad_remote_distance"])
	var near_building := map.distance_from(_building_mask(), remote_at)
	var cand := PackedInt32Array()
	var weight := PackedFloat32Array()
	for i in map.size():
		if allowed[map.terrain[i]] and not _blocked[i]:
			var w := 1.0
			if near_road[i] >= 0 and not map.road[i]:
				w *= float(cfg["nomad_road_weight"])
			if near_building[i] < 0:
				w *= float(cfg["nomad_remote_weight"])
			cand.append(i)
			weight.append(w)
	for j in n:
		var i := _weighted_pick(cand, weight)
		if i >= 0:
			_add("nomads", i, {"shop": true})


func _weighted_pick(cand: PackedInt32Array, weight: PackedFloat32Array) -> int:
	var total := 0.0
	for w in weight:
		total += w
	for attempt in 50:
		var roll := rng.randf() * total
		for j in cand.size():
			roll -= weight[j]
			if roll <= 0.0:
				if not _blocked[cand[j]]:
					return cand[j]
				break
	return -1


func _building_mask() -> PackedByteArray:
	var mask := PackedByteArray()
	mask.resize(map.size())
	for b in map.buildings:
		mask[b["hex"]] = 1
	return mask


func _hidden_sites() -> void:
	var n := _count(float(cfg["hidden_site_counts"][s["hidden_sites"]]))
	if n == 0:
		return
	var allowed := _allowed("hidden_site")
	var near_road := map.distance_from(map.road, 1)
	var cand := PackedInt32Array()
	for i in map.size():
		if allowed[map.terrain[i]] and near_road[i] < 0:
			cand.append(i)
	if cand.is_empty():
		return
	var kinds: Array = data.buildings["hidden_site"]["kinds"]
	var ok := _road_ok()
	_mark_networks()
	for j in n:
		var i := _pick(cand)
		if i < 0:
			return
		var site := _add("hidden_site", i, {"hidden": true, "kind": kinds[rng.randi_range(0, kinds.size() - 1)]})
		if rng.randf() < float(s["hidden_road_chance"]) and s["road_coverage"] != "none":
			site["road"] = _road_to_nearest_road(i, ok)


## Marks `_net`: every road hex on a network that reaches a visible building, so a new
## branch joins a real road and not a lone river bridge or another dead end.
func _mark_networks() -> void:
	var comp: PackedInt32Array = map.components(map.road)[0]
	var real := {}
	for b in map.buildings:
		if b["type"] in VISIBLE and map.road[b["hex"]]:
			real[comp[b["hex"]]] = true
	_net.resize(map.size())
	for i in map.size():
		_net[i] = 1 if comp[i] >= 0 and real.has(comp[i]) else 0
	for b in map.buildings:  # a lone town with no road yet is a fine place to end a branch too
		if b["type"] in VISIBLE:
			_net[b["hex"]] = 1


## Lays a road from `start` back to the closest road on a real network (`_net`), if one
## is within reach; the new branch joins that network.
func _road_to_nearest_road(start: int, ok: PackedByteArray) -> bool:
	var parent := {start: -1}
	var frontier := PackedInt32Array([start])
	for step in 60:
		var next := PackedInt32Array()
		for i in frontier:
			for k in range(i * 6, i * 6 + 6):
				var n := map.neighbors[k]
				if n < 0 or parent.has(n) or not ok[n]:
					continue
				parent[n] = i
				if _net[n]:
					var path := PackedInt32Array([n])
					var c := i
					while c >= 0:
						path.append(c)
						c = parent[c]
					map.lay_road(path)
					for h in path:
						_net[h] = 1
					return true
				next.append(n)
		frontier = next
	return false


# --- Lairs (layer 6, placement only) ------------------------------------------

func _lairs() -> void:
	var n := _count(float(cfg["lair_counts"][s["neutral_density"]]))
	if n == 0:
		return
	var near_road := map.distance_from(map.road, int(cfg["lair_road_gap"]) - 1)
	var base_gap := float(cfg["lair_base_gap"]) * map.width / 400.0
	var bases := [map.hex_at(map.player_base), map.hex_at(map.enemy_base)]
	# One pass over the map: candidate hexes per home terrain. Terrains can serve several homes.
	var homes_of: Array = []  # terrain id -> homes
	homes_of.resize(data.terrains.size())
	for t in data.terrains.size():
		homes_of[t] = []
	for home in _native_homes():
		for key in cfg["lair_terrains"][home]:
			homes_of[data.terrain_ids[key]].append(home)
	var pools := {}  # home terrain -> candidate hexes
	for i in map.size():
		var hs: Array = homes_of[map.terrain[i]]
		if hs.is_empty() or near_road[i] >= 0 or _blocked[i]:
			continue
		var h := map.hex_at(i)
		if Hex.distance(h, bases[0]) < base_gap or Hex.distance(h, bases[1]) < base_gap:
			continue
		for home in hs:
			if not pools.has(home):
				pools[home] = PackedInt32Array()
			pools[home].append(i)
	if pools.is_empty():
		return
	var homes: Array = pools.keys()
	var weights := PackedFloat32Array()
	for home in homes:
		weights.append(sqrt(float(pools[home].size())))  # big terrains get more lairs, small ones still some
	for j in n:
		var total := 0.0
		for w in weights:
			total += w
		var roll := rng.randf() * total
		var pick := 0
		while pick < homes.size() - 1 and roll > weights[pick]:
			roll -= weights[pick]
			pick += 1
		var i := _pick(pools[homes[pick]])
		if i >= 0:
			_add_lair(i, homes[pick])


## Unit terrains (sheet Terrain column) that have a lair terrain on the map.
func _native_homes() -> Array:
	var homes := []
	for u in data.units.values():
		if u["terrain"] not in homes and cfg["lair_terrains"].has(u["terrain"]):
			homes.append(u["terrain"])
	homes.sort()
	return homes


func _add_lair(i: int, home: String) -> void:
	var span := maxf(1.0, Hex.distance(map.hex_at(map.player_base), map.hex_at(map.enemy_base)))
	var danger := clampf(Hex.distance(map.hex_at(i), map.hex_at(map.player_base)) / span, 0.0, 1.0)
	map.lairs.append({"hex": i, "home": home, "danger": danger})
	_occupy(i)


## Rule 3 (§6.5): every sizable region of one terrain gets a building or lair.
func _cover_regions() -> void:
	var threshold := float(cfg["sizable_region_share"]) * map.size()
	var region := terrain_regions(map, data)
	var sizes := {}
	for r in region:
		if r >= 0:
			sizes[r] = sizes.get(r, 0) + 1
	var covered := {}
	for b in map.buildings:
		covered[region[b["hex"]]] = true
	for l in map.lairs:
		covered[region[l["hex"]]] = true
	var home_of := {}
	for home in cfg["lair_terrains"]:
		for key in cfg["lair_terrains"][home]:
			home_of[data.terrain_ids[key]] = home
	var members := {}
	for i in map.size():
		var r := region[i]
		if r >= 0 and sizes[r] >= threshold and not covered.has(r) and not _blocked[i]:
			if not members.has(r):
				members[r] = PackedInt32Array()
			members[r].append(i)
	var ok := _road_ok()
	_mark_networks()
	for r in members:
		var i := _pick(members[r])
		if i < 0:
			continue
		var t := map.terrain[i]
		# Neutrals are 25% rarer (user's playtest notes, 2026-11-10): a region gets a lair only
		# cover_lair_chance of the time, otherwise a tower with a road to the network.
		if s["neutral_density"] != "none" and home_of.has(t) and rng.randf() < float(cfg["cover_lair_chance"]):
			_add_lair(i, home_of[t])
		else:
			var tower := _add("tower", i, {"shop": rng.randf() < float(data.buildings["tower"].get("shop_chance", 0.0))})
			if s["road_coverage"] != "none":
				tower["road"] = _road_to_nearest_road(i, ok)


## Connected regions of one ground terrain each: region id per hex (-1 off ground).
static func terrain_regions(m: MapData, game_data: GameData) -> PackedInt32Array:
	var water := MapGen.terrain_flags(game_data, "water")
	var blocked := MapGen.terrain_flags(game_data, "impassable")
	var region := PackedInt32Array()
	region.resize(m.size())
	region.fill(-1)
	var next_id := 0
	for start in m.size():
		var t := m.terrain[start]
		if region[start] >= 0 or water[t] or blocked[t]:
			continue
		var stack := PackedInt32Array([start])
		region[start] = next_id
		while not stack.is_empty():
			var i := stack[stack.size() - 1]
			stack.resize(stack.size() - 1)
			for k in range(i * 6, i * 6 + 6):
				var n := m.neighbors[k]
				if n >= 0 and region[n] < 0 and m.terrain[n] == t:
					region[n] = next_id
					stack.append(n)
		next_id += 1
	return region

## Names every town from the parts in town_names.json (user's playtest notes,
## 2026-11-10): prefix + suffix, sometimes with a word in front; no two alike. Its own
## RNG from the map seed, so names never shift where anything else is placed.
func _town_names() -> void:
	var t: Dictionary = data.town_names
	var r := RandomNumberGenerator.new()
	r.seed = hash([map.seed, "town_names"])
	var used := {}
	for b in map.buildings:
		if b["type"] != "town":
			continue
		var name := ""
		for attempt in 200:
			name = town_name(t, r)
			if not used.has(name):
				break
		used[name] = true
		b["name"] = name


## Names every tower from tower_names.json (user's playtest notes, 2026-11-12): a
## pattern such as "{mage}'s Tower of {thing}" filled from its lists; no two alike.
func _tower_names() -> void:
	var t: Dictionary = data.tower_names
	var r := RandomNumberGenerator.new()
	r.seed = hash([map.seed, "tower_names"])
	var used := {}
	for b in map.buildings:
		if b["type"] != "tower":
			continue
		var name := ""
		for attempt in 200:
			name = tower_name(t, r)
			if not used.has(name):
				break
		used[name] = true
		b["name"] = name


static func tower_name(t: Dictionary, r: RandomNumberGenerator) -> String:
	var name: String = t["patterns"][r.randi() % t["patterns"].size()]
	for part in ["word", "mage", "thing", "adj"]:
		var key := "{%s}" % part
		if name.contains(key):
			name = name.replace(key, t[part][r.randi() % t[part].size()])
	return name


## Gives every temple (and every hidden secret temple) one of the Gods of Perinea
## (user's notes, 2026-11-12; repeats on a map are fine) and names it for the god.
func _temple_gods() -> void:
	var ids: Array = data.gods["gods"].keys()
	var r := RandomNumberGenerator.new()
	r.seed = hash([map.seed, "temple_gods"])
	for b in map.buildings:
		if b["type"] == "temple" or (b["type"] == "hidden_site" and b.get("kind", "") == "secret_temple"):
			var id: String = ids[r.randi() % ids.size()]
			b["god"] = id
			b["name"] = "Temple of %s" % data.gods["gods"][id]["name"]


## At least mapgen.json shops_min.total visible shops, shops_min.town of them in towns
## (playtest round 13), however small the map: random towns without one get one, then
## towers. Its own RNG (map seed + "shops"), so nothing else on the map moves.
func _shops_min() -> void:
	var want: Dictionary = cfg["shops_min"]
	var r := RandomNumberGenerator.new()
	r.seed = hash([map.seed, "shops"])
	var shops := map.buildings.filter(func(b): return b["shop"] and not b["hidden"])
	var towns := shops.filter(func(b): return b["type"] == "town").size()
	var total := shops.size()
	for type in ["town", "tower"]:
		var bare := map.buildings.filter(func(b): return b["type"] == type and not b["shop"] and not b["hidden"])
		_shuffle_with(bare, r)
		for b in bare:
			if total >= int(want["total"]) and (type != "town" or towns >= int(want["town"])):
				break
			b["shop"] = true
			total += 1
			if type == "town":
				towns += 1


func _shuffle_with(a: Array, r: RandomNumberGenerator) -> void:
	for i in range(a.size() - 1, 0, -1):
		var j := r.randi_range(0, i)
		var t: Variant = a[i]
		a[i] = a[j]
		a[j] = t


static func town_name(t: Dictionary, r: RandomNumberGenerator) -> String:
	var name := ""
	while true:
		var a: String = t["prefixes"][r.randi() % t["prefixes"].size()]
		var b: String = t["suffixes"][r.randi() % t["suffixes"].size()]
		name = a + b
		var j := a.length()  # no three letters alike at the join (Mill + ley)
		if not (name[j - 1] == name[j] and (name[j - 2].to_lower() == name[j] or (j + 1 < name.length() and name[j + 1] == name[j]))):
			break
	if r.randf() < float(t["word_chance"]):
		var word: String = t["words"][r.randi() % t["words"].size()]
		if not name.begins_with(word):  # not West Westwick
			name = "%s %s" % [word, name]
	return name
