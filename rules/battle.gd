class_name Battle
extends RefCounted
## One battle between two squads (SPEC §11.3–11.7, §12.1). Side 0 is the player's.
## step() plays one unit's turn and records what happened in `events`, for the log
## and the battle view; run() plays to the end. Units take damage directly.
## finish() clears statuses and Skeletons and reports the outcome.

const TACTICS := ["best", "strong", "weak", "leader"]

var data: GameData
var cfg: Dictionary  # data.battle
var sides: Array[Squad] = []
var terrain: Dictionary  # the battle hex's terrain (the defender's hex)
var daytime := true
var attacker := 0  # the side that started the battle (Charge)
var fair := [true, true]  # fairer dice per side (§12.1)
var defense := [0.0, 0.0]  # building defense bonus per side (§6.5)
var tactics := ["best", "best"]
var first_side := -1  # a side that takes its whole first round first (neutrals that resisted recruitment)
var rng: RandomNumberGenerator
var events: Array[Dictionary] = []
var retreated := -1  # the side that got away
var round := 0
var _start_hp := [0, 0]
var _queue: Array[Unit] = []  # this round's turns still to come
var _attacks := {}  # Unit -> attacks left
var _misses := {}  # Unit -> misses in a row
var _since_crit := {}  # Unit -> attacks since its last crit
var _tiebreak := {}  # Unit -> random value that settles equal Speed
var _status := {}  # Unit -> {status: the unit whose next turn ends it, or null for the whole battle}
var _lose_turn := [false, false]  # a failed retreat costs the side its next action
var _raised := {}  # Unit -> true once it has raised its Skeleton
var _skeletons: Array[Unit] = []
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
			_join(u)


func _join(u: Unit) -> void:
	_attacks[u] = attack_count(u)
	_misses[u] = 0
	_since_crit[u] = 0
	_tiebreak[u] = rng.randf()
	_status[u] = {}


## Plays to the end.
func run() -> void:
	while step():
		pass


## Plays the next unit's turn. False once the battle is over. Each round every unit
## with attacks left acts once, fastest first.
func step() -> bool:
	while not is_over():
		if _queue.is_empty():
			_queue = turn_order(round == 0)
			if _queue.is_empty():
				return false
			round += 1
		var u: Unit = _queue.pop_front()
		if u.is_alive() and _attacks[u] > 0:
			_turn(u)
			return not is_over()
	return false


func is_over() -> bool:
	return retreated >= 0 or sides[0].living().is_empty() or sides[1].living().is_empty()


## Living units with attacks left, highest Speed first (Freeze and Haste count). In the
## first round, a side that resisted recruitment goes first, then First strike units,
## and Charge units of the side that started the battle.
func turn_order(first_round := false) -> Array[Unit]:
	var order: Array[Unit] = []
	for side in 2:
		for u in sides[side].living():
			if _attacks.get(u, 0) > 0:
				order.append(u)
	order.sort_custom(func(a: Unit, b: Unit) -> bool:
		if first_round:
			if first_side >= 0 and side_of(a) != side_of(b):
				return side_of(a) == first_side
			if _strikes_first(a) != _strikes_first(b):
				return _strikes_first(a)
		if stat(a, "SPD") != stat(b, "SPD"):
			return stat(a, "SPD") > stat(b, "SPD")
		return _tiebreak[a] > _tiebreak[b])
	return order


func _strikes_first(u: Unit) -> bool:
	var t := traits(u)
	return "First strike" in t or ("Charge" in t and side_of(u) == attacker)


## The sheet's traits for the unit's class, plus interim ones from battle.json.
func traits(u: Unit) -> Array:
	return u.info(data).get("traits", []) + cfg["class_traits"].get(u.unit_class, [])


func side_of(u: Unit) -> int:
	return 0 if u in sides[0].units else 1


## The unit's attack type and count from its row (§8.1).
func attack_kind(u: Unit) -> String:
	return u.info(data)["front_attack" if u.row == "front" else "back_attack"]


func attack_count(u: Unit) -> int:
	return int(u.info(data)["front_count" if u.row == "front" else "back_count"])


# --- A turn -----------------------------------------------------------------------

