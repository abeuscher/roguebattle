class_name LedgerPopup
extends Control
## The day's ledger (user's playtest notes, 2026-11-10): at noon, when income and upkeep
## are settled, every gold change since the last noon, then the gold now. A modal: 50%
## dark overlay; "Do not show this window again" turns it off (Options has it too).

signal closed

const GAIN := Color("#7ee08a")
const LOSS := Color("#ff8a7a")


func setup(entry: Dictionary, options: Dictionary) -> void:
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
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 460
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Day %d  ·  Noon ledger" % int(entry["day"]), 24), func(): closed.emit()))
	col.add_child(UiStyle.label("Gold in and out since the last noon.", 15, Color(0.75, 0.78, 0.84)))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 24)
	grid.add_theme_constant_override("v_separation", 4)
	col.add_child(grid)
	var total := 0
	for line in entry["lines"]:
		var amount := int(line[1])
		total += amount
		var what := UiStyle.label(str(line[0]), 16)
		what.size_flags_horizontal = SIZE_EXPAND_FILL
		grid.add_child(what)
		grid.add_child(_amount(amount, 16))
	col.add_child(HSeparator.new())
	var sums := GridContainer.new()
	sums.columns = 2
	sums.add_theme_constant_override("h_separation", 24)
	col.add_child(sums)
	var net := UiStyle.label("Net for the day", 17)
	net.size_flags_horizontal = SIZE_EXPAND_FILL
	sums.add_child(net)
	sums.add_child(_amount(total, 17))
	sums.add_child(UiStyle.label("Gold now", 17, UiStyle.ACCENT))
	var now := UiStyle.label(str(int(entry["gold"])), 17, UiStyle.ACCENT)
	now.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	sums.add_child(now)
	if int(entry["gold"]) < 0:  # in debt (round 9)
		var debt := UiStyle.label("In debt: noon %d of %d. Nothing can be bought while in debt. Sell a squad in Edit Units (U) or take towns before the army breaks up." % [
				int(entry["debt_noons"]), int(entry["defeat_noons"])], 15, LOSS)
		debt.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		debt.custom_minimum_size.x = 360
		col.add_child(debt)
	col.add_child(UiStyle.dont_show_again(options, "show_daily_ledger"))


func _amount(n: int, font_size: int) -> Label:
	var l := UiStyle.label(("+%d" if n > 0 else "%d") % n if n != 0 else "0", font_size, GAIN if n > 0 else (LOSS if n < 0 else Color.WHITE))
	l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	return l


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
