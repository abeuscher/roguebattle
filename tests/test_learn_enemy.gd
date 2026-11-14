extends TestCase
## Learn the enemy (playtest round 14, settled 2026-11-14): a unit looked at shows its
## class, level, an HP bar, the attack from its row and a glossary link, never its numbers.

var d := GameData.load_dir()


func _texts(c: Node) -> Array:
	var out := []
	for n in c.find_children("*", "", true, false):
		if n is Label or n is LinkButton:
			out.append(n.text)
	return out


func test_a_closer_look_shows_no_numbers() -> void:
	var u := Unit.new()
	u.unit_class = "Troll"
	u.level = 4
	u.row = "front"
	u.stats = d.units["Troll"]["base_stats"].duplicate()
	u.hp = 7
	var peek := UnitPeek.make(d, u, func(_c): pass)
	var words := " ".join(_texts(peek))
	check(words.contains("Troll") and words.contains("Level 4"), "class and level: %s" % words)
	check(words.contains("Front: %s" % d.units["Troll"]["front_attack"]), "the attack from its row")
	check(words.contains("About the Troll"), "a glossary link")
	check(not words.contains("HP") and not words.contains("7"), "no HP numbers")
	for s in Unit.STATS:
		check(not words.contains(s), "no %s" % s)
	check(not peek.find_children("*", "ProgressBar", true, false).is_empty(), "an HP bar")
	peek.free()
	u.row = "back"
	peek = UnitPeek.make(d, u, func(_c): pass)
	check(" ".join(_texts(peek)).contains("Back: %s" % d.units["Troll"]["back_attack"]), "moved back, its back-row attack")
	peek.free()
