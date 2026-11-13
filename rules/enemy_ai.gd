class_name EnemyAI
extends RefCounted
## Enemy map AI (SPEC §12.3, §17), map-level targeting only: where an idle enemy
## squad should go. (GameState first sends a squad that has lost half or more of its
## units home to the Enemy Base, where its fallen revive.) The Warlord and the base
## guard hold the base; contact and ranged attacks handle anything that comes close.
## Field squads (user's playtest notes, 2026-11-10) take buildings: on a building the
## enemy doesn't hold, a field squad stays until it's taken; otherwise it scores holding
## where it is against moving on to each neutral or player-held town or tower no other
## enemy squad is after, makes the better choice most of the time and flips a coin
## the rest (weights in data/ai.json "field"). In-battle tactic and retreat weights
## come later.


## The hex an idle enemy squad should move to, or -1 to stay where it is.
static func target_hex(state: GameState, s: Squad) -> int:
	if s.role == "raider":
		return -1 if state.clock.tick < s.think_at else raid_target(state, s)
	if s.role != "field":
		return s.post if s.post != s.hex else -1
	var here := state.building_at(s.hex)
	if _takeable(state, here) and here["owner"] != "enemy":
		return -1  # taking it: capture needs the squad to stand still
	if state.clock.tick < s.think_at:
		return -1
	var f: Dictionary = state.data.ai["field"]
	var hold := hold_score(state, s)
	var best := best_move(state, s)
	var stay: bool = hold >= best[1]
	if state.rng.get_stream("enemy_ai").randf() >= float(f["logic_chance"]):
		stay = state.rng.get_stream("enemy_ai").randf() < 0.5
	if best[0] < 0 or (stay and hold > 0.0):
		s.ai_mode = "hold"
		s.goal = -1
		s.think_at = state.clock.tick + int(f["rethink_ticks"])
		return -1
	s.ai_mode = "move"
	s.goal = best[0]
	return best[0]


## Quick start's Raiders (user, 2026-11-13): the nearest town you hold, or your base if
## you hold none; -1 once standing on it (taking it needs the squad to stand still).
static func raid_target(state: GameState, s: Squad) -> int:
	var at := state.map.hex_at(s.hex)
	var best := state.map.player_base
	var best_d := INF
	for b in state.map.buildings:
		if b["type"] == "town" and b["owner"] == "player" and not b["hidden"]:
			var dist := float(Hex.distance(at, state.map.hex_at(b["hex"])))
			if dist < best_d:
				best_d = dist
				best = b["hex"]
	return -1 if best == s.hex else best


## A town or tower (the buildings worth taking for income and ground).
static func _takeable(state: GameState, b: Dictionary) -> bool:
	return not b.is_empty() and state.data.ai["field"]["type_value"].has(b["type"])


## What a building is worth to the enemy: its type, more toward the middle of the map
## between the two bases, double if the player holds it.
static func value(state: GameState, b: Dictionary) -> float:
	var f: Dictionary = state.data.ai["field"]
	var v := float(f["type_value"][b["type"]]) * (1.0 + float(f["middle_weight"]) * middle(state.map, b["hex"]))
	return v * float(f["player_held"]) if b["owner"] == "player" else v


## How central a hex is between the two bases: 0 at a base, 1 midway.
static func middle(m: MapData, i: int) -> float:
	var at := m.hex_at(i)
	var de := float(Hex.distance(at, m.hex_at(m.enemy_base)))
	var dp := float(Hex.distance(at, m.hex_at(m.player_base)))
	return 1.0 - absf(de - dp) / maxf(1.0, de + dp)


## Holding the building it stands on: worth more the more player strength is near,
## nothing if it isn't an enemy-held town or tower or another enemy squad holds it too.
static func hold_score(state: GameState, s: Squad) -> float:
	var b := state.building_at(s.hex)
	if not _takeable(state, b) or b["owner"] != "enemy":
		return 0.0
	for o in state.squads:
		if o != s and o.side == "enemy" and o.hex == s.hex and not o.living().is_empty():
			return 0.0
	var f: Dictionary = state.data.ai["field"]
	var near := 0.0
	var at := state.map.hex_at(s.hex)
	for o in state.squads:
		if o.side == "player" and not o.living().is_empty() and Hex.distance(at, state.map.hex_at(o.hex)) <= int(f["threat_radius"]):
			near += Threat.squad(state.data, o)
	var danger := minf(1.0, near / maxf(1.0, Threat.squad(state.data, s)))
	return value(state, b) * (float(f["hold_base"]) + float(f["threat_weight"]) * danger)


## The best building to move to and its score: [hex, score], or [-1, 0] if there's none.
static func best_move(state: GameState, s: Squad) -> Array:
	var f: Dictionary = state.data.ai["field"]
	var reach := float(f["distance_range"]) * maxf(1.0, state.map.width / 400.0)
	var taken := {}
	for o in state.squads:
		if o != s and o.side == "enemy" and o.role == "field" and not o.living().is_empty():
			taken[o.goal if o.is_moving() else o.hex] = true
	var at := state.map.hex_at(s.hex)
	var best := [-1, 0.0]
	for b in state.map.buildings:
		if not _takeable(state, b) or b["owner"] == "enemy" or b["hex"] == s.hex or taken.has(b["hex"]) or s.unreachable.has(b["hex"]) or b.get("away", false):
			continue
		var score := value(state, b) / (1.0 + Hex.distance(at, state.map.hex_at(b["hex"])) / reach)
		if score > best[1]:
			best = [b["hex"], score]
	return best
