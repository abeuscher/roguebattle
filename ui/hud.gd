class_name Hud
extends Control
## The battlemap HUD (SPEC §5.2): clock with day and night, game speed, pause
## state, gold, reputation, the squad number list and the minimap.

var minimap := Minimap.new()
var _clock := Label.new()
var _speed := Label.new()
var _money := Label.new()
var _squads := Label.new()
var _help := Label.new()


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	var bar := PanelContainer.new()
	bar.add_theme_stylebox_override("panel", _box(Color(0.07, 0.09, 0.11, 0.85), 10))
	bar.set_anchors_and_offsets_preset(PRESET_TOP_WIDE)
	bar.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(bar)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 40)
	bar.add_child(row)
	for label in [_clock, _speed, _squads]:
		label.add_theme_font_size_override("font_size", 20)
		row.add_child(label)
	var spacer := Control.new()
	spacer.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(spacer)
	_money.add_theme_font_size_override("font_size", 20)
	row.add_child(_money)
	add_child(minimap)
	_help.add_theme_stylebox_override("normal", _box(Color(0.07, 0.09, 0.11, 0.75), 6))
	_help.add_theme_font_size_override("font_size", 13)
	add_child(_help)
	resized.connect(place)


func set_help(text: String) -> void:
	_help.text = text
	place()


func refresh(state: GameState) -> void:
	_clock.text = "%s  ·  %s" % [state.clock.time_text(), "Day" if state.clock.is_day() else "Night"]
	_clock.add_theme_color_override("font_color", Color("#f6e7a8") if state.clock.is_day() else Color("#a9b8e8"))
	if state.clock.paused:
		_speed.text = "PAUSED  (Space)"
		_speed.add_theme_color_override("font_color", Color("#ff9b6a"))
	else:
		_speed.text = "%s  x%s" % [state.speed_name(), state.clock.speed()]
		_speed.remove_theme_color_override("font_color")
	_money.text = "Gold %d   ·   Reputation %d" % [state.gold, state.reputation]
	_squads.text = "Squads: none yet"


## Puts the minimap bottom-right and the help text bottom-left. Call after the map or text changes.
func place() -> void:
	minimap.position = size - minimap.size - Vector2(16, 16)
	_help.reset_size()
	_help.position = Vector2(12, size.y - _help.size.y - 12)


static func _box(color: Color, margin: int) -> StyleBoxFlat:
	var box := StyleBoxFlat.new()
	box.bg_color = color
	box.set_content_margin_all(margin)
	box.set_corner_radius_all(4)
	return box
