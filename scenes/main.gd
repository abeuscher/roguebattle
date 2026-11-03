extends Node2D
## The battlemap (SPEC §5): map view, camera, clock, HUD, minimap and log.
## For now it also generates maps itself (R, P, S); the configurator takes that over in session 7.

const NIGHT := Color(0.45, 0.5, 0.78)  # map tint at night

var data: GameData
var log: GameLog
var state: GameState
var view := MapView.new()
var camera := MapCamera.new()
var hud := Hud.new()
var night := CanvasModulate.new()
var _ui := CanvasLayer.new()
var _log_panel: LogPanel
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
	get_viewport().size_changed.connect(camera.fit)
	_generate(randi())


func _process(delta: float) -> void:
	if state == null:
		return
	for i in state.clock.advance(delta):
		state.step()
	night.color = Color.WHITE.lerp(NIGHT, darkness(state.clock.minute_of_day()))
	hud.refresh(state)


## 0 by day, 1 at night, with an hour of dusk after 18:00 and of dawn before 06:00.
static func darkness(minute: int) -> float:
	if minute >= GameClock.DAWN and minute < GameClock.DUSK:
		return 0.0
	if minute >= GameClock.DUSK:
		return minf(1.0, (minute - GameClock.DUSK) / 60.0)
	return clampf((GameClock.DAWN - minute) / 60.0, 0.0, 1.0)


func _generate(seed: int) -> void:
	_seed = seed
	var presets: Array = data.mapgen["presets"].keys()
	var sizes: Array = data.mapgen["sizes"].keys()
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed, {"preset": presets[_preset % presets.size()], "size": sizes[_size % sizes.size()]})
	_info = "Seed %d  ·  %s  ·  %s %dx%d  ·  generated in %d ms" % [seed, map.settings["preset"].capitalize(),
			map.settings["size"], map.width, map.height, Time.get_ticks_msec() - started]
	state = GameState.new(data, map, log)
	view.show_map(map, data)
	hud.minimap.set_map(map, data)
	hud.place()
	camera.world = MapView.world_size(map)
	camera.fit()
	_update_help()


func _update_help() -> void:
	var text := _info + "\nSpace: pause  ·  PgUp/PgDn: speed  ·  L: log  ·  Wheel: zoom  ·  Drag: pan  ·  F: fit  ·  " \
			+ "R: new map  ·  P: preset  ·  S: size  ·  H: hidden sites and lairs  ·  G: grid  ·  O: overlay (%s)" % MapOverlay.NAMES[view.overlay]
	var legend := MapOverlay.legend(view.overlay, state.map)
	if legend != "":
		text += "\n" + legend
	hud.set_help(text)


func _on_view_changed() -> void:
	view.set_zoom(camera.zoom.x)
	hud.minimap.set_view(camera.visible_rect())


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


func _unhandled_input(event: InputEvent) -> void:
	if _log_panel or not (event is InputEventKey and event.is_pressed()):
		return
	match (event as InputEventKey).keycode:
		KEY_SPACE:
			state.toggle_pause()
		KEY_PAGEUP:
			state.set_speed_index(state.clock.speed_index + 1)
		KEY_PAGEDOWN:
			state.set_speed_index(state.clock.speed_index - 1)
		KEY_L:
			_open_log()
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
	get_viewport().set_input_as_handled()
