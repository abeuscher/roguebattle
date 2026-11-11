extends TestCase

var d := GameData.load_dir()


func test_defaults() -> void:
	var c := GameConfig.create(d, 42)
	check_eq(int(c.values["width"]), 400, "default width")
	check_eq(int(c.values["height"]), 225, "default height")
	check_eq(c.values["preset"], "continent", "default map type")
	check_eq(int(c.values["land_pct"]), 55, "continent land %")
	check_eq(c.values["terrain_amounts.desert"], "low", "desert low by default")
	check_eq(c.values["road_coverage"], "main", "main roads")
	check_eq(float(c.map_overrides()["hidden_road_chance"]), 0.25, "25% chance of a road to a hidden site")
	check_eq(int(c.values["squad_cap"]), 6, "squad cap 6 on the default small map")
	check_eq(c.values["victory_leader"], true, "defeat the enemy leader on by default")
	check_eq(c.values["defeat_leader"], true, "losing the Opinion Leader on by default")


func test_preset_resets_its_fields() -> void:
	var c := GameConfig.create(d)
	c.set_value("terrain_amounts.forest", "none")
	c.set_value("preset", "deep_forest")
	check_eq(c.values["terrain_amounts.forest"], "high", "deep forest sets forest high")
	check_eq(int(c.values["land_pct"]), 58, "deep forest land %")
	check_eq(c.values["terrain_amounts.lava"], "none", "deep forest has no lava")


func test_overrides_build_the_same_map() -> void:
	var c := GameConfig.create(d, 9)
	c.set_value("preset", "islands")
	c.set_value("terrain_amounts.snow", "high")
	var o := c.map_overrides()
	check_eq(o["terrain_amounts"]["snow"], "high", "terrain amounts nest")
	var a := MapGen.generate(d, c.seed, o)
	var b := MapGen.generate(d, 9, {"preset": "islands", "terrain_amounts": {"snow": "high"}})
	check(a.terrain == b.terrain, "configurator settings rebuild the same map as hand-written ones")


func test_share_code_round_trip() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 5
	for trial in 30:
		var c := GameConfig.create(d, rng.randi())
		for f in d.config_fields:
			var opts := GameConfig.options(f)
			c.values[f["key"]] = opts[rng.randi_range(0, opts.size() - 1)]
		var code := c.to_code()
		var back := GameConfig.from_code(d, code)
		check(back != null, "code %s reads back" % code)
		if back == null:
			return
		check_eq(back.seed, c.seed, "seed survives")
		for f in d.config_fields:
			check(back.values[f["key"]] == c.values[f["key"]], "%s survives %s" % [f["key"], code])
	var code := GameConfig.create(d, 4000000000).to_code()
	check(code.length() <= 35, "code is short (%d chars: %s)" % [code.length(), code])
	check(GameConfig.from_code(d, code.to_lower()) != null, "codes ignore case")


func test_bad_codes_rejected() -> void:
	check(GameConfig.from_code(d, "") == null, "empty")
	check(GameConfig.from_code(d, "HELLO") == null, "too short")
	check(GameConfig.from_code(d, "IIII-IIII") == null, "letters outside the alphabet")
	var code := GameConfig.create(d, 1).to_code()
	check(GameConfig.from_code(d, "Z" + code.substr(1)) == null, "wrong version")


func test_game_mode_and_squad_cap_by_size() -> void:
	var c := GameConfig.create(d, 1)
	check_eq(c.values["mode"], "single", "single map mode by default")
	check_eq(int(c.values["xp_rate"]), 150, "XP rate 150% by default")
	check_eq(GameConfig.options(c.field("xp_rate")).front(), 100, "from 100%")
	check_eq(int(GameConfig.options(c.field("xp_rate")).back()), 300, "to 300%")
	check_eq(int(c.values["squad_cap"]), 6, "6 on the map for a small map")
	c.set_value("width", 800)
	c.set_value("height", 450)
	check_eq(int(c.values["squad_cap"]), 8, "8 for a medium one")
	c.set_value("width", 1200)
	c.set_value("height", 675)
	check_eq(int(c.values["squad_cap"]), 10, "10 for a large one")
	c.set_value("mode", "campaign")
	check_eq(int(c.values["squad_cap"]), 6, "the campaign start keeps 6, one per squad")
	var back := GameConfig.from_code(d, c.to_code())
	check_eq(back.values["mode"], "campaign", "the mode survives the share code")
