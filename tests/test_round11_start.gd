extends TestCase
## Playtest round 11, game start and tactics (ROADMAP M4 session 35): the player's name
## goes to the Opinion Leader, the enemy starts holding 1 or 2 central-leaning towns
## with field squads it already had, and each squad keeps its last battle tactic.

var d := GameData.load_dir()


func _game(seed: int, name := "") -> Array:
	var config := GameConfig.create(d, seed)
	config.values["width"] = 160
	config.values["height"] = 90
	config.fit_squad_cap()
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


func test_the_enemy_starts_on_central_towns() -> void:
	var picked := 0.0
	var all := 0.0
	var n_picked := 0
	var n_all := 0
	for seed in [3, 8, 13, 21, 34, 55]:
		var st: GameState = _game(seed)[0]
		var enemy := st.squads.filter(func(o: Squad): return o.side == "enemy")
		check_eq(enemy.size(), st.enemy_squad_count(), "no extra squads (seed %d)" % seed)
		var held := st.map.buildings.filter(func(b): return b["type"] == "town" and b["owner"] == "enemy")
		check(held.size() >= 1 and held.size() <= 2, "1 or 2 enemy towns (seed %d): %d" % [seed, held.size()])
		for b in held:
			check(enemy.any(func(o: Squad): return o.role == "field" and o.hex == b["hex"]), "a field squad on each")
			picked += st.centrality(b["hex"])
			n_picked += 1
		for b in st.map.buildings.filter(func(b): return b["type"] == "town"):
			all += st.centrality(b["hex"])
			n_all += 1
	check(picked / n_picked > all / n_all, "the towns lean central: %.2f against %.2f on average" % [picked / n_picked, all / n_all])


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
