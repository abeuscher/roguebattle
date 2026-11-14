class_name SquadToken
extends Node2D
## A squad on the battlemap: its leader standing on the map (the class's full-colour icon,
## unit icons 2026-11-14) on a soft shadow edged in the side's color, with a soft drop
## shadow, and the squad's number (enemies: their role's initial) on a tag at its feet.
## Flyers float above their shadow (SPEC §5.1). A squad without a leader is a numbered ring;
## a leaderless squad crawling home shows a skull in it (playtest round 9). With `as_flag`,
## it draws the squad's numbered flag instead: a moving squad's destination and the pointer
## while laying a move.

const FLY_HEIGHT := 16.0
const PLAYER := Color("#3b6fd6")
const DISC := Color("#1b2433")
const RADIUS := 17.0  # the ring of a leaderless squad
const ICON_PX := 128  # rasterized larger than drawn so it stays sharp when the map zooms in
const FIGURE := 65.0  # the leader's icon, drawn this many map pixels square (54 until playtest 2026-11-14: 20% larger)
const BASE := {"Tiny": 14.0, "Small": 18.0, "Large": 26.0}  # the shadow's half-width, by the leader's size
const EDGE := 1.2  # a faint dark edge round the figure, this wide, so it stands off the ground,
const EDGE_SHADE := 0.45  # this dark
const DROP := 3.5  # the drop shadow: down and right this far,
const BLUR := 1.5  # this soft (8 faint copies in a ring this wide),
const SHADE := 0.24  # each copy this dark (they overlap, so its core is darker)

var squad: Squad
var data: GameData  # for the leader's size
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
	var icon := UnitIcons.texture(squad.leader.unit_class, ICON_PX) if squad.leader and not crawl else null
	if icon:
		_standing(icon, lift, label, font)
		return
	draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.0, 0.35))
	draw_circle(Vector2(0, 12 / 0.35), 14.0 if squad.sky else 12.0, Color(0, 0, 0, 0.22 if squad.sky else 0.35))
	draw_set_transform(Vector2.ZERO)
	var center := Vector2(0, -8 + lift)  # the ring stands on its shadow
	if selected:
		draw_arc(center, RADIUS + 6, 0.0, TAU, 32, Color(1, 0.9, 0.3), 3.0)
	draw_circle(center, RADIUS, DISC)
	if crawl:
		if _skull == null:
			_skull = UiStyle.svg("skull", 72, Color(0.92, 0.9, 0.86))
		draw_texture_rect(_skull, Rect2(center - Vector2.ONE * RADIUS * 0.72, Vector2.ONE * RADIUS * 1.44), false)
	draw_arc(center, RADIUS, 0.0, TAU, 40, color, 3.0)
	_tag(center + Vector2(RADIUS * 0.75, RADIUS * 0.75), label, font)  # at the ring's lower right


## The leader standing: a soft shadow edged in the side's colour (wider for a Large
## leader), the figure's feet over it with its drop shadow, the numbered tag at its feet.
func _standing(icon: Texture2D, lift: float, label: String, font: Font) -> void:
	var feet := Vector2(0, 6)
	var base: float = BASE.get(str(squad.leader.info(data)["size"]) if data else "Small", BASE["Small"])
	if selected:
		_ellipse(feet, base + 6, Color(1, 0.9, 0.3), 3.0)
	draw_set_transform(feet, 0.0, Vector2(1.0, 0.32))
	draw_circle(Vector2.ZERO, base, Color(0, 0, 0, 0.22 if squad.sky else 0.4))
	draw_set_transform(Vector2.ZERO)
	_ellipse(feet, base, color, 2.5)
	var at := Rect2(Vector2(-FIGURE * UnitIcons.feet_x(squad.leader.unit_class), feet.y + lift - FIGURE * UnitIcons.FEET), Vector2.ONE * FIGURE)
	for k in 8:
		var off := Vector2.ONE * DROP + Vector2.from_angle(TAU * k / 8.0) * BLUR
		draw_texture_rect(icon, Rect2(at.position + off, at.size), false, Color(0, 0, 0, SHADE))
	for k in 8:  # the dark edge: the silhouette nudged a little every way, under the figure
		draw_texture_rect(icon, Rect2(at.position + Vector2.from_angle(TAU * k / 8.0) * EDGE, at.size), false, Color(0, 0, 0, EDGE_SHADE))
	draw_texture_rect(icon, at, false)
	_tag(feet + Vector2(base * 0.95, 2), label, font)


## The squad's number (an enemy's role initial) on a disc of the side's colour.
func _tag(at: Vector2, label: String, font: Font) -> void:
	draw_circle(at, 8.0, color)
	draw_arc(at, 8.0, 0.0, TAU, 20, Color("#1c2333"), 1.5)
	draw_string(font, at + Vector2(-8, 4.5), label, HORIZONTAL_ALIGNMENT_CENTER, 16, 12, Color.WHITE)


## A flat ellipse round `at`, `r` wide and a third as tall, as an even line.
func _ellipse(at: Vector2, r: float, col: Color, width: float) -> void:
	var pts := PackedVector2Array()
	for i in 41:
		var a := TAU * i / 40.0
		pts.append(at + Vector2(cos(a) * r, sin(a) * r * 0.32))
	draw_polyline(pts, col, width, true)


## The squad's numbered flag on a pole, its foot at the origin.
func _banner(lift: float, label: String, font: Font) -> void:
	var top := Vector2(0, -44 + lift)
	draw_line(Vector2(0, 10 + lift), top, Color("#2a2420"), 3.0)
	var flag := PackedVector2Array([top, top + Vector2(30, 0), top + Vector2(30, 22), top + Vector2(15, 17), top + Vector2(0, 22)])
	draw_colored_polygon(flag, color)
	draw_polyline(flag + PackedVector2Array([top]), Color("#1c2333"), 2.0)
	draw_string(font, top + Vector2(7, 16), label, HORIZONTAL_ALIGNMENT_LEFT, -1, 16, Color.WHITE)
