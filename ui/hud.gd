class_name Hud
extends Control
## The battlemap HUD (SPEC §5.2): clock with day and night, game speed, pause
## state, gold, reputation, the squad number list, the minimap, and a toolbar at the
## bottom with Edit Units and Deploy Squad.

signal squad_pressed(id: int)
signal edit_pressed
signal deploy_pressed
signal speed_chosen(index: int)  # -1 to pause

var minimap := Minimap.new()
var _clock := Label.new()
var _speed := Label.new()  # shown only while a menu holds the game
var _speed_pick := OptionButton.new()  # Paused, then the game speeds; Space, PgUp and PgDn change it too
var _money := Label.new()
var _squads := HBoxContainer.new()
var _help := Label.new()
var _banner := Label.new()
var _flash_until := 0
var _toolbar := HBoxContainer.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", UiStyle.box(Color(0.07, 0.09, 0.11, 0.85), 10))
	bar.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	bar.add_child(row)
	_clock.add_theme_font_size_override("font_size", 20)
	row.add_child(_clock)
	_speed_pick.add_theme_font_size_override("font_size", 18)
	_speed_pick.focus_mode = FOCUS_NONE  # Space and the arrow keys stay with the map
	_speed_pick.tooltip_text = "Pause (Space) or game speed (PgUp / PgDn)"
	_speed_pick.item_selected.connect(func(i: int): speed_chosen.emit(i - 1))
	row.add_child(_speed_pick)
	_speed.add_theme_font_size_override("font_size", 20)
	row.add_child(_speed)
	_squads.add_theme_constant_override("separation", 6)
	row.add_child(_squads)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	_money.add_theme_font_size_override("font_size", 20)
	row.add_child(_money)
	add_child(minimap)
	_help.add_theme_stylebox_override("normal", UiStyle.box(Color(0.07, 0.09, 0.11, 0.75), 6))
	_help.add_theme_font_size_override("font_size", 13)
	add_child(_help)
	_banner.add_theme_stylebox_override("normal", UiStyle.box(Color(0.12, 0.1, 0.04, 0.92), 10))
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.add_theme_color_override("font_color", Color("#ffe08a"))
	_banner.visible = false
	add_child(_banner)
	_toolbar.add_theme_constant_override("separation", 10)
	add_child(_toolbar)
	for entry in [["Edit Units (U)", edit_pressed], ["Deploy Squad (D)", deploy_pressed]]:
		var b := UiStyle.button(entry[0], 210)
		b.focus_mode = FOCUS_NONE
		b.pressed.connect(entry[1].emit)
		_toolbar.add_child(b)
	resized.connect(place)


## One button per squad, labelled with its number (click centers the map on it).
func set_squads(squads: Array[Squad]) -> void:
	for child in _squads.get_children():
		child.queue_free()
	for s in squads:
		var b := Button.new()
		b.text = "%d %s" % [s.id, s.name]
		b.focus_mode = FOCUS_NONE
		b.pressed.connect(func(): squad_pressed.emit(s.id))
		_squads.add_child(b)


## A message under the top bar; with `seconds`, it disappears after that long.
func show_banner(text: String, seconds := 0.0) -> void:
	_banner.text = text
	_banner.visible = text != ""
	_banner.reset_size()
	_banner.position = Vector2((size.x - _banner.size.x) / 2.0, 62)
	_flash_until = Time.get_ticks_msec() + int(seconds * 1000) if seconds > 0.0 else 0


func set_help(text: String) -> void:
	_help.text = text
	place()


func refresh(state: GameState) -> void:
	_clock.text = "%s  ·  %s" % [state.clock.time_text(), "Day" if state.clock.is_day() else "Night"]
	_clock.add_theme_color_override("font_color", Color("#f6e7a8") if state.clock.is_day() else Color("#a9b8e8"))
	if _speed_pick.item_count == 0:
		_speed_pick.add_item("Paused  (Space)")
		var names: Array = state.data.rules["game_speed_names"]
		for i in names.size():
			var x := float(state.data.rules["game_speeds"][i])
			_speed_pick.add_item("%s  ×%s" % [names[i], str(int(x)) if x == int(x) else str(x)])
	var shown := 0 if state.clock.paused else state.clock.speed_index + 1
	if _speed_pick.selected != shown:
		_speed_pick.select(shown)
	_speed_pick.add_theme_color_override("font_color", Color("#ff9b6a") if state.clock.paused else Color.WHITE)
	_speed.visible = not state.clock.paused and not state.clock.is_running()
	_speed.text = "Paused"
	_speed.add_theme_color_override("font_color", Color("#ffe08a"))
	_money.text = "Gold %d  (+%d / −%d a day)   ·   Reputation %d" % [state.gold, state.income(), state.army_upkeep(), state.reputation]
	if _flash_until > 0 and Time.get_ticks_msec() > _flash_until:
		_flash_until = 0
		_banner.visible = false


## Puts the minimap bottom-right, the toolbar bottom-centre and the help text bottom-left
## (above the toolbar if they'd overlap). Call after the map or text changes.
func place() -> void:
	minimap.position = size - minimap.size - Vector2(16, 16)
	_toolbar.reset_size()
	_toolbar.position = Vector2((size.x - _toolbar.size.x) / 2.0, size.y - _toolbar.size.y - 16)
	_help.reset_size()
	_help.position = Vector2(12, size.y - _help.size.y - 12)
	if _help.position.x + _help.size.x > _toolbar.position.x:
		_help.position.y = _toolbar.position.y - _help.size.y - 10

