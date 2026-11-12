class_name Fireworks
extends Node2D
## A small fireworks show over a building just liberated (user's playtest notes,
## 2026-11-10), so it stands out among its neighbours. A few staggered bursts of sparks
## that rise, spread and fade, then the node frees itself. Sizes are screen pixels:
## the battlemap scales it by 1 / zoom so it reads the same at any zoom.

const COLORS := [Color("#ffe08a"), Color("#ff7a5a"), Color("#8fd0ff"), Color("#b8ff8a"), Color("#ff9be0")]
const BURSTS := 5
const SPARKS := 16
const STAGGER := 0.35  # seconds between bursts
const LIFE := 1.4  # seconds a burst lasts
const RADIUS := 64.0  # pixels a burst spreads to

var _t := 0.0
var _heard := 0  # bursts whose sound has played (audio.json "firework_burst")
var _bursts := []  # [offset, color] per burst


func _ready() -> void:
	z_index = 10
	var r := RandomNumberGenerator.new()  # looks only: no game randomness involved
	for i in BURSTS:
		_bursts.append([Vector2(r.randf_range(-50, 50), r.randf_range(-120, -60)), COLORS[i % COLORS.size()]])


func _process(delta: float) -> void:
	_t += delta
	while _heard < BURSTS and _t >= _heard * STAGGER:
		_heard += 1
		Sound.event("firework_burst")
	if _t > STAGGER * (BURSTS - 1) + LIFE:
		queue_free()
	queue_redraw()


func _draw() -> void:
	for i in BURSTS:
		var age := _t - i * STAGGER
		if age < 0.0 or age > LIFE:
			continue
		var k := age / LIFE
		var at: Vector2 = _bursts[i][0]
		var c: Color = _bursts[i][1]
		var spread := RADIUS * (1.0 - pow(1.0 - k, 3))
		c.a = 1.0 - k * k
		for j in SPARKS:
			var dir := Vector2.RIGHT.rotated(TAU * j / SPARKS + i)
			var p := at + dir * spread + Vector2(0, 24.0 * k * k)  # sparks droop as they fade
			draw_line(p - dir * 12.0 * (1.0 - k), p, c, 3.0)
			draw_circle(p, 3.5, c)
		if k < 0.25:
			draw_circle(at, 10.0 * (1.0 - k * 4.0), Color(1, 1, 1, 0.9))
