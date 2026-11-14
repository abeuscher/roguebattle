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



## Any unit can change rows inside its squad (playtest round 13): moving the leader, or
## swapping with it, keeps it the leader, so the squad keeps the slots it earned.
func test_the_leader_changes_rows_and_stays_leader() -> void:
	var a := _army([["Knight", "front"], ["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"], ["Bowman", "back"]])
	var s: Squad = a.cells[0]
	var lead := s.leader
	var other: Unit = s.units[1]
	other.level = lead.level + 3  # a likelier leader by rank, but not the one leading
	lead.extra_slots = 1
	check(a.move(_unit("Acolyte"), 0, "back"), "the slot the leader earned holds a sixth unit")
	check(a.move(lead, 0, "back", 3), "the leader moves to the back row")
	check(s.leader == lead and lead.row == "back", "and still leads")
	check(a.move(lead, 0, "front", 1), "it swaps with a squadmate in front")
	check(s.leader == lead and lead.row == "front", "and still leads")
	check(a.move(other, 0, "back", 0), "another unit swaps onto a back-row spot")
	check(a.move(s.at("front", 2), 0, "front", 1), "a squadmate swaps onto the leader's spot")
	check(s.leader == lead, "the leader is still the leader")
	check_eq(s.units.size(), 6, "nobody is lost")


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
	check(not a.move(herald, 9), "a unit that can't lead can't start a squad")
	check_eq(a.refusal, "leader", "refused for want of a leader")
	check(a.cells[9] == null and herald in a.pool, "nothing changed")
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
	check_eq(st.army.items.size(), 6, "a starting kit of 6 items")
	check(st.army.items.all(func(it): return not d.items["items"][it["id"]].has("requires")), "none of them needs tech")
	check_eq(int(st.army.supplies.get("revive", 0)), 5, "5 Revival Draughts")
	check_eq(int(st.army.supplies.get("herb", 0)), 20, "20 Herbs")
	var first := st.player_squads()[0]
	check(st.can_edit(first), "a squad on the Player Base can be edited")
	check(st.can_edit(st.army.cells[1]), "so can one waiting at base")
	first.hex = m.index_of(Hex.from_offset(Vector2i(6, 2)))
	check(not st.can_edit(first), "not one out in the field")
	var u0 := first.units[0]
	check(st.can_rearrange(u0, first), "in the field its formation can still change")
	check(not st.can_rearrange(u0, null), "but no unit leaves it for the pool")
	check(not st.can_rearrange(u0, st.army.cells[1]), "or for another squad")
	check(not st.can_rearrange(st.army.cells[1].units[0], first), "and no unit joins it")
	var cell := st.army.cells.find(first)
	var to_row := "back" if u0.row == "front" else "front"
	check(st.army.move(u0, cell, to_row, first.next_col(to_row)), "moved to the other row")
	check_eq(u0.row, to_row, "the move took")
	check_eq(st.deploy_menu_blocker(), "", "Deploy Squad is on: squads wait at base, under the cap")
	st.settings["squad_cap"] = 1
	check(st.deploy_menu_blocker().contains("cap"), "off at the squad cap")
	st.settings["squad_cap"] = 10
	for s in st.army.squads():
		if s not in st.squads:
			st.squads.append(s)
	check(st.deploy_menu_blocker().contains("No squads"), "off with no squad waiting at base")
	for s in st.army.squads():
		if s != first:
			st.squads.erase(s)
	first.hex = m.player_base
	var order := first.units.duplicate()
	order.sort_custom(func(x: Unit, y: Unit): return not x.info(d)["can_lead"] and y.info(d)["can_lead"])  # leaders leave last
	for u in order:
		st.army.move(u, -1)
	st.after_edit()
	check(st.player_squads().is_empty(), "a squad emptied at base leaves the map")


func test_a_squad_always_keeps_someone_who_can_lead() -> void:
	var a := _army([["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]], ["Fighter", "Soldier"])
	var s: Squad = a.cells[0]
	var knight := s.leader
	check(not a.move(knight, -1), "the only leader can't leave a squad with others in it")
	check_eq(a.refusal, "leader", "for want of a leader")
	check(knight in s.units and s.leader == knight, "nothing changed")
	var spare: Unit = a.pool.filter(func(u: Unit): return u.unit_class == "Fighter")[0]
	check(not a.move(spare, 0, knight.row, knight.col), "nor can a Fighter swap in for the leader")
	var soldier: Unit = a.pool.filter(func(u: Unit): return u.unit_class == "Soldier")[0]
	check(a.move(soldier, 0, "back"), "another leader joins")
	check(a.move(knight, -1), "now the Knight can go")
	check_eq(s.leader, soldier, "and the Soldier leads")
	check(a.move(knight, 3), "a leader from the pool starts a squad in an empty cell")
	check_eq(a.refusal, "", "no refusal after a move that took")


func test_pool_sort_orders() -> void:
	var a := _army([["Knight", "front"]], ["Serf", "Fighter", "Soldier", "Acolyte"])
	a.pool[1].level = 4
	var classes := func(by: String) -> Array: return a.sorted_pool(by).map(func(u: Unit): return u.unit_class)
	check_eq(classes.call("leader")[0], "Soldier", "leaders first")
	check_eq(classes.call("class"), ["Acolyte", "Fighter", "Serf", "Soldier"], "by class")
	check_eq(classes.call("level")[0], "Fighter", "highest level first")
	var names: Array = a.sorted_pool("name").map(func(u: Unit): return u.name)
	var expected := names.duplicate()
	expected.sort()
	check_eq(names, expected, "by name")
	check_eq(a.pool.size(), 4, "sorting leaves the pool itself alone")
