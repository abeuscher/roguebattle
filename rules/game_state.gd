class_name GameState
extends RefCounted
## Everything one running map needs. Plain rules: scenes read it and pass input in.

var data: GameData
var map: MapData
var rng: RngStreams
var clock: GameClock
var log: GameLog
var pathfinder: Pathfinder
var squads: Array[Squad] = []  # every squad on the map
var army: Army  # the player's squads, on the map or at base, the recruit pool and items
var names: NameBook
var settings: Dictionary  # victory, defeat, squad cap, fairness (from the configurator)
var gold: int
var reputation: int
var pending: Battle  # a battle waiting to be fought; the map holds until it's resolved
var revealed := {}  # building index -> true for hidden sites and lairs a squad has seen
var _contact_until := {}  # "player id:enemy id" -> tick before which the pair won't fight again
var _moved := {}  # squads that entered a new hex this tick
var _building_at := {}  # hex -> index in map.buildings


func _init(game_data: GameData, game_map: MapData, game_log: GameLog, game_settings := {}) -> void:
	data = game_data
	map = game_map
	log = game_log
	settings = game_settings
	rng = RngStreams.new(map.seed)
	clock = GameClock.new(data.rules, int(data.rules["start_minute"]))
	pathfinder = Pathfinder.new(map, data)
	names = NameBook.new(data)
	gold = int(data.rules["starting_gold"])
	reputation = int(data.rules["starting_reputation"])
	army = Army.new(data)
	for i in map.buildings.size():
		var b: Dictionary = map.buildings[i]
		b["owner"] = data.buildings[b["type"]].get("owner", "neutral")
		b["away"] = false  # nomads that moved out of sight until the next half day
		_building_at[b["hex"]] = i
	log.add(clock.tick, "system", "New map: seed %d, %s %s." % [map.seed, map.settings["preset"], map.settings["size"]],
			-1, {"settings": map.settings, "game": settings})


## Runs the simulation for one tick. Stops early if two hostile squads meet:
## `pending` then holds the battle until resolve_pending().
func step() -> void:
	if pending:
		return
	for event in clock.step():
		if event == "new_day":
			log.add(clock.tick, "system", "Day %d begins." % clock.day())
			_rest()
		elif event == "half_day":
			_move_nomads()
		# Noon income and upkeep arrive with the economy (M3 session 4).
	_moved.clear()
	for s in squads.duplicate():
		_move(s)
		if s.entering_base and s.hex == map.player_base:
			return_to_base(s)
	_capture()
	_reveal_sites()
	_check_contact()


## A squad of freshly rolled units. `members` lists [class name, row] pairs;
## units that don't fit are skipped. Player squads are numbered from 1, others from 101.
func add_squad(squad_name: String, at_hex: int, members: Array, side := "player") -> Squad:
	var number := 1 + squads.filter(func(o: Squad): return o.side == side).size() + (0 if side == "player" else 100)
	var s := _form(number, squad_name, at_hex, members, side)
	squads.append(s)
	return s


## The placeholder army from rules.json until Map 1 setup (M4): its squads (named
## after their leaders) fill the first cells, the first one stands on the Player Base, the rest wait at base (§8.4).
func setup_army() -> void:
	var p: Dictionary = data.rules["placeholder_army"]
	for i in p["squads"].size():
		var entry: Dictionary = p["squads"][i]
		var s := _form(i + 1, "", map.player_base if i == 0 else -1, entry["units"], "player")
		army.cells[i] = s
		if i == 0:
			squads.append(s)
	for c in p["pool"]:
		var u := Unit.roll(data, c, rng.get_stream("recruit"), names)
		army.pool.append(u)
		log.add(clock.tick, "progression", "%s the %s waits in the recruit pool." % [u.name, u.unit_class])
	for id in p["items"]:
		for i in int(p["items"][id]):
			army.add_item(id)


# --- Buildings (SPEC §6.5) ---------------------------------------------------------------

