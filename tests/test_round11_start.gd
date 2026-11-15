extends TestCase
## Playtest round 11, game start and tactics (ROADMAP M4 session 35): the player's name
## goes to the Opinion Leader, the enemy starts holding 1 or 2 central-leaning towns
## with field squads it already had, and each squad keeps its last battle tactic.

var d := GameData.load_dir()


func _game(seed: int, name := "") -> Array:
	var config := GameConfig.create(d, seed)
	config.values["width"] = 160
	config.values["height"] = 90
	config.player_name = name
	var map := MapGen.generate(d, config.seed, config.map_overrides())
	var st := GameState.new(d, map, GameLog.new(), config.game_settings())
	st.setup_army()
	st.place_enemies()
	st.place_neutrals()
	return [st, config]


func test_the_opinion_leader_takes_the_players_name() -> void:
	var st: GameState = _game(5, "Ada Quill")[0]
	check_eq(st.opinion_leader.name, "Ada Quill", "the Opinion Leader is named for the player")
	check_eq(st.opinion_leader_squad().name, "Ada (%s)" % st.opinion_leader.unit_class, "and the squad after them")
	check(st.log.entries.any(func(e): return str(e["text"]).begins_with("Ada Quill the ")), "the log uses the name from the start")
	var plain: GameState = _game(5)[0]
	check(plain.opinion_leader.name != "Ada Quill", "no name given: a random one")
	check(SummaryScreen.random_name(d).contains(" "), "the summary's suggestion is a first and last name")


func test_the_enemy_starts_spread_out() -> void:
	# Round 16 (lever 2, replacing round 11's 1-2 central towns): raiders at the base,
	# holdfasts on the towns and towers nearest it, and a third of the front on towns of its
	# own across the enemy's half, far apart.
	for seed in [3, 8, 13]:
		var st: GameState = _game(seed)[0]
		var enemy := st.squads.filter(func(o: Squad): return o.side == "enemy")
		var e := st.map.hex_at(st.map.enemy_base)
		var p := st.map.hex_at(st.map.player_base)
		var ours := enemy.filter(func(o: Squad): var at := st.map.hex_at(o.hex); return Hex.distance(at, p) < Hex.distance(at, e))
		check_eq(enemy.size(), st.enemy_squad_count() + ours.size(), "no extra squads but the forward ones (seed %d)" % seed)
		check(ours.size() <= 2 * int(d.ai["force"]["forward"]), "at most the forward ones in your half")
		for o in enemy:
			if o.role == "raider":
				check_eq(o.hex, st.map.enemy_base, "%s sets off from the base" % o.name)
			elif o.role == "garrison":
				check(st.building_at(o.hex).get("owner", "") == "enemy" and o.post == o.hex, "%s holds its building" % o.name)
			elif o.role == "field" and o.hex != st.map.enemy_base and o not in ours:
				var at := st.map.hex_at(o.hex)
				check(Hex.distance(at, e) < Hex.distance(at, p), "%s starts in the enemy's half" % o.name)


func test_a_squad_keeps_its_tactic() -> void:
	var g := _game(5)
	var st: GameState = g[0]
	var ours := st.opinion_leader_squad()
	var foe: Squad = st.squads.filter(func(o: Squad): return o.side == "enemy")[0]
	check_eq(st.start_battle(ours, foe, foe).tactics[0], "best", "Best to start")
	ours.tactic = "weak"  # what the battle view does when the player picks Weak
	check_eq(st.start_battle(ours, foe, foe).tactics[0], "weak", "the next battle starts on Weak")
	var loaded = SaveGame.from_dict(d, SaveGame.to_dict(st, g[1]), GameLog.new())
	var back: GameState = loaded["state"]
	check_eq(back.opinion_leader_squad().tactic, "weak", "and keeps it through a save")
