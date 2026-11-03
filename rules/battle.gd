class_name Battle
extends RefCounted
## One battle between two squads (SPEC §11.3–11.7, §12.1; traits, auras and group
## attacks from the sheet's Mechanics tab). Side 0 is the player's.
## step() plays one unit's turn and records what happened in `events`, for the log
## and the battle view; run() plays to the end. Units take damage directly.
## finish() clears statuses and Skeletons and reports the outcome.

const TACTICS := ["best", "strong", "weak", "leader"]
const PHYSICAL := ["Melee", "Ranged"]
const MAGICAL := ["Magic", "Dispel", "Breath"]

var data: GameData
var cfg: Dictionary  # data.battle
var sides: Array[Squad] = []
var terrain: Dictionary  # the battle hex's terrain (the defender's hex)
var daytime := true
var attacker := 0  # the side that started the battle
var fair := [true, true]  # fairer dice per side (§12.1)
var defense := [0.0, 0.0]  # building defense bonus per side (§6.5)
var tactics := ["best", "best"]
var first_side := -1  # a side that takes its whole first round first (neutrals that resisted recruitment)
var rng: RandomNumberGenerator
var events: Array[Dictionary] = []
var retreated := -1  # the side that got away
var round := 0  # the current round, from 1
var _auras := [[], []]  # per side: the leader aura's effects, scaled for stage 4
var _start_hp := [0, 0]
var _queue: Array[Unit] = []  # this round's turns still to come
var _attacks := {}  # Unit -> attacks left
var _misses := {}  # Unit -> misses in a row
var _since_crit := {}  # Unit -> attacks since its last crit
var _tiebreak := {}  # Unit -> random value that settles equal Speed
var _status := {}  # Unit -> {status: the unit whose next turn ends it, or null}
var _used := {}  # "trait:unit id" -> true for once-per-battle effects
var _lose_turn := [false, false]  # a failed retreat costs the side its next action
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
		_auras[side] = _aura_effects(sides[side].leader)
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
			round += 1
			_queue = turn_order(round == 1)
			if _queue.is_empty():
				return false
			_start_round()
			if is_over():
				return false
		var u: Unit = _queue.pop_front()
		if u.is_alive() and _attacks[u] > 0:
			_turn(u)
			return not is_over()
	return false


func is_over() -> bool:
	return retreated >= 0 or sides[0].living().is_empty() or sides[1].living().is_empty()


## Living units with attacks left, highest Speed first. In the first round, a side that
## resisted recruitment goes first, then First strike units and Charge order squads;
## units with a round-one extra attack (Volley, Stampede) act a second time at the end.
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
	if first_round:
		for u in order.duplicate():
			if _round_one_bonus(u) > 0:
				order.append(u)
	return order


func _strikes_first(u: Unit) -> bool:
	if u.has_trait(data, "First strike"):
		return true
	for e in _effects(side_of(u)):
		if e.get("first", false):
			return true
	return false


func side_of(u: Unit) -> int:
	return 0 if u in sides[0].units else 1


## The unit's attack from its row (§8.1), e.g. "Breath (row)".
func attack_kind(u: Unit) -> String:
	return u.info(data)["front_attack" if u.row == "front" else "back_attack"]


## "Melee (cleave 2)" -> "Melee".
static func base_kind(kind: String) -> String:
	return kind.get_slice(" (", 0)


## "Melee (cleave 2)" -> "cleave 2"; "" for a plain attack.
static func group_of(kind: String) -> String:
	return kind.get_slice(" (", 1).trim_suffix(")") if kind.contains(" (") else ""


