extends TestCase
## Skip to action (playtest round 15, settled 2026-11-14; round 23): it runs until something
## opens a window or wants your orders, and no further.

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(60, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 5
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 58, 4)
	var st := GameState.new(d, m, GameLog.new())
	st.clock.tick = 8 * 60  # 08:00
	return st


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _march(st: GameState, col: int, to_col: int) -> Squad:
	var s := st.add_squad("Ours", _at(st.map, col, 4), [["Knight", "front"]])
	st.order_move(s, PackedInt32Array([_at(st.map, to_col, 4)]))
	return s


func test_standing_squads_dont_block_it() -> void:
	var st := _state()
	check(st.skip_blocker() != "", "nothing on the map: no skip")
	var a := _march(st, 5, 12)
	check_eq(st.skip_blocker(), "", "one squad, on the move: skip")
	var b := st.add_squad("Idle", _at(st.map, 8, 2), [["Knight", "front"]])
	check_eq(st.skip_blocker(), "", "another standing in place doesn't stop it (round 22)")
	var why := st.skip_ticks(5000)
	check(why.contains(a.name), "it runs until the one moving arrives, not stopped by %s" % b.name)


func test_stops_when_a_squad_arrives() -> void:
	var st := _state()
	var s := _march(st, 5, 9)
	var why := st.skip_ticks(5000)
	check(why.contains("has stopped"), "it stops on arrival: %s" % why)
	check_eq(s.hex, _at(st.map, 9, 4), "right there")
	check(not s.is_moving(), "and not a tick on")


func test_goes_past_what_needs_no_answer() -> void:
	var st := _state()
	var s := _march(st, 5, 33)
	var foe := st.add_squad("Raiders", _at(st.map, 30, 4), [["Soldier", "front"]], "enemy")
	foe.role = "garrison"
	foe.post = foe.hex
	foe.hex = _at(st.map, 30, 0)  # off the road, out of the way
	st.debug_freeze_ai = true
	st.notices.append("The enemy has captured Somewhere.")
	var why := st.skip_ticks(5000)
	check(why.contains("has stopped"), "a squad coming into sight or news doesn't stop it, the arrival does (round 23): %s" % why)
	check(st.is_visible(foe), "they came into sight on the way")
	check_eq(st.skip_squad, s, "and it names the squad, for the camera")


func test_stops_at_noon() -> void:
	var st := _state()
	st.clock.tick = 11 * 60 + 50  # 11:50
	_march(st, 5, 55)
	var why := st.skip_ticks(5000)
	check_eq(why, "Noon.", "noon stops it")
	check_eq(st.clock.minute_of_day(), GameClock.NOON, "at noon exactly")
	st.clock.tick = 11 * 60 + 50 + GameClock.TICKS_PER_DAY
	why = st.skip_ticks(30, {"ledger": false})
	check(why != "Noon.", "not with the noon ledger window off")


func test_stops_when_a_fight_starts() -> void:
	var st := _state()
	_march(st, 5, 20)
	var foe := st.add_squad("Wall", _at(st.map, 14, 4), [["Soldier", "front"]], "enemy")
	foe.role = "garrison"
	foe.post = foe.hex
	st.debug_freeze_ai = true
	var why := st.skip_ticks(5000)
	check(st.pending != null and why == "Something needs you.", "it runs to the fight, past the sighting: %s" % why)
	check_eq(st.skip_squad, st.pending.sides[0] if st.pending else null, "the squad in it")
