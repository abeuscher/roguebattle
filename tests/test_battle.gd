extends TestCase
## Battle rules core (SPEC §11.3–11.5, §12.1), with fixed seeds.

var d := GameData.load_dir()


## A unit with its class's base stats, neutral alignment and no luck.
func _unit(class_name_: String, row := "front", name := "") -> Unit:
	var u := Unit.new()
	u.unit_class = class_name_
	u.name = name if name != "" else class_name_
	for s in Unit.STATS:
		u.stats[s] = int(d.units[class_name_]["base_stats"][s])
	u.hp = u.max_hp(d)
	u.row = row
	return u


func _squad(units: Array) -> Squad:
	var s := Squad.new(1, "S", 0)
	for u in units:
		s.units.append(u)
		if s.leader == null and u.info(d)["can_lead"]:
			s.leader = u
	return s


func _battle(a: Array, b: Array, terrain := "plains", seed := 1, day := true) -> Battle:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Battle.new(d, _squad(a), _squad(b), terrain, day, rng)


func test_turn_order_by_speed() -> void:
	var fast := _unit("Centaur")
	var slow := _unit("Knight")
	fast.stats["SPD"] = 12
	slow.stats["SPD"] = 5
	var b := _battle([slow], [fast])
	b.run()
	check_eq(_acts(b)[0]["unit"], fast, "the faster unit acts first")
	var c := _battle([_unit("Knight", "front", "A")], [_unit("Knight", "front", "B")])
	c.first_side = 1
	c.sides[0].units[0].stats["SPD"] = 20
	c.run()
	check_eq(c.side_of(_acts(c)[0]["unit"]), 1, "a side that resisted recruitment takes its first round first")


func test_row_attack_counts() -> void:
	var front := _unit("Fighter", "front")  # front 2 attacks, back 1
	var back := _unit("Fighter", "back")
	var wall := _unit("Knight")
	wall.hp = 100000
	var b := _battle([front, back], [wall])
	b.run()
	var count := {front: 0, back: 0}
	for e in _acts(b):
		if count.has(e["unit"]):
			count[e["unit"]] += 1
	check_eq(count[front], 2, "front-row Fighter attacks twice")
	check_eq(count[back], 1, "back-row Fighter attacks once")
	check_eq(b.attack_kind(_unit("Bowman", "back")), d.units["Bowman"]["back_attack"], "row picks the attack type")


func test_rounds_interleave() -> void:
	var a := _unit("Fighter", "front", "A")  # two attacks
	var b2 := _unit("Fighter", "front", "B")
	a.stats["SPD"] = 10
	b2.stats["SPD"] = 9
	for u in [a, b2]:
		u.hp = 100000
	var b := _battle([a], [b2])
	b.run()
	var who := _acts(b).map(func(e): return e["unit"].name)
	check_eq(who, ["A", "B", "A", "B"], "each round every unit acts once, fastest first")


func test_melee_targets_front_first() -> void:
	var b := _battle([_unit("Fighter")], [_unit("Knight", "front", "F"), _unit("Bowman", "back", "K")])
	var me := b.sides[0].units[0]
	var targets := b.reachable(me, "Melee", b.sides[1])
	check_eq(targets.size(), 1, "melee reaches only the front row")
	check_eq(targets[0].name, "F", "the front unit")
	check_eq(b.reachable(me, "Magic", b.sides[1]).size(), 2, "magic reaches any row")
	check_eq(b.reachable(me, "Ranged", b.sides[1]).size(), 2, "ranged reaches any row")
	check_eq(b.reachable(me, "Melee (any row)", b.sides[1]).size(), 2, "melee (any row) reaches any row")
	b.sides[1].units[0].hp = 0
	check_eq(b.reachable(me, "Melee", b.sides[1])[0].name, "K", "the back row once the front is empty")


func test_physical_damage() -> void:
	var f := _unit("Fighter")  # STR 11
	var k := _unit("Knight")
	var b := _battle([f], [k], "forest")  # neither is at home or on hard terrain
	check_eq(b.expected_damage(f, k, "Melee"), maxf(1.0, 11.0 - k.stats["PDEF"]), "STR - PDEF")
	k.stats["PDEF"] = 50
	check_eq(b.expected_damage(f, k, "Melee"), 1.0, "minimum 1")
	k.stats["PDEF"] = 5
	b.defense[1] = 0.1
	check_eq(b.expected_damage(f, k, "Melee"), (11.0 - 5.0) * 0.9, "building defense cuts damage taken")


