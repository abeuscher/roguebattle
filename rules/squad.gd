class_name Squad
extends RefCounted
## A squad (SPEC §8): its units in two rows, the leader, slots, and how it moves.
## Travel type and speed tier follow from the units; call refresh() after changing them.

var id: int
var name: String
var hex: int
var units: Array[Unit] = []
var leader: Unit
var travel_type := ""  # terrain key it moves through as native ("" = none)
var sky := false
var speed_tier := 2
var path := PackedInt32Array()  # hexes still to enter, in order
var rally := PackedInt32Array()  # rally points still ahead, each also on the path
var progress := 0.0  # ticks spent so far toward entering path[0]
var morale := 50  # 0-100, hidden (§12.2); what moves it arrives in M4
var marching_home := false  # lost its leader: heads for base on its own (§11.3)


func _init(squad_id: int, squad_name: String, at_hex: int) -> void:
	id = squad_id
	name = squad_name
	hex = at_hex


func is_moving() -> bool:
	return not path.is_empty()


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
	return int(data.rules["slot_growth"]["base"]) + (leader.extra_slots if leader else 0)


func can_add(data: GameData, u: Unit) -> bool:
	var after := units.duplicate()
	after.append(u)
	return slots_filled(data, after) <= capacity(data)


## Adds a unit if it fits. The first unit that can lead becomes the leader.
func add(data: GameData, u: Unit, unit_row := "front") -> bool:
	if not can_add(data, u):
		return false
	u.row = unit_row
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

## Recomputes travel type and speed tier from the living units.
func refresh(data: GameData) -> void:
	var alive := living()
	if alive.is_empty():
		return
	speed_tier = 3
	for u in alive:
		speed_tier = mini(speed_tier, int(u.info(data)["speed_tier"]))
	var vote := travel_vote(data, alive, leader)
	sky = vote == "sky"
	travel_type = "" if sky else vote


## The weighted vote: Small 1, leader and Large 2, Tiny ½. Sky wins only if every
## unit flies; otherwise flyers don't vote. Ties go to the leader's terrain.
## An all-water squad gets the deep-water travel type. Returns a travel key or "sky".
static func travel_vote(data: GameData, members: Array[Unit], squad_leader: Unit) -> String:
	var keys: Dictionary = data.rules["travel_types"]
	var weights: Dictionary = data.rules["vote_weights"]
	var terrains := members.map(func(u: Unit): return u.terrain(data))
	if terrains.all(func(t: String): return t == "Sky"):
		return "sky"
	var tally := {}
	for u in members:
		var t := u.terrain(data)
		if t == "Sky":
			continue
		var w := float(weights["leader"]) if u == squad_leader else float(weights[u.info(data)["size"]])
		tally[t] = tally.get(t, 0.0) + w
	var best := ""
	for t in tally:
		if best == "" or tally[t] > tally[best]:
			best = t
	if squad_leader and tally.has(squad_leader.terrain(data)) and tally[squad_leader.terrain(data)] == tally[best]:
		best = squad_leader.terrain(data)
	if terrains.all(func(t: String): return t == "Water"):
		return data.rules["all_water_travel"]
	return keys[best]


## Time multiplier from the dead: each dead unit slows the squad by its share of
## the squad's slots (one of five slots lost = 20% slower).
func casualty_multiplier(data: GameData) -> float:
	var dead := living(false)
	if dead.is_empty():
		return 1.0
	return 1.0 + slots_filled(data, dead) / capacity(data)
