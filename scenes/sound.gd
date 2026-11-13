class_name Sound
extends Node
## Sound (SPEC §24, ROADMAP M5 session 2): plays the cues in data/audio.json on the buses
## Music, Effects and Voice, sets their volumes from the player's options, dips the music
## under stingers and voice lines, and clicks for every button pressed anywhere. One
## instance, made by Main at startup (Sound.start); the static calls do nothing without
## it (tests, tools). The rules never call it; scenes do, for what they show. A cue with
## no file yet plays nothing.

static var _it: Sound

var cues := {}
var events := {}
var duck := {}
var _streams := {}  # file -> AudioStream, loaded once
var _music_db := 0.0  # the Music bus's volume from the options, before any dip
var _dip := 0.0  # the current dip, in dB (0 or below)
var _dip_tween: Tween
var music_cue := ""  # what's playing (or fading in)
var _music_player: AudioStreamPlayer
var _fade := 2.0
var _left_at := {}  # sync group -> where its music was when it last faded out


## Makes the one instance under `parent`, with the sound data and the player's options.
static func start(parent: Node, audio: Dictionary, options: Dictionary) -> void:
	_it = Sound.new()
	_it.process_mode = PROCESS_MODE_ALWAYS
	parent.add_child(_it)
	_it.get_tree().node_added.connect(_it._on_node_added)
	_it._setup(audio, options)


## Plays an event's cues (audio.json "events").
static func event(id: String) -> void:
	if _it:
		_it._event(id)


## Crossfades to a music cue (audio.json "cues"); the same cue again does nothing. A cue
## with no file fades the music out.
static func music(cue: String) -> void:
	if _it:
		_it._music(cue)


## The music cue for a place (audio.json "music": menus, day, night, army, victory,
## defeat), or for a battle on `terrain` when `place` is "battle".
static func music_for(audio: Dictionary, place: String, terrain := "") -> String:
	var m: Dictionary = audio.get("music", {})
	if place == "battle":
		var by: Dictionary = m.get("battle", {})
		return str(by.get(terrain, by.get("_default", "")))
	return str(m.get(place, ""))


## Sets the buses from the options (after the player changes them).
static func apply_options(options: Dictionary) -> void:
	if _it:
		_it._apply(options)


## Reads the sound data and the player's options; makes the buses if they aren't there.
func _setup(audio: Dictionary, options: Dictionary) -> void:
	cues = audio.get("cues", {})
	events = audio.get("events", {})
	duck = audio.get("duck", {})
	_fade = float(audio.get("music", {}).get("fade_seconds", 2.0))
	for bus in audio.get("buses", []):
		if AudioServer.get_bus_index(bus) < 0:
			AudioServer.add_bus()
			AudioServer.set_bus_name(AudioServer.bus_count - 1, bus)
			AudioServer.set_bus_send(AudioServer.bus_count - 1, "Master")
	_apply(options)


## Sets every bus from the options: master_volume, <bus>_volume (0-100) and mute.
func _apply(options: Dictionary) -> void:
	AudioServer.set_bus_volume_db(0, volume_db(options.get("master_volume", 100)))
	AudioServer.set_bus_mute(0, bool(options.get("mute", false)))
	for i in range(1, AudioServer.bus_count):
		var bus := AudioServer.get_bus_name(i)
		var db := volume_db(options.get(bus.to_lower() + "_volume", 100))
		if bus == "Music":
			_music_db = db
			db += _dip
		AudioServer.set_bus_volume_db(i, db)


## An option's 0-100 volume as decibels (0 is silent).
static func volume_db(percent: Variant) -> float:
	var v := clampf(float(percent) / 100.0, 0.0, 1.0)
	return -80.0 if v <= 0.0 else linear_to_db(v)


## An event's cues, some after a delay.
func _event(id: String) -> void:
	for e in events.get(id, []):
		if e is Dictionary:
			get_tree().create_timer(float(e.get("after", 0.0))).timeout.connect(play.bind(str(e["cue"])))
		else:
			play(str(e))


func play(cue: String) -> void:
	var c: Dictionary = cues.get(cue, {})
	var stream := _stream(str(c.get("file", "")))
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = str(c.get("bus", "Master"))
	p.volume_db = float(c.get("db", 0.0))
	add_child(p)
	p.finished.connect(p.queue_free)
	p.play()
	if c.get("duck", false):
		_duck()


## The old music fades out as the new fades in. A cue with a "sync" group (day and night)
## starts where that group's music last was: at dawn and dusk the other arrangement takes
## over in step, and after Edit Units or a battle the map's tune carries on.
func _music(cue: String) -> void:
	if cue == music_cue:
		return
	var old := _music_player
	var c: Dictionary = cues.get(cue, {})
	var left := str(cues.get(music_cue, {}).get("sync", ""))
	if old and left != "":
		_left_at[left] = old.get_playback_position()
	var sync := str(c.get("sync", ""))
	var from: float = _left_at.get(sync, 0.0) if sync != "" else 0.0
	music_cue = cue
	_music_player = null
	if old:
		var out := old.create_tween()
		out.tween_property(old, "volume_db", -60.0, _fade)
		out.tween_callback(old.queue_free)
	var stream := _stream(str(c.get("file", "")))
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = str(c.get("bus", "Music"))
	p.volume_db = -60.0 if old else float(c.get("db", 0.0))
	add_child(p)
	p.play(from)
	if old:
		p.create_tween().tween_property(p, "volume_db", float(c.get("db", 0.0)), _fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_player = p


func _stream(file: String) -> AudioStream:
	if file == "" or not ResourceLoader.exists(file):
		return null
	if not _streams.has(file):
		_streams[file] = load(file)
	return _streams[file]


## Dips the music quickly, holds it while the stinger or line plays, then brings it back.
func _duck() -> void:
	if _dip_tween:
		_dip_tween.kill()
	_dip_tween = create_tween()
	_dip_tween.tween_method(_set_dip, _dip, float(duck.get("db", -9.0)), 0.15)
	_dip_tween.tween_interval(float(duck.get("seconds", 2.0)))
	_dip_tween.tween_method(_set_dip, float(duck.get("db", -9.0)), 0.0, 0.6)


func _set_dip(db: float) -> void:
	_dip = db
	var i := AudioServer.get_bus_index("Music")
	if i >= 0:
		AudioServer.set_bus_volume_db(i, _music_db + _dip)


func _on_node_added(n: Node) -> void:
	if n is BaseButton and not (n as BaseButton).pressed.is_connected(_click):
		(n as BaseButton).pressed.connect(_click)


func _click() -> void:
	_event("click")