func _turn(u: Unit) -> void:
	_attacks[u] -= 1
	var side := side_of(u)
	_end_buffs_from(u)
	_tick_statuses(u)
	if not u.is_alive():
		return
	if _lose_turn[side]:
		_lose_turn[side] = false
		_record({"type": "wait", "unit": u, "text": "%s's squad is still recovering from the failed retreat." % u.name})
		return
	for s in _status[u]:
		if cfg["statuses"][s].get("skip", false):
			_record({"type": "wait", "unit": u, "text": "%s can't act (%s)." % [u.name, s]})
			return
	_try_raise_dead(u, side)
	var kind := attack_kind(u)
	for s in _status[u]:
		if kind in cfg["statuses"][s].get("blocks", []):
			_record({"type": "wait", "unit": u, "text": "%s is silenced." % u.name})
			return
	for s in _status[u]:
		if rng.randf() < float(cfg["statuses"][s].get("lose_attack", 0.0)):
			_record({"type": "wait", "unit": u, "text": "%s is stunned by the shock." % u.name})
			return
	if _status[u].has("charm"):
		_status[u].erase("charm")
		var own := sides[side].living()
		own.erase(u)
		if not own.is_empty():
			_attack(u, kind, own[rng.randi() % own.size()], "charmed")
			return
	match kind:
		"Heal":
			_heal(u, side)
		"Buff":
			_buff(u, side)
		"Debuff":
			_debuff(u, side)
		_:
			var targets := reachable(kind, sides[1 - side])
			if not targets.is_empty():
				_attack(u, kind, pick_target(u, kind, targets, tactics[side]))


func _attack(u: Unit, kind: String, t: Unit, note := "") -> void:
	var hit := roll_hit(u, t)
	var event := {"type": "attack", "unit": u, "target": t, "kind": kind, "hit": hit, "crit": false, "damage": 0, "killed": false}
	var prefix := "%s (%s)" % [u.name, note] if note != "" else u.name
	if not hit:
		event["text"] = "%s misses %s." % [prefix, t.name]
		_record(event)
		return
	var crit := roll_crit(u)
	var dmg := expected_damage(u, t, kind) * (float(cfg["crit_multiplier"]) if crit else 1.0)
	dmg *= 1.0 + rng.randf_range(-float(cfg["spread"]), float(cfg["spread"]))
	var amount := maxi(1, roundi(dmg))
	t.hp = maxi(0, t.hp - amount)
	event.merge({"crit": crit, "damage": amount, "killed": not t.is_alive()}, true)
	event["text"] = "%s hits %s for %d%s.%s" % [prefix, t.name, amount, " (critical)" if crit else "",
			" %s falls." % t.name if not t.is_alive() else ""]
	_record(event)
	if not t.is_alive():
		return
	for s in _status[t].keys():
		if cfg["statuses"][s].get("wake_on_hit", false):
			_status[t].erase(s)
			_record({"type": "status", "unit": t, "status": s, "text": "%s wakes up." % t.name})
	var inflict := on_hit_status(u)
	if inflict != "" and rng.randf() < float(cfg["on_hit_chance"]):
		add_status(t, inflict, u)


func _heal(u: Unit, side: int) -> void:
	var hurt: Unit = null
	for a in sides[side].living():
		if a.hp < a.max_hp(data) and not _blocks_healing(a) and (hurt == null or _hp_share(a) < _hp_share(hurt)):
			hurt = a
	if hurt == null:
		_record({"type": "wait", "unit": u, "text": "%s has no one to heal." % u.name})
		return
	var amount := mini(heal_amount(u), hurt.max_hp(data) - hurt.hp)
	hurt.hp += amount
	_record({"type": "heal", "unit": u, "target": hurt, "amount": amount, "text": "%s heals %s for %d." % [u.name, hurt.name, amount]})


func heal_amount(u: Unit) -> int:
	var base := stat(u, "INT") * float(cfg["heal_int_share"])
	return maxi(1, roundi(base * (1.0 + rng.randf_range(-float(cfg["spread"]), float(cfg["spread"])))))


## A buffer raises a stat for its whole squad until its own next turn (§11.7).
func _buff(u: Unit, side: int) -> void:
	var s: String = cfg["buffers"].get(u.unit_class, "")
	if s == "":
		_record({"type": "wait", "unit": u, "text": "%s waits." % u.name})
		return
	for a in sides[side].living():
		_status[a][s] = u
	_record({"type": "status", "unit": u, "status": s, "text": "%s raises the squad's %s." % [u.name, s.trim_suffix("_up").to_upper()]})


func _debuff(u: Unit, side: int) -> void:
	var s: String = cfg["debuffers"].get(u.unit_class, "")
	var targets := sides[1 - side].living()
	if s == "" or targets.is_empty():
		_record({"type": "wait", "unit": u, "text": "%s waits." % u.name})
		return
	var fresh := targets.filter(func(t: Unit): return not has_status(t, s))
	if not fresh.is_empty():
		targets.assign(fresh)
	var t := pick_target(u, "Magic", targets, tactics[side])
	if roll_hit(u, t):
		if not add_status(t, s, u):
			_record({"type": "wait", "unit": u, "text": "%s's spell has no further effect on %s." % [u.name, t.name]})
	else:
		_record({"type": "attack", "unit": u, "target": t, "kind": "Debuff", "hit": false, "text": "%s misses %s." % [u.name, t.name]})


