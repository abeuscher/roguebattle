class_name PathView
extends Node2D
## Draws squad routes over the map: the route being planned, bright with
## numbered rally points, and committed routes, faint.

var planned := PackedVector2Array()
var rally := PackedVector2Array()
var committed: Array[PackedVector2Array] = []
var zoom := 1.0


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
	for j in rally.size():
		var p := rally[j]
		draw_circle(p, 11.0 / zoom, Color(0.1, 0.1, 0.1, 0.85))
		draw_circle(p, 9.0 / zoom, Color(1, 0.85, 0.25))
		draw_string(font, p + Vector2(-4.5, 5.0) / zoom, str(j + 1), HORIZONTAL_ALIGNMENT_LEFT, -1, size, Color.BLACK)
