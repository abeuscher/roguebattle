extends TestCase
## Morale, loyalty and bonds (SPEC §12.2).

var d := GameData.load_dir()


func _state(terrain_key := "plains") -> GameState:
	var m := MapData.new(12, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids[terrain_key]
	m.seed = 1
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Vector2i(0, 2))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(11, 2)))
	return GameState.new(d, m, GameLog.new())


func _out() -> Dictionary:
	return {"wiped": [false, false], "retreated": -1, "pushed": -1, "hp_lost": [0.0, 0.0]}


## Knight leans Holy, and a fresh GameState starts at midnight (not day): left alone,
## every test here would also trip the wrong-time-of-day trigger. Flattening alignment
## to neutral isolates whichever single trigger a test means to check.
func _neutral(s: Squad) -> void:
	for u in s.units:
		u.alignment = 50


# --- Morale ------------------------------------------------------------------------

func test_outnumbered_lowers_morale() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"], ["Fighter", "front"]], "enemy")
	_neutral(ours)
	_neutral(theirs)
	var b := st.start_battle(ours, theirs, theirs)
	st._update_morale(b, _out())
	check_eq(ours.morale, 50 + int(d.battle["morale"]["outnumbered"]), "the outnumbered side's morale falls")
	check_eq(theirs.morale, 50, "the other side isn't outnumbered: no change")


func test_leader_hit_lowers_morale() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	_neutral(ours)
	_neutral(theirs)
	var b := st.start_battle(ours, theirs, theirs)
	b.events.append({"type": "attack", "hit": true, "target": ours.leader})
	st._update_morale(b, _out())
	check_eq(ours.morale, 50 + int(d.battle["morale"]["leader_hit"]), "a hit on the leader lowers morale")


func test_a_death_lowers_morale() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"], ["Fighter", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	_neutral(ours)
	_neutral(theirs)
	var b := st.start_battle(ours, theirs, theirs)
	ours.units[1].hp = 0
	st._update_morale(b, _out())
	check_eq(ours.morale, 50 + int(d.battle["morale"]["unit_died"]), "losing a unit lowers morale")


func test_off_home_terrain_lowers_morale() -> void:
	var st := _state("swamp")
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])  # Knight: Plains native
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	_neutral(ours)
	_neutral(theirs)
	var b := st.start_battle(ours, theirs, theirs)
	st._update_morale(b, _out())
	check_eq(ours.morale, 50 + int(d.battle["morale"]["off_home_terrain"]), "fighting away from the leader's home terrain lowers morale")


func test_wrong_time_of_day_lowers_morale() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	for u in ours.units:
		u.alignment = 80  # holy
	var b := Battle.new(d, ours, theirs, "plains", false, RandomNumberGenerator.new())  # at night
	st._update_morale(b, _out())
	check_eq(ours.morale, 50 + int(d.battle["morale"]["wrong_time_of_day"]), "a holy squad fighting at night: wrong time")


func test_a_win_raises_morale() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	_neutral(ours)
	_neutral(theirs)
	var b := st.start_battle(ours, theirs, theirs)
	var out := _out()
	out["wiped"][1] = true
	st._update_morale(b, out)
	check_eq(ours.morale, 50 + int(d.battle["morale"]["win"]), "the winner's morale rises")


func test_several_triggers_combine_in_one_log_line() -> void:
	var st := _state("swamp")
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"], ["Fighter", "front"]], "enemy")
	_neutral(ours)
	_neutral(theirs)
	var b := st.start_battle(ours, theirs, theirs)
	st._update_morale(b, _out())
	var expect := 50 + int(d.battle["morale"]["outnumbered"]) + int(d.battle["morale"]["off_home_terrain"])
	check_eq(ours.morale, expect, "outnumbered and off home terrain both apply")


func test_morale_is_clamped() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	ours.morale = 2
	st.change_morale(ours, -100, "test")
	check_eq(ours.morale, 0, "never below 0")


func test_low_morale_deals_less_damage() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	var b := st.start_battle(ours, theirs, theirs)
	check_eq(b.morale_modifier(ours.units[0]), 1.0, "fine above the threshold")
	ours.morale = 29
	check_eq(b.morale_modifier(ours.units[0]), 1.0 - float(d.battle["morale"]["damage_penalty"]), "−10% below 30")


func test_liberating_raises_morale() -> void:
	var st := _state()
	var s := st.add_squad("Ours", 0, [["Knight", "front"]])
	var before := s.morale
	var b := {"type": "town", "hex": 0, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false, "owner": "enemy"}
	st._liberated(s, b)
	check_eq(s.morale, before + int(d.battle["morale"]["liberation"]), "liberating a building raises morale")