func _hp_share(u: Unit) -> float:
	return float(u.hp) / u.max_hp(data)


func _record(event: Dictionary) -> void:
	events.append(event)


## Share of a side's starting HP it has lost so far.
func hp_lost_share(side: int) -> float:
	var now := 0
	for u in sides[side].living():
		if u not in _skeletons:
			now += u.hp
	return 1.0 - float(now) / maxi(1, _start_hp[side])


# --- Statuses (§11.7) ---------------------------------------------------------------

## Gives a harmful or card status for the rest of the battle, unless the unit already
## has it or resists it (natives of the element's terrain). Charm ends after one turn.
func add_status(u: Unit, s: String, by: Unit = null) -> bool:
	var info: Dictionary = cfg["statuses"][s]
	var label := s.replace("_", " ")
	if _status[u].has(s):
		return false
	if info.get("resisted_by", "") == u.terrain(data):
		_record({"type": "status", "unit": u, "status": s, "resisted": true, "text": "%s resists %s." % [u.name, label]})
		return false
	if info.has("attacks"):
		_attacks[u] = maxi(0, _attacks[u] + int(info["attacks"]))
	_status[u][s] = null
	var text := "%s inflicts %s on %s." % [by.name, label, u.name] if by else "%s is affected by %s." % [u.name, label]
	_record({"type": "status", "unit": u, "status": s, "by": by, "text": text})
	return true


func has_status(u: Unit, s: String) -> bool:
	return _status.get(u, {}).has(s)


## Removes every harmful status (Cleanse).
func cleanse(u: Unit) -> void:
	for s in _status[u].keys():
		if cfg["statuses"][s].get("harmful", false):
			_status[u].erase(s)


func _end_buffs_from(u: Unit) -> void:
	for a in _status:
		for s in _status[a].keys():
			if _status[a][s] == u:
				_status[a].erase(s)


## Poison, Burn and Regen at the start of the unit's turn.
func _tick_statuses(u: Unit) -> void:
	for s in _status[u]:
		var share := float(cfg["statuses"][s].get("hp_per_turn", 0.0))
		if share == 0.0 or (share > 0.0 and _blocks_healing(u)):
			continue
		var change := roundi(u.max_hp(data) * share)
		u.hp = clampi(u.hp + change, 0, u.max_hp(data))
		_record({"type": "status", "unit": u, "status": s, "amount": change,
				"text": "%s %s %d HP from %s.%s" % [u.name, "loses" if change < 0 else "regains", absi(change), s,
				" %s falls." % u.name if not u.is_alive() else ""]})
		if not u.is_alive():
			return


func _blocks_healing(u: Unit) -> bool:
	for s in _status[u]:
		if cfg["statuses"][s].get("no_heal", false):
			return true
	return false


## A stat with statuses applied (Freeze, Haste, Protect, buffs).
func stat(u: Unit, s: String) -> float:
	var v := float(u.stats[s])
	for st in _status.get(u, {}):
		v *= float(cfg["statuses"][st].get("stats", {}).get(s, 1.0))
	return v


## The status this unit's hits can cause: by class (Siren charms) or by element (Ice freezes).
func on_hit_status(u: Unit) -> String:
	if cfg["on_hit_by_class"].has(u.unit_class):
		return cfg["on_hit_by_class"][u.unit_class]
	var e := element(u)
	return cfg["on_hit_by_element"].get(e, "") if e != "" else ""


func element(u: Unit) -> String:
	if u.element != "":
		return u.element
	var e = u.info(data)["element"]
	return e if e != null else ""


# --- Raise dead (§9.7) ----------------------------------------------------------------

## Occultist and Necromancer lines fill an empty slot with a Skeleton once per battle.
func _try_raise_dead(u: Unit, side: int) -> void:
	var rd: Dictionary = cfg["raise_dead"]
	if u.unit_class not in rd["classes"] or _raised.has(u):
		return
	var squad := sides[side]
	if squad.capacity(data) - Squad.slots_filled(data, squad.living()) < 1:
		return
	_raised[u] = true
	var sk := Unit.new()
	sk.unit_class = rd["base_class"]
	sk.name = rd["name"]
	sk.element = rd["element"]
	for s in Unit.STATS:
		sk.stats[s] = int(data.units[sk.unit_class]["base_stats"][s])
	for i in int(rd["bonus_stats"]):
		sk.stats[Unit.STATS[rng.randi() % Unit.STATS.size()]] += rng.randi_range(1, int(rd["bonus_die"]))
	sk.hp = sk.max_hp(data)
	squad.units.append(sk)
	_skeletons.append(sk)
	_join(sk)
	_record({"type": "raise", "unit": u, "target": sk, "text": "%s raises a Skeleton." % u.name})


