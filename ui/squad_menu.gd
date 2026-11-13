class_name SquadMenu
extends Control
## The squad menu (SPEC §5.3), opened by selecting a squad. A modal: 50% dark
## overlay, and the game stays paused while it's open. Clicking the overlay closes it.

signal move
signal fire
signal return_to_base
signal edit
signal shop
signal use_item
signal view_destination
signal portal
signal closed

const ALIGN_COLORS := {"holy": Color("#ffe08a"), "neutral": Color(0.8, 0.82, 0.86), "evil": Color("#e0604a")}


func setup(state: GameState, s: Squad) -> void:
	var data := state.data
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	shade.gui_input.connect(func(e: InputEvent):
		if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
			closed.emit())
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.mouse_filter = MOUSE_FILTER_IGNORE
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0.1, 0.12, 0.15), 18))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	var title := UiStyle.label("%d · %s" % [s.id, s.name], 26)
	var status := TextureRect.new()  # moving, in a building or in the open (playtest round 7)
	status.texture = Hud.status_icon(state.squad_status(s), 26)
	status.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	status.size_flags_vertical = SIZE_SHRINK_CENTER
	status.tooltip_text = state.status_text(s)
	col.add_child(UiStyle.title_row(title, func(): closed.emit(), "Close (Esc)", [markers(data, s, 26), status]))
	var cols := s.capacity(data)
	for u in s.units:
		cols = maxi(cols, u.col + 1)
	for r in ["front", "back"]:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		col.add_child(row)
		for c in cols:
			var slot := PanelContainer.new()
			var style := UiStyle.box(Color(0.09, 0.1, 0.12), 2)
			style.set_border_width_all(1)
			style.border_color = Color(0.25, 0.27, 0.32)
			slot.add_theme_stylebox_override("panel", style)
			slot.custom_minimum_size = Vector2(108, 74)
			var u := s.at(r, c)
			if u:
				var chip := EditUnits.Chip.new()
				chip.setup(data, u, "menu", s, EditUnits.KIND_COLORS)
				chip.mouse_default_cursor_shape = CURSOR_ARROW
				chip.tooltip_text = "%s (%s), level %d. HP %d/%d." % [u.name, u.unit_class, u.level, u.hp, u.max_hp(data)]
				slot.add_child(chip)
			row.add_child(slot)
	# Round 9: one row of icon buttons with tooltips instead of a column of words.
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation", 10)
	actions.alignment = BoxContainer.ALIGNMENT_CENTER
	col.add_child(_spacer(8))
	col.add_child(actions)
	var at_base := s.hex == state.map.player_base
	_button(actions, "pencil", "Edit squad", true, "Open the squad in Edit Units." if state.can_edit(s) else "Open the squad in Edit Units: in the field you can rearrange it but not add or remove units.") 			.pressed.connect(func(): edit.emit())
	var herbs := 0
	for id in state.army.supplies:
		herbs += int(state.army.supplies[id])
	_button(actions, "flask-conical", "Use item", herbs > 0, "Give a herb to a hurt unit." if herbs > 0 else "No supplies: buy herbs at a shop.") 			.pressed.connect(func(): use_item.emit())
	var place := state.shop_at(s)
	var shop_name := "Temple services" if place.get("type", "") == "temple" else "Shop"
	_button(actions, "hand-coins", shop_name, not place.is_empty(), "Buy here." if not place.is_empty() else "Stand still in a building with a shop (not enemy-held) or a temple.") 			.pressed.connect(func(): shop.emit())
	_button(actions, "footprints", "Move", true, "Click hexes to lay rally points.").pressed.connect(func(): move.emit())
	var here := state.building_at(s.hex)
	if here.get("type", "") == "temple" and not s.is_moving():  # session 059
		var gates := state.portal_targets(s)
		var no_gate := "Take this temple to use its portal." if here["owner"] != "player" else "Hold another temple to step to it."
		_button(actions, "orbit", "Portal", not gates.is_empty(), "Step at once to another temple you hold." if not gates.is_empty() else no_gate) \
				.pressed.connect(func(): portal.emit())
	if s.is_moving():
		_button(actions, "flag", "View destination", true, "Show where %s is headed." % s.name).pressed.connect(func(): view_destination.emit())
	var targets := state.fire_targets(s)
	var why := ""
	if not state.can_fire(s):
		why = "No ranged or magic units in position."
	elif state.clock.tick < s.fire_ready:
		why = "Reloading: ready in %s." % GameState.duration_text(s.fire_ready - state.clock.tick)
	elif targets.is_empty():
		why = "No visible enemy within %d hexes." % state.fire_range(s)
	_button(actions, "crosshair", "Ranged attack", targets.size() > 0, why if why != "" else "Click an enemy squad within %d hexes." % state.fire_range(s)) 			.pressed.connect(func(): fire.emit())
	_button(actions, "house", "Return to base", true, "Go into the Player Base." if at_base else "March to the Player Base and go in on arrival.") 			.pressed.connect(func(): return_to_base.emit())


