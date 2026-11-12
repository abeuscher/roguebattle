class_name Hud
extends Control
## The battlemap HUD (SPEC §5.2; layout from playtest round 7, ROADMAP M4 session 24):
## gold and the reputation meter at the top right; the squad drawer at the middle left;
## the minimap at the bottom right with the clock and game speed under it; the toolbar
## (Edit Units, Deploy Squad, Cards, Tech) at the bottom centre; an info button at the bottom
## left that shows or hides the key help (hidden to start).

signal squad_pressed(id: int)
signal squad_opened(id: int)  # a drawer row double-clicked (round 10)
signal edit_pressed
signal deploy_pressed
signal cards_pressed
signal tech_pressed
signal speed_chosen(index: int)  # -1 to pause
signal place_pressed(hex: int)  # a place named in the banner was clicked

const GOLD := Color("#f2c94c")
const DAY := Color("#f6e7a8")
const NIGHT := Color("#a9b8e8")
const GLASS := Color(0.07, 0.09, 0.11, 0.8)  # the panels' see-through dark
const DRAWER_SHUT := 104.0  # the drawer's width, collapsed: number and leader icon
const DRAWER_OPEN := 340.0  # expanded: markers and the squad's name too
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
var _info := Button.new()  # shows or hides _help
var _banner := PanelContainer.new()  # one line of labels, with place names as links
var _banner_line := HBoxContainer.new()
var _banner_text := ""
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
	_help.visible = false
	add_child(_help)
	_info.icon = UiStyle.svg("info", 24)
	_info.toggle_mode = true
	_info.focus_mode = FOCUS_NONE
	_info.tooltip_text = "Show or hide the controls"
	_info.add_theme_stylebox_override("normal", _glass(6))
	_info.add_theme_stylebox_override("hover", _glass(6))
	_info.add_theme_stylebox_override("pressed", _glass(6))
	_info.toggled.connect(func(on: bool):
		_help.visible = on
		_info.icon = UiStyle.svg("info", 24, GOLD if on else Color.WHITE)
		place())
	add_child(_info)
	_banner.add_theme_stylebox_override("panel", UiStyle.box(Color(0.12, 0.1, 0.04, 0.92), 10))
	_banner.mouse_filter = MOUSE_FILTER_IGNORE
	_banner_line.add_theme_constant_override("separation", 0)
	_banner_line.mouse_filter = MOUSE_FILTER_IGNORE
	_banner.add_child(_banner_line)
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
	create_tween().tween_property(_drawer, "size:x", to, DRAWER_TIME).set_trans(Tween.TRANS_CUBIC)


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


## One drawer row per squad: leader icon, number and status icon (moving, in a building,
## standing in the open), then travel type, speed and alignment and the name (seen when
## open). A click centers the map on it; a double click opens its squad menu.
func set_squads(squads: Array[Squad]) -> void:
	for child in _drawer_rows.get_children():
		_drawer_rows.remove_child(child)
		child.queue_free()
	for s in squads:
		var b := Button.new()
		b.set_meta("squad", s)
		b.tooltip_text = "%d %s" % [s.id, s.name]
		b.focus_mode = FOCUS_NONE
		b.clip_contents = true
		b.custom_minimum_size = Vector2(DRAWER_OPEN - 12, 36)
		b.pressed.connect(func(): squad_pressed.emit(s.id))
		b.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.double_click and (e as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
				squad_opened.emit(s.id))
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		row.mouse_filter = MOUSE_FILTER_IGNORE
		row.name = "Row"
		row.position = Vector2(6, 4)
		b.add_child(row)
		var lead := _icon_rect(null)
		lead.name = "Leader"
		row.add_child(lead)
		var number := UiStyle.label(str(s.id), 15)
		number.custom_minimum_size.x = 16
		number.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(number)
		var status := _icon_rect(null)
		status.name = "Status"
		row.add_child(status)
		var gap := Control.new()  # round 10: nothing past the status icon peeks out of the shut drawer
		gap.custom_minimum_size.x = DRAWER_SHUT - 92.0  # 92: the status icon's right edge (6 + 6 + 28 + 8 + 16 + 8 + 20)
		gap.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(gap)
		var marks := Control.new()  # travel, speed, alignment (playtest round 9), seen when open; filled by refresh
		marks.name = "Markers"
		row.add_child(marks)
		var name_label := UiStyle.label(s.name, 15)
		name_label.mouse_filter = MOUSE_FILTER_IGNORE
		row.add_child(name_label)
		_drawer_rows.add_child(b)
	place.call_deferred()


