extends TestCase
## The debug panel's tools (SPEC §19.2): each one exercised on a small plains map.

var d := GameData.load_dir()


func _state(w := 30, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 5
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _ours(st: GameState, col: int) -> Squad:
	var s := st.add_squad("Ours", _at(st.map, col, 4), [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]])
	st.army.cells[st.army.cells.find(null)] = s
	return s


func _theirs(st: GameState, col: int) -> Squad:
	return st.add_squad("Theirs", _at(st.map, col, 4), [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]], "enemy")


func _draft(st: GameState) -> Squad:
	var dr := DebugTools.draft(st)
	check(DebugTools.add_unit(st, dr, "Fighter", 1), "a Fighter added")
	check(DebugTools.add_unit(st, dr, "Knight", 4), "a level 4 Knight added")
	check(DebugTools.add_unit(st, dr, "Bowman", 2), "a level 2 Bowman added")
	return dr


func test_a_built_squad_places_with_the_chosen_classes_and_levels() -> void:
	var st := _state()
	var dr := _draft(st)
	var s: Squad = DebugTools.place(st, dr, "player", _at(st.map, 5, 4))
	check(s in st.squads and s in st.army.squads(), "on the map and in the army")
	var got := []
	for u in s.units:
		got.append([u.unit_class, u.level])
	check_eq(got, [["Fighter", 1], ["Knight", 4], ["Bowman", 2]], "exactly what was chosen")
	check_eq(s.leader.unit_class, "Knight", "the unit that can lead leads")
	check_eq(s.row("back")[0].unit_class, "Bowman", "each in its usual row")
	var again: Squad = DebugTools.place(st, dr, "enemy", _at(st.map, 10, 4))
	check(again.units[0] != s.units[0], "the draft stays and places again, as fresh copies")
	check_eq([again.side, again.role], ["enemy", "garrison"], "an enemy holds its post")
	var n: Squad = DebugTools.place(st, dr, "neutral", _at(st.map, 15, 4))
	check_eq(n.role, "roamer", "a neutral roams")
	check(n.id != again.id and again.id != s.id, "distinct ids")


func test_removing_a_unit_from_the_draft() -> void:
	var st := _state()
	var dr := _draft(st)
	DebugTools.remove_unit(st, dr, dr.leader)
	check_eq(dr.units.size(), 2, "two left")
	check(dr.leader == null, "no one else can lead")
	check(DebugTools.place(st, dr, "player", _at(st.map, 5, 4)) is String, "a squad without a leader isn't placed")
	check(DebugTools.place(st, DebugTools.draft(st), "player", _at(st.map, 5, 4)) is String, "nor an empty one")
	var stale := _draft(st)
	var gone := stale.leader
	stale.units.erase(gone)  # a leader that's no longer in the squad doesn't count
	check(DebugTools.place(st, stale, "player", _at(st.map, 5, 4)) is String, "a stale leader isn't a leader")
	var fallen := _draft(st)
	fallen.leader.hp = 0
	check(DebugTools.place(st, fallen, "player", _at(st.map, 5, 4)) is String, "nor a fallen one")


func test_the_draft_holds_a_full_squad_and_no_more() -> void:
	var st := _state()
	var dr := DebugTools.draft(st)
	var added := 0
	for i in 20:
		if DebugTools.add_unit(st, dr, "Fighter", 1):
			added += 1
	check_eq(added, dr.capacity(d), "as many as the slots hold")


func test_teleport_clears_orders() -> void:
	var st := _state()
	var s := _ours(st, 3)
	st.order_move(s, PackedInt32Array([_at(st.map, 20, 4)]))
	DebugTools.teleport(st, s, _at(st.map, 12, 2))
	check_eq(s.hex, _at(st.map, 12, 2), "on the new hex")
	check(not s.is_moving(), "order cleared")


func test_remove_squad() -> void:
	var st := _state()
	var s := _ours(st, 3)
	DebugTools.remove(st, s)
	check(s not in st.squads, "off the map")
	check(s not in st.army.squads(), "out of the army")