## Row count, plus Pack, Swarm, Tamer and aura bonuses.
func attack_count(u: Unit) -> int:
	var n := int(u.info(data)["front_count" if u.row == "front" else "back_count"])
	var squad := sides[side_of(u)]
	for t in u.info(data)["traits"]:
		var rule: Dictionary = cfg["traits"].get(t, {})
		if rule.has("attacks_per"):
			var others := squad.units.filter(func(o: Unit): return o != u and o.has_tag(data, rule["attacks_per"]))
			n += mini(others.size(), int(rule["max"]))
	if u.row == "front" and u.has_tag(data, "large") and u.has_tag(data, "beast") \
			and squad.units.any(func(o: Unit): return o != u and o.has_trait(data, "Tamer")):
		n += int(cfg["traits"]["Tamer"]["large_beast_front_attacks"])
	for e in _effects(side_of(u)):
		if e.has("attacks") and _covers(e, u, true) and not (e.get("front_only", false) and u.row != "front"):
			n += int(e["attacks"])
	return n


## Extra attacks a unit gets in round one only (counted in attack_count).
func _round_one_bonus(u: Unit) -> int:
	var n := 0
	for e in _effects(side_of(u)):
		if e.has("attacks") and e.get("when", "") == "round1" and _covers(e, u, true):
			n += int(e["attacks"])
	return n


# --- Leader auras -------------------------------------------------------------------

## The leader aura's battle effects, with numbers ×1.5 for a stage 4 leader.
func _aura_effects(leader: Unit) -> Array:
	if leader == null:
		return []
	var name = leader.info(data).get("leader_aura")
	if name == null or not cfg["auras"].has(name):
		return []
	var scale := float(cfg["aura_stage4_scale"]) if int(leader.info(data)["stage"]) >= 4 else 1.0
	var out := []
	for e in cfg["auras"][name]:
		if e.get("map", false):
			continue
		var copy: Dictionary = e.duplicate(true)
		for k in ["damage", "taken", "regen", "dodge", "enemy_hit", "after_battle_heal"]:
			if copy.has(k):
				copy[k] = float(copy[k]) * scale
		if copy.has("stats"):
			for s in copy["stats"]:
				copy["stats"][s] = float(copy["stats"][s]) * scale
		out.append(copy)
	return out


## A side's aura effects while its leader lives.
func _effects(side: int) -> Array:
	var leader := sides[side].leader
	return _auras[side] if leader and leader.is_alive() else []


## Whether an aura effect of side_of-owner reaches unit u now. "who" names squad
## members (squad, casters, healers, beasts, wolves, mounted, front, back) or enemies.
func _covers(e: Dictionary, u: Unit, ignore_when := false) -> bool:
	if not ignore_when:
		match e.get("when", ""):
			"day":
				if not daytime: return false
			"night":
				if daytime: return false
			"round1":
				if round != 1: return false
	if e.has("terrain") and terrain["key"] not in e["terrain"]:
		return false
	match e.get("who", "squad"):
		"casters": return base_kind(attack_kind(u)) == "Magic"
		"healers": return base_kind(attack_kind(u)) == "Heal"
		"beasts": return u.has_tag(data, "beast")
		"wolves": return u.has_tag(data, "wolf")
		"mounted": return u.has_tag(data, "mounted")
		"front", "enemy_front": return u.row == "front"
		"back": return u.row == "back"
		"enemy_leader": return u == sides[side_of(u)].leader
	return true


static func _is_enemy_effect(e: Dictionary) -> bool:
	return str(e.get("who", "")).begins_with("enemy")


## Aura effects acting on unit u: its own squad's (not enemy-aimed) and the enemy's enemy-aimed ones.
func _effects_on(u: Unit) -> Array:
	var out := []
	var side := side_of(u)
	for e in _effects(side):
		if not _is_enemy_effect(e) and _covers(e, u):
			out.append(e)
	for e in _effects(1 - side):
		if _is_enemy_effect(e) and _covers(e, u):
			out.append(e)
	return out


# --- A turn -----------------------------------------------------------------------

