class_name TechScreen
extends Control
## The Tech screen (SPEC §4, §14): the six branches by tier, and the terrain nodes. Click
## a node to learn it; its tier must be open (80% of the previous tier's branch nodes)
## and it costs its tier in points. A modal: 50% dark overlay.

signal closed

const OWNED := Color("#3f7a4a")

var state: GameState
var _body := HBoxContainer.new()
var _points := UiStyle.label("", 20, UiStyle.ACCENT)
var _status := UiStyle.label("", 16, UiStyle.ACCENT)


func setup(game_state: GameState) -> void:
	state = game_state
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	UiStyle.close_on_click(shade, center, func(): closed.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 20))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	_points.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	col.add_child(UiStyle.title_row(UiStyle.label("Tech", 26), func(): closed.emit(), "Close (Esc)", [_points]))
	_body.add_theme_constant_override("separation", 30)
	col.add_child(_body)
	col.add_child(_status)
	_refresh()


func _refresh() -> void:
	for c in _body.get_children():
		c.queue_free()
	_points.text = "%d point%s to spend  ·  earn them from liberations and battles won" % [state.tech_points, "" if state.tech_points == 1 else "s"]
	var nodes := state.tech_nodes()
	var grid := GridContainer.new()
	grid.columns = 5
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	_body.add_child(grid)
	grid.add_child(Control.new())
	for t in range(1, 5):
		var open := state.tier_open(t)
		grid.add_child(UiStyle.label("Tier %d  ·  %d pt%s%s" % [t, t, "" if t == 1 else "s", "" if open else "  ·  locked"], 15,
				Color(0.85, 0.87, 0.9) if open else Color(0.55, 0.57, 0.62)))
	for branch in state.data.tech["branches"]:
		var l := UiStyle.label(branch, 16, Color(0.75, 0.78, 0.82))
		l.custom_minimum_size.x = 150
		grid.add_child(l)
		for t in range(1, 5):
			for id in nodes:
				if nodes[id]["branch"] == branch and int(nodes[id]["tier"]) == t:
					grid.add_child(_node(id, nodes[id], Vector2(250, 92)))
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 6)
	_body.add_child(side)
	var note := UiStyle.label("Terrain: units native to it get +1 to +4\nSTR, INT, PDEF and MDEF (the highest tier counts)", 15, Color(0.75, 0.78, 0.82))
	side.add_child(note)
	var tgrid := GridContainer.new()
	tgrid.columns = 5
	tgrid.add_theme_constant_override("h_separation", 6)
	tgrid.add_theme_constant_override("v_separation", 6)
	side.add_child(tgrid)
	for terrain in state.data.tech["terrains"]:
		var l := UiStyle.label(terrain, 15, Color(0.75, 0.78, 0.82))
		l.custom_minimum_size.x = 90
		tgrid.add_child(l)
		for t in range(1, 5):
			var id := "terrain_%s_%d" % [terrain, t]
			tgrid.add_child(_node(id, nodes[id], Vector2(76, 44), ["I", "II", "III", "IV"][t - 1]))


## A node: green once learned, orange-edged when it can be learned, dim otherwise.
func _node(id: String, node: Dictionary, size: Vector2, short := "") -> Control:
	var owned := id in state.tech
	var why := state.tech_blocker(id)
	var cell := PanelContainer.new()
	cell.custom_minimum_size = size
	var style := UiStyle.box(OWNED if owned else Color(0.13, 0.15, 0.19), 8)
	style.set_border_width_all(2)
	style.border_color = OWNED.lightened(0.3) if owned else (UiStyle.ACTION if why == "" else Color(0.25, 0.27, 0.32))
	cell.add_theme_stylebox_override("panel", style)
	cell.tooltip_text = "%s (tier %d): %s%s" % [node["name"], int(node["tier"]), node["text"], "" if owned or why == "" else "\n" + why]
	var col := VBoxContainer.new()
	col.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_theme_constant_override("separation", 2)
	cell.add_child(col)
	var ink := Color.WHITE if owned or why == "" else Color(0.55, 0.57, 0.62)
	var title := UiStyle.label(short if short != "" else node["name"], 15, ink)
	title.mouse_filter = MOUSE_FILTER_IGNORE
	col.add_child(title)
	if short == "":
		var text := UiStyle.label(node["text"], 12, ink.darkened(0.15))
		text.autowrap_mode = TextServer.AUTOWRAP_WORD
		text.mouse_filter = MOUSE_FILTER_IGNORE
		col.add_child(text)
	if not owned:
		cell.mouse_default_cursor_shape = CURSOR_POINTING_HAND if why == "" else CURSOR_ARROW
		cell.gui_input.connect(func(e: InputEvent):
			if e is InputEventMouseButton and e.pressed and e.button_index == MOUSE_BUTTON_LEFT:
				_status.text = why
				if state.buy_tech(id):
					_status.text = "Learned %s." % node["name"]
				_refresh())
	return cell


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode in [KEY_ESCAPE, KEY_T]:
		closed.emit()
	get_viewport().set_input_as_handled()
