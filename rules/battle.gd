class_name Battle
extends RefCounted
## One battle between two squads (SPEC §11.3–11.5, §12.1). Side 0 is the player's.
## run() plays it out and records each action in `events` for the log and the battle view.
## Units take damage directly. Statuses, traits, retreat and outcomes come later (§11.6–11.7).

const TACTICS := ["best", "strong", "weak", "leader"]

var data: GameData
var cfg: Dictionary  # data.battle
var sides: Array[Squad] = []
var terrain: Dictionary  # the battle hex's terrain (the defender's hex)
var daytime := true
var fair := [true, true]  # fairer dice per side (§12.1)
var defense := [0.0, 0.0]  # building defense bonus per side (§6.5)
var tactics := ["best", "best"]
var first_side := -1  # a side that takes its whole first round first (neutrals that resisted recruitment)
var rng: RandomNumberGenerator
var events: Array[Dictionary] = []
var _start_hp := [0, 0]
var _attacks := {}  # Unit -> attacks left
var _misses := {}  # Unit -> misses in a row
var _since_crit := {}  # Unit -> attacks since its last crit
var _tiebreak := {}  # Unit -> random value that settles equal Speed
var _prd_cache := {}  # crit chance -> ramp step


func _init(game_data: GameData, player: Squad, enemy: Squad, terrain_key: String, is_day: bool,
		battle_rng: RandomNumberGenerator, fairness := "both") -> void:
	data = game_data
	cfg = data.battle
	sides.append_array([player, enemy])
	terrain = data.terrains[data.terrain_ids[terrain_key]]
	daytime = is_day
	rng = battle_rng
	fair = [true, fairness == "both"]
	for side in 2:
		for u in sides[side].living():
			_start_hp[side] += u.hp


## Plays rounds until every attack is spent or a side is down. Each round, every
## unit with attacks left acts once, fastest first.
func run() -> void:
	for side in 2:
		for u in sides[side].living():
			_attacks[u] = attack_count(u)
			_misses[u] = 0
			_since_crit[u] = 0
			_tiebreak[u] = rng.randf()
	var round := 0
	while not is_over():
		var order := turn_order(round == 0)
		if order.is_empty():
			break
		for u in order:
			if is_over():
				break
			if u.is_alive() and _attacks[u] > 0:
				act(u)
		round += 1


func is_over() -> bool:
	return sides[0].living().is_empty() or sides[1].living().is_empty()


## Living units with attacks left, highest Speed first. In the first round, `first_side` goes first.
func turn_order(first_round := false) -> Array[Unit]:
	var order: Array[Unit] = []
	for side in 2:
		for u in sides[side].living():
			if _attacks.get(u, 0) > 0:
				order.append(u)
	order.sort_custom(func(a: Unit, b: Unit) -> bool:
		if first_round and first_side >= 0 and side_of(a) != side_of(b):
			return side_of(a) == first_side
		if a.stats["SPD"] != b.stats["SPD"]:
			return a.stats["SPD"] > b.stats["SPD"]
		return _tiebreak[a] > _tiebreak[b])
	return order


func side_of(u: Unit) -> int:
	return 0 if u in sides[0].units else 1


## The unit's attack type and count from its row (§8.1).
func attack_kind(u: Unit) -> String:
	return u.info(data)["front_attack" if u.row == "front" else "back_attack"]


func attack_count(u: Unit) -> int:
	return int(u.info(data)["front_count" if u.row == "front" else "back_count"])


# --- One action -------------------------------------------------------------------

func act(u: Unit) -> void:
	_attacks[u] -= 1
	var side := side_of(u)
	var kind := attack_kind(u)
	if kind == "Heal":
		_heal(u, side)
		return
	if kind in ["Buff", "Debuff"]:  # statuses arrive with §11.7
		_record({"type": "wait", "unit": u, "text": "%s waits." % u.name})
		return
	var targets := reachable(kind, sides[1 - side])
	if targets.is_empty():
		return
	var t := pick_target(u, kind, targets, tactics[side])
	var hit := roll_hit(u, t)
	var event := {"type": "attack", "unit": u, "target": t, "kind": kind, "hit": hit, "crit": false, "damage": 0, "killed": false}
	if hit:
		var crit := roll_crit(u)
		var dmg := expected_damage(u, t, kind) * (float(cfg["crit_multiplier"]) if crit else 1.0)
		dmg *= 1.0 + rng.randf_range(-float(cfg["spread"]), float(cfg["spread"]))
		var amount := maxi(1, roundi(dmg))
		t.hp = maxi(0, t.hp - amount)
		event.merge({"crit": crit, "damage": amount, "killed": not t.is_alive()}, true)
		event["text"] = "%s hits %s for %d%s.%s" % [u.name, t.name, amount, " (critical)" if crit else "",
				" %s falls." % t.name if not t.is_alive() else ""]
	else:
		event["text"] = "%s misses %s." % [u.name, t.name]
	_record(event)