## Regenerate, Regrowth at the start of each round.
func _start_round() -> void:
	for side in 2:
		var squad_regen := 0.0
		for e in _effects(side):
			squad_regen += float(e.get("regen", 0.0))
		for u in sides[side].living():
			var share := squad_regen + (float(cfg["traits"]["Regenerate"]["regen"]) if u.has_trait(data, "Regenerate") else 0.0)
			if share > 0.0 and u.hp < u.max_hp(data) and not _blocks_healing(u):
				var amount := mini(maxi(1, roundi(u.max_hp(data) * share)), u.max_hp(data) - u.hp)
				u.hp += amount
				_record({"type": "heal", "unit": u, "target": u, "amount": amount, "text": "%s regenerates %d HP." % [u.name, amount]})


func _turn(u: Unit) -> void:
	var expiring := []
	for s in _status[u]:
		if cfg["statuses"][s].has("turns"):
			expiring.append(s)
	_act(u)
	for s in expiring:
		_status[u].erase(s)


func _act(u: Unit) -> void:
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
	var base := base_kind(kind)
	for s in _status[u].keys():
		if base in cfg["statuses"][s].get("blocks", []):
			if cfg["statuses"][s].get("once", false):
				_status[u].erase(s)
			_record({"type": "wait", "unit": u, "text": "%s's %s is cancelled (%s)." % [u.name, base.to_lower(), s]})
			return
	for s in _status[u]:
		if rng.randf() < float(cfg["statuses"][s].get("lose_attack", 0.0)):
			_record({"type": "wait", "unit": u, "text": "%s is stunned by the shock." % u.name})
			return
	if base in ["Magic", "Dispel"] and round == 1 and sides[1 - side].living().any(func(o: Unit): return o.has_trait(data, "Nullify")):
		_record({"type": "wait", "unit": u, "text": "%s's magic fizzles (Nullify)." % u.name})
		return
	if _status[u].has("charm"):
		_status[u].erase("charm")
		var own := sides[side].living()
		own.erase(u)
		if not own.is_empty():
			_attack(u, base, own[rng.randi() % own.size()], 1.0, "charmed")
			return
	match base:
		"Heal":
			_heal(u, side, group_of(kind) == "row")
		"Buff":
			_buff(u, side)
		"Ward":
			for a in sides[side].living():
				_status[a]["ward"] = u
			_record({"type": "status", "unit": u, "status": "ward", "text": "%s wards the squad against magic." % u.name})
		"Debuff":
			_debuff(u, side, group_of(kind) == "row")
		_:
			_strike(u, kind, side)


## An attack, single or group (row, all, cleave 2, pierce, chain 3).
func _strike(u: Unit, kind: String, side: int) -> void:
	var targets := reachable(u, kind, sides[1 - side])
	if targets.is_empty():
		return
	var base := base_kind(kind)
	var group := group_of(kind)
	var t := pick_target(u, base, targets, tactics[side])
	var enemy := sides[1 - side]
	match group:
		"row":
			for o in enemy.row(t.row):
				if o.is_alive():
					_attack(u, base, o)
		"all":
			for o in enemy.living():
				_attack(u, base, o)
		"cleave 2":
			_attack(u, base, t)
			var next := _beside(enemy, t)
			if next:
				_attack(u, base, next)
		"pierce":
			var behind := enemy.across(t) if t.row == "front" else null
			_attack(u, base, t)
			if behind and behind.is_alive():
				_attack(u, base, behind)
		"chain 3":
			var hit := [t]
			_attack(u, base, t)
			for jump in 2:
				var rest := enemy.living().filter(func(o: Unit): return o not in hit)
				if rest.is_empty():
					break
				var o: Unit = rest[rng.randi() % rest.size()]
				hit.append(o)
				_attack(u, base, o, 1.0 - float(cfg["chain_falloff"]) * (jump + 1))
		_:
			_attack(u, base, _guarded(enemy, t))
	_used["first:%d" % u.get_instance_id()] = true


## The nearest living unit beside t in its row.
func _beside(squad: Squad, t: Unit) -> Unit:
	var best: Unit = null
	for o in squad.row(t.row):
		if o != t and o.is_alive() and (best == null or absi(o.col - t.col) < absi(best.col - t.col)):
			best = o
	return best


