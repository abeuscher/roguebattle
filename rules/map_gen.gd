class_name MapGen
extends RefCounted
## Builds a map from settings plus seed. Layers run in order (SPEC §6.2) and
## each reads the ones before it: size, land shape, terrain features (with
## rivers and lava flows), a pass that keeps all land reachable on foot, then
## buildings, roads and lairs (MapPlaces).

var data: GameData
var map: MapData
var settings: Dictionary
var rng: RandomNumberGenerator
var _px: PackedFloat32Array  # hex center in "hex widths", for noise sampling
var _py: PackedFloat32Array
var _ridge: PackedFloat32Array
var _flow: PackedFloat32Array  # low ground that rivers and lava follow
var _edge: PackedFloat32Array  # squared distance from the map center: 0 there, 1 at the edge midpoints
var _water: PackedByteArray  # per terrain id


static func generate(game_data: GameData, game_seed: int, overrides: Dictionary = {}) -> MapData:
	var g := MapGen.new()
	g.data = game_data
	g.settings = resolve_settings(game_data, overrides)
	g.rng = RngStreams.new(game_seed).get_stream("map")
	var dims: Array = game_data.mapgen["sizes"][g.settings["size"]]
	g.map = MapData.new(int(dims[0]), int(dims[1]))
	g.map.seed = game_seed
	g.map.settings = g.settings
	g._layout()
	g._land_shape()
	g._terrain_features()
	g._rivers()
	g._lava_flows()
	g._ensure_reachable()
	MapPlaces.place_all(g.map, game_data, g.settings, g.rng)
	return g.map


## Defaults, then the preset's values, then the caller's overrides.
## Dictionary values (terrain amounts and scales) merge key by key.
static func resolve_settings(game_data: GameData, overrides: Dictionary) -> Dictionary:
	var s: Dictionary = game_data.mapgen["defaults"].duplicate(true)
	var preset: String = overrides.get("preset", s["preset"])
	s["preset"] = preset
	for layer in [game_data.mapgen["presets"][preset], overrides]:
		for k in layer:
			if layer[k] is Dictionary:
				s[k].merge(layer[k].duplicate(true), true)
			else:
				s[k] = layer[k]
	return s


## 1 for hexes a ground squad can enter: passable terrain, or any road or bridge.
static func ground_passable(m: MapData, game_data: GameData) -> PackedByteArray:
	var blocked := terrain_flags(game_data, "impassable")
	var out := PackedByteArray()
	out.resize(m.size())
	for i in m.size():
		out[i] = 1 if m.road[i] or not blocked[m.terrain[i]] else 0
	return out


## 1 per terrain id where terrain.json sets `flag`, for fast lookups in hex loops.
static func terrain_flags(game_data: GameData, flag: String) -> PackedByteArray:
	var out := PackedByteArray()
	for t in game_data.terrains:
		out.append(1 if t.get(flag, false) else 0)
	return out


func _id(key: String) -> int:
	return data.terrain_ids[key]


## Water or air: what rivers run into and what isn't land.
func _is_water(t: int) -> bool:
	return _water[t] == 1


func _layout() -> void:
	_water = terrain_flags(data, "water")
	_water[_id("air_gap")] = 1
	_px.resize(map.size())
	_py.resize(map.size())
	_edge.resize(map.size())
	var h := map.height * Hex.SQRT3 * 0.5
	for i in map.size():
		var row := i / map.width
		_px[i] = i % map.width + 0.5 * (row & 1)
		_py[i] = row * Hex.SQRT3 * 0.5
		var dx := _px[i] / map.width * 2.0 - 1.0
		var dy := _py[i] / h * 2.0 - 1.0
		_edge[i] = dx * dx + dy * dy


func _noise(field: String, frequency: float, ridged := false) -> FastNoiseLite:
	var n := FastNoiseLite.new()
	n.seed = RngStreams.derive_seed(map.seed, "map/" + field)
	n.noise_type = FastNoiseLite.TYPE_SIMPLEX_SMOOTH
	n.fractal_type = FastNoiseLite.FRACTAL_RIDGED if ridged else FastNoiseLite.FRACTAL_FBM
	n.fractal_octaves = 5
	n.frequency = frequency / map.width  # features scale with the map
	return n


## Noise field over every hex, mapped to roughly 0..1.
func _field(field: String, frequency: float, ridged := false) -> PackedFloat32Array:
	var n := _noise(field, frequency, ridged)
	var out := PackedFloat32Array()
	out.resize(map.size())
	for i in map.size():
		out[i] = n.get_noise_2d(_px[i], _py[i]) * 0.5 + 0.5
	return out



