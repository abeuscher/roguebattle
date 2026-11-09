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
