extends TestCase
## Hidden sites (SPEC §6.5, ROADMAP M4 session 22): seeing reveals, stepping on claims.
## Treasure, card caches and rare recruits are one-time; secret temples are temples;
## a lair is guarded, then shelters.

var d := GameData.load_dir()
const KINDS := ["treasure", "card", "secret_temple", "rare_recruit", "lair"]


## A plains strip, the bases at either end, one site of each kind along row 4 at
## columns 10, 14, 18, 22 and 26.
func _state() -> GameState:
	var m := MapData.new(40, 9)
	for i in m.size():
		m.terrain[i] = d.terrain_ids["plains"]
	m.seed = 4
	m.settings = {"preset": "continent", "size": "small"}
	m.player_base = _at(m, 1, 4)
	m.enemy_base = _at(m, 38, 4)
	for k in KINDS.size():
		m.buildings.append({"type": "hidden_site", "hex": _at(m, 10 + 4 * k, 4), "shop": false, "hint": false, "hidden": true, "kind": KINDS[k], "road": false})
	return GameState.new(d, m, GameLog.new())


func _at(m: MapData, col: int, row: int) -> int:
	return m.index_of(Hex.from_offset(Vector2i(col, row)))


func _site(st: GameState, kind: String) -> Dictionary:
	return st.map.buildings[KINDS.find(kind)]


func _ours(st: GameState, col: int) -> Squad:
	var s := st.add_squad("Ours", _at(st.map, col, 4), [["Knight", "front"], ["Fighter", "front"], ["Bowman", "back"]])
	st.army.cells[0] = s
	return s


func test_seeing_a_site_reveals_it_without_a_reward() -> void:
	var st := _state()
	var s := _ours(st, 7)
	var cards := st.cards.size()
	var gold := st.gold
	st.step()
	check(st.revealed.has(KINDS.find("treasure")), "the treasure 3 hexes away is seen")
	check_eq([st.cards.size(), st.gold], [cards, gold], "seeing it gives nothing")
	check(not _site(st, "treasure").get("claimed", false), "not claimed from afar")
	check(s.hex != _site(st, "treasure")["hex"], "the squad never stepped on it")


func test_treasure_pays_once_and_leaves() -> void:
	var st := _state()
	var site := _site(st, "treasure")
	_ours(st, 10)
	var gold := st.gold
	st.step()
	var info: Dictionary = d.buildings["hidden_site"]["kind_info"]["treasure"]
	check(st.gold - gold >= int(info["gold"][0]) and st.gold - gold <= int(info["gold"][1]), "gold in range: %d" % (st.gold - gold))
	check(site["claimed"], "claimed")
	check(st.building_at(site["hex"]).is_empty(), "and gone from the map")
	var after := st.gold
	st.step()
	check_eq(st.gold, after, "it pays only once")


func test_a_card_cache_draws_a_card() -> void:
	var st := _state()
	_ours(st, 14)
	var cards := st.cards.size()
	st.step()
	check_eq(st.cards.size(), cards + 1, "a card drawn")
	check(st.building_at(_site(st, "card")["hex"]).is_empty(), "the cache is gone")


func test_a_rare_recruit_joins_the_pool() -> void:
	var st := _state()
	_ours(st, 22)
	st.step()
	check_eq(st.army.pool.size(), 1, "one recruit in the pool")
	var u: Unit = st.army.pool[0]
	var serf_classes := []
	for lid in d.lines:
		if String(lid).is_valid_int():
			for stage in d.lines[lid]:
				serf_classes += stage
	check(u.unit_class not in serf_classes, "from a race line, not a Serf line: %s" % u.unit_class)
	check_eq(int(d.units[u.unit_class]["stage"]), 1, "stage 1 (%s)" % u.unit_class)
	check(u.recruited, "counts as a recruit (loyalty)")
	check(st.building_at(_site(st, "rare_recruit")["hex"]).is_empty(), "the site is gone")


func test_a_secret_temple_is_a_temple() -> void:
	var st := _state()
	var site := _site(st, "secret_temple")
	check_eq(site["type"], "temple", "a temple from the start")
	check(st.building_at(site["hex"]).is_empty(), "but hidden until seen")
	var s := _ours(st, 18)
	st.step()
	check(not st.building_at(site["hex"]).is_empty(), "it stays after a squad steps on it")
	check(st.can_service(s.units[0]), "temple services work there")
	check_eq(st.site_name(site), "Secret temple", "named for what it is")


func test_a_lair_is_guarded_then_shelters() -> void:
	var st := _state()
	st.place_neutrals()
	var site := _site(st, "lair")
	var guard := st.guard_of(site)
	check(guard != null, "a guard waits on the lair")
	check_eq([guard.side, guard.role, guard.hex], ["neutral", "guard", site["hex"]], "a neutral holding the site")
	for i in 50:
		st.step()
	check_eq(guard.hex, site["hex"], "the guard holds its ground")
	var s := _ours(st, 25)
	st.step()
	check(not st.pending_recruit.is_empty() and st.pending_recruit["neutral"] == guard, "meeting it offers Recruit or Fight")
	check_eq(st.building_effect(site, s), [0.0, 0.0], "no shelter while guarded")
	st.pending_recruit = {}
	st.squads.erase(guard)  # recruited or met in battle: it leaves the map
	var lair: Dictionary = d.buildings["hidden_site"]["kind_info"]["lair"]
	check_eq(st.building_effect(site, s), [float(lair["defense"]), float(lair["rest"])], "then any squad there is sheltered")


func test_town_hints_point_at_unseen_secret_temples_too() -> void:
	var st := _state()
	var town := {"type": "town", "hex": _at(st.map, 18, 1), "hint": true}
	check(st.hint(town) != "", "a hint finds the nearest unseen site, whatever its kind")
