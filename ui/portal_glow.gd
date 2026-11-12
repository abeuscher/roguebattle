class_name PortalGlow
extends Node2D
## Pulsing rings on the temples a squad can step to through a portal (user's notes,
## 2026-11-11: see where you're going on the map instead of reading a list). Rings
## keep a readable size on screen however far the map is zoomed out.

const COLOR := Color(0.55, 0.9, 1.0)
const MIN_SCREEN_RADIUS := 34.0  # pixels

var spots: Array[Vector2] = []
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	var scale_now := get_viewport().get_canvas_transform().x.length()
	var r := maxf(MapView.HEX_SIZE * 1.1, MIN_SCREEN_RADIUS / maxf(scale_now, 0.001))
	var pulse := 0.5 + 0.5 * sin(_t * 4.0)
	var width := 4.0 / maxf(scale_now, 0.001)
	for p in spots:
		draw_circle(p, r * 1.5, Color(COLOR, 0.12 + 0.12 * pulse))
		draw_circle(p, r * 1.1, Color(COLOR, 0.15 + 0.15 * pulse))
		draw_arc(p, r * (1.15 + 0.35 * pulse), 0.0, TAU, 48, Color(COLOR, 0.95 - 0.5 * pulse), width, true)
		draw_arc(p, r * 0.95, 0.0, TAU, 48, Color(1, 1, 1, 0.9), width * 0.6, true)
