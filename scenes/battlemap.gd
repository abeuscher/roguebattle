class_name Battlemap
extends Node2D
## The battlemap (SPEC §5): map view, camera, clock, HUD, minimap, log, squad
## orders and the Esc menu. The Opinion Leader's squad stands at the Player Base
## and the enemy's squads stand at their posts (their AI roles arrive later in M4).
## Contact and ranged attacks open the battle view; the map holds until it closes.

signal to_title
signal quit_game
signal save_settings
signal regenerate(seed: int)  # debug panel: a fresh map from this seed, same settings

const NIGHT := Color(0.45, 0.5, 0.78)  # map tint at night
const ENEMY := Color("#c8402f")
const CLICK_SLOP := 6.0  # a press and release closer than this is a click, not a drag
const STACK_SPREAD := 16.0  # world units between flags of squads standing on the same hex
const TEST_TRAVEL := ["plains", "forest", "mountain", "swamp", "snow", "desert", "shallow", "deep", "sky", ""]

var data: GameData
var options := {}  # the player's options (PlayerOptions), set by main
var log: GameLog
var state: GameState
var view := MapView.new()
var camera := MapCamera.new()
var hud := Hud.new()
var night := CanvasModulate.new()
var _ui := CanvasLayer.new()
var _log_panel: LogPanel
var _debug_panel: DebugPanel
var _recruit_popup: RecruitPopup
var _liberation_popup: LiberationPopup
var _end_screen: EndScreen
var _menu: SquadMenu
var _main_menu: MainMenu
var _battle: BattleView
var _encounter: EncounterPopup
var _announced := false  # the pending battle needs no encounter popup (already announced, or a recruit refused)
var _edit: EditUnits
var _deploy_menu: DeployMenu
var _confirm: ConfirmDialog
var _deploying := false  # _selected is a squad from base whose route is being laid
var _building_popup: BuildingPopup
var _shop: Control  # the shop screen or the supplies menu
var _cursor_flag: SquadToken  # while laying a route, the squad's flag replaces the mouse pointer
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
	hud.speed_chosen.connect(_on_speed_chosen)
	hud.edit_pressed.connect(func():
		if _can_open() and _selected == null:
			_open_edit())
	hud.deploy_pressed.connect(func():
		if _can_open() and _selected == null and state.deploy_menu_blocker() == "":
			_open_deploy_menu())
	hud.cards_pressed.connect(func():
		if _can_open() and _selected == null:
			_open_cards(false))
	hud.tech_pressed.connect(func():
		if _can_open() and _selected == null:
			_open_tech())
	get_viewport().size_changed.connect(camera.fit)
	var started := Time.get_ticks_msec()
	if map == null:
		map = MapGen.generate(data, config.seed, config.map_overrides())
	_info = "Seed %d  ·  %s  ·  %dx%d  ·  share code %s" % [config.seed, map.settings["preset"].capitalize(),
			map.width, map.height, config.to_code()]
	state = GameState.new(data, map, log, config.game_settings())
	view.show_map(map, data)
	state.setup_army(_wide_roster_count())
	state.place_enemies()
	state.place_neutrals()
	_sync_tokens()
	hud.set_squads(state.player_squads())
	hud.minimap.set_map(map, data)
	hud.place()
	camera.world = MapView.world_size(map)
	camera.fit()
	camera.fit.call_deferred()  # again once the camera is live, so the minimap frame is right
	_update_help()
	print("Battlemap ready in %d ms" % (Time.get_ticks_msec() - started))


## Developer override for playtesting unit variety: --wide-roster or
## --wide-roster=N on the command line (or Project Settings' editor/run/main_run_args,
## prefixed with --) swaps in Map1Setup.build_wide_roster() for the real §18 army.
## 0 (the default) means the real game's 6-squad roster.
func _wide_roster_count() -> int:
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--wide-roster"):
			return clampi(int(arg.split("=")[1]) if "=" in arg else int(data.rules["army_size"]), 1, int(data.rules["army_size"]))
	return 0