## Guard: a living Guard in front takes single hits aimed at the unit behind it.
func _guarded(squad: Squad, t: Unit) -> Unit:
	if t.row == "back":
		var g := squad.across(t)
		if g and g.is_alive() and g.has_trait(data, "Guard"):
			return g
	return t


func _attack(u: Unit, base: String, t: Unit, mult := 1.0, note := "") -> void:
	if not t.is_alive():
		return
	var hit := roll_hit(u, t, base)
	if hit and t.has_trait(data, "Mirage") and not _used.has("mirage:%d" % t.get_instance_id()):
		_used["mirage:%d" % t.get_instance_id()] = true
		hit = false
		note = "Mirage" if note == "" else note
	var event := {"type": "attack", "unit": u, "target": t, "kind": base, "hit": hit, "crit": false, "damage": 0, "killed": false}
	var prefix := "%s (%s)" % [u.name, note] if note != "" else u.name
	if not hit:
		event["text"] = "%s misses %s." % [prefix, t.name]
		_record(event)
		return
	var crit := roll_crit(u)
	var dmg := expected_damage(u, t, base) * mult * (float(cfg["crit_multiplier"]) if crit else 1.0)
	dmg *= 1.0 + rng.randf_range(-float(cfg["spread"]), float(cfg["spread"]))
	var amount := maxi(1, roundi(dmg))
	t.hp = maxi(0, t.hp - amount)
	event.merge({"crit": crit, "damage": amount, "killed": not t.is_alive()}, true)
	event["text"] = "%s hits %s for %d%s.%s" % [prefix, t.name, amount, " (critical)" if crit else "",
			" %s falls." % t.name if not t.is_alive() else ""]
	_record(event)
	_lifesteal(u, base, amount)
	if not t.is_alive():
		_grave_pact(t)
		return
	for s in _status[t].keys():
		if cfg["statuses"][s].get("wake_on_hit", false):
			_status[t].erase(s)
			_record({"type": "status", "unit": t, "status": s, "text": "%s wakes up." % t.name})
	if base == "Dispel":
		add_status(t, "dispelled", u)
	var inflict := on_hit_status(u, base)
	if inflict != "" and rng.randf() < float(cfg["on_hit_chance"]):
		add_status(t, inflict, u)
	if base == "Breath" and u.has_trait(data, "Petrify") and rng.randf() < float(cfg["traits"]["Petrify"]["chance"]):
		add_status(t, cfg["traits"]["Petrify"]["breath_status"], u)
	_pushback(u, t)
	if base == "Melee" and note == "" and t.has_trait(data, "Riposte") and side_of(t) != side_of(u) \
			and not (round == 1 and _effects(side_of(u)).any(func(e): return e.get("no_counter", false))):
		_attack(t, "Melee", u, float(cfg["traits"]["Riposte"]["counter"]), "riposte")


func _lifesteal(u: Unit, base: String, amount: int) -> void:
	for name in ["Drain", "Bloodthirst"]:
		if not u.has_trait(data, name) or not u.is_alive():
			continue
		var rule: Dictionary = cfg["traits"][name]
		if (rule.get("night_only", false) and daytime) or (rule.get("melee_only", false) and base != "Melee"):
			continue
		var heal := mini(roundi(amount * float(rule["lifesteal"])), u.max_hp(data) - u.hp)
		if heal > 0:
			u.hp += heal
			_record({"type": "heal", "unit": u, "target": u, "amount": heal, "text": "%s drains %d HP." % [u.name, heal]})


## Pushback (trait, once per battle) and Battering (aura, front row in round one):
## the target swaps places with the unit behind it, or steps back.
func _pushback(u: Unit, t: Unit) -> void:
	var key := "pushback:%d" % u.get_instance_id()
	var by_trait := u.has_trait(data, "Pushback") and not _used.has(key)
	var by_aura := _effects(side_of(u)).any(func(e): return e.get("pushback", false) and _covers(e, u))
	if t.row != "front" or not (by_trait or by_aura):
		return
	if by_trait:
		_used[key] = true
	var squad := sides[side_of(t)]
	var behind := squad.across(t)
	if behind:
		behind.row = "front"
	t.row = "back"
	_record({"type": "move", "unit": t, "text": "%s is knocked into the back row." % t.name})


