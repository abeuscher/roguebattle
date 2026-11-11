class_name Hud
extends Control
## The battlemap HUD (SPEC §5.2; layout from playtest round 7, ROADMAP M4 session 24):
## gold and the reputation meter at the top right; the squad drawer at the middle left;
## the minimap at the bottom right with the clock and game speed under it; the toolbar
## (Edit Units, Deploy Squad, Cards, Tech) at the bottom centre; key help at the bottom left.

signal squad_pressed(id: int)
signal edit_pressed
signal deploy_pressed
signal cards_pressed
signal tech_pressed
signal speed_chosen(index: int)  # -1 to pause

const GOLD := Color("#f2c94c")
const DAY := Color("#f6e7a8")
const NIGHT := Color("#a9b8e8")
const GLASS := Color(0.07, 0.09, 0.11, 0.8)  # the panels' see-through dark
const DRAWER_SHUT := 84.0  # the drawer's width, collapsed: number and leader icon
const DRAWER_OPEN := 280.0  # expanded: the squad's name too
const DRAWER_TIME := 0.2  # seconds to slide
const TOOL_HEIGHT := 32.0  # toolbar buttons, about half the old size

var minimap := Minimap.new()
var _clock := Label.new()
var _calendar := TextureRect.new()  # tinted like the clock text (day or night)
var _clock_panel := PanelContainer.new()  # under the minimap, at its width
var _speed := Label.new()  # shown only while a menu holds the game
var _speed_pick := OptionButton.new()  # Paused, then the game speeds; Space, PgUp and PgDn change it too
var _money_panel := PanelContainer.new()
var _gold := Label.new()
var _reputation := ProgressBar.new()
var _drawer := Panel.new()  # not a container, so the rows (full width) never widen it: its width is the slide
var _drawer_col := VBoxContainer.new()  # the toggle and the rows, always at the open width
var _drawer_rows := VBoxContainer.new()
var _drawer_toggle := Button.new()
var _drawer_open := false
var _help := Label.new()
var _banner := Label.new()
var _flash_until := 0
var _toolbar := HBoxContainer.new()
var _cards_button: Button
var _deploy_button: Button  # off when the squad cap is reached or no squad waits at base


func _ready() -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_build_money()
	_build_drawer()
	add_child(minimap)
	_build_clock()
	_help.add_theme_stylebox_override("normal", UiStyle.box(Color(0.07, 0.09, 0.11, 0.75), 6))
	_help.add_theme_font_size_override("font_size", 13)
	add_child(_help)
	_banner.add_theme_stylebox_override("normal", UiStyle.box(Color(0.12, 0.1, 0.04, 0.92), 10))
	_banner.add_theme_font_size_override("font_size", 18)
	_banner.add_theme_color_override("font_color", Color("#ffe08a"))
	_banner.visible = false
	add_child(_banner)
	_build_toolbar()
	resized.connect(place)


