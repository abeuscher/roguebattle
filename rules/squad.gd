class_name Squad
extends RefCounted
## A squad (SPEC §8): its units in two rows, the leader, slots, and how it moves.
## Travel type and speed tier follow from the units; call refresh() after changing them.
## A player squad is named after its leader, e.g. "Demandred (Knight)".

var id: int
var name: String
var side := "player"  # "player", "enemy" or "neutral"; only player and non-player squads fight
var role := ""  # enemy role (§17): leader, base_guard (hold the base) or field (EnemyAI); "roamer" for a neutral
var ai_mode := ""  # a field squad's last choice, "hold" or "move" (shown by the debug AI overlay)
var post := -1  # an enemy squad's placed hex, to return to after reviving at the Enemy Base
var goal := -1  # the building a field squad is heading for, so others pick something else
var think_at := 0  # tick from which a holding field squad weighs its choice again
var revive_at := -1  # enemy squad on the Enemy Base: tick its next fallen unit comes back
var unreachable := {}  # hexes a field squad found no route to, left out of its choices
var lair_hex := -1  # a roamer's home lair, to patrol around (§6.7); -1 for non-neutrals
var fire_ready := 0  # tick from which the squad may make a ranged map attack again (§11.2)
var hold_until := -1  # an enemy squad that just beat one of yours stands still until this tick (round 10)
var hex: int
var units: Array[Unit] = []
var leader: Unit
var travel_type := ""  # terrain key it moves through as native ("" = none)
var sky := false
var speed_tier := 2
var path := PackedInt32Array()  # hexes still to enter, in order
var rally := PackedInt32Array()  # rally points still ahead, each also on the path
var progress := 0.0  # ticks spent so far toward entering path[0]
var follow: Squad  # an enemy squad this one is following (re-routes as it moves), or null
var follow_hex := -1  # where the followed squad was last seen
var tactic := "best"  # the battle tactic last chosen for it (Battle.TACTICS), kept until changed (round 11)
var morale := 50  # 0-100, hidden (§12.2); below 30 deals less damage, below 25 can be driven off
var marching_home := false  # lost its leader: heads for base on its own (§11.3)
var entering_base := false  # leaves the map when it reaches the Player Base (§8.4)
var capture_ticks := 0.0  # time spent so far liberating the building it stands in (§6.5)
var tech: Array = []  # the army's tech nodes (the player's squads share GameState.tech)
var bond_battles := {}  # "id:id" (lowest instance id first) -> battles two units have fought together, toward a bond (§12.2)
var base_slots := 0  # slots before growth; 0 = rules.json slot_growth.base (single map mode sets 6)
var bonded_pairs: Array = []  # [Unit, Unit] once bonded; a +5% combat bonus while both live (Battle.gd)


func _init(squad_id: int, squad_name: String, at_hex: int) -> void:
	id = squad_id
	name = squad_name
	hex = at_hex


## Leaderless and marching home: it crawls at reduced speed and shows a skull (round 9).
func crawling() -> bool:
	return marching_home and (leader == null or not leader.is_alive())


func is_moving() -> bool:
	return not path.is_empty()


## The living unit u is bonded with (§12.2), or null.
func bonded_partner(u: Unit) -> Unit:
	for pair in bonded_pairs:
		if u == pair[0] and pair[1].is_alive():
			return pair[1]
		if u == pair[1] and pair[0].is_alive():
			return pair[0]
	return null


## The average of its units' alignment, the leader counted twice (§10).
func alignment() -> float:
	if units.is_empty():
		return 50.0
	var total := 0.0
	for u in units:
		total += u.alignment * (2 if u == leader else 1)
	return total / (units.size() + (1 if leader else 0))


## "holy", "evil" or "neutral", with the unit bands of §9.2.
func alignment_band(data: GameData) -> String:
	var bands: Dictionary = data.rules["alignment_bands"]
	var a := alignment()
	if a <= float(bands["evil_max"]):
		return "evil"
	return "holy" if a >= float(bands["holy_min"]) else "neutral"


func travel_name() -> String:
	if sky:
		return "Sky"
	return travel_type.capitalize() if travel_type != "" else "None"


func row(which: String) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.row == which:
			out.append(u)
	return out


func living(alive := true) -> Array[Unit]:
	var out: Array[Unit] = []
	for u in units:
		if u.is_alive() == alive:
			out.append(u)
	return out


# --- Positions ---------------------------------------------------------------------

func next_col(which: String) -> int:
	var c := 0
	for u in row(which):
		c = maxi(c, u.col + 1)
	return c


func at(which: String, column: int) -> Unit:
	for u in units:
		if u.row == which and u.col == column:
			return u
	return null


## Evens out a freshly generated squad's rows so neither holds more than one unit
## over half (5 units: 3:2 or 2:3; 4 units: 2:2), never 4:1 (user's playtest note,
## see DECISIONS.md session 030). Moves non-leaders from the full row, preferring
## the one with the most attacks in the other row (role template counts), then
## renumbers each row's positions from 0.
func balance_rows(data: GameData) -> void:
	var lo := floori(units.size() / 2.0)
	var hi := units.size() - lo
	while true:
		var front := row("front").size()
		var to := "back" if front > hi else ("front" if front < lo else "")
		if to == "":
			break
		var from := "front" if to == "back" else "back"
		var pool := row(from).filter(func(u: Unit): return u != leader)
		if pool.is_empty():
			pool = row(from)
		var best: Unit = null
		var best_count := -1
		for u: Unit in pool:
			var n := int(data.role_templates[u.info(data)["role"]][to + "_count"])
			if n > best_count or (n == best_count and u.col > best.col):
				best = u
				best_count = n
		best.row = to
		best.col = next_col(to)
	for which in ["front", "back"]:
		var r := row(which)
		r.sort_custom(func(a: Unit, b: Unit): return a.col < b.col)
		for i in r.size():
			r[i].col = i