func _heal(u: Unit, side: int, whole_row := false) -> void:
	var hurt: Unit = null
	for a in sides[side].living():
		if a.hp < a.max_hp(data) and not _blocks_healing(a) and (hurt == null or _hp_share(a) < _hp_share(hurt)):
			hurt = a
	if hurt == null:
		_record({"type": "wait", "unit": u, "text": "%s has no one to heal." % u.name})
		return
	var targets: Array[Unit] = [hurt]
	if whole_row:
		targets.assign(sides[side].row(hurt.row).filter(func(a: Unit): return a.is_alive() and not _blocks_healing(a)))
	for t in targets:
		var amount := mini(heal_amount(u), t.max_hp(data) - t.hp)
		if amount <= 0:
			continue
		t.hp += amount
		_record({"type": "heal", "unit": u, "target": t, "amount": amount, "text": "%s heals %s for %d." % [u.name, t.name, amount]})


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


## Debuff: one enemy, or with (row) every unit of the enemy's front row (back once it's empty).
func _debuff(u: Unit, side: int, whole_row := false) -> void:
	var s: String = cfg["debuffers"].get(u.unit_class, "")
	var enemy := sides[1 - side]
	var targets := enemy.living()
	if s == "" or targets.is_empty():
		_record({"type": "wait", "unit": u, "text": "%s waits." % u.name})
		return
	if whole_row:
		var front := enemy.row("front").filter(func(t: Unit): return t.is_alive())
		for t in (front if not front.is_empty() else targets):
			add_status(t, s, u)
		return
	var fresh := targets.filter(func(t: Unit): return not has_status(t, s))
	if not fresh.is_empty():
		targets.assign(fresh)
	var t := pick_target(u, "Magic", targets, tactics[side])
	if roll_hit(u, t, "Magic"):
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
## has it, resists it (natives of the element's terrain), or its squad's Discipline
## aura blocks harmful statuses in round one. Charm and Petrify end after one turn.
func add_status(u: Unit, s: String, by: Unit = null) -> bool:
	var info: Dictionary = cfg["statuses"][s]
	var label := s.replace("_", " ")
	if _status[u].has(s):
		return false
	if info.get("resisted_by", "") == u.terrain(data):
		_record({"type": "status", "unit": u, "status": s, "resisted": true, "text": "%s resists %s." % [u.name, label]})
		return false
	if info.get("harmful", false) and _effects_on(u).any(func(e): return e.get("debuff_immune", false)):
		_record({"type": "status", "unit": u, "status": s, "resisted": true, "text": "%s shrugs off %s (Discipline)." % [u.name, label]})
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
			_grave_pact(u)
			return


func _blocks_healing(u: Unit) -> bool:
	for s in _status[u]:
		if cfg["statuses"][s].get("no_heal", false):
			return true
	return false


## A stat with statuses, auras and Last stand applied. `vs` is the attack being
## defended against, for effects like Aerie (+PDEF against ranged).
func stat(u: Unit, s: String, vs := "") -> float:
	var v := float(u.stats[s])
	for st in _status.get(u, {}):
		v *= float(cfg["statuses"][st].get("stats", {}).get(s, 1.0))
	for e in _effects_on(u):
		if e.has("stats") and (not e.has("vs") or e["vs"] == vs.to_lower()) and (not e.get("stationary", false) or not sides[side_of(u)].is_moving()):
			v *= 1.0 + float(e["stats"].get(s, 0.0))
	if u.has_trait(data, "Last stand") and u.hp * 2 < u.max_hp(data):
		v *= 1.0 + float(cfg["traits"]["Last stand"]["below_half_stats"].get(s, 0.0))
	return v


