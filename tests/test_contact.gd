extends TestCase
## Enemy squads, contact, ranged map attacks and sight (SPEC §8.5, §11.1–11.2, §17).

var d := GameData.load_dir()


## A plains strip map with the player base on the left and the enemy base on the right.
func _state(w := 30, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 3
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _ours(st: GameState, col: int, row := 4, members := [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]]) -> Squad:
	return st.add_squad("Ours", _at(st.map, col, row), members)


func _theirs(st: GameState, col: int, row := 4, members := [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]]) -> Squad:
	return st.add_squad("Theirs", _at(st.map, col, row), members, "enemy")


func test_enemy_placement() -> void:
	var m := MapGen.generate(d, 11, {"size": "small"})
	var st := GameState.new(d, m, GameLog.new())
	st.place_enemies()
	var enemies := st.squads.filter(func(s: Squad): return s.side == "enemy")
	var towns := m.buildings.filter(func(b): return b["type"] == "town").size()
	check_eq(enemies.size(), maxi(3, roundi(towns * 0.5)), "half as many squads as towns (%d)" % towns)
	var roles := {}
	for s in enemies:
		roles[s.role] = roles.get(s.role, 0) + 1
		check_eq(s.units.size(), 4, "%s: four units" % s.name)
		check(not s.units.any(func(u: Unit): return Battle.base_kind(u.info(d)["back_attack" if u.row == "back" else "front_attack"]) == "Heal"),
				"%s: no healers" % s.name)
		check(s.id > 100, "enemy squads are numbered from 101")
		check_eq(s.hex, m.enemy_base, "%s starts on the Enemy Base" % s.name)
	check_eq(roles, {"leader": 1, "base_guard": 1, "field": enemies.size() - 2}, "roles")
	for b in m.buildings:
		if b["type"] not in ["player_base", "enemy_base"] and b.has("owner"):
			check_eq(b["owner"], "neutral", "%s starts neutral" % b["type"])
	var bare := MapData.new(10, 10)
	bare.settings = {"preset": "continent", "size": "small"}
	var few := GameState.new(d, bare, GameLog.new())
	check_eq(few.enemy_squad_count(), 3, "at least 3 squads with no towns")


func test_adjacency_triggers_battle() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 14)
	st.step()
	check(st.pending == null, "no battle at a distance")
	st.order_move(ours, PackedInt32Array([_at(st.map, 13, 4)]))
	var ticks := 0
	while st.pending == null and ticks < 200:
		st.step()
		ticks += 1
	check(st.pending != null, "moving next to an enemy starts a battle")
	check_eq(Hex.distance(st.map.hex_at(ours.hex), st.map.hex_at(theirs.hex)), 1, "they're adjacent")
	check_eq(st.pending.attacker, 0, "the squad that moved in attacks")
	var tick := st.clock.tick
	st.step()
	check_eq(st.clock.tick, tick, "the map holds while a battle is pending")
	var text: String = st.resolve_pending()["text"]
	check(text.begins_with(ours.name) and text.contains("battle"), "a summary comes back: " + text)
	check(st.pending == null, "the battle is resolved")


## An enemy listed before the player's squad walks into it: the player is still side 0,
## so the battle view, tactic and outcome text read the right squad as "us".
func test_player_is_side_zero_when_attacked() -> void:
	var st := _state()
	var theirs := _theirs(st, 14)
	var ours := _ours(st, 10)
	st.order_move(theirs, PackedInt32Array([_at(st.map, 11, 4)]))
	var ticks := 0
	while st.pending == null and ticks < 200:
		st.step()
		ticks += 1
	check(st.pending != null, "the enemy walks into contact")
	check(st.pending.sides[0] == ours, "the player's squad is side 0")
	check_eq(st.pending.attacker, 1, "the enemy, side 1, attacks")


## Squad 1 marches past an enemy that lies off its route; the battle's outcome is set by hand.
func _contact_on_the_march() -> Array:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 13, 3)
	st.order_move(ours, PackedInt32Array([_at(st.map, 18, 4)]))
	for i in 200:
		if st.pending:
			break
		st.step()
	check(st.pending != null, "contact on the march")
	check(ours.is_moving(), "orders survive contact")
	return [st, ours, theirs]


func test_orders_continue_unless_knocked_back() -> void:
	var r := _contact_on_the_march()
	var ours: Squad = r[1]
	for u in r[2].units:  # they lose more HP, but aren't wiped out
		u.hp = maxi(1, u.hp / 2)
	var out: Dictionary = r[0].end_battle(r[0].pending)
	check_eq(out["pushed"], 1, "the enemy is pushed back")
	check(ours.is_moving(), "the winner keeps its orders")
	r = _contact_on_the_march()
	for u in r[1].units:  # we lose more HP
		u.hp = maxi(1, u.hp / 2)
	out = r[0].end_battle(r[0].pending)
	check_eq(out["pushed"], 0, "we're pushed back")
	check(not r[1].is_moving(), "a squad knocked back stops")


