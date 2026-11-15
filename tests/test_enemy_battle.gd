extends TestCase
## How enemy squads fight (SPEC §12.3, ai.json battle): each rolls a tactic once and keeps
## it; one losing badly tries to retreat; the Warlord, base guard and holdfasts never do.

var d := GameData.load_dir()


func _unit(c: String, row := "front") -> Unit:
	var u := Unit.new()
	u.unit_class = c
	u.name = c
	for s in Unit.STATS:
		u.stats[s] = int(d.units[c]["base_stats"][s])
	u.hp = u.max_hp(d)
	u.row = row
	return u


func _squad(side: String, role: String, units: Array) -> Squad:
	var s := Squad.new(1 if side == "player" else 101, "Ours" if side == "player" else "Theirs", 0)
	s.side = side
	s.role = role
	for u in units:
		s.units.append(u)
		if s.leader == null and u.info(d)["can_lead"]:
			s.leader = u
	s.refresh(d)
	return s


## A strong squad of yours against a weak enemy one that starts the battle badly hurt.
func _lopsided(role: String, seed: int) -> Battle:
	var ours := _squad("player", "", [_unit("Knight"), _unit("Soldier"), _unit("Soldier"), _unit("Archer", "back")])
	var theirs := _squad("enemy", role, [_unit("Soldier"), _unit("Fighter"), _unit("Fighter"), _unit("Bowman", "back")])
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Battle.new(d, ours, theirs, "plains", true, rng)


func test_a_losing_enemy_tries_to_get_away() -> void:
	var got_away := 0
	for seed in 30:
		var b := _lopsided("field", seed)
		b.run()
		if b.retreated == 1:
			got_away += 1
			check(b.events.any(func(e): return e["type"] == "retreat" and e["side"] == 1 and str(e["text"]).begins_with("Theirs")), "it says who retreats (seed %d)" % seed)
	check(got_away >= 5, "a beaten enemy squad often gets away (%d of 30)" % got_away)


func test_holders_never_retreat() -> void:
	for role in ["leader", "base_guard", "garrison"]:
		for seed in 15:
			var b := _lopsided(role, seed)
			b.run()
			check(b.retreated != 1, "%s holds its ground (seed %d)" % [role, seed])
			check(not b.events.any(func(e): return e["type"] == "retreat"), "%s never even tries (seed %d)" % [role, seed])


func test_an_enemy_keeps_the_tactic_it_rolled() -> void:
	var config := GameConfig.create(d, 9)
	config.values["width"] = 160
	config.values["height"] = 90
	var map := MapGen.generate(d, config.seed, config.map_overrides())
	var st := GameState.new(d, map, GameLog.new(), config.game_settings())
	st.setup_army()
	st.place_enemies()
	var mine := st.player_squads()[0]
	var seen := {}
	for e: Squad in st.squads.filter(func(s: Squad): return s.side == "enemy"):
		var first := st.start_battle(mine, e, e)
		check(e.tactic_rolled and first.tactics[1] == e.tactic, "%s fights with its tactic" % e.name)
		var again := st.start_battle(mine, e, e)
		check_eq(again.tactics[1], first.tactics[1], "%s keeps it" % e.name)
		seen[e.tactic] = true
	var many := {}
	for i in 400:
		var t := st._roll_tactic()
		many[t] = many.get(t, 0) + 1
	check(many.size() == Battle.TACTICS.size(), "every tactic turns up: %s" % many)
	check(int(many.get("best", 0)) > 120, "mostly Best: %s" % many)


## Enemy ranged attacks on the map (ai.json volleys; SPEC §11.2).
func _volley_setup(gap: int) -> Array:
	var config := GameConfig.create(d, 9)
	config.values["width"] = 160
	config.values["height"] = 90
	var map := MapGen.generate(d, config.seed, config.map_overrides())
	var st := GameState.new(d, map, GameLog.new(), config.game_settings())
	st.setup_army()
	st.place_enemies()
	var road := st.pathfinder.find(st.map.enemy_base, st.map.player_base)
	var mine := st.player_squads()[0]
	var archers: Squad = st.squads.filter(func(s: Squad): return s.side == "enemy" and s.role in ["field", "raider", "garrison"])[0]
	archers.units = [_unit("Soldier"), _unit("Bowman", "back"), _unit("Bowman", "back")]
	archers.leader = archers.units[0]
	archers.refresh(d)
	archers.role = "garrison"  # stands still
	for o in st.squads:
		if o != mine and o != archers:
			o.hex = st.map.enemy_base  # everyone else out of the way
	archers.hex = road[30]
	mine.hex = road[30 + gap]
	mine.path.clear()
	return [st, mine, archers]


func test_enemy_archers_fire_from_range() -> void:
	var x := _volley_setup(2)
	var st: GameState = x[0]
	var mine: Squad = x[1]
	var archers: Squad = x[2]
	check_eq(Hex.distance(st.map.hex_at(mine.hex), st.map.hex_at(archers.hex)), 2, "two hexes apart")
	st.step()
	check(st.pending != null and st.pending.ranged_only, "they fire")
	if st.pending:
		check(st.pending.sides[0] == mine and st.pending.sides[1] == archers and st.pending.attacker == 1, "your squad on the left, theirs attacking")
		st.resolve_pending()
	check(archers.fire_ready > st.clock.tick, "then they reload")
	st.step()
	check(st.pending == null or not st.pending.ranged_only, "no second volley while reloading")


## Playtest round 19: an enemy volley opened its battle with no warning. It warns like
## contact does; only a ranged attack the player ordered opens at once.
func test_enemy_volley_warns_but_your_own_fire_does_not() -> void:
	var x := _volley_setup(2)
	var st: GameState = x[0]
	var mine: Squad = x[1]
	var archers: Squad = x[2]
	st.step()
	check(st.pending != null and st.pending.ranged_only and st.pending.warns(), "their volley gets the warning")
	st.resolve_pending()
	mine.units.append(_unit("Bowman", "back"))
	mine.refresh(d)
	st.fire(mine, archers)
	check(st.pending != null and not st.pending.warns(), "your own ordered shot opens at once")
	st.resolve_pending()
	var close := st.start_battle(mine, archers, archers)
	check(close.warns(), "contact always warns")


func test_no_volley_when_beside_or_falling_back() -> void:
	var x := _volley_setup(1)
	var st: GameState = x[0]
	st.step()
	check(st.pending == null or not st.pending.ranged_only, "side by side: a close fight, not a volley")
	x = _volley_setup(2)
	st = x[0]
	var archers: Squad = x[2]
	archers.marching_home = true
	archers.role = "field"
	st._enemy_volleys()
	check(st.pending == null, "a squad falling back doesn't fire")
