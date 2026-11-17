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
	check_eq(c.values["preset"], "castle_valley", "the chapter's map type")
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
	var joined := 0
	for sq in run.info["chapters"][0]["join"]:
		joined += sq["units"].size()
	check_eq(_count(next), units_before + joined, "every unit, in squads and the pool, and the squads that joined")
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


## Chapter 1 as Trifectus sets it up, its enemies placed.
func _chapter_one() -> GameState:
	var run := Campaign.begin("trifectus", 7, "Alex")
	var st := _state(run)
	st.place_enemies()
	return st


func test_trifectus_starts_with_its_own_army_and_a_boss() -> void:
	var st := _chapter_one()
	var lead := st.opinion_leader
	check(st.squads.filter(func(s: Squad): return s.side == "player").size() == 1 and st.army.cells[0].units == [lead], "the Opinion Leader alone, on the map")
	check_eq(st.army.squads().size(), 4, "and 3 squads waiting at the base")
	check_eq(st.army.pool.size(), 8, "a small recruit pool to pick companions from")
	var boss := st.boss_squad()
	check(boss != null and boss.hex == st.map.enemy_base and boss.role == "leader", "the boss holds the Enemy Base")
	check_eq(boss.name, "Xela", "named for the Opinion Leader, spelled backwards")
	check_eq(boss.leader.name, "Xela", "and so is its leader")
	check(not st.squads.any(func(s: Squad): return s.role == "leader" and not s.boss), "in the Warlord's place")


func test_only_the_opinion_leaders_party_beats_the_boss() -> void:
	var st := _chapter_one()
	var boss := st.boss_squad()
	var other: Squad = st.army.cells[1]
	other.hex = st.map.enemy_base
	st.squads.append(other)
	var b := st.start_battle(other, boss, boss)
	for u in boss.units:
		u.hp = 0
	st.end_battle(b)
	check_eq(st.boss_beaten, "", "another squad's win doesn't count")
	check(st.notices.any(func(n: String): return n.contains("only Alex's party")), "a banner says who must finish it")
	check(st.returning.any(func(e: Dictionary): return e["squad"] == boss), "and the boss comes back at its base")
	var eb := st.building_at(st.map.enemy_base)
	eb["owner"] = "player"
	st._check_game_over()
	check_eq(st.game_over, "", "taking the Enemy Base doesn't win a boss map")
	st.returning.clear()
	for u in boss.units:
		u.hp = u.max_hp(d)
	st.squads.append(boss)
	var ol := st.opinion_leader_squad()
	var b2 := st.start_battle(ol, boss, boss)
	for u in boss.units:
		u.hp = 0
	st.end_battle(b2)
	st._check_game_over()
	check_eq(st.game_over, "victory", "the Opinion Leader's party beating it wins the map")
	check(st.game_over_reason.contains("Xela"), "and says so: %s" % st.game_over_reason)


func test_the_boss_name_follows_a_rename() -> void:
	var st := _chapter_one()
	check(st.rename_leader("Bob"), "renamed")
	check_eq(st.boss_squad().name, "Bob", "Bob backwards is Bob")
	check(st.rename_leader("Marta"), "renamed again")
	check_eq(st.boss_squad().name, "Atram", "the boss follows")
	check_eq(st.boss_squad().leader.name, "Atram", "and its leader")
	check(st.notices.any(func(n: String): return n == "Bob is now known as Atram."), "with a banner")


func test_squads_join_after_the_first_map() -> void:
	var run := Campaign.begin("trifectus", 7, "Alex")
	var st := _state(run)
	var before := st.army.squads().size()
	run.advance(st)
	var next := _state(run)
	check_eq(next.army.squads().size(), before + 3, "three squads join")
	var joined := next.army.squads().slice(before)
	check_eq(joined.filter(func(s: Squad): return s.sky).size(), 1, "one flies high")
	check_eq(joined.filter(func(s: Squad): return s.travel_type == str(d.rules["all_water_travel"]) or s.travel_type == str(d.rules["amphibious_travel"])).size(), 2,
			"two travel on water (%s)" % ", ".join(joined.map(func(s: Squad): return s.travel_type)))
	check(joined.all(func(s: Squad): return s not in next.squads), "waiting at the Player Base")
	next.place_enemies()
	var boss := next.boss_squad()
	check(boss != null and boss.units.size() == 7 and boss.name == "The Evil Mr. Bosstoo", "the Evil Mr. Bosstoo, 7 strong")
	check_eq(int(d.units[boss.leader.unit_class]["stage"]), maxi(3, int(d.units[next.opinion_leader.unit_class]["stage"])), "his class from the Opinion Leader's line")
	check(boss.leader.level > Campaign.army_level(next), "a level above the army's average")