func test_same_side_and_cooldown() -> void:
	var st := _state()
	_ours(st, 10)
	_ours(st, 11)
	st.step()
	check(st.pending == null, "friendly squads don't fight")
	var st2 := _state()
	var o := _ours(st2, 10)
	var t := _theirs(st2, 11)
	st2.step()
	check(st2.pending != null, "standing next to an enemy starts a battle")
	check_eq(st2.pending.attacker, 0, "if neither moved, your squad attacks")
	for u in t.units:  # make sure neither side can push the other away
		u.stats["STR"] = 0
	for u in o.units:
		u.stats["STR"] = 0
	st2.resolve_pending()
	if Hex.distance(st2.map.hex_at(o.hex), st2.map.hex_at(t.hex)) <= 1:
		st2.step()
		check(st2.pending == null, "a pair that just fought waits before fighting again")
		for i in int(d.enemy["contact_cooldown_ticks"]) + 1:
			if st2.pending:
				break
			st2.step()
		check(st2.pending != null, "and fights again after the cooldown if still adjacent")


func test_friendly_squads_share_hexes() -> void:
	var st := _state()
	var a := _ours(st, 5)
	var b := _ours(st, 7)
	st.order_move(a, PackedInt32Array([_at(st.map, 9, 4)]))
	for i in 200:
		st.step()
	check_eq(a.hex, _at(st.map, 9, 4), "a squad passes through a friendly squad's hex")
	st.order_move(a, PackedInt32Array([_at(st.map, 7, 4)]))
	for i in 200:
		st.step()
	check_eq(a.hex, b.hex, "and can stop on it: your squads share hexes")


func test_sight() -> void:
	var st := _state()
	var walker := _ours(st, 5)  # plains squad on plains: 7 + 1
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 8, "7, +1 on its travel terrain")
	st.map.terrain[_at(st.map, 10, 4)] = d.terrain_ids["mountain"]
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 6, "-2 into mountains")
	st.map.terrain[_at(st.map, 10, 4)] = d.terrain_ids["forest"]
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 7, "-1 into forest")
	st.map.terrain[walker.hex] = d.terrain_ids["swamp"]
	st.map.terrain[_at(st.map, 10, 4)] = d.terrain_ids["mountain"]
	check_eq(st.sight(walker, _at(st.map, 10, 4)), 5, "7 - 1 - 2 = 4, clamped to 5")
	var flyer := st.add_squad("Wings", _at(st.map, 3, 2), [["Eagle Knight", "front"], ["Eagle Rider", "front"]])
	check(flyer.sky, "a flying squad")
	check_eq(st.sight(flyer, _at(st.map, 9, 2)), 10, "7 + 2 + 1 = 10, the cap")


func test_hidden_enemies() -> void:
	var st := _state(40)
	_ours(st, 2)
	var far := _theirs(st, 25)
	var near := _theirs(st, 8)
	check(not st.is_visible(far), "an enemy beyond sight is hidden")
	check(st.is_visible(near), "an enemy within sight shows")
	check(st.is_visible(st.squads[0]), "your own squads always show")


func test_hidden_sites_reveal() -> void:
	var st := _state(40)
	st.map.buildings.append({"type": "hidden_site", "hex": _at(st.map, 20, 4), "shop": false, "hint": false, "hidden": true, "kind": "treasure", "road": false})
	var ours := _ours(st, 2)
	st.step()
	check(st.revealed.is_empty(), "a hidden site out of sight stays hidden")
	ours.hex = _at(st.map, 15, 4)
	st.step()
	check(st.revealed.has(st.map.buildings.size() - 1), "it reveals once in sight")


