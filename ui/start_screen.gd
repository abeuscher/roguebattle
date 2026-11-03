class_name StartScreen
extends Control
## Start (SPEC §4): Start Game and Options. Campaign, custom game, load, save and
## continue come later.

signal start_game
signal quit


func setup() -> void:
	UiStyle.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var title := UiStyle.label("LANDWAR", 64, Color("#f4ead2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var start := UiStyle.button("Start Game", 300)
	start.pressed.connect(func(): start_game.emit())
	col.add_child(start)
	var options := UiStyle.button("Options", 300)
	options.disabled = true
	options.tooltip_text = "No options yet."
	col.add_child(options)
	var leave := UiStyle.button("Quit", 300)
	leave.pressed.connect(func(): quit.emit())
	col.add_child(leave)
	start.grab_focus.call_deferred()
