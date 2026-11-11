extends TestCase
## Squad status for the HUD (playtest round 7, ROADMAP M4 session 25): moving, in a
## building, or standing in the open.

var d := GameData.load_dir()


func test_moving_in_a_building_or_in_the_open() -> void:
	var m := MapData.new(20, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 2
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 4)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 4)))
	var town := m.index_of(Hex.from_offset(Vector2i(8, 4)))
	m.buildings.append({"type": "town", "hex": town, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	var s := st.add_squad("Ours", town, [["Knight", "front"]])
	check_eq(st.squad_status(s), "building", "standing in a town")
	check(st.status_text(s).begins_with("In "), st.status_text(s))
	st.order_move(s, PackedInt32Array([m.index_of(Hex.from_offset(Vector2i(10, 4)))]))
	check_eq(st.squad_status(s), "moving", "on the move")
	check(st.status_text(s).begins_with("Moving"), st.status_text(s))
	for i in 600:
		st.step()
	check_eq(st.squad_status(s), "still", "stopped in the open")
	check(st.status_text(s).begins_with("Standing in the open"), st.status_text(s))


func test_a_leaderless_squad_crawls_home_at_reduced_speed() -> void:
	var m := MapData.new(20, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 2
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 4)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 4)))
	var st := GameState.new(d, m, GameLog.new())
	var s := st.add_squad("Ours", m.index_of(Hex.from_offset(Vector2i(10, 4))), [["Knight", "front"], ["Fighter", "front"]])
	var normal := st.base_ticks(s)
	s.marching_home = true
	check(not s.crawling(), "marching home with its leader alive isn't crawling")
	check_eq(st.base_ticks(s), normal, "full speed")
	s.leader.hp = 0
	check(s.crawling(), "leader down and marching home: crawling")
	check(is_equal_approx(st.base_ticks(s), normal * float(d.rules["crawl_slowdown"]) * s.casualty_multiplier(d) / _casualty_free(st, s)), "slowed by crawl_slowdown")


## The casualty slowdown with the leader alive, to separate it from the crawl.
func _casualty_free(st: GameState, s: Squad) -> float:
	var hp := s.leader.hp
	s.leader.hp = s.leader.max_hp(d)
	var m := s.casualty_multiplier(d)
	s.leader.hp = hp
	return m
