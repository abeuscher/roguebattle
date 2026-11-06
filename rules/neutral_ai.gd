class_name NeutralAI
extends RefCounted
## Neutral map AI (SPEC §6.7): a roamer patrols a radius around its lair and
## chases the nearest living squad, player or enemy, that comes within it;
## otherwise it wanders inside that radius. Contact (GameState._check_contact)
## handles the actual fight once it catches up.


## The hex an idle roamer should move to, or -1 to hold its ground.
static func target_hex(state: GameState, s: Squad) -> int:
	var radius := int(state.data.neutrals["patrol_radius"])
	var lair := state.map.hex_at(s.lair_hex)
	var prey := _nearest_in_range(state, s, lair, radius)
	if prey >= 0:
		return prey
	return _wander(state, s, lair, radius)


## The closest non-neutral living squad within `radius` of the lair, or -1.
static func _nearest_in_range(state: GameState, s: Squad, lair: Vector2i, radius: int) -> int:
	var from := state.map.hex_at(s.hex)
	var best := -1
	var best_dist := -1
	for o in state.squads:
		if o.side == "neutral" or o.living().is_empty():
			continue
		var at := state.map.hex_at(o.hex)
		if Hex.distance(lair, at) > radius:
			continue
		var d := Hex.distance(from, at)
		if best < 0 or d < best_dist:
			best = o.hex
			best_dist = d
	return best


## A random walk of up to `radius` steps from the lair, stopping at the map edge
## or the first impassable hex; always within the patrol radius since it starts
## at the lair and each step moves 1 hex.
static func _wander(state: GameState, s: Squad, lair: Vector2i, radius: int) -> int:
	var r := state.rng.get_stream("neutral_ai")
	var i := state.map.index_of(lair)
	for step in r.randi_range(0, radius):
		var options := state.map.neighbor_indices(i)
		if options.is_empty():
			break
		var n: int = options[r.randi() % options.size()]
		if Movement.hex_multiplier(state.map, state.data, n) == INF:
			break
		i = n
	return i
