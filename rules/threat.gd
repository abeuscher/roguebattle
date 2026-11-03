class_name Threat
## Threat rating (SPEC §12.4): one number per unit and squad, from stats, attacks per
## battle and stage, scaled by HP left. Drives the pre-battle label.


static func unit(data: GameData, u: Unit) -> float:
	if not u.is_alive():
		return 0.0
	var t: Dictionary = data.battle["threat"]
	var c := u.info(data)
	var total := 0
	for s in u.stats:
		total += int(u.stats[s])
	var attacks := int(c["front_count" if u.row == "front" else "back_count"])
	return total * (1.0 + float(t["per_extra_attack"]) * (attacks - 1)) * (1.0 + float(t["per_stage"]) * (int(c["stage"]) - 1)) \
			* float(u.hp) / u.max_hp(data)


static func squad(data: GameData, s: Squad) -> float:
	var total := 0.0
	for u in s.units:
		total += unit(data, u)
	return total


## Weaker, Even, Stronger or Dangerous: how `enemy` compares with `own`.
static func label(data: GameData, own: Squad, enemy: Squad) -> String:
	var ratio := squad(data, enemy) / maxf(0.001, squad(data, own))
	for entry in data.battle["threat_labels"]:
		if ratio < float(entry[1]):
			return entry[0]
	return data.battle["threat_labels"][-1][0]