## The building on a hex, or {} if none (hidden sites count only once revealed;
## nomads that moved out of sight don't count).
func building_at(i: int) -> Dictionary:
	if not _building_at.has(i):
		return {}
	var b: Dictionary = map.buildings[_building_at[i]]
	if b["away"] or (b["hidden"] and not revealed.has(_building_at[i])):
		return {}
	return b


## A building's numbers for a squad: [defense, HP healed per day]. Towns and towers
## (and nomads, as towns) give more to squads of their alignment; a base gives its own side.
func building_effect(b: Dictionary, s: Squad) -> Array:
	var info: Dictionary = data.buildings[b["type"]]
	if info.has("own_base"):
		var own: bool = info["owner"] == ("player" if s.side == "player" else "enemy")
		return [float(info["own_base"]["defense"]), float(info["own_base"]["rest"])] if own else [0.0, 0.0]
	if not info.has("defense"):
		return [0.0, 0.0]
	var k := 1 if info.get("aligned", "") == s.alignment_band(data) else 0
	return [float(info["defense"][k]), float(info["rest"][k])]


func building_defense(s: Squad) -> float:
	var b := building_at(s.hex)
	return building_effect(b, s)[0] if not b.is_empty() else 0.0


## Liberation (§6.5): a player squad with a living ground unit that stays in an enemy-held
## town or tower for 60 ticks takes it; Sapper lines take it twice as fast.
func _capture() -> void:
	var c: Dictionary = data.rules["capture"]
	for s in player_squads():
		var b := building_at(s.hex)
		if s.is_moving() or b.is_empty() or not data.buildings[b["type"]].get("capturable", false) or b["owner"] == "player" \
				or not s.living().any(func(u: Unit): return not u.has_tag(data, "flyer")):
			s.capture_ticks = 0.0
			continue
		var sapper := s.living().any(func(u: Unit): return u.has_tag(data, "sapper"))
		s.capture_ticks += float(c["sapper_speed"]) if sapper else 1.0
		if s.capture_ticks >= float(c["ticks"]):
			s.capture_ticks = 0.0
			b["owner"] = "player"
			log.add(clock.tick, "map", "%s liberates the %s at %s." % [s.name, data.buildings[b["type"]]["name"].to_lower(), map.hex_at(s.hex)], s.id)


## Share of the capture done by squads on a building's hex (0 if none).
func capture_progress(b: Dictionary) -> float:
	var best := 0.0
	for s in player_squads():
		if s.hex == b["hex"]:
			best = maxf(best, s.capture_ticks / float(data.rules["capture"]["ticks"]))
	return best


## Daily rest (§6.5): squads in buildings heal their living units by the building's
## share of max HP; squads and recruits at the Player Base rest as in their own base.
func _rest() -> void:
	for s in squads:
		var b := building_at(s.hex)
		if not b.is_empty():
			_heal_share(s.living(), building_effect(b, s)[1])
	var base: float = data.buildings["player_base"]["own_base"]["rest"]
	for s in army.squads():
		if s not in squads:
			_heal_share(s.living(), base)
	_heal_share(army.pool.filter(func(u: Unit): return u.is_alive()), base)


func _heal_share(units: Array, share: float) -> void:
	if share <= 0.0:
		return
	for u in units:
		u.hp = mini(u.max_hp(data), u.hp + maxi(1, roundi(u.max_hp(data) * share)))


## Nomads (§6.5) move 4–6 hexes every half day over the terrains they can camp on,
## never onto another building or a squad; each move has a 20% chance to stay out of
## sight until the next half day.
func _move_nomads() -> void:
	var r := rng.get_stream("nomads")
	for i in map.buildings.size():
		var b: Dictionary = map.buildings[i]
		if b["type"] != "nomads":
			continue
		var info: Dictionary = data.buildings["nomads"]
		var spots := nomad_spots(b["hex"])
		if spots.is_empty():
			continue
		_building_at.erase(b["hex"])
		b["hex"] = spots[r.randi() % spots.size()]
		_building_at[b["hex"]] = i
		b["away"] = r.randf() < float(info["hide_chance"])
		log.add(clock.tick, "map", "Nomads move on.", -1, {"to": str(map.hex_at(b["hex"])), "out_of_sight": b["away"]})


