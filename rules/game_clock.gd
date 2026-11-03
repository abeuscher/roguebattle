class_name GameClock
extends RefCounted
## In-game time (SPEC §7): 1 tick = 1 minute, 1,440 ticks a day, 4.8 ticks per
## real second at normal speed (5 real minutes a day). Game speed scales the
## rate. The player's pause and any holds (open menus, battles) stop it.

const TICKS_PER_DAY := 1440
const NOON := 720
const DAWN := 360  # day runs 06:00-18:00
const DUSK := 1080

var tick := 0
var paused := false
var speed_index: int
var _speeds: Array
var _ticks_per_second: float
var _carry := 0.0  # fraction of a tick owed from earlier frames
var _holds := 0


func _init(rules: Dictionary, start_tick := 0) -> void:
	_speeds = rules["game_speeds"]
	_ticks_per_second = float(rules["ticks_per_real_second"])
	speed_index = int(rules["default_speed_index"])
	tick = start_tick


func speed() -> float:
	return float(_speeds[speed_index])


func set_speed_index(index: int) -> void:
	speed_index = clampi(index, 0, _speeds.size() - 1)


## Stops time until a matching release(), whatever the player's pause says.
func hold() -> void:
	_holds += 1


func release() -> void:
	_holds = maxi(0, _holds - 1)


func is_running() -> bool:
	return not paused and _holds == 0


## How many ticks are due after `real_seconds` of real time. Call step() that many times.
func advance(real_seconds: float) -> int:
	if not is_running():
		return 0
	_carry += real_seconds * _ticks_per_second * speed()
	var n := int(_carry)
	_carry -= n
	return n


## Moves time on by one tick and returns the scheduled events it reaches.
func step() -> PackedStringArray:
	tick += 1
	var events := PackedStringArray()
	match minute_of_day():
		0:
			events.append_array(["new_day", "half_day"])
		NOON:
			events.append_array(["noon", "half_day"])
		DAWN:
			events.append("dawn")
		DUSK:
			events.append("dusk")
	return events


func day() -> int:
	return tick / TICKS_PER_DAY + 1


func minute_of_day() -> int:
	return tick % TICKS_PER_DAY


func is_day() -> bool:
	return minute_of_day() >= DAWN and minute_of_day() < DUSK


func time_text() -> String:
	return "Day %d · %02d:%02d" % [day(), minute_of_day() / 60, minute_of_day() % 60]
