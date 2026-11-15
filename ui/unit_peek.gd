class_name UnitPeek
## A unit at a glance (playtest round 14, settled 2026-11-14): its class icon, first name,
## class and level, an HP bar with no numbers, the attack it makes from the row it stands
## in, and a ? to its glossary entry. No attribute numbers. Used in the battle view (an
## enemy card clicked), the enemy squad window and the squad menu (round 16).


## The unit as a small column `width` wide. `glossary` gets the class when its ? (beside
## the class name) is pressed; without one (Callable()) there's no ?, for a window that
## has it in its title bar. A leader is starred, a fallen unit greyed.
static func make(data: GameData, u: Unit, glossary: Callable, leader := false, width := 150.0) -> Control:
	var info := u.info(data)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 4)
	box.custom_minimum_size.x = width
	var pic := TextureRect.new()
	pic.texture = UnitIcons.texture(u.unit_class, 56)
	pic.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	box.add_child(pic)
	var first := UiStyle.label(u.name.get_slice(" ", 0), 15, UiStyle.TITLE)  # its first name (round 16)
	first.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(first)
	var name_row := HBoxContainer.new()
	name_row.add_theme_constant_override("separation", 6)
	name_row.alignment = BoxContainer.ALIGNMENT_CENTER
	name_row.add_child(UiStyle.label("%s%s" % [u.unit_class, " ★" if leader else ""], 15))
	if glossary.is_valid():
		name_row.add_child(UiStyle.help(glossary.bind(u.unit_class), "The %s in the unit glossary" % u.unit_class, 20))
	box.add_child(name_row)
	var level := UiStyle.label("Level %d%s" % [u.level, "" if u.is_alive() else ", fallen"], 14, Color(0.75, 0.78, 0.84))
	level.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	box.add_child(level)
	box.add_child(_hp_bar(float(u.hp) / maxf(1.0, u.max_hp(data))))
	var row := u.row
	var attack := UiStyle.label("%s: %s ×%d" % ["Front" if row == "front" else "Back", info[row + "_attack"], int(info[row + "_count"])], 14)
	attack.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	attack.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	attack.tooltip_text = "The attack it makes from the %s row." % row
	attack.mouse_filter = Control.MOUSE_FILTER_PASS
	box.add_child(attack)
	if not u.is_alive():
		box.modulate = Color(1, 1, 1, 0.45)
	return box


## A bar of the unit's HP share: green, then amber, then red, as on the battle cards.
static func _hp_bar(share: float) -> Control:
	var bar := ProgressBar.new()
	bar.show_percentage = false
	bar.max_value = 1.0
	bar.value = share
	bar.custom_minimum_size = Vector2(0, 8)
	bar.add_theme_stylebox_override("background", UiStyle.box(Color(0.05, 0.05, 0.06), 0))
	var fill := Color("#5fbf5a") if share > 0.5 else (Color("#e0b03a") if share > 0.25 else Color("#d9533f"))
	bar.add_theme_stylebox_override("fill", UiStyle.box(fill, 0))
	bar.tooltip_text = "Its health (the numbers stay hidden)."
	return bar
