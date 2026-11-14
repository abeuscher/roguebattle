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
var amb := {}  # audio.json map_ambience: the phrase pools and the map's environmental sound
var _pool := ""  # the phrase pool playing, or "" for a plain music cue
var _pool_gen := 0  # changes with the music, so a pending gap for older music does nothing
var _pool_files := {}  # pool -> its phrase files
var _last_phrase := -1
var _turn_next := false  # the dusk or dawn turn plays when the phrase playing ends
var _amb_state := ""
var _amb_gen := 0
var _bed: AudioStreamPlayer
var _rng := RandomNumberGenerator.new()  # the sound player's own, apart from the game's seeded streams
var queue := {}  # audio.json "queue"
var _queue_free_at := 0.0  # when the last queued stinger or voice line ends (seconds, engine time)
var _sounding := {}  # cue -> true while it plays or waits its turn


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
	queue = audio.get("queue", {})
	_fade = float(audio.get("music", {}).get("fade_seconds", 2.0))
	amb = audio.get("map_ambience", {})
	_rng.randomize()
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


## Plays a cue now, or, for one that ducks the music (a stinger or voice line), when the
## last of those ends: they take turns, and one that would wait more than the queue's
## max_wait is dropped (unless the cue has "wait": a voice line that follows a long riff).
## A cue already playing or waiting doesn't play again over itself.
func play(cue: String) -> void:
	var c: Dictionary = cues.get(cue, {})
	var stream := _stream(str(c.get("file", "")))
	if stream == null or _sounding.has(cue):
		return
	if not c.get("duck", false):
		_start(cue, c, stream)
		return
	var now := Time.get_ticks_msec() / 1000.0
	var at := queue_slot(now, _queue_free_at, INF if c.get("wait", false) else float(queue.get("max_wait", 2.0)))
	if at < 0.0:
		return
	_queue_free_at = at + stream.get_length()
	_sounding[cue] = true
	if at <= now:
		_start(cue, c, stream)
	else:
		get_tree().create_timer(at - now).timeout.connect(_start.bind(cue, c, stream))


## When a queued cue asked for at `now` starts: at once if the queue is free, else when
## it frees (`free_at`); -1 (dropped) if that's more than `max_wait` away.
static func queue_slot(now: float, free_at: float, max_wait: float) -> float:
	var at := maxf(now, free_at)
	return -1.0 if at - now > max_wait else at


func _start(cue: String, c: Dictionary, stream: AudioStream) -> void:
	_sounding[cue] = true
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = str(c.get("bus", "Master"))
	p.volume_db = float(c.get("db", 0.0))
	add_child(p)
	p.finished.connect(func():
		_sounding.erase(cue)
		p.queue_free())
	p.play()
	if c.get("duck", false):
		_duck()


## The old music fades out as the new fades in. A cue with a "pool" plays phrases from
## that pool instead of one loop (audio.json map_ambience: the map's day and night, the
## title and victory screens), the first one at once; between two pools that turn
## (day and night), the phrase playing finishes and the turn plays instead of a crossfade.
func _music(cue: String) -> void:
	if cue == music_cue:
		return
	var c: Dictionary = cues.get(cue, {})
	var pool := str(c.get("pool", ""))
	var turn := _pool != "" and pool != "" and _pool_cfg(_pool).has("turn_in") and _pool_cfg(pool).has("turn_in")
	music_cue = cue
	_pool = pool
	_pool_gen += 1
	_ambience(str(_pool_cfg(pool).get("ambience", "")))
	if turn:
		if _music_player and _music_player.playing:
			_turn_next = true  # when the phrase playing ends
		else:
			_turn()
		return
	_turn_next = false
	_last_phrase = -1
	var old := _music_player
	_music_player = null
	if old:
		var out := old.create_tween()
		out.tween_property(old, "volume_db", -60.0, _fade)
		out.tween_callback(old.queue_free)
	if pool != "":
		_phrase()
		return
	var stream := _stream(str(c.get("file", "")))
	if stream == null:
		return
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = str(c.get("bus", "Music"))
	p.volume_db = -60.0 if old else float(c.get("db", 0.0))
	add_child(p)
	p.play()
	if old:
		p.create_tween().tween_property(p, "volume_db", float(c.get("db", 0.0)), _fade).set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_music_player = p


func _pool_cfg(pool: String) -> Dictionary:
	return amb.get("pools", {}).get(pool, {})


## A pool's phrase files: <prefix>NN.wav in the phrases folder, sorted.
func _phrases(pool: String) -> Array:
	if not _pool_files.has(pool):
		var dir := str(amb.get("phrases", ""))
		var prefix := str(_pool_cfg(pool).get("prefix", pool + "_"))
		var files := []
		if DirAccess.dir_exists_absolute(dir):
			for f in ResourceLoader.list_directory(dir):
				if f.begins_with(prefix) and f.get_extension() == "wav":
					files.append(dir + f)
		files.sort()
		_pool_files[pool] = files
	return _pool_files[pool]


