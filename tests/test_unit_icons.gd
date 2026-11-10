extends TestCase
## Icons from tools/unit_icons.py: one per class, built from the sheet's Icon columns.

var d := GameData.load_dir()


func test_every_class_has_an_icon() -> void:
	for name in d.units:
		var u: Dictionary = d.units[name]
		check(u.get("icon_base") is String and u["icon_base"] != "", "%s: no Icon base in the sheet" % name)
		check(FileAccess.file_exists(UnitIcons.DIR + UnitIcons.file_name(name) + ".svg"),
				"%s: no icon file (run python tools/unit_icons.py)" % name)


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


func test_card_colors_swap() -> void:
	var light := UnitIcons.texture("Soldier", 32).get_image()
	var dark := UnitIcons.on_card("Soldier", 32, Color("#5a2626")).get_image()
	# Just inside the frame, beside the body, is paper: parchment by default, the card color on a card.
	check_eq(light.get_pixel(4, 16).to_html(false), UnitIcons.PAPER.substr(1), "light icon paper")
	check_eq(dark.get_pixel(4, 16).to_html(false), "5a2626", "card icon paper")
	check_eq(UnitIcons.file_name("Standard-Bearer"), "standard_bearer", "file name")