# --- Layer 2: land shape ---------------------------------------------------

func _land_shape() -> void:
	var elev: PackedFloat32Array
	match settings["shape"]:
		"islands":
			elev = _islands_elevation()
		_:
			elev = _field("elevation", float(settings["noise_frequency"]))
			for i in map.size():
				elev[i] -= float(settings["edge_falloff"]) * _edge[i]
			# Thin straits cut the land apart (archipelago).
			var cut_at := float(settings["strait_cut"])
			if cut_at > 0.0:
				var straits := _field("straits", 6.0, true)
				for i in map.size():
					if straits[i] > cut_at:
						elev[i] = -1e9
	var cut := _cutoff(elev, int(map.size() * float(settings["land_pct"]) / 100.0))
	var land := PackedByteArray()
	land.resize(map.size())
	for i in map.size():
		land[i] = 1 if elev[i] >= cut else 0
	if settings["shape"] == "continent":
		_keep_landmasses(land, 0, true)
		_add_islands(land)
	else:
		_keep_landmasses(land, int(settings["min_island_hexes"]), false)
	var sea := _id(settings["sea"])
	var shelf_width := int(settings["shelf_width"]) if sea == _id("deep") else 0
	var shelf := map.distance_from(land, shelf_width)
	var plains := _id("plains")
	var shallow := _id("shallow")
	for i in map.size():
		if land[i]:
			map.terrain[i] = plains
		else:
			map.terrain[i] = shallow if shelf[i] >= 0 else sea


## Elevation around 2+ island centers, with water forced along the lines between them.
func _islands_elevation() -> PackedFloat32Array:
	var range_: Array = settings["centers"]
	var k := rng.randi_range(int(range_[0]), int(range_[1]))
	var w := float(map.width)
	var h := map.height * Hex.SQRT3 * 0.5
	var centers: Array[Vector2] = []
	var spacing := sqrt(w * h / k) * 0.8
	while centers.size() < k:
		for attempt in 300:
			var c := Vector2(rng.randf_range(0.15, 0.85) * w, rng.randf_range(0.2, 0.8) * h)
			if centers.all(func(o): return c.distance_to(o) >= spacing):
				centers.append(c)
				if centers.size() == k:
					break
		spacing *= 0.9
	var spread := sqrt(w * h / k) * 0.5
	var elev := _field("elevation", float(settings["noise_frequency"]))
	var channel: float = settings["channel_width"]
	# Warp positions so the channels between islands wander instead of running straight.
	var warp_x := _field("warp_x", 3.0)
	var warp_y := _field("warp_y", 3.0)
	var amp := w * 0.12
	for i in map.size():
		var p := Vector2(_px[i] + (warp_x[i] - 0.5) * amp, _py[i] + (warp_y[i] - 0.5) * amp)
		var d1 := INF
		var d2 := INF
		for c in centers:
			var d := p.distance_to(c)
			if d < d1:
				d2 = d1
				d1 = d
			elif d < d2:
				d2 = d
		if d2 - d1 < channel:
			elev[i] = -1e9
		else:
			elev[i] -= float(settings["center_falloff"]) * pow(d1 / spread, 2) * 0.5 \
					+ float(settings["edge_falloff"]) * _edge[i]
	return elev


## Drops landmasses smaller than `min_size`, or all but the largest.
func _keep_landmasses(land: PackedByteArray, min_size: int, largest_only: bool) -> void:
	var result := map.components(land)
	var comp: PackedInt32Array = result[0]
	var sizes: PackedInt32Array = result[1]
	if sizes.is_empty():
		return
	var biggest := Array(sizes).find(Array(sizes).max())
	for i in map.size():
		if comp[i] >= 0 and (sizes[comp[i]] < min_size or (largest_only and comp[i] != biggest)):
			land[i] = 0


func _add_islands(land: PackedByteArray) -> void:
	var radius := float(data.mapgen["island_radius"][settings["island_size"]]) * map.width / 400.0
	var gap := map.distance_from(land, int(radius * 2 + 4))
	var shape := _field("islands", 40.0)
	var centers: Array[Vector2i] = []
	for n in int(settings["island_count"]):
		for attempt in 200:
			var c := map.hex_at(rng.randi_range(0, map.size() - 1))
			var o := Hex.to_offset(c)
			if gap[map.index_of(c)] >= 0 or o.x < radius or o.y < radius \
					or o.x >= map.width - radius or o.y >= map.height - radius:
				continue
			if centers.any(func(other): return Hex.distance(c, other) < radius * 3):
				continue
			centers.append(c)
			_grow_island(land, c, radius, shape)
			break


