extends TestCase
## Following an enemy squad (playtest round 8, ROADMAP M4 session 23); only one on the
## move, enemy or neutral (round 10, session 29).

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(40, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 5
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 38, 4)
	var st := GameState.new(d, m, GameLog.new())
	st.debug_freeze_ai = true  # the enemy moves only when the test moves it
	return st


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _pair(st: GameState, ours_col: int, theirs_col: int) -> Array:
	var ours := st.add_squad("Ours", _at(st.map, ours_col, 4), [["Knight", "front"], ["Fighter", "front"]])
	var theirs := st.add_squad("Theirs", _at(st.map, theirs_col, 4), [["Soldier", "front"]], "enemy")
	st.order_move(theirs, PackedInt32Array([_at(st.map, theirs_col, 1)]))  # on the move, so it can be followed (round 10)
	return [ours, theirs]


func test_a_follower_heads_for_the_target_and_reroutes_when_it_moves() -> void:
	var st := _state()
	var p := _pair(st, 5, 10)
	var ours: Squad = p[0]
	var theirs: Squad = p[1]
	check(st.order_follow(ours, theirs), "the order takes")
	check_eq(ours.path[ours.path.size() - 1], theirs.hex, "headed for the enemy's hex")
	theirs.hex = _at(st.map, 10, 7)  # it moves (still in sight)
	st.step()
	check_eq(ours.path[ours.path.size() - 1], theirs.hex, "re-routed to where it is now")
	check(ours.follow == theirs, "still following")


func test_contact_starts_a_fight_as_usual() -> void:
	var st := _state()
	var p := _pair(st, 5, 9)
	st.order_follow(p[0], p[1])
	for i in 2000:
		st.step()
		if st.pending:
			break
	check(st.pending != null, "the follower caught up and a battle began")


func test_out_of_sight_it_goes_to_the_last_seen_hex_and_stops() -> void:
	var st := _state()
	var p := _pair(st, 5, 10)
	var ours: Squad = p[0]
	var theirs: Squad = p[1]
	st.order_follow(ours, theirs)
	var last: int = theirs.hex
	theirs.hex = _at(st.map, 36, 4)  # far beyond sight
	st.step()
	check(ours.follow == null, "following ends")
	check_eq(ours.path[ours.path.size() - 1], last, "heading for where it was last seen")
	for i in 2000:
		st.step()
	check_eq(ours.hex, last, "and stops there")
	check(not ours.is_moving(), "stopped")


func test_a_new_order_ends_following() -> void:
	var st := _state()
	var p := _pair(st, 5, 10)
	var ours: Squad = p[0]
	st.order_follow(ours, p[1])
	st.order_move(ours, PackedInt32Array([_at(st.map, 5, 1)]))
	check(ours.follow == null, "a move order replaces following")
	p[1].hex = _at(st.map, 12, 4)
	st.step()
	check_eq(ours.path[ours.path.size() - 1], _at(st.map, 5, 1), "and the squad keeps to its new order")


func test_a_vanished_target_ends_following() -> void:
	var st := _state()
	var p := _pair(st, 5, 10)
	var ours: Squad = p[0]
	st.order_follow(ours, p[1])
	st.squads.erase(p[1])  # wiped out
	st.step()
	check(ours.follow == null, "nothing left to follow")


func test_a_squad_standing_still_cant_be_followed() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"]])
	var parked := st.add_squad("Parked", _at(st.map, 9, 4), [["Soldier", "front"]], "enemy")
	check(not st.can_follow(parked), "standing still: no Follow")
	check(not st.order_follow(ours, parked), "the order is refused")
	check(ours.follow == null, "not following")


func test_a_moving_neutral_can_be_followed() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"]])
	var wolves := st.add_squad("Wolves", _at(st.map, 9, 4), [["Soldier", "front"]], "neutral")
	st.order_move(wolves, PackedInt32Array([_at(st.map, 9, 1)]))
	check(st.can_follow(wolves), "a neutral on the move can be followed")
	check(st.order_follow(ours, wolves), "the order takes")
	check(ours.follow == wolves, "following it")