## Hexes 4–6 steps from `from` reachable through nomad terrain, free of buildings and squads.
func nomad_spots(from: int) -> Array:
	var info: Dictionary = data.buildings["nomads"]
	var allowed := {}
	for key in info["terrains"]:
		allowed[data.terrain_ids[key]] = true
	var lo := int(info["move_hexes"][0])
	var hi := int(info["move_hexes"][1])
	var dist := {from: 0}
	var frontier := [from]
	var out := []
	for step_n in hi:
		var next := []
		for h in frontier:
			for n in map.neighbor_indices(h):
				if dist.has(n) or not allowed.has(map.terrain[n]):
					continue
				dist[n] = step_n + 1
				next.append(n)
				if step_n + 1 >= lo and not _building_at.has(n) and _squad_on(n) == null:
					out.append(n)
		frontier = next
	return out


## A town's hint about the nearest unseen hidden site within range: "to the northeast,
## about 12 hexes away", or "".
func hint(b: Dictionary) -> String:
	if not b.get("hint", false):
		return ""
	var at := map.hex_at(b["hex"])
	var best := -1
	for i in map.buildings.size():
		var o: Dictionary = map.buildings[i]
		if o["type"] == "hidden_site" and not revealed.has(i):
			var d := Hex.distance(at, map.hex_at(o["hex"]))
			if d <= int(data.rules["capture"]["hint_range"]) and (best < 0 or d < Hex.distance(at, map.hex_at(map.buildings[best]["hex"]))):
				best = i
	if best < 0:
		return ""
	var delta := Hex.to_pixel(map.hex_at(map.buildings[best]["hex"]), 1.0) - Hex.to_pixel(at, 1.0)
	var names := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]
	var dir: String = names[posmod(roundi(delta.angle() / (PI / 4.0)), 8)]
	return "Travellers speak of something hidden to the %s, about %d hexes away." % [dir, Hex.distance(at, map.hex_at(map.buildings[best]["hex"]))]


# --- Base and deployment (SPEC §8.4, §6.5 Player Base, §15.1 services) ----------------

## Squads on the map at once, from the configurator (default 5).
func squad_cap() -> int:
	if settings.has("squad_cap"):
		return int(settings["squad_cap"])
	for f in data.config_fields:
		if f["key"] == "squad_cap":
			return int(f["default"])
	return 5


## Gold per day for the squad's units (§15.1): by stage, Large ×2, Tiny ×½.
func upkeep(s: Squad) -> int:
	var u: Dictionary = data.rules["upkeep"]
	var total := 0.0
	for unit in s.units:
		var c: Dictionary = unit.info(data)
		total += float(u["by_stage"][int(c["stage"]) - 1]) * float(u["size"][c["size"]])
	return roundi(total)


## Deploying costs one day of the squad's upkeep.
func deploy_cost(s: Squad) -> int:
	return upkeep(s)


## The hex a deployed squad appears on: the Player Base (your squads can share a hex).
func deploy_hex() -> int:
	return map.player_base


## Why the squad can't deploy, or "" if it can.
func deploy_blocker(s: Squad) -> String:
	if s in squads:
		return "Already on the map."
	if s.leader == null:
		return "It needs a leader."
	if not s.leader.is_alive():
		return "Its leader has fallen: revive them first."
	if player_squads().size() >= squad_cap():
		return "The squad cap is %d on the map at once." % squad_cap()
	if gold < deploy_cost(s):
		return "Not enough gold: deploying costs %d." % deploy_cost(s)
	return ""