func test_resting_in_a_temple_raises_morale() -> void:
	var m := MapData.new(12, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 1
	m.settings = {"preset": "continent", "size": "small"}
	var hex := m.index_of(Vector2i(0, 2))
	m.player_base = hex
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(11, 2)))
	m.buildings.append({"type": "temple", "hex": hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())  # the building must exist before GameState indexes it
	var s := st.add_squad("Ours", hex, [["Knight", "front"]])
	s.units[0].hp -= 1
	var before := s.morale
	st._rest()
	check_eq(s.morale, before + int(d.battle["morale"]["temple_rest"]), "resting in a temple raises morale")


# --- Bonds -------------------------------------------------------------------------

func test_units_bond_after_enough_battles_together() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"], ["Fighter", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	var a := ours.units[0]
	var c := ours.units[1]
	for i in int(d.battle["bonds"]["battles_to_bond"]) - 1:
		var b := st.start_battle(ours, theirs, theirs)
		st._update_bonds(b)
	check(ours.bonded_partner(a) == null, "not yet bonded: one battle short")
	var last := st.start_battle(ours, theirs, theirs)
	st._update_bonds(last)
	check_eq(ours.bonded_partner(a), c, "bonded after enough battles together")
	check_eq(ours.bonded_partner(c), a, "symmetric")


func test_bonded_pair_fights_better_while_both_live() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"], ["Fighter", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	var a := ours.units[0]
	var c := ours.units[1]
	var b := Battle.new(d, ours, theirs, "plains", false, RandomNumberGenerator.new())  # night: no Holy Vow day bonus to muddy the math
	check_eq(b._dealt_multiplier(a, theirs.units[0], "Melee"), 1.0, "no bond yet")
	ours.bonded_pairs.append([a, c])
	check_eq(b._dealt_multiplier(a, theirs.units[0], "Melee"), 1.0 + float(d.battle["bonds"]["damage"]), "+5% damage, bonded and alive")
	c.hp = 0
	check_eq(b._dealt_multiplier(a, theirs.units[0], "Melee"), 1.0, "no bonus once the partner is dead")


# --- Loyalty -----------------------------------------------------------------------

func test_a_successful_recruit_is_marked_and_starts_at_the_default_loyalty() -> void:
	var st := _state()
	var player := st.add_squad("Ours", 0, [["Knight", "front"]])
	var neutral := st.add_squad("Wolves", 1, [["Wolf", "front"]], "neutral")
	for u in player.units + neutral.units:
		u.alignment = 50
	st.reputation = 100
	st.tech = ["diplomacy", "tamers"]
	neutral.units[0].unit_class = "Wolf"
	st.pending_recruit = {"player": player, "neutral": neutral, "defender": neutral}
	st.resolve_recruit(true)
	check(st.army.pool[0].recruited, "marked as recruited")
	check_eq(st.army.pool[0].loyalty, int(d.rules["starting_loyalty"]), "starts at the default loyalty")


func test_loyalty_falls_unused_and_rises_with_high_reputation() -> void:
	var st := _state()
	var u := Unit.new()
	u.unit_class = "Wolf"
	u.name = "Wolf"
	u.hp = 1
	u.recruited = true
	u.loyalty = 50
	st.army.pool.append(u)
	st.reputation = 50
	st._loyalty_day()
	check_eq(u.loyalty, 50 + int(d.rules["loyalty"]["unused"]), "unused in the pool: loyalty falls")
	u.loyalty = 50
	st.reputation = int(d.rules["loyalty"]["high_reputation"])
	st._loyalty_day()
	check_eq(u.loyalty, 50 + int(d.rules["loyalty"]["unused"]) + int(d.rules["loyalty"]["high_reputation_gain"]), "both apply at once")


func test_a_non_recruited_unit_never_gets_a_loyalty_tick() -> void:
	var st := _state()
	var s := st.add_squad("Ours", 0, [["Knight", "front"]])
	st.army.cells[0] = s  # army.units() (what _loyalty_day scans) only sees the roster, not the map
	s.units[0].loyalty = 50
	st.reputation = 100
	st._loyalty_day()
	check_eq(s.units[0].loyalty, 50, "not recruited: untouched")


func test_very_low_loyalty_warns_for_a_day_before_leaving() -> void:
	var st := _state()
	var u := Unit.new()
	u.unit_class = "Wolf"
	u.name = "Wolf"
	u.hp = 1
	u.recruited = true
	u.loyalty = int(d.rules["loyalty"]["very_low"]) - 1
	st.army.pool.append(u)
	st._loyalty_day()
	check(u.loyalty_warned, "a day's warning first")
	check(u in st.army.pool, "not removed yet")
	var left := false
	for i in 50:  # leave_chance isn't certain: keep rolling until it happens
		u.loyalty_warned = true
		u.loyalty = int(d.rules["loyalty"]["very_low"]) - 1
		st._loyalty_day()
		if u not in st.army.pool:
			left = true
			break
	check(left, "eventually leaves once warned and still very low")


func test_loyalty_recovering_clears_the_warning() -> void:
	var st := _state()
	var s := st.add_squad("Ours", 0, [["Knight", "front"], ["Wolf", "front"]])
	st.army.cells[0] = s  # army.units() (what _loyalty_day scans) only sees the roster, not the map
	var u := s.units[1]  # in a squad, not the pool: no "unused" penalty to undo the recovery
	u.recruited = true
	u.loyalty_warned = true
	u.loyalty = int(d.rules["loyalty"]["very_low"])
	st._loyalty_day()
	check(not u.loyalty_warned, "recovered: the warning clears")


func test_winning_a_battle_raises_a_recruited_units_loyalty() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"], ["Wolf", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]], "enemy")
	ours.units[1].recruited = true
	ours.units[1].loyalty = 50
	var b := st.start_battle(ours, theirs, theirs)
	var out := _out()
	out["wiped"][1] = true
	st._update_loyalty_wins(b, out)
	check_eq(ours.units[1].loyalty, 50 + int(d.rules["loyalty"]["win"]), "a win raises a recruited unit's loyalty")
