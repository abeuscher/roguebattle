class_name BuildingMarker
extends Node2D
## Drawn over a building icon, in its texels with the origin at the icon's center: the
## owner's flag, its pole standing on the icon's top, and a progress bar while a squad
## is liberating it.

const POLE := 22.0  # flag sizes in the icons' design units (a hex of size 32)
const FLAG := Vector2(12, 8)

var top := Vector2.ZERO  # where the pole stands, in texels
var unit := 1.0  # texels per design unit
var flag := Color.TRANSPARENT:  # the owner's color; transparent for no flag
	set(v):
		if v != flag:
			flag = v
			queue_redraw()
var progress := 0.0:
	set(v):
		if not is_equal_approx(v, progress):
			progress = v
			queue_redraw()


func _draw() -> void:
	var ink := Color("#1c2333")
	if flag.a > 0.0:
		var peak := top - Vector2(0, POLE * unit)
		draw_line(top, peak, ink, 1.6 * unit)
		var cloth := PackedVector2Array([peak, peak + Vector2(FLAG.x, FLAG.y * 0.5) * unit, peak + Vector2(0, FLAG.y) * unit])
		draw_colored_polygon(cloth, flag)
		draw_polyline(cloth + PackedVector2Array([peak]), ink, 1.0 * unit)
	if progress > 0.0:
		var bar := Rect2(Vector2(-16, 15) * unit, Vector2(32, 4) * unit)
		draw_rect(bar.grow(unit), Color(0.05, 0.05, 0.06, 0.85))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color("#ffe08a"))
