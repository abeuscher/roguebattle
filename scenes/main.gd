extends Control
## Temporary start screen for M1: shows a generated map. R = new seed.
## Replaced by the battlemap and configurator later in M1.

var data: GameData
var log: GameLog
var view := TextureRect.new()
var label := Label.new()


func _ready() -> void:
	data = GameData.load_dir()
	log = GameLog.new("user://logs/game-%s.log" % Time.get_datetime_string_from_system().replace(":", "-"))
	set_anchors_preset(PRESET_FULL_RECT)
	var bg := ColorRect.new()
	bg.color = Color("#12161c")
	bg.set_anchors_preset(PRESET_FULL_RECT)
	add_child(bg)
	view.set_anchors_preset(PRESET_FULL_RECT)
	view.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	view.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	view.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(view)
	label.position = Vector2(16, 12)
	add_child(label)
	_generate(randi())


func _generate(seed: int) -> void:
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed)
	view.texture = ImageTexture.create_from_image(MinimapImage.build(map, data))
	label.text = "Seed %d  ·  %s %dx%d  ·  %d ms  ·  R: new map" % [
			seed, map.settings["preset"], map.width, map.height, Time.get_ticks_msec() - started]
	log.add(0, "system", "Map generated: seed %d, %s" % [seed, JSON.stringify(map.settings)])


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_R:
		_generate(randi())
