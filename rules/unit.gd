class_name Unit
extends RefCounted
## One soldier (SPEC §9): class, stats, row, and the hidden rolls of §12.2.

const STATS := ["STR", "CON", "INT", "SPD", "AGI", "PDEF", "MDEF"]

var unit_class: String
var name: String
var level := 1
var xp := 0
var stats := {}  # stat -> value
var hp := 0
var alignment := 50  # 0-100
var charisma := 0  # 0-100
var row := "front"  # "front" or "back"
var col := 0  # position in the row, left to right; a back-row unit stands behind the front-row unit in its column
var extra_slots := 0  # slots earned as a leader (§8.2)
var element := ""  # overrides the class's element when set (Skeletons)
var items := {}  # slot (weapon, armor, jewelry) -> the item worn ({uid, id}, §15.2)
var hp_bonus := 0.0  # extra share of max HP (the Veterans tech)
# Hidden (§12.2)
var growth := {}  # non-key stat -> chance to grow per level, before talent
var since_growth := {}  # non-key stat -> levels since it last grew (§12.2 guarantee)
var talent := "ordinary"
var luck := 0


## Rolls a new unit of `class_name` (§9.3): base stats, flex points weighted toward
## key stats, alignment inside the class's lean, hidden growth, talent and luck, and a name.
static func roll(data: GameData, unit_class_name: String, rng: RandomNumberGenerator, names: NameBook) -> Unit:
	var c: Dictionary = data.units[unit_class_name]
	var r: Dictionary = data.rules["unit_roll"]
	var u := Unit.new()
	u.unit_class = unit_class_name
	for s in STATS:
		u.stats[s] = int(c["base_stats"][s])
	var weights := PackedFloat32Array()
	for s in STATS:
		weights.append(float(r["flex_key_weight"]) if s in c["key_stats"] else 1.0)
	for i in rng.randi_range(int(c["flex_min"]), int(c["flex_max"])):
		u.stats[STATS[rng.rand_weighted(weights)]] += 1
	u.hp = u.max_hp(data)
	var band: Array = r["alignment_leans"].get(c["alignment_lean"], [0, 100])
	u.alignment = rng.randi_range(int(band[0]), int(band[1]))
	u.charisma = rng.randi_range(int(r["charisma"][0]), int(r["charisma"][1]))
	for s in STATS:
		if s not in c["key_stats"]:
			u.growth[s] = snappedf(rng.randf_range(float(r["growth"][0]), float(r["growth"][1])), 0.01)
	var talents: Dictionary = data.rules["talents"]
	var chances := PackedFloat32Array()
	for t in talents:
		chances.append(float(talents[t]["chance"]))
	u.talent = talents.keys()[rng.rand_weighted(chances)]
	u.luck = rng.randi_range(int(r["luck"][0]), int(r["luck"][1]))
	u.name = names.take(rng)
	return u


func max_hp(data: GameData) -> int:
	return roundi(stat(data, "CON") * int(data.rules["hp_per_con"]) * (1.0 + hp_bonus))


## A stat with its items' bonuses.
func stat(data: GameData, s: String) -> int:
	var v := int(stats[s])
	for slot in items:
		v += int(data.items["items"][items[slot]["id"]]["stats"].get(s, 0))
	return v


## Melee weapons need a Melee attack in either row; bows need an archer class.
func can_use(data: GameData, item_id: String) -> bool:
	match data.items["items"][item_id]["use"]:
		"melee":
			return Battle.base_kind(info(data)["front_attack"]) == "Melee" or Battle.base_kind(info(data)["back_attack"]) == "Melee"
		"archer":
			return has_tag(data, "archer")
	return true


func is_alive() -> bool:
	return hp > 0


func info(data: GameData) -> Dictionary:
	return data.units[unit_class]


func slots(data: GameData) -> float:
	return data.slots_for(info(data))


func has_trait(data: GameData, trait_name: String) -> bool:
	return trait_name in info(data)["traits"]


## Tags (flyer, mounted, archer, wolf...) from data/battle.json: by role, class, sheet
## terrain, size, trait, or the class being listed under a Mechanics-tab entry.
func has_tag(data: GameData, tag: String) -> bool:
	var key := unit_class + "|" + tag
	if not data.tag_cache.has(key):
		data.tag_cache[key] = _tagged(data, tag)
	return data.tag_cache[key]


func _tagged(data: GameData, tag: String) -> bool:
	var rule: Dictionary = data.battle["tags"].get(tag, {})
	var c := info(data)
	if unit_class in rule.get("not_classes", []):
		return false
	if c["role"] in rule.get("roles", []) or unit_class in rule.get("classes", []) 			or c["terrain"] in rule.get("terrains", []) or c["size"] in rule.get("sizes", []):
		return true
	for t in rule.get("traits", []):
		if t in c["traits"]:
			return true
	for m in rule.get("mechanics", []):
		if unit_class in data.mechanics[m]["used_by"]:
			return true
	return false


## The sheet's terrain for this class: Plains, Forest, ..., Water, Sky.
func terrain(data: GameData) -> String:
	return info(data)["terrain"]


## "evil", "neutral" or "holy" (§9.2).
func alignment_band(data: GameData) -> String:
	var bands: Dictionary = data.rules["alignment_bands"]
	if alignment <= int(bands["evil_max"]):
		return "evil"
	return "holy" if alignment >= int(bands["holy_min"]) else "neutral"
