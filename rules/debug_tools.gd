class_name DebugTools
extends RefCounted
## The debug panel's tools (SPEC §19.2) as plain rules, so tests can run them.
## None of this is part of the real game.


## The squad builder (user's design, 2026-11-11): an empty squad, off the map, that the
## panel fills unit by unit and then places. Room for a full squad on any side.
static func draft(state: GameState) -> Squad:
	var s := Squad.new(0, "", -1)
	s.base_slots = maxi(state.army.base_slots, int(state.data.rules["single_map"]["base_slots"]))
	return s


## A freshly rolled `class_id` at `level` joins the draft in its usual row. False if it
## doesn't fit. The first unit that can lead becomes the leader.
static func add_unit(state: GameState, s: Squad, class_id: String, level: int) -> bool:
	var u := Unit.roll(state.data, class_id, state.rng.get_stream("debug"), state.names)
	_raise(state, u, level)
	return s.add(state.data, u, data_row(state.data, class_id))


static func remove_unit(state: GameState, s: Squad, u: Unit) -> void:
	s.units.erase(u)
	if s.leader == u:
		s.leader = null
		for o in s.units:
			if o.info(state.data)["can_lead"]:
				s.leader = o
				break
	for which in ["front", "back"]:
		var r := s.row(which)
		r.sort_custom(func(a: Unit, b: Unit): return a.col < b.col)
		for i in r.size():
			r[i].col = i
	s.refresh(state.data)


## Puts a copy of the draft on `hex` for `side` (the draft stays, to place again). A
## player squad needs a free army cell; every squad needs a unit that can lead. Returns
## the squad, or why not as a String. Enemies hold their post like a garrison;
## neutrals roam around where they were put.
static func place(state: GameState, d: Squad, side: String, hex: int) -> Variant:
	if d.units.is_empty():
		return "Add some units first."
	if d.leader == null or d.leader not in d.units or not d.leader.info(state.data)["can_lead"] or not d.leader.is_alive():
		return "It has no leader. Add a unit that can lead (the gray star in Edit Units marks them): a squad without one can't take buildings or act properly."
	var number := 0
	var cell := -1
	if side == "player":
		cell = state.army.cells.find(null)
		if cell < 0:
			return "No free army cell for another squad."
		number = cell + 1
	else:
		number = (100 if side == "enemy" else 200) + 1
		for o in state.squads:
			if o.side == side:
				number = maxi(number, o.id + 1)
	var s := Squad.new(number, "", hex)
	s.side = side
	s.base_slots = d.base_slots
	if side == "player":
		s.tech = state.tech
	for u in d.units:
		var c := u.clone()
		s.units.append(c)
		if u == d.leader:
			s.leader = c
	s.refresh(state.data)
	if side != "player":
		s.name = "Debug %s %d" % [s.leader.unit_class, number]
	s.morale = int(state.data.rules["starting_morale"])
	if side == "enemy":
		s.role = "garrison"
	elif side == "neutral":
		s.role = "roamer"
		s.lair_hex = hex
	if cell >= 0:
		state.army.cells[cell] = s
	state.squads.append(s)
	state.log.add(state.clock.tick, "system", "Debug: placed %s (%s)." % [s.name, side], s.id)
	return s


static func data_row(data: GameData, class_id: String) -> String:
	return data.role_templates[data.units[class_id]["role"]]["primary_row"]


static func teleport(state: GameState, s: Squad, hex: int) -> void:
	s.hex = hex
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	s.capture_ticks = 0.0
	state.log.add(state.clock.tick, "system", "Debug: %s teleported." % s.name, s.id)


## Takes a squad out of the game for good (its units too).
static func remove(state: GameState, s: Squad) -> void:
	state.squads.erase(s)
	var cell := state.army.cells.find(s)
	if cell >= 0:
		state.army.cells[cell] = null
	state.log.add(state.clock.tick, "system", "Debug: %s removed." % s.name, s.id)


## Every player unit, on the map, at base or in the pool, back to full HP.
static func heal_all(state: GameState) -> void:
	for u in state.army.units():
		u.hp = u.max_hp(state.data)
	for s in state.army.squads():
		if s.marching_home and s.leader and s.leader.is_alive():
			s.marching_home = false
			s.entering_base = false
			s.path.clear()
			s.rally.clear()
	state.log.add(state.clock.tick, "system", "Debug: every player unit healed and revived.")


## Levels a unit up to `level` (never down), with the usual growth rolls, at full health.
static func _raise(state: GameState, u: Unit, level: int) -> void:
	var r := state.rng.get_stream("debug")
	while u.level < level:
		Progression.level_up(state.data, u, r)
	u.xp = 0
	if u.is_alive():
		u.hp = u.max_hp(state.data)