## Pays the deploy cost and puts a squad from base on the map at deploy_hex(); with
## rally points, it sets off along them at once.
func deploy(s: Squad, points := PackedInt32Array()) -> bool:
	if deploy_blocker(s) != "":
		return false
	var cost := deploy_cost(s)
	gold -= cost
	s.hex = deploy_hex()
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	s.marching_home = false
	s.entering_base = false
	squads.append(s)
	log.add(clock.tick, "economy", "%s deploys from the Player Base for %d gold." % [s.name, cost], s.id)
	if not points.is_empty():
		order_move(s, points)
	return true


## A squad standing on the Player Base can go in; elsewhere it marches there and goes
## in on arrival.
func send_home(s: Squad) -> void:
	if s.hex == map.player_base:
		return_to_base(s)
	elif order_move(s, PackedInt32Array([map.player_base])):
		s.entering_base = true


func return_to_base(s: Squad) -> void:
	_leave_map(s)
	log.add(clock.tick, "map", "%s returns to the Player Base." % s.name, s.id)


func _leave_map(s: Squad) -> void:
	squads.erase(s)
	s.hex = -1
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	s.marching_home = false
	s.entering_base = false


## Healing and revival are bought at base: for units at base or in the pool.
func at_base(u: Unit) -> bool:
	var s := army.squad_of(u)
	return s == null or s not in squads


func heal_cost(u: Unit) -> int:
	return int(data.rules["services"]["heal"]) if u.is_alive() and u.hp < u.max_hp(data) else 0


func revive_cost(u: Unit) -> int:
	return int(data.rules["services"]["revive_per_stage"]) * int(u.info(data)["stage"]) if not u.is_alive() else 0


## Heals a hurt unit to full, or revives a fallen one at full HP, for gold. False if
## the unit isn't at base, needs nothing, or the gold is short.
func restore(u: Unit) -> bool:
	var cost := heal_cost(u) + revive_cost(u)
	if cost == 0 or cost > gold or not at_base(u):
		return false
	var revived := not u.is_alive()
	gold -= cost
	u.hp = u.max_hp(data)
	var s := army.squad_of(u)
	if s:
		s.refresh(data)
	log.add(clock.tick, "economy", "%s %s for %d gold." % [u.name, "is revived" if revived else "is healed", cost], s.id if s else -1)
	return true


## Squads can be changed at the Player Base, or while waiting there off the map.
func can_edit(s: Squad) -> bool:
	return s not in squads or (s.hex == map.player_base and not s.is_moving() and not s.marching_home)


## After Edit Units: squads emptied there leave the map.
func after_edit() -> void:
	for s in squads.duplicate():
		if s.side == "player" and s not in army.squads():
			squads.erase(s)


func _form(number: int, squad_name: String, at_hex: int, members: Array, side: String) -> Squad:
	var s := Squad.new(number, squad_name, at_hex)
	s.side = side
	for m in members:
		var u := Unit.roll(data, m[0], rng.get_stream("recruit"), names)
		if s.add(data, u, m[1]):
			log.add(clock.tick, "progression", "%s the %s joins %s." % [u.name, u.unit_class, s.name], s.id,
					{"stats": u.stats, "alignment": u.alignment, "charisma": u.charisma, "growth": u.growth,
					"talent": u.talent, "luck": u.luck})
	s.morale = int(data.rules["starting_morale"])
	log.add(clock.tick, "map", "%s forms: travels as %s, speed tier %d." % [s.name, s.travel_name(), s.speed_tier], s.id)
	return s


## Ticks to cross one hex of multiplier 1 at this speed tier, slowed by casualties (SPEC §8.3).
func base_ticks(s: Squad) -> float:
	return float(data.rules["hex_seconds_by_tier"][s.speed_tier - 1]) * float(data.rules["ticks_per_real_second"]) \
			* s.casualty_multiplier(data)


## Ticks to enter hex `i`.
func step_ticks(s: Squad, i: int) -> float:
	return base_ticks(s) * pathfinder.hex_cost(i, s.travel_type, s.sky)


