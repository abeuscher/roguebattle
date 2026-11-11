extends TestCase
## Statuses, traits, Raise dead, retreat, outcomes, threat (SPEC §9.7, §11.3–11.7, §12.4).

var d := _formula_data()


func _unit(class_name_: String, row := "front", name := "") -> Unit:
	var u := Unit.new()
	u.unit_class = class_name_
	u.name = name if name != "" else class_name_
	for s in Unit.STATS:
		u.stats[s] = int(d.units[class_name_]["base_stats"][s])
	u.hp = u.max_hp(d)
	u.row = row
	return u


func _squad(units: Array, name := "S") -> Squad:
	var s := Squad.new(1, name, 0)
	for u in units:
		s.units.append(u)
		if s.leader == null and u.info(d)["can_lead"]:
			s.leader = u
	s.refresh(d)
	return s


func _battle(a: Array, b: Array, terrain := "plains", seed := 1) -> Battle:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Battle.new(d, _squad(a, "Ours"), _squad(b, "Theirs"), terrain, true, rng)


# --- Statuses -----------------------------------------------------------------------

func test_poison_burn_regen() -> void:
	var k := _unit("Knight")
	var b := _battle([k], [_unit("Fighter")])
	b.add_status(k, "poison")
	var hp := k.hp
	b._tick_statuses(k)
	check_eq(k.hp, hp - roundi(k.max_hp(d) * 0.05), "poison: -5% max HP per turn")
	b.cleanse(k)
	check(not b.has_status(k, "poison"), "cleanse removes harmful statuses")
	b.add_status(k, "regen")
	hp = k.hp
	b._tick_statuses(k)
	check_eq(k.hp, hp + roundi(k.max_hp(d) * 0.05), "regen: +5% per turn")
	b.cleanse(k)
	check(b.has_status(k, "regen"), "cleanse keeps helpful statuses")
	var f := _unit("Fighter")
	f.stats["STR"] = 40
	var dmg := b.expected_damage(f, k, "Melee")
	b._status[f] = {}
	b.add_status(f, "burn")
	check_eq(b.expected_damage(f, k, "Melee"), maxf(1.0, f.stats["STR"] * 1.15 * 0.9 - k.stats["PDEF"]), "burn: -10% physical damage")
	check(b.expected_damage(f, k, "Melee") < dmg, "burned hits are weaker")


func test_resistance() -> void:
	var troll := _unit("Trollboy")  # snow native
	var b := _battle([troll], [_unit("Fighter")])
	check(not b.add_status(troll, "freeze"), "snow natives ignore Freeze")
	check(b.add_status(troll, "burn"), "but not Burn")


func test_speed_statuses() -> void:
	var a := _unit("Fighter", "front", "A")
	var z := _unit("Fighter", "front", "Z")
	a.stats["SPD"] = 10
	z.stats["SPD"] = 8
	var b := _battle([a], [z])
	check_eq(b.turn_order()[0], a, "faster first")
	b.add_status(a, "freeze")
	check_eq(b.stat(a, "SPD"), 5.0, "freeze halves speed")
	check_eq(b.turn_order()[0], z, "frozen unit acts later")
	b.add_status(z, "haste")
	check_eq(b.stat(z, "SPD"), 12.0, "haste +50%")


func test_skip_statuses() -> void:
	var a := _unit("Fighter", "front", "A")
	var z := _unit("Knight", "front", "Z")
	z.hp = 100000
	var b := _battle([a], [z])
	b.add_status(a, "petrify")
	b._turn(a)
	check_eq(b.events[-1]["type"], "wait", "petrified units can't act")
	var hurt := _unit("Knight", "front", "Hurt")
	var healer := _unit("Acolyte", "back")
	var c := _battle([hurt, healer], [_unit("Fighter")])
	hurt.hp = 10
	c.add_status(hurt, "petrify")
	c._heal(healer, 0)
	check_eq(hurt.hp, 10, "petrified units can't be healed")
	var brute := _unit("Fighter")
	brute.stats["STR"] = 40
	check_eq(c.expected_damage(brute, hurt, "Melee"), (40 * 1.15 - hurt.stats["PDEF"]) * 0.5, "petrified units take half damage")
	var s := _battle([_unit("Knight", "front", "S")], [_unit("Fighter", "front", "F")], "plains", 3)
	var sleeper := s.sides[0].units[0]
	s.add_status(sleeper, "sleep")
	s._turn(sleeper)
	check_eq(s.events[-1]["type"], "wait", "sleepers skip turns")
	var hitter := s.sides[1].units[0]
	s._misses[hitter] = 3  # the streak breaker makes the next attack hit
	s._attack(hitter, "Melee", sleeper)
	check(not s.has_status(sleeper, "sleep"), "a hit wakes the sleeper")


