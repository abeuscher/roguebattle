extends TestCase
## The campaign layer (SPEC §25): campaign files, chapter settings, the army carried from
## map to map, and the campaign's own save.

var d := GameData.load_dir()


## A small map in the chapter's mode, its army set up as the chapter does.
func _state(run: Campaign) -> GameState:
	var m := MapGen.generate(d, 5, {"size": "small", "section_pct": 100})
	var st := GameState.new(d, m, GameLog.new(), run.settings(d))
	run.set_up(st)
	return st


func _count(st: GameState) -> int:
	var n := st.army.pool.size()
	for s in st.army.cells:
		if s:
			n += (s as Squad).units.size()
	return n


func test_trifectus_is_listed_with_three_chapters() -> void:
	var all := Campaign.list_all()
	check(all.any(func(c): return c["id"] == "trifectus"), "the Kingdom of Trifectus is a campaign")
	var run := Campaign.begin("trifectus", 7, "Ada")
	check_eq(run.info["chapters"].size(), 3, "three maps")
	check(Campaign.begin("no_such_campaign", 7) == null, "a missing file is no campaign")


func test_a_chapter_is_its_map_settings_in_single_map_mode() -> void:
	var run := Campaign.begin("trifectus", 7, "Ada")
	run.chapter = 2
	var c := run.config(d)
	check_eq(c.values["preset"], "volcanic", "the chapter's map type")
	check_eq(int(c.values["width"]), 500, "its size")
	check_eq(int(c.values["section_pct"]), 50, "and its chokepoints")
	check_eq(c.values["mode"], "single", "single map rules")
	check_eq(c.seed, 9, "chapter n's seed is the run's plus n")
	check(GameConfig.from_code(d, c.to_code()) != null, "and its settings make a share code (saves rebuild the map from it)")
	var s := run.settings(d)
	check_eq(s["campaign"], "trifectus", "the state knows its campaign")
	check_eq(int(s["chapter"]), 2, "and chapter")
	check_eq(s["player_name"], "Ada", "and your name")


func test_the_army_carries_to_the_next_map() -> void:
	var run := Campaign.begin("trifectus", 7, "Ada")
	var st := _state(run)
	check_eq(st.opinion_leader.name, "Ada", "chapter 1 starts as a single map, your leader named")
	var lead := st.opinion_leader
	Progression.level_up(d, lead, st.rng.get_stream("test"))
	lead.hp = 1
	lead.poison_left = 30
	var units_before := _count(st)
	st.tech.append("veterans")
	st.tech_points = 4
	st.reputation = 71
	st.gold = 99999
	var cards := st.cards.duplicate()
	st.army.add_item("ring")
	var item: Dictionary = st.army.items[-1]
	check(st.army.equip(lead, item), "a ring on the leader")
	run.advance(st)
	check_eq(run.chapter, 1, "on to chapter 2")
	var next := _state(run)
	var led := next.opinion_leader
	check_eq(led.name, "Ada", "the Opinion Leader comes along")
	check_eq(led.level, 2, "at the level earned")
	check_eq(led.hp, led.max_hp(d), "healed")
	check_eq(led.poison_left, 0, "poison gone")
	check_eq(_count(next), units_before, "every unit, in squads and the pool")
	check(next.tech.has("veterans") and next.tech_points == 4, "tech and tech points")
	check_eq(next.reputation, 71, "reputation")
	check_eq(next.cards, cards, "the hand of cards")
	check(next.gold != 99999, "but not the gold (%d)" % next.gold)
	check(not led.items.is_empty() and next.army.items.any(func(i): return i == led.items.values()[0]), "items worn, still the army's own")
	check(next.squads.size() == 1 and next.squads[0].leader == led and next.squads[0].hex == next.map.player_base, "the Opinion Leader's squad on the map at the base")
	check(next.squads[0].tech == next.tech, "squads share the army's tech")


func test_the_campaign_saves_and_resumes() -> void:
	Campaign.save_path = "user://test_saves/campaign.save"
	var run := Campaign.begin("trifectus", 7, "Ada")
	var st := _state(run)
	run.advance(st)
	check_eq(run.save(), "", "saved")
	var back := Campaign.load_saved()
	check(back != null and back.id == "trifectus" and back.chapter == 1 and back.player_name == "Ada", "resumes at chapter 2")
	check_eq(back.carry["units"].size(), run.carry["units"].size(), "with the army it carried")
	DirAccess.remove_absolute(Campaign.save_path)
	check(Campaign.load_saved() == null, "none once removed")
	Campaign.save_path = "user://saves/campaign.save"
