extends TestCase
## Which row Edit Units puts a unit in (user, 2026-11-12): back when its ranged or magic
## attack there reaches at least as many units as its front attack, counting a row-wide
## hit as 3, a chain or cleave as its number, a pierce as 2.

var d := GameData.load_dir()


func _row(cls: String) -> String:
	var u := Unit.new()
	u.unit_class = cls
	return EditUnits.preferred_row(d, u)


func test_rows_by_units_reached() -> void:
	check_eq(_row("Sapper"), "front", "Sapper: 3 melee hits beat 1 shot")
	check_eq(_row("Ranger"), "front", "Ranger: 3 melee hits beat 2 shots")
	check_eq(_row("Siege Engineer"), "back", "Siege Engineer: one row-wide shot (3) ties 3 melee hits")
	check_eq(_row("Sphinx"), "back", "Sphinx: a row spell (3) beats 2 melee hits")
	check_eq(_row("Electro Kraken"), "back", "Electro Kraken: a chain of 3 ties 3 melee hits")
	check_eq(_row("Earthshaker"), "back", "Earthshaker: 2 row spells (6) tie 3 piercing hits (6)")
	check_eq(_row("Battle Buffalo"), "front", "Battle Buffalo: 3 piercing hits (6) beat 1 row spell (3)")
	check_eq(_row("Battle Octopus"), "front", "Battle Octopus: 3 cleaves (6) beat 1 spell")


func test_units_reached() -> void:
	check_eq(EditUnits.targets_hit(d, "Magic (row)", 2), 6, "a row counts as 3")
	check_eq(EditUnits.targets_hit(d, "Magic (chain 3)", 1), 3, "a chain its number")
	check_eq(EditUnits.targets_hit(d, "Melee (cleave 2)", 3), 6, "a cleave its number")
	check_eq(EditUnits.targets_hit(d, "Melee (any row)", 2), 2, "any row is one target a hit")
	check_eq(EditUnits.targets_hit(d, "Ranged", 1), 1, "a plain shot is one")
