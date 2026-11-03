class_name GameState
extends RefCounted
## Everything one running map needs. Plain rules: scenes read it and pass input in.

var data: GameData
var map: MapData
var rng: RngStreams
var clock: GameClock
var log: GameLog
var pathfinder: Pathfinder
var squads: Array[Squad] = []
var names: NameBook
var settings: Dictionary  # victory, defeat, squad cap, fairness (from the configurator)
var gold: int
var reputation: int
var pending: Battle  # a battle waiting to be fought; the map holds until it's resolved
var revealed := {}  # building index -> true for hidden sites and lairs a squad has seen
var _contact_until := {}  # "player id:enemy id" -> tick before which the pair won't fight again
var _moved := {}  # squads that entered a new hex this tick


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
		# Noon income, nomad moves and daily healing arrive in M3.
	_moved.clear()
	for s in squads:
		_move(s)
	_reveal_sites()
	_check_contact()


## A squad of freshly rolled units. `members` lists [class name, row] pairs;
## units that don't fit are skipped. Player squads are numbered from 1, others from 101.
func add_squad(squad_name: String, at_hex: int, members: Array, side := "player") -> Squad:
	var number := 1 + squads.filter(func(o: Squad): return o.side == side).size() + (0 if side == "player" else 100)
	var s := Squad.new(number, squad_name, at_hex)
	s.side = side
	for m in members:
		var u := Unit.roll(data, m[0], rng.get_stream("recruit"), names)
		if s.add(data, u, m[1]):
			log.add(clock.tick, "progression", "%s the %s joins %s." % [u.name, u.unit_class, squad_name], s.id,
					{"stats": u.stats, "alignment": u.alignment, "charisma": u.charisma, "growth": u.growth,
					"talent": u.talent, "luck": u.luck})
	s.morale = int(data.rules["starting_morale"])
	squads.append(s)
	log.add(clock.tick, "map", "%s forms: travels as %s, speed tier %d." % [squad_name, s.travel_name(), s.speed_tier], s.id)
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


## 2 hexes, or 3 from high ground (mountains, towers).
func fire_range(s: Squad) -> int:
	var r: Dictionary = data.rules["ranged_attack"]
	var high: bool = data.terrains[map.terrain[s.hex]]["key"] in r["high_ground_terrains"]
	for b in map.buildings:
		if b["hex"] == s.hex and b["type"] in r["high_ground_buildings"]:
			high = true
	return int(r["high_ground_range"]) if high else int(r["range"])


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
				s.hex = map.player_base
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
			if pathfinder.hex_cost(n, s.travel_type, s.sky) == INF or _occupied(n, s):
				continue
			if best < 0 or Hex.distance(map.hex_at(n), origin) > Hex.distance(map.hex_at(best), origin):
				best = n
		if best < 0 or Hex.distance(map.hex_at(best), origin) <= Hex.distance(map.hex_at(s.hex), origin):
			break
		s.hex = best
	if s.hex != start:
		log.add(clock.tick, "battle", "%s is pushed back to %s." % [s.name, map.hex_at(s.hex)], s.id)


func _occupied(i: int, except: Squad) -> bool:
	for o in squads:
		if o != except and o.hex == i:
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
		if _squad_on(s.path[0]) != null:  # someone stands there: wait at the edge
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
