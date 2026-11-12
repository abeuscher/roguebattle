extends TestCase
## Sound (ROADMAP M5 session 2): the data hangs together, volumes save with the options,
## and a building changing hands is recorded for the scenes to sound.

var d := GameData.load_dir()


func test_every_event_names_a_cue_and_every_file_exists() -> void:
	var cues: Dictionary = d.audio["cues"]
	for id in d.audio["events"]:
		if id.begins_with("_"):
			continue
		for e in d.audio["events"][id]:
			var cue := str(e["cue"]) if e is Dictionary else str(e)
			check(cues.has(cue), "%s plays %s, a known cue" % [id, cue])
	for id in cues:
		var c: Dictionary = cues[id]
		check(c["bus"] in d.audio["buses"], "%s is on a known bus" % id)
		if c["file"] != "":
			check(ResourceLoader.exists(c["file"]), "%s's file is there: %s" % [id, c["file"]])
	for bus in d.audio["buses"]:
		check(d.options["options"].has(bus.to_lower() + "_volume"), "%s has a volume option" % bus)


func test_volumes_save_with_the_options() -> void:
	var path := "user://test_options.json"
	var values := PlayerOptions.load_values(d, path)
	check_eq(values["master_volume"], 80, "master at 80 to start")
	check_eq(values["mute"], false, "not muted")
	values["music_volume"] = 35
	values["mute"] = true
	PlayerOptions.save_values(values, path)
	var back := PlayerOptions.load_values(d, path)
	check_eq(int(back["music_volume"]), 35, "the music volume comes back")
	check_eq(back["mute"], true, "and mute")
	DirAccess.remove_absolute(path)
	check_eq(Sound.volume_db(100), 0.0, "100 is full volume")
	check(Sound.volume_db(0) <= -80.0, "0 is silent")
	check(absf(Sound.volume_db(50) - linear_to_db(0.5)) < 0.01, "50 is half")


func test_captures_are_recorded_for_their_sounds() -> void:
	var m := MapData.new(30, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(1, 4)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(28, 4)))
	var town := m.index_of(Hex.from_offset(Vector2i(10, 4)))
	m.buildings.append({"type": "town", "hex": town, "shop": false, "hint": false, "hidden": false, "kind": "", "road": false, "name": "Testford"})
	var st := GameState.new(d, m, GameLog.new())
	st.debug_freeze_ai = true
	st.add_squad("Ours", town, [["Knight", "front"]])
	for i in int(d.rules["capture"]["ticks"]) + 1:
		st.step()
	check_eq(st.captures.size(), 1, "one capture")
	check_eq(st.captures[0]["was"], "neutral", "it was neutral")
	check_eq(Sound.capture_event(st.captures[0], false), "taken_town", "taking a neutral town plays the town riff, seen or not")
	check_eq(Sound.capture_event({"type": "tower", "side": "enemy", "was": "neutral"}, true), "taken_tower", "the enemy taking a neutral tower in sight sounds the same")
	check_eq(Sound.capture_event({"type": "tower", "side": "enemy", "was": "neutral"}, false), "", "but not out of sight")
	check_eq(Sound.capture_event({"type": "temple", "side": "enemy", "was": "player"}, false), "building_lost", "the enemy taking one of yours always has its own sound")
	for t in int(d.rules["capture"]["ticks"]) * 3:
		st.step()
	check(st.captures.size() == 1, "the capture is recorded once, at the end of the progress bar, not again while the squad stays")
