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
var extra_slots := 0  # slots earned as a leader (§8.2)
var element := ""  # overrides the class's element when set (Skeletons)
# Hidden (§12.2)
var growth := {}  # non-key stat -> chance to grow per level, before talent
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
	return int(stats["CON"]) * int(data.rules["hp_per_con"])


func is_alive() -> bool:
	return hp > 0


func info(data: GameData) -> Dictionary:
	return data.units[unit_class]


func slots(data: GameData) -> float:
	return data.slots_for(info(data))


## The sheet's terrain for this class: Plains, Forest, ..., Water, Sky.
func terrain(data: GameData) -> String:
	return info(data)["terrain"]


## "evil", "neutral" or "holy" (§9.2).
func alignment_band(data: GameData) -> String:
	var bands: Dictionary = data.rules["alignment_bands"]
	if alignment <= int(bands["evil_max"]):
		return "evil"
	return "holy" if alignment >= int(bands["holy_min"]) else "neutral"