## The route through these rally points in order, starting where the squad stands
## (the squad's own hex not included). Empty if any point can't be reached.
func plan(s: Squad, points: PackedInt32Array) -> PackedInt32Array:
	var route := PackedInt32Array()
	var from := s.hex
	for p in points:
		var leg := pathfinder.find(from, p, s.travel_type, s.sky)
		if leg.is_empty():
			return PackedInt32Array()
		route.append_array(leg.slice(1))
		from = p
	return route


func route_ticks(s: Squad, route: PackedInt32Array) -> float:
	var total := 0.0
	for i in route:
		total += step_ticks(s, i)
	return total


## Gives a move order through these rally points. Returns false if a point can't be reached.
func order_move(s: Squad, points: PackedInt32Array) -> bool:
	var route := plan(s, points)
	if route.is_empty() and not points.is_empty():
		return false
	s.entering_base = false
	s.path = route
	s.rally = points.duplicate()
	s.progress = 0.0
	var to := map.hex_at(points[points.size() - 1]) if not points.is_empty() else map.hex_at(s.hex)
	log.add(clock.tick, "map", "%s ordered to %s via %d rally point%s: %d hexes, about %s." % [s.name, to,
			points.size(), "" if points.size() == 1 else "s", route.size(), duration_text(route_ticks(s, route))],
			s.id, {"path": Array(route)})
	return true


func player_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for s in squads:
		if s.side == "player":
			out.append(s)
	return out


func hostile(a: Squad, b: Squad) -> bool:
	return (a.side == "player") != (b.side == "player")


# --- Enemy squads (SPEC §17) --------------------------------------------------------

## Places the enemy's squads by role: the leader on the Enemy Base, the base guard and
## raider next to it, garrisons and wildcards on separate enemy-held buildings
## (towns and towers until liberation arrives). They stand still until the AI (M4).
func place_enemies() -> void:
	var e: Dictionary = data.enemy
	var r := rng.get_stream("enemy")
	var sites := []
	for b in map.buildings:
		if b["type"] in e["enemy_buildings"]:
			sites.append(b["hex"])
	for i in range(sites.size() - 1, 0, -1):  # seeded shuffle
		var j := r.randi_range(0, i)
		var t = sites[i]
		sites[i] = sites[j]
		sites[j] = t
	var builds: Array = e["builds"]
	for entry in e["roles"]:
		var count := int(entry["count"])
		for k in count:
			var at := -1
			match entry["at"]:
				"enemy_base":
					at = map.enemy_base
				"near_enemy_base":
					at = _free_near(map.enemy_base)
				_:
					while not sites.is_empty() and at < 0:
						var h: int = sites.pop_front()
						if _squad_on(h) == null:
							at = h
			if at < 0:
				at = _free_near(map.enemy_base)
			var title: String = e["names"][entry["role"]]
			var s := add_squad("%s %d" % [title, k + 1] if count > 1 else title, at, builds[r.randi() % builds.size()], "enemy")
			s.role = entry["role"]


## The nearest hex to `center` (not center itself) that a ground squad can stand on and no squad holds.
func _free_near(center: int) -> int:
	var seen_hexes := {center: true}
	var frontier := [center]
	while not frontier.is_empty():
		var next := []
		for h in frontier:
			for n in map.neighbor_indices(h):
				if seen_hexes.has(n):
					continue
				seen_hexes[n] = true
				if Movement.hex_multiplier(map, data, n) < INF and _squad_on(n) == null:
					return n
				next.append(n)
		frontier = next
	return center


func _squad_on(i: int) -> Squad:
	for s in squads:
		if s.hex == i:
			return s
	return null


# --- Contact and sight (SPEC §11.1, §8.5) -------------------------------------------------

