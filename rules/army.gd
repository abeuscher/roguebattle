class_name Army
extends RefCounted
## The player's army (SPEC §4 Edit Units, §8.2): up to 16 squads in a numbered grid,
## the unassigned recruit pool and the item stash. A squad's number is its cell + 1.
## Moves never put a squad over its slots; a squad that loses its leader takes the
## best unit left that can lead.

var data: GameData
var cells: Array = []  # Squad or null per grid cell
var pool: Array[Unit] = []
var stash := {}  # item id -> count


func _init(game_data: GameData) -> void:
	data = game_data
	cells.resize(int(data.rules["army_size"]))


func squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for s in cells:
		if s:
			out.append(s)
	return out


func squad_of(u: Unit) -> Squad:
	for s in squads():
		if u in s.units:
			return s
	return null


## Moves u into the squad in `cell` (-1 = the pool) at a row and position (-1 = the
## first free one). A unit already standing there swaps into u's old place. An empty
## cell forms a new squad. Returns false, changing nothing, if a squad would go over
## its slots.
func move(u: Unit, cell: int, to_row := "front", to_col := -1) -> bool:
	var from := squad_of(u)
	var to: Squad = cells[cell] if cell >= 0 else null
	if cell >= 0 and to == null:
		to = Squad.new(cell + 1, "Squad %d" % (cell + 1), -1)
	if to == null and from == null:
		return true
	var other: Unit = to.at(to_row, to_col) if to and to_col >= 0 else null
	if other == u:
		return true
	var snap := _snapshot([from, to], [u, other])
	var old_row := u.row
	var old_col := u.col
	_take(from, u)
	if other:
		_take(to, other)
		_put(from, other, old_row, old_col)
	if to:
		_put(to, u, to_row, to_col if to_col >= 0 else _free_col(to, to_row))
	for s in [from, to]:
		if s and not _fits(s):
			_restore(snap)
			return false
	if to and cells[cell] == null:
		cells[cell] = to
	for s in [from, to]:
		if s and s.units.is_empty():
			cells[s.id - 1] = null
	return true


## Makes u its squad's leader, if it can lead and the squad still fits its slots.
func set_leader(u: Unit) -> bool:
	var s := squad_of(u)
	if s == null or not u.info(data)["can_lead"]:
		return false
	var old := s.leader
	s.leader = u
	if not _fits(s):
		s.leader = old
		return false
	s.refresh(data)
	return true


## Equips an item from the stash ("" takes the slot's item off). The old item goes back
## to the stash. Extra HP from an item heals the unit by that much; losing it caps HP.
func equip(u: Unit, slot: String, item_id: String) -> bool:
	if item_id != "":
		var item: Dictionary = data.items["items"][item_id]
		if item["slot"] != slot or int(stash.get(item_id, 0)) <= 0 or not u.can_use(data, item_id):
			return false
	var before := u.max_hp(data)
	if u.items.has(slot):
		stash[u.items[slot]] = int(stash.get(u.items[slot], 0)) + 1
		u.items.erase(slot)
	if item_id != "":
		stash[item_id] = int(stash[item_id]) - 1
		u.items[slot] = item_id
	if u.is_alive():
		u.hp = clampi(u.hp + maxi(0, u.max_hp(data) - before), 1, u.max_hp(data))
	return true


## Items in the stash that fit this unit's slot.
func choices(u: Unit, slot: String) -> Array[String]:
	var out: Array[String] = []
	for id in stash:
		if int(stash[id]) > 0 and data.items["items"][id]["slot"] == slot and u.can_use(data, id):
			out.append(id)
	return out


# --- Helpers --------------------------------------------------------------------------

func _take(s: Squad, u: Unit) -> void:
	if s == null:
		pool.erase(u)
		return
	s.units.erase(u)
	if s.leader == u:
		s.leader = null


func _put(s: Squad, u: Unit, r: String, c: int) -> void:
	if s == null:
		pool.append(u)
		return
	u.row = r
	u.col = c
	s.units.append(u)
	if s.leader == null:
		s.leader = _best_leader(s)
	s.refresh(data)


## The highest-level unit that can lead, living units first.
func _best_leader(s: Squad) -> Unit:
	var best: Unit = null
	for u in s.units:
		if not u.info(data)["can_lead"]:
			continue
		if best == null or _rank(u) > _rank(best):
			best = u
	return best


func _rank(u: Unit) -> int:
	return (1000 if u.is_alive() else 0) + u.level * 10 + int(u.info(data)["stage"])


func _free_col(s: Squad, r: String) -> int:
	var c := 0
	while s.at(r, c):
		c += 1
	return c


func _fits(s: Squad) -> bool:
	if s.leader == null or s.leader not in s.units:
		s.leader = _best_leader(s)
	return Squad.slots_filled(data, s.units) <= s.capacity(data)


func _snapshot(sq: Array, us: Array) -> Dictionary:
	var snap := {"pool": pool.duplicate(), "squads": [], "units": []}
	for s in sq:
		if s:
			snap["squads"].append([s, s.units.duplicate(), s.leader])
	for u in us:
		if u:
			snap["units"].append([u, u.row, u.col])
	return snap


func _restore(snap: Dictionary) -> void:
	pool.assign(snap["pool"])
	for e in snap["squads"]:
		e[0].units.assign(e[1])
		e[0].leader = e[2]
		e[0].refresh(data)
	for e in snap["units"]:
		e[0].row = e[1]
		e[0].col = e[2]