## The status icons, by GameState.squad_status: footprints (moving), a house (in any
## building), crossed-out footprints (standing in the open).
static func status_icon(status: String, px := 20) -> Texture2D:
	return UiStyle.svg({"moving": "footprints", "building": "house", "still": "footprints-off"}[status], px, Color(0.85, 0.88, 0.92))


## A message near the top; with `seconds`, it disappears after that long.
func show_banner(text: String, seconds := 0.0) -> void:
	show_banner_links(text, seconds, {})


## A banner whose place names (`links`: name -> hex) are links: clicking one sends
## place_pressed, and the map centres on it (playtest round 9).
func show_banner_links(text: String, seconds: float, links: Dictionary) -> void:
	_banner_text = text
	for c in _banner_line.get_children():
		_banner_line.remove_child(c)
		c.queue_free()
	var rest := text
	while rest != "":
		var at := rest.length()
		var found := ""
		for n in links:
			var i := rest.find(n)
			if i >= 0 and i < at:
				at = i
				found = n
		if at > 0:
			var plain := UiStyle.label(rest.left(at), 18, UiStyle.ACCENT)
			plain.mouse_filter = MOUSE_FILTER_IGNORE
			_banner_line.add_child(plain)
		if found == "":
			break
		var link := LinkButton.new()
		link.text = found
		link.underline = LinkButton.UNDERLINE_MODE_ALWAYS
		link.add_theme_font_size_override("font_size", 18)
		for c in ["font_color", "font_focus_color", "font_pressed_color"]:
			link.add_theme_color_override(c, UiStyle.ACCENT)
		link.add_theme_color_override("font_hover_color", Color.WHITE)
		link.focus_mode = FOCUS_NONE
		link.size_flags_vertical = SIZE_SHRINK_CENTER
		link.tooltip_text = "Show %s on the map" % found
		var hex: int = links[found]
		link.pressed.connect(func(): place_pressed.emit(hex))
		_banner_line.add_child(link)
		rest = rest.substr(at + found.length())
	_banner.visible = text != ""
	_banner.reset_size()
	_banner.position = Vector2((size.x - _banner.size.x) / 2.0, 16)
	_flash_until = Time.get_ticks_msec() + int(seconds * 1000) if seconds > 0.0 else 0


func banner_text() -> String:
	return _banner_text if _banner.visible else ""


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
	var money := "%d   +%d / −%d a day%s" % [state.gold, state.income(), state.army_upkeep(),
			"   In debt %d/%d" % [state.debt_noons, int(state.data.rules["debt"]["defeat_noons"])] if state.in_debt() else ""]
	if _gold.text != money:  # the panel's width follows the text, so keep its right edge in place
		_gold.text = money
		_money_panel.reset_size()
		_money_panel.position.x = size.x - _money_panel.size.x - 16
	_gold.add_theme_color_override("font_color", Color("#ff6b5a") if state.in_debt() else GOLD)
	for b in _drawer_rows.get_children():
		var s: Squad = b.get_meta("squad")
		var st := state.squad_status(s)
		var lead: TextureRect = b.get_node("Row/Leader")
		var face := "skull" if s.crawling() else (s.leader.unit_class if s.leader else "")  # a skull while it crawls home leaderless (playtest round 9)
		if lead.get_meta("face", "-") != face:
			lead.set_meta("face", face)
			lead.texture = UiStyle.svg("skull", 24, Color(0.92, 0.9, 0.86)) if face == "skull" 					else (UnitIcons.on_token(face, 28, SquadToken.PLAYER) if face != "" else null)
		var marks: Control = b.get_node("Row/Markers")
		var key := "%s|%d|%s" % [s.travel_name(), s.speed_tier, s.alignment_band(state.data)]
		if marks.get_meta("key", "") != key:
			var fresh := SquadMenu.markers(state.data, s, 16)
			fresh.set_meta("key", key)
			for m in [fresh] + fresh.get_children():
				m.mouse_filter = MOUSE_FILTER_IGNORE
			marks.replace_by(fresh)
			marks.queue_free()
			fresh.name = "Markers"
		var icon: TextureRect = b.get_node("Row/Status")
		if icon.get_meta("status", "") != st:
			icon.set_meta("status", st)
			icon.texture = status_icon(st)
			b.tooltip_text = "%d %s: %s" % [s.id, s.name, state.status_text(s)]
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
## it; the toolbar bottom centre; the info button bottom left with the help text above it
## (above the toolbar if they'd overlap). Call after the map or text changes.
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
	_info.reset_size()
	_info.position = Vector2(16, size.y - _info.size.y - 16)
	_help.reset_size()
	_help.position = Vector2(16, _info.position.y - _help.size.y - 8)
	if _help.position.x + _help.size.x > _toolbar.position.x:
		_help.position.y = minf(_help.position.y, _toolbar.position.y - _help.size.y - 10)
