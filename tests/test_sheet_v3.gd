extends TestCase
## Unit sheet v3: data, positions, group attacks, Ward and Dispel, traits and leader
## auras (the sheet's Mechanics tab; SPEC §21 where it overrides the sheet).

var d := GameData.load_dir()


func _unit(class_name_: String, row := "front", name := "") -> Unit:
	var u := Unit.new()
	u.unit_class = class_name_
	u.name = name if name != "" else class_name_
	for s in Unit.STATS:
		u.stats[s] = int(d.units[class_name_]["base_stats"][s])
	u.hp = u.max_hp(d)
	u.row = row
	return u


## Units take positions in their row in the order given.
func _squad(units: Array, name := "S") -> Squad:
	var s := Squad.new(1, name, 0)
	for u in units:
		u.col = s.next_col(u.row)
		s.units.append(u)
		if s.leader == null and u.info(d)["can_lead"]:
			s.leader = u
	s.refresh(d)
	return s


func _battle(a: Array, b: Array, terrain := "plains", seed := 1, day := true) -> Battle:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	return Battle.new(d, _squad(a, "Ours"), _squad(b, "Theirs"), terrain, day, rng)


## Gives the unit a guaranteed hit (streak breaker) and makes it act.
func _sure_turn(b: Battle, u: Unit) -> void:
	b._misses[u] = 3
	b._turn(u)


func _tough(u: Unit) -> Unit:
	u.hp = 100000
	u.stats["CON"] = 10000
	return u


# --- Data ---------------------------------------------------------------------------

func test_sheet_loads() -> void:
	check_eq(d.units.size(), 190, "190 classes")
	check(not FileAccess.file_exists("res://data/unit-table-final.xlsx"), "the old sheet is gone")
	check_eq(float(d.units["Lancer"]["xp_rate"]), 1.25, "XP rate column")
	check_eq(d.units["Dragon"]["leader_aura"], "Dragonfear", "leader aura name")
	check_eq(d.units["Lancer"]["traits"], ["Mounted", "Charge"], "traits as names")
	var tiny := 0
	for c in d.units:
		if d.units[c]["size"] == "Tiny":
			tiny += 1
	check_eq(tiny, 8, "eight Tiny units")


func test_every_trait_and_aura_is_known() -> void:
	var handled_by_name := ["Bulwark", "Guard", "Pounce", "First strike", "Raise dead", "Pushback", "Mounted", "Brace",
			"Anti-air", "Giant-killer", "Tiny", "Mass heal (row)", "Pathfinder", "Bridge", "Supply", "Black market", "Banner", "Foresight"]
	for c in d.units:
		for t in d.units[c]["traits"]:
			check(t in handled_by_name or d.battle["traits"].has(t), "%s: unknown trait '%s'" % [c, t])
		var aura = d.units[c].get("leader_aura")
		check(aura == null or d.battle["auras"].has(aura), "%s: unknown aura '%s'" % [c, aura])
		if d.units[c]["can_lead"]:
			check(aura != null, "%s leads, so has an aura" % c)


# --- Positions and movement ----------------------------------------------------------

func test_positions() -> void:
	var s := Squad.new(1, "S", 0)
	var a := Unit.roll(d, "Knight", RandomNumberGenerator.new(), NameBook.new(d))
	var b := Unit.roll(d, "Fighter", RandomNumberGenerator.new(), NameBook.new(d))
	var c := Unit.roll(d, "Bowman", RandomNumberGenerator.new(), NameBook.new(d))
	s.add(d, a, "front")
	s.add(d, b, "front")
	s.add(d, c, "back")
	check_eq([a.col, b.col, c.col], [0, 1, 0], "positions fill left to right per row")
	check_eq(s.across(a), c, "the bowman stands behind the knight")
	check_eq(s.across(b), null, "nobody behind the fighter")


