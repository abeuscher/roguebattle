extends TestCase
## Playtest round 16 (user, 2026-11-15): the enemy chases your squads out of its backfield
## (ai.json hunt), squads falling back route round your still squads and raiders sometimes
## sneak round all of them (ai.json dodge), and a fight put aside to look at the map keeps
## its two squads where they are.

var d := GameData.load_dir()


func _game(seed := 4) -> GameState:
	var config := GameConfig.create(d, seed)
	config.values["width"] = 160
	config.values["height"] = 90
	var map := MapGen.generate(d, config.seed, config.map_overrides())
	var st := GameState.new(d, map, GameLog.new(), config.game_settings())
	st.setup_army()
	st.place_enemies()
	return st


## A front squad `s` part way from the Enemy Base toward yours, and your squad `p` a few
## hexes behind it (nearer the Enemy Base), every other building neutral.
func _chase_setup(st: GameState) -> Array:
	for b in st.map.buildings:
		if b["type"] in ["town", "tower", "temple"]:
			b["owner"] = "neutral"
	var road := st.pathfinder.find(st.map.enemy_base, st.map.player_base)
	var s: Squad = st.squads.filter(func(o: Squad): return o.side == "enemy" and o.role in ["field", "raider", "garrison"])[0]
	s.role = "field"
	s.hex = road[24]
	s.path.clear()
	var p := st.player_squads()[0]
	p.hex = road[20]
	return [s, p]


func test_the_chase_is_likelier_the_more_it_leaves_behind() -> void:
	var st := _game()
	var sp := _chase_setup(st)
	var s: Squad = sp[0]
	var p: Squad = sp[1]
	check_eq(EnemyAI.behind(st, s, p), 1, "only the Enemy Base is behind it")
	var chased := 0
	for i in 400:
		s.spotted = {}
		s.follow = null
		st._spot(s)
		chased += 1 if s.follow == p else 0
	check(chased > 60 and chased < 140, "one building behind: about 25%% chase (%d of 400)" % chased)
	# Four towns nearer your squad than the enemy's: it always turns.
	var near := st.map.buildings.filter(func(b): return b["type"] == "town")
	near.sort_custom(func(a, b): return Hex.distance(st.map.hex_at(a["hex"]), st.map.hex_at(p.hex)) < Hex.distance(st.map.hex_at(b["hex"]), st.map.hex_at(p.hex)))
	var made := 0
	for b in near:
		if made < 3 and Hex.distance(st.map.hex_at(b["hex"]), st.map.hex_at(p.hex)) < Hex.distance(st.map.hex_at(b["hex"]), st.map.hex_at(s.hex)):
			b["owner"] = "enemy"
			made += 1
	check_eq(EnemyAI.behind(st, s, p), 1 + made, "the towns count too")
	if made == 3:
		for i in 50:
			s.spotted = {}
			s.follow = null
			st._spot(s)
			check(s.follow == p, "four behind: it always chases")
	check(st.log.entries.any(func(e): return str(e["text"]).contains("turns to chase")), "logged")


func test_one_roll_per_sighting_and_the_chase_ends_out_of_sight() -> void:
	var st := _game()
	var sp := _chase_setup(st)
	var s: Squad = sp[0]
	var p: Squad = sp[1]
	var h: Dictionary = d.ai["hunt"]
	var was: float = h["per_building"]
	h["per_building"] = 0.0
	st._spot(s)
	check(s.follow == null and s.spotted.has(str(p.id)), "rolled (and didn't chase)")
	h["per_building"] = 1.0
	st._spot(s)
	check(s.follow == null, "no second roll while your squad stays in sight")
	var at := p.hex
	p.hex = st.map.player_base
	st._spot(s)
	check(not s.spotted.has(str(p.id)), "out of sight: forgotten")
	p.hex = at
	st._spot(s)
	check(s.follow == p and s.is_moving(), "seen again: a new roll, and this time it chases")
	p.hex = st.map.player_base
	st._update_followers()
	check(s.follow == null and not s.is_moving(), "lost sight: the chase ends")
	h["per_building"] = was


func test_falling_back_goes_round_a_still_squad() -> void:
	var st := _game()
	var sp := _chase_setup(st)
	var s: Squad = sp[0]
	var p: Squad = sp[1]
	s.marching_home = true
	st._fall_back(s)
	check_eq(s.refuge, st.map.enemy_base, "heading for the Enemy Base")
	var close := Array(s.path).filter(func(i: int): return Hex.distance(st.map.hex_at(i), st.map.hex_at(p.hex)) <= 1)
	check(close.is_empty(), "the route keeps a hex clear of your squad standing in its way")
	p.path = PackedInt32Array([st.map.player_base])  # on the move: no way round it
	st._fall_back(s)
	close = Array(s.path).filter(func(i: int): return Hex.distance(st.map.hex_at(i), st.map.hex_at(p.hex)) <= 1)
	check(not close.is_empty(), "your squad on the move: the straight way, so you can catch it")


func test_a_route_round_falls_back_to_straight_when_boxed_in() -> void:
	var st := _game()
	var s: Squad = _chase_setup(st)[0]
	var all := PackedInt32Array()
	for i in st.map.size():
		if i != st.map.enemy_base:
			all.append(i)
	check(st.order_move(s, PackedInt32Array([st.map.enemy_base]), all), "no way round: it still goes")
	check(s.is_moving(), "straight")


func test_a_fight_put_aside_keeps_its_squads() -> void:
	var st := _game()
	var sp := _chase_setup(st)
	var s: Squad = sp[0]
	var p: Squad = sp[1]
	st.pending = st.start_battle(p, s, s)
	check(st.in_fight(p) and st.in_fight(s), "both are in the waiting fight")
	var at := p.hex
	st.send_home(p)
	check(p in st.squads and p.hex == at and not p.is_moving(), "it can't go home")
	check(st.portal_targets(p).is_empty(), "or step through a portal")
	var tick := st.clock.tick
	st.step()
	check_eq(st.clock.tick, tick, "the map waits for the fight")
