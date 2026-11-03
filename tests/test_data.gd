extends TestCase

const STATS := ["STR", "CON", "INT", "SPD", "AGI", "PDEF", "MDEF"]
const FIELDS := ["class", "stage", "size", "slots", "can_lead", "alignment_lean", "terrain",
		"speed_tier", "role", "key_stats", "base_stats", "flex_min", "flex_max",
		"front_attack", "front_count", "back_attack", "back_count", "lines"]

var d := GameData.load_dir()


func test_every_class_loads() -> void:
	check(d.units.size() > 0, "no classes loaded")
	for name in d.units:
		var u: Dictionary = d.units[name]
		for f in FIELDS:
			check(u.has(f) and u[f] != null, "%s: missing %s" % [name, f])
		for s in STATS:
			check(u["base_stats"].get(s) is float, "%s: stat %s is not a number" % [name, s])
		check(int(u["stage"]) in [1, 2, 3, 4], "%s: bad stage %s" % [name, u["stage"]])
		check(int(u["speed_tier"]) in [1, 2, 3], "%s: bad speed tier" % name)
		check(d.role_templates.has(u["role"]), "%s: role %s has no template" % [name, u["role"]])


func test_lines_resolve() -> void:
	for line_id in d.lines:
		var stages: Array = d.lines[line_id]
		for i in stages.size():
			for c in stages[i]:
				check(d.units.has(c), "line %s: '%s' has no class" % [line_id, c])
				if i > 0 and d.units.has(c) and d.units.has(stages[i - 1][0]):
					check_eq(int(d.units[c]["stage"]), int(d.units[stages[i - 1][0]]["stage"]) + 1,
							"line %s: stage of '%s'" % [line_id, c])
	for name in d.units:
		for line_id in d.units[name]["lines"]:
			check(d.lines.has(line_id), "%s: unknown line %s" % [name, line_id])
		if int(d.units[name]["stage"]) < 4:
			check(not d.next_classes(name).is_empty(), "%s: no next class" % name)


func test_next_classes() -> void:
	check_eq(d.next_classes("Fighter"), PackedStringArray(["Soldier", "Spearman", "Knight", "Berserker", "Tamer", "Sapper"]),
			"Fighter promotes to")
	check_eq(d.next_classes("Soldier"), PackedStringArray(["Sentinel", "Champion"]), "Soldier promotes to")


func test_sizes_map_to_slots() -> void:
	var expected := {"Small": 1.0, "Large": 2.0, "Tiny": 0.5}
	for size in expected:
		check_eq(float(d.rules["size_slots"][size]), expected[size], "slots for " + size)
	for name in d.units:
		var u: Dictionary = d.units[name]
		check(expected.has(u["size"]), "%s: unknown size %s" % [name, u["size"]])
		check_eq(d.slots_for(u), float(u["slots"]), "%s: sheet slots vs size" % name)


func test_names_load() -> void:
	check(d.first_names.size() > 50, "too few first names")
	check(d.last_names.size() > 50, "too few last names")


func test_terrain_keys() -> void:
	for key in ["plains", "forest", "desert", "snow", "mountain", "swamp", "shallow", "deep", "lava", "cliff", "air_gap"]:
		check(d.terrain_ids.has(key), "terrain missing: " + key)