func _heal(u: Unit, side: int) -> void:
	var hurt: Unit = null
	for a in sides[side].living():
		if a.hp < a.max_hp(data) and (hurt == null or _hp_share(a) < _hp_share(hurt)):
			hurt = a
	if hurt == null:
		_record({"type": "wait", "unit": u, "text": "%s has no one to heal." % u.name})
		return
	var amount := heal_amount(u)
	amount = mini(amount, hurt.max_hp(data) - hurt.hp)
	hurt.hp += amount
	_record({"type": "heal", "unit": u, "target": hurt, "amount": amount, "text": "%s heals %s for %d." % [u.name, hurt.name, amount]})


func heal_amount(u: Unit) -> int:
	var base := float(u.stats["INT"]) * float(cfg["heal_int_share"])
	return maxi(1, roundi(base * (1.0 + rng.randf_range(-float(cfg["spread"]), float(cfg["spread"])))))


func _hp_share(u: Unit) -> float:
	return float(u.hp) / u.max_hp(data)


func _record(event: Dictionary) -> void:
	events.append(event)


## Share of a side's starting HP it has lost so far.
func hp_lost_share(side: int) -> float:
	var now := 0
	for u in sides[side].living():
		now += u.hp
	return 1.0 - float(now) / maxi(1, _start_hp[side])


# --- Targeting (§11.3) ------------------------------------------------------------

## Melee hits the front row, and the back row only once the front is empty.
## Ranged, Magic, Breath, Melee (any row) and reach can hit any row.
func reachable(kind: String, enemy: Squad) -> Array[Unit]:
	var alive := enemy.living()
	if kind != "Melee":
		return alive
	var front: Array[Unit] = []
	for u in alive:
		if u.row == "front":
			front.append(u)
	return front if not front.is_empty() else alive


## Best: the target it hurts most. Strong: the highest stat total. Weak: the lowest HP.
## Leader: the enemy leader if it can be reached, otherwise Best.
func pick_target(u: Unit, kind: String, targets: Array[Unit], tactic: String) -> Unit:
	var enemy_leader := sides[side_of(targets[0])].leader
	if tactic == "leader" and enemy_leader in targets:
		return enemy_leader
	var best: Unit = targets[0]
	for t in targets:
		match tactic:
			"strong":
				if _stat_total(t) > _stat_total(best):
					best = t
			"weak":
				if t.hp < best.hp:
					best = t
			_:
				var d := expected_damage(u, t, kind)
				var bd := expected_damage(u, best, kind)
				if d > bd or (d == bd and t.hp < best.hp):
					best = t
	return best


static func _stat_total(u: Unit) -> int:
	var total := 0
	for s in u.stats:
		total += u.stats[s]
	return total


# --- Damage (§11.4) and modifiers (§11.5) -------------------------------------------

## Damage before crit and spread. Weapons, armor and spell power arrive with items (M3).
func expected_damage(u: Unit, t: Unit, kind: String) -> float:
	var m := modifier(u, t)
	var dmg: float
	match kind:
		"Magic":
			dmg = (u.stats["INT"] * m - t.stats["MDEF"]) * element_multiplier(u, t)
		"Breath":
			dmg = ((u.stats["STR"] + u.stats["INT"]) * float(cfg["breath_stat_share"]) * m
					- t.stats["MDEF"] * float(cfg["breath_mdef_share"])) * element_multiplier(u, t)
		_:
			dmg = u.stats["STR"] * m - t.stats["PDEF"]
	return maxf(1.0, dmg * (1.0 - defense[side_of(t)]))


## Home terrain, day and night, and matchups, multiplied together.
func modifier(u: Unit, t: Unit) -> float:
	return terrain_modifier(u) * day_modifier(u) * matchup_modifier(u, t)