## The squad's travel terrain, speed tier and alignment, with tooltips: in the squad menu
## header and everywhere else a squad is shown (playtest round 9). `px` is the icon size.
static func markers(data: GameData, s: Squad, px := 26) -> HBoxContainer:
	var box := HBoxContainer.new()
	box.add_theme_constant_override("separation", maxi(4, px / 3))
	box.size_flags_vertical = SIZE_SHRINK_CENTER
	var terrain := TextureRect.new()
	terrain.texture = _terrain_hex(data, s, px * 0.58)
	terrain.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	terrain.size_flags_vertical = SIZE_SHRINK_CENTER
	terrain.tooltip_text = "Travel type: %s" % s.travel_name()
	box.add_child(terrain)
	var speed := UiStyle.label(str(s.speed_tier), roundi(px * 0.85))
	speed.mouse_filter = MOUSE_FILTER_STOP
	speed.tooltip_text = "Speed tier %d" % s.speed_tier
	box.add_child(speed)
	var band := s.alignment_band(data)
	var align := TextureRect.new()
	align.texture = UiStyle.icon(band, px)
	align.modulate = ALIGN_COLORS[band]
	align.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	align.size_flags_vertical = SIZE_SHRINK_CENTER
	align.tooltip_text = "Alignment: %s (%d)" % [band.capitalize(), roundi(s.alignment())]
	box.add_child(align)
	return box


## A small hex of the squad's travel terrain (sky blue for flyers, grey for none).
static func _terrain_hex(data: GameData, s: Squad, size := 15.0) -> Texture2D:
	if s.travel_type != "" and not s.sky:
		var t: Dictionary = data.terrains[data.terrain_ids[s.travel_type]]
		return ImageTexture.create_from_image(TerrainTiles.draw_tile(t["key"], Color(t["color"]), size))
	var px := TerrainTiles.tile_size(size)
	var img := Image.create_empty(px.x, px.y, false, Image.FORMAT_RGBA8)
	var sky := Color(data.terrains[data.terrain_ids["air_gap"]]["color"])
	TerrainTiles.fill(img, TerrainTiles.hex_points(Vector2(px) / 2.0, size), sky if s.sky else Color(0.4, 0.42, 0.46))
	return ImageTexture.create_from_image(img)


## A square icon button; the tooltip names the action, then says what it does or why
## it can't be used now.
func _button(parent: Control, icon_name: String, text: String, enabled: bool, tip: String) -> Button:
	var b := UiStyle.button("", 60)
	b.custom_minimum_size = Vector2(60, 56)
	b.icon = UiStyle.svg(icon_name, 28)
	b.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	b.add_theme_color_override("icon_disabled_color", Color(1, 1, 1, 0.28))
	b.disabled = not enabled
	b.tooltip_text = "%s
%s" % [text, tip] if tip != "" else text
	b.focus_mode = FOCUS_NONE
	b.name = text.to_pascal_case()
	parent.add_child(b)
	return b


static func _spacer(px: int) -> Control:
	var c := Control.new()
	c.custom_minimum_size.y = px
	return c


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
