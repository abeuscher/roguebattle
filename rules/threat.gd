class_name Threat
## Threat rating (SPEC §12.4): one number per unit and squad from stats, attacks per
## battle and stage, scaled by HP left. It drives the pre-battle label and the Strong
## tactic, and later scales enemies and guides the AI.
##
## A unit's offense is the damage its attacks would do in a battle to an average
## stage-2 unit (healing and support count too); its durability is how many average
## hits it can take. A squad's power is total offense × total durability, as in a
## battle of attrition. Stage is already in the stats, since later stages have more.

## The average stage-2 unit: the yardstick for offense and durability.
static func yardstick(data: GameData) -> Dictionary:
	if data.threat_ref.is_empty():
		var sum := {}
		var n := 0
		for c in data.units.values():
			if int(c["stage"]) == 2:
				n += 1
				for s in Unit.STATS:
					sum[s] = float(sum.get(s, 0.0)) + float(c["base_stats"][s])
		for s in Unit.STATS:
			sum[s] = sum[s] / n
		data.threat_ref = sum
	return data.threat_ref


## Damage (or healing, or support value) per battle against the reference unit.
static func offense(data: GameData, u: Unit) -> float:
	if not u.is_alive():
		return 0.0
	var t: Dictionary = data.battle["threat"]
	var ref := yardstick(data)
	var c := u.info(data)
	var kind: String = c["front_attack" if u.row == "front" else "back_attack"]
	var attacks := float(c["front_count" if u.row == "front" else "back_count"])
	var per_hit: float
	match Battle.base_kind(kind):
		"Magic", "Dispel":
			per_hit = maxf(1.0, u.stat(data, "INT") - ref["MDEF"])
		"Breath":
			per_hit = maxf(1.0, (u.stat(data, "STR") + u.stat(data, "INT")) * 0.5 - ref["MDEF"] * 0.5)
		"Heal":
			per_hit = u.stat(data, "INT") * float(data.battle["heal_int_share"])
		"Buff", "Debuff", "Ward":
			per_hit = float(t["support_share"]) * maxf(1.0, ref["STR"] - ref["PDEF"])
		_:
			per_hit = maxf(1.0, u.stat(data, "STR") - ref["PDEF"])
	return per_hit * attacks * float(t["group"].get(Battle.group_of(kind), 1.0))


## How many average hits (half physical, half magic) the unit can take now.
static func durability(data: GameData, u: Unit) -> float:
	if not u.is_alive():
		return 0.0
	var ref := yardstick(data)
	var incoming := 0.5 * maxf(1.0, ref["STR"] - u.stat(data, "PDEF")) + 0.5 * maxf(1.0, ref["INT"] - u.stat(data, "MDEF"))
	return u.hp / incoming


static func unit(data: GameData, u: Unit) -> float:
	return sqrt(offense(data, u) * durability(data, u))


## Total offense × total durability.
static func squad(data: GameData, s: Squad) -> float:
	var off := 0.0
	var dur := 0.0
	for u in s.units:
		off += offense(data, u)
		dur += durability(data, u)
	return off * dur


## Weaker, Even, Stronger or Dangerous: how `enemy` compares with `own`.
static func label(data: GameData, own: Squad, enemy: Squad) -> String:
	var ratio := squad(data, enemy) / maxf(0.001, squad(data, own))
	for entry in data.battle["threat_labels"]:
		if ratio < float(entry[1]):
			return entry[0]
	return data.battle["threat_labels"][-1][0]