func _process(delta: float) -> void:
	if state == null:
		return
	for i in state.clock.advance(delta):
		state.step()
		if state.pending or not state.pending_recruit.is_empty() or state.game_over != "":
			break
	if state.pending and _battle == null and _encounter == null and _recruit_popup == null:
		if _announced or state.pending.ranged_only:
			_open_battle()
		else:
			_open_encounter()
	if not state.pending_recruit.is_empty() and _recruit_popup == null:
		_open_recruit_popup()
	_pump_liberations()
	if not state.card_offer.is_empty() and _can_open() and _selected == null:
		_open_cards(true)
	if state.game_over != "" and _end_screen == null and _can_open():
		_open_end_screen()
	if state.noon_report != "":
		hud.show_banner(state.noon_report, 5.0)
		state.noon_report = ""
	if _tokens.size() != state.squads.size():  # a squad went into the base, or left the map
		_sync_tokens()
		hud.set_squads(state.player_squads())
	_update_cursor()
	var under := state.building_at(_hex_at(get_global_mouse_position())) if _planning and _confirm == null else {}
	view.hover_building(state.map.buildings.find(under) if not under.is_empty() else -1)
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
	var text := _info + "\nClick a squad to give orders  ·  1-9: find squad  ·  F8: test squad's travel type  ·  Space: pause  ·  PgUp/PgDn: speed  ·  L: log  ·  Esc: menu" \
			+ "\nWheel: zoom  ·  Drag: pan  ·  F: fit  ·  H: hidden sites and lairs  ·  G: grid  ·  O: overlay (%s)" % MapOverlay.NAMES[view.overlay]
	var legend := MapOverlay.legend(view.overlay, state.map)
	if legend != "":
		text += "\n" + legend
	hud.set_help(text)


func _on_view_changed() -> void:
	view.set_zoom(camera.zoom.x)
	hud.minimap.set_view(camera.visible_rect())
	for token in _tokens.values():
		token.scale = _token_scale()


## Like building icons, tokens stay readable when zoomed out.
func _token_scale() -> Vector2:
	return Vector2.ONE * maxf(1.0, 0.7 / camera.zoom.x)


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
			token.scale = _token_scale()  # new tokens match the current zoom
			view.add_object(token)
			_tokens[s.id] = token


## Places each token, sliding smoothly between hexes as the squad moves; squads standing
## on the same hex fan out side by side. Enemies show only within sight (SPEC §8.5);
## hidden sites appear once seen.
func _update_tokens() -> void:
	for i in state.revealed:
		if not _shown_sites.has(i):
			_shown_sites[i] = true
			view.reveal(state.map.buildings[i]["hex"])
	for i in state.map.buildings.size():
		var b: Dictionary = state.map.buildings[i]
		if BuildingIcons.TOPS.has(b["type"]):
			var flag: Color = {"player": SquadToken.PLAYER, "enemy": ENEMY}.get(b["owner"], Color.TRANSPARENT)
			view.update_building(i, b["hex"], not b["away"], flag, state.capture_progress(b))
	var stacks := {}  # hex -> squads standing there, in id order
	for s in state.squads:
		if not s.is_moving():
			stacks[s.hex] = stacks.get(s.hex, []) + [s]
	for s in state.squads:
		var token: SquadToken = _tokens[s.id]
		var at := MapView.hex_center(state.map, s.hex)
		if not s.is_moving():
			var stack: Array = stacks[s.hex]
			at.x += (stack.find(s) - (stack.size() - 1) / 2.0) * STACK_SPREAD
		else:
			var t := clampf((s.progress + state.clock.fraction()) / state.step_ticks(s, s.path[0]), 0.0, 1.0)
			at = at.lerp(MapView.hex_center(state.map, s.path[0]), t)
		token.position = at
		token.selected = s == _selected
		token.visible = state.is_visible(s)


