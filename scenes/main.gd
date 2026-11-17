extends Node
## The game's screens and the flow between them (SPEC §4):
## Title -> Start -> Configurator -> Game summary -> Battlemap, Start -> Quick Start ->
## Battlemap, Start -> Continue / Load game -> Battlemap, or Start -> Start Campaign ->
## pages -> Battlemap, chapter after chapter (SPEC §25).
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
	s.setup(SaveGame.latest_slot() >= 0 or not Campaign.saved_meta().is_empty())
	s.start_game.connect(show_configurator)
	s.start_campaign.connect(show_campaigns)
	s.quick_start.connect(func(): start_game(GameConfig.quick(data, randi())))
	s.continue_game.connect(func():  # the newer of the latest slot and the campaign's own save
		var slot := SaveGame.latest_slot()
		var at_chapter := Campaign.saved_meta()
		if not at_chapter.is_empty() and (slot < 0 or str(at_chapter["saved"]) > str(SaveGame.summary(slot)["saved"])):
			var c := Campaign.load_saved()
			if c:
				start_chapter(c)
				return
		var why := load_game(slot) if slot >= 0 else "That campaign can no longer be read."
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


func show_campaigns() -> void:
	var c := CampaignScreen.new()
	_swap(c)
	c.setup(data)
	c.back.connect(show_start)
	c.chosen.connect(func(id: String, who: String):
		var run := Campaign.begin(id, randi(), who)
		if run == null:
			show_start()
			return
		run.save()
		show_pages(run.info.get("opening", []) + run.chapter_info().get("before", []), run, func(): start_chapter(run)))


## A campaign's pages between maps (SPEC §25.3), then `then`.
func show_pages(pages: Array, run: Campaign, then: Callable) -> void:
	var p := StoryPages.new()
	_swap(p)
	p.setup(pages, run)
	p.done.connect(then, CONNECT_ONE_SHOT)


## The campaign's current chapter, from its start, with the army brought into it.
func start_chapter(run: Campaign) -> void:
	var b := Battlemap.new()
	b.options = options
	b.campaign = run
	_swap(b, false)
	config = run.config(data)
	b.start(data, log, config)
	_wire(b)


## The end screen's campaign button: a win goes on (the won chapter's pages, then the next
## chapter's, saved at its start), or after the last to the ending; a loss tries the map again.
func _campaign_step(b: Battlemap) -> void:
	var run := b.campaign
	if b.state.game_over != "victory":
		var again := Campaign.load_saved()
		start_chapter(again if again and again.id == run.id and again.chapter == run.chapter else run)
		return
	var after: Array = run.chapter_info().get("after", [])
	if run.is_last():
		DirAccess.remove_absolute(Campaign.save_path)  # done: Continue no longer offers it
		show_pages(after + run.info.get("ending", []), run, show_title)
		return
	run.advance(b.state)
	run.save()
	show_pages(after + run.chapter_info().get("before", []), run, func(): start_chapter(run))


## Starts a map from `game_config` (Quick start's own), or the configurator's settings.
func start_game(game_config: GameConfig = null) -> void:
	var b := Battlemap.new()
	b.options = options
	_swap(b, false)
	b.start(data, log, game_config if game_config else config, _preview_map)
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
	var at: Dictionary = r["state"].settings
	if at.has("campaign"):  # a map of the campaign saved: back in it, if it's the run on file
		var run := Campaign.load_saved()
		if run and run.id == str(at["campaign"]) and run.chapter == int(at["chapter"]):
			b.campaign = run
	b.start_loaded(data, log, config, r["state"])
	_wire(b)
	return ""


func _wire(b: Battlemap) -> void:
	b.to_title.connect(show_title)
	b.campaign_go.connect(func(): _campaign_step(b))
	b.quit_game.connect(func(): get_tree().quit())
	b.save_settings.connect(func():  # this game's settings, Quick start's included
		config = b.config
		_save_settings())
	b.regenerate.connect(func(seed: int):  # same settings (Quick start's too), new seed
		var c := b.config
		c.seed = seed
		start_game(c))


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
