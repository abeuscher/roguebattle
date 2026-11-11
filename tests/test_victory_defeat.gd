extends TestCase
## Victory and defeat (SPEC §6.8): each configurator toggle, and the symmetric
## capture mechanic that makes "Player Base captured" reachable.

var d := GameData.load_dir()


## A plains strip with a town at (8, 3), a tower at (12, 3), bases at the ends.
## `_check_game_over()` itself defaults every toggle to off (so other tests' GameStates,
## built with no settings at all, are never mistakenly "lost"); these tests are about
## victory/defeat specifically, so this helper fills in the configurator's real on-by-
## default toggles unless a test overrides them.
func _state(settings := {}) -> GameState:
	var merged := {"defeat_leader": true, "defeat_base": true, "victory_leader": true}
	merged.merge(settings, true)
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 9
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("player_base", m.player_base))
	m.buildings.append(_b("enemy_base", m.enemy_base))
	m.buildings.append(_b("town", _at(m, 8, 3)))
	m.buildings.append(_b("tower", _at(m, 12, 3)))
	return GameState.new(d, m, GameLog.new(), merged)


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": true, "hint": false, "hidden": false, "kind": "", "road": false}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


## A player squad placed in army cell 0 (the Opinion Leader's squad).
func _opinion_leader(st: GameState, col: int) -> Squad:
	var s := st.add_squad("Ours", _at(st.map, col, 3), [["Knight", "front"], ["Fighter", "front"]])
	st.army.cells[0] = s
	return s


func test_opinion_leader_dying_is_a_defeat() -> void:
	var st := _state()
	var s := _opinion_leader(st, 2)
	s.leader.hp = 0
	st._check_game_over()
	check_eq(st.game_over, "defeat", "the Opinion Leader's own death ends the map")
	check(st.game_over_reason.contains("Opinion Leader"), "reason names the Opinion Leader")


func test_opinion_leader_toggle_off() -> void:
	var st := _state({"defeat_leader": false, "defeat_base": false, "victory_leader": false})
	var s := _opinion_leader(st, 2)
	s.leader.hp = 0
	st._check_game_over()
	check_eq(st.game_over, "", "off by the configurator, the Opinion Leader's death doesn't end the map")


func test_player_base_captured_is_a_defeat() -> void:
	var st := _state({"defeat_leader": false})
	st.building_at(st.map.player_base)["owner"] = "enemy"
	st._check_game_over()
	check_eq(st.game_over, "defeat", "an enemy-held Player Base ends the map")


func test_enemy_squad_captures_the_player_base() -> void:
	var st := _state({"defeat_leader": false, "victory_leader": false})
	var raider := st.add_squad("Raiders", st.map.player_base, [["Goblin", "front"]], "enemy")
	for i in int(d.rules["capture"]["ticks"]):
		st.step()
	check_eq(st.building_at(st.map.player_base)["owner"], "enemy", "the raider's siege flips the base's owner")
	check_eq(st.game_over, "defeat", "...and that's a defeat")


func test_defeating_the_enemy_leader_is_the_default_victory() -> void:
	var st := _state({"defeat_leader": false, "defeat_base": false})
	var enemy_leader := st.add_squad("Enemy Leader", st.map.enemy_base, [["Knight", "front"]], "enemy")
	enemy_leader.role = "leader"
	st.squads.erase(enemy_leader)
	st._check_game_over()
	check_eq(st.game_over, "victory", "no enemy leader squad left on the map: victory")
	check(st.game_over_reason.contains("enemy leader"), "reason names the enemy leader")


func test_victory_leader_toggle_off() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false})
	st._check_game_over()
	check_eq(st.game_over, "", "no enemy leader was ever placed, but the toggle is off: no victory")


func test_reach_the_goal() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false, "victory_goal": true})
	st.add_squad("Ours", st.map.enemy_base, [["Knight", "front"]])
	st._check_game_over()
	check_eq(st.game_over, "victory", "a living player squad standing at the goal wins")


func test_defeat_n_enemy_squads() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_squads": true, "victory_squads_n": 2})
	st.enemy_squads_defeated = 1
	st._check_game_over()
	check_eq(st.game_over, "", "1 of 2 required isn't enough yet")
	st.enemy_squads_defeated = 2
	st._check_game_over()
	check_eq(st.game_over, "victory", "2 of 2 required: victory")


