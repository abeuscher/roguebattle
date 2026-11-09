class_name EnemyAI
extends RefCounted
## Enemy map AI (SPEC §12.3, §17), map-level targeting only: where an idle
## enemy squad should go, by role. (GameState first sends a squad that has lost
## half or more of its units home to the Enemy Base, where its fallen revive.) The leader, base guard and garrisons hold
## their post; the existing contact and ranged-attack rules handle anything
## that comes close, so they need no AI of their own. Raiders, and wildcards
## that rolled Attack, march on the weakest player-held town or tower (or the
## Player Base if the player holds none); wildcards that rolled Defend march
## on the nearest enemy-held building a player squad is standing in, and
## otherwise hold their ground. In-battle tactic and retreat weights are
## deferred to a later AI session.

const MOVING_ROLES := ["raider", "wildcard"]


## The hex an idle enemy squad should move to, or -1 to hold its ground. A holding
## squad that went home to revive heads back to its post.
static func target_hex(state: GameState, s: Squad) -> int:
	if s.role not in MOVING_ROLES:
		return s.post if s.post != s.hex else -1
	if s.role == "wildcard" and s.ai_mode == "defend":
		return _nearest_threatened_building_hex(state, s)
	return _weakest_player_building_hex(state)


## The player-held town or tower with the least Threat defending it (0 for an
## undefended one), or the Player Base if the player holds none (§17).
static func _weakest_player_building_hex(state: GameState) -> int:
	var data := state.data
	var held: Array = state.map.buildings.filter(func(b): return b["owner"] == "player" and b["type"] in data.rules["economy"]["income_buildings"])
	if held.is_empty():
		return state.map.player_base
	var best_hex := -1
	var best_threat := INF
	for b in held:
		var t := 0.0
		for sq in state.squads:
			if sq.side == "player" and sq.hex == b["hex"] and not sq.living().is_empty():
				t += Threat.squad(data, sq)
		if best_hex < 0 or t < best_threat:
			best_threat = t
			best_hex = b["hex"]
	return best_hex


## The nearest enemy-held building a living player squad stands on (being
## fought for or liberated), or -1 if nothing is threatened.
static func _nearest_threatened_building_hex(state: GameState, s: Squad) -> int:
	var best := -1
	var best_dist := -1
	var from := state.map.hex_at(s.hex)
	for b in state.map.buildings:
		if b["owner"] != "enemy":
			continue
		if not state.squads.any(func(sq: Squad): return sq.side == "player" and sq.hex == b["hex"] and not sq.living().is_empty()):
			continue
		var d := Hex.distance(from, state.map.hex_at(b["hex"]))
		if best < 0 or d < best_dist:
			best = b["hex"]
			best_dist = d
	return best