func test_flyers_and_amphibians() -> void:
	var angels := _squad([_unit("Archangel"), _unit("Angel"), _unit("Eagle Rider")])
	check(angels.sky, "angels count as flyers (Mechanics tab), so the squad flies")
	var frogs := _squad([_unit("Frog Boy"), _unit("Frog"), _unit("Toad")])
	check_eq(frogs.travel_type, "amphibious", "an all-amphibious squad")
	var m := MapData.new(4, 1)
	for i in 4:
		m.terrain[i] = d.terrain_ids[["mountain", "swamp", "shallow", "deep"][i]]
	for i in 4:
		check_eq(Movement.hex_multiplier(m, d, i, "amphibious"), 1.0, "amphibious: x1 on %s" % d.terrains[m.terrain[i]]["key"])
	check_eq(_squad([_unit("Siren"), _unit("Frog")]).travel_type, "deep", "water natives and amphibians cross deep water")


# --- Group attacks -------------------------------------------------------------------

func test_row_and_all() -> void:
	var dragon := _unit("Dragon", "back")  # Breath (row)
	var b := _battle([dragon], [_tough(_unit("Knight", "front", "A")), _tough(_unit("Knight", "front", "B")), _tough(_unit("Knight", "back", "C"))])
	_sure_turn(b, dragon)
	var hit := b.events.filter(func(e): return e["type"] == "attack").map(func(e): return e["target"].row)
	check(hit.size() == 2 and hit.all(func(r): return r == hit[0]), "breath (row) hits every unit of one row (%s)" % [hit])
	var lev := _unit("Leviathan", "back")  # Breath (all)
	var c := _battle([lev], [_tough(_unit("Knight")), _tough(_unit("Knight")), _tough(_unit("Bowman", "back"))])
	_sure_turn(c, lev)
	check_eq(c.events.filter(func(e): return e["type"] == "attack").size(), 3, "breath (all) hits the whole squad")


func test_cleave_pierce_chain() -> void:
	var cat := _unit("Shadow Cat")  # Melee (cleave 2)
	var b := _battle([cat], [_tough(_unit("Knight", "front", "L")), _tough(_unit("Knight", "front", "M")), _tough(_unit("Knight", "front", "R"))])
	_sure_turn(b, cat)
	var hits := b.events.filter(func(e): return e["type"] == "attack")
	check_eq(hits.size(), 2, "cleave hits two")
	check(absi(hits[0]["target"].col - hits[1]["target"].col) == 1, "the second is beside the first")
	var mage := _unit("Earth Mage", "back")
	check_eq(Battle.group_of(Battle.base_kind("Magic (pierce)") + " (pierce)"), "pierce", "kind parsing")
	var front := _tough(_unit("Knight", "front", "F"))
	var back := _tough(_unit("Bowman", "back", "B"))
	var c := _battle([mage], [front, back])
	c._misses[mage] = 3
	c._attack(mage, "Magic", front)  # pierce follows the target to the unit behind it
	var hit_back := false
	c._strike(mage, "Magic (pierce)", 0)
	for e in c.events:
		if e["type"] == "attack" and e["target"] == back:
			hit_back = true
	check(hit_back, "pierce hits the unit behind")
	var kraken := _unit("Electro Kraken", "back")  # Magic (chain 3)
	var foes := [_tough(_unit("Knight")), _tough(_unit("Knight")), _tough(_unit("Knight")), _tough(_unit("Bowman", "back"))]
	var k := _battle([kraken], foes, "plains", 4)
	k._misses[kraken] = 100
	k.fair[0] = true
	k._strike(kraken, "Magic (chain 3)", 0)
	var chain := k.events.filter(func(e): return e["type"] == "attack")
	check_eq(chain.size(), 3, "chain jumps to three targets")
	var targets := {}
	for e in chain:
		targets[e["target"]] = true
	check_eq(targets.size(), 3, "three different targets")