func test_magic_and_breath() -> void:
	var mage := _unit("Apprentice")
	var k := _unit("Knight")
	var b := _battle([mage], [k], "forest")
	check_eq(b.expected_damage(mage, k, "Magic"), maxf(1.0, float(mage.stats["INT"] - k.stats["MDEF"])), "INT - MDEF")
	var dragon := _unit("Dragon")
	var breath: float = (dragon.stats["STR"] + dragon.stats["INT"]) * 0.5 - k.stats["MDEF"] * 0.5
	var bd := _battle([dragon], [k], "forest")
	check_eq(bd.expected_damage(dragon, k, "Breath"), maxf(1.0, breath), "breath: half of STR + INT, ignores half MDEF")


func test_element() -> void:
	var fire := ""
	var ice := ""
	for c in d.units:
		if d.units[c]["element"] == "Fire" and fire == "":
			fire = c
		if d.units[c]["element"] == "Ice" and ice == "":
			ice = c
	var b := _battle([_unit(fire)], [_unit(ice)])
	check_eq(b.element_multiplier(b.element(b.sides[0].units[0]), b.element(b.sides[1].units[0])), 1.5, "fire against ice")
	check_eq(b.element_multiplier(b.element(b.sides[0].units[0]), b.element(_unit(fire))), 0.75, "fire against fire")
	check_eq(b.element_multiplier(b.element(b.sides[0].units[0]), b.element(_unit("Knight"))), 1.0, "no element, no change")


func test_terrain_and_day() -> void:
	var k := _unit("Knight")  # plains
	var b := _battle([k], [_unit("Fighter")], "plains")
	check_eq(b.terrain_modifier(k), 1.15, "home terrain +15%")
	check_eq(_battle([k], [_unit("Fighter")], "swamp").terrain_modifier(k), 0.85, "difficulty 3 -15%")
	check_eq(_battle([k], [_unit("Fighter")], "forest").terrain_modifier(k), 1.0, "difficulty 2: no change")
	var mer := _unit("Mermaid")
	check_eq(_battle([mer], [k], "deep").terrain_modifier(mer), 1.15, "water natives at home on deep water")
	var eagle := _unit("Eagle Rider")
	check_eq(_battle([eagle], [k], "mountain").terrain_modifier(eagle), 1.0, "flyers ignore terrain")
	k.alignment = 80
	check_eq(b.day_modifier(k), 1.15, "holy by day")
	check_eq(_battle([k], [_unit("Fighter")], "plains", 1, false).day_modifier(k), 0.85, "holy at night")
	k.alignment = 10
	check_eq(b.day_modifier(k), 0.85, "evil by day")
	k.alignment = 50
	check_eq(b.day_modifier(k), 1.0, "neutral unaffected")


func test_matchups() -> void:
	var b := _battle([_unit("Fighter")], [_unit("Fighter")])
	check_eq(b.matchup_modifier(_unit("Archer"), _unit("Eagle Rider")), 1.5, "archers x1.5 against flyers")
	check_eq(b.matchup_modifier(_unit("Archer"), _unit("Knight")), 1.0, "archers x1 against walkers")
	check_eq(b.matchup_modifier(_unit("Lancer"), _unit("Lancer")), 1.5, "mounted against mounted")
	check_eq(b.matchup_modifier(_unit("Spearman"), _unit("Lancer")), 1.5, "spears against mounted")
	check_eq(b.matchup_modifier(_unit("Spearman"), _unit("Knight")), 1.0, "spears against foot")


func test_hit_chance() -> void:
	var a := _unit("Fighter")
	var t := _unit("Fighter")
	var b := _battle([a], [t])
	check_eq(b.hit_chance(a, t), 85.0, "85% at equal AGI")
	a.stats["AGI"] += 5
	check_eq(b.hit_chance(a, t), 90.0, "+1% per AGI point over")
	a.stats["AGI"] += 50
	check_eq(b.hit_chance(a, t), 95.0, "clamped at 95%")
	a.stats["AGI"] -= 100
	check_eq(b.hit_chance(a, t), 50.0, "clamped at 50%")
	a.stats["AGI"] += 50
	t.luck = 10
	check_eq(b.hit_chance(a, t), 85.0, "each luck point dodges 0.5% (90 - 5)")


