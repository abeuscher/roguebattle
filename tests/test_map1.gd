extends TestCase
## Map 1 setup: 6 Serf-line squads, terrain coverage and the soft rule, over many
## seeds; the Opinion Leader's squad and the starting state (SPEC §18).

var d := GameData.load_dir()
const SEEDS := 50


func _serf_classes() -> Array:
	var out := []
	for lid in d.lines.keys():
		if not lid.is_valid_int():
			continue
		for stage in d.lines[lid]:
			for c in stage:
				if c not in out:
					out.append(c)
	return out


func _is_front_line(class_name_: String) -> bool:
	return d.role_templates[d.units[class_name_]["role"]]["primary_row"] == "front"


func _is_healer_or_support(class_name_: String) -> bool:
	var role: String = d.units[class_name_]["role"]
	return role == "Support" or role.to_lower().contains("healer")


func test_six_squads_of_a_leader_and_four_stage_two_units() -> void:
	var serf := _serf_classes()
	var rng := RandomNumberGenerator.new()
	for seed_ in SEEDS:
		rng.seed = seed_
		var squads := Map1Setup.build(d, rng)
		check_eq(squads.size(), 6, "6 squads (seed %d)" % seed_)
		for s in squads:
			check_eq(s.size(), 5, "a leader plus four stage 2 units (seed %d)" % seed_)
			check_eq(int(d.units[s[0][0]]["stage"]), 3, "the first is a stage 3 leader (seed %d)" % seed_)
			check(d.units[s[0][0]]["can_lead"], "%s can actually lead (seed %d)" % [s[0][0], seed_])
			for m in s.slice(1):
				check_eq(int(d.units[m[0]]["stage"]), 2, "the rest are stage 2 (seed %d)" % seed_)
			for m in s:
				check(m[0] in serf, "%s is rolled from a Serf line (seed %d)" % [m[0], seed_])


## Checked against each leader's native terrain: see Map1Setup and DECISIONS.md
## for why the squad's actual (voted) travel type can't be used here.
func test_terrain_coverage() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_ in SEEDS:
		rng.seed = seed_
		var squads := Map1Setup.build(d, rng)
		var terrains := {}
		for s in squads:
			terrains[d.units[s[0][0]]["terrain"]] = true
		for t in Map1Setup.TERRAINS:
			check(terrains.has(t), "seed %d: no squad's leader is native to %s" % [seed_, t])


func test_soft_rule_front_line_and_healer_or_support() -> void:
	var rng := RandomNumberGenerator.new()
	for seed_ in SEEDS:
		rng.seed = seed_
		var squads := Map1Setup.build(d, rng)
		for s in squads:
			var front: bool = s.any(func(m): return _is_front_line(m[0]))
			var healer: bool = s.any(func(m): return _is_healer_or_support(m[0]))
			check(front, "seed %d: %s has no front-line unit" % [seed_, s[0][0]])
			check(healer, "seed %d: %s has no healer or support unit" % [seed_, s[0][0]])


func _state(seed_: int) -> GameState:
	var m := MapData.new(10, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = seed_
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 2)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(8, 2)))
	var st := GameState.new(d, m, GameLog.new())
	st.setup_army()
	return st


func test_opinion_leader_squad_starts_alone_on_the_map() -> void:
	for seed_ in range(30):
		var st := _state(seed_)
		check_eq(st.army.squads().size(), 6, "6 squads in the army (seed %d)" % seed_)
		check_eq(st.player_squads().size(), 1, "only one squad starts on the map (seed %d)" % seed_)
		check_eq(st.player_squads()[0], st.opinion_leader_squad(), "it's the Opinion Leader's squad (seed %d)" % seed_)
		check_eq(st.opinion_leader_squad().hex, st.map.player_base, "at the Player Base (seed %d)" % seed_)
		for s in st.army.squads():
			check(s.leader != null, "%s has a leader (seed %d)" % [s.name, seed_])


func test_starting_state() -> void:
	var st := _state(1)
	check_eq(st.gold, 500, "500 gold")
	check_eq(st.tech_points, 3, "3 tech points")
	check_eq(st.cards.size(), 3, "3 random cards")


