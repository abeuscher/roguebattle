extends TestCase
## The map's ambience (ROADMAP M5 session 9; user 2026-11-14): beds and one-shots by day
## and night, plus one-shots that play only under a condition (hooves while a mounted unit
## moves in sight, waves near the sea, a river beside one), on the map only.

var d := GameData.load_dir()


func _state() -> GameState:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 5
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 28, 4)
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func test_conditional_one_shots_need_their_fact() -> void:
	var amb: Dictionary = d.audio["map_ambience"]
	check(Sound.shot_allowed(amb, "owl.wav", []), "an ordinary one-shot always may")
	check(not Sound.shot_allowed(amb, "clops_1.wav", []), "hooves need a mounted unit moving")
	check(Sound.shot_allowed(amb, "clops_1.wav", ["mounted_moving"]), "and then may")
	check(not Sound.shot_allowed(amb, "waves_2.wav", ["near_river"]), "waves need the sea, not a river")
	check(Sound.shot_allowed(amb, "river_1.wav", ["near_river"]), "a river needs a river")


func test_the_facts() -> void:
	var st := _state()
	var s := st.add_squad("Ours", _at(st.map, 10, 4), [["Knight", "front"]])
	check(st.ambience_facts().is_empty(), "on open plains, standing still: nothing")
	st.map.terrain[_at(st.map, 12, 4)] = d.terrain_ids["shallow"]
	check("near_ocean" in st.ambience_facts(), "the sea two hexes off")
	st.map.terrain[_at(st.map, 12, 4)] = d.terrain_ids["plains"]
	st.map.rivers.append(PackedInt32Array([_at(st.map, 11, 4), _at(st.map, 11, 5)]))
	check("near_river" in st.ambience_facts(), "a river beside it")
	var riders := st.add_squad("Riders", _at(st.map, 4, 4), [["Squire", "front"]])
	check("mounted_moving" not in st.ambience_facts(), "mounted, but standing still")
	st.order_move(riders, PackedInt32Array([_at(st.map, 6, 4)]))
	check("mounted_moving" in st.ambience_facts(), "mounted and on the move")


func test_ambience_on_the_map_only() -> void:
	var pools: Dictionary = d.audio["map_ambience"]["pools"]
	var menus: String = d.audio["cues"][Sound.music_for(d.audio, "menus")]["pool"]
	check(not pools[menus].has("ambience"), "the menus play the day's piano without the map's sounds")
	check(pools["day"].has("ambience") and pools["night"].has("ambience"), "the map's day and night have theirs")


func test_the_draft_sounds_are_in() -> void:
	var root: String = d.audio["map_ambience"]["ambience"]
	for f in ["day/bed", "night/bed", "day/birds_1", "night/owl", "any/clops_1", "any/waves_1", "any/river_1"]:
		check(load(root + f + ".wav") is AudioStreamWAV, "%s loads" % f)
	for f in ["day/chapel", "night/wolves", "night/bell"]:
		check(not ResourceLoader.exists(root + f + ".wav"), "no %s (user, 2026-11-14)" % f)


## User, 2026-11-14: a little panning for depth: one-shots spread across panned buses.
func test_one_shots_are_panned() -> void:
	var amb: Dictionary = d.audio["map_ambience"]
	check(int(amb.get("pan_steps", 0)) >= 3, "several panned buses")
	check(float(amb["shot_pan"]) > 0.3 and float(amb["shot_pan"]) <= 1.0, "spread left and right, not to the very edges")
