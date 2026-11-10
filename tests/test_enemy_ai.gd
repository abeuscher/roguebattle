extends TestCase
## Enemy map AI (SPEC §12.3, §17; even start, user's playtest notes 2026-11-10): the
## Warlord and base guard hold the base; field squads take buildings, then score
## holding against moving on, with an 80/20 split between logic and a coin flip.

var d := GameData.load_dir()


## A plains strip map with the player base on the left and the enemy base on the right.
func _state(w := 30, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 9
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	m.buildings.append({"type": "player_base", "hex": m.player_base, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	m.buildings.append({"type": "enemy_base", "hex": m.enemy_base, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


## A town added after setup (so GameState's building index knows about it).
func _town(st: GameState, col: int, row := 4, owner := "neutral", type := "town") -> Dictionary:
	var b := {"type": type, "hex": _at(st.map, col, row), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false,
			"owner": owner, "away": false}
	st.map.buildings.append(b)
	st._building_at[b["hex"]] = st.map.buildings.size() - 1
	return b


func _enemy_squad(st: GameState, col: int, row: int, role: String) -> Squad:
	var s := st.add_squad(role.capitalize(), _at(st.map, col, row), [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]], "enemy")
	s.role = role
	s.post = s.hex
	return s


func _run(st: GameState, ticks: int) -> void:
	for i in ticks:
		st.step()
		if st.pending:
			break


func test_leader_and_base_guard_hold_the_base() -> void:
	var st := _state()
	_town(st, 15)
	var lead := _enemy_squad(st, 28, 4, "leader")
	var guard := _enemy_squad(st, 28, 4, "base_guard")
	_run(st, 100)
	for s in [lead, guard]:
		check(not s.is_moving() and s.hex == st.map.enemy_base, "%s stays on the Enemy Base" % s.role)


func test_field_squad_marches_out_and_takes_a_town() -> void:
	var st := _state()
	var town := _town(st, 15)
	_enemy_squad(st, 28, 4, "field")
	_run(st, 600)
	check_eq(town["owner"], "enemy", "it walked to the neutral town and took it")


func test_two_field_squads_pick_different_towns() -> void:
	var st := _state()
	var a := _town(st, 15, 2)
	var b := _town(st, 15, 6)
	_enemy_squad(st, 28, 4, "field")
	_enemy_squad(st, 28, 4, "field")
	_run(st, 800)
	check(a["owner"] == "enemy" and b["owner"] == "enemy", "each went for its own town")


func test_values_favour_the_middle_and_player_towns() -> void:
	var st := _state()
	var near_home := _town(st, 26)
	var middle := _town(st, 15, 2)
	var theirs := _town(st, 15, 6, "player")
	check(EnemyAI.value(st, middle) > EnemyAI.value(st, near_home), "a town midway is worth more than one by the Enemy Base")
	check_eq(EnemyAI.value(st, theirs), EnemyAI.value(st, middle) * 2.0, "a player-held one is worth double")
	var tower := _town(st, 15, 8, "neutral", "tower")
	check(EnemyAI.value(st, tower) < EnemyAI.value(st, _town(st, 15, 0)), "a tower is worth less than a town")


func test_hold_when_threatened_move_when_safe() -> void:
	var st := _state()
	var here := _town(st, 20, 4, "enemy")
	_town(st, 12, 4)
	var s := _enemy_squad(st, 20, 4, "field")
	var calm := EnemyAI.hold_score(st, s)
	check(calm < EnemyAI.best_move(st, s)[1], "nothing near: moving on scores higher")
	st.add_squad("Ours", _at(st.map, 17, 4), [["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"]])
	check(EnemyAI.hold_score(st, s) > calm, "a player squad close by makes holding worth more")
	check(EnemyAI.hold_score(st, s) > EnemyAI.best_move(st, s)[1], "and now holding wins")
	_enemy_squad(st, 20, 4, "field")
	check_eq(EnemyAI.hold_score(st, s), 0.0, "not worth holding what another enemy squad already holds")
	check(here["owner"] == "enemy", "setup")


func test_logic_wins_about_80_percent() -> void:
	var st := _state()
	_town(st, 20, 4, "enemy")
	_town(st, 12, 4)
	var moves := 0
	var n := 400
	for i in n:
		var s := _enemy_squad(st, 20, 4, "field")
		s.think_at = 0
		if EnemyAI.target_hex(st, s) >= 0:
			moves += 1
		st.squads.erase(s)
	# Logic says move (nothing near); the coin flip holds half of the other 20%: ~90% move.
	check(moves > n * 0.84 and moves < n * 0.96, "moves %d of %d, about 90%%" % [moves, n])


func test_a_holding_squad_thinks_again_later() -> void:
	var st := _state()
	_town(st, 20, 4, "enemy")
	var s := _enemy_squad(st, 20, 4, "field")
	check_eq(EnemyAI.target_hex(st, s), -1, "nowhere else to go: it holds")
	check_eq(s.think_at, st.clock.tick + int(d.ai["field"]["rethink_ticks"]), "and waits before thinking again")
	_town(st, 12, 4)
	check_eq(EnemyAI.target_hex(st, s), -1, "until then it keeps holding")


## Enemy units come back only at the Enemy Base; a squad down half its units goes
## there, revives, and returns to its post (user's playtest notes, 2026-11-09).
func test_half_beaten_squad_goes_home_revives_and_returns() -> void:
	var st := _state()
	var post := _at(st.map, 20, 4)
	var s := _enemy_squad(st, 20, 4, "base_guard")
	s.post = post
	s.units[0].hp = 0
	s.units[1].hp = 0
	st.step()
	check(s.marching_home and s.is_moving(), "two of three down: it heads home")
	var reached := false
	for i in 2000:
		st.step()
		if s.hex == st.map.enemy_base:
			reached = true
		if reached and s.hex == post and not s.is_moving():
			break
	check(reached, "it reached the Enemy Base")
	check_eq(s.living().size(), s.units.size(), "everyone revived there, at full HP")
	check_eq(s.units[0].hp, s.units[0].max_hp(d), "full HP")
	check_eq(s.hex, post, "and it went back to its post")


func test_lighter_losses_stay_down_away_from_base() -> void:
	var st := _state()
	var s := _enemy_squad(st, 20, 4, "base_guard")
	s.add(d, Unit.roll(d, "Fighter", st.rng.get_stream("test"), NameBook.new(d)), "front")
	s.units[0].hp = 0  # one of four
	for i in 24 * 60:
		st.step()
	check(not s.marching_home and s.hex == s.post, "one of four down: it holds its post")
	check(not s.units[0].is_alive(), "and no one revives it away from the base")