## Top right: a coin and the gold, then the reputation meter between a sad and a happy face.
func _build_money() -> void:
	_money_panel.add_theme_stylebox_override("panel", _glass(10))
	add_child(_money_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_money_panel.add_child(row)
	row.add_child(_icon_rect(UiStyle.svg("coins", 22, GOLD)))
	_gold.add_theme_font_size_override("font_size", 20)
	_gold.add_theme_color_override("font_color", GOLD)
	row.add_child(_gold)
	var gap := Control.new()
	gap.custom_minimum_size.x = 18
	row.add_child(gap)
	var meter := HBoxContainer.new()
	meter.add_theme_constant_override("separation", 6)
	meter.mouse_filter = MOUSE_FILTER_PASS
	row.add_child(meter)
	meter.add_child(_icon_rect(UiStyle.svg("frown", 20, Color("#ff9b8a"))))
	_reputation.min_value = 0
	_reputation.max_value = 100
	_reputation.show_percentage = false
	_reputation.custom_minimum_size = Vector2(120, 12)
	_reputation.size_flags_vertical = SIZE_SHRINK_CENTER
	var back := UiStyle.box(Color(0.2, 0.22, 0.26), 0)
	back.set_corner_radius_all(6)
	var fill := UiStyle.box(Color("#7ee08a"), 0)
	fill.set_corner_radius_all(6)
	_reputation.add_theme_stylebox_override("background", back)
	_reputation.add_theme_stylebox_override("fill", fill)
	meter.add_child(_reputation)
	meter.add_child(_icon_rect(UiStyle.svg("smile", 20, Color("#7ee08a"))))


## Middle left: one row per squad on the map. Shut, its number and leader icon; open,
## its name too. The chevron slides it open and shut; a row finds its squad either way.
func _build_drawer() -> void:
	_drawer.add_theme_stylebox_override("panel", _glass(0))
	_drawer.clip_contents = true
	_drawer.size.x = DRAWER_SHUT
	add_child(_drawer)
	_drawer_col.position = Vector2(6, 6)
	_drawer_col.add_theme_constant_override("separation", 4)
	_drawer.add_child(_drawer_col)
	_drawer_toggle.flat = true
	_drawer_toggle.focus_mode = FOCUS_NONE
	_drawer_toggle.tooltip_text = "Show or hide squad names"
	_drawer_toggle.icon = UiStyle.svg("chevron-right", 20)
	_drawer_toggle.custom_minimum_size = Vector2(DRAWER_SHUT - 12, 28)
	_drawer_toggle.size_flags_horizontal = SIZE_SHRINK_BEGIN
	_drawer_toggle.pressed.connect(_toggle_drawer)
	_drawer_col.add_child(_drawer_toggle)
	_drawer_col.add_child(_drawer_rows)
	_drawer_rows.add_theme_constant_override("separation", 4)


func _toggle_drawer() -> void:
	_drawer_open = not _drawer_open
	_drawer_toggle.icon = UiStyle.svg("chevron-left" if _drawer_open else "chevron-right", 20)
	var to := DRAWER_OPEN if _drawer_open else DRAWER_SHUT
	if _drawer_open:
		_name_rows()
	var slide := create_tween()
	slide.tween_property(_drawer, "size:x", to, DRAWER_TIME).set_trans(Tween.TRANS_CUBIC)
	if not _drawer_open:
		slide.finished.connect(_name_rows)


## Shut, a row says only its number; open, its name too.
func _name_rows() -> void:
	for b in _drawer_rows.get_children():
		b.text = b.get_meta("names")[int(_drawer_open)]


## Bottom right, under the minimap and as wide: date, time and time of day, then the speed.
func _build_clock() -> void:
	_clock_panel.add_theme_stylebox_override("panel", _glass(8))
	add_child(_clock_panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	_clock_panel.add_child(row)
	_calendar.texture = UiStyle.icon("calendar")
	_calendar.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_calendar.size_flags_vertical = SIZE_SHRINK_CENTER
	row.add_child(_calendar)
	_clock.add_theme_font_size_override("font_size", 17)
	_clock.size_flags_horizontal = SIZE_EXPAND_FILL
	row.add_child(_clock)
	_speed.add_theme_font_size_override("font_size", 16)
	row.add_child(_speed)
	_speed_pick.add_theme_font_size_override("font_size", 15)
	_speed_pick.focus_mode = FOCUS_NONE  # Space and the arrow keys stay with the map
	_speed_pick.tooltip_text = "Pause (Space) or game speed (PgUp / PgDn)"
	_speed_pick.item_selected.connect(func(i: int): speed_chosen.emit(i - 1))
	row.add_child(_speed_pick)


## Bottom centre: small rounded, see-through buttons, an icon left of each label.
func _build_toolbar() -> void:
	_toolbar.add_theme_constant_override("separation", 8)
	add_child(_toolbar)
	for entry in [["Edit Units (U)", "users", edit_pressed], ["Deploy Squad (D)", "flag", deploy_pressed],
			["Cards (C)", "layers", cards_pressed], ["Tech (T)", "flask-conical", tech_pressed]]:
		var b := _tool_button(entry[0], entry[1])
		b.pressed.connect(entry[2].emit)
		_toolbar.add_child(b)
		if entry[0].begins_with("Cards"):
			_cards_button = b
		elif entry[0].begins_with("Deploy"):
			_deploy_button = b


func _tool_button(text: String, icon_name: String) -> Button:
	var b := Button.new()
	b.text = text
	b.icon = UiStyle.svg(icon_name, 16)
	b.focus_mode = FOCUS_NONE
	b.custom_minimum_size = Vector2(0, TOOL_HEIGHT)
	b.add_theme_font_size_override("font_size", 14)
	b.add_theme_constant_override("h_separation", 6)
	for st in ["normal", "hover", "pressed", "disabled", "focus"]:
		var fill: Color = {"normal": Color(0.12, 0.14, 0.18, 0.7), "hover": Color(0.2, 0.23, 0.28, 0.8), "pressed": Color(0.08, 0.1, 0.12, 0.85),
				"disabled": Color(0.1, 0.11, 0.13, 0.5), "focus": Color(0, 0, 0, 0)}[st]
		var box := StyleBoxFlat.new()
		box.bg_color = fill
		box.set_corner_radius_all(25)
		box.set_border_width_all(1)
		box.border_color = UiStyle.ACCENT if st in ["hover", "pressed"] else Color(UiStyle.OUTLINE, 0.6)
		box.content_margin_left = 14
		box.content_margin_right = 16
		box.content_margin_top = 4
		box.content_margin_bottom = 4
		b.add_theme_stylebox_override(st, box)
	b.add_theme_color_override("font_disabled_color", Color(1, 1, 1, 0.35))
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.35))
	return b