## The status this attack can cause: Magic and Breath carry the unit's element (Ice freezes).
func on_hit_status(u: Unit, base := "Magic") -> String:
	if base not in ["Magic", "Breath", "Dispel"]:
		return ""
	var e := element(u)
	return cfg["on_hit_by_element"].get(e, "") if e != "" else ""


func element(u: Unit) -> String:
	if u.element != "":
		return u.element
	var e = u.info(data)["element"]
	return e if e != null else ""


## The element an attack carries: Magic and Breath carry the unit's; Melee carries one
## from Attunement (the leader's element) or Scorch (Fire).
func attack_element(u: Unit, base: String) -> String:
	if base in MAGICAL:
		return element(u)
	if base == "Melee":
		for e in _effects(side_of(u)):
			if e.has("melee_element"):
				var leader := sides[side_of(u)].leader
				return element(leader) if e["melee_element"] == "leader" else str(e["melee_element"])
	return ""


# --- Raise dead (§9.7) ----------------------------------------------------------------

## Raise dead (trait) fills an empty slot with a Skeleton once per battle.
func _try_raise_dead(u: Unit, side: int) -> void:
	var key := "raise:%d" % u.get_instance_id()
	if not u.has_trait(data, "Raise dead") or _used.has(key):
		return
	var squad := sides[side]
	if squad.capacity(data) - Squad.slots_filled(data, squad.living()) < 1:
		return
	_used[key] = true
	_add_skeleton(squad, "front", squad.next_col("front"))
	_record({"type": "raise", "unit": u, "target": _skeletons[-1], "text": "%s raises a Skeleton." % u.name})


## Grave pact (aura): the side's first fallen unit rises as a Skeleton in its place.
func _grave_pact(fallen: Unit) -> void:
	var side := side_of(fallen)
	var key := "grave:%d" % side
	if fallen in _skeletons or _used.has(key) or not _effects(side).any(func(e): return e.get("grave_pact", false)):
		return
	_used[key] = true
	var squad := sides[side]
	var spot := fallen.col
	fallen.col = squad.next_col(fallen.row) + 100  # the dead keep their slot but give up the position
	_add_skeleton(squad, fallen.row, spot)
	_record({"type": "raise", "unit": fallen, "target": _skeletons[-1], "text": "%s rises again as a Skeleton." % fallen.name})


func _add_skeleton(squad: Squad, row: String, col: int) -> void:
	var rd: Dictionary = cfg["raise_dead"]
	var sk := Unit.new()
	sk.unit_class = rd["base_class"]
	sk.name = rd["name"]
	sk.element = rd["element"]
	sk.row = row
	sk.col = col
	for s in Unit.STATS:
		sk.stats[s] = int(data.units[sk.unit_class]["base_stats"][s])
	for i in int(rd["bonus_stats"]):
		sk.stats[Unit.STATS[rng.randi() % Unit.STATS.size()]] += rng.randi_range(1, int(rd["bonus_die"]))
	sk.hp = sk.max_hp(data)
	squad.units.append(sk)
	_skeletons.append(sk)
	_join(sk)


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


## Ends the battle: statuses clear, Skeletons leave, Remount heals. Returns per side whether
## it was wiped out or lost its leader, who retreated, and who is pushed back
## (the side that lost the larger share of its HP, if neither is wiped out or retreated).
func finish() -> Dictionary:
	_status.clear()
	var out := {"wiped": [], "leader_dead": [], "retreated": retreated, "pushed": -1,
			"hp_lost": [hp_lost_share(0), hp_lost_share(1)]}
	for sk in _skeletons:
		for s in sides:
			s.units.erase(sk)
	_skeletons.clear()
	for side in 2:
		var s := sides[side]
		for u in s.units:
			if u.col >= 100:
				u.col = s.next_col(u.row)  # a Grave pact unit takes a free position again
		out["wiped"].append(s.living().is_empty())
		out["leader_dead"].append(s.leader != null and not s.leader.is_alive())
		for e in _effects(side):
			if e.has("after_battle_heal"):
				for u in s.living():
					if _covers(e, u):
						u.hp = mini(u.max_hp(data), u.hp + roundi(u.max_hp(data) * float(e["after_battle_heal"])))
	if retreated < 0 and not out["wiped"].has(true) and out["hp_lost"][0] != out["hp_lost"][1]:
		out["pushed"] = 0 if out["hp_lost"][0] > out["hp_lost"][1] else 1
	for s in sides:
		s.refresh(data)
	return out


