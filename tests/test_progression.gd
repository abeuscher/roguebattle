extends TestCase
## XP, levels, growth and promotion (SPEC §9.4, §12.2, §8.2).

var d := GameData.load_dir()
var rng := RandomNumberGenerator.new()
var names := NameBook.new(d)


func _unit(c: String, level := 1) -> Unit:
	var u := Unit.roll(d, c, rng, names)
	u.level = level
	u.talent = "ordinary"
	return u


func _squad(members: Array) -> Squad:
	var s := Squad.new(1, "S", -1)
	for u in members:
		s.add(d, u, "front")
	return s


func test_battle_xp() -> void:
	var leader := _unit("Knight")
	leader.charisma = 50
	var own := _squad([leader, _unit("Fighter")])
	var even := _squad([_unit("Knight"), _unit("Fighter")])
	check_eq(Progression.battle_xp(d, own, even, own.units[1]), 40, "40 × ratio 1 × (0.5 + 0.5) × 1")
	var strong := _squad([_unit("Knight", 4), _unit("Fighter", 4)])
	check_eq(Progression.battle_xp(d, own, strong, own.units[1]), 80, "a ratio of 4 is capped at 2")
	var weak := _squad([_unit("Serf")])
	for u in own.units:
		u.level = 4
	check_eq(Progression.battle_xp(d, own, weak, own.units[1]), 20, "a ratio of 1/4 is floored at 0.5")
	own.units[1].talent = "prodigy"
	check_eq(Progression.battle_xp(d, own, weak, own.units[1]), 25, "a prodigy earns +25%")


func test_level_cost() -> void:
	check_eq(Progression.level_cost(d, _unit("Fighter")), 100, "100 × XP rate 1")
	check_eq(Progression.level_cost(d, _unit("Dragon")), 125, "100 × XP rate 1.25")


func test_level_up() -> void:
	rng.seed = 3
	var u := _unit("Fighter")
	var before := u.stats.duplicate()
	var ups := Progression.gain_xp(d, u, 250, rng)
	check_eq(ups.size(), 2, "250 XP buys two levels")
	check_eq(u.level, 3, "level 3")
	check_eq(u.xp, 50, "50 XP carried over")
	check_eq(u.stats["STR"], before["STR"] + 2, "key stats +1 a level")
	check_eq(u.stats["AGI"], before["AGI"] + 2, "both key stats")
	check_eq(u.hp, u.max_hp(d), "HP rises with CON")


func test_every_stat_grows_within_three_levels() -> void:
	rng.seed = 11
	var u := _unit("Serf")
	for s in u.growth:
		u.growth[s] = 0.0  # no luck at all: only the guarantee
	var before := u.stats.duplicate()
	for i in 3:
		Progression.level_up(d, u, rng)
	for s in Unit.STATS:
		check(u.stats[s] > before[s], "%s grew within 3 levels" % s)
	for i in 2:
		Progression.level_up(d, u, rng)
	check_eq(u.stats["STR"], before["STR"] + 1, "but no more than the guarantee with 0% growth")


func test_promotion() -> void:
	var u := _unit("Fighter", 5)
	check(Progression.promotion_options(d, u).is_empty(), "a stage 2 unit promotes to stage 3 at level 6")
	u.level = 6
	var options := Progression.promotion_options(d, u)
	check("Soldier" in options and "Knight" in options, "the next classes on its lines: %s" % ", ".join(options))
	var before := u.stats.duplicate()
	var gains := Progression.promote(d, u, "Soldier")
	check_eq(u.unit_class, "Soldier", "promoted")
	check_eq(u.stats["PDEF"], before["PDEF"] + 12 - 6, "adds the base stat difference (PDEF 6 → 12)")
	check_eq(gains["CON"], 5, "CON 10 → 15")
	check(Progression.promotion_options(d, u).is_empty(), "stage 4 waits for level 9")
	var serf := _unit("Serf", 3)
	check(not Progression.promotion_options(d, serf).is_empty(), "a Serf promotes at level 3")


func test_alignment_branches() -> void:
	var witch := _unit("Witch", 9)
	witch.alignment = 80
	check_eq(Progression.promotion_options(d, witch), ["Fairy Godmother"] as Array[String], "a holy Witch can only become a Fairy Godmother")
	witch.alignment = 20
	check_eq(Progression.promotion_options(d, witch), ["Wicked Witch"] as Array[String], "an evil one a Wicked Witch")
	var dragon := _unit("Dragon", 9)
	dragon.alignment = 80
	var options := Progression.promotion_options(d, dragon)
	check("Silver Dragon" in options and "Red Dragon" in options and "Black Dragon" not in options, "a holy Dragon: Silver, or the any-alignment colors")
	var knight := _unit("Knight", 9)
	knight.alignment = 20
	check("Paladin" in Progression.promotion_options(d, knight), "lines without a branch ignore alignment")


func test_after_battle() -> void:
	var m := MapData.new(20, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 2
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 2)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 2)))
	var st := GameState.new(d, m, GameLog.new())
	st.setup_army()
	var ours := st.player_squads()[0]
	var dead := ours.units[1]
	dead.hp = 0
	var foe := st.add_squad("Them", m.index_of(Hex.from_offset(Vector2i(3, 2))), [["Knight", "front"]], "enemy")
	var b := st.start_battle(ours, foe, foe)
	ours.units[2].xp = Progression.level_cost(d, ours.units[2]) - 1
	var out := st.end_battle(b)
	check(dead not in out["xp"] and out["xp"].size() == ours.living().size(), "every living unit earns XP, the fallen don't")
	check_eq(ours.units[2].level, 2, "one was a point short of a level")
	check(out["level_ups"].any(func(l: String): return l.contains("reaches level 2")), "the result lists the level-up")


func test_promote_at_base() -> void:
	var m := MapData.new(20, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 2
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 2)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 2)))
	var st := GameState.new(d, m, GameLog.new())
	st.setup_army()
	var waiting: Squad = st.army.cells[1]
	var squire: Unit = waiting.units.filter(func(u: Unit): return u.unit_class == "Squire")[0]
	squire.level = 6
	var options := Progression.promotion_options(d, squire)
	check(not options.is_empty(), "a level 6 Squire can promote")
	check_eq(st.promote(squire, options[0]), "", "promote it at base")
	check_eq(squire.unit_class, options[0], "it's a %s now" % options[0])
	var field := st.player_squads()[0]
	field.hex = m.index_of(Hex.from_offset(Vector2i(8, 2)))
	field.units[1].level = 6
	check(st.promote(field.units[1], Progression.promotion_options(d, field.units[1])[0]) != "", "not out in the field")
