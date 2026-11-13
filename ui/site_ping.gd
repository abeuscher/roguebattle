class_name SitePing
extends Node2D
## Rings spreading out from a hidden site the moment it comes into view (ROADMAP M5
## session 5: with the "Hidden Location!" line, so you can see where it is). Keeps a
## readable size on screen at any zoom, then frees itself.

const COLOR := Color(1.0, 0.85, 0.4)
const MIN_SCREEN_RADIUS := 30.0  # pixels

var seconds := 3.0
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= seconds:
		queue_free()
	queue_redraw()


func _draw() -> void:
	var scale_now := maxf(get_viewport().get_canvas_transform().x.length(), 0.001)
	var r := maxf(MapView.HEX_SIZE, MIN_SCREEN_RADIUS / scale_now)
	var width := 4.0 / scale_now
	var fade := 1.0 - _t / seconds
	for k in 3:  # three rings, a third of a second apart, each spreading and fading
		var phase := fmod(_t * 1.2 + k / 3.0, 1.0)
		draw_arc(Vector2.ZERO, r * (0.6 + 2.4 * phase), 0.0, TAU, 48, Color(COLOR, (1.0 - phase) * fade), width, true)
	draw_circle(Vector2.ZERO, r * 0.5, Color(COLOR, 0.35 * fade))