# --- Retreat and the end (§11.6, §11.3) ------------------------------------------------

## 50% + 20% per speed tier over the enemy, clamped 10–90%.
func retreat_chance(side: int) -> float:
	var r: Dictionary = cfg["retreat"]
	var c := float(r["base"]) + (sides[side].speed_tier - sides[1 - side].speed_tier) * float(r["per_tier"])
	return clampf(c, float(r["range"][0]), float(r["range"][1])) / 100.0


## On success the battle ends; on failure the side loses its next action.
func retreat(side: int) -> bool:
	if rng.randf() < retreat_chance(side):
		retreated = side
		_record({"type": "retreat", "side": side, "success": true, "text": "%s retreats." % sides[side].name})
		return true
	_lose_turn[side] = true
	_record({"type": "retreat", "side": side, "success": false, "text": "%s fails to retreat." % sides[side].name})
	return false


## Ends the battle: statuses clear and Skeletons leave. Returns per side whether it
## was wiped out or lost its leader, who retreated, and who is pushed back
## (the side that lost the larger share of its HP, if neither is wiped out or retreated).
func finish() -> Dictionary:
	_status.clear()
	for sk in _skeletons:
		for s in sides:
			s.units.erase(sk)
	_skeletons.clear()
	var out := {"wiped": [], "leader_dead": [], "retreated": retreated, "pushed": -1,
			"hp_lost": [hp_lost_share(0), hp_lost_share(1)]}
	for s in sides:
		out["wiped"].append(s.living().is_empty())
		out["leader_dead"].append(s.leader != null and not s.leader.is_alive())
	if retreated < 0 and not out["wiped"].has(true) and out["hp_lost"][0] != out["hp_lost"][1]:
		out["pushed"] = 0 if out["hp_lost"][0] > out["hp_lost"][1] else 1
	for s in sides:
		s.refresh(data)
	return out


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


## Best: the target it hurts most. Strong: the highest threat. Weak: the lowest HP.
## Leader: the enemy leader if it can be reached, otherwise Best.
func pick_target(u: Unit, kind: String, targets: Array[Unit], tactic: String) -> Unit:
	var enemy_leader := sides[side_of(targets[0])].leader
	if tactic == "leader" and enemy_leader in targets:
		return enemy_leader
	var best: Unit = targets[0]
	for t in targets:
		match tactic:
			"strong":
				if Threat.unit(data, t) > Threat.unit(data, best):
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


# --- Damage (§11.4) and modifiers (§11.5) -------------------------------------------

## Damage before crit and spread. Weapons, armor and spell power arrive with items (M3).
func expected_damage(u: Unit, t: Unit, kind: String) -> float:
	var m := modifier(u, t)
	var dmg: float
	var taken := "magic_taken"
	match kind:
		"Magic":
			dmg = (stat(u, "INT") * m - stat(t, "MDEF")) * element_multiplier(u, t)
		"Breath":
			dmg = ((stat(u, "STR") + stat(u, "INT")) * float(cfg["breath_stat_share"]) * m
					- stat(t, "MDEF") * float(cfg["breath_mdef_share"])) * element_multiplier(u, t)
		_:
			taken = "physical_taken"
			for s in _status.get(u, {}):
				m *= float(cfg["statuses"][s].get("physical_dealt", 1.0))
			dmg = stat(u, "STR") * m - stat(t, "PDEF")
	dmg = maxf(1.0, dmg * (1.0 - defense[side_of(t)]))
	for s in _status.get(t, {}):
		dmg *= float(cfg["statuses"][s].get(taken, 1.0)) * float(cfg["statuses"][s].get("damage_taken", 1.0))
	return maxf(1.0, dmg)


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
	var a := element(u)
	var b := element(t)
	if a == "" or b == "":
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

## 85% + 1% per point of AGI over the target's, less 0.5% per point of the target's
## luck, clamped 50–95%. Blind takes 30% off after the clamp.
func hit_chance(u: Unit, t: Unit) -> float:
	var c: float = float(cfg["hit_base"]) + (stat(u, "AGI") - stat(t, "AGI")) * float(cfg["hit_per_agi"]) \
			- t.luck * float(cfg["luck_dodge_per_point"])
	c = clampf(c, float(cfg["hit_range"][0]), float(cfg["hit_range"][1]))
	for s in _status.get(u, {}):
		c += float(cfg["statuses"][s].get("hit", 0.0))
	return maxf(0.0, c)


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
