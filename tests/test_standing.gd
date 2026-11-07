extends TestCase
## Reputation, charisma and alignment: every change event, price scaling and the
## recruit chance (SPEC §9.5, §9.6, §10, §16).

var d := GameData.load_dir()


## A plains strip with a town at (8, 3) and a tower at (12, 3).
func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 9
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 2, 3)
	m.enemy_base = _at(m, 28, 3)
	m.buildings.append(_b("town", _at(m, 8, 3)))
	m.buildings.append(_b("tower", _at(m, 12, 3)))
	return GameState.new(d, m, GameLog.new())


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": true, "hint": false, "hidden": false, "kind": "", "road": false}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


## A player squad on the strip whose units all have the given alignment.
func _squad(st: GameState, col: int, alignment: int, members := [["Knight", "front"], ["Fighter", "front"]]) -> Squad:
	var s := st.add_squad("Ours", _at(st.map, col, 3), members)
	for u in s.units:
		u.alignment = alignment
	st.army.cells[st.army.cells.find(null)] = s
	return s


func _liberate(st: GameState) -> void:
	for i in int(d.rules["capture"]["ticks"]):
		st.step()


func test_liberating_a_town() -> void:
	var st := _state()
	var holy := _squad(st, 8, 80)
	var cha := holy.leader.charisma
	_liberate(st)
	check_eq(st.reputation, 55, "a holy squad liberating a town: +5 reputation")
	check_eq(holy.leader.charisma, cha + 5, "its holy leader: +5 charisma")
	check_eq(holy.units[1].alignment, 83, "each unit +3 alignment for a town")


func test_liberating_a_tower() -> void:
	var st := _state()
	var holy := _squad(st, 12, 80)
	var cha := holy.leader.charisma
	_liberate(st)
	check_eq(st.reputation, 45, "a holy squad liberating a tower: −5")
	check_eq(holy.leader.charisma, cha, "no charisma: the tower doesn't match a holy leader")
	check_eq(holy.units[1].alignment, 77, "each unit −3 alignment for a tower")
	var st2 := _state()
	var evil := _squad(st2, 12, 20)
	_liberate(st2)
	check_eq(st2.reputation, 55, "an evil squad liberating a tower: +5")
	var st3 := _state()
	_squad(st3, 8, 50)
	_liberate(st3)
	check_eq(st3.reputation, 50, "a neutral squad: no change")


## Queued for the battlemap to show a focused popup (user request, 2026-11-07).
func test_liberation_is_queued_for_the_ui() -> void:
	var st := _state()
	check(st.liberations.is_empty(), "nothing queued yet")
	_squad(st, 8, 80)
	_liberate(st)
	check_eq(st.liberations.size(), 1, "one liberation queued")
	var entry: Dictionary = st.liberations[0]
	check_eq(entry["building"]["hex"], _at(st.map, 8, 3), "the building that was taken")
	check_eq(entry["card"], st.cards[-1], "the card it drew, for the same popup")
	check(st.card_offer.is_empty(), "no Seer/Oracle here: straight into the hand, no offer")


## A Seer offers a choice instead of drawing straight into the hand (§13); the queued
## entry leaves "card" empty so the UI reads the choice from card_offer instead.
func test_liberation_with_a_seer_queues_an_offer_not_a_card() -> void:
	var st := _state()
	_squad(st, 8, 80, [["Knight", "front"], ["Seer", "back"]])
	_liberate(st)
	check_eq(st.liberations.size(), 1, "one liberation queued")
	check_eq(st.liberations[0]["card"], "", "no card drawn directly: it's an offer")
	check_eq(st.card_offer.size(), 2, "a Seer chooses from 2")


func test_black_market_doubles_swings() -> void:
	var st := _state()
	_squad(st, 8, 80, [["Knight", "front"], ["Fence", "back"]])
	_liberate(st)
	check_eq(st.reputation, 60, "a Fence doubles the +5")


