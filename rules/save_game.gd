class_name SaveGame
extends RefCounted
## Saving and loading a game in progress (ROADMAP M4 session 32; user's answers,
## 2026-11-10): 3 slots, no autosave, never mid-battle. The map itself isn't saved: it
## rebuilds from its seed and the configurator's map settings, checked against a hash
## of its terrain; the share code comes along for the screens that show it. Everything that changes in play is: buildings, squads, units,
## items, gold, cards, tech, the clock, every RNG stream's position and the log.
## Units and squads are written once each, in tables, and referred to by index, so
## shared references (a squad on the map and in an army cell, the Opinion Leader)
## come back shared. Written with store_var, which keeps 64-bit ints exact (RNG states).

const FORMAT := "landwar-save"
const VERSION := 1
const SLOTS := 3
static var dir := "user://saves/"  # tests point this elsewhere

# GameState fields saved as they are (plain values only).
const STATE_FIELDS := ["settings", "gold", "reputation", "enemy_start_squads", "_warbands", "revealed", "_contact_until",
		"noon_report", "ledger", "cards", "next_card", "card_offer", "tech", "tech_points", "debt_noons",
		"enemy_squads_defeated", "debug_reveal", "debug_freeze_ai", "debug_force", "debug_fairness", "intel",
		"_towns_held_since", "_rare_declined", "notes"]
# Squad fields that hold objects, handled by hand.
const SQUAD_REFS := ["units", "leader", "follow", "bonded_pairs", "tech", "bond_battles"]


static func path(slot: int) -> String:
	return dir + "slot%d.save" % slot


## Why the game can't be saved right now, or "" if it can.
static func blocker(state: GameState) -> String:
	if state.game_over != "":
		return "The map is over."
	if state.pending or not state.pending_recruit.is_empty() or not state.pending_rare.is_empty():
		return "Not in the middle of a battle or an encounter."
	return ""


# --- Writing ---------------------------------------------------------------------------

## The whole game as plain values, with the configurator the map was made from.
static func to_dict(state: GameState, config: GameConfig) -> Dictionary:
	var units: Array[Unit] = []
	var squads: Array[Squad] = []
	for s in state.squads:
		_add_squad(s, squads, units)
	for s in state.army.cells:
		if s:
			_add_squad(s, squads, units)
	for u in state.army.pool + state.enemy_pool + state._rare_units.values():
		if u not in units:
			units.append(u)
	if state.opinion_leader and state.opinion_leader not in units:
		units.append(state.opinion_leader)
	var d := {
		"format": FORMAT, "version": VERSION, "code": config.to_code(), "map_seed": state.map.seed,
		"map_overrides": config.map_overrides(), "terrain_hash": hash(state.map.terrain),
		"meta": summary_of(state),
		"buildings": state.map.buildings.duplicate(true),
		"units": units.map(func(u: Unit): return _unit_dict(u)),
		"squads": squads.map(func(s: Squad): return _squad_dict(s, units, squads)),
		"on_map": state.squads.map(func(s: Squad): return squads.find(s)),
		"cells": state.army.cells.map(func(s): return squads.find(s) if s else -1),
		"pool": state.army.pool.map(func(u: Unit): return units.find(u)),
		"enemy_pool": state.enemy_pool.map(func(u: Unit): return units.find(u)),
		"opinion_leader": units.find(state.opinion_leader) if state.opinion_leader else -1,
		"rare_units": _map_values(state._rare_units, func(u: Unit): return units.find(u)),
		"army": {"items": state.army.items.duplicate(true), "next_item": state.army._next_item,
				"supplies": state.army.supplies.duplicate(true), "base_slots": state.army.base_slots},
		"clock": {"tick": state.clock.tick, "paused": state.clock.paused, "speed_index": state.clock.speed_index,
				"frozen": state.clock.frozen, "frozen_offset": state.clock._frozen_offset},
		"rng": _rng_dict(state.rng),
		"names": state.names.used.duplicate(),
		"log": state.log.entries.map(func(e: Dictionary): return _plain(e)),
		"state": {},
	}
	for f in STATE_FIELDS:
		d["state"][f] = _plain(state.get(f))
	return d


## What a slot's list shows: the day and time, gold, squads and when it was saved.
static func summary_of(state: GameState) -> Dictionary:
	return {"day": state.clock.day(), "time": "%02d:%02d" % [state.clock.minute_of_day() / 60, state.clock.minute_of_day() % 60],
			"gold": state.gold, "squads": state.player_squads().size(), "seed": state.map.seed,
			"size": "%dx%d" % [state.map.width, state.map.height], "saved": Time.get_datetime_string_from_system(false, true)}


