extends TestCase
## Unit icons (the user's set, 2026-11-14): one per class in data/unit_icons/svg, drawn by
## tools/unit_icons_humans.py and tools/unit_icons_creatures.py from the sheet's Icon columns.

var d := GameData.load_dir()


func test_every_class_has_an_icon() -> void:
	for name in d.units:
		var u: Dictionary = d.units[name]
		check(u.get("icon_base") is String and u["icon_base"] != "", "%s: no Icon base in the sheet" % name)
		check(FileAccess.file_exists(UnitIcons.DIR + UnitIcons.file_name(name) + ".svg"),
				"%s: no icon file (tools/unit_icons_humans.py or unit_icons_creatures.py)" % name)


func test_icons_rasterize_at_the_asked_size() -> void:
	for name in ["Serf", "Fire Mage", "Black Dragon", "Rat King", "Standard-Bearer"]:
		var tex := UnitIcons.texture(name, 48)
		check(tex != null, "%s: icon didn't load" % name)
		if tex:
			check_eq(tex.get_size(), Vector2(48, 48), "%s: icon size" % name)


func test_later_stages_keep_earlier_symbols() -> void:
	# The point of the set: a stage-4 icon shows the hand and head of the stages before it.
	for line_id in d.lines:
		var stages: Array = d.lines[line_id]
		for i in range(1, stages.size()):
			var before: Dictionary = d.units[stages[i - 1][0]]
			for c in stages[i]:
				var u: Dictionary = d.units[c]
				for key in ["icon_base", "icon_hand", "icon_head"]:
					if before.get(key) != null:
						check_eq(u.get(key), before.get(key), "line %s: %s %s" % [line_id, c, key])


func test_icons_are_see_through_round_the_figure() -> void:
	var img := UnitIcons.texture("Soldier", 64).get_image()
	check(img.get_pixel(1, 1).a < 0.05, "a corner is see-through")
	check(img.get_used_rect().size.y > 40, "the figure is there")
	check_eq(UnitIcons.file_name("Standard-Bearer"), "standard_bearer", "file name")


func test_trimmed_icons_fill_their_square() -> void:
	# Small places (the drawer, compact chips) draw the figure without its margin.
	for name in ["Serf", "Rat", "Black Dragon"]:
		var full := UnitIcons.texture(name, 32).get_image().get_used_rect().size
		var trim := UnitIcons.texture(name, 32, true).get_image().get_used_rect().size
		check(maxi(trim.x, trim.y) >= 30, "%s: the trimmed figure fills the square (%s)" % [name, trim])
		check(maxi(trim.x, trim.y) > maxi(full.x, full.y), "%s: larger than in the full icon" % name)


func test_feet_are_found() -> void:
	# The token stands each figure on its shadow by its feet, wherever they are across the art.
	for name in ["Serf", "Knight", "Wolf", "Rat"]:
		var x := UnitIcons.feet_x(name)
		check(x > 0.2 and x < 0.9, "%s: feet at %.2f across" % [name, x])