static func set_alignment(state: GameState, s: Squad, value: int) -> void:
	for u in s.units:
		u.alignment = clampi(value, 0, 100)
	state.log.add(state.clock.tick, "system", "Debug: %s's alignment set to %d." % [s.name, value], s.id)


## Runs the map on for `hours` (stopping early for a battle, a recruit choice or the
## end of the map). Returns the ticks actually run.
static func skip_hours(state: GameState, hours: int) -> int:
	var n := 0
	while n < hours * 60 and state.pending == null and state.pending_recruit.is_empty() and state.game_over == "":
		state.step()
		n += 1
	return n


## Ends a battle the way the debug panel forced: the enemy (win) or the player
## (loss) falls at once, or nobody fights at all (draw).
static func force(b: Battle, kind: String) -> void:
	match kind:
		"win", "loss":
			for u in b.sides[1 if kind == "win" else 0].living():
				u.hp = 0
		"draw":
			b.halted = true


## The last player battle again from the same start and the same rolls, on copies
## (nothing on the map changes). Cards and tactic changes from the first time aren't
## replayed (the view lets you play it anew); replay_inputs() does that.
static func replay(state: GameState) -> Battle:
	if state.last_battle.is_empty() or state.last_battle["battle"].start.is_empty():
		return null
	return rebuild(state.data, state.last_battle["battle"].start)


# --- The battle report (playtest round 19) --------------------------------------------

## How a battle stands before its first action (Battle._mark_start): both squads as plain
## values (as a save holds them), the per-unit draws its setup made, and the dice's place.
static func battle_start(b: Battle) -> Dictionary:
	var squads := []
	for side in 2:
		var s := b.sides[side]
		var sq := SaveGame._props(s, SaveGame.SQUAD_REFS)
		sq["units"] = s.units.map(func(u: Unit): return SaveGame._props(u, []))
		sq["leader"] = s.units.find(s.leader)
		sq["bonded_pairs"] = s.bonded_pairs.map(func(p: Array): return [s.units.find(p[0]), s.units.find(p[1])])
		sq["tech"] = s.tech.duplicate(true)
		sq["draws"] = s.units.map(func(u: Unit): return [b._tiebreak.get(u, -1.0), b._attacks.get(u, -1)])
		squads.append(sq)
	return {"squads": squads, "terrain": b.terrain["key"], "daytime": b.daytime, "attacker": b.attacker,
			"fair": b.fair.duplicate(), "fairness_rules": b.fairness_rules.duplicate(), "defense": b.defense.duplicate(),
			"broken": b.broken.duplicate(), "worn": b.worn.duplicate(), "tactics": b.tactics.duplicate(), "first_side": b.first_side,
			"ranged_only": b.ranged_only, "odds": b.odds, "tech": b.tech.duplicate(true),
			"rng_seed": b.rng.seed, "rng_state": b.rng.state, "derived": _derived(b)}


## What the rules make of each unit at the start (for reading, not for the replay).
static func _derived(b: Battle) -> Array:
	var out := []
	for side in 2:
		var s := b.sides[side]
		var units := []
		for u in s.units:
			var stats := {}
			for k in Unit.STATS:
				stats[k] = snappedf(b.stat(u, k), 0.01)
			var info := u.info(b.data)
			var kind := b.attack_kind(u)
			units.append({"name": u.name, "class": u.unit_class, "level": u.level, "row": u.row, "col": u.col,
					"hp": u.hp, "max_hp": u.max_hp(b.data), "leader": u == s.leader, "stats": stats,
					"attack": kind, "attacks": b.attack_count(u), "element": b.element(u),
					"traits": info.get("traits", []), "leader_aura": info.get("leader_aura", ""), "terrain": u.terrain(b.data),
					"crit": snappedf(b.crit_chance(u), 0.001), "statuses": b.status_ids(u),
					"equipment": u.items.values().map(func(it: Dictionary): return it["id"])})
		out.append({"squad": s.name, "side": s.side, "role": s.role, "morale": s.morale, "speed_tier": s.speed_tier,
				"aura": SaveGame._plain(b._auras[side]), "units": units})
	return out


## A battle's report for the clipboard (the debug panel): the start, every input and every
## event with its hidden numbers, as JSON, plus `replay`, the start as Godot text (exact:
## 64-bit dice, typed values) for rebuilding it. Meant for Claude, not for people.
static func battle_report(b: Battle) -> String:
	var start := b.start if not b.start.is_empty() else battle_start(b)  # not begun yet: as it stands now
	var events := []
	for e in b.events:
		var x := {}
		for k in e:
			x[k] = _named(b, e[k])
		events.append(x)
	var report := {"report": "landwar battle", "version": 1, "context": SaveGame._plain(b.context),
			"start": _readable(start), "inputs": b.inputs.duplicate(true), "events": events,
			"over": b.is_over(), "retreated": b.retreated, "hp_lost_share": [b.hp_lost_share(0), b.hp_lost_share(1)],
			"replay": var_to_str({"start": start, "inputs": b.inputs})}
	return JSON.stringify(report, " ", false)


