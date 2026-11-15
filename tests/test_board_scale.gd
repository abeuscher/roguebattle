extends TestCase
## Pace and board scale (playtest round 16): with the squad cap on Auto, both sides field a
## force that scales with the map's towns, towers and temples, and they're matched.

var d := GameData.load_dir()


func _state(w: int, h: int, seed := 7) -> GameState:
	var cfg := GameConfig.create(d, seed)
	cfg.set_value("width", w)
	cfg.set_value("height", h)
	var m := MapGen.generate(d, cfg.seed, cfg.map_overrides())
	return GameState.new(d, m, GameLog.new(), cfg.game_settings())


func test_the_force_scales_with_the_map() -> void:
	var c: Dictionary = d.rules["board_scale"]
	var small := _state(100, 45)
	var big := _state(600, 400)
	check_eq(small.squad_cap(), int(c["min_squads"]), "a tiny map: the minimum")
	var places := big.map.buildings.filter(func(b): return b["type"] in ["town", "tower", "temple"]).size()
	check_eq(big.squad_cap(), clampi(roundi(places / float(c["places_per_squad"])), int(c["min_squads"]), int(c["max_squads"])), "a big one: one per %d places (%d places)" % [int(c["places_per_squad"]), places])
	check(big.squad_cap() > small.squad_cap(), "more on the bigger map")


func test_both_sides_are_matched() -> void:
	var st := _state(400, 225)
	st.place_enemies()
	var field := st.squads.filter(func(s: Squad): return s.side == "enemy" and s.role not in ["leader", "base_guard"]).size()
	check_eq(field, st.squad_cap(), "the enemy fields as many squads as you may")


func test_a_cap_set_by_hand_still_rules() -> void:
	var st := _state(600, 400)
	st.settings["squad_cap"] = 5
	check_eq(st.squad_cap(), 5, "a number in the configurator wins over Auto")


## Your held buildings resist (round 16): the enemy takes held_resist times as long to take one.
func test_your_buildings_resist() -> void:
	var m := MapData.new(20, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 3
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 4)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 4)))
	var town := {"type": "town", "hex": m.index_of(Hex.from_offset(Vector2i(10, 4))), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false}
	m.buildings.append(town)
	var st := GameState.new(d, m, GameLog.new())
	st.debug_freeze_ai = true
	st.building_at(town["hex"])["owner"] = "player"
	st.add_squad("Them", town["hex"], [["Soldier", "front"]], "enemy")
	var plain := int(d.rules["capture"]["ticks"])
	for i in plain + 2:
		st.step()
	check_eq(st.building_at(town["hex"])["owner"], "player", "not taken in the time a neutral town takes")
	for i in roundi(plain * (float(d.rules["capture"]["held_resist"]) - 1.0)):
		st.step()
	check_eq(st.building_at(town["hex"])["owner"], "enemy", "taken at held_resist times as long")
