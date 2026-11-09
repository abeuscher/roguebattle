class_name PathView
extends Node2D
## Draws squad routes over the map: the route being planned, bright with
## numbered rally points, and committed routes, faint.

var planned := PackedVector2Array()
var rally := PackedVector2Array()
var committed: Array[PackedVector2Array] = []
var zoom := 1.0
# Debug (§19.2), filled by the battlemap only while switched on in the debug panel:
var show_ai := false
var show_sight := false
var ai_lines: Array = []  # [from, to, label]: each enemy squad's role and target
var sight_rings: Array = []  # [center, radius]: each player squad's sight radius


func _draw() -> void:
	var w := 3.0 / zoom
	for line in committed:
		if line.size() > 1:
			draw_polyline(line, Color(1, 1, 1, 0.45), w)
	if planned.size() > 1:
		draw_polyline(planned, Color(0.05, 0.05, 0.05, 0.6), w * 2.2)
		draw_polyline(planned, Color(1, 0.85, 0.25), w)
	var font := ThemeDB.fallback_font
	var size := int(14.0 / zoom)
	for r in sight_rings:
		draw_arc(r[0], r[1], 0.0, TAU, 64, Color(0.5, 0.9, 1.0, 0.6), w)
	for a in ai_lines:
		if a[0] != a[1]:
			draw_line(a[0], a[1], Color(1, 0.35, 0.3, 0.7), w)
			draw_circle(a[1], 6.0 / zoom, Color(1, 0.35, 0.3, 0.9))
		draw_string(font, a[0] + Vector2(-40, -26) / zoom, a[2], HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color(1, 0.75, 0.7))
	for j in rally.size():
		var p := rally[j]
		draw_circle(p, 11.0 / zoom, Color(0.1, 0.1, 0.1, 0.85))
		draw_circle(p, 9.0 / zoom, Color(1, 0.85, 0.25))
		draw_string(font, p + Vector2(-4.5, 5.0) / zoom, str(j + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.BLACK)
