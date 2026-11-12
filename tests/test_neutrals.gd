extends TestCase
## Neutral squads (SPEC §6.7, §16): a lair rolls a race line native to its home
## terrain, scaled by danger; roamers patrol around their lair and fight anyone,
## player or enemy, that comes close; meeting the player offers Recruit or Fight.

var d := GameData.load_dir()


## A plains strip map with the player base on the left and the enemy base on the right.
func _state(w := 20, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 9
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _squad(st: GameState, col: int, row: int, side: String, count := 1) -> Squad:
	var members := []
	for i in count:
		members.append(["Knight", "front"])
	var s := st.add_squad(side.capitalize(), _at(st.map, col, row), members, side)
	if side == "neutral":
		s.role = "roamer"
	return s


func test_rolls_a_race_line_native_to_the_home_terrain() -> void:
	var names := NameBook.new(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	var units := NeutralSquads.roll(d, "Mountain", 0.3, rng, names)
	check(not units.is_empty(), "a Mountain lair rolls at least one unit")
	for u in units:
		check_eq(u.unit_class, units[0].unit_class, "all one class")
		check_eq(d.units[u.unit_class]["terrain"], "Mountain", "native to the lair's home terrain")
		check(d.units[u.unit_class]["lines"].any(func(l): return not l.is_valid_int()), "a race line class, not a Serf line")


func test_no_matching_line_rolls_nothing() -> void:
	var names := NameBook.new(d)
	var rng := RandomNumberGenerator.new()
	rng.seed = 1
	check(NeutralSquads.roll(d, "Nowhere", 0.5, rng, names).is_empty(), "an unknown home terrain rolls no one")


func test_danger_raises_stage_and_level() -> void:
	var names := NameBook.new(d)
	var low_rng := RandomNumberGenerator.new()
	low_rng.seed = 7
	var low := NeutralSquads.roll(d, "Mountain", 0.0, low_rng, names)
	var high_rng := RandomNumberGenerator.new()
	high_rng.seed = 7
	var high := NeutralSquads.roll(d, "Mountain", 1.0, high_rng, names)
	check(int(d.units[low[0].unit_class]["stage"]) <= int(d.units[high[0].unit_class]["stage"]), "more danger: the same stage or later")
	check(low[0].level <= high[0].level, "more danger: the same level or higher")


func test_place_neutrals_fills_every_lair() -> void:
	var m := MapGen.generate(d, 11, {"size": "small"})
	var st := GameState.new(d, m, GameLog.new())
	st.place_neutrals()
	var roamers := st.squads.filter(func(s: Squad): return s.side == "neutral" and s.role != "guard")  # lair-site guards come on top (session 050)
	check_eq(roamers.size(), m.lairs.size(), "one roamer squad per lair (every lair terrain has a native line)")
	var guards := st.squads.filter(func(s: Squad): return s.role == "guard")
	check_eq(guards.size(), m.buildings.filter(func(b): return b["hidden"] and b["kind"] == "lair").size(), "a guard per lair site")
	for s in roamers:
		check_eq(s.role, "roamer", "")
		check(s.lair_hex >= 0, "knows its lair")
		check(s.units.size() > 0 and s.units.size() <= 9, "1-9 units, slots permitting")


func test_hostile_fights_every_other_side() -> void:
	var st := _state()
	var p := _squad(st, 5, 4, "player")
	var e := _squad(st, 5, 4, "enemy")
	var n := _squad(st, 5, 4, "neutral")
	check(st.hostile(p, e), "player against enemy")
	check(st.hostile(p, n), "player against neutral")
	check(st.hostile(e, n), "enemy against neutral (§6.7: neutrals fight both sides)")
	check(not st.hostile(p, _squad(st, 6, 4, "player")), "player against player: never")
	check(not st.hostile(n, _squad(st, 6, 4, "neutral")), "neutral against neutral: never")


func test_meeting_a_neutral_offers_recruit_or_fight() -> void:
	var st := _state()
	var p := _squad(st, 5, 4, "player")
	var n := _squad(st, 6, 4, "neutral")
	st._check_contact()
	check(st.pending == null, "no battle yet")
	check(not st.pending_recruit.is_empty(), "a recruit encounter instead")
	check_eq(st.recruit_class(), n.units[0].unit_class, "shows the class, not the count")


func test_fight_skips_straight_to_a_battle() -> void:
	var st := _state()
	var p := _squad(st, 5, 4, "player")
	var n := _squad(st, 6, 4, "neutral")
	st.pending_recruit = {"player": p, "neutral": n, "defender": n}
	st.resolve_recruit(false)
	check(st.pending_recruit.is_empty(), "the encounter is resolved")
	check(st.pending != null, "straight into a battle")
	var out := st.resolve_pending()
	var won := GameState.battle_result(out) == "won"
	if won and not n.living().is_empty():  # beaten: one more chance to recruit them (round 9)
		check(st.pending_recruit.get("beaten", false), "beaten, they can be asked once more")
		st.resolve_recruit(false)
	check(n not in st.squads, "met once: the neutrals leave after the fight, whoever won")
	var text: String = out["text"]
	check(text.begins_with(p.name + (" wins." if won else " loses.")), "party wins or loses: " + text)
	check(text.contains("are beaten back" if won else "are victorious") and text.ends_with("return to the plains."),
			"the neutrals go back to their ground: " + text)


func test_battle_result_words() -> void:
	var base := {"wiped": [false, false], "retreated": -1, "hp_lost": [0.2, 0.5]}
	check_eq(GameState.battle_result(base), "won", "the enemy lost more")
	base["hp_lost"] = [0.6, 0.5]
	check_eq(GameState.battle_result(base), "lost", "we lost more")
	base["wiped"] = [false, true]
	check_eq(GameState.battle_result(base), "won", "wiping them out wins whatever the HP")
	base["wiped"] = [false, false]
	base["retreated"] = 0
	check_eq(GameState.battle_result(base), "retreated", "we retreated")
	base["retreated"] = -1
	base["hp_lost"] = [0.3, 0.3]
	check_eq(GameState.battle_result(base), "even", "level")


func test_recruit_failure_resists_and_fights_first() -> void:
	var st := _state()
	var p := _squad(st, 5, 4, "player")
	var n := _squad(st, 6, 4, "neutral")
	for u in p.units:
		u.alignment = 0
	for u in n.units:
		u.alignment = 100  # a full alignment gap: recruit_chance is exactly 0 (§16)
	st.pending_recruit = {"player": p, "neutral": n, "defender": n}
	var result := st.resolve_recruit(true)
	check(not result["joined"], "they refuse")
	check(String(result["text"]).contains("refuse") and String(result["text"]).contains("ideals"), "the result says why: " + String(result["text"]))
	check(st.pending_recruit.is_empty(), "the encounter is resolved")
	check(st.pending != null, "resisted, so it fights")
	check_eq(st.pending.first_side, 1, "the neutrals take their whole first round (§16)")
	st.resolve_pending()
	check(n not in st.squads, "and then they're gone")


func test_recruit_success_joins_the_pool() -> void:
	var st := _state()
	var p := _squad(st, 5, 4, "player")
	var n := _squad(st, 6, 4, "neutral")
	for u in p.units + n.units:
		u.alignment = 50  # no gap: recruit_chance is as high as it gets
	st.reputation = 100
	st.tech = ["diplomacy", "tamers"]  # with a Large neutral, pushes the chance over 1.0: a sure thing
	n.units[0].unit_class = "Wolf"  # Mountain, Large (size matters for the Tamers bonus)
	check(is_equal_approx(st.recruit_chance(p, n.living().size(), n.alignment(), true), 1.0), "chance is clamped to a sure thing")
	var before := st.army.pool.size()
	var leader_charisma := p.leader.charisma
	st.pending_recruit = {"player": p, "neutral": n, "defender": n}
	var result := st.resolve_recruit(true)
	check(result["joined"] and String(result["text"]).contains("join"), "the result says they joined")
	check(st.pending_recruit.is_empty() and st.pending == null, "no battle: it joined")
	check_eq(st.army.pool.size(), before + n.units.size(), "the neutrals join the recruit pool")
	check_eq(p.leader.charisma, leader_charisma + 3, "the leader gains charisma")
	check(n not in st.squads, "the neutral squad leaves the map")


func test_roamer_chases_a_hostile_within_its_patrol_radius() -> void:
	var st := _state()
	var lair := _at(st.map, 10, 4)
	var n := _squad(st, 10, 4, "neutral", 3)
	n.lair_hex = lair
	var prey := _squad(st, 12, 4, "enemy")
	var contacted := false
	for i in 300:
		st.step()
		if Hex.distance(st.map.hex_at(n.hex), st.map.hex_at(prey.hex)) <= 1:
			contacted = true
			break
	check(contacted, "the roamer catches the enemy inside its radius")


func test_roamer_wanders_within_its_patrol_radius_when_nothing_is_near() -> void:
	var st := _state()
	var lair := _at(st.map, 10, 4)
	var n := _squad(st, 10, 4, "neutral", 3)
	n.lair_hex = lair
	var radius := int(d.neutrals["patrol_radius"])
	for i in 500:
		st.step()
		check(Hex.distance(st.map.hex_at(n.hex), st.map.hex_at(lair)) <= radius, "never strays past the patrol radius")
