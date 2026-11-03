class_name SquadToken
extends Node2D
## A squad on the battlemap: a numbered banner. Flyers float with a soft shadow (SPEC §5.1).

const FLY_HEIGHT := 16.0

var squad: Squad
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var color := Color("#3b6fd6")  # player blue; enemies are red


func _draw() -> void:
	var lift := -FLY_HEIGHT if squad.sky else 0.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2(0, 12 / 0.35), 14.0 if squad.sky else 12.0, Color(0, 0, 0, 0.22 if squad.sky else 0.35))
	draw_set_transform(Vector2.ZERO)
	if selected:
		draw_arc(Vector2(0, 8), 22.0, 0.0, TAU, 32, Color(1, 0.9, 0.3), 3.0)
	var top := Vector2(0, -44 + lift)
	draw_line(Vector2(0, 10 + lift), top, Color("#2a2420"), 3.0)
	var flag := PackedVector2Array([top, top + Vector2(30, 0), top + Vector2(30, 22), top + Vector2(15, 17), top + Vector2(0, 22)])
	draw_colored_polygon(flag, color)
	draw_polyline(flag + PackedVector2Array([top]), Color("#1c2333"), 2.0)
	var font := ThemeDB.fallback_font
	var label := str(squad.id) if squad.side == "player" else squad.role.left(1).to_upper()  # enemies show their role's initial
	draw_string(font, top + Vector2(7, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
