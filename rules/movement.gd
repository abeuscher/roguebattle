class_name Movement
## Travel-time rules (SPEC §8.3, §6.3).


## Time multiplier for one hex: difficulty 1/2/3 cost x1/x1.5/x2, the squad's
## travel type counts as difficulty 1, roads give x0.75 to non-Sky squads.
## Impassable terrain marked natives_cross (deep water) is open to that travel type.
## INF where the squad can't go. `travel_type` is a terrain key ("" = none).
static func hex_multiplier(map: MapData, data: GameData, i: int, travel_type := "", sky := false) -> float:
	if sky:
		return 1.0
	var info: Dictionary = data.terrains[map.terrain[i]]
	var m: float
	if info.get("impassable", false):
		if info.get("natives_cross", false) and info["key"] == travel_type:
			m = 1.0  # an all-water squad swims deep water (§8.3)
		elif not map.road[i]:  # otherwise bridges are the only way over
			return INF
		m = 1.0
	elif travel_type != "" and (info["key"] == travel_type or info.get("native_as", "") == travel_type):
		m = 1.0
	else:
		m = float(data.rules["difficulty_multiplier"][int(info["difficulty"]) - 1])
	if map.road[i]:
		m *= float(data.rules["road_multiplier"])
	return m
