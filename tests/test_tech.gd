extends TestCase
## The tech tree: points, costs, tier gates and every node's effect (SPEC §14).

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 13
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append({"type": "town", "hex": _at(m, 8, 3), "shop": true, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	st.setup_army()
	return st


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _learn(st: GameState, ids: Array) -> void:
	for id in ids:
		st.tech_points += st.tech_nodes()[id]["tier"]
		check(st.buy_tech(id), "learn %s" % id)


func _unit(c: String, row := "front") -> Unit:
	var u := Unit.new()
	u.unit_class = c
	u.name = c
	for s in Unit.STATS:
		u.stats[s] = int(d.units[c]["base_stats"][s])
	u.hp = u.max_hp(d)
	u.row = row
	return u


func _squad(units: Array, tech := []) -> Squad:
	var s := Squad.new(1, "S", 0)
	s.tech = tech
	for u in units:
		s.units.append(u)
		if s.leader == null and u.info(d)["can_lead"]:
			s.leader = u
	s.refresh(d)
	return s


func _battle(a: Array, b: Array, tech: Array, terrain := "plains") -> Battle:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	var bt := Battle.new(d, _squad(a, tech), _squad(b), terrain, true, rng)
	bt.tech[0] = tech
	return bt


func test_points_and_costs() -> void:
	var st := _state()
	check_eq(st.tech_points, 3, "3 points to start")
	check(st.buy_tech("shield_wall"), "a tier 1 node costs 1")
	check_eq(st.tech_points, 2, "2 left")
	check(st.tech_blocker("shield_wall") != "", "can't buy it twice")
	st.player_squads()[0].hex = st.map.buildings[0]["hex"]
	for i in int(d.rules["capture"]["ticks"]):
		st.step()
	check_eq(st.tech_points, 3, "+1 for a liberation")


func test_tier_gate() -> void:
	var st := _state()
	st.tech_points = 100
	check(not st.tier_open(2), "tier 2 starts closed")
	for id in ["shield_wall", "longbow_training", "field_medicine", "barding"]:
		st.buy_tech(id)
	check(not st.tier_open(2), "4 of 6 tier 1 branch nodes: still closed")
	for terrain in d.tech["terrains"]:
		st.buy_tech("terrain_%s_1" % terrain)
	check(not st.tier_open(2), "terrain nodes don't count toward the gate")
	st.buy_tech("aerial_scouts")
	check(st.tier_open(2), "5 of 6 (80%) opens tier 2")
	var before := st.tech_points
	check(st.buy_tech("steelworking"), "buy a tier 2 node")
	check_eq(st.tech_points, before - 2, "it costs 2")
	check(st.tech_blocker("drill").contains("Tier 3"), "tier 3 still closed")


func test_battle_win_earns_a_point() -> void:
	var st := _state()
	var ours := st.player_squads()[0]
	var foe := st.add_squad("Them", _at(st.map, 3, 3), [["Serf", "front"]], "enemy")
	var b := st.start_battle(ours, foe, foe)
	foe.units[0].hp = 0
	var points := st.tech_points
	st.end_battle(b)
	check_eq(st.tech_points, points + 1, "+1 for a win")


func test_arms() -> void:
	var front := _unit("Knight")
	var back := _unit("Archer", "back")
	var b := _battle([front, back], [_unit("Soldier")], ["shield_wall"])
	check(is_equal_approx(b.stat(front, "PDEF"), front.stats["PDEF"] * 1.1), "Shield Wall: front row +10% PDEF")
	check(is_equal_approx(b.stat(back, "PDEF"), back.stats["PDEF"]), "not the back row")
	var plain := _battle([_unit("Knight")], [_unit("Soldier")], [])
	var drilled := _battle([_unit("Knight")], [_unit("Soldier")], ["drill"])
	check_eq(drilled.attack_count(drilled.sides[0].units[0]), plain.attack_count(plain.sides[0].units[0]) + 1, "Drill: stage 3 melee +1 attack")
	var st := _state()
	var paladin := Unit.roll(d, "Paladin", RandomNumberGenerator.new(), st.names)
	st.army.pool.append(paladin)
	var hp := paladin.max_hp(d)
	_learn(st, ["shield_wall", "longbow_training", "field_medicine", "barding", "aerial_scouts", "steelworking", "skyhunters",
			"elemental_focus", "charge", "tamers", "drill", "volley", "mage_regiments", "outriders", "pack_bond", "veterans"])
	check_eq(paladin.max_hp(d), roundi(hp * 1.1), "Veterans: stage 4 units +10% HP")
	var town: Dictionary = st.map.buildings[0]
	town["stock"] = null
	town.erase("stock")
	check(st.tier_open(4), "every tier open by now")


func test_shop_unlocks() -> void:
	var st := _state()
	var town: Dictionary = st.map.buildings[0]
	for i in 40:
		town.erase("stock")
		check("longbow" not in st.shop_stock(town) and "steel" not in st.shop_stock(town), "no longbows or steel without the tech")
	st.tech.append("longbow_training")
	var seen := false
	for i in 60:
		town.erase("stock")
		seen = seen or "longbow" in st.shop_stock(town)
	check(seen, "Longbow Training puts longbows in shops")


func test_archery() -> void:
	var archer := _unit("Archer", "back")
	var flyer := _unit("Eagle Knight")
	var plain := _battle([_unit("Knight"), archer], [flyer], [])
	var sky := _battle([_unit("Knight"), archer], [flyer], ["skyhunters"])
	check(is_equal_approx(sky.matchup_modifier(archer, flyer), plain.matchup_modifier(archer, flyer) / 1.5 * 2.0), "Skyhunters: ×1.5 becomes ×2")
	var dead := _battle([_unit("Knight"), archer], [flyer], ["deadeye"])
	check(is_equal_approx(dead.crit_chance(archer), plain.crit_chance(archer) + 0.10), "Deadeye: +10% crit for archers")
	var a := _unit("Archer", "back")
	var e1 := _unit("Soldier")
	var e2 := _unit("Soldier")
	var v := _battle([_unit("Knight"), a], [e1, e2], ["volley"])
	v._strike(a, "Ranged", 0)
	var hits := v.events.filter(func(ev): return ev["type"] == "attack" and ev["unit"] == a)
	check_eq(hits.size(), 2, "Volley: one shot becomes two")
	check(hits[0]["target"] != hits[1]["target"], "at two targets")


func test_arcana() -> void:
	var mage := _unit("Apprentice", "back")
	var targets := [_unit("Soldier"), _unit("Soldier"), _unit("Fighter")]
	var b := _battle([_unit("Knight"), mage], targets, ["archmagi"])
	b._strike(mage, "Magic", 0)
	var hit := b.events.filter(func(ev): return ev["type"] == "attack" and ev["unit"] == mage).size()
	check_eq(hit, 3, "Archmagi: a single Magic attack hits the whole row")
	var hurt := _unit("Knight")
	var m := _battle([hurt], [_unit("Serf")], ["field_medicine"])
	hurt.hp = 10
	m.finish()
	check_eq(hurt.hp, 10 + roundi(hurt.max_hp(d) * 0.1), "Field Medicine: +10% after the battle")
	var slow := _squad([_unit("Lancer"), _unit("Apprentice", "back")])
	check_eq(slow.speed_tier, 1, "an Apprentice slows a Lancer squad to tier 1")
	var regiment := _squad([_unit("Lancer"), _unit("Apprentice", "back")], ["mage_regiments"])
	check_eq(regiment.speed_tier, 3, "Mage Regiments: casters don't slow it")


func test_cavalry_and_flyers() -> void:
	# A Knight leads, so the Lancer's own Charge order aura doesn't apply.
	var lancer := _unit("Lancer")
	var b := _battle([_unit("Knight"), lancer], [_unit("Soldier")], ["charge"])
	b.attacker = 0
	check(b._strikes_first(lancer), "Charge: mounted units strike first attacking on plains")
	var forest := _battle([_unit("Knight"), _unit("Lancer")], [_unit("Soldier")], ["charge"], "forest")
	forest.attacker = 0
	check(not forest._strikes_first(forest.sides[0].units[1]), "not in a forest")
	var rush := _battle([_unit("Knight"), _unit("Lancer")], [_unit("Soldier")], ["charge", "lance_rush"], "forest")
	rush.attacker = 0
	check(rush._strikes_first(rush.sides[0].units[1]), "Lance Rush: any terrain that isn't hard")
	var flyers := _squad([_unit("Eagle Knight"), _unit("Eagle Knight")], ["sky_lords"])
	check(flyers.sky, "a flying squad")
	var wolf := _unit("Wolfhound")
	var pack := _battle([wolf, _unit("Wolfhound")], [_unit("Serf")], ["pack_bond"])
	check(is_equal_approx(pack.stat(wolf, "PDEF"), wolf.stats["PDEF"] * 1.1), "Pack Bond: two Large units +10%")


func test_sight_and_speed() -> void:
	var st := _state()
	var riders := st.add_squad("Riders", _at(st.map, 5, 3), [["Lancer", "front"]])
	var base := st.sight(riders, _at(st.map, 10, 3))
	st.tech.append("outriders")
	check_eq(st.sight(riders, _at(st.map, 10, 3)), base + 1, "Outriders: +1 sight with mounted units")
	var wings := st.add_squad("Wings", _at(st.map, 5, 5), [["Eagle Knight", "front"]])
	var tier := wings.speed_tier
	st.tech.append("sky_lords")
	wings.refresh(d)
	check_eq(wings.speed_tier, mini(3, tier + 1), "Sky Lords: one tier faster")


func test_logistics() -> void:
	var st := _state()
	var upkeep := st.army_upkeep()
	st.tech.append("quartermaster")
	check(st.army_upkeep() < upkeep, "Quartermaster: less upkeep (%d → %d)" % [upkeep, st.army_upkeep()])
	st.map.buildings[0]["owner"] = "player"
	var income := st.income()
	st.tech.append("war_chest")
	check_eq(st.income(), roundi(income * 1.1), "War Chest: +10% income")
	var s := st.player_squads()[0]
	var chance := st.recruit_chance(s, 3, 50.0)
	st.tech.append("diplomacy")
	check(is_equal_approx(st.recruit_chance(s, 3, 50.0), chance * 1.1), "Diplomacy: +10%")
	st.tech.append("tamers")
	check(is_equal_approx(st.recruit_chance(s, 3, 50.0, true), chance * 1.1 * 1.2), "Tamers: +20% more with Large neutrals")
	var road := _at(st.map, 6, 3)
	st.map.road[road] = 1
	var t := st.step_ticks(s, road)
	st.tech.append("engineers")
	check(is_equal_approx(st.step_ticks(s, road), t * 0.6 / 0.75), "Engineers: roads ×0.6")


func test_terrain_nodes() -> void:
	var knight := _unit("Knight")
	var b := _battle([knight], [_unit("Soldier")], ["terrain_Plains_1", "terrain_Plains_3"])
	check_eq(b.terrain_level(0, knight), 3, "the highest Plains tier bought")
	check(is_equal_approx(b.stat(knight, "STR"), knight.stats["STR"] + 3.0), "+3 STR for a Plains unit")
	var eagle := _unit("Eagle Knight")
	var b2 := _battle([eagle], [_unit("Soldier")], ["terrain_Plains_3"])
	check_eq(b2.terrain_level(0, eagle), 0, "a Sky unit doesn't count as Plains")
