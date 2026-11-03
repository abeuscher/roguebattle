class_name MapOverlay
## Debug overlays (SPEC §19.2): one color per hex, transparent where there is nothing to show.

const MODES := ["", "terrain", "movement", "roads", "quadrants", "lair_danger"]
const NAMES := {"": "none", "terrain": "terrain", "movement": "movement cost", "roads": "roads",
		"quadrants": "buildings per quadrant", "lair_danger": "lair danger"}
const QUADRANT_TINTS := [Color(0.25, 0.45, 0.95, 0.28), Color(0.95, 0.55, 0.15, 0.28),
		Color(0.25, 0.8, 0.35, 0.28), Color(0.7, 0.3, 0.85, 0.28)]


static func colors(mode: String, map: MapData, data: GameData) -> PackedColorArray:
	var out := PackedColorArray()
	out.resize(map.size())
	match mode:
		"terrain":
			for i in map.size():
				out[i] = Color(data.terrains[map.terrain[i]]["color"])
		"movement":
			# Cost for a ground squad with no native terrain: green x0.75 (road) to red x2; dark red impassable.
			for i in map.size():
				var m := Movement.hex_multiplier(map, data, i)
				if m == INF:
					out[i] = Color(0.45, 0.05, 0.05, 0.75)
				else:
					var t := clampf((m - 0.75) / 1.25, 0.0, 1.0)
					out[i] = Color(0.2, 0.75, 0.25, 0.85).lerp(Color(0.95, 0.85, 0.2, 0.85), minf(t * 2.0, 1.0)) \
							.lerp(Color(0.9, 0.2, 0.15, 0.85), maxf(t * 2.0 - 1.0, 0.0))
		"roads":
			for i in map.size():
				if map.road[i]:
					var bridge: bool = data.terrains[map.terrain[i]].get("impassable", false)
					out[i] = Color(1.0, 0.55, 0.1, 0.95) if bridge else Color(1.0, 0.9, 0.2, 0.95)
				else:
					out[i] = Color(0, 0, 0, 0.45)
		"quadrants":
			for i in map.size():
				out[i] = QUADRANT_TINTS[map.quadrant(i)]
		"lair_danger":
			var r := 4
			for lair in map.lairs:
				var c := map.hex_at(lair["hex"])
				var color := Color(0.2, 0.8, 0.3, 0.7).lerp(Color(0.9, 0.15, 0.1, 0.7), lair["danger"])
				for dq in range(-r, r + 1):
					for dr in range(maxi(-r, -dq - r), mini(r, -dq + r) + 1):
						var h := c + Vector2i(dq, dr)
						if map.in_bounds(h):
							out[map.index_of(h)] = color
	return out


## Per quadrant (NW, NE, SW, SE): building type -> count.
static func quadrant_counts(map: MapData) -> Array:
	var out := [{}, {}, {}, {}]
	for b in map.buildings:
		var q: Dictionary = out[map.quadrant(b["hex"])]
		q[b["type"]] = q.get(b["type"], 0) + 1
	return out


## A one-line legend for the HUD.
static func legend(mode: String, map: MapData) -> String:
	match mode:
		"movement":
			return "green x0.75 (road) → yellow → red x2, dark red impassable (ground squad, no native terrain)"
		"roads":
			return "yellow road, orange bridge"
		"quadrants":
			var parts := []
			var names := ["NW", "NE", "SW", "SE"]
			var counts := quadrant_counts(map)
			for q in 4:
				parts.append("%s: %d towns, %d towers, %d temples" % [names[q], counts[q].get("town", 0),
						counts[q].get("tower", 0), counts[q].get("temple", 0)])
			return " · ".join(parts)
		"lair_danger":
			return "around each lair: green near your base → red far away"
	return ""
