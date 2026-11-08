class_name SummaryScreen
extends Control
## Game summary (SPEC §4): game type, map size and seed. Confirm to start.

signal back
signal confirm


func setup(config: GameConfig) -> void:
	UiStyle.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 28))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	panel.add_child(col)
	col.add_child(UiStyle.label("Ready to start", 34))
	var width := int(config.values["width"])
	var height := int(config.values["height"])
	for line in [
		["Game type", "Custom map"],
		["Map", "%s" % String(config.values["preset"]).capitalize()],
		["Map size", "%s (%d x %d hexes)" % [GameConfig.size_name(config.data, width, height), width, height]],
		["Seed", str(config.seed)],
		["Share code", config.to_code()],
	]:
		var row := HBoxContainer.new()
		var name := UiStyle.label(line[0], 18, Color(0.7, 0.72, 0.78))
		name.custom_minimum_size.x = 160
		row.add_child(name)
		row.add_child(UiStyle.label(line[1], 18))
		col.add_child(row)
	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 12)
	col.add_child(buttons)
	var b := UiStyle.button("Back", 160)
	b.pressed.connect(func(): back.emit())
	buttons.add_child(b)
	var go := UiStyle.button("Start", 240, true)
	go.pressed.connect(func(): confirm.emit())
	buttons.add_child(go)
	go.grab_focus.call_deferred()