## The start without its replay-only parts.
static func _readable(start: Dictionary) -> Dictionary:
	var out := start.duplicate(true)
	for k in ["squads", "rng_seed", "rng_state"]:
		out.erase(k)
	return out


## A value for the report, units as "side.index Name".
static func _named(b: Battle, v: Variant) -> Variant:
	if v is Unit:
		var side := b.side_of(v)
		return "%d.%d %s" % [side, b.sides[side].units.find(v), v.name]
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _named(b, v[k])
		return d
	if v is Array:
		return v.map(func(x): return _named(b, x))
	return SaveGame._plain(v)


## A battle report pasted back: the battle at its start, ready to step (its inputs in
## `inputs`, for replay_inputs). Null if the text isn't a report.
static func from_report(data: GameData, text: String) -> Battle:
	if not text.strip_edges().begins_with("{"):
		return null
	var j: Variant = JSON.parse_string(text)
	if not (j is Dictionary and j.has("replay")):
		return null
	var r: Variant = str_to_var(str(j["replay"]))
	if not (r is Dictionary):
		return null
	var b := rebuild(data, r["start"])
	b.set_meta("inputs", r["inputs"])
	return b


## A battle as `start` describes it (battle_start), on fresh copies of its units.
static func rebuild(data: GameData, start: Dictionary) -> Battle:
	var squads: Array[Squad] = []
	for sq in start["squads"]:
		var s := Squad.new(0, "", -1)
		SaveGame._apply(s, sq, SaveGame.SQUAD_REFS + ["draws"])
		var units: Array[Unit] = []
		for ud in sq["units"]:
			var u := Unit.new()
			SaveGame._apply(u, ud, [])
			units.append(u)
		s.units = units
		s.leader = units[sq["leader"]] if int(sq["leader"]) >= 0 else null
		s.bonded_pairs = sq["bonded_pairs"].map(func(p: Array): return [units[p[0]], units[p[1]]])
		s.tech = sq["tech"].duplicate(true)
		squads.append(s)
	var r := RandomNumberGenerator.new()
	var b := Battle.new(data, squads[0], squads[1], start["terrain"], start["daytime"], r)
	for k in ["attacker", "first_side", "ranged_only", "odds"]:
		b.set(k, start[k])
	for k in ["fair", "fairness_rules", "defense", "broken", "tactics", "tech"] + (["worn"] if start.has("worn") else []):
		b.set(k, start[k].duplicate(true))
	for side in 2:
		var draws: Array = start["squads"][side]["draws"]
		for i in draws.size():
			var u := squads[side].units[i]
			if float(draws[i][0]) >= 0.0:
				if not b._attacks.has(u):
					b._join(u)
				b._tiebreak[u] = draws[i][0]
				b._attacks[u] = draws[i][1]
	r.seed = start["rng_seed"]
	r.state = start["rng_state"]
	return b


## Plays a rebuilt battle to its end, making each recorded input before the step it came before.
static func replay_inputs(b: Battle, inputs: Array) -> void:
	var i := 0
	while true:
		while i < inputs.size() and int(inputs[i]["at"]) <= b.steps:
			var x: Dictionary = inputs[i]
			match x["kind"]:
				"card": b.play_card(x["card"], x["side"])
				"tactic": b.set_tactic(x["side"], x["tactic"])
				"retreat": b.retreat(x["side"])
				"cure": b.cure(b.sides[x["side"]].units[x["unit"]], x["status"], x["potion"])
			i += 1
		if not b.step():
			break


static func copy_squad(s: Squad) -> Squad:
	var c := Squad.new(s.id, s.name, s.hex)
	var copies := {}
	for u in s.units:
		copies[u] = u.clone()
		c.units.append(copies[u])
	c.leader = copies.get(s.leader)
	c.side = s.side
	c.role = s.role
	c.morale = s.morale
	c.base_slots = s.base_slots
	c.tech = s.tech.duplicate()
	c.travel_type = s.travel_type
	c.sky = s.sky
	c.speed_tier = s.speed_tier
	for pair in s.bonded_pairs:
		if copies.has(pair[0]) and copies.has(pair[1]):
			c.bonded_pairs.append([copies[pair[0]], copies[pair[1]]])
	return c


## Every squad build as [[class, row], ...] for BattleSim.
static func build_of(s: Squad) -> Array:
	var out := []
	var ordered := s.units.duplicate()
	if s.leader:
		ordered.erase(s.leader)
		ordered.push_front(s.leader)
	for u in ordered:
		out.append([u.unit_class, u.row])
	return out
