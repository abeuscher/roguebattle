class_name RngStreams
extends RefCounted
## One seeded generator per system (map, battle, recruitment, loot...), all
## derived from the game seed, so systems never disturb each other's sequences.

var seed: int
var _streams: Dictionary = {}


func _init(game_seed: int) -> void:
	seed = game_seed


func get_stream(system: String) -> RandomNumberGenerator:
	if not _streams.has(system):
		var rng := RandomNumberGenerator.new()
		rng.seed = derive_seed(seed, system)
		_streams[system] = rng
	return _streams[system]


static func derive_seed(game_seed: int, system: String) -> int:
	return ("%d:%s" % [game_seed, system]).hash()
