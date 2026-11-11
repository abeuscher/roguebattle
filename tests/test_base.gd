extends TestCase
## The Player Base: deploy and return, the squad cap, healing and revival (SPEC §8.4, §6.5, §15.1).

var d := GameData.load_dir()


func _state(cap := 5) -> GameState:
	var m := MapData.new(20, 7)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 5
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(3, 3)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 3)))
	var st := GameState.new(d, m, GameLog.new(), {"squad_cap": cap})
	st.setup_army()
	return st


func test_deploy() -> void:
	var st := _state()
	var waiting: Squad = st.army.cells[1]
	check(waiting not in st.squads, "the second squad waits at base")
	check_eq(st.deploy_blocker(waiting), "", "it can deploy")
	check(st.deploy(waiting), "deploy")
	check(waiting in st.squads, "it's on the map")
	check_eq(waiting.hex, st.map.player_base, "it shares the base hex with the first squad")
	check(st.deploy_blocker(waiting) != "", "it can't deploy twice")


func test_deploy_needs_a_living_leader() -> void:
	var st := _state()
	var s: Squad = st.army.cells[2]
	s.leader.hp = 0
	check(st.deploy_blocker(s).contains("fallen"), "a fallen leader keeps the squad at base")
	st.restore(s.leader)
	check_eq(st.deploy_blocker(s), "", "revived, it can go")
	for u in s.units.duplicate():  # Edit Units can't leave a squad leaderless; the check stays as a safety net
		if u.info(d)["can_lead"]:
			s.units.erase(u)
	s.leader = null
	check(st.deploy_blocker(s).contains("leader"), "a squad without a leader can't deploy")


func test_deploy_cost_and_route() -> void:
	var st := _state()
	var s: Squad = st.army.cells[1]
	var cost := 0
	for u in s.units:  # one day of upkeep: by stage, all Small here
		cost += [5, 10, 20, 35][int(u.info(d)["stage"]) - 1]
	check_eq(st.deploy_cost(s), cost, "deploying costs one day of upkeep")
	var gold := st.gold
	var to := st.map.index_of(Hex.from_offset(Vector2i(9, 3)))
	check(st.deploy(s, PackedInt32Array([to])), "deploy with a destination")
	check_eq(st.gold, gold - cost, "the cost is paid")
	check(s.is_moving() and s.rally[-1] == to, "it sets off at once")
	var other: Squad = st.army.cells[2]
	st.gold = st.deploy_cost(other) - 1
	check(st.deploy_blocker(other).contains("gold"), "not without the gold")


func test_squad_cap() -> void:
	var st := _state(2)
	check(st.deploy(st.army.cells[1]), "the second squad fits under a cap of 2")
	check(st.deploy_blocker(st.army.cells[2]).contains("cap"), "the third doesn't")
	check(not st.deploy(st.army.cells[2]), "and stays at base")


func test_return() -> void:
	var st := _state()
	var first := st.player_squads()[0]
	st.send_home(first)
	check(first not in st.squads, "a squad on the base goes in at once")
	check_eq(first.hex, -1, "it's off the map")
	st.deploy(first)
	st.order_move(first, PackedInt32Array([st.map.index_of(Hex.from_offset(Vector2i(7, 3)))]))
	for i in 300:
		st.step()
	check(first in st.squads and not first.is_moving(), "out in the field")
	st.send_home(first)
	check(first.entering_base and first.is_moving(), "sent home, it marches back")
	for i in 300:
		st.step()
	check(first not in st.squads, "and goes in on arrival")
	st.deploy(first)
	st.order_move(first, PackedInt32Array([st.map.index_of(Hex.from_offset(Vector2i(7, 3)))]))
	st.send_home(first)
	st.order_move(first, PackedInt32Array([st.map.index_of(Hex.from_offset(Vector2i(6, 3)))]))
	check(not first.entering_base, "a new order cancels going home")


func test_heal_and_revive() -> void:
	var st := _state()
	var at_base: Squad = st.army.cells[1]
	var hurt := at_base.units[1]
	var dead := at_base.units[2]
	hurt.hp = 1
	dead.hp = 0
	var gold := st.gold
	check_eq(st.heal_cost(hurt), int(d.rules["services"]["heal"]), "healing costs 20")
	check(st.restore(hurt), "heal at base")
	check_eq(hurt.hp, hurt.max_hp(d), "to full")
	check_eq(st.gold, gold - 20, "for 20 gold")
	var cost := st.revive_cost(dead)
	check_eq(cost, 50 * int(dead.info(d)["stage"]), "revival costs 50 × stage")
	check(st.restore(dead), "revive")
	check(dead.is_alive() and dead.hp == dead.max_hp(d), "back at full HP")
	check(not st.restore(dead), "nothing left to pay for")
	var field := st.player_squads()[0]
	field.units[1].hp = 1
	field.hex = st.map.index_of(Hex.from_offset(Vector2i(8, 3)))
	check(not st.at_base(field.units[1]) and not st.restore(field.units[1]), "no healing out in the field")
	st.gold = 5
	hurt.hp = 1
	check(not st.restore(hurt), "not without the gold")


func test_wiped_squad_comes_home() -> void:
	var st := _state()
	var first := st.player_squads()[0]
	var enemy := st.add_squad("Raiders", st.map.index_of(Hex.from_offset(Vector2i(4, 3))), [["Knight", "front"]], "enemy")
	var b := st.start_battle(first, enemy, enemy)
	for u in first.units:
		u.hp = 0
	st.end_battle(b)
	check(first not in st.squads and first in st.army.squads(), "a wiped-out squad is back at base, still in the army")
	check(st.deploy_blocker(first) != "", "it can't go out until its leader is revived")
