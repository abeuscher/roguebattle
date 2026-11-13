class_name GameConfig
extends RefCounted
## The configurator's settings (SPEC §4, §6.2): one value per field in
## data/configurator.json, plus the seed. Map fields feed MapGen; game fields
## (victory, defeat, squad cap, fairness) feed the game. Settings and seed
## pack into a short share code.

const CODE_VERSION := 5  # 2: "size" became "width"/"height" (§6.1); 3: Land % to 100 and the No Ocean preset; 4: game mode and XP rate; 5: Quick start mode, heights from 45
const ALPHABET := "0123456789ABCDEFGHJKMNPQRSTVWXYZ"  # 32 symbols, no I, L, O or U

var data: GameData
var values := {}  # field key -> chosen option
var seed := 0
var player_name := ""  # the Game summary's "Your name" (round 11): the Opinion Leader's name; not in the share code


static func create(game_data: GameData, game_seed := 0) -> GameConfig:
	var c := GameConfig.new()
	c.data = game_data
	c.seed = game_seed
	for f in game_data.config_fields:
		if f["target"] == "game":
			c.values[f["key"]] = f["default"]
	c.values["preset"] = game_data.mapgen["defaults"]["preset"]
	c.values["width"] = game_data.mapgen["defaults"]["width"]
	c.values["height"] = game_data.mapgen["defaults"]["height"]
	c.apply_preset()
	c.fit_squad_cap()
	return c


## Quick start's settings (rules.json quick_start): its mode and its small map, the rest
## as the defaults. The Start screen's Quick Start begins a game straight from these.
static func quick(game_data: GameData, game_seed := 0) -> GameConfig:
	var c := create(game_data, game_seed)
	var m: Dictionary = game_data.rules["quick_start"]["map"]
	c.set_value("preset", m["preset"])  # first: the map type resets the fields below
	for k in m:
		c.set_value(k, m[k])
	c.set_value("mode", "quick")
	return c


static func options(f: Dictionary) -> Array:
	if f.has("options"):
		return f["options"]
	var out := []
	var r: Array = f["range"]
	var v: float = r[0]
	while v <= r[1] + 0.0001:
		out.append(v)
		v += r[2]
	return out


## "Small"/"Medium"/"Large" for an exact match with data/mapgen.json's named
## sizes (§6.1), or "Custom" for any other width and height.
static func size_name(game_data: GameData, width: int, height: int) -> String:
	for n in game_data.mapgen["sizes"]:
		var dims: Array = game_data.mapgen["sizes"][n]
		if int(dims[0]) == width and int(dims[1]) == height:
			return String(n).capitalize()
	return "Custom"


func field(key: String) -> Dictionary:
	for f in data.config_fields:
		if f["key"] == key:
			return f
	return {}


## Sets a value; choosing a map type resets the fields that map type decides.
func set_value(key: String, value: Variant) -> void:
	values[key] = value
	if key == "preset":
		apply_preset()
	elif key == "land_pct":  # within what the map type allows
		values[key] = _nearest(field(key), MapGen.resolve_settings(data, map_overrides())["land_pct"])
	if key in ["mode", "width", "height"]:
		fit_squad_cap()


## The squads-on-the-map default follows the map: in single map mode, rules.json
## single_map.squad_cap_by_size for the named size nearest in area; otherwise the
## field's own default. The player can still move it afterwards.
func fit_squad_cap() -> void:
	var f := field("squad_cap")
	if values.get("mode", "campaign") == "campaign":
		values["squad_cap"] = f["default"]
		return
	var area := int(values["width"]) * int(values["height"])
	var best := ""
	for n in data.mapgen["sizes"]:
		var dims: Array = data.mapgen["sizes"][n]
		if best == "" or absi(int(dims[0]) * int(dims[1]) - area) < absi(int(data.mapgen["sizes"][best][0]) * int(data.mapgen["sizes"][best][1]) - area):
			best = n
	values["squad_cap"] = _nearest(f, data.rules["single_map"]["squad_cap_by_size"][best])