## Two hostile squads on the same or adjacent hexes fight. The squad that moved into
## contact attacks; the battle uses the defender's hex. A pair that just fought waits
## a short cooldown before fighting again.
func _check_contact() -> void:
	for p in squads:
		if p.side != "player" or p.living().is_empty():
			continue
		for e in squads:
			if not hostile(p, e) or e.living().is_empty():
				continue
			if Hex.distance(map.hex_at(p.hex), map.hex_at(e.hex)) > 1:
				continue
			if clock.tick < int(_contact_until.get(_pair(p, e), -1)):
				continue
			var defender := e if _moved.has(p) or not _moved.has(e) else p
			for s in [p, e]:
				s.path.clear()
				s.rally.clear()
				s.progress = 0.0
			pending = start_battle(p, e, defender)
			return


func _pair(p: Squad, e: Squad) -> String:
	return "%d:%d" % [p.id, e.id]


## Fights the pending battle to the end (the battle view may have played it already)
## and applies the outcome. Returns end_battle's outcome plus a short summary as "text".
func resolve_pending() -> Dictionary:
	var b := pending
	pending = null
	b.run()
	var key := _pair(b.sides[0], b.sides[1])
	var out := end_battle(b)
	if not b.ranged_only:
		_contact_until[key] = clock.tick + int(data.enemy["contact_cooldown_ticks"])
	out["text"] = battle_summary(b, out)
	return out


static func battle_summary(b: Battle, out: Dictionary) -> String:
	var who := [b.sides[0].name, b.sides[1].name]
	var text := "%s %s %s: lost %d%% of its HP, took %d%% of theirs." % [who[0],
			"fired on" if b.ranged_only else "fought", who[1], roundi(out["hp_lost"][0] * 100), roundi(out["hp_lost"][1] * 100)]
	for side in 2:
		if out["wiped"][side]:
			text += " %s was wiped out." % who[side]
		elif out["leader_dead"][side]:
			text += " %s lost its leader." % who[side]
	if out["retreated"] >= 0:
		text += " %s retreated." % who[out["retreated"]]
	if out["pushed"] >= 0:
		text += " %s was pushed back." % who[out["pushed"]]
	return text


## Hidden sight radius from `viewer` to a hex (§8.5): 7, +2 if the viewer flies, +1 on
## its travel-type terrain (else −1), −2 if the target is in mountains, −1 in forest.
## Clamped to 5–10.
func sight(viewer: Squad, target_hex: int) -> int:
	var r: Dictionary = data.rules["sight"]
	var v := int(r["base"])
	if viewer.sky:
		v += int(r["flying"])
	v += int(r["on_travel_terrain"]) if _on_travel_terrain(viewer) else int(r["off_travel_terrain"])
	v += int(r["target_terrain"].get(data.terrains[map.terrain[target_hex]]["key"], 0))
	return clampi(v, int(r["range"][0]), int(r["range"][1]))


## Whether any player squad can see this hex.
func seen(target_hex: int) -> bool:
	for s in squads:
		if s.side == "player" and not s.living().is_empty() \
				and Hex.distance(map.hex_at(s.hex), map.hex_at(target_hex)) <= sight(s, target_hex):
			return true
	return false


## Player squads always show; others only within sight.
func is_visible(s: Squad) -> bool:
	return s.side == "player" or seen(s.hex)


func _reveal_sites() -> void:
	for i in map.buildings.size():
		var b: Dictionary = map.buildings[i]
		if (b["hidden"] or b["type"] == "lair") and not revealed.has(i) and seen(b["hex"]):
			revealed[i] = true
			log.add(clock.tick, "map", "A hidden site comes into view at %s." % map.hex_at(b["hex"]))


# --- Ranged map attacks (SPEC §11.2) ----------------------------------------------------

func can_fire(s: Squad) -> bool:
	for u in s.living():
		var kind: String = u.info(data)["front_attack" if u.row == "front" else "back_attack"]
		if Battle.base_kind(kind) in data.rules["ranged_attack"]["attack_kinds"]:
			return true
	return false