## The unit in the other row at the same position: behind a front-row unit, or in front of a back-row one.
func across(u: Unit) -> Unit:
	return at("back" if u.row == "front" else "front", u.col)


# --- Slots (§8.2) -----------------------------------------------------------------

## Slots the given units fill: Small 1, Large 2, and Tiny units share a slot in pairs.
static func slots_filled(data: GameData, members: Array[Unit]) -> float:
	var total := 0.0
	var tiny := 0
	for u in members:
		if u.info(data)["size"] == "Tiny":
			tiny += 1
		else:
			total += u.slots(data)
	return total + ceili(tiny / 2.0)


func capacity(data: GameData) -> int:
	return (base_slots if base_slots > 0 else int(data.rules["slot_growth"]["base"])) + (leader.extra_slots if leader else 0)


func can_add(data: GameData, u: Unit) -> bool:
	var after := units.duplicate()
	after.append(u)
	return slots_filled(data, after) <= capacity(data)


## Adds a unit if it fits, at the next free position of its row. The first unit
## that can lead becomes the leader.
func add(data: GameData, u: Unit, unit_row := "front") -> bool:
	if not can_add(data, u):
		return false
	u.row = unit_row
	u.col = next_col(unit_row)
	units.append(u)
	if leader == null and u.info(data)["can_lead"]:
		leader = u
	refresh(data)
	return true


## At level 5, 10, 15 and 20 the leader earns a slot if charisma (plus banner
## bearers in the squad) is at least 5 × level. Call when the leader levels up.
func check_slot_growth(data: GameData) -> bool:
	var g: Dictionary = data.rules["slot_growth"]
	if leader == null or float(leader.level) not in g["levels"]:
		return false
	var charisma := leader.charisma
	for u in units:
		charisma += int(g["banners"].get(u.unit_class, 0))
	if charisma < int(g["charisma_per_level"]) * leader.level:
		return false
	leader.extra_slots += 1
	return true


# --- Movement (§8.3) ------------------------------------------------------------

## Recomputes the name, travel type and speed tier from the units.
func refresh(data: GameData) -> void:
	if side == "player":
		name = "%s (%s)" % [leader.name.get_slice(" ", 0), leader.unit_class] if leader else "Squad %d" % id
	var alive := living()
	if alive.is_empty():
		return
	speed_tier = 3
	var pacers := alive.filter(func(u: Unit): return not ("mage_regiments" in tech and Battle.base_kind(
			u.info(data)["front_attack" if u.row == "front" else "back_attack"]) == "Magic"))  # Mage Regiments: casters don't slow it
	for u in (pacers if not pacers.is_empty() else alive):
		speed_tier = mini(speed_tier, int(u.info(data)["speed_tier"]))
	var vote := travel_vote(data, alive, leader)
	sky = vote == "sky"
	if sky and "sky_lords" in tech:
		speed_tier = mini(3, speed_tier + int(data.tech["nodes"]["sky_lords"]["tiers"]))
	travel_type = "" if sky else vote


## The weighted vote: Small 1, leader and Large 2, Tiny ½. Sky wins only if every
## unit flies; otherwise flyers don't vote. Ties go to the leader's terrain.
## A squad of water natives and amphibians can cross deep water; an all-amphibious
## squad also moves freely on land. Returns a travel key or "sky".
static func travel_vote(data: GameData, members: Array[Unit], squad_leader: Unit) -> String:
	var keys: Dictionary = data.rules["travel_types"]
	var weights: Dictionary = data.rules["vote_weights"]
	if members.all(func(u: Unit): return u.has_tag(data, "flyer")):
		return "sky"
	if members.all(func(u: Unit): return u.has_tag(data, "amphibious")):
		return data.rules["amphibious_travel"]
	var tally := {}
	for u in members:
		var t := u.terrain(data)
		if u.has_tag(data, "flyer"):
			continue
		var w := float(weights["leader"]) if u == squad_leader else float(weights[u.info(data)["size"]])
		tally[t] = tally.get(t, 0.0) + w
	var best := ""
	for t in tally:
		if best == "" or tally[t] > tally[best]:
			best = t
	if squad_leader and tally.has(squad_leader.terrain(data)) and tally[squad_leader.terrain(data)] == tally[best]:
		best = squad_leader.terrain(data)
	if members.all(func(u: Unit): return u.terrain(data) == "Water" or u.has_tag(data, "amphibious")):
		return data.rules["all_water_travel"]
	return keys[best]


## Time multiplier from the dead: each dead unit slows the squad by its share of
## the squad's slots (one of five slots lost = 20% slower).
func casualty_multiplier(data: GameData) -> float:
	var dead := living(false)
	if dead.is_empty():
		return 1.0
	return 1.0 + slots_filled(data, dead) / capacity(data)