## Map fields take the generator's defaults overlaid with the chosen preset's values.
func apply_preset() -> void:
	var s := MapGen.resolve_settings(data, {"preset": values["preset"]})
	for f in data.config_fields:
		if f["target"] != "map" or f["key"] in ["preset", "width", "height"]:
			continue
		var v: Variant = _lookup(s, f["key"])
		if f.has("scale"):
			v = float(v) / float(f["scale"])
		values[f["key"]] = _nearest(f, v)


## Overrides for MapGen.generate.
func map_overrides() -> Dictionary:
	var out := {}
	for f in data.config_fields:
		if f["target"] != "map":
			continue
		var v: Variant = values[f["key"]]
		if f.has("scale"):
			v = float(v) * float(f["scale"])
		var parts: PackedStringArray = f["key"].split(".")
		if parts.size() == 2:
			if not out.has(parts[0]):
				out[parts[0]] = {}
			out[parts[0]][parts[1]] = v
		else:
			out[parts[0]] = v
	if values.get("mode", "") == "quick":  # a small map still gets a few of each building
		out["building_min"] = data.rules["quick_start"]["buildings"]
		out["town_near_base"] = data.rules["quick_start"]["town_near_base"]
	return out


## Victory, defeat, squad cap and fairness settings.
func game_settings() -> Dictionary:
	var out := {}
	for f in data.config_fields:
		if f["target"] == "game":
			out[f["key"]] = values[f["key"]]
	if player_name != "":
		out["player_name"] = player_name
	return out


## Settings and seed as a short code, such as "1K7Q-3MX0-…". Groups of four are split by dashes.
func to_code() -> String:
	var bits := PackedByteArray()
	_put(bits, CODE_VERSION, 4)
	_put(bits, seed & 0xffffffff, 32)
	for f in data.config_fields:
		var opts := options(f)
		_put(bits, maxi(0, _index_of(opts, values[f["key"]])), _width(opts.size()))
	while bits.size() % 5 != 0:
		bits.append(0)
	var chars := ""
	for i in range(0, bits.size(), 5):
		var v := 0
		for j in 5:
			v = v * 2 + bits[i + j]
		if i > 0 and (i / 5) % 4 == 0:
			chars += "-"
		chars += ALPHABET[v]
	return chars


## Reads a share code; null if it isn't a valid one.
static func from_code(game_data: GameData, code: String) -> GameConfig:
	var bits := PackedByteArray()
	for ch in code.to_upper().replace("-", "").replace(" ", ""):
		var v := ALPHABET.find(ch)
		if v < 0:
			return null
		for j in range(4, -1, -1):
			bits.append((v >> j) & 1)
	var cursor := [0]
	var take := func(width: int) -> int:
		if cursor[0] + width > bits.size():
			return -1
		var v := 0
		for j in width:
			v = v * 2 + bits[cursor[0] + j]
		cursor[0] += width
		return v
	if take.call(4) != CODE_VERSION:
		return null
	var c := GameConfig.new()
	c.data = game_data
	c.seed = take.call(32)
	if c.seed < 0:
		return null
	for f in game_data.config_fields:
		var opts := options(f)
		var index: int = take.call(_width(opts.size()))
		if index < 0 or index >= opts.size():
			return null
		c.values[f["key"]] = opts[index]
	return c


static func _lookup(s: Dictionary, key: String) -> Variant:
	var parts := key.split(".")
	return s[parts[0]][parts[1]] if parts.size() == 2 else s[key]


## The option equal to `v`, or the closest one for numbers.
static func _nearest(f: Dictionary, v: Variant) -> Variant:
	var opts := options(f)
	var i := _index_of(opts, v)
	if i >= 0:
		return opts[i]
	var best: Variant = opts[0]
	for o in opts:
		if (o is float or o is int) and absf(float(o) - float(v)) < absf(float(best) - float(v)):
			best = o
	return best


static func _index_of(opts: Array, v: Variant) -> int:
	for i in opts.size():
		if typeof(opts[i]) == typeof(v) or ((opts[i] is float or opts[i] is int) and (v is float or v is int)):
			if opts[i] == v:
				return i
	return -1


static func _width(n: int) -> int:
	var w := 1
	while (1 << w) < n:
		w += 1
	return w


static func _put(bits: PackedByteArray, value: int, width: int) -> void:
	for j in range(width - 1, -1, -1):
		bits.append((value >> j) & 1)
