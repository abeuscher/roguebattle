class_name Battlemap
extends Node2D
## The battlemap (SPEC §5): map view, camera, clock, HUD, minimap, log, squad
## orders and the Esc menu. For now one test squad stands at the Player Base and
## the enemy's squads stand at their posts; real army setup arrives in M3 and M4.
## Contact and ranged attacks open the battle view; the map holds until it closes.

signal to_title
signal quit_game
signal save_settings

const NIGHT := Color(0.45, 0.5, 0.78)  # map tint at night
const ENEMY := Color("#c8402f")
const CLICK_SLOP := 6.0  # a press and release closer than this is a click, not a drag
const TEST_TRAVEL := ["plains", "forest", "mountain", "swamp", "snow", "desert", "shallow", "deep", "sky", ""]

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
var _main_menu: MainMenu
var _battle: BattleView
var _edit: EditUnits
var _tokens := {}  # squad id -> SquadToken
var _selected: Squad  # the squad whose menu or move order is open (the game is held meanwhile)
var _planning := false  # laying rally points for _selected
var _firing := false  # choosing a ranged-attack target for _selected
var _shown_sites := {}  # building index -> true once its icon is revealed
var _points := PackedInt32Array()
var _planned := PackedInt32Array()  # route through _points
var _press_at := Vector2.ZERO
var _info := ""


## Starts a map from the configurator's settings. `map` is the configurator's
## preview, already built from the same settings; without it the map is generated here.
func start(game_data: GameData, game_log: GameLog, config: GameConfig, map: MapData = null) -> void:
	data = game_data
	log = game_log
	for node in [view, camera, night, _ui]:
		add_child(node)
	_ui.add_child(hud)
	camera.view_changed.connect(_on_view_changed)
	hud.minimap.jump.connect(camera.center_on)
	hud.squad_pressed.connect(_center_on_squad)
	get_viewport().size_changed.connect(camera.fit)
	var started := Time.get_ticks_msec()
	if map == null:
		map = MapGen.generate(data, config.seed, config.map_overrides())
	_info = "Seed %d  ·  %s  ·  %s %dx%d  ·  share code %s" % [config.seed, map.settings["preset"].capitalize(),
			map.settings["size"], map.width, map.height, config.to_code()]
	state = GameState.new(data, map, log, config.game_settings())
	view.show_map(map, data)
	state.setup_army()
	state.place_enemies()
	_sync_tokens()
	hud.set_squads(state.player_squads())
	hud.minimap.set_map(map, data)
	hud.place()
	camera.world = MapView.world_size(map)
	camera.fit()
	camera.fit.call_deferred()  # again once the camera is live, so the minimap frame is right
	_update_help()
	print("Battlemap ready in %d ms" % (Time.get_ticks_msec() - started))


func _process(delta: float) -> void:
	if state == null:
		return
	for i in state.clock.advance(delta):
		state.step()
		if state.pending:
			break
	if state.pending and _battle == null:
		_open_battle()
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


func _update_help() -> void:
	var text := _info + "\nClick a squad to give orders  ·  1-9: find squad  ·  T: test squad's travel type  ·  Space: pause  ·  PgUp/PgDn: speed  ·  U: edit units  ·  L: log  ·  Esc: menu" \
			+ "\nWheel: zoom  ·  Drag: pan  ·  F: fit  ·  H: hidden sites and lairs  ·  G: grid  ·  O: overlay (%s)" % MapOverlay.NAMES[view.overlay]
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

## Adds tokens for squads new on the map and drops those of squads that left it
## (wiped out, driven off, or emptied in Edit Units).
func _sync_tokens() -> void:
	for id in _tokens.keys():
		if not state.squads.any(func(s: Squad): return s.id == id):
			_tokens[id].queue_free()
			_tokens.erase(id)
	for s in state.squads:
		if not _tokens.has(s.id):
			var token := SquadToken.new()
			token.squad = s
			if s.side != "player":
				token.color = ENEMY
			view.add_object(token)
			_tokens[s.id] = token


## Places each token, sliding smoothly between hexes as the squad moves. Enemies show
## only within sight (SPEC §8.5); hidden sites appear once seen.
func _update_tokens() -> void:
	for i in state.revealed:
		if not _shown_sites.has(i):
			_shown_sites[i] = true
			view.reveal(state.map.buildings[i]["hex"])
	for s in state.squads:
		var token: SquadToken = _tokens[s.id]
		var at := MapView.hex_center(state.map, s.hex)
		if s.is_moving():
			var t := clampf((s.progress + state.clock.fraction()) / state.step_ticks(s, s.path[0]), 0.0, 1.0)
			at = at.lerp(MapView.hex_center(state.map, s.path[0]), t)
		token.position = at
		token.selected = s == _selected
		token.visible = state.is_visible(s)


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
	if _tokens.has(id) and id < 100:
		camera.center_on(_tokens[id].position)


