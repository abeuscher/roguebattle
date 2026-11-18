extends TestCase
## More weapons (user, 2026-11-18): staffs for spellcasters, the better ones casting a spell
## from the front row only; the Crossbow, the Katana, and Metal Claws for beasts with claws.

var d := GameData.load_dir()
var rng := RandomNumberGenerator.new()
var names := NameBook.new(d)


func _unit(c: String, row := "front") -> Unit:
	var u := Unit.roll(d, c, rng, names)
	u.row = row
	return u


func test_who_can_use_what() -> void:
	var mage := _unit("Mage")
	var knight := _unit("Knight")
	var bowman := _unit("Bowman")
	var lion := _unit("Lion")
	var goat := _unit("Goat")
	check(mage.can_use(d, "staff") and mage.can_use(d, "rune_staff") and mage.can_use(d, "storm_staff"), "a spellcaster takes staffs")
	check(not knight.can_use(d, "staff") and not _unit("Cleric").can_use(d, "staff"), "not a fighter or a healer with no Magic attack")
	check(bowman.can_use(d, "crossbow") and not knight.can_use(d, "crossbow"), "a crossbow is an archer's")
	check(knight.can_use(d, "katana") and not mage.can_use(d, "katana"), "a katana needs a melee attack")
	check(lion.can_use(d, "claws") and not goat.can_use(d, "claws") and not knight.can_use(d, "claws"), "Metal Claws only on a beast with claws")


func test_a_rune_staff_casts_from_the_front_row_only() -> void:
	var gnome := _unit("Gnome")
	var army := Army.new(d)
	army.items.clear()
	check_eq(gnome.attack(d, "front"), "Melee", "without a staff it swings in front")
	army.equip(gnome, army.add_item("staff"))
	check_eq(gnome.attack(d, "front"), "Melee", "a plain staff casts nothing")
	army.equip(gnome, army.add_item("rune_staff"))
	check_eq(gnome.attack(d, "front"), "Magic", "a Rune Staff casts in the front row")
	check_eq(gnome.attack(d, "back"), "Magic", "and the back row is its own spell as before")
	var knight := _unit("Knight")
	var a := Squad.new(1, "Ours", 0)
	a.add(d, gnome, "front")
	var e := Squad.new(2, "Theirs", 1)
	e.add(d, knight, "front")
	var b := Battle.new(d, a, e, "plains", true, rng)
	check_eq(b.attack_kind(gnome), "Magic", "the battle uses it")
	gnome.row = "back"
	check_eq(b.attack_kind(gnome), str(gnome.info(d)["back_attack"]), "in the back row, just its stats")


func test_beasts_wear_claws_or_nothing() -> void:
	var lion := _unit("Lion")
	check(not lion.can_use(d, "sword") and not lion.can_use(d, "katana") and not lion.can_use(d, "dagger"), "no swords on a lion")
	check(lion.can_use(d, "bronze") and lion.can_use(d, "ring"), "armor and jewelry as before")
	for c in ["Gryphon", "Roc", "Red Dragon", "Drakeling", "Wolf"]:
		check(_unit(c).can_use(d, "claws") and not _unit(c).can_use(d, "sword"), "%s: claws, no sword" % c)
	check(not _unit("Serpent").can_use(d, "claws"), "a serpent has no claws")
	check(not _unit("Rat").can_use(d, "sword") and not _unit("Rat").can_use(d, "claws"), "a rat wears no weapon")
	check(_unit("Knight").can_use(d, "sword"), "people still use swords")