func test_blind_silence_fear_weak_protect() -> void:
	var a := _unit("Fighter")
	var t := _unit("Fighter")
	var b := _battle([a], [t])
	b.add_status(a, "blind")
	check_eq(b.hit_chance(a, t), 55.0, "blind: -30% hit")
	var mage := _unit("Apprentice")
	var c := _battle([mage], [_unit("Knight")])
	c.add_status(mage, "silence")
	c._turn(mage)
	check(c.events[-1]["type"] == "wait" and c.events[-1]["text"].contains("cancelled"), "silence stops magic")
	var f := _unit("Fighter")  # two attacks in the front row
	var e := _battle([f], [_unit("Knight")])
	e.add_status(f, "fear")
	check_eq(e._attacks[f], 1, "fear: one fewer attack")
	var k := _unit("Knight")
	var w := _battle([_unit("Fighter")], [k])
	var base := w.expected_damage(w.sides[0].units[0], k, "Melee")
	w.add_status(k, "weak_physical")
	check_eq(w.expected_damage(w.sides[0].units[0], k, "Melee"), base * 1.25, "weak: +25% physical damage taken")
	var p := _battle([_unit("Fighter")], [_unit("Knight")])
	var pk := p.sides[1].units[0]
	p.add_status(pk, "protect")
	check_eq(p.stat(pk, "PDEF"), pk.stats["PDEF"] * 1.2, "protect: +20% PDEF")


func test_shock_loses_attacks() -> void:
	var lost := 0
	for seed in 400:
		var a := _unit("Fighter")
		var b := _battle([a], [_unit("Knight")], "plains", seed)
		b.add_status(a, "shock")
		b._turn(a)
		if b.events[-1]["text"].contains("shock"):
			lost += 1
	check(absf(lost / 400.0 - 0.3) < 0.06, "shock loses about 30%% of attacks (%d)" % lost)


func test_charm() -> void:
	var a := _unit("Fighter", "front", "Charmed")
	var friend := _unit("Knight", "front", "Friend")
	friend.hp = 100000
	var b := _battle([a, friend], [_unit("Knight", "front", "Foe")])
	b.add_status(a, "charm")
	b._misses[a] = 3
	b._turn(a)
	check_eq(b.events[-1]["target"], friend, "a charmed unit attacks its own squad")
	check(not b.has_status(a, "charm"), "charm lasts one turn")


func test_buff_lasts_until_buffers_next_turn() -> void:
	var faerie := _unit("Faerie", "back")
	var k := _unit("Knight")
	var b := _battle([k, faerie], [_unit("Fighter")])
	b._turn(faerie)
	check(b.has_status(k, "mdef_up"), "the faerie raises the squad's MDEF")
	check_eq(b.stat(k, "MDEF"), k.stats["MDEF"] * 1.1, "by 10%")
	b._end_buffs_from(faerie)
	check(not b.has_status(k, "mdef_up"), "it ends at the faerie's next turn")
	var ench := _unit("Enchantress", "back")
	var foe := _unit("Knight")
	var c := _battle([ench], [foe])
	c._misses[ench] = 3
	c._turn(ench)
	check(c.has_status(foe, "str_down"), "the enchantress lowers STR")


func test_statuses_clear_at_end() -> void:
	var k := _unit("Knight")
	var b := _battle([k], [_unit("Fighter")])
	b.add_status(k, "poison")
	b.finish()
	check(not b.has_status(k, "poison"), "every status clears after the battle")


func test_on_hit_status() -> void:
	var ice := ""
	for c in d.units:
		if d.units[c]["element"] == "Ice" and ice == "":
			ice = c
	var b := _battle([_unit(ice)], [_unit("Knight")])
	check_eq(b.on_hit_status(b.sides[0].units[0]), "freeze", "ice casters freeze")
	check_eq(b.on_hit_status(b.sides[0].units[0], "Melee"), "", "only Magic and Breath carry the element")


# --- Traits and Raise dead ------------------------------------------------------------

func test_first_strike() -> void:
	var ronin := _unit("Ronin", "front", "R")
	var fast := _unit("Fighter", "front", "F")
	ronin.stats["SPD"] = 1
	fast.stats["SPD"] = 20
	var b := _battle([ronin], [fast])
	check_eq(b.turn_order(true)[0], ronin, "First strike acts first in round 1")
	check_eq(b.turn_order(false)[0], fast, "only in round 1")