func test_heal_row_ward_dispel() -> void:
	var templar := _unit("Templar", "back")  # Heal (row)
	var a := _unit("Knight", "front", "A")
	var b2 := _unit("Knight", "front", "B")
	a.hp -= 10
	b2.hp -= 5
	var b := _battle([a, b2, templar], [_unit("Fighter")])
	b._turn(templar)
	check(a.hp > a.max_hp(d) - 10 and b2.hp > b2.max_hp(d) - 5, "heal (row) heals the whole row")
	var elf := _unit("Elf")  # front action Ward
	var k := _unit("Knight")
	var mage := _unit("Mage", "back")
	var w := _battle([elf, k], [mage])
	var before := w.expected_damage(mage, k, "Magic")
	w._turn(elf)
	check(w.has_status(k, "ward"), "ward covers the squad")
	check(w.expected_damage(mage, k, "Magic") < before, "and cuts magic damage")
	w._end_buffs_from(elf)
	check(not w.has_status(k, "ward"), "until the warder acts again")
	var toad := _unit("Toad", "back")  # Dispel
	var cleric := _unit("Cleric", "back")
	var t := _battle([toad], [_unit("Knight"), cleric])
	t._misses[toad] = 3
	t._attack(toad, "Dispel", cleric)
	check(t.has_status(cleric, "dispelled"), "dispel marks the target")
	cleric.hp -= 0
	t.sides[1].units[0].hp -= 30
	t._turn(cleric)
	check(t.events[-1]["text"].contains("cancelled"), "its next heal is cancelled")
	check(not t.has_status(cleric, "dispelled"), "only once")


# --- Targeting traits -------------------------------------------------------------------

func test_bulwark_and_guard() -> void:
	var gryphon := _unit("Gryphon", "front")  # Bulwark
	var hidden := _unit("Bowman", "back")
	var archer := _unit("Archer", "back")
	var b := _battle([archer], [gryphon, hidden])
	check(hidden not in b.reachable(archer, "Ranged", b.sides[1]), "bulwark hides the unit behind it from ranged")
	var rogue := _unit("Rogue")
	check(hidden in b.reachable(rogue, "Melee (any row)", b.sides[1]), "any-row melee gets past")
	check(hidden in b.reachable(_unit("Falconer"), "Ranged", b.sides[1]), "falconers get past")
	check(hidden in b.reachable(_unit("Mage"), "Magic", b.sides[1]), "magic isn't blocked")
	var sentinel := _unit("Sentinel", "front")  # Guard
	var ward := _unit("Bowman", "back")
	var c := _battle([_unit("Archer", "back")], [sentinel, ward])
	check_eq(c._guarded(c.sides[1], ward), sentinel, "guard takes hits aimed at the unit behind it")


func test_pounce_and_reach() -> void:
	var cat := _unit("Sabretooth", "front")
	var back := _unit("Bowman", "back")
	var b := _battle([cat], [_unit("Knight"), back])
	check(back in b.reachable(cat, b.attack_kind(cat), b.sides[1]), "pounce: front attack reaches the back row")
	var spear := _unit("Spearman", "back")
	check(back in b.reachable(spear, b.attack_kind(spear), b.sides[1]), "reach 2nd row")


func test_pushback() -> void:
	var ram := _unit("Battle Ram")
	var front := _tough(_unit("Knight", "front", "F"))
	var behind := _tough(_unit("Bowman", "back", "B"))
	var b := _battle([ram], [front, behind])
	b.round = 2  # past round 1, so the ram's own Battering aura is quiet
	b._misses[ram] = 3
	b._attack(ram, "Melee", front)
	check(front.row == "back" and behind.row == "front", "the first hit swaps the target with the unit behind")
	b._misses[ram] = 3
	b._attack(ram, "Melee", behind)
	check_eq(behind.row, "front", "only once per battle")


# --- Damage traits -------------------------------------------------------------------------