func test_fire_range() -> void:
	var st := _state()
	var archers := _ours(st, 10)
	var near := _theirs(st, 12)
	var far := _theirs(st, 13)
	check_eq(st.fire_range(archers), 2, "2 hexes on flat ground")
	check(near in st.fire_targets(archers) and far not in st.fire_targets(archers), "targets within 2")
	st.map.terrain[archers.hex] = d.terrain_ids["mountain"]
	check_eq(st.fire_range(archers), 3, "3 from mountains")
	check(far in st.fire_targets(archers), "now 3 hexes away is in range")
	st.map.terrain[archers.hex] = d.terrain_ids["plains"]
	st.map.buildings.append({"type": "tower", "hex": archers.hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	check_eq(st.fire_range(archers), 3, "3 from a tower")
	archers.at("back", 0).items["weapon"] = {"uid": 1, "id": "longbow"}
	check_eq(st.fire_range(archers), 4, "a longbow adds 1 (§11.2)")
	var melee := _ours(st, 11, 7, [["Knight", "front"], ["Fighter", "front"]])
	check(not st.can_fire(melee), "a squad without ranged or magic units can't fire")
	check(st.fire_targets(melee).is_empty(), "so it has no targets")


func test_ranged_attack() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 12)
	var spot := theirs.hex
	st.fire(ours, theirs)
	check(st.pending != null and st.pending.ranged_only, "a ranged attack waits for the battle view like contact")
	var text: String = st.resolve_pending()["text"]
	check(text.begins_with(ours.name), "a summary comes back: " + text)
	check_eq(theirs.hex, spot, "no push-back after a ranged attack")
	check(st.fire_targets(ours).is_empty(), "the squad must reload")
	check_eq(ours.fire_ready, st.clock.tick + int(d.rules["ranged_attack"]["cooldown_ticks"]), "120-tick cooldown")
	for i in int(d.rules["ranged_attack"]["cooldown_ticks"]):
		st.clock.step()
	check(not st.fire_targets(ours).is_empty(), "ready again after the cooldown")


func test_only_ranged_units_act() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 12)
	var b := st.start_battle(ours, theirs, theirs)
	b.ranged_only = true
	for side in 2:
		for u in b.sides[side].living():
			b._join(u)
	b.run()
	for e in b.events:
		if e["type"] == "attack":
			check(b.fires_at_range(e["unit"]), "%s (%s) acted in a ranged attack" % [e["unit"].name, e["unit"].unit_class])
	var out := b.finish()
	check_eq(out["pushed"], -1, "no push-back")


func test_battle_log_lines() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 11)
	var b := st.start_battle(ours, theirs, theirs)
	b.run()
	var acts := b.events.filter(func(e): return e["type"] != "round")
	st.pending = b
	st.resolve_pending()
	var lines := st.log.filtered("battle").map(func(e): return e["text"])
	check("-- Round 1 --" in lines, "rounds are marked")
	for e in acts:
		var line := b.log_line(e)
		check(line in lines, "every action is logged: " + line)
		check(line.begins_with("[%s]" % b.sides[e["side"]].name), "tagged with the acting squad: " + line)
	var attack: Dictionary = acts.filter(func(e): return e["type"] == "attack")[0]
	check(attack["text"].contains("(%s)" % attack["unit"].unit_class), "names carry the class: " + attack["text"])
	var logged: Dictionary = st.log.filtered("battle").filter(func(e): return e["text"] == b.log_line(attack))[0]
	check(logged["hidden"].has("hit_chance") and logged["hidden"].has("roll"), "hit chance and roll are kept as hidden values")


## Use item in the encounter popup (user's playtest notes, 2026-11-10): a unit revived
## or healed after the battle is set up, but before it starts, fights and counts.
func test_supplies_used_before_the_battle_count() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 11)
	var fallen := ours.units[2]
	fallen.hp = 0
	ours.units[1].hp = 5
	st.army.supplies = {"revive": 1, "herb": 1}
	var b := st.start_battle(ours, theirs, theirs)
	check(fallen not in b.fought[0], "set up with the unit fallen")
	check(st.use_supply_before_battle(b, fallen, "revive"), "revived from the popup")
	check(st.use_supply_before_battle(b, ours.units[1], "herb"), "healed from the popup")
	check(fallen in b.fought[0], "the revived unit is in the battle")
	check_eq(b.hp_lost_share(0), 0.0, "starting HP counts the revival and the herb")
	b.run()
	check(b.events.any(func(e): return e["type"] == "attack" and e["unit"] == fallen) or not fallen.is_alive(), "and it acts in the battle")


## Playtest round 7: after a fight the player can see the enemy squad's makeup.
func test_a_fight_shows_the_enemy_makeup() -> void:
	var st := _state()
	var ours := _ours(st, 10)
	var theirs := _theirs(st, 11)
	check(not st.intel.has(theirs.id), "unknown before any fight")
	st.pending = st.start_battle(ours, theirs, theirs)
	st.resolve_pending()
	if theirs in st.squads:
		var seen: Dictionary = st.intel[theirs.id]
		check_eq(seen["units"].size(), theirs.units.size(), "every unit seen")
		check_eq(seen["units"].map(func(u): return u["class"]), theirs.units.map(func(u: Unit): return u.unit_class), "classes as they are")
		check_eq(seen["units"].map(func(u): return u["alive"]), theirs.units.map(func(u: Unit): return u.is_alive()), "and who stood at the end")


## Playtest round 7: when one of your parties stops, the log and the HUD say so.
func test_a_party_stopping_is_announced() -> void:
	var st := _state()
	var ours := _ours(st, 3)
	st.order_move(ours, PackedInt32Array([_at(st.map, 6, 4)]))
	for i in 2000:
		st.step()
		if not ours.is_moving():
			break
	check(not ours.is_moving(), "it arrived")
	check_eq(st.notices, ["%s has stopped at %s." % [ours.name, st.map.hex_at(ours.hex)]] as Array[String], "a notice for the HUD")
	check(st.log.entries.any(func(e): return "has stopped at" in str(e["text"])), "and a log line")
