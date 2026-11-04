extends TestCase
## The army, recruit pool and items (SPEC §4 Edit Units, §8.1–8.2, §15.2).

var d := GameData.load_dir()
var rng := RandomNumberGenerator.new()
var names := NameBook.new(d)


func _unit(c: String) -> Unit:
	return Unit.roll(d, c, rng, names)


## An army with one squad in cell 0 built from [class, row] pairs, and a pool.
func _army(members: Array, pool := []) -> Army:
	var a := Army.new(d)
	var s := Squad.new(1, "One", -1)
	for m in members:
		s.add(d, _unit(m[0]), m[1])
	a.cells[0] = s
	for c in pool:
		a.pool.append(_unit(c))
	return a


func test_pool_to_squad_respects_slots() -> void:
	var a := _army([["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"], ["Bowman", "back"]], ["Fighter", "Bowman", "Wolfhound"])
	var s: Squad = a.cells[0]
	var wolf := a.pool[2]
	check(not a.move(wolf, 0), "a Large unit doesn't fit in the last free slot")
	check(wolf in a.pool and s.units.size() == 4, "a refused move changes nothing")
	var f := a.pool[0]
	check(a.move(f, 0, "back"), "a Small unit fills the fifth slot")
	check(f in s.units and f not in a.pool, "it leaves the pool")
	check_eq(f.row, "back", "in the chosen row")
	check_eq(f.col, 1, "at the first free position")
	check(not a.move(a.pool[0], 0), "the squad is full")


func test_swap_when_full() -> void:
	var a := _army([["Knight", "front"], ["Fighter", "front"], ["Fighter", "front"], ["Bowman", "back"], ["Acolyte", "back"]], ["Squire"])
	var s: Squad = a.cells[0]
	var squire := a.pool[0]
	var bowman := s.at("back", 0)
	check(a.move(squire, 0, "back", 0), "dropping onto a unit in a full squad swaps them")
	check(squire in s.units and bowman in a.pool, "the displaced unit goes to the pool")
	check_eq([squire.row, squire.col], ["back", 0], "the newcomer takes its place")


func test_rows_and_positions_within_a_squad() -> void:
	var a := _army([["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]])
	var s: Squad = a.cells[0]
	var fighter := s.at("front", 1)
	var bowman := s.at("back", 0)
	check(a.move(fighter, 0, "back", 0), "moving onto a squadmate swaps their places")
	check_eq([fighter.row, fighter.col], ["back", 0], "the mover takes the spot")
	check_eq([bowman.row, bowman.col], ["front", 1], "the other takes the mover's old spot")
	check(a.move(bowman, 0, "back", 3), "a free spot further along is fine")
	check_eq(s.units.size(), 3, "nobody is lost")


func test_new_squad_and_leaders() -> void:
	var a := _army([["Knight", "front"], ["Fighter", "front"], ["Soldier", "front"]], ["Lancer"])
	var s: Squad = a.cells[0]
	var knight := s.leader
	check_eq(knight.unit_class, "Knight", "the first unit that can lead leads")
	var lancer := a.pool[0]
	check(a.move(lancer, 5), "dropping into an empty cell forms a squad")
	var formed: Squad = a.cells[5]
	check(formed != null and formed.id == 6, "numbered by its cell")
	check_eq(formed.leader, lancer, "and the unit leads it")
	check(a.move(knight, -1), "the leader can go to the pool")
	check(knight in a.pool and knight not in s.units, "and is in the pool")
	check_eq(s.leader.unit_class, "Soldier", "the next unit that can lead takes over")
	check_eq(s.name, "%s (Soldier)" % s.leader.name.get_slice(" ", 0), "the squad is named after its leader")
	check(a.move(a.pool[0], 7), "a Knight alone forms a squad")
	var herald := _unit("Herald")
	a.pool.append(herald)
	check(a.move(herald, 9), "so does a unit that can't lead")
	check_eq(a.cells[9].name, "Squad 10", "a squad without a leader goes by its number")
	check(a.set_leader(s.at("front", 1)) == false, "a Fighter can't lead")
	check(a.move(lancer, -1), "the last unit leaves")
	check(a.cells[5] == null, "an emptied squad leaves the grid")


func test_items() -> void:
	var a := _army([["Knight", "front"], ["Bowman", "back"], ["Apprentice", "back"]])
	var sword := a.add_item("sword")
	var bow := a.add_item("bow")
	var sword2 := a.add_item("sword")
	var necklace := a.add_item("necklace")
	check(sword != sword2, "each item is its own entry")
	var s: Squad = a.cells[0]
	var knight := s.leader
	var bowman := s.at("back", 0)
	var mage := s.at("back", 1)
	check(a.fits(knight, sword) and not a.fits(knight, bow), "a Knight takes melee weapons, not bows")
	check(a.fits(bowman, bow), "archers take bows")
	check(not a.equip(mage, sword), "an Apprentice has no melee attack for a sword")
	var str_before := knight.stat(d, "STR")
	check(a.equip(knight, sword), "equip a sword")
	check_eq(knight.stat(d, "STR"), str_before + 2, "the sword adds STR")
	check_eq(a.holder(sword), knight, "the inventory knows who wears it")
	check(a.holder(sword2) == null, "the other sword is still free")
	check(a.equip(knight, sword2), "a second sword replaces the first")
	check(a.holder(sword) == null and a.holder(sword2) == knight, "the first goes back to the inventory")
	check_eq(a.items.size(), 4, "nothing is lost")
	var hp := knight.max_hp(d)
	check(a.equip(knight, necklace), "equip a necklace")
	check_eq(knight.max_hp(d), hp + 2 * int(d.rules["hp_per_con"]), "+2 CON raises max HP")
	check_eq(knight.hp, knight.max_hp(d), "and heals the gain")
	check(a.equip(bowman, necklace), "moving it to another unit")
	check(a.holder(necklace) == bowman and not knight.items.has("jewelry"), "takes it off the first")
	check(knight.hp <= knight.max_hp(d), "HP is capped again")
	a.unequip(bowman, "jewelry")
	check(a.holder(necklace) == null, "unequipped items are free again")
	var b := Battle.new(d, s, Squad.new(2, "X", -1), "plains", true, rng)
	check_eq(b.stat(knight, "STR"), float(knight.stat(d, "STR")), "battle uses item bonuses")


func test_state_army_and_editing() -> void:
	var m := MapData.new(20, 5)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 4
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = m.index_of(Hex.from_offset(Vector2i(2, 2)))
	m.enemy_base = m.index_of(Hex.from_offset(Vector2i(18, 2)))
	var st := GameState.new(d, m, GameLog.new())
	st.setup_army()
	check_eq(st.army.squads().size(), 6, "the 6 Map 1 squads (§18)")
	check_eq(st.player_squads().size(), 1, "only the first squad starts on the map (§8.4)")
	check(st.army.pool.is_empty(), "no starting recruit pool")
	var first := st.player_squads()[0]
	check(st.can_edit(first), "a squad on the Player Base can be edited")
	check(st.can_edit(st.army.cells[1]), "so can one waiting at base")
	first.hex = m.index_of(Hex.from_offset(Vector2i(6, 2)))
	check(not st.can_edit(first), "not one out in the field")
	first.hex = m.player_base
	for u in first.units.duplicate():
		st.army.move(u, -1)
	st.after_edit()
	check(st.player_squads().is_empty(), "a squad emptied at base leaves the map")