func test_damage_traits() -> void:
	var lancer := _unit("Lancer")
	var k := _unit("Knight")
	var b := _battle([lancer], [k], "forest")
	var first := b.expected_damage(lancer, k, "Melee")
	b._used["first:%d" % lancer.get_instance_id()] = true
	var later := b.expected_damage(lancer, k, "Melee")
	check(first > later, "charge: the first attack hits harder (%.1f vs %.1f)" % [first, later])
	var champ := _unit("Champion")
	var c := _battle([champ], [k])
	var str_full := c.stat(champ, "STR")
	champ.hp = champ.max_hp(d) / 3
	check_eq(c.stat(champ, "STR"), str_full * 1.5, "last stand: +50% STR below half HP")
	var rogue := _unit("Rogue")
	var t := _unit("Knight")
	var e := _battle([rogue], [t], "forest")
	var normal := e.expected_damage(rogue, t, "Melee")
	t.hp = t.max_hp(d) / 5
	check(e.expected_damage(rogue, t, "Melee") >= normal * 2.0 - 0.01, "execute: x2 under 25% HP")
	var ghost := _unit("Ghost")
	var brute := _unit("Fighter")
	brute.stats["STR"] = 60
	var g := _battle([brute], [ghost], "forest")
	var plain_target := _unit("Ghost")
	check_eq(g.expected_damage(brute, ghost, "Melee"), maxf(1.0, (60 - ghost.stats["PDEF"])) * 0.5, "incorporeal: half physical")
	var stone := _unit("Stoneguard")
	var caster := _unit("Apprentice")  # can't lead, so no aura
	caster.stats["INT"] = 60
	var s := _battle([caster], [stone], "forest")
	check_eq(s.expected_damage(caster, stone, "Magic"), maxf(1.0, (60 - stone.stats["MDEF"])) * 1.5, "stoneskin: x1.5 magic")
	var xbow := _unit("Crossbowman")
	xbow.stats["STR"] = 30
	var x := _battle([xbow], [k], "forest")
	check_eq(x.expected_damage(xbow, k, "Ranged"), 30.0 - k.stats["PDEF"] * 0.5, "armor-piercing ignores half PDEF")


func test_riposte_drain_regenerate() -> void:
	var sword := _tough(_unit("Swordfighter"))
	var f := _tough(_unit("Fighter"))
	var b := _battle([f], [sword])
	b._misses[f] = 3
	b._misses[sword] = 3
	b._attack(f, "Melee", sword)
	check(b.events.any(func(e): return e["unit"] == sword and e.get("type") == "attack"), "riposte counters a melee hit")
	var bat := _unit("Vampire Bats")
	bat.hp = 2
	bat.stats["STR"] = 200
	var c := _battle([bat], [_tough(_unit("Knight"))])
	c._misses[bat] = 3
	c._attack(bat, "Melee", c.sides[1].units[0])
	check(bat.hp > 2, "drain heals from damage dealt")
	var troll := _unit("Trollboy")
	troll.hp -= 30
	var t := _battle([troll], [_unit("Fighter")])
	var hp := troll.hp
	t._start_round()
	check_eq(troll.hp, hp + roundi(troll.max_hp(d) * 0.05), "regenerate: 5% per round")


func test_evasion_mirage_petrify() -> void:
	var shade := _unit("Shade")
	var f := _unit("Fighter")
	var day := _battle([f], [shade], "plains", 1, true)
	var night := _battle([f], [shade], "plains", 1, false)
	check_eq(night.hit_chance(f, shade), day.hit_chance(f, shade) - 25.0, "night evasion: +25% dodge at night")
	var djinn := _tough(_unit("Djinn"))
	var a := _unit("Fighter")
	var m := _battle([a], [djinn])
	m._misses[a] = 3
	m._attack(a, "Melee", djinn)
	check(not m.events[-1]["hit"], "mirage: the first hit misses")
	m._misses[a] = 3
	m._attack(a, "Melee", djinn)
	check(m.events[-1]["hit"], "only the first")
	var petrified := 0
	for seed in 200:
		var bas := _unit("Basilisk", "back")
		var k := _tough(_unit("Knight"))
		var p := _battle([bas], [k], "plains", seed)
		p._misses[bas] = 3
		p._attack(bas, "Breath", k)
		if p.has_status(k, "petrify"):
			petrified += 1
	check(petrified > 25 and petrified < 75, "petrify: about 25%% of breaths stun (%d of 200)" % petrified)


