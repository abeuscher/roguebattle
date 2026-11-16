extends SceneTree
## Watch run (playtest round 22): plays a real map in a window, your side by a simple
## autopilot, and records when each window, player tip, sound, music change, banner and
## camera glide starts and ends, to look for collisions (two things at once, the camera
## moving with nothing to say why). The autopilot keeps squads deployed and heading for the
## nearest place it doesn't hold, starts every fight, recruits, takes offered cards, and
## reads each window and tip for READ_MS before moving on.
##
##   godot --path . --resolution 1920x1080 -s res://tools/watch_run.gd -- [seed] [days] [WxH] [loud]
##
## Writes user://watch_<seed>.txt: the timeline (as it goes), then the flags. Every tip
## shows; tips seen are saved to user://watch_options.json, never the player's options.

const WINDOWS := ["_log_panel", "_notes_log", "_debug_panel", "_menu", "_main_menu", "_battle", "_encounter",
		"_rare_popup", "_edit", "_deploy_menu", "_confirm", "_building_popup", "_enemy_popup", "_shop",
		"_recruit_popup", "_liberation_popup", "_end_screen", "_chooser", "_ledger", "_lost_popup"]
const PRESS := ["Got it", "Begin Battle", "Fight", "Continue", "Take", "Recruit", "Done (U)", "Leave", "OK"]
const READ_MS := 1500  # how long the autopilot "reads" a window or tip before pressing on

var bm: Battlemap
var seed := 1
var days := 4.0
var size := Vector2i(800, 450)
var t0 := 0
var lines := []  # [msec, kind, text]
var open := {}  # window -> msec it opened
var tip_at := -1
var cam_from := Vector2.ZERO
var cam_last := Vector2.ZERO
var cam_zoom := Vector2.ONE
var cam_moving_since := -1
var heard := {}  # AudioStreamPlayer instance id -> true
var music := ""
var banner := ""
var places := []
var next_orders := 0
var _flushed := 0


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		seed = int(args[0])
	if args.size() > 1:
		days = float(args[1])
	if args.size() > 2:
		var wh := args[2].split("x")
		size = Vector2i(int(wh[0]), int(wh[1]))
	PlayerOptions.save_path = "user://watch_options.json"  # tips seen go here, never into the player's options
	call_deferred("_begin", args)


## The map, once the tree is up (Sound and the map need it).
func _begin(args: PackedStringArray) -> void:
	var data := GameData.load_dir()
	var options := PlayerOptions.load_values(data, "user://__watch_defaults.json")  # the defaults: every tip shows
	if "loud" not in args:
		options["master_volume"] = 0  # silent unless asked: the sounds still start, so they're still recorded
	Sound.start(root, data.audio, options)
	var cfg := GameConfig.create(data, seed)
	cfg.set_value("width", size.x)
	cfg.set_value("height", size.y)
	bm = Battlemap.new()
	bm.options = options
	root.add_child(bm)
	bm.start(data, GameLog.new(), cfg)
	places = bm.state.map.buildings.filter(func(b): return b["type"] in BoardSim.KINDS)
	t0 = Time.get_ticks_msec()
	_add("start", "seed %d, %dx%d, %d places" % [seed, size.x, size.y, places.size()])


func _now() -> int:
	return Time.get_ticks_msec() - t0


func _add(kind: String, text: String) -> void:
	lines.append([_now(), kind, text])


func _process(_delta: float) -> bool:
	if bm == null or bm.state == null:
		return false
	var st := bm.state
	_record()
	_pilot(st)
	if _now() - _flushed > 5000:  # as it goes, with what it's waiting on, in case it sticks
		_flushed = _now()
		_add("state", "tick %d, %s, free %s, open %s, tip %s, squads out %d" % [st.clock.tick, "paused" if st.clock.paused else "running",
				bm._free(), ",".join(open.keys()), is_instance_valid(bm._tip), st.player_squads().size()])
		_write()
	if st.game_over != "" or st.clock.tick >= days * GameClock.TICKS_PER_DAY:
		_add("end", st.game_over if st.game_over != "" else "%s days" % str(days))
		_finish()
		return true
	return false