func test_heal_all_revives() -> void:
	var st := _state()
	var s := _ours(st, 3)
	s.units[0].hp = 0
	s.units[1].hp = 1
	DebugTools.heal_all(st)
	for u in s.units:
		check_eq(u.hp, u.max_hp(d), "%s at full HP" % u.name)


func test_set_alignment() -> void:
	var st := _state()
	var s := _ours(st, 3)
	DebugTools.set_alignment(st, s, 90)
	for u in s.units:
		check_eq(u.alignment, 90, "alignment 90")


func test_set_time_and_freeze() -> void:
	var st := _state()
	st.clock.set_minute(GameClock.NOON + 60)
	check_eq(st.clock.minute_of_day(), GameClock.NOON + 60, "13:00")
	var day := st.clock.day()
	st.clock.frozen = true
	for i in 300:
		st.step()
	check_eq(st.clock.minute_of_day(), GameClock.NOON + 60, "time stands still while frozen")
	check_eq(st.clock.day(), day, "same day")
	st.clock.frozen = false
	st.step()
	check_eq(st.clock.minute_of_day(), GameClock.NOON + 61, "and runs again")


func test_skip_hours() -> void:
	var st := _state()
	var before := st.clock.tick
	check_eq(DebugTools.skip_hours(st, 3), 180, "three hours of ticks")
	check_eq(st.clock.tick - before, 180, "the clock moved with them")


func test_reveal_shows_far_enemies() -> void:
	var st := _state(60)
	_ours(st, 2)
	var e := _theirs(st, 55)
	check(not st.is_visible(e), "out of sight")
	st.debug_reveal = true
	check(st.is_visible(e), "revealed")


func test_freeze_ai_holds_enemies() -> void:
	var st := _state()
	var e := _theirs(st, 25)
	e.role = "raider"
	st.debug_freeze_ai = true
	var at := e.hex
	for i in 200:
		st.step()
	check_eq(e.hex, at, "a frozen raider doesn't move")


func test_forced_outcomes() -> void:
	for kind in ["win", "loss", "draw"]:
		var st := _state()
		st.debug_force = kind
		var a := _ours(st, 5)
		var b := _theirs(st, 6)
		st.pending = st.start_battle(a, b, b)
		var out := st.resolve_pending()
		check_eq(out["wiped"][1], kind == "win", "%s: enemy wiped" % kind)
		check_eq(out["wiped"][0], kind == "loss", "%s: player wiped" % kind)
		if kind == "draw":
			check_eq(out["hp_lost"], [0.0, 0.0], "draw: nobody hurt")


func test_replay_uses_the_same_rolls() -> void:
	var st := _state()
	var a := _ours(st, 5)
	var b := _theirs(st, 6)
	st.pending = st.start_battle(a, b, b)
	st.pending.run()
	var first := st.pending.events.map(func(e): return st.pending.log_line(e))
	var hp_after := a.units.map(func(u: Unit): return u.hp)
	var r1 := DebugTools.replay(st)
	r1.run()
	check_eq(r1.events.map(func(e): return r1.log_line(e)), first, "same events, same rolls")
	var r2 := DebugTools.replay(st)
	r2.run()
	check_eq(r2.events.size(), r1.events.size(), "replays repeat")
	check_eq(a.units.map(func(u: Unit): return u.hp), hp_after, "the real squad is untouched")


func test_fairness_rules_switch_off() -> void:
	var st := _state()
	st.debug_fairness["two_dice"] = false
	st.debug_fairness["spread"] = false
	var e := _theirs(st, 6)
	var b := st.start_battle(_ours(st, 5), e, e)
	check(not b.fairness_rules["two_dice"], "two-dice roll off")
	check(b.fairness_rules["streak_breaker"], "streak breaker still on")
	check_eq(b._spread(), float(d.battle["spread_unfair"]), "wider spread")


func test_build_of_puts_leader_first() -> void:
	var st := _state()
	var s := _ours(st, 3)
	var build := DebugTools.build_of(s)
	check_eq(build[0][0], s.leader.unit_class, "leader first")
	var r := BattleSim.run(d, build, DebugTools.build_of(_theirs(st, 8)), 5, 1)
	check_eq(int(r["trials"]), 5, "sim runs on the builds")