func _update_paths() -> void:
	var paths := view.paths
	paths.committed.clear()
	for s in state.squads:
		if s.side == "player" and s.is_moving() and not (_planning and s == _selected):  # enemy routes would give hidden squads away (§8.5)
			paths.committed.append(_line(s.hex, s.path))
	paths.planned = _line(_selected.hex, _planned) if _planning else PackedVector2Array()
	paths.rally.clear()
	for p in (_points if _planning else PackedInt32Array()):
		paths.rally.append(MapView.hex_center(state.map, p))
	_update_debug_paths(paths)
	paths.queue_redraw()


## Debug overlays (§19.2): enemy and neutral roles and targets, player sight radii.
func _update_debug_paths(paths: PathView) -> void:
	paths.ai_lines.clear()
	paths.sight_rings.clear()
	if paths.show_ai:
		for s in state.squads:
			if s.side == "player":
				continue
			var target := s.path[s.path.size() - 1] if s.is_moving() else -1
			var role := s.role.replace("_", " ") + (" (%s)" % s.ai_mode if s.ai_mode != "" else "")
			var at: Vector2 = _tokens[s.id].position if _tokens.has(s.id) else MapView.hex_center(state.map, s.hex)
			paths.ai_lines.append([at, MapView.hex_center(state.map, target) if target >= 0 else at,
					"%s: %s" % [role, "moving" if target >= 0 else "holds"]])
	if paths.show_sight:
		var step := MapView.hex_center(state.map, 0).distance_to(MapView.hex_center(state.map, state.map.neighbor_indices(0)[0]))
		for s in state.player_squads():
			if _tokens.has(s.id):
				paths.sight_rings.append([_tokens[s.id].position, state.sight(s, s.hex) * step])


func _line(start: int, route: PackedInt32Array) -> PackedVector2Array:
	var line := PackedVector2Array([MapView.hex_center(state.map, start)])
	for i in route:
		line.append(MapView.hex_center(state.map, i))
	return line


func _center_on_squad(id: int) -> void:
	if _tokens.has(id) and id < 100:
		camera.center_on(_tokens[id].position)


func _squad_at(world: Vector2) -> Squad:
	var found := _squads_at(world)
	return found[0] if not found.is_empty() else null


## Visible squads whose flags are under the point, nearest first.
func _squads_at(world: Vector2) -> Array[Squad]:
	var out: Array[Squad] = []
	for s in state.squads:
		if state.is_visible(s) and _tokens[s.id].position.distance_to(world) < MapView.HEX_SIZE * 1.2:
			out.append(s)
	out.sort_custom(func(a: Squad, b: Squad): return _tokens[a.id].position.distance_to(world) < _tokens[b.id].position.distance_to(world))
	return out


## Your squads open their menu; enemies show what they are.
func _pick(s: Squad) -> void:
	if s.side == "player":
		_select(s)
	else:
		_show_enemy(s)


## Several flags (or flags over a building) under one click: a small menu at the pointer
## to choose between them.
func _choose(found: Array[Squad], building: Dictionary) -> void:
	var menu := PopupMenu.new()
	menu.add_theme_font_size_override("font_size", 18)
	for i in found.size():
		var s := found[i]
		menu.add_item("%d  %s" % [s.id, s.name] if s.side == "player" else "%s (%s)" % [s.name, s.role.replace("_", " ")], i)
	if not building.is_empty():
		menu.add_item(building.get("name", state.data.buildings[building["type"]]["name"]), found.size())
	menu.id_pressed.connect(func(i: int):
		if i < found.size():
			_pick(found[i])
		else:
			_open_building(building))
	menu.popup_hide.connect(menu.queue_free)
	_ui.add_child(menu)
	menu.popup(Rect2i(Vector2i(get_viewport().get_mouse_position()), Vector2i.ZERO))


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
		state.send_home(_selected)
		_end_selection()
		_sync_tokens()
		hud.set_squads(state.player_squads()))
	_menu.shop.connect(func():
		var s := _selected
		_end_selection()
		var screen := ShopScreen.new()
		_ui.add_child(screen)
		screen.setup(state, s, state.shop_at(s))
		_open_shop(screen))
	_menu.use_item.connect(func():
		var s := _selected
		_end_selection()
		var screen := SuppliesMenu.new()
		_ui.add_child(screen)
		screen.setup(state, s)
		_open_shop(screen))
	_menu.edit.connect(func():
		var cell := _selected.id - 1
		_end_selection()
		_open_edit(cell))
	_menu.closed.connect(_end_selection)


