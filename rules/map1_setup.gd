class_name Map1Setup
extends RefCounted
## Map 1's starting squads (SPEC §18): 6 Serf-line squads, each a stage 3 leader plus
## four stage 2 units, terrain coverage across the 6, and a soft rule (a front-line
## unit and a healer or support unit per squad). Classes come from data/lines.json
## and data/units.json, never hard-coded here.
##
## Coverage is checked against each squad's leader, not its actual (voted) travel
## type: every Serf-line stage 2 class is Plains, so the §8.3 vote always gives a
## Serf-line squad a Plains travel type regardless of its leader. See DECISIONS.md.

const TERRAINS: Array[String] = ["Plains", "Forest", "Swamp", "Mountain", "Desert"]


## Six squads as [class, row] member lists (leader first), position 0 being the
## Opinion Leader's squad (SPEC §8.4, §18; GameState.opinion_leader_squad()).
static func build(data: GameData, rng: RandomNumberGenerator) -> Array:
	var stage2 := _stage2_classes(data)
	var front_stage2 := stage2.filter(func(c): return _is_front_line(data, c))
	var healer_stage2 := stage2.filter(func(c): return _is_healer_or_support(data, c))
	var by_terrain := _leaders_by_terrain(data)
	var terrains := TERRAINS.duplicate()
	_shuffle(terrains, rng)
	var squads := []
	for t in terrains:
		var options: Array = by_terrain[t]
		squads.append(_build_squad(data, options[rng.randi() % options.size()], stage2, front_stage2, healer_stage2, rng))
	var all_leaders: Array = by_terrain.values().reduce(func(a, b): return a + b, [])
	squads.append(_build_squad(data, all_leaders[rng.randi() % all_leaders.size()], stage2, front_stage2, healer_stage2, rng))
	_shuffle(squads, rng)
	return squads


## A leader and four stage 2 units: the soft rule's minimum forced, the rest random.
static func _build_squad(data: GameData, leader_class: String, stage2: Array, front_stage2: Array,
		healer_stage2: Array, rng: RandomNumberGenerator) -> Array:
	var members := [[leader_class, _row(data, leader_class)]]
	var picks := []
	if not _is_front_line(data, leader_class):
		picks.append(front_stage2[rng.randi() % front_stage2.size()])
	if not _is_healer_or_support(data, leader_class):
		picks.append(healer_stage2[rng.randi() % healer_stage2.size()])
	while picks.size() < 4:
		picks.append(stage2[rng.randi() % stage2.size()])
	for c in picks:
		members.append([c, _row(data, c)])
	return members


static func _serf_line_ids(data: GameData) -> Array:
	return data.lines.keys().filter(func(k: String): return k.is_valid_int())


## The distinct stage 2 classes across every Serf line.
static func _stage2_classes(data: GameData) -> Array:
	var out := []
	for lid in _serf_line_ids(data):
		for c in data.lines[lid][1]:
			if c not in out:
				out.append(c)
	return out


## Serf-line stage 3 classes that can actually lead (Herald can't, §8.2's banner
## bonus is its whole role), grouped by native terrain.
static func _leaders_by_terrain(data: GameData) -> Dictionary:
	var out := {}
	for lid in _serf_line_ids(data):
		for c in data.lines[lid][2]:
			if not data.units[c]["can_lead"]:
				continue
			var t: String = data.units[c]["terrain"]
			if not out.has(t):
				out[t] = []
			if c not in out[t]:
				out[t].append(c)
	return out


static func _row(data: GameData, class_name_: String) -> String:
	return "front" if _is_front_line(data, class_name_) else "back"


static func _is_front_line(data: GameData, class_name_: String) -> bool:
	var role: String = data.units[class_name_]["role"]
	return data.role_templates[role]["primary_row"] == "front"


static func _is_healer_or_support(data: GameData, class_name_: String) -> bool:
	var role: String = data.units[class_name_]["role"]
	return role == "Support" or role.to_lower().contains("healer")


## Debug only: as many distinct Serf-line leaders as fit in `count` (one squad
## each, still terrain-covering and soft-rule-compliant), for exercising more of
## the unit roster in playtests. Not part of the real game; see the --wide-roster
## check in Battlemap.start().
static func build_wide_roster(data: GameData, rng: RandomNumberGenerator, count: int) -> Array:
	var stage2 := _stage2_classes(data)
	var front_stage2 := stage2.filter(func(c): return _is_front_line(data, c))
	var healer_stage2 := stage2.filter(func(c): return _is_healer_or_support(data, c))
	var by_terrain := _leaders_by_terrain(data)
	var terrains := TERRAINS.duplicate()
	_shuffle(terrains, rng)
	var leaders := []
	for t in terrains:
		var options: Array = by_terrain[t]
		leaders.append(options[rng.randi() % options.size()])
	var rest: Array = by_terrain.values().reduce(func(a, b): return a + b, []).filter(func(c): return c not in leaders)
	_shuffle(rest, rng)
	leaders.append_array(rest.slice(0, maxi(0, count - leaders.size())))
	var squads := []
	for leader_class in leaders.slice(0, count):
		squads.append(_build_squad(data, leader_class, stage2, front_stage2, healer_stage2, rng))
	return squads


static func _shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i in range(arr.size() - 1, 0, -1):
		var j := rng.randi_range(0, i)
		var t = arr[i]
		arr[i] = arr[j]
		arr[j] = t