## The next phrase: any but the last one (pick_phrase); now and then one is sat out.
func _phrase() -> void:
	var files := _phrases(_pool)
	if files.is_empty():
		return
	var k := pick_phrase(files.size(), _last_phrase, _rng.randf())
	var stream := _stream(files[k])
	if _rng.randf() < float(_pool_cfg(_pool).get("rest_chance", amb.get("rest_chance", 0.0))):
		_wait(stream.get_length(), _phrase)
		return
	_last_phrase = k
	_play_phrase(stream)


## Plays one phrase or turn on the Music bus; when it ends: the turn if one is due, else
## a gap of silence, then the next phrase.
func _play_phrase(stream: AudioStream) -> void:
	var p := AudioStreamPlayer.new()
	p.stream = stream
	p.bus = "Music"
	p.volume_db = float(amb.get("phrase_db", 0.0)) + float(_pool_cfg(_pool).get("db", 0.0))
	add_child(p)
	p.finished.connect(func():
		p.queue_free()
		if p != _music_player:
			return  # faded out for other music
		_music_player = null
		if _turn_next:
			_turn()
		else:
			_wait(_gap(), _phrase))
	p.play()
	_music_player = p


## The turn into the pool now playing (dusk into night, dawn into day), then on with it.
func _turn() -> void:
	_turn_next = false
	_last_phrase = -1
	var stream := _stream(str(amb.get("phrases", "")) + str(amb.get("turns", {}).get(_pool_cfg(_pool).get("turn_in", ""), "")))
	if stream:
		_play_phrase(stream)
	else:
		_phrase()


## A random gap length from the pool's "gap" (or map_ambience's), in seconds.
func _gap() -> float:
	var g: Array = _pool_cfg(_pool).get("gap", amb.get("gap", [0, 0]))
	return _rng.randf_range(float(g[0]), float(g[1]))


## Calls `then` after `seconds`, unless the music has changed since (paused or not).
func _wait(seconds: float, then: Callable) -> void:
	var gen := _pool_gen
	get_tree().create_timer(seconds).timeout.connect(func():
		if gen == _pool_gen:
			then.call())


## Which phrase of `count` plays next for a random `r` in [0, 1): any but `last`.
static func pick_phrase(count: int, last: int, r: float) -> int:
	if count <= 1:
		return 0
	if last < 0:
		return mini(int(r * count), count - 1)
	var k := mini(int(r * (count - 1)), count - 2)
	return k + 1 if k >= last else k


## The map's environmental sound for `state` (day, night; "" for none): its bed loops,
## crossfading over bed_fade when the state changes, and the other files are one-shots
## at random spacing, volume, pitch and pan, on the Effects bus.
func _ambience(state: String) -> void:
	if state == _amb_state:
		return
	_amb_state = state
	_amb_gen += 1
	var fade := float(amb.get("bed_fade", 8.0))
	if _bed:
		var old := _bed
		var out := old.create_tween()
		out.tween_property(old, "volume_db", -60.0, fade)
		out.tween_callback(old.queue_free)
		_bed = null
	if state == "":
		return
	var dir := str(amb.get("ambience", "")) + state + "/"
	var shots := []
	if DirAccess.dir_exists_absolute(dir):
		for f in ResourceLoader.list_directory(dir):
			if f.get_extension() != "wav":
				continue
			if f.begins_with("bed") and _bed == null:
				var bed := _stream(dir + f) as AudioStreamWAV
				bed.loop_mode = AudioStreamWAV.LOOP_FORWARD
				bed.loop_begin = 0
				bed.loop_end = int(bed.get_length() * bed.mix_rate)
				_bed = AudioStreamPlayer.new()
				_bed.stream = bed
				_bed.bus = "Effects"
				_bed.volume_db = -60.0
				add_child(_bed)
				_bed.play()
				_bed.create_tween().tween_property(_bed, "volume_db", float(amb.get("bed_db", 0.0)), fade)
			elif not f.begins_with("bed"):
				shots.append(dir + f)
	if not shots.is_empty():
		_shot(shots, _amb_gen)


func _shot(shots: Array, gen: int) -> void:
	var g: Array = amb.get("shot_gap", [6, 25])
	get_tree().create_timer(_rng.randf_range(float(g[0]), float(g[1]))).timeout.connect(func():
		if gen != _amb_gen:
			return
		var p := AudioStreamPlayer.new()
		p.stream = _stream(shots[_rng.randi() % shots.size()])
		p.bus = "Effects"
		var v: Array = amb.get("shot_db", [-10, -10])
		p.volume_db = _rng.randf_range(float(v[0]), float(v[1]))
		var pitch := float(amb.get("shot_pitch", 0.0))
		p.pitch_scale = 1.0 + _rng.randf_range(-pitch, pitch)
		add_child(p)
		p.finished.connect(p.queue_free)
		p.play()
		_shot(shots, gen))


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
