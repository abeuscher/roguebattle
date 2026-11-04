extends Node
## The game's screens and the flow between them (SPEC §4):
## Title -> Start -> Configurator -> Game summary -> Battlemap.
## The game starts on the battlemap; Edit Units opens from its toolbar.

const SETTINGS_PATH := "user://settings.json"

var data: GameData
var log: GameLog
var config: GameConfig
var _screens := CanvasLayer.new()
var _current: Node
var _preview_map: MapData


func _ready() -> void:
	data = GameData.load_dir()
	log = GameLog.new("user://logs/game-%s.log" % Time.get_datetime_string_from_system().replace(":", "-"))
	RenderingServer.set_default_clear_color(UiStyle.BACKGROUND)
	add_child(_screens)
	config = _load_settings()
	show_title()


func _swap(node: Node, as_screen := true) -> void:
	if _current:
		_current.queue_free()
	_current = node
	if as_screen:
		_screens.add_child(node)
	else:
		add_child(node)


func show_title() -> void:
	var t := TitleScreen.new()
	_swap(t)
	t.setup(data)
	t.next.connect(show_start)


func show_start() -> void:
	var s := StartScreen.new()
	_swap(s)
	s.setup()
	s.start_game.connect(show_configurator)
	s.quit.connect(func(): get_tree().quit())


func show_configurator() -> void:
	var c := ConfiguratorScreen.new()
	_swap(c)
	c.setup(data, config)
	c.back.connect(show_start)
	c.next.connect(func(map: MapData):
		_preview_map = map
		show_summary())


func show_summary() -> void:
	var s := SummaryScreen.new()
	_swap(s)
	s.setup(config)
	s.back.connect(show_configurator)
	s.confirm.connect(start_game)


func start_game() -> void:
	var b := Battlemap.new()
	_swap(b, false)
	b.start(data, log, config, _preview_map)
	_preview_map = null
	b.to_title.connect(show_title)
	b.quit_game.connect(func(): get_tree().quit())
	b.save_settings.connect(_save_settings)


## The configurator starts from the last saved settings (seed included), or the defaults.
func _load_settings() -> GameConfig:
	if FileAccess.file_exists(SETTINGS_PATH):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(SETTINGS_PATH))
		if saved is Dictionary and saved.has("code"):
			var c := GameConfig.from_code(data, saved["code"])
			if c:
				return c
	return GameConfig.create(data, randi())


func _save_settings() -> void:
	var f := FileAccess.open(SETTINGS_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify({"code": config.to_code()}))
	log.add(0, "system", "Settings saved: %s." % config.to_code())