## 2 hexes, or 3 from high ground (mountains, towers); a longbow adds its range.
func fire_range(s: Squad) -> int:
	var r: Dictionary = data.rules["ranged_attack"]
	var high: bool = data.terrains[map.terrain[s.hex]]["key"] in r["high_ground_terrains"]
	for b in map.buildings:
		if b["hex"] == s.hex and b["type"] in r["high_ground_buildings"]:
			high = true
	var extra := 0
	for u in s.living():
		for slot in u.items:
			extra = maxi(extra, int(data.items["items"][u.items[slot]["id"]].get("range", 0)))
	return (int(r["high_ground_range"]) if high else int(r["range"])) + extra


## Visible hostile squads within range, if the squad has ranged units and its cooldown is over.
func fire_targets(s: Squad) -> Array[Squad]:
	var out: Array[Squad] = []
	if not can_fire(s) or clock.tick < s.fire_ready:
		return out
	for e in squads:
		if hostile(s, e) and is_visible(e) and not e.living().is_empty() \
				and Hex.distance(map.hex_at(s.hex), map.hex_at(e.hex)) <= fire_range(s):
			out.append(e)
	return out


## A ranged map attack: only Ranged and Magic units on both sides act, no push-back.
## Starts the squad's 120-tick cooldown and leaves the battle pending, like contact.
func fire(s: Squad, target: Squad) -> void:
	var b := start_battle(s, target, target)
	b.ranged_only = true
	for side in 2:
		for u in b.sides[side].living():
			b._join(u)
	s.fire_ready = clock.tick + int(data.rules["ranged_attack"]["cooldown_ticks"])
	pending = b


# --- Battles (SPEC §11) ------------------------------------------------------------

## Opens a battle between a player squad and an enemy, fought on the defender's hex.
func start_battle(player: Squad, enemy: Squad, defender: Squad) -> Battle:
	var info: Dictionary = data.terrains[map.terrain[defender.hex]]
	var b := Battle.new(data, player, enemy, info["key"], clock.is_day(), rng.get_stream("battle"), settings.get("fairness", "both"))
	b.attacker = 0 if defender == enemy else 1
	b.defense = [building_defense(player), building_defense(enemy)]
	log.add(clock.tick, "battle", "Battle: %s against %s on %s. The enemy looks %s." % [player.name, enemy.name, info["name"],
			Threat.label(data, player, enemy).to_lower()], player.id)
	return b


## Ends a battle and applies its outcome on the map (§11.3, §11.6): a wiped-out player
## squad returns to base (an enemy one leaves the map), a squad that lost its leader
## marches home, a retreating squad steps back 1 hex and each unit loses 1 charisma,
## and the side that lost more of its HP is pushed back.
func end_battle(b: Battle) -> Dictionary:
	for e in b.events:
		log.add(clock.tick, "battle", b.log_line(e), b.sides[0].id, e.get("hidden", {}))
	var out := b.finish()
	for side in 2:
		var s := b.sides[side]
		var enemy := b.sides[1 - side]
		if out["wiped"][side]:
			s.path.clear()
			s.rally.clear()
			if side == 0:
				_leave_map(s)
				log.add(clock.tick, "battle", "%s is wiped out and carried back to base." % s.name, s.id)
			else:
				squads.erase(s)
				log.add(clock.tick, "battle", "%s is wiped out." % s.name, s.id)
			continue
		if out["retreated"] == side:
			_push(s, enemy.hex, 1)
			for u in s.units:
				u.charisma = maxi(0, u.charisma - 1)
		elif out["pushed"] == side:
			_push(s, enemy.hex, int(data.battle["push_back"]["on_travel_terrain" if _on_travel_terrain(s) else "otherwise"]))
		if out["leader_dead"][side] and not s.marching_home:
			s.marching_home = true
			order_move(s, PackedInt32Array([map.player_base if side == 0 else map.enemy_base]))
			s.entering_base = side == 0
			log.add(clock.tick, "battle", "%s lost its leader and marches home." % s.name, s.id)
	return out