func _squad_at(world: Vector2) -> Squad:
	for s in state.squads:
		if state.is_visible(s) and _tokens[s.id].position.distance_to(world) < MapView.HEX_SIZE * 1.2:
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
	_menu.fire.connect(_start_firing)
	_menu.return_to_base.connect(func():
		state.order_move(_selected, PackedInt32Array([state.map.player_base]))
		_end_selection())
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
	_firing = false
	hud.show_banner("")


func _start_planning() -> void:
	_close_menu()
	_planning = true
	_points.clear()
	_planned.clear()
	hud.show_banner("Move %s: left-click hexes to lay rally points, then click the last point again to commit.  Right-click: undo  ·  Esc: back" % _selected.name)


func _start_firing() -> void:
	_close_menu()
	_firing = true
	hud.show_banner("Ranged attack with %s: click an enemy squad within %d hexes.  Esc: back" % [_selected.name, state.fire_range(_selected)])


func _fire_click(world: Vector2) -> void:
	var target := _squad_at(world)
	if target == null or target not in state.fire_targets(_selected):
		hud.show_banner("Pick a visible enemy squad within %d hexes.  Esc: back" % state.fire_range(_selected))
		return
	state.fire(_selected, target)
	_end_selection()


## Clicking an enemy shows what it is and how it compares with your first squad.
func _show_enemy(s: Squad) -> void:
	var own := state.player_squads()
	var label := Threat.label(state.data, own[0], s).to_lower() if not own.is_empty() else ""
	hud.show_banner("%s (%s): %d units. It looks %s." % [s.name, s.role.replace("_", " "), s.living().size(), label], 3.0)


func _plan_click(hex: int) -> void:
	if hex < 0:
		return
	if not _points.is_empty() and hex == _points[_points.size() - 1]:
		state.order_move(_selected, _points)  # clicking the last point again commits and resumes play
		_end_selection()
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


# --- Battle, log and Esc menu ---------------------------------------------------------

func _open_battle() -> void:
	_battle = BattleView.new()
	_ui.add_child(_battle)
	_battle.setup(state, state.pending)
	_battle.finished.connect(_close_battle)
	state.clock.hold()


func _close_battle(text: String) -> void:
	_battle.queue_free()
	_battle = null
	state.clock.release()
	hud.show_banner(text, 5.0)
	_sync_tokens()


func _open_edit() -> void:
	_edit = EditUnits.new()
	_ui.add_child(_edit)
	_edit.setup(state)
	_edit.closed.connect(_close_edit)
	state.clock.hold()


func _close_edit() -> void:
	_edit.queue_free()
	_edit = null
	state.after_edit()
	_sync_tokens()
	hud.set_squads(state.player_squads())
	state.clock.release()


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


func _open_main_menu() -> void:
	_main_menu = MainMenu.new()
	_ui.add_child(_main_menu)
	_main_menu.setup()
	_main_menu.resume.connect(_close_main_menu)
	_main_menu.save_settings.connect(func():
		save_settings.emit()
		_main_menu.note("Settings saved. The configurator will start from them."))
	_main_menu.to_title.connect(func(): to_title.emit())
	_main_menu.quit.connect(func(): quit_game.emit())
	state.clock.hold()


func _close_main_menu() -> void:
	_main_menu.queue_free()
	_main_menu = null
	state.clock.release()


# --- Input ------------------------------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if _log_panel or _menu or _main_menu or _battle or _edit:
		return
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
			_press_at = mb.position
		elif mb.button_index == MOUSE_BUTTON_LEFT and mb.position.distance_to(_press_at) < CLICK_SLOP:
			var world := get_canvas_transform().affine_inverse() * mb.position
			if _planning:
				_plan_click(_hex_at(world))
			elif _firing:
				_fire_click(world)
			else:
				var s := _squad_at(world)
				if s and s.side == "player":
					_select(s)
				elif s:
					_show_enemy(s)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _planning:
			_undo_point()
		return
	if not (event is InputEventKey and event.is_pressed()):
		return
	var key := (event as InputEventKey).keycode
	if _planning or _firing:
		if key == KEY_ESCAPE:
			_planning = false
			_firing = false
			_open_menu()
		get_viewport().set_input_as_handled()
		return
	match key:
		KEY_ESCAPE:
			_open_main_menu()
		KEY_SPACE:
			state.toggle_pause()
		KEY_PAGEUP:
			state.set_speed_index(state.clock.speed_index + 1)
		KEY_PAGEDOWN:
			state.set_speed_index(state.clock.speed_index - 1)
		KEY_L:
			_open_log()
		KEY_U:
			_open_edit()
		KEY_T:
			var s := state.player_squads()[0]
			var next: String = TEST_TRAVEL[(TEST_TRAVEL.find("sky" if s.sky else s.travel_type) + 1) % TEST_TRAVEL.size()]
			s.sky = next == "sky"
			s.travel_type = "" if s.sky else next
			s.path.clear()
			s.rally.clear()
			s.progress = 0.0
			hud.show_banner("%s now travels as: %s (order cleared)" % [s.name, s.travel_name()], 2.5)
		KEY_F:
			camera.fit()
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
