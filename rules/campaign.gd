class_name Campaign
extends RefCounted
## A campaign in progress (SPEC §25): which campaign, which chapter, and the army brought
## into that chapter. Campaigns are data files, `data/campaigns/<id>.json`, with a folder of
## the same name for their pictures, videos and sounds: a name, a description, opening and
## ending pages, and chapters in order, each a map (configurator values), its starting gold,
## and pages before it and after it is won. Pages are shown by StoryPages.
## The campaign saves itself at the start of each chapter (one file); that is also what
## Try again goes back to, so a retried map is the same map with the same army.

const DIR := "res://data/campaigns/"
const FORMAT := "landwar-campaign"
static var save_path := "user://saves/campaign.save"  # tests point this elsewhere

var id := ""
var info := {}  # the campaign file
var chapter := 0  # index into info.chapters
var seed := 0  # chapter n's map uses seed + n
var player_name := ""
var carry := {}  # the army brought into this chapter (carry_of); {} for the first, which starts fresh


## Every campaign file: [{id, name, description}], in name order.
static func list_all() -> Array:
	var out := []
	for f in DirAccess.get_files_at(DIR):
		if f.ends_with(".json"):
			var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + f))
			if d is Dictionary:
				out.append({"id": f.get_basename(), "name": str(d.get("name", f.get_basename())), "description": str(d.get("description", ""))})
	out.sort_custom(func(a, b): return a["name"] < b["name"])
	return out


## A new run of campaign `campaign_id` from its first chapter, or null if there's no such file.
static func begin(campaign_id: String, game_seed: int, name := "") -> Campaign:
	if not FileAccess.file_exists(DIR + campaign_id + ".json"):
		return null
	var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + campaign_id + ".json"))
	if not d is Dictionary:
		return null
	var c := Campaign.new()
	c.id = campaign_id
	c.info = d
	c.seed = game_seed
	c.player_name = name
	return c


func chapter_info() -> Dictionary:
	return info["chapters"][chapter]


func is_last() -> bool:
	return chapter >= info["chapters"].size() - 1


## A media path in a page, relative to the campaign's folder, as a res:// path.
func media(file: String) -> String:
	return "%s%s/%s" % [DIR, id, file]


## The chapter's map: the configurator's defaults with the chapter's values over them (the
## map type first, as it resets the map fields), in single map mode, whose rules a campaign
## keeps (SPEC §25).
func config(data: GameData) -> GameConfig:
	var c := GameConfig.create(data, seed + chapter)
	var m: Dictionary = chapter_info().get("map", {})
	if m.has("preset"):
		c.set_value("preset", m["preset"])
	for k in m:
		c.set_value(k, m[k])
	c.set_value("mode", "single")
	c.player_name = player_name
	return c


## The game settings for the chapter's state: the config's, and which campaign and chapter.
func settings(data: GameData) -> Dictionary:
	var out := config(data).game_settings()
	out["campaign"] = id
	out["chapter"] = chapter
	return out


## Starts the chapter's army on a fresh state: chapter 1's is the single map's start;
## later ones, the army carried in (apply_carry). Gold is the chapter's own if it sets one.
func set_up(state: GameState) -> void:
	if carry.is_empty():
		state.setup_army()
	else:
		apply_carry(state, carry)
	if chapter_info().has("gold"):
		state.gold = int(chapter_info()["gold"])


## The chapter was won: the army goes on into the next one.
func advance(state: GameState) -> void:
	carry = carry_of(state)
	chapter += 1


# --- The army between maps (SPEC §25.4) ---------------------------------------------------

## What carries to the next map: every squad in the army with its units, the recruit pool,
## the Opinion Leader, items and supplies, tech, tech points, cards and reputation, as plain
## values (units and squads in tables by index, as SaveGame writes them).
static func carry_of(state: GameState) -> Dictionary:
	var units: Array[Unit] = []
	var squads: Array[Squad] = []
	for s in state.army.cells:
		if s:
			SaveGame._add_squad(s, squads, units)
	for u in state.army.pool:
		if u not in units:
			units.append(u)
	if state.opinion_leader and state.opinion_leader not in units:
		units.append(state.opinion_leader)
	return {
		"units": units.map(func(u: Unit): return SaveGame._unit_dict(u)),
		"squads": squads.map(func(s: Squad): return {"name": s.name, "units": s.units.map(func(u: Unit): return units.find(u)),
				"leader": units.find(s.leader) if s.leader else -1, "tactic": s.tactic, "base_slots": s.base_slots,
				"bonded_pairs": s.bonded_pairs.map(func(p: Array): return [units.find(p[0]), units.find(p[1])]),
				"bond_battles": s.bond_battles.duplicate()}),
		"cells": state.army.cells.map(func(s): return squads.find(s) if s else -1),
		"pool": state.army.pool.map(func(u: Unit): return units.find(u)),
		"opinion_leader": units.find(state.opinion_leader) if state.opinion_leader else -1,
		"army": {"items": state.army.items.duplicate(true), "next_item": state.army._next_item,
				"supplies": state.army.supplies.duplicate(true), "base_slots": state.army.base_slots},
		"tech": state.tech.duplicate(), "tech_points": state.tech_points, "cards": state.cards.duplicate(),
		"reputation": state.reputation, "names": state.names.used.duplicate(),
	}