# --- Targeting (§11.3) ------------------------------------------------------------

## Plain Melee hits the front row, and the back row only once the front is empty;
## Melee (any row), reach and a front-row Pounce hit any row, as do Ranged, Magic
## and Breath. Bulwark hides the unit behind it from Melee and Ranged, except
## any-row Melee and Falconers.
func reachable(u: Unit, kind: String, enemy: Squad) -> Array[Unit]:
	var base := base_kind(kind)
	var group := group_of(kind)
	var alive := enemy.living()
	var any_row := group in ["any row", "reach 2nd row"] or (u.row == "front" and u.has_trait(data, "Pounce"))
	var out: Array[Unit] = alive
	if base == "Melee" and not any_row:
		var front := alive.filter(func(t: Unit): return t.row == "front")
		if not front.is_empty():
			out.assign(front)
	if base in PHYSICAL and group != "any row" and not u.has_tag(data, "falconer"):
		var open := out.filter(func(t: Unit):
			var f := enemy.across(t) if t.row == "back" else null
			return not (f and f.is_alive() and f.has_trait(data, "Bulwark")))
		if not open.is_empty():
			out.assign(open)
	return out


## Best: the target it hurts most. Strong: the highest threat. Weak: the lowest HP.
## Leader: the enemy leader if it can be reached, otherwise Best.
func pick_target(u: Unit, base: String, targets: Array[Unit], tactic: String) -> Unit:
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
				var d := expected_damage(u, t, base)
				var bd := expected_damage(u, best, base)
				if d > bd or (d == bd and t.hp < best.hp):
					best = t
	return best


# --- Damage (§11.4) and modifiers (§11.5) -------------------------------------------

## Damage before crit and spread. Weapons, armor and spell power arrive with items (M3).
func expected_damage(u: Unit, t: Unit, base: String) -> float:
	base = base_kind(base)
	var m := modifier(u, t) * _dealt_multiplier(u, t, base)
	var dmg: float
	match base:
		"Magic", "Dispel":
			dmg = stat(u, "INT") * m - stat(t, "MDEF", base)
		"Breath":
			dmg = (stat(u, "STR") + stat(u, "INT")) * float(cfg["breath_stat_share"]) * m \
					- stat(t, "MDEF", base) * float(cfg["breath_mdef_share"])
		_:
			var pdef := stat(t, "PDEF", base)
			if u.has_trait(data, "Armor-piercing"):
				pdef *= 1.0 - float(cfg["traits"]["Armor-piercing"]["ignore_pdef"])
			dmg = stat(u, "STR") * m - pdef
	dmg *= element_multiplier(attack_element(u, base), element(t))
	dmg = maxf(1.0, dmg * (1.0 - defense[side_of(t)]))
	return maxf(1.0, dmg * _taken_multiplier(u, t, base))


## Charge, Execute, Burn and the attacker's damage auras.
func _dealt_multiplier(u: Unit, t: Unit, base: String) -> float:
	var m := 1.0
	if u.has_trait(data, "Charge") and not _used.has("first:%d" % u.get_instance_id()):
		m *= float(cfg["traits"]["Charge"]["first_attack"])
	if u.has_trait(data, "Execute") and _hp_share(t) < float(cfg["traits"]["Execute"]["under"]):
		m *= float(cfg["traits"]["Execute"]["multiplier"])
	if base in PHYSICAL:
		for s in _status.get(u, {}):
			m *= float(cfg["statuses"][s].get("physical_dealt", 1.0))
	for e in _effects(side_of(u)):
		if e.has("damage") and _covers(e, u) and (not e.has("element") or attack_element(u, base) == e["element"]):
			m *= 1.0 + float(e["damage"])
	return m


