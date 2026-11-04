class_name Progression
## XP, levels and promotion (SPEC §9.4, §12.2). Plain static rules: GameState awards XP
## after battles and logs what happens; Edit Units offers promotions.


## XP for each living unit after a battle: 40 × level ratio × charisma factor × talent bonus.
## The level ratio is the enemy's average level over the squad's, clamped 0.5–2; the
## charisma factor is 0.5 + leader charisma/100.
static func battle_xp(data: GameData, own: Squad, enemy: Squad, u: Unit) -> int:
	var p: Dictionary = data.rules["progression"]
	var ratio := clampf(_average_level(enemy) / maxf(1.0, _average_level(own)), float(p["level_ratio"][0]), float(p["level_ratio"][1]))
	var charisma := 0.5 + (own.leader.charisma / 100.0 if own.leader else 0.0)
	var talent := 1.0 + float(data.rules["talents"][u.talent]["xp_bonus"])
	return roundi(float(p["battle_xp"]) * ratio * charisma * talent)


static func _average_level(s: Squad) -> float:
	if s.units.is_empty():
		return 1.0
	var total := 0
	for u in s.units:
		total += u.level
	return float(total) / s.units.size()


## XP needed for the next level: 100 × the class's XP rate.
static func level_cost(data: GameData, u: Unit) -> int:
	return roundi(float(data.rules["progression"]["level_xp"]) * float(u.info(data)["xp_rate"]))


## Adds XP and levels the unit up as often as it pays for. Returns each level-up's
## stat gains ({stat: +n}), in order.
static func gain_xp(data: GameData, u: Unit, amount: int, rng: RandomNumberGenerator) -> Array[Dictionary]:
	var ups: Array[Dictionary] = []
	u.xp += amount
	while u.xp >= level_cost(data, u):
		u.xp -= level_cost(data, u)
		ups.append(level_up(data, u, rng))
	return ups


## One level: key stats +1; every other stat grows on its hidden chance (plus the talent's
## bonus), and surely if it hasn't grown in the last 3 levels. HP rises with CON.
static func level_up(data: GameData, u: Unit, rng: RandomNumberGenerator) -> Dictionary:
	var before := u.max_hp(data)
	var bonus := float(data.rules["talents"][u.talent]["growth_bonus"])
	var guarantee := int(data.rules["progression"]["growth_guarantee"])
	var gains := {}
	u.level += 1
	for s in Unit.STATS:
		var grows: bool
		if s in u.info(data)["key_stats"]:
			grows = true
		else:
			u.since_growth[s] = int(u.since_growth.get(s, 0)) + 1
			grows = rng.randf() < float(u.growth.get(s, 0.0)) + bonus or int(u.since_growth[s]) >= guarantee
			if grows:
				u.since_growth[s] = 0
		if grows:
			u.stats[s] += 1
			gains[s] = 1
	if u.is_alive():
		u.hp += u.max_hp(data) - before
	return gains


## The classes the unit can promote into now: the next stage on its lines, once it has
## the level for that stage (3, 6, 9). A class with a branch lean (Witch, dragons) only
## promotes into next classes whose Holy, Evil or Neutral lean matches the unit's band.
static func promotion_options(data: GameData, u: Unit) -> Array[String]:
	var out: Array[String] = []
	var p: Dictionary = data.rules["progression"]
	var branch: bool = u.info(data)["alignment_lean"] in p["branch_leans"]
	for c in data.next_classes(u.unit_class):
		var stage := str(int(data.units[c]["stage"]))
		if not p["promotion_levels"].has(stage) or u.level < int(p["promotion_levels"][stage]):
			continue
		var lean: String = data.units[c]["alignment_lean"]
		if branch and lean in ["Holy", "Evil", "Neutral"] and lean.to_lower() != u.alignment_band(data):
			continue
		out.append(c)
	return out


## The level the unit needs for its next promotion, or 0 at its final stage.
static func next_promotion_level(data: GameData, u: Unit) -> int:
	var next := data.next_classes(u.unit_class)
	if next.is_empty():
		return 0
	return int(data.rules["progression"]["promotion_levels"].get(str(int(data.units[next[0]]["stage"])), 0))


## Changes the class, adding the difference between the two classes' base stats.
static func promote(data: GameData, u: Unit, new_class: String) -> Dictionary:
	var before := u.max_hp(data)
	var old: Dictionary = data.units[u.unit_class]["base_stats"]
	var new: Dictionary = data.units[new_class]["base_stats"]
	var gains := {}
	for s in Unit.STATS:
		var d := int(new[s]) - int(old[s])
		u.stats[s] += d
		if d != 0:
			gains[s] = d
	u.unit_class = new_class
	if u.is_alive():
		u.hp = clampi(u.hp + u.max_hp(data) - before, 1, u.max_hp(data))
	return gains


## "STR +1, CON +1".
static func gains_text(gains: Dictionary) -> String:
	var parts := []
	for s in gains:
		parts.append("%s %+d" % [s, gains[s]])
	return ", ".join(parts) if not parts.is_empty() else "no stat changes"
