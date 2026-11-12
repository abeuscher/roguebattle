extends TestCase
## Playtest round 9's rules and round 10's debt balance (ROADMAP M4 session 30): building
## sight, a second recruit chance after beating neutrals, the Phoenix card and card
## weights, shop spread and the rare item, debt and defeat by penury, and upkeep that
## scales with the map.

var d := GameData.load_dir()


func _state(towns := 0, seed := 9) -> GameState:
	var m := MapData.new(40, 12)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = seed
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 38, 4)
	for i in towns:
		m.buildings.append(_b("town", _at(m, 2 + i % 36, 11 - int(i / 36.0))))
	return GameState.new(d, m, GameLog.new())


func _b(type: String, hex: int) -> Dictionary:
	return {"type": type, "hex": hex, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false}


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


# --- Building sight ---------------------------------------------------------------------

func test_held_buildings_see_by_type() -> void:
	var st := _state()
	for type in ["tower", "temple", "town"]:
		st.map.buildings.clear()
		st.map.buildings.append(_b(type, _at(st.map, 10, 4)))
		var r := int(d.buildings[type]["sight"])
		var edge := _at(st.map, 10 + r, 4)
		var past := _at(st.map, 10 + r + 1, 4)
		st.map.buildings[0]["owner"] = "neutral"
		check(not st.seen(edge), "%s: not yours, it sees nothing" % type)
		st.map.buildings[0]["owner"] = "player"
		check(st.seen(edge) and not st.seen(past), "%s held: sees %d hexes" % [type, r])
	check(int(d.buildings["tower"]["sight"]) > int(d.buildings["temple"]["sight"]) and int(d.buildings["temple"]["sight"]) > int(d.buildings["town"]["sight"]),
			"towers furthest, temples middle, towns least")


func test_an_enemy_near_a_held_tower_shows() -> void:
	var st := _state()
	st.map.buildings.append(_b("tower", _at(st.map, 20, 4)))
	var foe := st.add_squad("Foe", _at(st.map, 23, 4), [["Soldier", "front"]], "enemy")
	st.map.buildings[0]["owner"] = "neutral"
	check(not st.is_visible(foe), "no squad of ours near: hidden")
	st.map.buildings[0]["owner"] = "player"
	check(st.is_visible(foe), "the held tower sees it")


# --- A second chance to recruit -----------------------------------------------------------

## A neutral band the player's squad beats (it runs) without wiping it out.
func _beaten_neutral(seed: int) -> Array:
	var st := _state(0, seed)
	st.reputation = 50  # about a 60% chance: both outcomes show up over the seeds
	var p := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"], ["Fighter", "front"]])
	var n := st.add_squad("Band", _at(st.map, 6, 4), [["Soldier", "front"]], "neutral")
	n.role = "roamer"
	n.units[0].alignment = roundi(p.alignment())
	n.units[0].hp = 7
	st.pending = st.start_battle(p, n, n)
	st.pending.retreated = 1  # they run: beaten, not wiped out
	st.resolve_pending()
	return [st, p, n]


func test_beaten_neutrals_can_be_asked_again_and_join_hurt() -> void:
	var joined := 0
	var refused := 0
	for seed in 40:
		var r := _beaten_neutral(seed)
		var st: GameState = r[0]
		var n: Squad = r[2]
		check(st.pending_recruit.get("beaten", false) and st.pending_recruit["neutral"] == n, "beaten: one more Recruit choice")
		check(n in st.squads, "they wait for the answer")
		var hp := n.units[0].hp
		var out := st.resolve_recruit(true)
		check(st.pending == null, "no second fight either way")
		check(n not in st.squads, "they leave the map either way")
		if out["joined"]:
			joined += 1
			check(n.units[0] in st.army.pool, "into the recruit pool")
			check_eq(n.units[0].hp, hp, "at the HP they had left")
		else:
			refused += 1
			check(n.units[0] not in st.army.pool, "a refusal sends them home")
	check(joined > 0 and refused > 0, "both outcomes happen (%d joined, %d refused)" % [joined, refused])


func test_letting_beaten_neutrals_go() -> void:
	var r := _beaten_neutral(1)
	var st: GameState = r[0]
	var n: Squad = r[2]
	var out := st.resolve_recruit(false)
	check(not out["joined"] and n not in st.squads and n.units[0] not in st.army.pool, "Let them go: they go home")


func test_a_lost_fight_gives_no_second_chance() -> void:
	var st := _state()
	var p := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"]])
	var n := st.add_squad("Band", _at(st.map, 6, 4), [["Soldier", "front"]], "neutral")
	n.role = "roamer"
	st.pending = st.start_battle(p, n, n)
	st.pending.retreated = 0  # we run
	st.resolve_pending()
	check(st.pending_recruit.is_empty(), "no Recruit choice after losing")
	check(n not in st.squads, "they go home as before")


# --- Phoenix and card weights ---------------------------------------------------------

func test_phoenix_revives_the_fallen_at_half_hp() -> void:
	var st := _state()
	var p := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"]])
	var foe := st.add_squad("Foe", _at(st.map, 6, 4), [["Soldier", "front"]], "enemy")
	var before := p.units[1]
	before.hp = 0  # fell before the battle
	var b := st.start_battle(p, foe, foe)
	var during := p.units[2]
	during.hp = 0  # falls in the battle
	check(b.play_card("phoenix"), "play Phoenix")
	for u in [before, during]:
		check_eq(u.hp, roundi(u.max_hp(d) * 0.5), "%s back at half HP" % u.name)
	check(b._attacks[before] > 0, "a unit that fell before the battle fights now")
	check_eq(p.units[0].hp, p.units[0].max_hp(d), "the living are untouched")


