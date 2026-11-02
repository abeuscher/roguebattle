class_name MapGen
extends RefCounted
## Builds a map from settings plus seed. Layers run in order (SPEC §6.2) and
## each reads the ones before it. So far: size, land shape, terrain features.

var data: GameData
var map: MapData
var settings: Dictionary
var rng: RandomNumberGenerator
var _px: PackedFloat32Array  # hex center in "hex widths", for noise sampling
var _py: PackedFloat32Array


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
	return g.map


## Defaults, then the preset's values, then the caller's overrides.
static func resolve_settings(game_data: GameData, overrides: Dictionary) -> Dictionary:
	var s: Dictionary = game_data.mapgen["defaults"].duplicate(true)
	var preset: String = overrides.get("preset", s["preset"])
	s.merge(game_data.mapgen["presets"][preset].duplicate(true), true)
	for k in overrides:
		if k == "terrain_amounts":
			s[k].merge(overrides[k], true)
		else:
			s[k] = overrides[k]
	return s


func _layout() -> void:
	_px.resize(map.size())
	_py.resize(map.size())
	for i in map.size():
		var row := i / map.width
		_px[i] = i % map.width + 0.5 * (row & 1)
		_py[i] = row * Hex.SQRT3 * 0.5


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
	var land := _continent_mask()
	_add_islands(land)
	var shelf := _distance_from(land, int(data.mapgen["shelf_width"]))
	var plains: int = data.terrain_ids["plains"]
	var shallow: int = data.terrain_ids["shallow"]
	var deep: int = data.terrain_ids["deep"]
	for i in map.size():
		if land[i]:
			map.terrain[i] = plains
		else:
			map.terrain[i] = shallow if shelf[i] >= 0 else deep


func _continent_mask() -> PackedByteArray:
	var elev := _field("elevation", float(settings["noise_frequency"]))
	var falloff: float = settings["edge_falloff"]
	var h := map.height * Hex.SQRT3 * 0.5
	for i in map.size():
		var dx := _px[i] / map.width * 2.0 - 1.0
		var dy := _py[i] / h * 2.0 - 1.0
		elev[i] -= falloff * (dx * dx + dy * dy)
	var cut := _cutoff(elev, int(map.size() * float(settings["land_pct"]) / 100.0))
	var land := PackedByteArray()
	land.resize(map.size())
	for i in map.size():
		land[i] = 1 if elev[i] >= cut else 0
	_keep_largest_landmass(land)
	return land


func _keep_largest_landmass(land: PackedByteArray) -> void:
	var comp := PackedInt32Array()
	comp.resize(map.size())
	comp.fill(-1)
	var sizes: Array[int] = []
	var nb := map.neighbors
	for start in map.size():
		if not land[start] or comp[start] >= 0:
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
				var n := nb[k]
				if n >= 0 and land[n] and comp[n] < 0:
					comp[n] = id
					stack.append(n)
		sizes.append(count)
	var biggest := sizes.find(sizes.max())
	for i in map.size():
		if land[i] and comp[i] != biggest:
			land[i] = 0


func _add_islands(land: PackedByteArray) -> void:
	var radius := float(data.mapgen["island_radius"][settings["island_size"]]) * map.width / 400.0
	var gap := _distance_from(land, int(radius * 2 + 4))
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


## Steps from the nearest marked hex, up to `limit`; -1 beyond it (and 0 on marked hexes).
func _distance_from(marked: PackedByteArray, limit: int) -> PackedInt32Array:
	var dist := PackedInt32Array()
	dist.resize(map.size())
	dist.fill(-1)
	var frontier := PackedInt32Array()
	for i in map.size():
		if marked[i]:
			dist[i] = 0
			frontier.append(i)
	var nb := map.neighbors
	for step in range(1, limit + 1):
		var next := PackedInt32Array()
		for i in frontier:
			for k in range(i * 6, i * 6 + 6):
				var n := nb[k]
				if n >= 0 and dist[n] < 0:
					dist[n] = step
					next.append(n)
		frontier = next
	for i in map.size():
		if marked[i]:
			dist[i] = 0
	return dist


# --- Layer 3: terrain features ---------------------------------------------

func _terrain_features() -> void:
	var plains: int = data.terrain_ids["plains"]
	var land := PackedInt32Array()
	for i in map.size():
		if map.terrain[i] == plains:
			land.append(i)
	var h := map.height * Hex.SQRT3 * 0.5
	var ridge := _field("ridge", 4.0, true)
	var lava := _field("lava", 6.0)
	var moist := _field("moisture", 3.0)
	var woods := _field("woods", 5.0)
	var heat := _field("heat", 2.0)
	for i in map.size():
		heat[i] = 0.6 * (_py[i] / h) + 0.4 * heat[i]  # north is colder
	# Each terrain takes the best-scoring plains left, in this order.
	var scores := {
		"mountain": ridge,
		"lava": _map_values(lava, func(i, v): return v * 0.5 + ridge[i]),  # lava sits in the hills
		"snow": _map_values(heat, func(i, v): return -v),
		"desert": _map_values(heat, func(i, v): return v - moist[i]),
		"swamp": _map_values(moist, func(i, v): return v - ridge[i] * 0.5),
		"forest": woods,
	}
	var fractions: Dictionary = data.mapgen["amount_fractions"]
	for key in scores:
		var amount: String = settings["terrain_amounts"].get(key, "none")
		_assign(land, data.terrain_ids[key], int(land.size() * float(fractions[amount])), scores[key])


func _map_values(values: PackedFloat32Array, f: Callable) -> PackedFloat32Array:
	var out := PackedFloat32Array()
	out.resize(values.size())
	for i in values.size():
		out[i] = f.call(i, values[i])
	return out


func _assign(land: PackedInt32Array, terrain_id: int, count: int, score: PackedFloat32Array) -> void:
	if count <= 0:
		return
	var plains: int = data.terrain_ids["plains"]
	var cand := PackedInt32Array()
	var vals := PackedFloat32Array()
	for i in land:
		if map.terrain[i] == plains:
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