## Writes the game to a slot. Returns "" or what went wrong.
static func write(slot: int, state: GameState, config: GameConfig) -> String:
	var why := blocker(state)
	if why != "":
		return why
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(path(slot), FileAccess.WRITE)
	if f == null:
		return "Couldn't write the save file (%s)." % error_string(FileAccess.get_open_error())
	f.store_var(to_dict(state, config))
	f.close()
	state.log.add(state.clock.tick, "system", "Game saved to slot %d." % slot)
	return ""


static func _add_squad(s: Squad, squads: Array[Squad], units: Array[Unit]) -> void:
	if s in squads:
		return
	squads.append(s)
	for u in s.units:
		if u not in units:
			units.append(u)


static func _unit_dict(u: Unit) -> Dictionary:
	var d := _props(u, [])
	d["iid"] = u.get_instance_id()  # bond keys are built from instance ids; remapped on load
	return d


static func _squad_dict(s: Squad, units: Array[Unit], squads: Array[Squad]) -> Dictionary:
	var d := _props(s, SQUAD_REFS)
	d["units"] = s.units.map(func(u: Unit): return units.find(u))
	d["leader"] = units.find(s.leader) if s.leader else -1
	d["follow"] = squads.find(s.follow) if s.follow else -1
	d["bonded_pairs"] = s.bonded_pairs.map(func(p: Array): return [units.find(p[0]), units.find(p[1])])
	d["shares_tech"] = s.side == "player"
	d["tech"] = s.tech.duplicate()
	d["bond_battles"] = s.bond_battles.duplicate()
	return d


static func _rng_dict(r: RngStreams) -> Dictionary:
	var out := {"seed": r.seed, "streams": {}}
	for name in r._streams:
		out["streams"][name] = r._streams[name].state
	return out


## An object's script variables, deep-copied, skipping `skip`.
static func _props(o: Object, skip: Array) -> Dictionary:
	var d := {}
	for p in o.get_property_list():
		if p["usage"] & PROPERTY_USAGE_SCRIPT_VARIABLE and p["name"] not in skip:
			d[p["name"]] = _plain(o.get(p["name"]))
	return d


## A deep copy with any stray object turned into text, so the file holds plain values.
static func _plain(v: Variant) -> Variant:
	if v is Object:
		return str(v)
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _plain(v[k])
		return d
	if v is Array:
		return v.map(func(x): return _plain(x))
	return v


static func _map_values(d: Dictionary, f: Callable) -> Dictionary:
	var out := {}
	for k in d:
		out[k] = f.call(d[k])
	return out


# --- Reading ---------------------------------------------------------------------------

## The slot saved most recently (for Continue), or -1 if none is in use.
static func latest_slot() -> int:
	var best := -1
	var when := ""
	for slot in range(1, SLOTS + 1):
		var meta := summary(slot)
		if not meta.is_empty() and str(meta["saved"]) > when:
			best = slot
			when = str(meta["saved"])
	return best


## A slot's summary for the list, or {} if it's empty or unreadable.
static func summary(slot: int) -> Dictionary:
	var d = _read_file(slot)
	return d["meta"] if d is Dictionary else {}


## Loads a slot: {"state": GameState, "config": GameConfig}, or why not as a String.
static func read(slot: int, data: GameData, game_log: GameLog) -> Variant:
	var d = _read_file(slot)
	if d is String:
		return d
	return from_dict(data, d, game_log)


static func _read_file(slot: int) -> Variant:
	if not FileAccess.file_exists(path(slot)):
		return "That slot is empty."
	var f := FileAccess.open(path(slot), FileAccess.READ)
	if f == null:
		return "Couldn't open the save file."
	var d = f.get_var(false)
	f.close()
	if not (d is Dictionary) or d.get("format", "") != FORMAT:
		return "This file isn't a Landwar save, or it's damaged."
	if int(d.get("version", 0)) != VERSION:
		return "This save comes from a different version of the game and can't be loaded."
	return d


