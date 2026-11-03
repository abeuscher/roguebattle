class_name BuildingMarker
extends Node2D
## Drawn over a building icon (in its texels): a blue pennant once the player holds it,
## and a progress bar while a squad is liberating it.

var owned := false:
	set(v):
		if v != owned:
			owned = v
			queue_redraw()
var progress := 0.0:
	set(v):
		if not is_equal_approx(v, progress):
			progress = v
			queue_redraw()


func _draw() -> void:
	if owned:
		var top := Vector2(16, -56)
		draw_line(top, top + Vector2(0, 26), Color("#1c2333"), 3.0)
		var flag := PackedVector2Array([top, top + Vector2(26, 6), top + Vector2(0, 14)])
		draw_colored_polygon(flag, Color("#3b6fd6"))
		draw_polyline(flag + PackedVector2Array([top]), Color("#1c2333"), 2.0)
	if progress > 0.0:
		var bar := Rect2(-34, 8, 68, 9)
		draw_rect(bar.grow(2), Color(0.05, 0.05, 0.06, 0.85))
		draw_rect(Rect2(bar.position, Vector2(bar.size.x * progress, bar.size.y)), Color("#ffe08a"))
