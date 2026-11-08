extends TestCase
## Variable map size (SPEC §6.1): a custom width/height instead of only
## Small/Medium/Large, so a full playtest doesn't need a large map's runtime.

var d := GameData.load_dir()


func test_custom_dimensions_generate_a_map_of_that_size() -> void:
	var m := MapGen.generate(d, 3, {"width": 150, "height": 90})
	check_eq(m.width, 150, "custom width")
	check_eq(m.height, 90, "custom height")
	check(m.player_base >= 0 and m.enemy_base >= 0, "both bases still placed")
	check(not m.buildings.is_empty(), "buildings still placed on a small custom map")


func test_default_config_still_builds_the_small_preset() -> void:
	var c := GameConfig.create(d, 1)
	check_eq(int(c.values["width"]), 400, "default width")
	check_eq(int(c.values["height"]), 225, "default height")
	check_eq(GameConfig.size_name(d, 400, 225), "Small", "400x225 is still named Small")
	check_eq(GameConfig.size_name(d, 800, 450), "Medium", "800x450 is still named Medium")
	check_eq(GameConfig.size_name(d, 1200, 675), "Large", "1200x675 is still named Large")
	check_eq(GameConfig.size_name(d, 150, 90), "Custom", "an unnamed size reads as Custom")


func test_share_code_round_trips_a_custom_size() -> void:
	var c := GameConfig.create(d, 123)
	c.set_value("width", 150)
	c.set_value("height", 90)
	var code := c.to_code()
	var back := GameConfig.from_code(d, code)
	check(back != null, "the code reads back")
	check_eq(int(back.values["width"]), 150, "width survives the share code")
	check_eq(int(back.values["height"]), 90, "height survives the share code")


## A full day (the survive-timer, which doesn't depend on how combat plays out)
## generates and simulates well within a playtester's patience on a small custom map.
func test_a_small_custom_map_plays_start_to_finish_quickly() -> void:
	var started := Time.get_ticks_msec()
	var m := MapGen.generate(d, 11, {"width": 100, "height": 60})
	var st := GameState.new(d, m, GameLog.new(), {"victory_timer": true, "victory_timer_days": 1})
	st.setup_army()
	st.place_enemies()
	st.place_neutrals()
	var ticks := 0
	while st.game_over == "" and ticks < 3000:
		if st.pending:
			st.resolve_pending()
		elif not st.pending_recruit.is_empty():
			st.resolve_recruit(true)
		else:
			st.step()
		ticks += 1
	var ms := Time.get_ticks_msec() - started
	check_eq(st.game_over, "victory", "a day passes and the survive-timer fires: %d ticks" % ticks)
	check(ms < 5000, "generating and simulating a whole day on a small custom map is fast: %d ms" % ms)
