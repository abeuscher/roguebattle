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
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 12)
	col.add_child(head)
	var title := UiStyle.label("%d · %s" % [s.id, s.name], 26)
	title.size_flags_horizontal = SIZE_EXPAND_FILL
	head.add_child(title)
	var terrain := TextureRect.new()
	terrain.texture = _terrain_hex(data, s)
	terrain.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	terrain.size_flags_vertical = SIZE_SHRINK_CENTER
	terrain.tooltip_text = "Travel type: %s" % s.travel_name()
	head.add_child(terrain)
	var speed := UiStyle.label(str(s.speed_tier), 22)
	speed.mouse_filter = MOUSE_FILTER_STOP
	speed.tooltip_text = "Speed tier %d" % s.speed_tier
	head.add_child(speed)
	var band := s.alignment_band(data)
	var align := TextureRect.new()
	align.texture = UiStyle.icon(band, 26)
	align.modulate = ALIGN_COLORS[band]
	align.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	align.size_flags_vertical = SIZE_SHRINK_CENTER
	align.tooltip_text = "Alignment: %s (%d)" % [band.capitalize(), roundi(s.alignment())]
	head.add_child(align)
	var where := "Moving: %d hexes to go, about %s." % [s.path.size(), GameState.duration_text(state.route_ticks(s, s.path))] if s.is_moving() \
			else "Waiting at %s." % state.map.hex_at(s.hex)
	if s.follow:
		where = "Following %s. %s" % [s.follow.name, where]
	col.add_child(UiStyle.label(where, 15, Color(0.75, 0.78, 0.84)))
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
	var gap := Control.new()
	gap.custom_minimum_size.y = 40  # with the separation, about 50px between the squad and its actions
	col.add_child(gap)
	var at_base := s.hex == state.map.player_base
	_button(col, "Edit squad", true, "Open the squad in Edit Units." if state.can_edit(s) else "Open the squad in Edit Units: in the field you can rearrange it but not add or remove units.") \
			.pressed.connect(func(): edit.emit())
	var herbs := 0
	for id in state.army.supplies:
		herbs += int(state.army.supplies[id])
	_button(col, "Use item", herbs > 0, "Give a herb to a hurt unit." if herbs > 0 else "No supplies: buy herbs at a shop.") \
			.pressed.connect(func(): use_item.emit())
	var place := state.shop_at(s)
	var shop_name := "Temple services" if place.get("type", "") == "temple" else "Shop"
	_button(col, shop_name, not place.is_empty(), "Buy here." if not place.is_empty() else "Stand still in a building with a shop (not enemy-held) or a temple.") \
			.pressed.connect(func(): shop.emit())
	_button(col, "Move", true, "Click hexes to lay rally points.").pressed.connect(func(): move.emit())
	var targets := state.fire_targets(s)
	var why := ""
	if not state.can_fire(s):
		why = "No ranged or magic units in position."
	elif state.clock.tick < s.fire_ready:
		why = "Reloading: ready in %s." % GameState.duration_text(s.fire_ready - state.clock.tick)
	elif targets.is_empty():
		why = "No visible enemy within %d hexes." % state.fire_range(s)
	_button(col, "Ranged attack", targets.size() > 0, why if why != "" else "Click an enemy squad within %d hexes." % state.fire_range(s)) \
			.pressed.connect(func(): fire.emit())
	_button(col, "Return to base", true, "Go into the Player Base." if at_base else "March to the Player Base and go in on arrival.") \
			.pressed.connect(func(): return_to_base.emit())
	_button(col, "Close (Esc)", true, "").pressed.connect(func(): closed.emit())


## A small hex of the squad's travel terrain (sky blue for flyers, grey for none).
static func _terrain_hex(data: GameData, s: Squad) -> Texture2D:
	var size := 15.0
	if s.travel_type != "" and not s.sky:
		var t: Dictionary = data.terrains[data.terrain_ids[s.travel_type]]
		return ImageTexture.create_from_image(TerrainTiles.draw_tile(t["key"], Color(t["color"]), size))
	var px := TerrainTiles.tile_size(size)
	var img := Image.create_empty(px.x, px.y, false, Image.FORMAT_RGBA8)
	var sky := Color(data.terrains[data.terrain_ids["air_gap"]]["color"])
	TerrainTiles.fill(img, TerrainTiles.hex_points(Vector2(px) / 2.0, size), sky if s.sky else Color(0.4, 0.42, 0.46))
	return ImageTexture.create_from_image(img)


func _button(parent: Control, text: String, enabled: bool, tip: String) -> Button:
	var b := Button.new()
	b.text = text
	b.disabled = not enabled
	b.tooltip_text = tip
	b.custom_minimum_size = Vector2(0, 40)
	parent.add_child(b)
	return b


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
