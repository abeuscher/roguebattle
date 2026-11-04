extends TestCase
## Cards: every effect, drawing, Seer and Oracle choices, Foresight, map cards and the
## card XP redirect (SPEC §13, §9.4).

var d := GameData.load_dir()


func _unit(c: String, row := "front") -> Unit:
	var u := Unit.new()
	u.unit_class = c
	u.name = c
	for s in Unit.STATS:
		u.stats[s] = int(d.units[c]["base_stats"][s])
	u.hp = u.max_hp(d)
	u.row = row
	return u


func _squad(units: Array) -> Squad:
	var s := Squad.new(1, "S", 0)
	for u in units:
		s.units.append(u)
		if s.leader == null and u.info(d)["can_lead"]:
			s.leader = u
	s.refresh(d)
	return s


func _battle(a: Array, b: Array) -> Battle:
	var rng := RandomNumberGenerator.new()
	rng.seed = 4
	return Battle.new(d, _squad(a), _squad(b), "forest", true, rng)


func test_stat_boost_lasts_until_the_leaders_second_turn() -> void:
	var knight := _unit("Knight")
	var fighter := _unit("Fighter")
	var b := _battle([knight, fighter], [_unit("Soldier")])
	var base := b.stat(fighter, "STR")
	check(b.play_card("panther"), "play Panther")
	check(is_equal_approx(b.stat(fighter, "STR"), base * 1.3), "+30% STR")
	b._act(knight)
	check(is_equal_approx(b.stat(fighter, "STR"), base * 1.3), "still on after the leader's first turn")
	b._act(knight)
	check(is_equal_approx(b.stat(fighter, "STR"), base), "gone on the leader's second turn")


func test_heals() -> void:
	var a := _unit("Knight")
	var f := _unit("Fighter")
	var b := _battle([a, f], [_unit("Soldier")])
	f.hp = 1
	b.play_card("dolphin")
	check_eq(f.hp, mini(51, f.max_hp(d)), "Dolphin: +50 HP")
	f.hp = 1
	b.play_card("whale")
	check_eq(f.hp, f.max_hp(d), "Whale: full")
	f.hp = 1
	b.play_card("narwhal")
	check_eq(f.hp, 1 + 2 * 10, "Narwhal: two heals at the squad's average level (1) × 10")
	b.play_card("elephant")
	check_eq(a.hp, a.max_hp(d) + roundi(a.max_hp(d) * 0.3), "Elephant: 30% more, even above full")
	b.finish()
	check_eq(a.hp, a.max_hp(d), "back to full at the end of the battle")


func test_walrus_cleanses() -> void:
	var f := _unit("Fighter")
	var b := _battle([f], [_unit("Soldier")])
	b.add_status(f, "poison")
	b.play_card("walrus")
	check(not b.has_status(f, "poison"), "Walrus clears harmful statuses")


func test_attack_cards() -> void:
	var foe := _unit("Soldier")
	var other := _unit("Fighter")
	var b := _battle([_unit("Knight")], [foe, other])
	var hp := [foe.hp, other.hp]
	b.play_card("tiger")
	check(foe.hp < hp[0] and other.hp < hp[1], "Tiger hits the whole enemy squad")
	check_eq(b.card_damage, hp[0] - foe.hp + hp[1] - other.hp, "card damage is counted")
	foe.hp = foe.max_hp(d)
	b.play_card("angelfish")
	check(b.has_status(foe, "shock"), "Angelfish shocks")
	var water := _unit("Mermaid")
	var b2 := _battle([_unit("Knight")], [water])
	var before := water.hp
	b2.play_card("crocodile")
	var same := before - water.hp
	water.hp = before
	b2.play_card("rhino")
	check(same < before - water.hp or d.units["Mermaid"]["element"] != "Water", "water hits a water unit less hard than earth does")


func test_weakness_cards() -> void:
	var foe := _unit("Soldier")
	var b := _battle([_unit("Knight")], [foe])
	b.play_card("mouse")
	check(b.has_status(foe, "weak_physical"), "Mouse: weak to physical")
	b.play_card("mink")
	check(b.has_status(foe, "weak_magic"), "Mink: weak to magic")


