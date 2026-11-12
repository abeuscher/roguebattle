class_name StartScreen
extends Control
## Start (SPEC §4): Continue (the latest save), Start Game, Load game (when any slot
## is in use), Options and Quit. Campaign and custom game come later.

signal start_game
signal continue_game
signal load_game
signal options
signal quit


var _note := UiStyle.label("", 16, Color("#e0604a"))


func setup(has_save := false) -> void:
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
	var go := UiStyle.button("Continue", 300, true)
	go.pressed.connect(func(): continue_game.emit())
	go.visible = has_save
	col.add_child(go)
	var start := UiStyle.button("Start Game", 300, not has_save)
	start.pressed.connect(func(): start_game.emit())
	col.add_child(start)
	var load := UiStyle.button("Load game", 300)
	load.pressed.connect(func(): load_game.emit())
	load.visible = has_save
	col.add_child(load)
	var opts := UiStyle.button("Options", 300)
	opts.pressed.connect(func(): options.emit())
	col.add_child(opts)
	var leave := UiStyle.button("Quit", 300)
	leave.pressed.connect(func(): quit.emit())
	col.add_child(leave)
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 300
	col.add_child(_note)
	(go if has_save else start).grab_focus.call_deferred()


## Shows why a load didn't work.
func note(text: String) -> void:
	_note.text = text
