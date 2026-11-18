extends TestCase
## Playtest notes, 2026-11-18: options to pause after any battle and after a liberation;
## the Opinion Leader starts sturdier, with armor and a weapon.

var d := GameData.load_dir()


func _state(seed := 7) -> GameState:
	var cfg := GameConfig.create(d, seed)
	cfg.set_value("width", 100)
	cfg.set_value("height", 45)
	var m := MapGen.generate(d, cfg.seed, cfg.map_overrides())
	var st := GameState.new(d, m, GameLog.new(), cfg.game_settings())
	st.setup_army()
	return st


func test_pause_after_every_battle_only_when_asked() -> void:
	var opts := {}
	check(not GameState.pause_after("won", opts), "off by default")
	opts["pause_after_battle"] = true
	for r in ["won", "lost", "retreated"]:
		check(GameState.pause_after(r, opts), "on: %s pauses" % r)
	check(not bool(d.options["options"]["pause_after_liberation"]["default"]), "pausing after a liberation is off by default")


func test_the_opinion_leader_starts_sturdier() -> void:
	var kit: Dictionary = d.rules["opinion_leader_kit"]
	for seed in [7, 8, 9]:
		var st := _state(seed)
		var u := st.opinion_leader
		check_eq(u.hp_mult, float(kit["hp_mult"]), "more max HP")
		check_eq(u.hp, u.max_hp(d), "and at full health")
		check_eq(str(u.items.get("armor", {}).get("id", "")), str(kit["armor"]), "wearing armor")
		var weapon := str(u.items.get("weapon", {}).get("id", ""))
		var jewel := str(u.items.get("jewelry", {}).get("id", ""))
		check((weapon in kit["weapons"] and u.can_use(d, weapon)) or (weapon == "" and jewel == str(kit["no_weapon"])),
				"a weapon it can use, else jewelry (%s the %s: %s %s)" % [u.name, u.unit_class, weapon, jewel])
		var other: Unit = st.army.units().filter(func(o: Unit): return o != u)[0]
		check_eq(other.hp_mult, 1.0, "the others as they were")