func test_two_dice_and_streak_breaker() -> void:
	var a := _unit("Fighter")
	var t := _unit("Fighter")
	a.stats["AGI"] -= 25  # 60% shown
	var fair := _battle([a], [t], "plains", 9)
	fair._misses[a] = 0
	var plain := _battle([a], [t], "plains", 9)
	plain.fair = [false, false]
	plain._misses[a] = 0
	var hits := [0, 0]
	var streak := 0
	var worst := 0
	for i in 20000:
		var h := fair.roll_hit(a, t)
		hits[0] += int(h)
		streak = 0 if h else streak + 1
		worst = maxi(worst, streak)
		hits[1] += int(plain.roll_hit(a, t))
	check(absf(hits[1] / 20000.0 - 0.6) < 0.015, "plain dice hit about 60%% (%d)" % hits[1])
	check(hits[0] > hits[1], "two dice favor a 60%% shot (%d vs %d)" % hits)
	check(worst <= 3, "never more than 3 misses in a row (worst %d)" % worst)


func test_ramping_crits_keep_average() -> void:
	var a := _unit("Fighter")
	var b := _battle([a], [_unit("Fighter")], "plains", 4)
	b._since_crit[a] = 0
	var crits := 0
	var longest := 0
	var gap := 0
	for i in 40000:
		if b.roll_crit(a):
			crits += 1
			gap = 0
		else:
			gap += 1
			longest = maxi(longest, gap)
	check(absf(crits / 40000.0 - 0.05) < 0.005, "ramping crits average 5%% (%d)" % crits)
	check(longest < 60, "ramping makes long dry spells rare (longest %d)" % longest)
	a.luck = 20
	check_eq(b.crit_chance(a), 0.15, "luck adds 0.5% each")


func test_spread_and_crit_damage() -> void:
	for seed in 50:
		var f := _unit("Fighter")
		var k := _unit("Knight")
		k.hp = 100000
		var b := _battle([f], [k], "forest", seed)
		var base := b.expected_damage(f, k, "Melee")
		b.run()
		for e in _acts(b):
			if e["unit"] == f and e["hit"]:
				var m := base * (1.5 if e["crit"] else 1.0)
				check(e["damage"] >= floori(m * 0.9) and e["damage"] <= ceili(m * 1.1), "damage within ±10%% (%d of %.1f)" % [e["damage"], m])


func test_heal() -> void:
	var healer := _unit("Acolyte", "back")
	var hurt := _unit("Knight", "front", "Hurt")
	hurt.hp = 10
	var b := _battle([hurt, healer], [_unit("Fighter")])
	var before := hurt.hp
	b._heal(healer, 0)
	var gain := hurt.hp - before
	var int_: int = healer.stats["INT"]
	var share: float = d.battle["heal_int_share"]
	check(gain >= floori(int_ * share * 0.9) and gain <= ceili(int_ * share * 1.1), "heals about INT x heal share (%d)" % gain)
	check_eq(b.events[-1]["target"], hurt, "heals the most hurt ally")


func test_tactics() -> void:
	var weak := _unit("Bowman", "front", "Weak")
	weak.hp = 5
	var lead := _unit("Knight", "front", "Lead")
	var tough := _unit("Fighter", "front", "Tough")
	var a := _unit("Fighter")
	var b := _battle([a], [lead, weak, tough])
	var targets := b.reachable(a, "Melee", b.sides[1])
	check_eq(b.pick_target(a, "Melee", targets, "weak").name, "Weak", "Weak focuses the lowest HP")
	check_eq(b.pick_target(a, "Melee", targets, "leader").name, "Lead", "Leader focuses the leader")
	check_eq(b.pick_target(a, "Melee", targets, "strong").name, "Lead", "Strong focuses the highest stat total")
	var best := b.pick_target(a, "Melee", targets, "best")
	for t in targets:
		check(b.expected_damage(a, best, "Melee") >= b.expected_damage(a, t, "Melee"), "Best hurts most")


func test_battle_runs_to_an_end() -> void:
	var a := [_unit("Knight"), _unit("Fighter"), _unit("Fighter"), _unit("Bowman", "back"), _unit("Acolyte", "back")]
	var e := [_unit("Soldier"), _unit("Fighter"), _unit("Slinger"), _unit("Archer", "back"), _unit("Apprentice", "back")]
	var b := _battle(a, e, "plains", 12)
	b.run()
	check(not b.events.is_empty(), "something happened")
	for e2 in b.events:
		check(e2.has("text") and e2["text"] != "", "every event has a log line")
	var again := _battle([_unit("Knight")], [_unit("Fighter")], "plains", 12)
	var twice := _battle([_unit("Knight")], [_unit("Fighter")], "plains", 12)
	again.run()
	twice.run()
	check_eq(again.events.map(func(x): return x["text"]), twice.events.map(func(x): return x["text"]), "same seed, same battle")


## Events without the round headers.
func _acts(b: Battle) -> Array:
	return b.events.filter(func(e): return e["type"] != "round")
