class_name UnitGlossary
extends Control
## The unit glossary (playtest round 13): what each class is and does, from the unit
## data alone (units.json, mechanics.json for the terms, lines.json for promotions). A
## searchable list of every class on the left, the entry on the right, opened at the
## class it was asked for (a neutral band, a unit in Edit Units). X, Esc or a click
## outside closes it.

signal closed

const MUTED := Color(0.65, 0.68, 0.72)
const SOFT := Color(0.85, 0.87, 0.9)

var data: GameData
var _list := VBoxContainer.new()
var _entry := VBoxContainer.new()
var _search := LineEdit.new()
var _shown := ""


func setup(game_data: GameData, unit_class: String) -> void:
	data = game_data
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
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	var screen := get_viewport_rect().size
	panel.custom_minimum_size = Vector2(minf(1100, screen.x - 80), minf(760, screen.y - 80))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Unit glossary", 24), func(): closed.emit(), "Close (Esc)"))
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 22)
	body.size_flags_vertical = SIZE_EXPAND_FILL
	col.add_child(body)
	var side := VBoxContainer.new()
	side.add_theme_constant_override("separation", 8)
	side.custom_minimum_size.x = 250
	body.add_child(side)
	_search.placeholder_text = "Search"
	_search.clear_button_enabled = true
	_search.text_changed.connect(func(_t): _fill_list())
	side.add_child(_search)
	var list_scroll := ScrollContainer.new()
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.size_flags_vertical = SIZE_EXPAND_FILL
	side.add_child(list_scroll)
	_list.size_flags_horizontal = SIZE_EXPAND_FILL
	list_scroll.add_child(_list)
	var entry_scroll := ScrollContainer.new()
	entry_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	entry_scroll.size_flags_horizontal = SIZE_EXPAND_FILL
	body.add_child(entry_scroll)
	_entry.add_theme_constant_override("separation", 10)
	_entry.size_flags_horizontal = SIZE_EXPAND_FILL
	entry_scroll.add_child(_entry)
	show_class(unit_class)


## Shows a class's entry and marks it in the list.
func show_class(unit_class: String) -> void:
	_shown = unit_class
	_fill_list()
	for c in _entry.get_children():
		_entry.remove_child(c)
		c.queue_free()
	if data.units.has(unit_class):
		_write_entry(data.units[unit_class])


## Every class whose name holds the search text, A to Z.
func _fill_list() -> void:
	for c in _list.get_children():
		_list.remove_child(c)
		c.queue_free()
	var names: Array = data.units.keys()
	names.sort()
	var find := _search.text.strip_edges().to_lower()
	for n in names:
		if find != "" and not str(n).to_lower().contains(find):
			continue
		var b := UiStyle.button(n, 230, n == _shown)
		b.focus_mode = FOCUS_NONE
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.icon = UnitIcons.texture(n, 24)
		for c in ["icon_normal_color", "icon_hover_color", "icon_pressed_color", "icon_focus_color"]:
			b.add_theme_color_override(c, Color.WHITE)  # the icon as drawn, on the picked button too
		b.pressed.connect(show_class.bind(n))
		_list.add_child(b)
		if n == _shown:
			var scroll := _list.get_parent() as ScrollContainer
			(func(): if b.is_inside_tree(): scroll.ensure_control_visible(b)).call_deferred()  # unless another class was shown meanwhile


func _write_entry(c: Dictionary) -> void:
	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 18)
	var pic := TextureRect.new()
	pic.texture = UnitIcons.texture(c["class"], 96)
	head.add_child(pic)
	var names := VBoxContainer.new()
	names.alignment = BoxContainer.ALIGNMENT_CENTER
	var title := UiStyle.label(c["class"], 30, UiStyle.TITLE)
	title.add_theme_font_override("font", UiStyle.title_font())
	names.add_child(title)
	names.add_child(UiStyle.label("%s  ·  stage %d  ·  %s  ·  leans %s" % [c["role"], int(c["stage"]), c["size"],
			str(c["alignment_lean"]).to_lower()], 17, SOFT))
	head.add_child(names)
	_entry.add_child(head)
	_text(str(c["notes"]) + "." if c.get("notes") != null else "No description of the %s yet." % c["class"], 17, Color.WHITE)
	_section("In battle")
	_text("Front row: %s ×%d    Back row: %s ×%d" % [c["front_attack"], int(c["front_count"]), c["back_attack"], int(c["back_count"])], 16, Color.WHITE)
	_text("Strongest in %s.%s" % [", ".join(c["key_stats"]), "  Element: %s." % c["element"] if c["element"] != null else ""], 16, SOFT)
	for term in _attack_terms(c):
		_term(term)
	if not c["traits"].is_empty():
		_section("Traits")
		for t in c["traits"]:
			_term(t)
	_section("Leading")
	if not c["can_lead"]:
		_text("Can't lead a squad.", 16, SOFT)
	elif c["leader_aura"] != null:
		_text("Can lead. Aura as leader: %s%s" % [c["leader_aura"], ", " + str(c["leader_aura_text"]) + "." if c.get("leader_aura_text") else "."], 16, SOFT)
	else:
		_text("Can lead.", 16, SOFT)
	_section("On the map")
	_text("Home terrain %s: it fights better there.  Speed tier %d.  Takes %s in a squad." % [
			str(c["terrain"]).to_lower(), int(c["speed_tier"]), "half a slot" if c["size"] == "Tiny" else ("2 slots" if c["size"] == "Large" else "1 slot")], 16, SOFT)
	_section("Promotion lines")
	for line_id in c["lines"]:
		var stages := PackedStringArray()
		for stage in data.lines[line_id]:
			stages.append(" / ".join(PackedStringArray(stage)))
		_text("  >  ".join(stages), 15, SOFT)


## The rules terms in a class's attacks: "Magic (row)" -> Magic's and (row)'s, where the
## Mechanics sheet has them.
func _attack_terms(c: Dictionary) -> Array:
	var out := []
	for a in [c["front_attack"], c["back_attack"]]:
		var parts := str(a).split(" (")
		var terms := [parts[0]]
		if parts.size() > 1:
			terms.append("(" + parts[1])
		for t in terms:
			if data.mechanics.has(t) and t not in out:
				out.append(t)
	return out


## A term and its rule from the Mechanics sheet (just the term if the sheet has none).
func _term(name: String) -> void:
	var m: Dictionary = data.mechanics.get(name, data.mechanics.get(name + " size", {}))  # "Tiny" is "Tiny size" on the sheet
	var shown := name.trim_prefix("(").trim_suffix(")").capitalize() if name.begins_with("(") else name
	_text("%s: %s" % [shown, m["rule"]] if m.has("rule") else shown, 15, SOFT)


func _section(text: String) -> void:
	var l := UiStyle.section(text)
	_entry.add_child(l)


func _text(text: String, px: int, color: Color) -> void:
	var l := UiStyle.label(text, px, color)
	l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	l.custom_minimum_size.x = 640
	_entry.add_child(l)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
