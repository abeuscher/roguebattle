class_name TipPopup
extends Control
## A player tip (ROADMAP M4 session 33): a small panel beside a part of the screen with
## an arrow pointing at it, the tip's text, "Got it", and a ticked "Show player tips"
## box (unticking turns every tip off). It doesn't block the screen around it, so the
## player can do what it says while it's up.

signal closed

const COLOR := Color(0.98, 0.84, 0.45)
const GAP := 26.0  # between the panel and what it points at
const WIDTH := 380.0

var _panel := PanelContainer.new()
var _target := Rect2()


## Points at `target` (a global rect), placing the panel to its left if there's room,
## otherwise to its right.
func setup(text: String, target: Rect2, options: Dictionary) -> void:
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	mouse_filter = MOUSE_FILTER_IGNORE
	_target = target
	var style := UiStyle.box(Color(0.1, 0.11, 0.14), 18)
	style.set_border_width_all(2)
	style.border_color = COLOR
	_panel.add_theme_stylebox_override("panel", style)
	_panel.custom_minimum_size.x = WIDTH
	add_child(_panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	_panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Tip", 20, COLOR), func(): closed.emit(), "Close"))
	var body := UiStyle.label(text, 17)
	body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	body.custom_minimum_size.x = WIDTH - 40
	col.add_child(body)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var show := CheckBox.new()
	show.text = "Show player tips"
	show.button_pressed = bool(options.get("show_tips", true))
	show.add_theme_font_size_override("font_size", 15)
	show.focus_mode = FOCUS_NONE
	show.size_flags_horizontal = SIZE_EXPAND_FILL
	show.toggled.connect(func(on: bool):
		options["show_tips"] = on
		PlayerOptions.save_values(options))
	row.add_child(show)
	var ok := UiStyle.button("Got it", 120, true)
	ok.pressed.connect(func(): closed.emit())
	row.add_child(ok)
	_place.call_deferred()


func _place() -> void:
	_panel.reset_size()
	var screen := get_viewport_rect().size
	var x := _target.position.x - GAP - _panel.size.x
	if x < 16:
		x = _target.end.x + GAP
	var y := clampf(_target.get_center().y - _panel.size.y / 2.0, 16, screen.y - _panel.size.y - 16)
	_panel.global_position = Vector2(x, y)
	queue_redraw()


## The arrow: a wedge from the panel's near edge to the target's edge, and an outline
## round the target so it's clear what the tip means.
func _draw() -> void:
	var p := Rect2(_panel.global_position - global_position, _panel.size)
	var t := Rect2(_target.position - global_position, _target.size)
	var left := p.position.x > t.position.x  # panel to the right of the target
	var base_x := p.position.x if left else p.end.x
	var tip_x := t.end.x + 4 if left else t.position.x - 4
	var y := clampf(t.get_center().y, p.position.y + 24, p.end.y - 24)
	draw_colored_polygon(PackedVector2Array([Vector2(base_x, y - 14), Vector2(base_x, y + 14), Vector2(tip_x, y)]), COLOR)
	draw_rect(t.grow(4), Color(COLOR, 0.9), false, 3.0)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		closed.emit()