# --- What happens -------------------------------------------------------------------

func _record() -> void:
	for w in WINDOWS:
		var node = bm.get(w)
		var up: bool = node != null and is_instance_valid(node) and (not node is CanvasItem or node.is_visible_in_tree())
		if up and not open.has(w):
			open[w] = _now()
			_add("open", w.trim_prefix("_") + _detail(w, node))
		elif not up and open.has(w):
			_add("close", w.trim_prefix("_"))
			open.erase(w)
	var tip_up := is_instance_valid(bm._tip)
	if tip_up and tip_at < 0:
		tip_at = _now()
		_add("tip", str(bm._tip.get_meta("id", "?")))
	elif not tip_up and tip_at >= 0:
		tip_at = -1
		_add("tip_close", "")
	var cam := bm.camera.position
	var moved := cam.distance_to(cam_last) > 0.5 or not bm.camera.zoom.is_equal_approx(cam_zoom)
	if moved and cam_moving_since < 0:
		cam_moving_since = _now()
		cam_from = cam_last
	elif not moved and cam_moving_since >= 0:
		var hexes := cam.distance_to(cam_from) / MapView.HEX_SIZE
		_add("camera", "glided %.0f (%d ms)" % [hexes, _now() - cam_moving_since])
		cam_moving_since = -1
	cam_last = cam
	cam_zoom = bm.camera.zoom
	if Sound._it:
		for c in Sound._it.get_children():
			if c is AudioStreamPlayer and not heard.has(c.get_instance_id()) and c != Sound._it._music_player and c != Sound._it._bed:
				heard[c.get_instance_id()] = true
				if c.stream and c.bus != Sound.AMBIENCE_BUS and not c.bus.begins_with(Sound.AMBIENCE_BUS):
					_add("sound", c.stream.resource_path.get_file().get_basename() + " (%.1f s, %s)" % [c.stream.get_length(), c.bus])
		if Sound._it.music_cue != music:
			music = Sound._it.music_cue
			_add("music", music)
	var b: String = bm.hud._banner_text if "_banner_text" in bm.hud else ""
	if b != banner:
		banner = b
		if b != "":
			_add("banner", b.left(90))


func _detail(w: String, node: Object) -> String:
	if w == "_liberation_popup" and bm.state:
		return ""
	if w == "_encounter" or w == "_battle":
		var p := bm.state.pending
		return " (%s vs %s)" % [p.sides[0].name, p.sides[1].name] if p else ""
	return ""


# --- The autopilot --------------------------------------------------------------------

func _pilot(st: GameState) -> void:
	# Read what's up for a moment, then press on: the tip first, then the topmost window.
	if is_instance_valid(bm._tip):
		if _now() - tip_at >= READ_MS:
			_press(bm._tip)
		return
	for w in ["_battle", "_encounter", "_recruit_popup", "_rare_popup", "_liberation_popup", "_lost_popup", "_ledger", "_shop", "_edit", "_menu", "_chooser"]:
		var node = bm.get(w)
		if node == null or not is_instance_valid(node):
			continue
		if not open.has(w) or _now() - int(open[w]) < READ_MS:
			return
		if w == "_battle":
			_press(node)  # Fight, then Continue at the end (it plays out between)
			return
		if w == "_edit":  # the opening Edit Units: the army as Auto pick army sorted it
			node.emit_signal("closed")
			return
		if not _press(node) and node.has_signal("closed"):
			node.emit_signal("closed")
		elif not open.has(w):
			pass
		if w == "_recruit_popup" and is_instance_valid(node) and _now() - int(open[w]) > READ_MS * 3:
			node.emit_signal("done")
		if w in ["_menu", "_chooser"] and is_instance_valid(node):
			bm._close_menu() if w == "_menu" else node.queue_free()
		return
	if st.clock.paused and bm._free():
		st.toggle_pause()  # starts the map, and resumes after a battle that paused it
	if st.clock.speed_index != st.clock._speeds.size() - 1:
		st.set_speed_index(st.clock._speeds.size() - 1)
	if _now() >= next_orders and bm._free():
		next_orders = _now() + 2000
		for s in st.army.squads():
			if s not in st.squads and st.deploy_blocker(s) == "":
				var target := _nearest_free(st, st.map.player_base)
				if target >= 0:
					st.deploy(s, PackedInt32Array([target]))
					bm._sync_tokens()
		BoardSim._orders(st, places)