func test_environment_cards() -> void:
	var k := _unit("Knight")
	var b := _battle([k, _unit("Fighter")], [_unit("Soldier")])
	check_eq(b.terrain["key"], "forest", "fought in a forest")
	check(b.play_card("chameleon"), "play Chameleon")
	check_eq(b.terrain["key"], "plains", "now it plays as the Knight's squad's home terrain")
	b.play_card("sloth")
	check(b._lose_turn[1], "Sloth: the enemy loses its next action")
	var attacks: int = b._attacks[k]
	b.play_card("unicorn")
	check_eq(b._attacks[k], attacks + 1, "Unicorn: one extra attack each")
	check(not b.play_card("rooster"), "Rooster isn't a battle card")


func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 12
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(2, 3)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(28, 3)))
	m.buildings.append({"type": "town", "hex": m.index_of(Hex.from_offset(Vector2i(8, 3))), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	st.setup_army()
	return st


func test_hand_and_draws() -> void:
	var st := _state()
	check_eq(st.cards.size(), 3, "3 cards to start")
	var next := st.next_card
	var s := st.player_squads()[0]
	s.hex = st.map.buildings[0]["hex"]
	for i in int(d.rules["capture"]["ticks"]):
		st.step()
	check_eq(st.cards.size(), 4, "a liberation draws a card")
	check_eq(st.cards[-1], next, "the card Foresight would have shown")


func test_seer_and_oracle_choose() -> void:
	var st := _state()
	var s := st.add_squad("Seers", 0, [["Seer", "front"]])
	st.draw_card(s)
	check_eq(st.card_offer.size(), 2, "a Seer chooses from 2")
	var pick := st.card_offer[1]
	var held := st.cards.size()
	st.choose_card(pick)
	check(st.card_offer.is_empty() and st.cards.size() == held + 1 and st.cards[-1] == pick, "the chosen card joins the hand")
	var o := st.add_squad("Oracles", 0, [["Oracle", "front"]])
	st.draw_card(o)
	check_eq(st.card_offer.size(), 3, "an Oracle chooses from 3")


func test_foresight() -> void:
	var st := _state()
	check(not st.foresight(), "no Foresight leader on the map")
	st.add_squad("Seers", st.map.player_base, [["Seer", "front"]])
	check(st.foresight(), "a Seer leading a squad on the map previews the next card")


func test_rooster_and_fox() -> void:
	var st := _state()
	st.cards.append("rooster")
	st.cards.append("fox")
	check(st.clock.minute_of_day() < 720, "morning")
	var gold := st.gold
	check(st.play_map_card("rooster"), "play Rooster")
	check_eq(st.clock.minute_of_day(), 720, "noon")
	check(st.gold < gold, "the noon ledger ran on the way")
	check(st.play_map_card("fox"), "play Fox")
	check_eq(st.clock.minute_of_day(), 0, "midnight")
	check(not st.play_map_card("fox"), "it's used up")


func test_card_xp_goes_to_the_opinion_leader() -> void:
	var st := _state()
	var ol := st.opinion_leader_squad()
	var fighting: Squad = st.army.cells[1]
	st.squads.append(fighting)
	fighting.hex = st.map.index_of(Hex.from_offset(Vector2i(5, 3)))
	var foe := st.add_squad("Them", st.map.index_of(Hex.from_offset(Vector2i(6, 3))), [["Fighter", "front"]], "enemy")
	var b := st.start_battle(fighting, foe, foe)
	st.cards.append("tiger")
	check(st.play_battle_card(b, "tiger"), "play Tiger from the hand")
	check("tiger" not in st.cards, "it leaves the hand")
	foe.units[0].hp = 0  # the rest of the enemy's losses come from the fight
	var ol_xp := ol.units[1].xp
	var full := Progression.battle_xp(d, fighting, foe, fighting.units[1])
	var out := st.end_battle(b)
	check(out["xp"][fighting.units[1]] < full, "the fighting squad gets less than the full %d" % full)
	check(ol.units[1].xp > ol_xp, "the Opinion Leader's squad gets the card share")
