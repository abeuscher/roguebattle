extends Node2D
## The battlemap (SPEC §5): map view, camera, clock, HUD, minimap, log and squad orders.
## For now it also generates maps itself (R, P, S) and places one test squad;
## the configurator and army setup take that over later.

const NIGHT := Color(0.45, 0.5, 0.78)  # map tint at night
const CLICK_SLOP := 6.0  # a press and release closer than this is a click, not a drag
const TEST_TRAVEL := ["plains", "forest", "mountain", "swamp", "snow", "desert", "sky", ""]

var data: GameData
var log: GameLog
var state: GameState
var view := MapView.new()
var camera := MapCamera.new()
var hud := Hud.new()
var night := CanvasModulate.new()
var _ui := CanvasLayer.new()
var _log_panel: LogPanel
var _menu: SquadMenu
var _tokens := {}  # squad id -> SquadToken
var _selected: Squad  # the squad whose menu or move order is open (the game is held meanwhile)
var _planning := false  # laying rally points for _selected
var _points := PackedInt32Array()
var _planned := PackedInt32Array()  # route through _points
var _press_at := Vector2.ZERO
var _seed := 0
var _preset := 0
var _size := 0
var _info := ""


func _ready() -> void:
	data = GameData.load_dir()
	log = GameLog.new("user://logs/game-%s.log" % Time.get_datetime_string_from_system().replace(":", "-"))
	RenderingServer.set_default_clear_color(Color("#12161c"))
	for node in [view, camera, night, _ui]:
		add_child(node)
	_ui.add_child(hud)
	camera.view_changed.connect(_on_view_changed)
	hud.minimap.jump.connect(camera.center_on)
	hud.squad_pressed.connect(_center_on_squad)
	get_viewport().size_changed.connect(camera.fit)
	_generate(randi())


func _process(delta: float) -> void:
	if state == null:
		return
	for i in state.clock.advance(delta):
		state.step()
	night.color = Color.WHITE.lerp(NIGHT, darkness(state.clock.minute_of_day()))
	_update_tokens()
	_update_paths()
	hud.refresh(state)


## 0 by day, 1 at night, with an hour of dusk after 18:00 and of dawn before 06:00.
static func darkness(minute: int) -> float:
	if minute >= GameClock.DAWN and minute < GameClock.DUSK:
		return 0.0
	if minute >= GameClock.DUSK:
		return minf(1.0, (minute - GameClock.DUSK) / 60.0)
	return clampf((GameClock.DAWN - minute) / 60.0, 0.0, 1.0)


func _generate(seed: int) -> void:
	_end_selection()
	_seed = seed
	var presets: Array = data.mapgen["presets"].keys()
	var sizes: Array = data.mapgen["sizes"].keys()
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed, {"preset": presets[_preset % presets.size()], "size": sizes[_size % sizes.size()]})
	_info = "Seed %d  ·  %s  ·  %s %dx%d  ·  generated in %d ms" % [seed, map.settings["preset"].capitalize(),
			map.settings["size"], map.width, map.height, Time.get_ticks_msec() - started]
	state = GameState.new(data, map, log)
	view.show_map(map, data)
	var test: Dictionary = data.rules["placeholder_squad"]
	state.add_squad(test["name"], map.player_base, test["travel_type"], int(test["speed_tier"]))
	_tokens.clear()
	for s in state.squads:
		var token := SquadToken.new()
		token.squad = s
		view.add_object(token)
		_tokens[s.id] = token
	hud.set_squads(state.squads)
	hud.minimap.set_map(map, data)
	hud.place()
	camera.world = MapView.world_size(map)
	camera.fit()
	_update_help()


func _update_help() -> void:
	var text := _info + "\nClick a squad to give orders  ·  1-9: find squad  ·  T: test squad's travel type  ·  Space: pause  ·  PgUp/PgDn: speed  ·  L: log" \
			+ "\nWheel: zoom  ·  Drag: pan  ·  F: fit  ·  R: new map  ·  P: preset  ·  S: size  ·  H: hidden sites and lairs  ·  G: grid  ·  O: overlay (%s)" % MapOverlay.NAMES[view.overlay]
	var legend := MapOverlay.legend(view.overlay, state.map)
	if legend != "":
		text += "\n" + legend
	hud.set_help(text)


func _on_view_changed() -> void:
	view.set_zoom(camera.zoom.x)
	hud.minimap.set_view(camera.visible_rect())
	for token in _tokens.values():  # like building icons, tokens stay readable when zoomed out
		token.scale = Vector2.ONE * maxf(1.0, 0.7 / camera.zoom.x)


# --- Squads on the map --------------------------------------------------------

## Places each token, sliding smoothly between hexes as the squad moves.
func _update_tokens() -> void:
	for s in state.squads:
		var token: SquadToken = _tokens[s.id]
		var at := MapView.hex_center(state.map, s.hex)
		if s.is_moving():
			var t := clampf((s.progress + state.clock.fraction()) / state.step_ticks(s, s.path[0]), 0.0, 1.0)
			at = at.lerp(MapView.hex_center(state.map, s.path[0]), t)
		token.position = at
		token.selected = s == _selected


func _update_paths() -> void:
	var paths := view.paths
	paths.committed.clear()
	for s in state.squads:
		if s.is_moving() and not (_planning and s == _selected):
			paths.committed.append(_line(s.hex, s.path))
	paths.planned = _line(_selected.hex, _planned) if _planning else PackedVector2Array()
	paths.rally.clear()
	for p in (_points if _planning else PackedInt32Array()):
		paths.rally.append(MapView.hex_center(state.map, p))
	paths.queue_redraw()