func _nearest_free(st: GameState, from: int) -> int:
	var best := -1
	var best_d := -1
	for b in places:
		if b["owner"] == "player":
			continue
		var d := Hex.distance(st.map.hex_at(from), st.map.hex_at(b["hex"]))
		if best_d < 0 or d < best_d:
			best = b["hex"]
			best_d = d
	return best


## Presses the first visible, enabled button under `node` whose text starts with one of
## PRESS (in that order). False if there's none.
func _press(node: Node) -> bool:
	var buttons := node.find_children("*", "Button", true, false)
	for label in PRESS:
		for b in buttons:
			var btn := b as Button
			if btn.is_visible_in_tree() and not btn.disabled and btn.text.begins_with(label):
				btn.pressed.emit()
				return true
	return false


# --- The report -----------------------------------------------------------------------

func _write(flags := false) -> void:
	var out := PackedStringArray()
	for l in lines:
		out.append("%7.2f  %-9s %s" % [l[0] / 1000.0, l[1], l[2]])
	if flags:
		out.append("")
		out.append("--- Flags ---")
		out.append_array(_flags())
	var f := FileAccess.open("user://watch_%d.txt" % seed, FileAccess.WRITE)
	f.store_string("\n".join(out))
	f.close()


func _finish() -> void:
	_write(true)
	quit()


## What to look at: a glide with no window or tip around it to say why; a window or tip
## within a second of the last one closing; two windows up at once; sounds on top of
## each other (stingers and voice lines); a tip whose window changed under it.
func _flags() -> PackedStringArray:
	var out := PackedStringArray()
	for i in lines.size():
		var l: Array = lines[i]
		if l[1] == "camera" and not l[2].begins_with("glided 0"):
			var why := false
			for k in lines:
				if absi(int(k[0]) - int(l[0])) <= 2500 and k[1] in ["open", "tip", "banner"]:
					why = true
			if not why:
				out.append("%.2f  camera moved with no window, tip or banner near it: %s" % [l[0] / 1000.0, l[2]])
		if l[1] in ["open", "tip"]:
			for j in range(i - 1, -1, -1):
				var k: Array = lines[j]
				if int(l[0]) - int(k[0]) > 1000:
					break
				if k[1] in ["close", "tip_close"] and not (l[1] == "tip" and k[1] == "close"):
					out.append("%.2f  %s %s came %d ms after %s %s closed" % [l[0] / 1000.0, l[1], l[2], int(l[0]) - int(k[0]), k[1], k[2]])
					break
	var up := {}
	for l in lines:
		if l[1] == "open":
			if up.size() > 0 and not l[2].begins_with("shop") and not l[2].begins_with("edit"):
				out.append("%.2f  %s opened over %s" % [l[0] / 1000.0, l[2], ", ".join(up.keys())])
			up[l[2].split(" ")[0]] = true
		elif l[1] == "close":
			up.erase(l[2])
	var ends := []  # [msec it ends, name] of stingers and voice lines
	for l in lines:
		if l[1] != "sound" or not ("Voice" in l[2] or "stinger" in l[2].to_lower() or "riff" in l[2]):
			continue
		for e in ends:
			if int(e[0]) > int(l[0]):
				out.append("%.2f  %s over %s" % [l[0] / 1000.0, l[2], e[1]])
		var secs := float(l[2].get_slice("(", 1).get_slice(" s", 0))
		ends.append([int(l[0]) + roundi(secs * 1000.0), l[2]])
	return out
