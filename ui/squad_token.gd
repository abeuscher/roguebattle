class_name SquadToken
extends Node2D
## A squad on the battlemap: its leader's class icon on a pole, ringed in the side's color,
## with the squad's number (enemies: their role's initial) on a tag. A squad without a
## leader flies a plain numbered banner. Flyers float with a soft shadow (SPEC §5.1).

const FLY_HEIGHT := 16.0
const PLAYER := Color("#3b6fd6")
const DISC := Color("#1b2433")
const RADIUS := 17.0
const ICON_PX := 72  # rasterized larger than drawn so it stays sharp when the map zooms in

var squad: Squad
var selected := false:
	set(value):
		selected = value
		queue_redraw()
var color := PLAYER  # player blue; enemies are red


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var lift := -FLY_HEIGHT if squad.sky else 0.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2(0, 12 / 0.35), 14.0 if squad.sky else 12.0, Color(0, 0, 0, 0.22 if squad.sky else 0.35))
	draw_set_transform(Vector2.ZERO)
	if selected:
		draw_arc(Vector2(0, 8), 22.0, 0.0, TAU, 32, Color(1, 0.9, 0.3), 3.0)
	var label := str(squad.id) if squad.side == "player" else squad.role.left(1).to_upper()  # enemies show their role's initial
	var font := ThemeDB.fallback_font
	var icon := UnitIcons.on_token(squad.leader.unit_class, ICON_PX, DISC) if squad.leader else null
	if icon == null:
		_banner(lift, label, font)
		return
	var center := Vector2(0, -36 + lift)
	draw_line(Vector2(0, 10 + lift), center, Color("#2a2420"), 3.0)
	draw_circle(center, RADIUS, DISC)
	draw_texture_rect(icon, Rect2(center - Vector2.ONE * RADIUS * 1.06, Vector2.ONE * RADIUS * 2.12), false)
	draw_arc(center, RADIUS, 0.0, TAU, 40, color, 3.0)
	var tag := center + Vector2(0, RADIUS + 8)  # on the pole, clear of the icon's symbols
	draw_circle(tag, 8.0, color)
	draw_arc(tag, 8.0, 0.0, TAU, 20, Color("#1c2333"), 1.5)
	draw_string(font, tag + Vector2(-8, 4.5), label, HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color.WHITE)


## The old numbered flag, for a squad with no leader.
func _banner(lift: float, label: String, font: Font) -> void:
	var top := Vector2(0, -44 + lift)
	draw_line(Vector2(0, 10 + lift), top, Color("#2a2420"), 3.0)
	var flag := PackedVector2Array([top, top + Vector2(30, 0), top + Vector2(30, 22), top + Vector2(15, 17), top + Vector2(0, 22)])
	draw_colored_polygon(flag, color)
	draw_polyline(flag + PackedVector2Array([top]), Color("#1c2333"), 2.0)
	draw_string(font, top + Vector2(7, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