func _grow_island(land: PackedByteArray, center: Vector2i, radius: float, shape: PackedFloat32Array) -> void:
	var reach := int(ceil(radius * 1.3))
	for dr in range(-reach, reach + 1):
		for dq in range(-reach, reach + 1):
			var h := center + Vector2i(dq, dr)
			if not map.in_bounds(h):
				continue
			var i := map.index_of(h)
			if Hex.distance(h, center) < radius * (0.6 + 0.7 * shape[i]):
				land[i] = 1


# --- Layer 3: terrain features ---------------------------------------------

func _terrain_features() -> void:
	var plains := _id("plains")
	var land := PackedInt32Array()
	for i in map.size():
		if map.terrain[i] == plains:
			land.append(i)
	var h := map.height * Hex.SQRT3 * 0.5
	_ridge = _field("ridge", 4.0, true)
	var ridge := _ridge
	var lava := _field("lava", 6.0)
	var moist := _field("moisture", 3.0)
	var woods := _field("woods", 5.0)
	var heat := _field("heat", 2.0)
	var cold := PackedFloat32Array()
	var dry := PackedFloat32Array()
	var wet := PackedFloat32Array()
	for a in [cold, dry, wet]:
		a.resize(map.size())
	for i in map.size():
		var t := 0.6 * (_py[i] / h) + 0.4 * heat[i]  # north is colder
		lava[i] = lava[i] * 0.5 + ridge[i]  # lava sits in the hills
		cold[i] = -t
		dry[i] = t - moist[i]
		wet[i] = moist[i] - ridge[i] * 0.5  # swamps sit low
	# Each terrain takes the best-scoring plains left, in this order.
	var scores := {
		"cliff": ridge,  # the crests of the ranges
		"mountain": ridge,
		"lava": lava,
		"snow": cold,
		"desert": dry,
		"swamp": wet,
		"forest": woods,
	}
	for key in scores:
		_assign(land, _id("plains"), _id(key), int(land.size() * target_fraction(data, settings, key)), scores[key])
	# Frozen lakes: blobs cut out of the snow (Tundra).
	var lake_share := float(settings["frozen_lakes"])
	if lake_share > 0.0:
		var snow_count := map.terrain.count(_id("snow"))
		_assign(land, _id("snow"), _id("frozen_lake"), int(snow_count * lake_share), _field("lakes", 14.0))


## The share of land a terrain is meant to cover under these settings.
static func target_fraction(game_data: GameData, s: Dictionary, key: String) -> float:
	var amount: String = s["terrain_amounts"].get(key, "none")
	return float(game_data.mapgen["amount_fractions"][amount]) * float(s["terrain_scale"].get(key, 1.0))


## Turns the `count` best-scoring `from` hexes among `land` into `terrain_id`.
func _assign(land: PackedInt32Array, from: int, terrain_id: int, count: int, score: PackedFloat32Array) -> void:
	if count <= 0:
		return
	var cand := PackedInt32Array()
	var vals := PackedFloat32Array()
	for i in land:
		if map.terrain[i] == from:
			cand.append(i)
			vals.append(score[i])
	var cut := _cutoff(vals, count)
	for j in cand.size():
		if vals[j] >= cut:
			map.terrain[cand[j]] = terrain_id


## The value at or above which `count` of `values` lie.
static func _cutoff(values: PackedFloat32Array, count: int) -> float:
	if count <= 0:
		return INF
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[maxi(0, sorted.size() - count)]


# --- Rivers and lava flows ---------------------------------------------------

func _rivers() -> void:
	var count := int(settings["rivers"])
	if count == 0:
		return
	var dist := _distance_to_water()
	var max_dist: int = Array(dist).max()
	var sources := _pick_sources(count, func(i): return dist[i] >= maxi(8, int(max_dist * 0.4)), 25)
	var spacing := int(settings["river_crossing_spacing"])
	for src in sources:
		var path := _downhill(src, dist, 1 << 30)
		if path.size() < 12:
			continue
		for i in path:
			map.terrain[i] = _id("deep")
		# Crossings along the river, alternating bridge and ford.
		var bridge := rng.randf() < 0.5
		for j in range(spacing / 2, path.size(), spacing):
			if bridge:
				map.road[path[j]] |= MapData.ROAD_STANDALONE
			else:
				map.terrain[path[j]] = _id("shallow")
			bridge = not bridge
		map.rivers.append(path)


func _lava_flows() -> void:
	var count := int(settings["lava_flows"])
	if count == 0:
		return
	var dist := _distance_to_water()
	var sources := _pick_sources(count, func(i): return map.terrain[i] == _id("mountain") and dist[i] > 3, 15)
	for src in sources:
		for i in _downhill(src, dist, int(settings["lava_flow_length"])):
			map.terrain[i] = _id("lava")


