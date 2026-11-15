extends TestCase
## Skip to action (playtest round 15, settled 2026-11-14): only while every squad of
## yours on the map is moving; it runs until something needs you, and no further.

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


func test_only_while_every_squad_moves() -> void:
	var st := _state()
	check(st.skip_blocker() != "", "nothing on the map: no skip")
	var a := _march(st, 5, 12)
	check_eq(st.skip_blocker(), "", "one squad, on the move: skip")
	var b := st.add_squad("Idle", _at(st.map, 8, 2), [["Knight", "front"]])
	check(st.skip_blocker().contains(b.name), "another standing still: no skip, and it says which")
	st.order_move(b, PackedInt32Array([_at(st.map, 9, 2)]))
	check_eq(st.skip_blocker(), "", "both moving again")


func test_stops_when_a_squad_arrives() -> void:
	var st := _state()
	var s := _march(st, 5, 9)
	var why := st.skip_ticks(5000)
	check(why.contains("has stopped"), "it stops on arrival: %s" % why)
	check_eq(s.hex, _at(st.map, 9, 4), "right there")
	check(not s.is_moving(), "and not a tick on")


func test_stops_when_an_enemy_comes_into_sight() -> void:
	var st := _state()
	_march(st, 5, 40)
	var foe := st.add_squad("Raiders", _at(st.map, 30, 4), [["Soldier", "front"]], "enemy")
	foe.role = "garrison"
	foe.post = foe.hex
	st.debug_freeze_ai = true
	check(not st.is_visible(foe), "out of sight to begin with")
	var why := st.skip_ticks(5000)
	check(why.contains("Raiders") and why.contains("sight"), "it stops when they come into sight: %s" % why)
	check(st.is_visible(foe), "they're visible now")


func test_stops_at_noon() -> void:
	var st := _state()
	st.clock.tick = 11 * 60 + 50  # 11:50
	_march(st, 5, 55)
	var why := st.skip_ticks(5000)
	check_eq(why, "Noon.", "noon stops it")
	check_eq(st.clock.minute_of_day(), GameClock.NOON, "at noon exactly")


func test_stops_when_a_fight_starts() -> void:
	var st := _state()
	_march(st, 5, 20)
	var foe := st.add_squad("Wall", _at(st.map, 14, 4), [["Soldier", "front"]], "enemy")
	foe.role = "garrison"
	foe.post = foe.hex
	st.debug_freeze_ai = true
	var why := st.skip_ticks(5000)
	check(st.pending != null or why.contains("sight"), "it stops at the sighting or the fight: %s" % why)
	if st.pending == null:
		why = st.skip_ticks(5000)
		check(st.pending != null and why == "Something needs you.", "then at the fight: %s" % why)
