extends TestCase
## Playtest round 20 (2026-11-15).

var d := GameData.load_dir()


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 20
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 28, 4)
	return GameState.new(d, m, GameLog.new())


## Your squad marching east along row 4 to column 20 meets a band standing on its road at
## column 9; `how` settles the meeting. Returns the state and your squad after a while.
func _march(how: String) -> Array:
	var st := _state()
	var p := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"], ["Knight", "front"], ["Knight", "front"]])
	st.army.cells[st.army.cells.find(null)] = p
	var n := st.add_squad("Rats", _at(st.map, 9, 4), [["Fighter", "front"]], "neutral")
	n.role = "roamer"
	n.lair_hex = n.hex
	st.debug_freeze_ai = false
	check(st.order_move(p, PackedInt32Array([_at(st.map, 20, 4)])), "ordered")
	for i in 400:
		st.step()
		if not st.pending_recruit.is_empty():
			match how:
				"sneak":
					p.units[0].stats["AGI"] = 999
					st.sneak_past()
				"recruit":
					st.reputation = 100
					n.units[0].alignment = int(p.alignment())
					var r := st.rng.get_stream("recruit")
					st.recruit_chance(p, 1, n.alignment())
					st.resolve_recruit(true)
				"fight":
					st.resolve_recruit(false)
				"beaten_offer":
					st.resolve_recruit(false)  # the second recruit chance after winning: decline
		if st.pending:
			if how == "lose":
				for u in p.units:
					u.hp = 0 if u != p.leader else 1
			st.resolve_pending()
		if p.hex == _at(st.map, 20, 4):
			break
	return [st, p]


func test_a_neutral_meeting_doesnt_stop_the_march() -> void:
	for how in ["sneak", "recruit", "fight"]:
		var x := _march(how)
		var st: GameState = x[0]
		var p: Squad = x[1]
		check_eq(p.hex, _at(st.map, 20, 4), "%s: it carries on to where it was going" % how)


func test_a_leader_of_the_bands_terrain_sees_the_odds() -> void:
	var st := _state()
	var p := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"]])
	var n := st.add_squad("Wolves", _at(st.map, 6, 4), [["Fighter", "front"]], "neutral")
	var enc := {"player": p, "neutral": n, "defender": n}
	check_eq(p.leader.terrain(d), n.units[0].terrain(d), "both Plains here")
	var odds := st.band_odds(enc)
	check(is_equal_approx(odds["recruit"], st.recruit_chance(p, 1, n.alignment())) and is_equal_approx(odds["sneak"], st.sneak_chance(p, n)), "the real chances")
	enc["beaten"] = true
	check(not st.band_odds(enc).has("sneak"), "after a won fight, no sneaking")
	n.units[0].unit_class = "Wolf"
	check(p.leader.terrain(d) != n.units[0].terrain(d), "a Wolf is from elsewhere")
	check(st.band_odds(enc).is_empty(), "a stranger to them: no odds")


## Round 20: from the squad menu too, healing everyone closes the Heal window.
func test_heal_closes_once_all_are_well_from_the_menu() -> void:
	var st := _state()
	var p := st.add_squad("Ours", _at(st.map, 5, 4), [["Knight", "front"], ["Knight", "front"]])
	p.units[0].hp -= 5
	st.army.supplies["herb"] = 2
	var menu := SuppliesMenu.new()
	var closed := [false]
	menu.closed.connect(func(): closed[0] = true)
	menu.setup(st, p)
	check(not closed[0], "someone hurt: open")
	st.use_supply(p.units[0], "herb")
	menu._refresh(true)
	check(closed[0], "all well: it closes")
	menu.free()


func test_buildings_to_the_next_squad() -> void:
	var st := _state()
	for k in 8:
		st.map.buildings.append({"type": "town", "hex": _at(st.map, 3 + k * 2, 7), "owner": "neutral", "hidden": false, "kind": "", "shop": false, "hint": false, "road": false})
	check_eq(st.buildings_to_next_squad(), 6, "none held: 6 to go")
	for k in 4:
		st.map.buildings[k]["owner"] = "player"
	check_eq(st.buildings_to_next_squad(), 2, "4 held: 2 to go")
	for k in 7:
		st.map.buildings[k]["owner"] = "player"
	check_eq(st.buildings_to_next_squad(), 5, "7 held: one squad gained, 5 to the next")


func test_zoom_share_runs_from_out_to_in() -> void:
	var cam := MapCamera.new()
	cam._fit_zoom = 1.0
	cam.zoom = Vector2.ONE * 0.5
	check(is_equal_approx(cam.zoom_share(), 0.0), "all the way out: 0")
	cam.zoom = Vector2.ONE * MapCamera.MAX_ZOOM
	check(is_equal_approx(cam.zoom_share(), 1.0), "all the way in: 1")
	cam.zoom = Vector2.ONE * 1.0
	check(cam.zoom_share() > 0.0 and cam.zoom_share() < 1.0, "between")
	cam.free()