func _close_menu() -> void:
	if _menu:
		_menu.queue_free()
		_menu = null


## Closing the menu resumes play.
func _end_selection() -> void:
	_close_menu()
	if _deploying and _selected not in state.squads:
		_selected.hex = -1  # back at base after all
	_deploying = false
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
	hud.show_banner("%s %s: left-click hexes to lay rally points, then click the last point again to commit.  Right-click: undo  ·  Esc: back" % ["Deploy" if _deploying else "Move", _selected.name])


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
		if _deploying:
			_confirm_deploy()
			return
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
	hud.show_banner("%s %s: %d rally point%s, %d hexes, about %s.  Click the last point again to commit  ·  Right-click: undo  ·  Esc: back" % [
			"Deploy" if _deploying else "Move", _selected.name, _points.size(), "" if _points.size() == 1 else "s", _planned.size(), eta])


## While laying a route, the mouse pointer is the squad's flag, its pole on the hex under it.
func _update_cursor() -> void:
	var want := _planning and _confirm == null and _menu == null
	if want and _cursor_flag == null:
		_cursor_flag = SquadToken.new()
		_cursor_flag.squad = _selected
		_ui.add_child(_cursor_flag)
		Input.mouse_mode = Input.MOUSE_MODE_HIDDEN
	elif not want and _cursor_flag:
		_cursor_flag.queue_free()
		_cursor_flag = null
		Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if _cursor_flag:
		_cursor_flag.position = get_viewport().get_mouse_position() - Vector2(0, 10)


func _open_shop(screen: Control) -> void:
	_shop = screen
	screen.connect("closed", func():
		_shop.queue_free()
		_shop = null
		state.clock.release())
	state.clock.hold()


func _open_tech() -> void:
	var screen := TechScreen.new()
	_ui.add_child(screen)
	screen.setup(state)
	_open_shop(screen)


func _open_cards(offer: bool) -> void:
	var panel := CardsPanel.new()
	_ui.add_child(panel)
	panel.setup(state, offer)
	_open_shop(panel)


func _open_building(b: Dictionary) -> void:
	_building_popup = BuildingPopup.new()
	_ui.add_child(_building_popup)
	_building_popup.setup(state, b)
	_building_popup.closed.connect(func():
		_building_popup.queue_free()
		_building_popup = null
		state.clock.release())
	state.clock.hold()


# --- Deploying (SPEC §8.4) -----------------------------------------------------------

func _open_deploy_menu() -> void:
	_deploy_menu = DeployMenu.new()
	_ui.add_child(_deploy_menu)
	_deploy_menu.setup(state)
	_deploy_menu.picked.connect(func(s: Squad):
		_close_deploy_menu()
		_start_deploy(s))
	_deploy_menu.closed.connect(_close_deploy_menu)
	state.clock.hold()


func _close_deploy_menu() -> void:
	_deploy_menu.queue_free()
	_deploy_menu = null
	state.clock.release()


## A squad from base: lay its route from where it will appear, with the move tool.
func _start_deploy(s: Squad) -> void:
	if _selected == null:
		state.clock.hold()
	_selected = s
	_deploying = true
	s.hex = state.deploy_hex()
	var at := MapView.hex_center(state.map, s.hex)
	if not get_viewport_rect().has_point(get_canvas_transform() * at):  # bring the base into view
		camera.center_on(at)
	_start_planning()


func _confirm_deploy() -> void:
	_confirm = ConfirmDialog.new()
	_ui.add_child(_confirm)
	_confirm.setup("Deploy %s for %d gold?" % [_selected.name, state.deploy_cost(_selected)], "Deploy")
	_confirm.confirmed.connect(func():
		_close_confirm()
		state.deploy(_selected, _points)
		_end_selection()
		_sync_tokens()
		hud.set_squads(state.player_squads()))
	_confirm.cancelled.connect(_close_confirm)  # back to laying the route


