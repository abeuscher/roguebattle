extends TestCase
## Squad status for the HUD (playtest round 7, ROADMAP M4 session 25): moving, in a
## building, or standing in the open.

var d := GameData.load_dir()


func test_moving_in_a_building_or_in_the_open() -> void:
	var m := MapData.new(20, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 2
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 4)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 4)))
	var town := m.index_of(Hex.from_offset(Vector2i(8, 4)))
	m.buildings.append({"type": "town", "hex": town, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false})
	var st := GameState.new(d, m, GameLog.new())
	var s := st.add_squad("Ours", town, [["Knight", "front"]])
	check_eq(st.squad_status(s), "building", "standing in a town")
	check(st.status_text(s).begins_with("In "), st.status_text(s))
	st.order_move(s, PackedInt32Array([m.index_of(Hex.from_offset(Vector2i(10, 4)))]))
	check_eq(st.squad_status(s), "moving", "on the move")
	check(st.status_text(s).begins_with("Moving"), st.status_text(s))
	for i in 600:
		st.step()
	check_eq(st.squad_status(s), "still", "stopped in the open")
	check(st.status_text(s).begins_with("Standing in the open"), st.status_text(s))
