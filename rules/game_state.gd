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


## Runs the simulation for one tick.
func step() -> void:
	for event in clock.step():
		if event == "new_day":
			log.add(clock.tick, "system", "Day %d begins." % clock.day())
		# Noon income, nomad moves and daily healing arrive in M3.
	for s in squads:
		_move(s)


## A squad of freshly rolled units. `members` lists [class name, row] pairs;
## units that don't fit are skipped.
func add_squad(squad_name: String, at_hex: int, members: Array) -> Squad:
	var s := Squad.new(squads.size() + 1, squad_name, at_hex)
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
		log.add(clock.tick, "battle", e["text"], b.sides[0].id)
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
		s.progress -= step_ticks(s, s.path[0])
		s.hex = s.path[0]
		s.path = s.path.slice(1)
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
