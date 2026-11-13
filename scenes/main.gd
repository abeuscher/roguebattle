extends Node
## The game's screens and the flow between them (SPEC §4):
## Title -> Start -> Configurator -> Game summary -> Battlemap, or Start -> Continue /
## Load game -> Battlemap.
## The game starts on the battlemap; Edit Units opens from its toolbar.

const SETTINGS_PATH := "user://settings.json"

var data: GameData
var log: GameLog
var config: GameConfig
var options: Dictionary  # the player's options (PlayerOptions), shared live with the screens that read them
var _screens := CanvasLayer.new()
var _current: Node
var _preview_map: MapData


func _ready() -> void:
	data = GameData.load_dir()
	log = GameLog.new("user://logs/game-%s.log" % Time.get_datetime_string_from_system().replace(":", "-"))
	RenderingServer.set_default_clear_color(UiStyle.BACKGROUND)
	add_child(_screens)
	config = _load_settings()
	options = PlayerOptions.load_values(data)
	Sound.start(self, data.audio, options)
	show_title()


func _swap(node: Node, as_screen := true) -> void:
	if _current:
		_current.queue_free()
	_current = node
	if node is TitleScreen:
		Sound.music(Sound.music_for(data.audio, "title"))
	elif not node is Battlemap:  # the menus (the battlemap picks its own)
		Sound.music(Sound.music_for(data.audio, "menus"))
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
	s.setup(SaveGame.latest_slot() >= 0)
	s.start_game.connect(show_configurator)
	s.continue_game.connect(func():
		var why := load_game(SaveGame.latest_slot())
		if why != "":
			s.note(why))
	s.load_game.connect(func():
		var slots := SaveSlots.new()
		s.add_child(slots)
		slots.setup(false)
		slots.closed.connect(slots.queue_free)
		slots.picked.connect(func(slot: int):
			var why := load_game(slot)
			if why != "":
				slots.note(why)))
	s.options.connect(func():
		var o := OptionsScreen.new()
		s.add_child(o)
		o.setup(data, options)
		o.closed.connect(o.queue_free))
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
	b.options = options
	_swap(b, false)
	b.start(data, log, config, _preview_map)
	_preview_map = null
	_wire(b)


## Loads a save slot onto the battlemap. "" on success, otherwise why not.
func load_game(slot: int) -> String:
	var r = SaveGame.read(slot, data, log)
	if r is String:
		return r
	config = r["config"]
	var b := Battlemap.new()
	b.options = options
	_swap(b, false)
	b.start_loaded(data, log, config, r["state"])
	_wire(b)
	return ""


func _wire(b: Battlemap) -> void:
	b.to_title.connect(show_title)
	b.quit_game.connect(func(): get_tree().quit())
	b.save_settings.connect(_save_settings)
	b.regenerate.connect(func(seed: int):
		config.seed = seed
		start_game())


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
