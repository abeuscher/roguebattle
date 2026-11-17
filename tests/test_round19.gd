extends TestCase
## Playtest round 19 (2026-11-15): the squad cap growing with buildings held, contact
## sooner on small boards, beaten squads giving out, the enemy's fallen coming back,
## field promotion, recaptured towns, and the smaller switches.

var d := GameData.load_dir()


func test_pause_after_a_lost_battle_only_when_asked() -> void:
	var opts := PlayerOptions.load_values(d, "user://no_such_options.json")
	check(not GameState.pause_after("lost", opts), "off by default")
	opts["pause_after_loss"] = true
	check(GameState.pause_after("lost", opts), "on: a lost battle pauses")
	check(not GameState.pause_after("won", opts) and not GameState.pause_after("retreated", opts), "only a loss")


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


## A plain 40×9 map with 18 towns along row 6, bases at either end.
func _state(settings := {"squad_cap": 4}) -> GameState:
	var m := MapData.new(40, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 19
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 3)
	m.enemy_base = _at(m, 38, 3)
	for k in 18:
		m.buildings.append({"type": "town", "hex": _at(m, 2 + k * 2, 6), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	return GameState.new(d, m, GameLog.new(), settings)


func _own(st: GameState, side: String, n: int) -> void:
	var towns := st.map.buildings.filter(func(b): return b["type"] == "town")
	for i in towns.size():
		towns[i]["owner"] = side if i < n else "neutral"


func _squad(st: GameState, side := "player", members := [["Knight", "front"], ["Fighter", "front"]]) -> Squad:
	var s := st.add_squad("S", _at(st.map, 10, 3), members, side)
	if side == "player":
		st.army.cells[st.army.cells.find(null)] = s
	return s


func test_the_cap_rises_and_falls_with_buildings_held() -> void:
	var st := _state()
	check_eq(st.field_cap(), 4, "the starting cap, holding nothing")
	_own(st, "player", 5)
	check_eq(st.field_cap(), 4, "5 buildings: not yet")
	_own(st, "player", 6)
	check_eq(st.field_cap(), 5, "6 buildings: one more squad")
	_own(st, "player", 12)
	check_eq(st.field_cap(), 6, "12: two more")
	st._check_cap()
	check(st.army.cells.size() >= 7, "room in the army for the squads it allows")
	st.enemy_start_squads = 3
	_own(st, "enemy", 8)
	check_eq(st.field_cap("enemy"), 3, "the enemy needs 9 a step: 8 isn't enough")
	_own(st, "enemy", 9)
	check_eq(st.field_cap("enemy"), 4, "9: one more Warband")


func test_over_the_cap_nothing_deploys() -> void:
	var st := _state({"squad_cap": 1})
	_own(st, "player", 6)
	var out := _squad(st)
	out.hex = _at(st.map, 10, 3)
	var waiting := st.add_squad("W", -1, [["Knight", "front"]])
	st.squads.erase(waiting)
	st.army.cells[st.army.cells.find(null)] = waiting
	st.gold = 10000
	check_eq(st.deploy_blocker(waiting), "", "6 buildings: a second squad may go out")
	_own(st, "player", 0)
	check(st.deploy_blocker(waiting) != "", "buildings lost: over the cap, it can't")
	check(out in st.squads, "the squad already out stays out")


func test_beaten_squads_give_out() -> void:
	var st := _state()
	var ours := _squad(st)
	var theirs := _squad(st, "enemy")
	var cfg: Dictionary = d.battle["worn"]
	check_eq(st.worn(ours), 1.0, "fresh: full defence")
	ours.units[0].hp -= 1  # hurt, so it hasn't recovered
	st._lost_battle(ours)
	st._lost_battle(ours)
	check(is_equal_approx(st.worn(ours), 1.0 - 2 * float(cfg["step"])), "two lost battles: two steps (%s)" % st.worn(ours))
	ours.units[1].hp = 0
	check(is_equal_approx(st.worn(ours), 1.0 - 3 * float(cfg["step"])), "and a fallen unit: a third")
	st._lost_battle(theirs)
	check(is_equal_approx(st.worn(theirs), 1.0 - float(cfg["step"]) * float(cfg["enemy_mult"])), "the enemy's steps are bigger")
	for u in ours.units:
		u.hp = u.max_hp(d)
	check_eq(st.worn(ours), 1.0, "yours recover at full health")
	check_eq(ours.beaten, 0, "and the count starts again")
	theirs.hex = st.map.enemy_base
	st._revive_at_enemy_base(theirs)
	check_eq(theirs.beaten, 0, "the enemy recovers on a refuge")
	var b := st.start_battle(ours, theirs, theirs)
	check_eq(b.worn, [st.worn(ours), st.worn(theirs)], "the battle takes it in")
	var knight := ours.units[0]
	var full := b.stat(knight, "PDEF")
	b.worn[0] = 0.5
	check(is_equal_approx(b.stat(knight, "PDEF"), full * 0.5), "on PDEF")


func test_a_wiped_out_enemy_comes_back_at_its_base() -> void:
	var st := _state()
	var theirs := _squad(st, "enemy")
	theirs.hex = _at(st.map, 20, 3)
	var ticks := st.return_ticks(theirs)
	check(ticks > 0, "a march home takes time")
	for u in theirs.units:
		u.hp = 0
	var ours := _squad(st)
	ours.hex = _at(st.map, 19, 3)
	st.pending = st.start_battle(ours, theirs, theirs)
	st.resolve_pending()
	check(theirs not in st.squads, "it leaves the board")
	check(st.notices.any(func(n: String): return "wiped out and leaves the board" in n), "with a note: %s" % [st.notices])
	check_eq(st.returning.size(), 1, "and waits to return")
	var at: int = st.returning[0]["at"]
	check_eq(at - st.clock.tick, roundi(ticks * float(d.enemy["return"]["travel_share"])), "after half its march home")
	st.settings["victory_squads"] = true
	st.settings["victory_squads_n"] = "all"
	st._check_game_over()
	check_eq(st.game_over, "", "defeat all: not while one waits to return")
	st.clock.tick = at
	st._return_fallen()
	check(theirs in st.squads and theirs.hex == st.map.enemy_base, "back at the Enemy Base")
	check(theirs.units.all(func(u: Unit): return u.hp == u.max_hp(d)), "at full strength")


func test_recaptured_counts_per_town() -> void:
	var st := _state()
	var ours := _squad(st)
	var town: Dictionary = st.map.buildings[4]
	ours.hex = town["hex"]
	for k in 3:
		town["owner"] = "enemy"
		for i in int(d.rules["capture"]["ticks"]):
			st.step()
		check_eq(town["owner"], "player", "taken (%d)" % (k + 1))
	var times := st.liberations.map(func(e: Dictionary): return e["times"])
	check_eq(times, [1, 2, 3], "first, second, third")
	check_eq(st.liberations[1]["card"], "", "no card the second time")
	check_eq([GameState.ordinal(2), GameState.ordinal(3), GameState.ordinal(11), GameState.ordinal(22)], ["second", "third", "11th", "22nd"], "ordinals")


func test_heal_before_a_fight_closes_at_full_health() -> void:
	var st := _state()
	var ours := _squad(st)
	var theirs := _squad(st, "enemy")
	ours.units[0].hp -= 5
	st.army.supplies["herb"] = 3
	var b := st.start_battle(ours, theirs, theirs)
	var menu := SuppliesMenu.new()
	var closed := [false]
	menu.closed.connect(func(): closed[0] = true)
	menu.setup(st, ours, b)
	check(not closed[0], "someone is hurt: it stays open")
	st.use_supply_before_battle(b, ours.units[0], "herb")
	menu._refresh(true)
	check(closed[0], "everyone at full HP: it closes")
	check(ours.all_well(d), "all well")
	menu.free()


func test_the_portal_tip_waits_for_two_temples() -> void:
	var opts := {"show_tips": true, "tips_seen": []}
	check_eq(PlayerTips.due(d, opts, "portal_ready", "single_map"), "portal", "due at its moment")
	check(str(d.tips["tips"]["portal"]["text"]).begins_with("Temples are not only places of worship"), "the user's text")


func test_enemy_squads_start_forward_in_your_half() -> void:
	var config := GameConfig.create(d, 4)
	config.values["width"] = 300
	config.values["height"] = 180
	var map := MapGen.generate(d, config.seed, config.map_overrides())
	var st := GameState.new(d, map, GameLog.new(), config.game_settings())
	st.place_enemies()
	var p := map.hex_at(map.player_base)
	var e := map.hex_at(map.enemy_base)
	var axis := Vector2(e - p)
	var forward := st.squads.filter(func(o: Squad): var at := map.hex_at(o.hex); return o.side == "enemy" and Hex.distance(at, p) < Hex.distance(at, e))
	check_eq(forward.size(), 2, "two forward squads in your half")
	var sides := forward.map(func(o: Squad): return signf(axis.cross(Vector2(map.hex_at(o.hex) - p))))
	check(sides.has(1.0) and sides.has(-1.0), "one each side of the line between the bases")
	for o in forward:
		check_eq(st.building_at(o.hex).get("owner", ""), "enemy", "%s holds a town or tower" % o.name)