## Whether the battle hex is the squad's travel-type terrain (flyers always are).
func _on_travel_terrain(s: Squad) -> bool:
	if s.sky:
		return true
	var info: Dictionary = data.terrains[map.terrain[s.hex]]
	return s.travel_type != "" and (info["key"] == s.travel_type or info.get("native_as", "") == s.travel_type)


## Moves a squad up to `steps` hexes directly away from `from`, through hexes it can
## enter that no other squad holds. Its orders are dropped.
func _push(s: Squad, from: int, steps: int) -> void:
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	var origin := map.hex_at(from)
	var start := s.hex
	for i in steps:
		var best := -1
		for n in map.neighbor_indices(s.hex):
			if pathfinder.hex_cost(n, s.travel_type, s.sky) == INF or _hostile_at(n, s):
				continue
			if best < 0 or Hex.distance(map.hex_at(n), origin) > Hex.distance(map.hex_at(best), origin):
				best = n
		if best < 0 or Hex.distance(map.hex_at(best), origin) <= Hex.distance(map.hex_at(s.hex), origin):
			break
		s.hex = best
	if s.hex != start:
		log.add(clock.tick, "battle", "%s is pushed back to %s." % [s.name, map.hex_at(s.hex)], s.id)


## Whether a squad hostile to s stands on the hex. Your squads can share hexes; hostile ones can't.
func _hostile_at(i: int, s: Squad) -> bool:
	for o in squads:
		if o.hex == i and hostile(s, o):
			return true
	return false


## The leader's charisma %, halved if the enemy's morale is 10–25; none at 25 or more (§11.6).
func drive_off_chance(s: Squad, enemy: Squad) -> float:
	var d: Dictionary = data.battle["drive_off"]
	if s.leader == null or not s.leader.is_alive() or enemy.morale >= int(d["morale_below"]):
		return 0.0
	var c := s.leader.charisma / 100.0
	return c / 2.0 if enemy.morale >= int(d["halved_from"]) else c


## Demands that a beaten enemy flee. On success it leaves the map for good.
func drive_off(s: Squad, enemy: Squad) -> bool:
	var ok := rng.get_stream("battle").randf() < drive_off_chance(s, enemy)
	if ok:
		squads.erase(enemy)
	log.add(clock.tick, "battle", "%s %s." % [enemy.name, "flees the map" if ok else "refuses to flee"], s.id)
	return ok


static func duration_text(ticks: float) -> String:
	var minutes := roundi(ticks)
	return "%d h %02d m" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d m" % minutes


func _move(s: Squad) -> void:
	if not s.is_moving():
		return
	s.progress += 1.0
	while s.is_moving() and s.progress >= step_ticks(s, s.path[0]):
		if _hostile_at(s.path[0], s):  # an enemy holds it: wait at the edge
			s.progress = step_ticks(s, s.path[0])
			break
		s.progress -= step_ticks(s, s.path[0])
		s.hex = s.path[0]
		s.path = s.path.slice(1)
		_moved[s] = true
		if not s.rally.is_empty() and s.hex == s.rally[0]:
			s.rally = s.rally.slice(1)
			if s.rally.is_empty():
				log.add(clock.tick, "map", "%s reached its destination %s." % [s.name, map.hex_at(s.hex)], s.id)
			else:
				log.add(clock.tick, "map", "%s reached a rally point; %d to go." % [s.name, s.rally.size()], s.id)
	if not s.is_moving():
		s.progress = 0.0


func speed_name() -> String:
	return data.rules["game_speed_names"][clock.speed_index]


func set_speed_index(index: int) -> void:
	var before := clock.speed_index
	clock.set_speed_index(index)
	if clock.speed_index != before:
		log.add(clock.tick, "system", "Game speed: %s (x%s)." % [speed_name(), clock.speed()])


func toggle_pause() -> void:
	clock.paused = not clock.paused
	log.add(clock.tick, "system", "Paused." if clock.paused else "Resumed.")