## The --wide-roster developer override (Battlemap._wide_roster_count()): not part
## of the real game, just a playtesting aid for exercising more of the roster.
func test_wide_roster_is_debug_only_variety() -> void:
	var serf := _serf_classes()
	var rng := RandomNumberGenerator.new()
	for seed_ in SEEDS:
		rng.seed = seed_
		var squads: Array = Map1Setup.build_wide_roster(d, rng, 16)
		check_eq(squads.size(), 16, "16 squads (seed %d)" % seed_)
		var leaders := {}
		var terrains := {}
		for s in squads:
			check_eq(s.size(), 5, "a leader plus four stage 2 units (seed %d)" % seed_)
			check(d.units[s[0][0]]["can_lead"], "%s can actually lead (seed %d)" % [s[0][0], seed_])
			for m in s:
				check(m[0] in serf, "%s is rolled from a Serf line (seed %d)" % [m[0], seed_])
			leaders[s[0][0]] = true
			terrains[d.units[s[0][0]]["terrain"]] = true
		check_eq(leaders.size(), 16, "16 distinct leaders (seed %d)" % seed_)
		for t in Map1Setup.TERRAINS:
			check(terrains.has(t), "seed %d: no squad's leader is native to %s" % [seed_, t])


## The debug panel's Wide roster button (GameState.reroll_wide_roster()): swaps
## the whole army, keeps progress, and still leaves one squad on the map.
func test_reroll_wide_roster_replaces_the_army() -> void:
	var st := _state(1)
	var old_squad := st.player_squads()[0]
	var gold := st.gold
	var cards := st.cards.size()
	st.reroll_wide_roster(16)
	check_eq(st.army.squads().size(), 16, "16 squads after the reroll")
	check_eq(st.player_squads().size(), 1, "still only one squad on the map")
	check(old_squad not in st.army.squads(), "the old squad is gone")
	check_eq(st.player_squads()[0].hex, st.map.player_base, "the new one is at the Player Base")
	check_eq(st.gold, gold, "gold is untouched")
	check_eq(st.cards.size(), cards, "cards are untouched")


## Every generated squad (player, enemy, neutral) starts with its rows evened out:
## neither row more than one unit over half (5 units 3:2 or 2:3, never 4:1). User's
## playtest note, see DECISIONS.md session 030.
func test_generated_squads_have_balanced_rows() -> void:
	for seed_ in [3, 11, 27]:
		var m := MapGen.generate(d, seed_, {"width": 160, "height": 90})
		var st := GameState.new(d, m, GameLog.new())
		st.setup_army()
		st.place_enemies()
		st.place_neutrals()
		var all: Array = st.army.squads() + st.squads.filter(func(s: Squad): return s.side != "player")
		check(all.size() > 6, "enemies and neutrals placed too (seed %d)" % seed_)
		for s: Squad in all:
			var f := s.row("front").size()
			var b := s.row("back").size()
			check(absi(f - b) <= 1, "%s (%s) rows %d:%d (seed %d)" % [s.name, s.side, f, b, seed_])
			for which in ["front", "back"]:
				for i in s.row(which).size():
					check(s.at(which, i) != null, "%s %s positions run 0..n-1 (seed %d)" % [s.name, which, seed_])


# --- Single map mode (user's design, 2026-11-10) -------------------------------------

func _single(seed_: int) -> GameState:
	var m := MapData.new(10, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = seed_
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 2)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(8, 2)))
	var st := GameState.new(d, m, GameLog.new(), {"mode": "single", "xp_rate": 150})
	st.setup_army()
	return st


