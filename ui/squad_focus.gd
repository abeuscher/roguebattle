class_name SquadFocus
extends Node2D
## A ring round a squad picked from the squad list (round 24), drawn like the Portal's
## temple rings: it holds a beat, then shrinks into the squad and fades. It follows the
## squad's token if it's moving.

const COLOR := PortalGlow.COLOR
const MIN_SCREEN_RADIUS := 34.0  # pixels

var target: Node2D
var hold := 0.6  # seconds before it shrinks (rules.json squad_focus)
var shrink := 0.5  # seconds it takes to shrink and fade
var _t := 0.0


func _process(delta: float) -> void:
	_t += delta
	if _t >= hold + shrink or not is_instance_valid(target):
		queue_free()
		return
	position = target.position
	queue_redraw()


func _draw() -> void:
	var scale_now := maxf(get_viewport().get_canvas_transform().x.length(), 0.001)
	var r := maxf(MapView.HEX_SIZE * 1.1, MIN_SCREEN_RADIUS / scale_now)
	var k := clampf((_t - hold) / shrink, 0.0, 1.0)  # 0 holding, 1 gone
	var size := r * (1.0 - 0.7 * k)
	var a := 1.0 - k
	var width := 4.0 / scale_now
	draw_circle(Vector2.ZERO, size * 1.1, Color(COLOR, 0.2 * a))
	draw_arc(Vector2.ZERO, size * 1.2, 0.0, TAU, 48, Color(COLOR, 0.95 * a), width, true)
	draw_arc(Vector2.ZERO, size * 0.95, 0.0, TAU, 48, Color(1, 1, 1, 0.9 * a), width * 0.6, true)