func _close_confirm() -> void:
	_confirm.queue_free()
	_confirm = null


# --- Battle, log and Esc menu ---------------------------------------------------------

## A fight has started (§11.1): pause, center the map on it, and say so before the battle view.
func _open_encounter() -> void:
	var b := state.pending
	_encounter = EncounterPopup.new()
	_ui.add_child(_encounter)
	_encounter.setup(b, state.army.supplies)
	_fly_to_meeting(b.sides[0], b.sides[1], _encounter)
	_encounter.use_item.connect(func():  # herbs and revivals before the fight
		var screen := SuppliesMenu.new()
		_ui.add_child(screen)
		screen.setup(state, b.sides[0], b)
		_open_shop(screen)
		_encounter.hide()  # its focused Go to fight would take Enter meant for the menu
		screen.closed.connect(func():
			if _encounter:
				_encounter.refresh()
				_encounter.show()))
	_encounter.go.connect(func():
		_encounter.queue_free()
		_encounter = null
		state.clock.release()
		_open_battle())
	state.clock.hold()


## Glides the camera to two squads that just met (zooming in, never out), with the
## popup hidden until it lands.
func _fly_to_meeting(a: Squad, b: Squad, popup: Control) -> void:
	var at := [a, b].map(func(s: Squad): return _tokens[s.id].position if _tokens.has(s.id) else MapView.hex_center(state.map, s.hex))
	var cam: Dictionary = data.battle["encounter_camera"]
	popup.hide()
	camera.fly_to((at[0] + at[1]) / 2.0, float(cam["map_share"]), float(cam["seconds"])).finished.connect(func():
		if is_instance_valid(popup):
			popup.show())


func _open_battle() -> void:
	_announced = false
	_battle = BattleView.new()
	_ui.add_child(_battle)
	_battle.setup(state, state.pending, false, bool(options.get("battle_wait_for_fight", true)))
	_battle.finished.connect(_close_battle)
	state.clock.hold()


func _close_battle(text: String) -> void:
	_battle.queue_free()
	_battle = null
	state.clock.release()
	hud.show_banner(text, 5.0)
	_sync_tokens()


func _open_edit(cell := -1) -> void:
	_edit = EditUnits.new()
	_ui.add_child(_edit)
	_edit.setup(state, cell)
	_edit.closed.connect(_close_edit)
	_edit.deploy.connect(func(s: Squad):
		_close_edit()
		_start_deploy(s))
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


func _open_debug_panel() -> void:
	_debug_panel = DebugPanel.new()
	_ui.add_child(_debug_panel)
	var under := _hex_at(get_global_mouse_position())
	_debug_panel.setup(state, view, under)
	_debug_panel.closed.connect(_close_debug_panel)
	_debug_panel.changed.connect(func():
		_sync_tokens()
		hud.set_squads(state.player_squads()))
	_debug_panel.regenerate.connect(func(seed: int): regenerate.emit(seed))
	_debug_panel.replay.connect(func():
		var b := DebugTools.replay(state)
		_close_debug_panel()
		_battle = BattleView.new()
		_ui.add_child(_battle)
		_battle.setup(state, b, true)
		_battle.finished.connect(_close_battle)
		state.clock.hold())
	_debug_panel.wide_roster.connect(func():
		for s in state.player_squads():  # the reroll renumbers from 1, which could collide with these ids
			if _tokens.has(s.id):
				_tokens[s.id].queue_free()
				_tokens.erase(s.id)
		state.reroll_wide_roster(int(data.rules["army_size"]))
		_sync_tokens()
		hud.set_squads(state.player_squads()))
	state.clock.hold()


func _close_debug_panel() -> void:
	_debug_panel.queue_free()
	_debug_panel = null
	state.clock.release()


