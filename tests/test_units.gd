extends TestCase
## Units and squads (SPEC §8.1–8.3, §9.2–9.3, §12.2 rolls).

var d := GameData.load_dir()
var rng := RandomNumberGenerator.new()
var names := NameBook.new(d)


func _squad(members: Array) -> Squad:
	var s := Squad.new(1, "Test", 0)
	for m in members:
		check(s.add(d, Unit.roll(d, m[0], rng, names), m[1] if m.size() > 1 else "front"), "%s fits" % m[0])
	return s


func test_rolls_stay_in_range() -> void:
	rng.seed = 7
	for class_name_ in ["Serf", "Fighter", "Knight", "Dragon", "Mermaid"]:
		var c: Dictionary = d.units[class_name_]
		var base := 0
		for s in Unit.STATS:
			base += int(c["base_stats"][s])
		for i in 200:
			var u := Unit.roll(d, class_name_, rng, names)
			var total := 0
			for s in Unit.STATS:
				check(u.stats[s] >= int(c["base_stats"][s]), "%s never loses base %s" % [class_name_, s])
				total += u.stats[s]
			check(total - base >= int(c["flex_min"]) and total - base <= int(c["flex_max"]), "%s flex within range" % class_name_)
			check_eq(u.hp, u.stats["CON"] * 10, "HP is CON x 10")
			check(u.luck >= 0 and u.luck <= 20, "luck 0-20")
			check(u.alignment >= 0 and u.alignment <= 100, "alignment 0-100")
			for s in u.growth:
				check(s not in c["key_stats"] and u.growth[s] >= 0.2 and u.growth[s] <= 0.5, "growth only for non-key stats, 20-50%")
			check_eq(u.growth.size(), Unit.STATS.size() - c["key_stats"].size(), "every non-key stat has a growth chance")


func test_flex_leans_to_key_stats() -> void:
	rng.seed = 3
	var key := 0
	var other := 0
	for i in 500:
		var u := Unit.roll(d, "Fighter", rng, names)  # key stats STR, AGI
		var base: Dictionary = d.units["Fighter"]["base_stats"]
		for s in Unit.STATS:
			if s in ["STR", "AGI"]:
				key += u.stats[s] - int(base[s])
			else:
				other += u.stats[s] - int(base[s])
	check(key > other, "two key stats get more flex than five others (%d vs %d)" % [key, other])


func test_alignment_follows_lean() -> void:
	rng.seed = 5
	for lean in ["Evil", "Neutral", "Holy"]:
		var c := ""
		for k in d.units:
			if d.units[k]["alignment_lean"] == lean:
				c = k
				break
		for i in 100:
			check_eq(Unit.roll(d, c, rng, names).alignment_band(d), lean.to_lower(), "%s lean rolls %s" % [c, lean])


func test_talent_shares() -> void:
	rng.seed = 11
	var count := {"ordinary": 0, "gifted": 0, "prodigy": 0}
	for i in 4000:
		count[Unit.roll(d, "Serf", rng, names).talent] += 1
	check(absf(count["ordinary"] / 4000.0 - 0.8) < 0.03, "about 80%% ordinary (%d)" % count["ordinary"])
	check(absf(count["prodigy"] / 4000.0 - 0.05) < 0.015, "about 5%% prodigy (%d)" % count["prodigy"])


func test_no_repeated_names() -> void:
	var book := NameBook.new(d)
	book.first = PackedStringArray(["Ann", "Bo", "Cy"])
	book.last = PackedStringArray(["Ash", "Birch"])
	rng.seed = 2
	var seen := {}
	for i in 8:  # all six pairings, then the fallback
		var name := book.take(rng)
		check(not seen.has(name), "name repeated: " + name)
		seen[name] = true
	check(seen.has("Cy Birch") and seen.has("Ann Ash"), "every pairing gets used")
	var run := NameBook.new(d)
	for i in 300:
		check(Unit.roll(d, "Serf", rng, run).name.split(" ").size() >= 2, "first and last name")
	check_eq(run.used.size(), 300, "300 different names in one run")