func test_staying_in_a_town() -> void:
	var st := _state()
	var holy := _squad(st, 8, 80)
	st.map.buildings[0]["owner"] = "player"
	st.clock.tick = GameClock.TICKS_PER_DAY - 1
	st.step()
	check_eq(st.reputation, 51, "a day in a town: +1 for a holy squad")
	holy.hex = _at(st.map, 12, 3)
	st.map.buildings[1]["owner"] = "player"
	st.clock.tick = 2 * GameClock.TICKS_PER_DAY - 1
	st.step()
	check_eq(st.reputation, 50, "a day in a tower: −1")


func test_battle_alignment_and_charisma() -> void:
	var st := _state()
	var ours := _squad(st, 5, 50)
	var foe := st.add_squad("Them", _at(st.map, 6, 3), [["Serf", "front"]], "enemy")
	var b := st.start_battle(ours, foe, foe)
	check_eq(b.odds, "Much weaker", "a lone Serf looks much weaker")
	var cha := ours.units[1].charisma
	foe.units[0].hp = 0
	st.end_battle(b)
	check_eq(ours.units[1].alignment, 48, "fighting a weaker squad: −2 alignment")
	check_eq(ours.units[1].charisma, maxi(0, cha - 1), "beating a much weaker squad: −1 charisma")
	var st2 := _state()
	var small := _squad(st2, 5, 50, [["Fighter", "front"]])
	var big := st2.add_squad("Them", _at(st2.map, 6, 3), [["Knight", "front"], ["Lancer", "front"], ["Soldier", "front"]], "enemy")
	var b2 := st2.start_battle(small, big, big)
	check(b2.odds in ["Stronger", "Dangerous"], "three leaders look stronger than a Fighter (%s)" % b2.odds)
	var cha2 := small.units[0].charisma
	for u in big.units:
		u.hp = 0
	st2.end_battle(b2)
	check_eq(small.units[0].alignment, 52, "fighting a stronger squad: +2 alignment")
	check_eq(small.units[0].charisma, cha2 + 1, "and beating it: +1 charisma")


func test_retreat_costs_charisma() -> void:
	var st := _state()
	var ours := _squad(st, 5, 50)
	var foe := st.add_squad("Them", _at(st.map, 6, 3), [["Knight", "front"]], "enemy")
	var cha := ours.units[1].charisma
	var b := st.start_battle(ours, foe, foe)
	b.retreated = 0
	st.end_battle(b)
	check_eq(ours.units[1].charisma, maxi(0, cha - 1), "−1 charisma for retreating")


func test_prices_scale_with_reputation() -> void:
	var st := _state()
	check_eq(st.price(100), 100, "reputation 50: list price")
	st.reputation = 100
	check_eq(st.price(100), 80, "reputation 100: −20%")
	st.reputation = 0
	check_eq(st.price(100), 120, "reputation 0: +20%")
	st.reputation = 50
	var smuggler := _squad(st, 5, 50, [["Knight", "front"], ["Smuggler", "back"]])
	var fence := _squad(st, 6, 50, [["Knight", "front"], ["Fence", "back"]])
	check_eq(st.price(100, smuggler), 90, "a Smuggler takes 10% off")
	check_eq(st.price(100, fence), 80, "a Fence 20%")


func test_recruit_chance() -> void:
	var st := _state()
	var s := _squad(st, 5, 50)
	check(is_equal_approx(st.recruit_chance(s, 1, 50.0), 0.6), "one neutral of the same alignment at reputation 50: 60%")
	check(is_equal_approx(st.recruit_chance(s, 4, 50.0), 0.6 * 6.0 / 9.0), "four units: × 6/9")
	check(is_equal_approx(st.recruit_chance(s, 1, 0.0), 0.3), "a 50-point alignment gap halves it")
	st.reputation = 100
	check(is_equal_approx(st.recruit_chance(s, 1, 50.0), 0.9), "reputation 100: × 1.5")