func test_rare_cards_are_drawn_rarely() -> void:
	var st := _state()
	var counts := {}
	var n := 6000
	for i in n:
		var id := st._roll_card()
		counts[id] = int(counts.get(id, 0)) + 1
	var cards: Dictionary = d.cards["cards"]
	var total := 0.0
	for id in cards:
		total += float(cards[id].get("weight", 1.0))
	var expect := n * float(cards["phoenix"]["weight"]) / total
	var got := int(counts.get("phoenix", 0))
	check(got > expect * 0.4 and got < expect * 2.0, "Phoenix about %d in %d draws: %d" % [roundi(expect), n, got])
	check(got * 2 < int(counts.get("panther", 0)), "far rarer than an ordinary card")


# --- Shops -------------------------------------------------------------------------------

func test_shops_vary_and_one_holds_a_rare_item() -> void:
	var st := _state(30)
	for b in st.map.buildings:
		b["shop"] = true
	st = GameState.new(d, st.map, GameLog.new())  # the rare item is placed when the map begins
	var kinds := []
	var counts := []
	var rare := 0
	for b in st.map.buildings:
		var stock := st.shop_stock(b)
		var items: Array = stock.keys().filter(func(k): return d.items["items"].has(k) and not d.items["items"][k].get("rare", false))
		kinds.append(items.size())
		for id in items:
			counts.append(int(stock[id]))
		rare += stock.keys().filter(func(k): return d.items["items"].has(k) and d.items["items"][k].get("rare", false)).size()
	check(kinds.max() - kinds.min() >= 3, "item kinds per shop vary: %s" % str(kinds))
	check(counts.max() > counts.min(), "how many of each varies")
	check_eq(rare, 1, "one very rare item on the map")


func test_a_rare_item_sold_is_not_restocked() -> void:
	var st := _state(1)
	st.map.buildings[0]["shop"] = true
	st = GameState.new(d, st.map, GameLog.new())
	var shop: Dictionary = st.map.buildings[0]
	var id: String = shop["rare_item"]
	st.gold = 100000
	check(st.buy_item(shop, id), "buy it")
	st.restock()
	check_eq(int(st.shop_stock(shop).get(id, 0)), 0, "gone for good")


# --- Debt ---------------------------------------------------------------------------------

func _in_the_field(st: GameState) -> Squad:
	return st.add_squad("Ours", st.map.player_base, [["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"]])


func _to_noon(st: GameState) -> void:
	st.step()
	while st.clock.minute_of_day() != 12 * 60:
		st.step()


func test_three_noons_in_debt_is_a_defeat() -> void:
	var st := _state(28)
	var s := _in_the_field(st)
	st.gold = 1
	_to_noon(st)
	check_eq(st.gold, 1 - st.upkeep(s), "upkeep goes into debt")
	check_eq(st.debt_noons, 1, "noon 1 in debt")
	check(st.notices.any(func(t: String): return t.contains("In debt")), "a banner says so")
	check(not st.buy_supply({"shop": true, "stock": {"herb": 5}}, "herb"), "nothing can be bought in debt")
	_to_noon(st)
	check_eq(st.game_over, "", "two noons: not yet")
	_to_noon(st)
	check_eq(st.game_over, "defeat", "the third noon in debt")


func test_getting_out_of_debt_resets_the_count() -> void:
	var st := _state(28)
	var s := _in_the_field(st)
	st.gold = 1
	_to_noon(st)
	check_eq(st.debt_noons, 1, "in debt")
	st.gold = 10 * st.upkeep(s)
	_to_noon(st)
	check_eq(st.debt_noons, 0, "paid off: the count starts again")


func test_debt_past_the_limit_is_a_defeat() -> void:
	var st := _state(28)
	_in_the_field(st)
	st.gold = -st.debt_limit()
	_to_noon(st)
	check_eq(st.game_over, "defeat", "past the limit at the first noon")
	check(st.game_over_reason.contains("Debt"), st.game_over_reason)


# --- Upkeep that scales with the map --------------------------------------------------

func test_pool_and_base_cost_no_upkeep() -> void:
	var st := _state(28)
	st.setup_army()
	var field := st.player_squads()
	var at_base: Array = st.army.squads().filter(func(s: Squad): return s not in st.squads)
	check(not at_base.is_empty() or not st.army.pool.is_empty(), "someone waits at base or in the pool")
	var sum := 0
	for s in field:
		sum += st.upkeep(s)
	check_eq(st.army_upkeep(), sum, "only squads on the map pay")


func test_upkeep_scales_with_towns_and_towers() -> void:
	var small := _state(28)
	var big := _state(56)
	var a := _in_the_field(small)
	var b := _in_the_field(big)
	check(is_equal_approx(small.upkeep_scale(), 1.0), "a Small map's 28: scale 1")
	check_eq(big.upkeep(b), 2 * small.upkeep(a), "twice the towns, twice the upkeep")
	check_eq(small.deploy_cost(a), small.upkeep(a), "deploying costs a day of the scaled upkeep")


func test_starting_gold_is_two_days_of_a_full_field_army() -> void:
	var st := _state(56)
	var k: Dictionary = d.rules["starting_gold"]
	var day := st.squad_cap() * int(k["squad_units"]) * int(d.rules["upkeep"]["by_stage"][int(k["stage"]) - 1]) * 2
	check_eq(st.gold, int(k["days"]) * day, "2 days' upkeep at scale 2")
	check_eq(_state(5).gold, int(k["min"]), "a tiny map: at least 500")