func _line(start: int, route: PackedInt32Array) -> PackedVector2Array:
	var line := PackedVector2Array([MapView.hex_center(state.map, start)])
	for i in route:
		line.append(MapView.hex_center(state.map, i))
	return line


func _center_on_squad(id: int) -> void:
	if id >= 1 and id <= state.squads.size():
		camera.center_on(_tokens[id].position)


func _squad_at(world: Vector2) -> Squad:
	for s in state.squads:
		if _tokens[s.id].position.distance_to(world) < MapView.HEX_SIZE * 1.2:
			return s
	return null


func _hex_at(world: Vector2) -> int:
	var h := Hex.from_pixel(world, MapView.HEX_SIZE)
	return state.map.index_of(h) if state.map.in_bounds(h) else -1


# --- Selection, menu and move orders (SPEC §5.3) ------------------------------

## Selecting a squad pauses the game and opens its menu.
func _select(s: Squad) -> void:
	if _selected == null:
		state.clock.hold()
	_selected = s
	_planning = false
	_open_menu()


func _open_menu() -> void:
	hud.show_banner("")
	_menu = SquadMenu.new()
	_ui.add_child(_menu)
	_menu.setup(state, _selected)
	_menu.move.connect(_start_planning)
	_menu.return_to_base.connect(func():
		state.order_move(_selected, PackedInt32Array([state.map.player_base]))
		_close_menu()
		_open_menu())
	_menu.closed.connect(_end_selection)


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


## Closing the menu resumes play.
func _end_selection() -> void:
	_close_menu()
	if _selected != null:
		state.clock.release()
	_selected = null
	_planning = false
	hud.show_banner("")


func _start_planning() -> void:
	_close_menu()
	_planning = true
	_points.clear()
	_planned.clear()
	hud.show_banner("Move %s: left-click hexes to lay rally points, then click the last point again to commit.  Right-click: undo  ·  Esc: back" % _selected.name)


func _plan_click(hex: int) -> void:
	if hex < 0:
		return
	if not _points.is_empty() and hex == _points[_points.size() - 1]:
		state.order_move(_selected, _points)  # clicking the last point again commits
		_planning = false
		_open_menu()
		return
	var leg := state.pathfinder.find(_points[_points.size() - 1] if not _points.is_empty() else _selected.hex,
			hex, _selected.travel_type, _selected.sky)
	if leg.is_empty():
		hud.show_banner("%s can't reach that hex." % _selected.name, 2.0)
		return
	_points.append(hex)
	_planned.append_array(leg.slice(1))
	_show_plan()


func _undo_point() -> void:
	if _points.is_empty():
		return
	_points.resize(_points.size() - 1)
	_planned = state.plan(_selected, _points)
	_show_plan()


func _show_plan() -> void:
	var eta := GameState.duration_text(state.route_ticks(_selected, _planned))
	hud.show_banner("Move %s: %d rally point%s, %d hexes, about %s.  Click the last point again to commit  ·  Right-click: undo  ·  Esc: back" % [
			_selected.name, _points.size(), "" if _points.size() == 1 else "s", _planned.size(), eta])


# --- Log ------------------------------------------------------------------------

func _open_log() -> void:
	_log_panel = LogPanel.new()
	_ui.add_child(_log_panel)
	_log_panel.show_log(log)
	_log_panel.closed.connect(_close_log)
	state.clock.hold()


func _close_log() -> void:
	_log_panel.queue_free()
	_log_panel = null
	state.clock.release()


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _log_panel or _menu:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press_at = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.distance_to(_press_at) < CLICK_SLOP:
			var world := get_canvas_transform().affine_inverse() * mb.position
			if _planning:
				_plan_click(_hex_at(world))
			else:
				var s := _squad_at(world)
				if s:
					_select(s)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _planning:
			_undo_point()
		return
	if not (event is InputEventKey and event.is_pressed()):
		return
	var key := (event as InputEventKey).keycode
	if _planning:
		if key == KEY_ESCAPE:
			_planning = false
			_open_menu()
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_SPACE:
			state.toggle_pause()
		KEY_PAGEUP:
			state.set_speed_index(state.clock.speed_index + 1)
		KEY_PAGEDOWN:
			state.set_speed_index(state.clock.speed_index - 1)
		KEY_L:
			_open_log()
		KEY_T:
			var s := state.squads[0]
			var next: String = TEST_TRAVEL[(TEST_TRAVEL.find("sky" if s.sky else s.travel_type) + 1) % TEST_TRAVEL.size()]
			s.sky = next == "sky"
			s.travel_type = "" if s.sky else next
			s.path.clear()
			s.rally.clear()
			s.progress = 0.0
			hud.show_banner("%s now travels as: %s (order cleared)" % [s.name, s.travel_name()], 2.5)
		KEY_R:
			_generate(randi())
		KEY_F:
			camera.fit()
		KEY_P:
			_preset += 1
			_generate(_seed)
		KEY_S:
			_size += 1
			_generate(_seed)
		KEY_H:
			view.show_secrets = not view.show_secrets
		KEY_G:
			view.show_grid = not view.show_grid
		KEY_O:
			view.overlay = MapOverlay.MODES[(MapOverlay.MODES.find(view.overlay) + 1) % MapOverlay.MODES.size()]
			_update_help()
		_:
			if key >= KEY_1 and key <= KEY_9:
				_center_on_squad(key - KEY_0)
			return
	get_viewport().set_input_as_handled()