## Rebuilds a game from to_dict()'s output: {"state", "config"}, or why not as a String.
static func from_dict(data: GameData, d: Dictionary, game_log: GameLog) -> Variant:
	var config := GameConfig.from_code(data, str(d.get("code", "")))
	if config == null:
		return "This save's map settings can't be read."
	var map := MapGen.generate(data, int(d["map_seed"]), d["map_overrides"])
	if hash(map.terrain) != d["terrain_hash"]:
		return "This save's map no longer generates the same way (the game changed since); it can't be loaded."
	var state := GameState.new(data, map, GameLog.new(), d["state"]["settings"])
	state.log = game_log
	game_log.entries.assign(d["log"])
	map.buildings.assign(d["buildings"].duplicate(true))
	state._building_at.clear()
	for i in map.buildings.size():
		state._building_at[map.buildings[i]["hex"]] = i
	# Units, then the army's items, which units wear by reference.
	var units: Array[Unit] = []
	var by_iid := {}
	for ud in d["units"]:
		var u := Unit.new()
		_apply(u, ud, ["iid"])
		units.append(u)
		by_iid[int(ud["iid"])] = u
	state.army.items.assign(d["army"]["items"].duplicate(true))
	state.army._next_item = int(d["army"]["next_item"])
	state.army.supplies = d["army"]["supplies"].duplicate(true)
	state.army.base_slots = int(d["army"]["base_slots"])
	var by_uid := {}
	for item in state.army.items:
		by_uid[int(item["uid"])] = item
	for u in units:
		for slot in u.items.keys():
			u.items[slot] = by_uid.get(int(u.items[slot]["uid"]), u.items[slot])
	# Squads.
	var squads: Array[Squad] = []
	for sd in d["squads"]:
		var s := Squad.new(int(sd["id"]), str(sd["name"]), int(sd["hex"]))
		_apply(s, sd, SQUAD_REFS + ["shares_tech"])
		for i in sd["units"]:
			s.units.append(units[i])
		s.leader = units[sd["leader"]] if sd["leader"] >= 0 else null
		s.tech = state.tech if sd["shares_tech"] else sd["tech"].duplicate()
		for p in sd["bonded_pairs"]:
			s.bonded_pairs.append([units[p[0]], units[p[1]]])
		for key in sd["bond_battles"]:
			var ids: PackedStringArray = str(key).split(":")
			var a: Unit = by_iid.get(int(ids[0]))
			var b: Unit = by_iid.get(int(ids[1]))
			if a and b:
				var k := "%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]
				s.bond_battles[k] = sd["bond_battles"][key]
		squads.append(s)
	for i in squads.size():
		var f: int = d["squads"][i]["follow"]
		squads[i].follow = squads[f] if f >= 0 else null
	state.squads.assign(d["on_map"].map(func(i: int): return squads[i]))
	state.army.cells = d["cells"].map(func(i: int): return squads[i] if i >= 0 else null)
	state.army.pool.assign(d["pool"].map(func(i: int): return units[i]))
	state.enemy_pool.assign(d["enemy_pool"].map(func(i: int): return units[i]))
	state.opinion_leader = units[d["opinion_leader"]] if d["opinion_leader"] >= 0 else null
	state._rare_units = _map_values(d["rare_units"], func(i: int): return units[i])
	# Everything else.
	for f in STATE_FIELDS:
		if not d["state"].has(f):
			continue  # a save from before the field existed (the notifications log): keep the new game's value
		var v = d["state"][f]
		var cur = state.get(f)
		if cur is Array:
			cur.assign(v)  # keeps typed arrays typed, and tech shared with the army and squads
		else:
			state.set(f, v.duplicate(true) if v is Dictionary else v)
	var c: Dictionary = d["clock"]
	state.clock.tick = int(c["tick"])
	state.clock.paused = bool(c["paused"])
	state.clock.speed_index = int(c["speed_index"])
	state.clock.frozen = bool(c["frozen"])
	state.clock._frozen_offset = int(c["frozen_offset"])
	state.rng = RngStreams.new(int(d["rng"]["seed"]))
	for name in d["rng"]["streams"]:
		state.rng.get_stream(name).state = d["rng"]["streams"][name]
	state.names.used = d["names"].duplicate()
	return {"state": state, "config": config}


static func _apply(o: Object, d: Dictionary, skip: Array) -> void:
	for k in d:
		if k in skip:
			continue
		var cur = o.get(k)
		var v = d[k]
		if cur is Array and v is Array:
			cur.assign(v.duplicate(true))
		else:
			o.set(k, v.duplicate(true) if v is Dictionary else v)