## Statuses, traits (Incorporeal, Stoneskin) and the target's protective auras.
func _taken_multiplier(u: Unit, t: Unit, base: String) -> float:
	var physical := base in PHYSICAL
	var key := "physical_taken" if physical else "magic_taken"
	var m := 1.0
	for s in _status.get(t, {}):
		m *= float(cfg["statuses"][s].get(key, 1.0)) * float(cfg["statuses"][s].get("damage_taken", 1.0))
	for name in t.info(data)["traits"]:
		m *= float(cfg["traits"].get(name, {}).get(key, 1.0))
	for e in _effects_on(t):
		if not e.has("taken"):
			continue
		var applies := false
		match e.get("from", ""):
			"mounted": applies = u.has_tag(data, "mounted")
			"Dark": applies = attack_element(u, base) == "Dark"
			"magic": applies = not physical
			"dark_or_magic": applies = not physical or attack_element(u, base) == "Dark"
		if applies:
			m *= 1.0 + float(e["taken"])
	return m


## Home terrain, day and night, and matchups, multiplied together.
func modifier(u: Unit, t: Unit) -> float:
	return terrain_modifier(u) * day_modifier(u) * matchup_modifier(u, t)


## +15% on the unit's home terrain, −15% on other difficulty-3 terrain (not for flyers).
func terrain_modifier(u: Unit) -> float:
	var sheet := u.terrain(data)
	var home: String = data.rules["travel_types"].get(sheet, "")
	if home != "" and (terrain["key"] == home or terrain.get("native_as", "") == home or (home == "shallow" and terrain.get("water", false))):
		return 1.0 + float(cfg["home_terrain_bonus"])
	if int(terrain.get("difficulty", 0)) == 3 and not u.has_tag(data, "flyer"):
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
		if u.has_tag(data, rule["attacker"]) and t.has_tag(data, rule["target"]):
			m *= float(rule["multiplier"])
	return m


## ×1.5 against the opposite element, ×0.75 against the same one.
func element_multiplier(a: String, b: String) -> float:
	if a == "" or b == "":
		return 1.0
	if a == b:
		return float(cfg["element_same"])
	for pair in cfg["element_pairs"]:
		if a in pair and b in pair:
			return float(cfg["element_opposite"])
	return 1.0


# --- Hit and crit (§11.4, §12.1) ----------------------------------------------------

## 85% + 1% per point of AGI over the target's, less 0.5% per point of the target's
## luck, clamped 50–95%. Then Blind, Night evasion, Screen and Ink cloud.
func hit_chance(u: Unit, t: Unit, base := "Melee") -> float:
	var c: float = float(cfg["hit_base"]) + (stat(u, "AGI") - stat(t, "AGI")) * float(cfg["hit_per_agi"]) \
			- t.luck * float(cfg["luck_dodge_per_point"])
	c = clampf(c, float(cfg["hit_range"][0]), float(cfg["hit_range"][1]))
	for s in _status.get(u, {}):
		c += float(cfg["statuses"][s].get("hit", 0.0))
	if not daytime and t.has_trait(data, "Night evasion"):
		c -= float(cfg["traits"]["Night evasion"]["night_dodge"])
	if base == "Ranged":
		for e in _effects_on(t):
			c -= float(e.get("dodge", 0.0)) if e.get("vs", "") == "ranged" else 0.0
		for e in _effects(side_of(t)):
			c += float(e.get("enemy_hit", 0.0)) if e.get("vs", "") == "ranged" else 0.0
	return maxf(0.0, c)


## With fairer dice: the average of two d100 rolls, and a guaranteed hit after 3 misses in a row.
func roll_hit(u: Unit, t: Unit, base := "Melee") -> bool:
	var chance := hit_chance(u, t, base)
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
