extends TestCase
## Temples (ROADMAP M4 session 31): taken like towns with no rewards, worth a little to
## the enemy, portals between temples you hold, training while resting in one, and
## catch-up battle XP.

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(40, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 4
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 38, 4)
	for col in [10, 20, 30]:
		m.buildings.append({"type": "temple", "hex": _at(m, col, 4), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	st.debug_freeze_ai = true
	return st


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _temple(st: GameState, col: int) -> Dictionary:
	return st.building_at(_at(st.map, col, 4))


func test_taking_a_temple_gives_no_rewards() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 10, 4), [["Knight", "front"]])
	var gold := st.gold
	var rep := st.reputation
	var cards := st.cards.size()
	for i in int(d.rules["capture"]["ticks"]) + 1:
		st.step()
	check_eq(_temple(st, 10)["owner"], "player", "the temple is ours")
	check_eq([st.gold, st.reputation, st.cards.size()], [gold, rep, cards], "no bonus gold, reputation or card")
	check_eq(st.liberations.size(), 1, "a window says so, like a liberation (round 11)")
	check_eq([str(st.liberations[0]["card"]), st.liberations[0]["recruits"].size()], ["", 0], "with no card and no conscripts")
	check_eq(s.capture_ticks, 0.0, "done")


func test_losing_a_temple_costs_no_reputation() -> void:
	var st := _state()
	_temple(st, 10)["owner"] = "player"
	st.add_squad("Foe", _at(st.map, 10, 4), [["Soldier", "front"]], "enemy")
	var rep := st.reputation
	for i in int(d.rules["capture"]["ticks"]) + 1:
		st.step()
	check_eq(_temple(st, 10)["owner"], "enemy", "the enemy takes it")
	check_eq(st.reputation, rep, "no reputation lost")
	check(not st.losses.is_empty() and int(st.losses[0]["reputation"]) == 0, "the 'lost' window, with no reputation cost")


func test_the_enemy_goes_for_temples_last() -> void:
	var st := _state()
	var foe := st.add_squad("Foe", _at(st.map, 25, 4), [["Soldier", "front"]], "enemy")
	foe.role = "field"
	check_eq(EnemyAI.best_move(st, foe)[0], _temple(st, 20)["hex"], "with only temples about, it goes for the nearest")
	st.map.buildings.append({"type": "town", "hex": _at(st.map, 32, 4), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	st.map.buildings[-1]["owner"] = "neutral"
	st._building_at[st.map.buildings[-1]["hex"]] = st.map.buildings.size() - 1
	check_eq(EnemyAI.best_move(st, foe)[0], st.map.buildings[-1]["hex"], "a town at a similar distance comes first")


func test_portals_join_only_temples_you_hold() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 10, 4), [["Knight", "front"]])
	check(st.portal_targets(s).is_empty(), "not ours: no portal")
	_temple(st, 10)["owner"] = "player"
	check(st.portal_targets(s).is_empty(), "the only temple we hold: nowhere to go")
	_temple(st, 30)["owner"] = "player"
	check_eq(st.portal_targets(s), [_at(st.map, 30, 4)] as Array[int], "the other temple we hold, not the neutral one")
	check(not st.portal(s, _at(st.map, 20, 4)), "a temple we don't hold is refused")
	st.order_move(s, PackedInt32Array([_at(st.map, 10, 1)]))
	check(st.portal_targets(s).is_empty(), "not while moving")
	s.path.clear()
	s.rally.clear()
	check(st.portal(s, _at(st.map, 30, 4)), "step through")
	check_eq(s.hex, _at(st.map, 30, 4), "there at once")
	var foe := st.add_squad("Foe", _at(st.map, 10, 4), [["Soldier", "front"]], "enemy")
	check(st.portal_targets(foe).is_empty(), "player squads only")


func test_training_favours_low_levels() -> void:
	var st := _state()
	_temple(st, 10)["owner"] = "player"
	var s := st.add_squad("Ours", _at(st.map, 10, 4), [["Knight", "front"], ["Fighter", "front"]])
	var low := s.units[1]
	var high := s.units[0]
	low.level = 1
	high.level = 6
	var xp := [low.xp, high.xp]
	st._rest()
	var gained := [low.xp - xp[0], high.xp - xp[1]]
	check_eq(gained[0], st.training_xp(low), "level 1 earns the full amount")
	check(gained[0] > gained[1] and gained[1] >= 1, "more for the lower level: %s" % str(gained))


func test_no_training_in_a_temple_you_dont_hold() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 10, 4), [["Fighter", "front"]])
	var xp := s.units[0].xp
	st._rest()
	check_eq(s.units[0].xp, xp, "neutral temple: rest, but no training")


func test_catch_up_xp() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"]])
	var foe := st.add_squad("Foe", _at(st.map, 6, 4), [["Soldier", "front"]], "enemy")
	for u in s.units:
		u.level = 5
	var even := Progression.battle_xp(d, s, foe, s.units[1])
	s.units[2].level = 2  # average now 4: two levels under
	var p: Dictionary = d.rules["progression"]
	check(is_equal_approx(Progression.catch_up(d, s, s.units[2]), 1.0 + 2 * float(p["catch_up_per_level"])), "two levels under the average")
	check_eq(Progression.catch_up(d, s, s.units[0]), 1.0, "at or above the average: no extra")
	check(Progression.battle_xp(d, s, foe, s.units[2]) > Progression.battle_xp(d, s, foe, s.units[0]), "the low unit earns more")
	s.units[2].level = 1
	s.units[0].level = 40
	check_eq(Progression.catch_up(d, s, s.units[2]), float(p["catch_up_max"]), "capped")
	check(even > 0, "XP flows")
