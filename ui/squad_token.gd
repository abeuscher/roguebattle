class_name SquadToken
extends Node2D
## A squad on the battlemap: its leader's class icon in a ring of the side's color, with
## the squad's number (enemies: their role's initial) on a tag; no pole or flag (playtest
## round 7). A squad without a leader is a numbered ring. Flyers float with a soft shadow
## (SPEC §5.1). With `as_flag`, it draws the squad's numbered flag instead: a moving
## squad's destination and the pointer while laying a move. A leaderless squad crawling
## home shows a skull instead of the leader's icon (playtest round 9).

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
var as_flag := false  # the destination flag / move cursor, not the squad itself
var crawl := false:  # leaderless, marching home (Squad.crawling)
	set(value):
		if value != crawl:
			crawl = value
			queue_redraw()

static var _skull: Texture2D


func _ready() -> void:
	texture_filter = TEXTURE_FILTER_LINEAR_WITH_MIPMAPS


func _draw() -> void:
	var label := str(squad.id) if squad.side == "player" else squad.role.left(1).to_upper()  # enemies show their role's initial
	var font := ThemeDB.fallback_font
	if as_flag:
		_banner(0.0, label, font)
		return
	var lift := -FLY_HEIGHT if squad.sky else 0.0
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2(0, 12 / 0.35), 14.0 if squad.sky else 12.0, Color(0, 0, 0, 0.22 if squad.sky else 0.35))
	draw_set_transform(Vector2.ZERO)
	var center := Vector2(0, -8 + lift)  # the ring stands on its shadow
	if selected:
		draw_arc(center, RADIUS + 6, 0.0, TAU, 32, Color(1, 0.9, 0.3), 3.0)
	var icon := UnitIcons.on_token(squad.leader.unit_class, ICON_PX, DISC) if squad.leader else null
	draw_circle(center, RADIUS, DISC)
	if crawl:
		if _skull == null:
			_skull = UiStyle.svg("skull", ICON_PX, Color(0.92, 0.9, 0.86))
		draw_texture_rect(_skull, Rect2(center - Vector2.ONE * RADIUS * 0.72, Vector2.ONE * RADIUS * 1.44), false)
	elif icon:
		draw_texture_rect(icon, Rect2(center - Vector2.ONE * RADIUS * 1.06, Vector2.ONE * RADIUS * 2.12), false)
	draw_arc(center, RADIUS, 0.0, TAU, 40, color, 3.0)
	var tag := center + Vector2(RADIUS * 0.75, RADIUS * 0.75)  # at the ring's lower right, clear of the icon's symbols
	draw_circle(tag, 8.0, color)
	draw_arc(tag, 8.0, 0.0, TAU, 20, Color("#1c2333"), 1.5)
	draw_string(font, tag + Vector2(-8, 4.5), label, HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color.WHITE)


## The squad's numbered flag on a pole, its foot at the origin.
func _banner(lift: float, label: String, font: Font) -> void:
	var top := Vector2(0, -44 + lift)
	draw_line(Vector2(0, 10 + lift), top, Color("#2a2420"), 3.0)
	var flag := PackedVector2Array([top, top + Vector2(30, 0), top + Vector2(30, 22), top + Vector2(15, 17), top + Vector2(0, 22)])
	draw_colored_polygon(flag, color)
	draw_polyline(flag + PackedVector2Array([top]), Color("#1c2333"), 2.0)
	draw_string(font, top + Vector2(7, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