func test_single_map_starts_with_the_opinion_leader_alone_and_a_pool() -> void:
	var cfg: Dictionary = d.rules["single_map"]["pool"]
	for seed_ in range(SEEDS):
		var st := _single(seed_)
		check_eq(st.army.squads().size(), 1, "one squad in the army (seed %d)" % seed_)
		var s := st.opinion_leader_squad()
		check(s != null and s.units.size() == 1 and s.leader == st.opinion_leader, "the Opinion Leader alone in it (seed %d)" % seed_)
		check(s in st.player_squads() and s.hex == st.map.player_base, "on the map at the Player Base (seed %d)" % seed_)
		check_eq(s.capacity(d), 6, "6 slots (seed %d)" % seed_)
		check_eq(st.army.pool.size() + 1, 30, "30 units in all (seed %d)" % seed_)
		var count := func(f: Callable) -> int: return st.army.pool.filter(f).size()
		var leaders: Array = st.army.pool.filter(func(u: Unit): return u.info(d)["can_lead"]).map(func(u: Unit): return u.unit_class)
		check_eq(leaders.size() + 1, int(cfg["leaders"]), "4 leaders (seed %d)" % seed_)
		var terrains := {st.opinion_leader.info(d)["terrain"]: true}
		for c in leaders:
			terrains[d.units[c]["terrain"]] = true
		check_eq(terrains.size(), int(cfg["leaders"]), "on 4 different terrains (seed %d)" % seed_)
		check_eq(count.call(func(u: Unit): return int(u.info(d)["stage"]) == 2), int(cfg["stage2"]), "13 stage 2 units (seed %d)" % seed_)
		check_eq(count.call(func(u: Unit): return u.unit_class == "Serf"), int(cfg["serfs"]), "10 Serfs (seed %d)" % seed_)
		var large: Array = st.army.pool.filter(func(u: Unit): return u.info(d)["size"] == "Large").map(func(u: Unit): return u.unit_class)
		check_eq(large.size(), int(cfg["large"]), "3 Large units (seed %d)" % seed_)
		for c in large:
			check(int(d.units[c]["stage"]) == 1 and d.units[c]["terrain"] != "Water" and large.count(c) == 1, "%s: stage 1, not a sea creature, no repeats (seed %d)" % [c, seed_])
		check(count.call(func(u: Unit): return int(u.info(d)["stage"]) == 2 and _is_front_line(u.unit_class)) >= int(cfg["front_min"]), "enough front-line units (seed %d)" % seed_)
		check(count.call(func(u: Unit): return int(u.info(d)["stage"]) == 2 and _is_healer_or_support(u.unit_class)) >= int(cfg["healer_min"]), "enough healers or support (seed %d)" % seed_)


func test_single_map_squads_hold_six_and_start_with_a_leader() -> void:
	var st := _single(3)
	var serfs := st.army.pool.filter(func(u: Unit): return u.unit_class == "Serf")
	for i in 5:
		check(st.army.move(serfs[i], 0), "Serf %d joins squad 1" % (i + 1))
	check(not st.army.move(serfs[5], 0), "a seventh unit doesn't fit")
	check(not st.army.move(serfs[5], 1), "a Serf can't start a squad")
	var leader: Unit = st.army.pool.filter(func(u: Unit): return u.info(d)["can_lead"])[0]
	check(st.army.move(leader, 1), "a leader can")
	check_eq(st.army.cells[1].capacity(d), 6, "it has 6 slots too")
	check(st.army.move(serfs[5], 1), "then the Serf joins it")
	check_eq(st.army.cells[1].leader, leader, "under the leader")
	check_eq(st.deploy_blocker(st.army.cells[1]), "", "and it can deploy")


func test_the_opinion_leader_is_followed_wherever_they_go() -> void:
	var st := _single(4)
	st.settings["defeat_leader"] = true
	var ol := st.opinion_leader
	var leader: Unit = st.army.pool.filter(func(u: Unit): return u.info(d)["can_lead"])[0]
	check(st.army.move(leader, 2), "another leader forms squad 3")
	check(st.army.move(ol, 2), "the Opinion Leader moves into squad 3")
	check_eq(st.opinion_leader_squad(), st.army.cells[2], "their squad is now squad 3")
	st._check_game_over()
	check_eq(st.game_over, "", "squad 1 emptying doesn't lose the map")
	check(st.army.move(ol, -1), "into the pool")
	check(st.opinion_leader_squad() == null, "no squad while waiting in the pool")
	st._check_game_over()
	check_eq(st.game_over, "", "still not lost")
	ol.hp = 0
	st._check_game_over()
	check_eq(st.game_over, "defeat", "only the Opinion Leader's death loses the map")


func test_xp_rate_scales_battle_xp_in_single_map_mode_only() -> void:
	var st := _single(5)
	var s := st.opinion_leader_squad()
	var foe := st.add_squad("Them", st.map.enemy_base, [[st.opinion_leader.unit_class, "front"]], "enemy")
	var base := Progression.battle_xp(d, s, foe, st.opinion_leader)
	check_eq(st.battle_xp(s, foe, st.opinion_leader), roundi(base * 1.5), "1.5x at 150%")
	st.settings["xp_rate"] = 300
	check_eq(st.battle_xp(s, foe, st.opinion_leader), base * 3, "3x at 300%")
	st.settings["mode"] = "campaign"
	check_eq(st.battle_xp(s, foe, st.opinion_leader), base, "the campaign start ignores it")