func test_pack_swarm_tamer_nullify() -> void:
	var w := _unit("Arctic Wolf")
	var b := _battle([_unit("Knight", "back"), w, _unit("Wolf"), _unit("Wolfhound"), _unit("Ember Wolf", "back")], [_unit("Knight")])  # the knight leads, so no Pack aura
	check_eq(b.attack_count(w), int(d.units["Arctic Wolf"]["front_count"]) + 2, "pack: +1 per other wolf, capped at +2 (§21)")
	var rat := _unit("Rat")
	var r := _battle([rat, _unit("Giant Rat"), _unit("Bat")], [_unit("Knight")])
	check_eq(r.attack_count(rat), int(d.units["Rat"]["front_count"]) + 2, "swarm: +1 per other Tiny")
	var lion := _unit("Lion")
	var t := _battle([_unit("Knight", "back"), _unit("Tamer"), lion], [_unit("Knight")])  # the knight leads, so no Pack lead aura
	check_eq(t.attack_count(lion), int(d.units["Lion"]["front_count"]) + 1, "tamer: large beasts +1 front attack")
	var mage := _unit("Mage")
	var n := _battle([mage], [_tough(_unit("Spellbreaker"))])
	n.round = 1
	n._turn(mage)
	check(n.events[-1]["text"].contains("Nullify"), "nullify: enemy magic does nothing in round 1")


# --- Leader auras ----------------------------------------------------------------------------

func _led_by(leader_class: String, others: Array) -> Array:
	return [_unit(leader_class)] + others


func test_stat_auras() -> void:
	var k := _unit("Fighter")
	var b := _battle(_led_by("Soldier", [k]), [_unit("Fighter")])  # Soldier: Hold the line
	var aura: String = d.units["Soldier"]["leader_aura"]
	check_eq(aura, "Hold the line", "the soldier's aura")
	check_eq(b.stat(k, "PDEF"), k.stats["PDEF"] * 1.1, "squad +10% PDEF")
	var sentinel_aura: String = d.units["Sentinel"]["leader_aura"]
	if sentinel_aura == "Hold the line":
		var s := _battle(_led_by("Sentinel", [k]), [_unit("Fighter")])
		check_eq(s.stat(k, "PDEF"), k.stats["PDEF"] * 1.15, "stage 4 leader: x1.5 strength")
	var foe := _unit("Knight")
	var dr := _battle(_led_by("Dragon", []), [foe])  # Dragonfear: enemy -10% SPD, AGI
	check_eq(dr.stat(foe, "SPD"), foe.stats["SPD"] * 0.9, "dragonfear slows the enemy")
	dr.sides[0].leader.hp = 0
	check_eq(dr.stat(foe, "SPD"), float(foe.stats["SPD"]), "no aura once the leader falls")


func test_combat_auras() -> void:
	var k := _unit("Knight")  # Holy vow: +10% damage by day
	var f := _unit("Fighter")
	var foe := _unit("Soldier")
	var day := _battle([k, f], [foe], "forest", 1, true)
	var night := _battle([k, f], [foe], "forest", 1, false)
	f.alignment = 50
	f.stats["STR"] = 40
	check(day.expected_damage(f, foe, "Melee") > night.expected_damage(f, foe, "Melee"), "holy vow: more damage by day")
	var lancer_squad := _battle(_led_by("Lancer", [_unit("Squire")]), [_unit("Fighter", "front", "F")])  # Charge order
	var sq := lancer_squad.sides[0].units[1]
	var fast := lancer_squad.sides[1].units[0]
	sq.stats["SPD"] = 1
	fast.stats["SPD"] = 30
	check_eq(lancer_squad.side_of(lancer_squad.turn_order(true)[0]), 0, "charge order: the squad acts first in round 1")