func test_slots() -> void:
	var s := _squad([["Knight"], ["Fighter"], ["Fighter"], ["Bowman", "back"], ["Acolyte", "back"]])
	check_eq(Squad.slots_filled(d, s.units), 5.0, "five small units fill five slots")
	check(not s.can_add(d, Unit.roll(d, "Fighter", rng, names)), "a sixth doesn't fit")
	check_eq(s.leader.unit_class, "Knight", "first unit that can lead leads")
	check_eq(s.row("back").size(), 2, "two in the back row")
	var big := _squad([["Sea Dragon"], ["Serpent"]])
	check_eq(Squad.slots_filled(d, big.units), 4.0, "large units take two slots")
	check(not big.add(d, Unit.roll(d, "Serpent", rng, names)), "a third large unit doesn't fit in five")
	# Tiny: no Tiny class in the sheet yet, so make one.
	d.units["Test Tiny"] = d.units["Serf"].duplicate()
	d.units["Test Tiny"]["size"] = "Tiny"
	var tiny := _squad([["Knight"], ["Fighter"], ["Fighter"], ["Fighter"]])
	for i in 2:
		check(tiny.add(d, Unit.roll(d, "Test Tiny", rng, names)), "two Tiny units share the last slot")
	check(not tiny.can_add(d, Unit.roll(d, "Test Tiny", rng, names)), "a third Tiny needs a slot of its own")
	d.units.erase("Test Tiny")


func test_slot_growth() -> void:
	var s := _squad([["Knight"]])
	s.leader.level = 5
	s.leader.charisma = 24
	check(not s.check_slot_growth(d), "level 5 needs charisma 25")
	s.leader.charisma = 25
	check(s.check_slot_growth(d), "level 5 with charisma 25 earns a slot")
	check_eq(s.capacity(d), 6, "six slots")
	s.leader.level = 6
	check(not s.check_slot_growth(d), "only at 5, 10, 15, 20")
	s.leader.level = 10
	s.leader.charisma = 48
	d.units["Herald"] = d.units["Fighter"].duplicate()  # banner bearers aren't in the sheet yet
	s.add(d, Unit.roll(d, "Herald", rng, names))
	check(not s.check_slot_growth(d), "48 + Herald 1 < 50")
	s.leader.charisma = 49
	check(s.check_slot_growth(d), "49 + Herald 1 = 50")
	d.units.erase("Herald")


func test_vote() -> void:
	check_eq(_squad([["Knight"], ["Fighter"], ["Rogue"]]).travel_type, "plains", "plains majority")
	var forest := _squad([["Rogue"], ["Knight"], ["Fighter"]])  # Rogue leads: forest 2 vs plains 2
	check_eq(forest.travel_type, "forest", "a tie goes to the leader's terrain")
	var beasts := _squad([["Fighter"], ["Fighter"], ["Fighter"], ["Rogue"]])
	check_eq(beasts.leader.unit_class, "Rogue", "Rogue leads")
	check_eq(beasts.travel_type, "plains", "three plains (3) beat a forest leader (2)")
	check_eq(_squad([["Knight"], ["Serpent"]]).travel_type, "plains", "a large water unit (2) ties the plains leader (2): leader wins")
	check_eq(_squad([["Knight"], ["Serpent"], ["Mermaid"]]).travel_type, "shallow", "water 3 beats plains 2")
	var flyers := _squad([["Eagle Knight"], ["Eagle Rider"], ["Gryphon"]])
	check(flyers.sky, "all flyers: Sky")
	var mixed := _squad([["Eagle Knight"], ["Eagle Rider"], ["Fighter"]])
	check(not mixed.sky, "one walker grounds the squad")
	check_eq(mixed.travel_type, "plains", "flyers' votes are dropped")


func test_deep_water() -> void:
	var swimmers := _squad([["Siren"], ["Mermaid"], ["Frog"]])
	check_eq(swimmers.travel_type, "deep", "all water natives can swim deep water")
	var m := MapData.new(2, 1)
	m.terrain[0] = d.terrain_ids["deep"]
	m.terrain[1] = d.terrain_ids["shallow"]
	check_eq(Movement.hex_multiplier(m, d, 0, "deep"), 1.0, "deep water at full speed")
	check_eq(Movement.hex_multiplier(m, d, 1, "deep"), 1.0, "shallow water at full speed")
	var wet := _squad([["Siren"], ["Mermaid"], ["Knight"]])
	check_eq(wet.travel_type, "shallow", "one non-native keeps them in the shallows")
	check_eq(Movement.hex_multiplier(m, d, 0, "shallow"), INF, "a mixed water squad can't cross deep water")
	check_eq(Movement.hex_multiplier(m, d, 0, "lava"), INF, "natives_cross is deep water only")


func test_speed_tier_and_casualties() -> void:
	var s := _squad([["Knight"], ["Centaur"], ["Bowman"], ["Fighter"], ["Militia"]])
	check_eq(s.speed_tier, 1, "the slowest unit sets the tier")
	var slow: Array[Unit] = [s.units[0], s.units[3]]
	for u in slow:
		u.hp = 0
	s.refresh(d)
	check_eq(s.speed_tier, 2, "dead units don't slow the tier")
	check_eq(s.casualty_multiplier(d), 1.4, "two of five slots lost: 40% slower")
	var whole := _squad([["Knight"]])
	check_eq(whole.casualty_multiplier(d), 1.0, "no losses, no slowdown")