## A neutral squad in reach (§16): offers Recruit or Fight. The class shows, not the count.
func _open_recruit_popup() -> void:
	_recruit_popup = RecruitPopup.new()
	_ui.add_child(_recruit_popup)
	_recruit_popup.setup(state.recruit_class())
	_fly_to_meeting(state.pending_recruit["player"], state.pending_recruit["neutral"], _recruit_popup)
	_recruit_popup.recruit.connect(func():
		var result := state.resolve_recruit(true)
		_announced = true  # the result panel already announced any fight
		_recruit_popup.show_result(result["joined"], result["text"]))
	_recruit_popup.done.connect(_close_recruit_popup)
	_recruit_popup.fight.connect(func():
		_announced = true  # the recruit popup already announced this fight
		state.resolve_recruit(false)
		_close_recruit_popup())
	state.clock.hold()


func _close_recruit_popup() -> void:
	_recruit_popup.queue_free()
	_recruit_popup = null
	state.clock.release()
	if state.pending and _battle == null:
		_open_battle()


## Shows the next unshown liberation (§6.5), if any.
func _pump_liberations() -> void:
	if not state.liberations.is_empty() and _can_open():
		_open_liberation_popup(state.liberations.pop_front())


func _open_liberation_popup(entry: Dictionary) -> void:
	camera.center_on(MapView.hex_center(state.map, entry["building"]["hex"]))
	_liberation_popup = LiberationPopup.new()
	_ui.add_child(_liberation_popup)
	_liberation_popup.setup(state, entry["building"], entry["card"])
	_liberation_popup.closed.connect(_close_liberation_popup)
	state.clock.hold()


func _close_liberation_popup() -> void:
	_liberation_popup.queue_free()
	_liberation_popup = null
	state.clock.release()


## The map has ended (§6.8): the player's only way out is to the title screen.
func _open_end_screen() -> void:
	_end_screen = EndScreen.new()
	_ui.add_child(_end_screen)
	_end_screen.setup(state)
	_end_screen.to_title.connect(func(): to_title.emit())
	state.clock.hold()


func _open_main_menu() -> void:
	_main_menu = MainMenu.new()
	_ui.add_child(_main_menu)
	_main_menu.setup()
	_main_menu.resume.connect(_close_main_menu)
	_main_menu.options.connect(func():
		var o := OptionsScreen.new()
		_ui.add_child(o)
		o.setup(data, options)
		o.closed.connect(o.queue_free))
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

## Switching to another window pauses the battle if one is playing, else the map
## (an option, on by default). The player resumes it themselves.
func _notification(what: int) -> void:
	if what != NOTIFICATION_APPLICATION_FOCUS_OUT or not bool(options.get("pause_on_focus_loss", true)) or state == null:
		return
	if _battle:
		_battle.pause()
	elif not state.clock.paused:
		state.toggle_pause()


## From the top bar's dropdown: -1 pauses; a speed also unpauses.
func _on_speed_chosen(index: int) -> void:
	if (index < 0) != state.clock.paused:
		state.toggle_pause()
	if index >= 0:
		state.set_speed_index(index)


## No menu or dialog is open.
func _can_open() -> bool:
	return not (_log_panel or _debug_panel or _menu or _main_menu or _battle or _encounter or _edit or _deploy_menu or _confirm or _building_popup \
			or _shop or _recruit_popup or _liberation_popup or _end_screen)


func _unhandled_input(event: InputEvent) -> void:
	if not _can_open():
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
				var found := _squads_at(world)
				var building := state.building_at(_hex_at(world))
				if found.size() + (0 if building.is_empty() else 1) > 1:
					_choose(found, building)
				elif found.size() == 1:
					_pick(found[0])
				elif not building.is_empty():
					_open_building(building)
		elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed and _planning:
			_undo_point()
		return
	if not (event is InputEventKey and event.is_pressed()):
		return
	var key := (event as InputEventKey).keycode
	if _planning or _firing:
		if key == KEY_ESCAPE and _deploying:
			_end_selection()
		elif key == KEY_ESCAPE:
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
		KEY_D:
			if state.deploy_menu_blocker() == "":
				_open_deploy_menu()
		KEY_C:
			_open_cards(false)
		KEY_T:
			_open_tech()
		KEY_QUOTELEFT:
			_open_debug_panel()
		KEY_F8:  # debug: cycle the first squad's travel type
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
