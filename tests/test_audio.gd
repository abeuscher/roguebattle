extends TestCase
## Sound (ROADMAP M5 session 2): the data hangs together, volumes save with the options,
## and every building you take has its riff.

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


func test_every_building_you_take_has_a_riff_event() -> void:
	for type in ["town", "tower", "temple"]:
		check(d.audio["events"].has("taken_" + type), "taking a %s has its event (played when its window opens)" % type)
	check(d.audio["events"].has("building_lost"), "and losing one (played when the lost window opens)")