func test_defeat_all_enemy_squads() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_squads": true, "victory_squads_n": "all"})
	var e := st.add_squad("Raiders", st.map.enemy_base, [["Goblin", "front"]], "enemy")
	st._check_game_over()
	check_eq(st.game_over, "", "an enemy squad still stands")
	st.squads.erase(e)
	st._check_game_over()
	check_eq(st.game_over, "victory", "none left: victory")


func test_hold_towns() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_towns": true, "victory_towns_pct": 100, "victory_towns_days": 1})
	st.building_at(_at(st.map, 8, 3))["owner"] = "player"
	st.building_at(_at(st.map, 12, 3))["owner"] = "player"
	st._check_game_over()
	check_eq(st.game_over, "", "just reached 100%: the clock starts now")
	st.clock.tick += 1440 - 1
	st._check_game_over()
	check_eq(st.game_over, "", "not quite a full day yet")
	st.clock.tick += 2
	st._check_game_over()
	check_eq(st.game_over, "victory", "held 100% of the towns for a full day")


func test_hold_towns_resets_if_a_town_is_lost() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_towns": true, "victory_towns_pct": 100, "victory_towns_days": 1})
	st.building_at(_at(st.map, 8, 3))["owner"] = "player"
	st.building_at(_at(st.map, 12, 3))["owner"] = "player"
	st._check_game_over()
	st.building_at(_at(st.map, 12, 3))["owner"] = "enemy"
	st._check_game_over()
	st.building_at(_at(st.map, 12, 3))["owner"] = "player"
	st.clock.tick += 1440
	st._check_game_over()
	check_eq(st.game_over, "", "losing the tower in between resets the held-since clock")


func test_survive_the_timer() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_timer": true, "victory_timer_days": 3})
	st.clock.tick = 3 * 1440 - 1
	st._check_game_over()
	check_eq(st.game_over, "", "not quite 3 days yet")
	st.clock.tick += 1
	st._check_game_over()
	check_eq(st.game_over, "victory", "the timer runs out: victory")


func test_victory_awards_the_map_end_tech_bonus() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_timer": true, "victory_timer_days": 1})
	var before := st.tech_points
	st.clock.tick = 1440
	st._check_game_over()
	check_eq(st.tech_points, before + int(d.tech["points"]["map_end"]), "victory earns the map_end tech bonus")
	check_eq(st.end_summary()["tech_points"], st.tech_points, "...and it shows in the end summary")


func test_defeat_awards_no_tech_bonus() -> void:
	var st := _state({"defeat_leader": false})
	var before := st.tech_points
	st.building_at(st.map.player_base)["owner"] = "enemy"
	st._check_game_over()
	check_eq(st.tech_points, before, "losing earns no map_end bonus")


func test_game_over_is_sticky_and_stops_the_tick() -> void:
	var st := _state({"victory_leader": false, "defeat_leader": false, "defeat_base": false,
			"victory_timer": true, "victory_timer_days": 1})
	st.clock.tick = 1440
	st._check_game_over()
	check_eq(st.game_over, "victory", "sanity: the timer fired")
	var tick_before := st.clock.tick
	st.step()
	check_eq(st.clock.tick, tick_before, "step() does nothing once the map has ended")


func test_defeat_is_checked_before_victory_on_the_same_tick() -> void:
	var st := _state()
	var leader := _opinion_leader(st, 2)
	leader.leader.hp = 0
	var enemy_leader := st.add_squad("Enemy Leader", st.map.enemy_base, [["Knight", "front"]], "enemy")
	enemy_leader.role = "leader"
	st.squads.erase(enemy_leader)
	st._check_game_over()
	check_eq(st.game_over, "defeat", "both conditions are met at once: defeat wins the tie")


func test_taking_the_enemy_base_wins_whatever_the_settings() -> void:
	var st := _state({"victory_leader": false})
	_opinion_leader(st, 5)
	st.add_squad("Warlord", _at(st.map, 20, 3), [["Knight", "front"]], "enemy").role = "leader"
	st._check_game_over()
	check_eq(st.game_over, "", "nothing yet")
	st.building_at(st.map.enemy_base)["owner"] = "player"
	st._check_game_over()
	check_eq(st.game_over, "victory", "the Enemy Base taken is a victory")