## Puts a carried army on a fresh state: everyone healed and revived, poison gone, morale
## back to its start; squads wait at the Player Base off the map, the Opinion Leader's on it,
## as a map's start has it.
static func apply_carry(state: GameState, d: Dictionary) -> void:
	var data := state.data
	var units: Array[Unit] = []
	var by_iid := {}
	for ud in d["units"]:
		var u := Unit.new()
		SaveGame._apply(u, ud, ["iid"])
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
		u.poison_left = 0
		u.hp = u.max_hp(data)
	state.tech.assign(d["tech"])  # shared with the army and its squads
	state.tech_points = int(d["tech_points"])
	state.cards.assign(d["cards"])
	state.reputation = int(d["reputation"])
	state.names.used = d["names"].duplicate()
	state.opinion_leader = units[d["opinion_leader"]] if d["opinion_leader"] >= 0 else null
	var squads: Array[Squad] = []
	for i in d["squads"].size():
		var sd: Dictionary = d["squads"][i]
		var s := Squad.new(i + 1, str(sd["name"]), -1)
		s.side = "player"
		s.tech = state.tech
		s.base_slots = int(sd["base_slots"])
		s.tactic = str(sd["tactic"])
		for k in sd["units"]:
			s.units.append(units[k])
		s.leader = units[sd["leader"]] if sd["leader"] >= 0 else null
		for p in sd["bonded_pairs"]:
			s.bonded_pairs.append([units[p[0]], units[p[1]]])
		for key in sd["bond_battles"]:  # keyed by instance ids, which are new now
			var ids: PackedStringArray = str(key).split(":")
			var a: Unit = by_iid.get(int(ids[0]))
			var b: Unit = by_iid.get(int(ids[1]))
			if a and b:
				s.bond_battles["%d:%d" % [mini(a.get_instance_id(), b.get_instance_id()), maxi(a.get_instance_id(), b.get_instance_id())]] = sd["bond_battles"][key]
		s.morale = int(data.rules["starting_morale"])
		s.refresh(data)
		squads.append(s)
	var cells: Array = d["cells"].map(func(i: int): return squads[i] if i >= 0 else null)
	if cells.size() < state.army.cells.size():
		cells.resize(state.army.cells.size())
	state.army.cells = cells
	for i in cells.size():
		if cells[i]:
			(cells[i] as Squad).id = i + 1
	var first: Squad = state.army.squad_of(state.opinion_leader) if state.opinion_leader else null
	if first:
		first.hex = state.map.player_base
		state.squads.append(first)
	state.army.pool.assign(d["pool"].map(func(i: int): return units[i]))


# --- Saving (SPEC §25.5) -------------------------------------------------------------------

func to_dict() -> Dictionary:
	return {"format": FORMAT, "id": id, "chapter": chapter, "seed": seed, "name": player_name, "carry": carry,
			"saved": Time.get_datetime_string_from_system(false, true)}


## Writes the campaign's progress (at a chapter's start). "" or what went wrong.
func save() -> String:
	DirAccess.make_dir_recursive_absolute(save_path.get_base_dir())
	var f := FileAccess.open(save_path, FileAccess.WRITE)
	if f == null:
		return "Couldn't write the campaign save (%s)." % error_string(FileAccess.get_open_error())
	f.store_var(to_dict())
	f.close()
	return ""


## The saved campaign, or null if there's none (or it can't be read).
static func load_saved() -> Campaign:
	var d := saved_meta()
	if d.is_empty():
		return null
	var c := begin(str(d["id"]), int(d["seed"]), str(d["name"]))
	if c == null or int(d["chapter"]) >= c.info["chapters"].size():
		return null
	c.chapter = int(d["chapter"])
	c.carry = d["carry"]
	return c


## The campaign save's contents ({} if none), for Continue to weigh against the slots.
static func saved_meta() -> Dictionary:
	if not FileAccess.file_exists(save_path):
		return {}
	var f := FileAccess.open(save_path, FileAccess.READ)
	if f == null:
		return {}
	var d: Variant = f.get_var(false)
	f.close()
	return d if d is Dictionary and d.get("format", "") == FORMAT else {}
