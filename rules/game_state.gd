class_name GameState
extends RefCounted
## Everything one running map needs. Plain rules: scenes read it and pass input in.

var data: GameData
var map: MapData
var rng: RngStreams
var clock: GameClock
var log: GameLog
var gold: int
var reputation: int


func _init(game_data: GameData, game_map: MapData, game_log: GameLog) -> void:
	data = game_data
	map = game_map
	log = game_log
	rng = RngStreams.new(map.seed)
	clock = GameClock.new(data.rules, int(data.rules["start_minute"]))
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
