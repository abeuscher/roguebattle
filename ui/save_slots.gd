class_name SaveSlots
extends Control
## The three save slots (ROADMAP M4 session 32): each shows the day and time, gold,
## squads on the map and when it was saved, or "Empty". Saving over a slot in use asks
## first; loading skips empty slots. A modal: 50% dark overlay.

signal picked(slot: int)
signal closed

var _saving := false
var _note := UiStyle.label("", 15, Color("#e0604a"))


## `saving`: true to pick a slot to save into, false to pick one to load.
func setup(saving: bool) -> void:
	_saving = saving
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
	panel.custom_minimum_size.x = 620
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Save game" if saving else "Load game", 26), func(): closed.emit()))
	col.add_child(UiStyle.label("Pick a slot to save into." if saving else "Pick a saved game.", 16, Color(0.7, 0.72, 0.76)))
	for slot in range(1, SaveGame.SLOTS + 1):
		var meta := SaveGame.summary(slot)
		var b := UiStyle.button(describe(slot, meta), 580)
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.disabled = not saving and meta.is_empty()
		b.pressed.connect(func(): _pick(slot, meta))
		col.add_child(b)
	_note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	col.add_child(_note)


## One slot's line: "Slot 1 · Day 3, 14:20 · 840 gold · 4 squads · saved 2026-11-11 21:04".
static func describe(slot: int, meta: Dictionary) -> String:
	if meta.is_empty():
		return "Slot %d  ·  Empty" % slot
	return "Slot %d  ·  Day %d, %s  ·  %d gold  ·  %d squad%s on the map  ·  saved %s" % [slot, int(meta["day"]), meta["time"],
			int(meta["gold"]), int(meta["squads"]), "" if int(meta["squads"]) == 1 else "s", str(meta["saved"]).left(16)]


## Shows why a save or load didn't work.
func note(text: String) -> void:
	_note.text = text


func _pick(slot: int, meta: Dictionary) -> void:
	if not _saving or meta.is_empty():
		picked.emit(slot)
		return
	var ask := ConfirmDialog.new()
	add_child(ask)
	ask.setup("Save over slot %d (day %d)?" % [slot, int(meta["day"])], "Save over it")
	ask.confirmed.connect(func():
		ask.queue_free()
		picked.emit(slot))
	ask.cancelled.connect(ask.queue_free)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
