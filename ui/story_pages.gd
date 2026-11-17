class_name StoryPages
extends Control
## The pages between a campaign's maps (SPEC §25.3), kept simple: each page has any of a
## title, text, a picture, a video and a sound. Click, Space or Enter goes on (a video goes
## on by itself when it ends); Esc skips the rest. Pages fade from one to the next.

signal done

const FADE := 0.35  # seconds each way between pages
const TEXT_WIDTH := 760.0

var _pages: Array = []
var _campaign: Campaign
var _at := -1
var _page: Control
var _sound := AudioStreamPlayer.new()
var _leaving := false


## `pages`: the campaign file's page dictionaries; media paths are in the campaign's folder.
func setup(pages: Array, campaign: Campaign) -> void:
	_pages = pages
	_campaign = campaign
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	UiStyle.backdrop(self)
	(get_child(0) as Control).mouse_filter = MOUSE_FILTER_IGNORE  # clicks come to this screen
	_sound.bus = "Voice"
	add_child(_sound)
	if _pages.is_empty():
		_finish.call_deferred()
	else:
		_next()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		accept_event()
		_next()


func _unhandled_key_input(event: InputEvent) -> void:
	var k := event as InputEventKey
	if k == null or not k.pressed or k.echo:
		return
	if k.keycode in [KEY_SPACE, KEY_ENTER, KEY_KP_ENTER]:
		get_viewport().set_input_as_handled()
		_next()
	elif k.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_finish()


func _next() -> void:
	if _leaving:
		return
	_at += 1
	if _at >= _pages.size():
		_finish()
		return
	var old := _page
	_page = _build(_pages[_at])
	_page.modulate.a = 0.0
	add_child(_page)
	var t := create_tween()
	if old:
		t.tween_property(old, "modulate:a", 0.0, FADE)
		t.tween_callback(old.queue_free)
	t.tween_property(_page, "modulate:a", 1.0, FADE)
	_sound.stop()
	var sound := str(_pages[_at].get("sound", ""))
	if sound != "" and ResourceLoader.exists(_campaign.media(sound)):
		_sound.stream = load(_campaign.media(sound))
		_sound.play()


func _finish() -> void:
	if _leaving:
		return
	_leaving = true
	_sound.stop()
	done.emit()


func _build(p: Dictionary) -> Control:
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 18)
	col.mouse_filter = MOUSE_FILTER_IGNORE
	center.add_child(col)
	if str(p.get("title", "")) != "":
		var title := UiStyle.label(str(p["title"]), 40)
		title.add_theme_font_override("font", UiStyle.title_font())
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(title)
	var screen := get_viewport_rect().size
	var media_size := Vector2(screen.x * 0.6, screen.y * 0.5)
	var video := str(p.get("video", ""))
	var image := str(p.get("image", ""))
	if video != "" and ResourceLoader.exists(_campaign.media(video)):
		var player := VideoStreamPlayer.new()
		player.stream = load(_campaign.media(video))
		player.expand = true
		player.custom_minimum_size = media_size
		player.mouse_filter = MOUSE_FILTER_IGNORE
		player.finished.connect(_next)
		player.ready.connect(player.play)
		col.add_child(player)
	elif image != "" and ResourceLoader.exists(_campaign.media(image)):
		var pic := TextureRect.new()
		pic.texture = load(_campaign.media(image))
		pic.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		pic.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		pic.custom_minimum_size = media_size
		pic.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(pic)
	if str(p.get("text", "")) != "":
		var text := UiStyle.label(str(p["text"]), 20, Color(0.88, 0.9, 0.93))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		text.custom_minimum_size.x = TEXT_WIDTH
		text.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		col.add_child(text)
	var hint := UiStyle.label("Click or press Space to go on  ·  Esc to skip", 14, Color(0.6, 0.62, 0.68))
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(hint)
	return center
