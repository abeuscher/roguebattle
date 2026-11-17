class_name StartScreen
extends Control
## Start (SPEC §4): Continue (the latest save), Start Game, Quick Start (a small map,
## squads ready, no configurator), Start Campaign (SPEC §25), Load game (when any slot is in
## use), Options and Quit.

signal start_game
signal quick_start
signal start_campaign
signal continue_game
signal load_game
signal options
signal quit


var _note := UiStyle.label("", 16, Color("#e0604a"))


const BUTTON_WIDTH := 270.0  # half the title's width (playtest round 15)


func setup(has_save := false) -> void:
	UiStyle.backdrop(self)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	center.add_child(col)
	var title := UiStyle.game_name(110)
	col.add_child(title)
	var go := UiStyle.button("Continue", BUTTON_WIDTH, true)
	go.pressed.connect(func(): continue_game.emit())
	go.visible = has_save
	col.add_child(go)
	var start := UiStyle.button("Start Game", BUTTON_WIDTH, not has_save)
	start.pressed.connect(func(): start_game.emit())
	col.add_child(start)
	var quick := UiStyle.button("Quick Start", BUTTON_WIDTH)
	quick.tooltip_text = "A small map with your squads ready, straight away."
	quick.pressed.connect(func(): quick_start.emit())
	col.add_child(quick)
	var story := UiStyle.button("Start Campaign", BUTTON_WIDTH)
	story.tooltip_text = "A run of maps with a story between them; your army carries from one to the next."
	story.pressed.connect(func(): start_campaign.emit())
	col.add_child(story)
	var load := UiStyle.button("Load game", BUTTON_WIDTH)
	load.pressed.connect(func(): load_game.emit())
	load.visible = has_save
	col.add_child(load)
	var opts := UiStyle.button("Options", BUTTON_WIDTH)
	opts.pressed.connect(func(): options.emit())
	col.add_child(opts)
	var leave := UiStyle.button("Quit", BUTTON_WIDTH)
	leave.pressed.connect(func(): quit.emit())
	col.add_child(leave)
	for b in col.get_children():  # centred under the title, not stretched to its width (playtest round 15)
		if b is Button:
			b.size_flags_horizontal = SIZE_SHRINK_CENTER
	_note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_note.custom_minimum_size.x = 300
	col.add_child(_note)
	(go if has_save else start).grab_focus.call_deferred()


## Shows why a load didn't work.
func note(text: String) -> void:
	_note.text = text