func test_raise_dead() -> void:
	var n := _unit("Necromancer", "back")
	var b := _battle([n], [_unit("Knight")])
	b._turn(n)
	var sk := b.sides[0].units[-1]
	check_eq(sk.name, "Skeleton", "a Skeleton fills the empty slot")
	check_eq(b.element(sk), "Dark", "dark element")
	var bonus := 0
	for s in Unit.STATS:
		bonus += sk.stats[s] - int(d.units["Serf"]["base_stats"][s])
	check(bonus >= 3 and bonus <= 12, "three stats gain 1d4 (%d)" % bonus)
	var count := b.sides[0].units.size()
	b._turn(n)
	check_eq(b.sides[0].units.size(), count, "once per battle")
	b.finish()
	check(sk not in b.sides[0].units, "removed after the battle")


# --- Steps, retreat, outcomes ------------------------------------------------------------

func test_steps() -> void:
	var b := _battle([_unit("Knight")], [_unit("Fighter")])
	var steps := 0
	while b.step():
		steps += 1
	check(steps > 0 and b.events.size() >= steps, "one turn per step")
	check(not b.step(), "nothing after the end")


func test_retreat() -> void:
	var b := _battle([_unit("Knight")], [_unit("Fighter")])
	b.sides[0].speed_tier = 3
	b.sides[1].speed_tier = 1
	check_eq(b.retreat_chance(0), 0.9, "50% + 2 tiers x 20%, capped at 90%")
	check_eq(b.retreat_chance(1), 0.1, "floored at 10%")
	b.sides[1].speed_tier = 2
	check_eq(b.retreat_chance(0), 0.7, "one tier faster: 70%")
	var ok := 0
	var fail_costs := false
	for seed in 200:
		var r := _battle([_unit("Knight", "front", "K")], [_unit("Fighter")], "plains", seed)
		if r.retreat(0):
			ok += 1
			check(r.is_over() and not r.step(), "a successful retreat ends the battle")
		else:
			var k := r.sides[0].units[0]
			r._turn(k)
			fail_costs = fail_costs or r.events[-1]["text"].contains("failed retreat")
	check(absf(ok / 200.0 - 0.5) < 0.1, "even speed: about 50%% (%d)" % ok)
	check(fail_costs, "a failed retreat costs the next action")


func test_outcome_report() -> void:
	var weak := _unit("Serf", "front", "W")
	weak.hp = 1
	var strong := _unit("Knight", "front", "K")
	var b := _battle([strong], [weak], "plains", 2)
	b._misses[strong] = 3
	b.run()
	var out := b.finish()
	check(out["wiped"][1], "the serf's squad is wiped out")
	check(out["leader_dead"] == [false, false], "the knight lives; the serf squad had no leader")
	check_eq(out["pushed"], -1, "no push-back after a wipe-out")
	var a := _unit("Knight", "front", "A")
	var z := _unit("Knight", "front", "Z")
	var c := _battle([a], [z])
	z.hp -= 10
	var out2 := c.finish()
	check_eq(out2["pushed"], 1, "the side that lost the larger share is pushed")


func _state() -> GameState:
	var m := MapData.new(12, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 1
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Vector2i(0, 2))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(11, 2)))
	return GameState.new(d, m, GameLog.new())


func test_push_back_on_the_map() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", st.map.index_of(Hex.from_offset(Vector2i(5, 2))), [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", st.map.index_of(Hex.from_offset(Vector2i(6, 2))), [["Knight", "front"]])
	var b := st.start_battle(ours, theirs, theirs)
	ours.units[0].hp -= 10
	var before := st.map.hex_at(ours.hex)
	st.end_battle(b)
	check_eq(Hex.distance(st.map.hex_at(ours.hex), before), 1, "pushed 1 hex on its own travel terrain (plains)")
	check(Hex.distance(st.map.hex_at(ours.hex), st.map.hex_at(theirs.hex)) > 1, "away from the enemy")
	var st2 := _state()
	var swamp := st2.map.index_of(Hex.from_offset(Vector2i(5, 2)))
	for i in st2.map.size():
		st2.map.terrain[i] = d.terrain_ids["forest"]
	var o2 := st2.add_squad("Ours", swamp, [["Knight", "front"]])
	var t2 := st2.add_squad("Theirs", st2.map.index_of(Hex.from_offset(Vector2i(6, 2))), [["Knight", "front"]])
	var b2 := st2.start_battle(o2, t2, t2)
	o2.units[0].hp -= 10
	st2.end_battle(b2)
	check_eq(Hex.distance(st2.map.hex_at(o2.hex), Hex.from_offset(Vector2i(5, 2))), 2, "pushed 2 hexes off its travel terrain")


