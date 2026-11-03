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
var gold: int
var reputation: int


func _init(game_data: GameData, game_map: MapData, game_log: GameLog) -> void:
	data = game_data
	map = game_map
	log = game_log
	rng = RngStreams.new(map.seed)
	clock = GameClock.new(data.rules, int(data.rules["start_minute"]))
	pathfinder = Pathfinder.new(map, data)
	gold = int(data.rules["starting_gold"])
	reputation = int(data.rules["starting_reputation"])
	log.add(clock.tick, "system", "New map: seed %d, %s %s." % [map.seed, map.settings["preset"], map.settings["size"]],
			-1, {"settings": map.settings})


## Runs the simulation for one tick.
func step() -> void:
	for event in clock.step():
		if event == "new_day":
			log.add(clock.tick, "system", "Day %d begins." % clock.day())
		# Noon income, nomad moves and daily healing arrive in M3.
	for s in squads:
		_move(s)


func add_squad(squad_name: String, at_hex: int, travel_type: String, speed_tier: int) -> Squad:
	var s := Squad.new(squads.size() + 1, squad_name, at_hex)
	s.travel_type = travel_type
	s.speed_tier = speed_tier
	squads.append(s)
	return s


## Ticks to cross one hex of multiplier 1 at this speed tier (SPEC §8.3).
func base_ticks(s: Squad) -> float:
	return float(data.rules["hex_seconds_by_tier"][s.speed_tier - 1]) * float(data.rules["ticks_per_real_second"])


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