func _distance_to_water() -> PackedInt32Array:
	var water := PackedByteArray()
	water.resize(map.size())
	for i in map.size():
		water[i] = 1 if _is_water(map.terrain[i]) else 0
	return map.distance_from(water, map.width + map.height)


## Up to `count` random hexes passing `ok`, at least `spacing` apart.
func _pick_sources(count: int, ok: Callable, spacing: int) -> Array[int]:
	var out: Array[int] = []
	for attempt in count * 200:
		if out.size() == count:
			break
		var i := rng.randi_range(0, map.size() - 1)
		if not ok.call(i):
			continue
		var h := map.hex_at(i)
		if out.all(func(o): return Hex.distance(h, map.hex_at(o)) >= spacing):
			out.append(i)
	return out


## A winding path toward water, following low ground in a noise field. It may
## run level for a few steps but never climbs, and stops before water (or an
## earlier river), or after `max_len` hexes.
func _downhill(start: int, dist: PackedInt32Array, max_len: int) -> PackedInt32Array:
	if _flow.is_empty():
		_flow = _field("flow", 10.0)
	var path := PackedInt32Array()
	var visited := {}
	var cur := start
	var level_steps := 0
	while path.size() < max_len and dist[cur] > 0 and not _is_water(map.terrain[cur]):
		path.append(cur)
		visited[cur] = true
		var best := -1
		var best_score := INF
		for k in 6:
			var n := map.neighbors[cur * 6 + k]
			if n < 0 or visited.has(n) or dist[n] > dist[cur] or (dist[n] == dist[cur] and level_steps >= 3):
				continue
			var score := dist[n] + 40.0 * _flow[n]
			if score < best_score:
				best_score = score
				best = n
		if best < 0:
			break
		level_steps = level_steps + 1 if dist[best] == dist[cur] else 0
		cur = best
	return path


# --- Reachability ------------------------------------------------------------

## Every landmass must be reachable on foot from the largest one. Where it
## isn't, the cheapest route is cut through: deep water becomes a ford, cliffs
## a pass, lava a gap, and air gaps get a bridge (terrain.json "crossing").
func _ensure_reachable() -> void:
	var passable := ground_passable(map, data)
	var comp: PackedInt32Array = map.components(passable)[0]
	var land_count := {}
	for i in map.size():
		if comp[i] >= 0 and not _is_water(map.terrain[i]):
			land_count[comp[i]] = land_count.get(comp[i], 0) + 1
	if land_count.size() < 2:
		return
	var main: int = land_count.keys().reduce(func(a, b): return a if land_count[a] >= land_count[b] else b)
	# 0-1 search from the main region: entering an impassable hex costs 1.
	var dist := PackedInt32Array()
	dist.resize(map.size())
	dist.fill(1 << 30)
	var parent := PackedInt32Array()
	parent.resize(map.size())
	parent.fill(-1)
	var cur := PackedInt32Array()
	for i in map.size():
		if comp[i] == main:
			dist[i] = 0
			cur.append(i)
	var d := 0
	while not cur.is_empty():
		var nxt := PackedInt32Array()
		var idx := 0
		while idx < cur.size():
			var i := cur[idx]
			idx += 1
			if dist[i] != d:
				continue
			for k in range(i * 6, i * 6 + 6):
				var n := map.neighbors[k]
				if n < 0:
					continue
				var nd := d + (0 if passable[n] else 1)
				if nd < dist[n]:
					dist[n] = nd
					parent[n] = i
					if nd == d:
						cur.append(n)
					else:
						nxt.append(n)
		cur = nxt
		d += 1
	# Cut a route from the closest hex of each other landmass.
	var best := {}
	for i in map.size():
		var c := comp[i]
		if c != main and land_count.has(c) and (not best.has(c) or dist[i] < dist[best[c]]):
			best[c] = i
	for c in best:
		var i: int = best[c]
		var bridged := false  # was the previous step a bridge?
		var prev := -1
		while i >= 0 and comp[i] != main:
			var bridge := false
			if not passable[i]:
				var crossing: String = data.terrains[map.terrain[i]]["crossing"]
				if crossing == "bridge":
					bridge = true
				else:
					map.terrain[i] = _id(crossing)
				passable[i] = 1
			if prev >= 0 and (bridge or bridged):
				map.link_road(prev, i)  # bridges link to each other and to the land at each end
			bridged = bridge
			prev = i
			i = parent[i]
		if bridged and i >= 0:
			map.link_road(prev, i)
