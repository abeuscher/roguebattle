class_name DebugTools
extends RefCounted
## The debug panel's tools (SPEC §19.2) as plain rules, so tests can run them.
## None of this is part of the real game.


## A squad of `count` fresh units of `class_id` on `hex`, for any side. A player
## squad needs a free army cell (null if none). Enemies hold their post like a
## garrison; neutrals roam around where they were put.
static func spawn(state: GameState, class_id: String, count: int, side: String, hex: int) -> Squad:
	var members := []
	for i in count:
		members.append([class_id, data_row(state.data, class_id)])
	var number := 0
	var cell := -1
	if side == "player":
		cell = state.army.cells.find(null)
		if cell < 0:
			return null
		number = cell + 1
	else:
		number = (100 if side == "enemy" else 200) + 1
		for s in state.squads:
			if s.side == side:
				number = maxi(number, s.id + 1)
	var s := state._form(number, "" if side == "player" else "Debug %s %d" % [class_id, number], hex, members, side)
	s.balance_rows(state.data)
	if side == "enemy":
		s.role = "garrison"
	elif side == "neutral":
		s.role = "roamer"
		s.lair_hex = hex
	if cell >= 0:
		state.army.cells[cell] = s
	state.squads.append(s)
	state.log.add(state.clock.tick, "system", "Debug: spawned %s (%s)." % [s.name, side], s.id)
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


## Levels every unit in the squad up to `level` (never down), with the usual growth rolls.
static func set_level(state: GameState, s: Squad, level: int) -> void:
	var r := state.rng.get_stream("debug")
	for u in s.units:
		while u.level < level:
			Progression.level_up(state.data, u, r)
		u.xp = 0
		if u.is_alive():
			u.hp = u.max_hp(state.data)  # at full health for the new level
	state.log.add(state.clock.tick, "system", "Debug: %s raised to level %d." % [s.name, level], s.id)


static func set_stat(state: GameState, s: Squad, stat: String, value: int) -> void:
	for u in s.units:
		u.stats[stat] = value
		u.hp = mini(u.hp, u.max_hp(state.data))
	state.log.add(state.clock.tick, "system", "Debug: %s's %s set to %d." % [s.name, stat, value], s.id)


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


## Both squads as they were, and the battle stream's position, just before a battle.
static func snapshot(player: Squad, enemy: Squad, stream: RandomNumberGenerator) -> Dictionary:
	return {"squads": [copy_squad(player), copy_squad(enemy)], "seed": stream.seed, "state": stream.state}


## The last player battle again from the same start and the same rolls, on copies
## (nothing on the map changes). Tactic changes and cards played the first time
## aren't replayed, so a battle that used them can come out differently.
static func replay(state: GameState) -> Battle:
	if state.last_battle.is_empty() or not state.last_battle.has("battle"):
		return null
	var was: Battle = state.last_battle["battle"]
	var r := RandomNumberGenerator.new()
	r.seed = state.last_battle["seed"]
	r.state = state.last_battle["state"]
	var sides: Array = state.last_battle["squads"]
	var b := Battle.new(state.data, copy_squad(sides[0]), copy_squad(sides[1]), was.terrain["key"], was.daytime, r)
	b.fair = was.fair.duplicate()
	b.fairness_rules = was.fairness_rules.duplicate()
	b.attacker = was.attacker
	b.defense = was.defense.duplicate()
	b.odds = was.odds
	b.tech = was.tech.duplicate(true)
	b.first_side = was.first_side
	if was.ranged_only:
		b.ranged_only = true
		for side in 2:
			for u in b.sides[side].living():
				b._join(u)
	return b


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
