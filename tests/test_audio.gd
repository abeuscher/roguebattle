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


func test_every_place_has_music_that_loops() -> void:
	var cues: Dictionary = d.audio["cues"]
	for place in ["title", "menus", "day", "night", "army", "victory", "defeat"]:
		var cue := Sound.music_for(d.audio, place)
		check(cues.has(cue), "%s plays %s, a known cue" % [place, cue])
		check(cues[cue]["bus"] == "Music", "%s is on the Music bus" % cue)
		if cues[cue].has("pool"):
			continue  # phrases, not a loop: test_map_phrase_pools
		var stream := load(cues[cue]["file"]) as AudioStreamWAV
		check(stream != null and stream.loop_mode == AudioStreamWAV.LOOP_FORWARD, "%s loops" % cue)
	for t in d.terrains:
		var cue := Sound.music_for(d.audio, "battle", t["key"])
		check(cues.has(cue) and (load(cues[cue]["file"]) as AudioStreamWAV).loop_mode == AudioStreamWAV.LOOP_FORWARD, "a battle on %s plays %s, a loop" % [t["key"], cue])
	check_eq(Sound.music_for(d.audio, "battle", "forest"), "battle_forest", "forest has its own")
	check_eq(Sound.music_for(d.audio, "battle", "deep"), "battle_plains", "anything else borrows plains")


## Stingers and voice lines take turns (ROADMAP M5 session 5).
func test_stingers_take_turns() -> void:
	check_eq(Sound.queue_slot(10.0, 9.0, 2.0), 10.0, "a free queue plays a stinger at once")
	check_eq(Sound.queue_slot(10.0, 11.5, 2.0), 11.5, "a busy one plays it when the last ends")
	check_eq(Sound.queue_slot(10.0, 12.5, 2.0), -1.0, "and drops it if that's more than 2 s off")
	check_eq(float(d.audio["queue"]["max_wait"]), 2.0, "the wait limit is data")
	for id in ["new_town", "new_tower", "new_temple", "retaken"]:
		check(d.audio["events"].has(id), "the %s voice line has its event" % id)


func test_map_phrase_pools() -> void:
	var amb: Dictionary = d.audio["map_ambience"]
	for place in ["day", "night", "menus", "title", "victory"]:
		var cue: Dictionary = d.audio["cues"][Sound.music_for(d.audio, place)]
		check(amb["pools"].has(cue.get("pool", "")), "%s plays a phrase pool" % place)
	for pool in amb["pools"]:
		var cfg: Dictionary = amb["pools"][pool]
		var files := Array(ResourceLoader.list_directory(amb["phrases"])).filter(func(f: String): return f.begins_with(cfg["prefix"]) and f.ends_with(".wav"))
		check(files.size() >= 2, "the %s pool has phrases (%d)" % [pool, files.size()])
		for f in files:
			var w := load(amb["phrases"] + f) as AudioStreamWAV
			check(w != null and w.loop_mode == AudioStreamWAV.LOOP_DISABLED, "%s plays once, not looped" % f)
		if cfg.has("turn_in"):
			check(ResourceLoader.exists(amb["phrases"] + amb["turns"][cfg["turn_in"]]), "the turn into %s is there" % pool)
	for pool in ["title", "victory"]:
		var cfg: Dictionary = amb["pools"][pool]
		check(not cfg.has("turn_in") and not cfg.has("ambience"), "the %s bed has no turn and no ambience" % pool)
		check(float(cfg["gap"][1]) <= 10.0 and float(cfg["rest_chance"]) == 0.0, "the %s bed's gaps are short and it never sits out" % pool)


func test_a_phrase_never_plays_twice_running() -> void:
	for last in [-1, 0, 4, 9]:
		var seen := {}
		for i in 200:
			var k := Sound.pick_phrase(10, last, i / 200.0)
			check(k >= 0 and k < 10 and k != last, "pick %d after %d" % [k, last])
			seen[k] = true
		check_eq(seen.size(), 10 if last < 0 else 9, "every other phrase can come up")
	check_eq(Sound.pick_phrase(1, 0, 0.5), 0, "a pool of one plays its one")
