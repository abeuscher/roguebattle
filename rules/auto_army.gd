class_name AutoArmy
extends RefCounted
## "Auto pick army" (playtest round 16; user, 2026-11-15): sorts the recruit pool into
## squads as a starting point the player can change. Up to `count` squads, the Opinion
## Leader's first (army cell 0):
## - Leaders: those native to a terrain other than Plains with a Large unit of the same
##   terrain in the pool come first, each with that monster, so the squad's travel vote
##   (leader 2 + Large 2 against the rest) goes their way; then the strongest (stage,
##   level). Spare leaders stay in the pool.
## - A monster for each squad still without one, while they last.
## - A healer or support unit for each squad without one, then a front-line unit for each
##   squad without one, spread round the squads.
## - The rest fill the emptiest squad first, each taking the row it's short of, a class it
##   doesn't have yet, and no second healer while others are left; Serfs only if room is left. Rows by role, then balanced (Squad.balance_rows).


static func pick(data: GameData, army: Army, count: int) -> void:
	var first: Squad = army.cells[0]
	army.move(first.leader, 0, _row(data, first.leader))  # the Opinion Leader starts front: to its role's row
	var free: Array = army.pool.duplicate()
	var larges := free.filter(func(u: Unit): return u.info(data)["size"] == "Large" and not u.info(data)["can_lead"])
	var leaders := free.filter(func(u: Unit): return u.info(data)["can_lead"])
	leaders.sort_custom(func(a: Unit, b: Unit): return _rank(a, data) > _rank(b, data))
	var cells := [0]
	var mates := {}  # cell -> the monster matched to its leader
	var mine := _monster(data, first.leader, larges)
	if mine:
		mates[0] = mine
	var heads := []
	for pass_ in 2:
		for u: Unit in leaders:
			if cells.size() + heads.size() >= count or u in heads:
				continue
			if pass_ == 0:
				if u.info(data)["terrain"] == "Plains":
					continue
				var m := _monster(data, u, larges)
				if m == null:
					continue
				mates[cells.size() + heads.size()] = m
			heads.append(u)
	for u: Unit in heads:
		var cell := army.cells.find(null)
		if cell < 0:
			break
		army.move(u, cell, _row(data, u))
		cells.append(cell)
	var squads := cells.map(func(c: int): return army.cells[c])
	for i in squads.size():
		if mates.has(i):
			_add(data, army, squads[i], mates[i])
	for s: Squad in squads:
		if larges.is_empty():
			break
		if not s.units.any(func(u: Unit): return u.info(data)["size"] == "Large"):
			_add(data, army, s, larges.pop_front())
	var rest := army.pool.filter(func(u: Unit): return not u.info(data)["can_lead"] and u.info(data)["size"] != "Large" and u.unit_class != "Serf")
	var needs := [func(u: Unit): return Map1Setup._is_healer_or_support(data, u.unit_class),
			func(u: Unit): return Map1Setup._is_front_line(data, u.unit_class)]
	for need: Callable in needs:
		for s: Squad in squads:
			if s.units.any(need):
				continue
			for u: Unit in rest:
				if need.call(u) and s.can_add(data, u):
					_add(data, army, s, u)
					rest.erase(u)
					break
	_fill(data, army, squads, rest)
	_fill(data, army, squads, army.pool.filter(func(u: Unit): return u.unit_class == "Serf"))
	for s: Squad in squads:
		s.balance_rows(data)


## Puts units into the squad with the most room left, each time the unit of the row that
## squad is shortest of, until no squad has room or no unit is left.
static func _fill(data: GameData, army: Army, squads: Array, units: Array) -> void:
	while not units.is_empty():
		var best: Squad = null
		var room := 0.0
		for s: Squad in squads:
			var r := s.capacity(data) - Squad.slots_filled(data, s.units)
			if r > room and units.any(func(u: Unit): return s.can_add(data, u)):
				best = s
				room = r
		if best == null:
			return
		var want := "front" if best.row("front").size() <= best.row("back").size() else "back"
		var healed := best.units.any(func(u: Unit): return Map1Setup._is_healer_or_support(data, u.unit_class))
		var pick: Unit = null
		var low := INF
		for u: Unit in units:  # the row it's short of, a class it lacks, no second healer while others are left
			if not best.can_add(data, u):
				continue
			var cost := (0.0 if _row(data, u) == want else 10.0) + 3.0 * best.units.filter(func(o: Unit): return o.unit_class == u.unit_class).size() 					+ (5.0 if healed and Map1Setup._is_healer_or_support(data, u.unit_class) else 0.0)
			if cost < low:
				pick = u
				low = cost
		_add(data, army, best, pick)
		units.erase(pick)


static func _add(data: GameData, army: Army, s: Squad, u: Unit) -> void:
	army.move(u, s.id - 1, _row(data, u))


## A Large unit native to the leader's terrain (not Plains), taken from `larges`; null if none.
static func _monster(data: GameData, leader: Unit, larges: Array) -> Unit:
	var t: String = leader.info(data)["terrain"]
	if t == "Plains":
		return null
	for m: Unit in larges:
		if m.info(data)["terrain"] == t:
			larges.erase(m)
			return m
	return null


static func _rank(u: Unit, data: GameData) -> int:
	return int(u.info(data)["stage"]) * 100 + u.level


static func _row(data: GameData, u: Unit) -> String:
	return Map1Setup._row(data, u.unit_class)