func test_wipe_out_and_march_home() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", st.map.index_of(Hex.from_offset(Vector2i(5, 2))), [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", st.map.index_of(Hex.from_offset(Vector2i(6, 2))), [["Knight", "front"], ["Fighter", "front"]], "enemy")
	var b := st.start_battle(ours, theirs, theirs)
	ours.units[0].hp = 0
	theirs.leader.hp = 0
	st.end_battle(b)
	check(ours not in st.squads, "a wiped-out squad is carried back to base, off the map")
	check(theirs.marching_home and theirs.is_moving(), "a squad that lost its leader marches home")
	check_eq(theirs.rally[-1], st.map.enemy_base, "to its own base")
	var st2 := _state()
	var o2 := st2.add_squad("Ours", st2.map.index_of(Hex.from_offset(Vector2i(5, 2))), [["Knight", "front"]])
	var t2 := st2.add_squad("Theirs", st2.map.index_of(Hex.from_offset(Vector2i(6, 2))), [["Knight", "front"]])
	var cha := o2.units[0].charisma
	var b2 := st2.start_battle(o2, t2, t2)
	b2.retreated = 0
	st2.end_battle(b2)
	check_eq(o2.units[0].charisma, cha - 1, "retreating costs each unit 1 charisma")
	check_eq(Hex.distance(st2.map.hex_at(o2.hex), Hex.from_offset(Vector2i(5, 2))), 1, "and steps back 1 hex")


func test_drive_off() -> void:
	var st := _state()
	var ours := st.add_squad("Ours", 0, [["Knight", "front"]])
	var theirs := st.add_squad("Theirs", 1, [["Knight", "front"]])
	ours.leader.charisma = 40
	theirs.morale = 30
	check_eq(st.drive_off_chance(ours, theirs), 0.0, "only below morale 25")
	theirs.morale = 20
	check_eq(st.drive_off_chance(ours, theirs), 0.2, "halved at morale 10-25")
	theirs.morale = 5
	check_eq(st.drive_off_chance(ours, theirs), 0.4, "charisma % below 10")
	ours.leader.charisma = 100
	st.army.cells[0] = ours  # army.units() sees only the roster
	var xp_before := ours.leader.xp
	var level_before := ours.leader.level
	var gained := {}
	check(st.drive_off(ours, theirs, gained), "a sure demand works")
	check(theirs not in st.squads, "the squad leaves the map")
	check(int(gained["xp"].get(ours.leader, 0)) > 0, "driving them off earns XP")
	check(ours.leader.xp != xp_before or ours.leader.level > level_before, "the XP is given")


# --- Threat ----------------------------------------------------------------------------

func test_threat() -> void:
	var serf := _unit("Serf")
	var knight := _unit("Knight")
	check(Threat.unit(d, knight) > Threat.unit(d, serf), "a knight is more threatening than a serf")
	var full := Threat.unit(d, knight)
	knight.hp /= 2
	check(absf(Threat.unit(d, knight) - full / sqrt(2.0)) < 0.01, "threat scales with HP left")
	var a := _squad([_unit("Knight"), _unit("Fighter")])
	check_eq(Threat.label(d, a, _squad([_unit("Knight"), _unit("Fighter")])), "Even", "equal squads: Even")
	check_eq(Threat.label(d, a, _squad([_unit("Serf")])), "Much weaker", "a lone serf: Much weaker")
	check_eq(Threat.label(d, a, _squad([_unit("Knight")])), "Weaker", "a lone Knight: Weaker")
	var big := _squad([_unit("Dragon"), _unit("Dragon"), _unit("Knight")])
	check(Threat.label(d, a, big) in ["Stronger", "Dangerous"], "dragons: Stronger or Dangerous")
	check_eq(Threat.label(d, _squad([_unit("Serf")]), big), "Dangerous", "dragons against a serf: Dangerous")


# --- Sim -------------------------------------------------------------------------------

func test_sim_runs_and_hits_the_rout_target() -> void:
	var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_builds.json"))
	var r := BattleSim.run(GameData.load_dir(), builds["vanguard"], builds["shieldwall"], 60, 7)  # with the front-row cut
	check_eq(r["trials"], 60, "ran every trial")
	check(absf(r["win_a"] + r["win_b"] + r["draws"] - 1.0) < 0.001, "shares add up")
	check(r["loser_hp_lost"] >= 0.22 and r["loser_hp_lost"] <= 0.55, "an even fight costs the loser about 35-50%% of its HP (%.0f%%)" % (r["loser_hp_lost"] * 100))
	check(r["win_a"] <= 0.65 and r["win_b"] <= 0.65, "these two builds are even (%.0f%% / %.0f%%)" % [r["win_a"] * 100, r["win_b"] * 100])


## The game data with the front-row damage cut off, so the formula checks keep exact numbers
## (test_battle.test_front_row_damage_cut covers the cut itself).
static func _formula_data() -> GameData:
	var data := GameData.load_dir()
	data.battle["front_row_damage_cut"] = 0.0
	return data
