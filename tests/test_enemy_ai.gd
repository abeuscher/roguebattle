extends TestCase
## Enemy map AI (SPEC §12.3, §17): garrisons hold their post; raiders and
## attacking wildcards march on the weakest player-held building; defending
## wildcards reinforce a threatened enemy building or hold their ground.

var d := GameData.load_dir()


## A plains strip map with the player base on the left and the enemy base on the right.
func _state(w := 30, h := 9) -> GameState:
	var m := MapData.new(w, h)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 9
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, w - 2, 4)
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _town(st: GameState, col: int, row := 4, owner := "player") -> Dictionary:
	var b := {"type": "town", "hex": _at(st.map, col, row), "shop": false, "hint": false, "hidden": false, "kind": "", "road": false, "owner": owner}
	st.map.buildings.append(b)
	return b


func _enemy_squad(st: GameState, col: int, row: int, role: String, ai_mode := "") -> Squad:
	var s := st.add_squad(role.capitalize(), _at(st.map, col, row), [["Soldier", "front"], ["Fighter", "front"], ["Bowman", "back"]], "enemy")
	s.role = role
	s.ai_mode = ai_mode
	return s


## No threat nearby: isolates the AI's own choice from push-back, which can
## still move a stationary role if it loses a fight (a separate, pre-existing
## mechanic, not something the AI decides).
func test_leader_base_guard_and_garrison_hold_their_post() -> void:
	var st := _state()
	var roles := ["leader", "base_guard", "garrison"]
	var posts := {}
	for i in roles.size():
		var s := _enemy_squad(st, 10 + i * 5, 2 + i, roles[i])
		posts[s] = s.hex
	for i in 50:
		st.step()
	check_eq(posts.size(), 3, "all three are set up")
	for s in posts:
		check(not s.is_moving(), "%s never gets an order" % s.role)
		check_eq(s.hex, posts[s], "%s never leaves its post" % s.role)


func test_raider_marches_on_the_weakest_player_building() -> void:
	var st := _state()
	var weak := _town(st, 10, 4)
	var strong := _town(st, 10, 7)  # off the raider's row, so it isn't intercepted en route
	st.add_squad("Defenders", strong["hex"], [["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"]])
	var raider := _enemy_squad(st, 25, 4, "raider")
	for i in 400:
		st.step()
		if st.pending:
			break
	check_eq(raider.hex, weak["hex"], "it marches on the undefended town, not the defended one")


func test_raider_targets_the_player_base_with_nothing_else_held() -> void:
	var st := _state()
	var raider := _enemy_squad(st, 25, 4, "raider")
	for i in 400:
		st.step()
		if st.pending:
			break
	check_eq(raider.hex, st.map.player_base, "no player-held town or tower: it goes for the Player Base")


func test_attacking_wildcard_acts_like_a_raider() -> void:
	var st := _state()
	var weak := _town(st, 10)
	var wildcard := _enemy_squad(st, 25, 4, "wildcard", "attack")
	for i in 400:
		st.step()
		if st.pending:
			break
	check_eq(wildcard.hex, weak["hex"], "an attacking wildcard marches on the weakest player building")


func test_defending_wildcard_reinforces_a_threatened_building() -> void:
	var st := _state()
	var held := _town(st, 20, 4, "enemy")
	var wildcard := _enemy_squad(st, 25, 6, "wildcard", "defend")
	var at := wildcard.hex
	for i in 50:
		st.step()
	check_eq(wildcard.hex, at, "nothing threatened yet: it holds its ground")
	st.add_squad("Liberators", held["hex"], [["Knight", "front"]])
	for i in 200:
		st.step()
		if st.pending:
			break
	check(Hex.distance(st.map.hex_at(wildcard.hex), st.map.hex_at(held["hex"])) <= 1,
			"a player squad shows up at the enemy town: it marches to defend it (can't stand on the same hex as a hostile)")


func test_wildcards_roll_attack_or_defend_at_placement() -> void:
	var m := MapGen.generate(d, 11, {"size": "small"})
	var st := GameState.new(d, m, GameLog.new())
	st.place_enemies()
	var wildcards := st.squads.filter(func(s: Squad): return s.role == "wildcard")
	check_eq(wildcards.size(), 3, "three wildcards")
	for s in wildcards:
		check(s.ai_mode in ["attack", "defend"], "%s rolled a mode: %s" % [s.name, s.ai_mode])