func test_round_one_extra_attacks() -> void:
	var leader := ""
	for c in d.units:
		if d.units[c].get("leader_aura") == "Volley":
			leader = c
			break
	var archer := _unit("Bowman", "back")
	var b := _battle(_led_by(leader, [archer]), [_tough(_unit("Knight"))])
	var order := b.turn_order(true)
	check_eq(order.count(archer), 2, "volley: back row acts twice in round 1")
	check_eq(b.attack_count(archer), int(d.units["Bowman"]["back_count"]) + 1, "with one extra attack")


func test_every_battle_aura_runs() -> void:
	for c in d.units:
		var aura = d.units[c].get("leader_aura")
		if aura == null:
			continue
		var rng_seed: int = c.hash()
		var ours := [_unit(c), _unit("Fighter"), _unit("Acolyte", "back")]
		var theirs := [_unit("Knight"), _unit("Fighter"), _unit("Mage", "back")]
		var b := _battle(ours, theirs, "plains", rng_seed)
		b.run()
		b.finish()
		check(not b.events.is_empty(), "%s (%s): the battle played" % [c, aura])


func test_every_class_fights() -> void:
	for c in d.units:
		var front := _battle([_unit(c, "front")], [_unit("Knight")], "plains", c.hash())
		front.run()
		var back := _battle([_unit("Knight"), _unit(c, "back")], [_unit("Knight")], "plains", c.hash())
		back.run()
		check(front.round > 0 and back.round > 0, "%s fights in both rows" % c)


func test_special_auras() -> void:
	var occ := _unit("Occultist", "back")  # Grave pact
	var f := _unit("Fighter", "front", "F")
	var g := _battle([occ, f], [_unit("Knight")])
	g._misses[g.sides[1].units[0]] = 3
	f.hp = 1
	g._attack(g.sides[1].units[0], "Melee", f)
	check(g.events.any(func(e): return e["type"] == "raise" and e["unit"] == f), "grave pact: the first fallen rises as a Skeleton")
	g.finish()
	check(g.sides[0].units.all(func(u: Unit): return u.name != "Skeleton"), "and leaves after the battle")
	var spirit := _unit("Spiritaur")  # Remount: mounted units heal 10% after battle
	var squire := _unit("Squire")
	squire.hp -= 10
	var r := _battle([spirit, squire], [_unit("Knight")])
	var hp := squire.hp
	r.finish()
	check_eq(squire.hp, hp + roundi(squire.max_hp(d) * 0.1), "remount heals mounted units after battle")
	var ronin := _unit("Ronin")  # Discipline: immune to debuffs in round 1
	var dis := _battle([ronin], [_unit("Enchantress", "back")])
	dis.round = 1
	check(not dis.add_status(ronin, "str_down"), "discipline blocks debuffs in round 1")
	dis.round = 2
	check(dis.add_status(ronin, "str_down"), "but not later")
	var rogue := _tough(_unit("Rogue"))  # Ambush: the enemy can't counter in round 1
	var sword := _tough(_unit("Swordfighter"))
	var am := _battle([rogue], [sword])
	am.round = 1
	am._misses[rogue] = 3
	am._attack(rogue, "Melee", sword)
	check(not am.events.any(func(e): return e["unit"] == sword), "ambush: no riposte in round 1")
	var fm := _unit("Fire Mage")  # Attunement: squad melee carries the leader's element
	var fighter := _unit("Fighter")
	var at := _battle([fm, fighter], [_unit("Knight")])
	check_eq(at.attack_element(fighter, "Melee"), "Fire", "attunement: melee carries the leader's element")
