extends TestCase

var d := GameData.load_dir()


func _clock(start := 0) -> GameClock:
	return GameClock.new(d.rules, start)


func test_tick_rate_per_speed() -> void:
	var c := _clock()
	check_eq(c.speed(), 1.0, "starts at normal speed")
	check_eq(c.advance(300.0), 1440, "a day lasts 5 real minutes at normal speed")
	var expected := {0: 1.2, 1: 2.4, 2: 4.8, 3: 9.6, 4: 19.2}  # ticks per real second
	for index in expected:
		c = _clock()
		c.set_speed_index(index)
		check_eq(c.advance(10.0), int(round(expected[index] * 10.0)), "ticks in 10 s at speed %d" % index)


func test_fractions_carry_over() -> void:
	var c := _clock()
	var total := 0
	for frame in 60:
		total += c.advance(1.0 / 60.0)
	check_eq(total, 4, "4.8 ticks per second: 4 whole ticks after 1 s")
	total += c.advance(0.05)
	check_eq(total, 5, "the leftover 0.8 completes a tick soon after")


func test_speed_clamps() -> void:
	var c := _clock()
	c.set_speed_index(-3)
	check_eq(c.speed_index, 0, "no slower than ultra slow")
	c.set_speed_index(99)
	check_eq(c.speed_index, 4, "no faster than ultra fast")


func test_pause_and_holds() -> void:
	var c := _clock()
	c.paused = true
	check_eq(c.advance(10.0), 0, "paused: no ticks")
	c.paused = false
	c.hold()
	c.hold()
	check_eq(c.advance(10.0), 0, "held by a menu: no ticks")
	c.release()
	check_eq(c.advance(10.0), 0, "still held once")
	c.release()
	check(c.advance(10.0) > 0, "released: time runs")


func test_day_boundaries_and_events() -> void:
	var c := _clock(GameClock.NOON - 1)
	check_eq(c.step(), PackedStringArray(["noon", "half_day"]), "noon events")
	c = _clock(GameClock.TICKS_PER_DAY - 1)
	check_eq(c.step(), PackedStringArray(["new_day", "half_day"]), "midnight events")
	check_eq(c.day(), 2, "day 2 after midnight")
	check_eq(c.time_text(), "Day 2 · 00:00", "clock text")
	c = _clock(GameClock.DAWN - 1)
	check(not c.is_day(), "05:59 is night")
	check_eq(c.step(), PackedStringArray(["dawn"]), "dawn event")
	check(c.is_day(), "06:00 is day")
	c = _clock(GameClock.DUSK - 1)
	check(c.is_day(), "17:59 is day")
	c.step()
	check(not c.is_day(), "18:00 is night")


func test_state_logs_days_and_speed() -> void:
	var m := MapData.new(4, 4)
	m.settings = {"preset": "continent", "size": "small"}
	var log := GameLog.new()
	var s := GameState.new(d, m, log)
	check_eq(s.gold, 500, "starting gold")
	check_eq(s.reputation, 50, "starting reputation")
	check_eq(s.clock.time_text(), "Day 1 · 08:00", "game starts at 08:00")
	s.set_speed_index(3)
	for t in GameClock.TICKS_PER_DAY:
		s.step()
	check_eq(log.filtered("system").filter(func(e): return e["text"] == "Day 2 begins.").size(), 1, "day change logged once")
	check(log.filtered("system").any(func(e): return e["text"].begins_with("Game speed: Fast")), "speed change logged")