func _glass(margin: int) -> StyleBoxFlat:
	var b := UiStyle.box(GLASS, margin)
	b.set_corner_radius_all(8)
	return b


func _icon_rect(tex: Texture2D) -> TextureRect:
	var r := TextureRect.new()
	r.texture = tex
	r.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	r.size_flags_vertical = SIZE_SHRINK_CENTER
	r.mouse_filter = MOUSE_FILTER_IGNORE
	return r


## One drawer row per squad: its number and leader icon, and its name (seen when open).
## A click centers the map on it.
func set_squads(squads: Array[Squad]) -> void:
	for child in _drawer_rows.get_children():
		_drawer_rows.remove_child(child)
		child.queue_free()
	for s in squads:
		var b := Button.new()
		b.set_meta("names", ["%d" % s.id, "%d   %s" % [s.id, s.name]])  # shut, open
		b.text = b.get_meta("names")[int(_drawer_open)]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = UnitIcons.on_token(s.leader.unit_class, 28, SquadToken.PLAYER) if s.leader else null
		b.tooltip_text = "%d %s" % [s.id, s.name]
		b.focus_mode = FOCUS_NONE
		b.clip_text = true
		b.custom_minimum_size = Vector2(DRAWER_OPEN - 12, 36)
		b.add_theme_font_size_override("font_size", 15)
		b.add_theme_constant_override("h_separation", 8)
		b.pressed.connect(func(): squad_pressed.emit(s.id))
		_drawer_rows.add_child(b)
	place.call_deferred()


## A message near the top; with `seconds`, it disappears after that long.
func show_banner(text: String, seconds := 0.0) -> void:
	_banner.text = text
	_banner.visible = text != ""
	_banner.reset_size()
	_banner.position = Vector2((size.x - _banner.size.x) / 2.0, 16)
	_flash_until = Time.get_ticks_msec() + int(seconds * 1000) if seconds > 0.0 else 0


func banner_text() -> String:
	return _banner.text if _banner.visible else ""


func set_help(text: String) -> void:
	_help.text = text
	place()


func refresh(state: GameState) -> void:
	var tint := DAY if state.clock.is_day() else NIGHT
	_clock.text = "%s  ·  %s" % [state.clock.time_text(), "Day" if state.clock.is_day() else "Night"]
	_clock.add_theme_color_override("font_color", tint)
	_calendar.modulate = tint
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
	_gold.text = "%d   +%d / −%d a day" % [state.gold, state.income(), state.army_upkeep()]
	_reputation.value = state.reputation
	_reputation.tooltip_text = "Reputation %d of 100" % state.reputation
	_cards_button.text = "Cards (C): %d" % state.cards.size()
	var why: String = state.deploy_menu_blocker()
	_deploy_button.disabled = why != ""
	_deploy_button.tooltip_text = why
	if _flash_until > 0 and Time.get_ticks_msec() > _flash_until:
		_flash_until = 0
		_banner.visible = false


## Gold top right; the drawer middle left; the minimap bottom right with the clock under
## it; the toolbar bottom centre; the help text bottom left (above the toolbar if they'd
## overlap). Call after the map or text changes.
func place() -> void:
	_money_panel.reset_size()
	_money_panel.position = Vector2(size.x - _money_panel.size.x - 16, 16)
	_drawer_col.reset_size()
	_drawer.size.y = _drawer_col.size.y + 12
	_drawer.position = Vector2(0, (size.y - _drawer.size.y) / 2.0)
	_clock_panel.custom_minimum_size.x = minimap.size.x
	_clock_panel.reset_size()
	_clock_panel.position = Vector2(size.x - minimap.size.x - 16, size.y - _clock_panel.size.y - 16)
	minimap.position = Vector2(_clock_panel.position.x, _clock_panel.position.y - minimap.size.y - 6)
	_toolbar.reset_size()
	_toolbar.position = Vector2((size.x - _toolbar.size.x) / 2.0, size.y - _toolbar.size.y - 16)
	_help.reset_size()
	_help.position = Vector2(12, size.y - _help.size.y - 12)
	if _help.position.x + _help.size.x > _toolbar.position.x:
		_help.position.y = _toolbar.position.y - _help.size.y - 10