## +15% on the unit's home terrain, −15% on other difficulty-3 terrain. Flyers are unaffected.
func terrain_modifier(u: Unit) -> float:
	var sheet := u.terrain(data)
	if sheet == "Sky":
		return 1.0
	var home: String = data.rules["travel_types"][sheet]
	if terrain["key"] == home or terrain.get("native_as", "") == home or (home == "shallow" and terrain.get("water", false)):
		return 1.0 + float(cfg["home_terrain_bonus"])
	if int(terrain.get("difficulty", 0)) == 3:
		return 1.0 - float(cfg["hard_terrain_penalty"])
	return 1.0


## Holy units +15% by day and −15% at night; evil units the reverse.
func day_modifier(u: Unit) -> float:
	var b := float(cfg["day_night_bonus"])
	match u.alignment_band(data):
		"holy":
			return 1.0 + b if daytime else 1.0 - b
		"evil":
			return 1.0 - b if daytime else 1.0 + b
	return 1.0


func matchup_modifier(u: Unit, t: Unit) -> float:
	var m := 1.0
	for rule in cfg["matchups"]:
		if has_tag(u, rule["attacker"]) and has_tag(t, rule["target"]):
			m *= float(rule["multiplier"])
	return m


## ×1.5 against the opposite element, ×0.75 against the same one.
func element_multiplier(u: Unit, t: Unit) -> float:
	var a = u.info(data)["element"]
	var b = t.info(data)["element"]
	if a == null or b == null:
		return 1.0
	if a == b:
		return float(cfg["element_same"])
	for pair in cfg["element_pairs"]:
		if a in pair and b in pair:
			return float(cfg["element_opposite"])
	return 1.0


## Tags (archer, mounted, flyer...) from data/battle.json: by role, class, sheet terrain or size.
func has_tag(u: Unit, tag: String) -> bool:
	var rule: Dictionary = cfg["tags"].get(tag, {})
	var c := u.info(data)
	return c["role"] in rule.get("roles", []) or u.unit_class in rule.get("classes", []) \
			or c["terrain"] in rule.get("terrains", []) or c["size"] in rule.get("sizes", [])


# --- Hit and crit (§11.4, §12.1) ----------------------------------------------------

## 85% + 1% per point of AGI over the target's, less 0.5% per point of the target's luck, clamped 50–95%.
func hit_chance(u: Unit, t: Unit) -> float:
	var c: float = float(cfg["hit_base"]) + (u.stats["AGI"] - t.stats["AGI"]) * float(cfg["hit_per_agi"]) \
			- t.luck * float(cfg["luck_dodge_per_point"])
	return clampf(c, float(cfg["hit_range"][0]), float(cfg["hit_range"][1]))


## With fairer dice: the average of two d100 rolls, and a guaranteed hit after 3 misses in a row.
func roll_hit(u: Unit, t: Unit) -> bool:
	var chance := hit_chance(u, t)
	var hit: bool
	if fair[side_of(u)]:
		if _misses[u] >= int(cfg["streak_breaker_misses"]):
			hit = true
		else:
			hit = (rng.randi_range(1, 100) + rng.randi_range(1, 100)) / 2.0 <= chance
	else:
		hit = rng.randi_range(1, 100) <= chance
	_misses[u] = 0 if hit else _misses[u] + 1
	return hit


## 5% + 0.5% per luck point. With fairer dice the chance starts low and ramps up after
## each non-crit, resetting on a crit, with the same average.
func crit_chance(u: Unit) -> float:
	return (float(cfg["crit_base"]) + u.luck * float(cfg["luck_crit_per_point"])) / 100.0


func roll_crit(u: Unit) -> bool:
	var p := crit_chance(u)
	if fair[side_of(u)]:
		_since_crit[u] += 1
		p = minf(1.0, prd_constant(p) * _since_crit[u])
	var crit := rng.randf() < p
	if crit:
		_since_crit[u] = 0
	return crit


## The step C where the n-th try since the last success has chance C × n and the
## long-run rate is p.
func prd_constant(p: float) -> float:
	var key := snappedf(p, 0.0001)
	if _prd_cache.has(key):
		return _prd_cache[key]
	var lo := 0.0
	var hi := p
	for i in 40:
		var c := (lo + hi) / 2.0
		if _prd_rate(c) > p:
			hi = c
		else:
			lo = c
	_prd_cache[key] = (lo + hi) / 2.0
	return _prd_cache[key]


static func _prd_rate(c: float) -> float:
	var expected := 0.0
	var not_yet := 1.0
	var n := 1
	while not_yet > 1e-9:
		var p := minf(1.0, c * n)
		expected += n * not_yet * p
		not_yet *= 1.0 - p
		n += 1
	return 1.0 / expected
