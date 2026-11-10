class_name GameState
extends RefCounted
## Everything one running map needs. Plain rules: scenes read it and pass input in.

var data: GameData
var map: MapData
var rng: RngStreams
var clock: GameClock
var log: GameLog
var pathfinder: Pathfinder
var squads: Array[Squad] = []  # every squad on the map
var army: Army  # the player's squads, on the map or at base, the recruit pool and items
var names: NameBook
var settings: Dictionary  # victory, defeat, squad cap, fairness (from the configurator)
var gold: int
var reputation: int
var pending: Battle  # a battle waiting to be fought; the map holds until it's resolved
var pending_recruit := {}  # {player, neutral, defender}: a Recruit-or-Fight choice waiting on the player (§16)
var liberations: Array[Dictionary] = []  # {building, card}, oldest first: liberations the UI hasn't shown yet
var revealed := {}  # building index -> true for hidden sites and lairs a squad has seen
var _contact_until := {}  # "player id:enemy id" -> tick before which the pair won't fight again
var _moved := {}  # squads that entered a new hex this tick
var _building_at := {}  # hex -> index in map.buildings
var noon_report := ""  # the last noon's ledger, for the HUD to show once
var cards: Array[String] = []  # the hand: card ids (§13)
var next_card := ""  # the next card to be drawn, rolled ahead so Foresight can preview it
var card_offer: Array[String] = []  # cards to choose one from (a Seer or Oracle drew), shown by the HUD
var tech: Array[String] = []  # tech nodes bought (§14), shared with the army and its squads
var tech_points := 0
var game_over := ""  # "", "victory" or "defeat" (§6.8), once a condition is met
var game_over_reason := ""  # the sentence the end screen shows
var enemy_squads_defeated := 0  # wiped or driven off, for "defeat N enemy squads" (§6.8)
# Debug panel switches (SPEC §19.2); never set in the real game.
var debug_reveal := false  # every squad shows, whatever the sight radius
var debug_freeze_ai := false  # enemy and neutral squads take no orders and stand still
var debug_force := ""  # "", "win", "loss" or "draw": every battle a player squad joins ends that way
var debug_fairness := {"two_dice": true, "ramping_crits": true, "streak_breaker": true, "spread": true}
var last_battle := {}  # the last player battle as it began, for DebugTools.replay()
var _towns_held_since := -1  # tick the player started holding the required share of towns continuously; -1 if not currently


func _init(game_data: GameData, game_map: MapData, game_log: GameLog, game_settings := {}) -> void:
	data = game_data
	map = game_map
	log = game_log
	settings = game_settings
	rng = RngStreams.new(map.seed)
	clock = GameClock.new(data.rules, int(data.rules["start_minute"]))
	pathfinder = Pathfinder.new(map, data)
	names = NameBook.new(data)
	gold = int(data.rules["starting_gold"])
	reputation = int(data.rules["starting_reputation"])
	army = Army.new(data)
	army.tech = tech
	tech_points = int(data.tech["start_points"])
	for i in map.buildings.size():
		var b: Dictionary = map.buildings[i]
		b["owner"] = data.buildings[b["type"]].get("owner", "neutral")
		b["away"] = false  # nomads that moved out of sight until the next half day
		_building_at[b["hex"]] = i
	log.add(clock.tick, "system", "New map: seed %d, %s %dx%d." % [map.seed, map.settings["preset"], map.width, map.height],
			-1, {"settings": map.settings, "game": settings})


## Runs the simulation for one tick. Stops early if two hostile squads meet:
## `pending` then holds the battle until resolve_pending(). Also stops for good
## once `game_over` is set (§6.8).
func step() -> void:
	if pending or not pending_recruit.is_empty() or game_over != "":
		return
	for event in clock.step():
		_clock_event(event)
	_moved.clear()
	if not debug_freeze_ai:
		_run_enemy_ai()
		_run_neutral_ai()
	for s in squads.duplicate():
		if debug_freeze_ai and s.side != "player":
			continue
		_move(s)
		if s.entering_base and s.hex == map.player_base:
			return_to_base(s)
	_capture()
	_reveal_sites()
	_check_contact()
	_check_game_over()


## Daily rest, nomads every half day, the noon ledger (§7).
func _clock_event(event: String) -> void:
	if event == "new_day":
		log.add(clock.tick, "system", "Day %d begins." % clock.day())
		_rest()
		_loyalty_day()
	elif event == "half_day":
		_move_nomads()
	if event == "noon":
		_noon()


## A squad of freshly rolled units. `members` lists [class name, row] pairs;
## units that don't fit are skipped. Player squads are numbered from 1, others from 101.
func add_squad(squad_name: String, at_hex: int, members: Array, side := "player") -> Squad:
	var number := 1 + squads.filter(func(o: Squad): return o.side == side).size() + (0 if side == "player" else 100)
	var s := _form(number, squad_name, at_hex, members, side)
	squads.append(s)
	return s


## Map 1's starting army (SPEC §18): 6 Serf-line squads from Map1Setup fill the
## first cells; the Opinion Leader's (cell 0) is the only one that starts on the
## map, at the Player Base (§8.4). 3 random cards complete the starting state
## (starting gold and tech points are set in _init).
## `wide_roster_count`, when > 0, is a developer override (Battlemap's
## --wide-roster) that swaps in Map1Setup.build_wide_roster() for playtesting
## unit variety; it isn't part of the real game.
func setup_army(wide_roster_count := 0) -> void:
	var built := Map1Setup.build_wide_roster(data, rng.get_stream("army_setup"), wide_roster_count) if wide_roster_count > 0 \
			else Map1Setup.build(data, rng.get_stream("army_setup"))
	for i in built.size():
		var s := _form(i + 1, "", map.player_base if i == 0 else -1, built[i], "player")
		s.balance_rows(data)
		army.cells[i] = s
		if i == 0:
			squads.append(s)
	for i in int(data.cards["start"]):
		draw_card(null)
	_starting_kit()


## The starting kit (user's playtest notes, 2026-11-10; rules.json "starting_kit"):
## a few random items that need no tech, plus supplies.
func _starting_kit() -> void:
	var kit: Dictionary = data.rules["starting_kit"]
	var r := rng.get_stream("army_setup")
	var basic: Array = data.items["items"].keys().filter(func(id): return not data.items["items"][id].has("requires"))
	for i in int(kit["items"]):
		army.add_item(basic[r.randi() % basic.size()])
	for id in kit["supplies"]:
		army.supplies[id] = int(army.supplies.get(id, 0)) + int(kit["supplies"][id])


## Debug only (the debug panel's Wide roster button): replaces every player
## squad, on the map or at base, with a fresh Map1Setup.build_wide_roster() of
## `count` squads. Gold, tech points and cards are untouched. Not part of the
## real game.
func reroll_wide_roster(count: int) -> void:
	for s in player_squads().duplicate():
		squads.erase(s)
	for i in army.cells.size():
		if army.cells[i] and army.cells[i].side == "player":
			army.cells[i] = null
	var built := Map1Setup.build_wide_roster(data, rng.get_stream("army_setup"), count)
	for i in built.size():
		var s := _form(i + 1, "", map.player_base if i == 0 else -1, built[i], "player")
		s.balance_rows(data)
		army.cells[i] = s
		if i == 0:
			squads.append(s)


# --- Buildings (SPEC §6.5) ---------------------------------------------------------------

## The building on a hex, or {} if none (hidden sites count only once revealed;
## nomads that moved out of sight don't count).
func building_at(i: int) -> Dictionary:
	if not _building_at.has(i):
		return {}
	var b: Dictionary = map.buildings[_building_at[i]]
	if b["away"] or (b["hidden"] and not revealed.has(_building_at[i])):
		return {}
	return b


## A building's numbers for a squad: [defense, HP healed per day]. Towns and towers
## (and nomads, as towns) give more to squads of their alignment; a base gives its
## current owner's side the bonus — a captured base (§6.8) gives it to its new owner.
func building_effect(b: Dictionary, s: Squad) -> Array:
	var info: Dictionary = data.buildings[b["type"]]
	if info.has("own_base"):
		return [float(info["own_base"]["defense"]), float(info["own_base"]["rest"])] if b["owner"] == s.side else [0.0, 0.0]
	if not info.has("defense"):
		return [0.0, 0.0]
	var k := 1 if info.get("aligned", "") == s.alignment_band(data) else 0
	return [float(info["defense"][k]), float(info["rest"][k])]


func building_defense(s: Squad) -> float:
	var b := building_at(s.hex)
	return building_effect(b, s)[0] if not b.is_empty() else 0.0


## Liberation and capture (§6.5): a squad with a living ground unit that stays in a
## building it doesn't already hold for 60 ticks takes it; Sapper lines take it twice
## as fast. Works both ways (§6.8): the enemy can retake a liberated town or tower, or
## take the Player Base for a defeat, just as the player liberates an enemy-held one or
## takes the Enemy Base. A player capture keeps its full liberation flavor (bonus gold,
## reputation, alignment, a card); an enemy capture just flips the owner and log line.
func _capture() -> void:
	var c: Dictionary = data.rules["capture"]
	for s in squads:
		if s.side == "neutral":
			continue
		var b := building_at(s.hex)
		if s.is_moving() or b.is_empty() or not data.buildings[b["type"]].get("capturable", false) or b["owner"] == s.side \
				or not s.living().any(func(u: Unit): return not u.has_tag(data, "flyer")):
			s.capture_ticks = 0.0
			continue
		var sapper := s.living().any(func(u: Unit): return u.has_tag(data, "sapper"))
		s.capture_ticks += float(c["sapper_speed"]) if sapper else 1.0
		if s.capture_ticks >= float(c["ticks"]):
			s.capture_ticks = 0.0
			b["owner"] = s.side
			var what: String = data.buildings[b["type"]]["name"].to_lower()
			if s.side == "player":
				log.add(clock.tick, "map", "%s liberates the %s at %s." % [s.name, what, map.hex_at(s.hex)], s.id)
				var bonus := liberation_bonus()
				gold += bonus
				log.add(clock.tick, "economy", "Liberation bonus: %d gold." % bonus, s.id, {"reputation": reputation})
				_liberated(s, b)
			else:
				log.add(clock.tick, "map", "%s captures the %s at %s." % [s.name, what, map.hex_at(s.hex)], s.id)
				change_morale(s, int(data.battle["morale"]["liberation"]), "capturing a %s" % what)


## Standing changes for a liberation (§9.5, §9.6, §10): reputation by the squad's
## alignment, +5 charisma for a leader whose alignment matches the building, and each
## unit's alignment +3 for a town or −3 for a tower. Queues it for the UI (`liberations`),
## with the card drawn if it went straight into the hand (empty if there was none, or if
## it's a Seer/Oracle offer instead, left for the UI to read from `card_offer`).
func _liberated(s: Squad, b: Dictionary) -> void:
	var st: Dictionary = data.rules["standing"]
	var aligned: String = data.buildings[b["type"]].get("aligned", "")
	var what: String = data.buildings[b["type"]]["name"].to_lower()
	change_reputation(s, _swing(aligned, s.alignment_band(data)) * int(st["liberate_reputation"]), "%s liberated a %s" % [s.name, what])
	if s.leader and s.leader.alignment_band(data) == aligned:
		change_charisma([s.leader], int(st["liberate_charisma"]), "liberating a %s that matches their alignment" % what)
	change_alignment(s.units, int(st["liberate_alignment"]) * (1 if aligned == "holy" else -1), "liberating a %s" % what)
	change_morale(s, int(data.battle["morale"]["liberation"]), "liberating a %s" % what)
	var before := cards.size()
	draw_card(s)
	earn_tech_points(int(data.tech["points"]["liberation"]), "a liberation")
	liberations.append({"building": b, "card": cards[-1] if cards.size() > before else ""})


## +1 when the squad's band matches the building's (holy town, evil tower), −1 for the
## opposite band, 0 for a neutral squad.
static func _swing(aligned: String, band: String) -> int:
	if band == "neutral" or aligned == "":
		return 0
	return 1 if band == aligned else -1


## Share of the capture done by squads on a building's hex (0 if none).
func capture_progress(b: Dictionary) -> float:
	var best := 0.0
	for s in player_squads():
		if s.hex == b["hex"]:
			best = maxf(best, s.capture_ticks / float(data.rules["capture"]["ticks"]))
	return best


## Victory and defeat (§6.8): each toggle in `settings` is checked independently; any one
## of them met ends the map. Defeat is checked first, on the (arbitrary) call that losing
## should win a tie. A missing toggle defaults to off, not the configurator's on-by-default
## choice: the real game always supplies the full dict (GameConfig.game_settings()), and a
## GameState built without one — most tests — has no opinion leader or enemy leader placed,
## so defaulting those two to on would call the map lost from the very first tick.
func _check_game_over() -> void:
	if game_over != "":
		return
	if settings.get("defeat_leader", false):
		var ol := opinion_leader_squad()
		if ol == null or ol.leader == null or not ol.leader.is_alive():
			_end_game("defeat", "The Opinion Leader has died.")
			return
	if settings.get("defeat_base", false):
		var pb := building_at(map.player_base)
		if not pb.is_empty() and pb["owner"] != "player":
			_end_game("defeat", "The Player Base has been captured.")
			return
	if settings.get("victory_leader", false) and not squads.any(func(s: Squad): return s.side == "enemy" and s.role == "leader"):
		_end_game("victory", "The enemy leader is defeated.")
		return
	if settings.get("victory_goal", false) and squads.any(func(s: Squad): return s.side == "player" and s.hex == map.enemy_base and not s.living().is_empty()):
		_end_game("victory", "You reached the goal.")
		return
	if settings.get("victory_squads", false):
		var n: Variant = settings.get("victory_squads_n", "all")
		var is_all := typeof(n) == TYPE_STRING
		var enemies_left := squads.any(func(s: Squad): return s.side == "enemy")
		if (is_all and not enemies_left) or (not is_all and enemy_squads_defeated >= int(n)):
			_end_game("victory", "The enemy is defeated." if is_all else "You defeated %d enemy squads." % int(n))
			return
	if settings.get("victory_towns", false):
		var buildings: Array = map.buildings.filter(func(b): return b["type"] in data.rules["economy"]["income_buildings"])
		var pct := (buildings.filter(func(b): return b["owner"] == "player").size() / float(buildings.size()) * 100.0) if not buildings.is_empty() else 0.0
		var need := float(settings.get("victory_towns_pct", 100))
		if pct >= need:
			if _towns_held_since < 0:
				_towns_held_since = clock.tick
			elif clock.tick - _towns_held_since >= float(settings.get("victory_towns_days", 1)) * GameClock.TICKS_PER_DAY:
				_end_game("victory", "You held %d%% of the towns for %s." % [int(need), duration_text(clock.tick - _towns_held_since)])
				return
		else:
			_towns_held_since = -1
	if settings.get("victory_timer", false) and clock.tick >= float(settings.get("victory_timer_days", 7)) * GameClock.TICKS_PER_DAY:
		_end_game("victory", "You survived.")


func _end_game(kind: String, reason: String) -> void:
	game_over = kind
	game_over_reason = reason
	log.add(clock.tick, "system", "%s: %s" % ["Victory" if kind == "victory" else "Defeat", reason])
	if kind == "victory":
		earn_tech_points(int(data.tech["points"]["map_end"]), "finishing the map")


## Stats for the end-of-map summary (§4, §6.8): gold, reputation, days played,
## enemy squads defeated and towns held of the total.
func end_summary() -> Dictionary:
	var towns: Array = map.buildings.filter(func(b): return b["type"] in data.rules["economy"]["income_buildings"])
	return {
		"outcome": game_over,
		"reason": game_over_reason,
		"day": clock.day(),
		"gold": gold,
		"reputation": reputation,
		"enemy_squads_defeated": enemy_squads_defeated,
		"towns_held": towns.filter(func(b): return b["owner"] == "player").size(),
		"towns_total": towns.size(),
		"tech_points": tech_points,
	}


## Daily rest (§6.5): squads in buildings heal their living units by the building's
## share of max HP; squads and recruits at the Player Base rest as in their own base.
func _rest() -> void:
	for s in squads:
		var b := building_at(s.hex)
		if not b.is_empty():
			_heal_share(s.living(), building_effect(b, s)[1])
			if b["type"] == "temple" and not s.living().is_empty():
				change_morale(s, int(data.battle["morale"]["temple_rest"]), "resting in a temple")
			if s.side == "player" and b["type"] in ["town", "tower", "nomads"]:  # nomads count as towns
				var aligned: String = data.buildings[b["type"]]["aligned"]
				change_reputation(s, _swing(aligned, s.alignment_band(data)) * int(data.rules["standing"]["stay_reputation"]),
						"%s spent the day in a %s" % [s.name, data.buildings[b["type"]]["name"].to_lower()])
	var base: float = data.buildings["player_base"]["own_base"]["rest"]
	for s in army.squads():
		if s not in squads:
			_heal_share(s.living(), base)
	_heal_share(army.pool.filter(func(u: Unit): return u.is_alive()), base)


func _heal_share(units: Array, share: float) -> void:
	if share <= 0.0:
		return
	for u in units:
		u.hp = mini(u.max_hp(data), u.hp + maxi(1, roundi(u.max_hp(data) * share)))


## Loyalty's daily tick (§12.2, recruited units only): sitting unused in the recruit
## pool costs loyalty; high reputation earns it. Very low loyalty warns for a day
## (never leaving without that warning first) before it may actually leave — this
## only runs on a day change, so it can never happen mid-battle either.
func _loyalty_day() -> void:
	var l: Dictionary = data.rules["loyalty"]
	for u in army.units():
		if not u.recruited or not u.is_alive():
			continue
		var delta := 0
		var why: Array[String] = []
		if u in army.pool:
			delta += int(l["unused"])
			why.append("unused")
		if reputation >= int(l["high_reputation"]):
			delta += int(l["high_reputation_gain"])
			why.append("high reputation")
		change_loyalty(u, delta, ", ".join(why))
		if u.loyalty >= int(l["very_low"]):
			u.loyalty_warned = false
			continue
		if not u.loyalty_warned:
			u.loyalty_warned = true
			log.add(clock.tick, "progression", "%s is growing restless." % u.name)
			continue
		if rng.get_stream("loyalty").randf() < float(l["leave_chance"]):
			_unit_leaves(u)


## A unit whose loyalty ran out for good (§12.2): leaves the army, no sale, no gold.
## If it was its squad's last unit and that squad was on the map, the squad leaves too.
func _unit_leaves(u: Unit) -> void:
	var s := army.squad_of(u)
	army.remove(u)
	if s and s.units.is_empty() and s in squads:
		_leave_map(s)
	log.add(clock.tick, "progression", "%s's loyalty runs out. They leave the army." % u.name)


## Nomads (§6.5) move 4–6 hexes every half day over the terrains they can camp on,
## never onto another building or a squad; each move has a 20% chance to stay out of
## sight until the next half day.
func _move_nomads() -> void:
	var r := rng.get_stream("nomads")
	for i in map.buildings.size():
		var b: Dictionary = map.buildings[i]
		if b["type"] != "nomads":
			continue
		var info: Dictionary = data.buildings["nomads"]
		var spots := nomad_spots(b["hex"])
		if spots.is_empty():
			continue
		_building_at.erase(b["hex"])
		b["hex"] = spots[r.randi() % spots.size()]
		_building_at[b["hex"]] = i
		b["away"] = r.randf() < float(info["hide_chance"])
		log.add(clock.tick, "map", "Nomads move on.", -1, {"to": str(map.hex_at(b["hex"])), "out_of_sight": b["away"]})


## Hexes 4–6 steps from `from` reachable through nomad terrain, free of buildings and squads.
func nomad_spots(from: int) -> Array:
	var info: Dictionary = data.buildings["nomads"]
	var allowed := {}
	for key in info["terrains"]:
		allowed[data.terrain_ids[key]] = true
	var lo := int(info["move_hexes"][0])
	var hi := int(info["move_hexes"][1])
	var dist := {from: 0}
	var frontier := [from]
	var out := []
	for step_n in hi:
		var next := []
		for h in frontier:
			for n in map.neighbor_indices(h):
				if dist.has(n) or not allowed.has(map.terrain[n]):
					continue
				dist[n] = step_n + 1
				next.append(n)
				if step_n + 1 >= lo and not _building_at.has(n) and _squad_on(n) == null:
					out.append(n)
		frontier = next
	return out


## A town's hint about the nearest unseen hidden site within range: "to the northeast,
## about 12 hexes away", or "".
func hint(b: Dictionary) -> String:
	if not b.get("hint", false):
		return ""
	var at := map.hex_at(b["hex"])
	var best := -1
	for i in map.buildings.size():
		var o: Dictionary = map.buildings[i]
		if o["type"] == "hidden_site" and not revealed.has(i):
			var d := Hex.distance(at, map.hex_at(o["hex"]))
			if d <= int(data.rules["capture"]["hint_range"]) and (best < 0 or d < Hex.distance(at, map.hex_at(map.buildings[best]["hex"]))):
				best = i
	if best < 0:
		return ""
	var delta := Hex.to_pixel(map.hex_at(map.buildings[best]["hex"]), 1.0) - Hex.to_pixel(at, 1.0)
	var names := ["east", "southeast", "south", "southwest", "west", "northwest", "north", "northeast"]
	var dir: String = names[posmod(roundi(delta.angle() / (PI / 4.0)), 8)]
	return "Travellers speak of something hidden to the %s, about %d hexes away." % [dir, Hex.distance(at, map.hex_at(map.buildings[best]["hex"]))]


# --- Tech (SPEC §14) ------------------------------------------------------------------

## A bought node's number (e.g. war_chest's "income"), or 0 if not bought.
func tech_value(id: String, key: String) -> float:
	return float(data.tech["nodes"][id][key]) if id in tech else 0.0


func earn_tech_points(n: int, why: String) -> void:
	if n > 0:
		tech_points += n
		log.add(clock.tick, "progression", "+%d tech point%s for %s (%d to spend)." % [n, "" if n == 1 else "s", why, tech_points])


## Every node: the branch nodes, then a terrain node per terrain per tier ("terrain_Plains_1").
func tech_nodes() -> Dictionary:
	var out: Dictionary = data.tech["nodes"].duplicate()
	for terrain in data.tech["terrains"]:
		for t in range(1, 5):
			out["terrain_%s_%d" % [terrain, t]] = {"name": "%s %s" % [terrain, ["I", "II", "III", "IV"][t - 1]], "branch": "", "tier": t,
					"text": "Units native to %s: +%d STR, INT, PDEF and MDEF." % [terrain.to_lower(), t]}
	return out


## Tier 1 is always open; a later tier opens once 80% of the previous tier's branch nodes are bought.
func tier_open(tier: int) -> bool:
	if tier <= 1:
		return true
	var branch: Array = data.tech["nodes"].keys().filter(func(id): return int(data.tech["nodes"][id]["tier"]) == tier - 1)
	var bought: int = branch.filter(func(id): return id in tech).size()
	return bought >= ceili(branch.size() * float(data.tech["gate_share"]) - 0.0001)


## Why a node can't be bought, or "" if it can.
func tech_blocker(id: String) -> String:
	var node: Dictionary = tech_nodes()[id]
	if id in tech:
		return "Already learned."
	if not tier_open(int(node["tier"])):
		return "Tier %d opens with 80%% of tier %d's branch nodes." % [int(node["tier"]), int(node["tier"]) - 1]
	if tech_points < int(node["tier"]):
		return "Needs %d point%s." % [int(node["tier"]), "" if int(node["tier"]) == 1 else "s"]
	return ""


## Buys a node for its tier in points (§14).
func buy_tech(id: String) -> bool:
	if tech_blocker(id) != "":
		return false
	var node: Dictionary = tech_nodes()[id]
	tech_points -= int(node["tier"])
	tech.append(id)
	_apply_tech()
	log.add(clock.tick, "progression", "Tech learned: %s. %s" % [node["name"], node["text"]])
	return true


## Effects that live on units and squads: Veterans' HP, and speed tiers (Mage Regiments, Sky Lords).
func _apply_tech() -> void:
	var share := tech_value("veterans", "hp")
	for u in army.units():
		var before := u.max_hp(data)
		u.hp_bonus = share if int(u.info(data)["stage"]) >= 4 else 0.0
		if u.is_alive():
			u.hp = clampi(u.hp + u.max_hp(data) - before, 1, u.max_hp(data))
	for s in army.squads():
		s.refresh(data)


# --- Cards (SPEC §13) ---------------------------------------------------------------

func _roll_card() -> String:
	var ids: Array = data.cards["cards"].keys()
	return ids[rng.get_stream("cards").randi() % ids.size()]


## Draws a card for a liberation or a found hidden site. A squad with a Seer (2) or an
## Oracle (3) chooses from that many cards (card_offer, for the HUD); otherwise the card
## goes straight into the hand. The next card is rolled ahead for Foresight.
func draw_card(s: Squad) -> void:
	var choose := 1
	if s:
		for u in s.living():
			choose = maxi(choose, int(data.cards["choose"].get(u.unit_class, 1)))
	if next_card == "":
		next_card = _roll_card()
	var drawn: Array[String] = []
	for i in choose:
		drawn.append(next_card)
		next_card = _roll_card()
	if choose == 1:
		cards.append(drawn[0])
		log.add(clock.tick, "progression", "You draw %s." % card_name(drawn[0]), s.id if s else -1)
	else:
		card_offer = drawn


## Takes one card from the offer into the hand.
func choose_card(id: String) -> void:
	if id in card_offer:
		cards.append(id)
		log.add(clock.tick, "progression", "You choose %s." % card_name(id))
	card_offer.clear()


func card_name(id: String) -> String:
	return data.cards["cards"][id]["name"]


## Whether a squad on the map has a leader with the Foresight aura, which shows the next card.
func foresight() -> bool:
	return player_squads().any(func(s: Squad): return s.leader and s.leader.is_alive() and s.leader.info(data)["leader_aura"] == "Foresight")


## The squad the Opinion Leader leads: the first squad of the army (§18).
func opinion_leader_squad() -> Squad:
	return army.cells[0]


## Plays a map card (Rooster, Fox): time jumps ahead to its hour, with the noon ledger,
## nomad moves and daily rest it passes; squads don't move meanwhile.
func play_map_card(id: String) -> bool:
	var c: Dictionary = data.cards["cards"][id]
	if id not in cards or c["where"] != "map":
		return false
	cards.erase(id)
	var ticks := posmod(int(c["minute"]) - clock.minute_of_day(), GameClock.TICKS_PER_DAY)
	for i in (ticks if ticks > 0 else GameClock.TICKS_PER_DAY):
		for event in clock.step():
			_clock_event(event)
	log.add(clock.tick, "system", "%s: %s" % [c["name"], c["text"]])
	return true


## Plays a battle card from the hand in the pending battle.
func play_battle_card(b: Battle, id: String) -> bool:
	if id not in cards or not b.play_card(id, 0):
		return false
	cards.erase(id)
	return true


# --- Reputation, charisma and alignment (SPEC §9.5, §9.6, §10) ------------------------

## Changes the army's reputation (0–100). A squad with a Black market unit (Smuggler,
## Fence) doubles the swing.
func change_reputation(s: Squad, amount: int, why: String) -> void:
	if amount == 0:
		return
	if s and s.living().any(func(u: Unit): return u.has_trait(data, "Black market")):
		amount *= int(data.battle["traits"]["Black market"]["reputation_swing"])
	var before := reputation
	reputation = clampi(reputation + amount, 0, 100)
	log.add(clock.tick, "progression", "Reputation %+d (%s): now %d." % [reputation - before, why, reputation], s.id if s else -1)


func change_charisma(units: Array, amount: int, why: String) -> void:
	for u in units:
		u.charisma = clampi(u.charisma + amount, 0, 100)
	if not units.is_empty():
		log.add(clock.tick, "progression", "Charisma %+d for %s (%s)." % [amount, _who(units), why])


func change_alignment(units: Array, amount: int, why: String) -> void:
	for u in units:
		u.alignment = clampi(u.alignment + amount, 0, 100)
	if not units.is_empty():
		log.add(clock.tick, "progression", "Alignment %+d for %s (%s)." % [amount, _who(units), why])


func _who(units: Array) -> String:
	if units.size() == 1:
		return units[0].name
	var s := army.squad_of(units[0])
	return "each unit in %s" % s.name if s else "%d units" % units.size()


## Morale (§12.2), clamped 0-100, with a log line. Applies to any squad, not just
## the player's — an enemy or neutral squad's morale has to move too, for it to ever
## drop low enough to be driven off (§11.6).
func change_morale(s: Squad, amount: int, why: String) -> void:
	if amount == 0:
		return
	s.morale = clampi(s.morale + amount, 0, 100)
	log.add(clock.tick, "progression", "%s's morale %+d (%s): now %d." % [s.name, amount, why, s.morale], s.id)


## Loyalty (§12.2, recruited neutrals only), clamped 0-100, with a log line.
func change_loyalty(u: Unit, amount: int, why: String) -> void:
	if amount == 0:
		return
	u.loyalty = clampi(u.loyalty + amount, 0, 100)
	log.add(clock.tick, "progression", "%s's loyalty %+d (%s): now %d." % [u.name, amount, why, u.loyalty])


## A win: the side's enemy is wiped out, or (no one retreated) it lost the larger share of its HP.
func _won(out: Dictionary, side: int) -> bool:
	return out["wiped"][1 - side] or (out["retreated"] < 0 and out["hp_lost"][1 - side] > out["hp_lost"][side])


## After a battle (§9.5, §9.6): each living unit of your squad shifts alignment +2
## against an equal or stronger enemy and −2 against a weaker one; after a win, each
## gains 1 charisma against a stronger enemy and loses 1 against a much weaker one.
func _battle_standing(b: Battle, out: Dictionary) -> void:
	if b.sides[0].side != "player":  # an enemy-neutral fight (§6.7): no player squad to credit
		return
	var st: Dictionary = data.rules["standing"]
	var units := b.sides[0].living().filter(func(u: Unit): return u in army.units())
	var weaker := b.odds in ["Weaker", "Much weaker"]
	change_alignment(units, int(st["battle_alignment"]) * (-1 if weaker else 1), "fighting a %s enemy" % b.odds.to_lower())
	var won := _won(out, 0)
	if won:
		earn_tech_points(int(data.tech["points"]["battle_win"]), "a battle won")
	if won and b.odds in ["Stronger", "Dangerous"]:
		change_charisma(units, int(st["battle_charisma"]), "beating a stronger squad")
	elif won and b.odds == "Much weaker":
		change_charisma(units, -int(st["battle_charisma"]), "beating a much weaker squad")


## Shop prices with reputation: −20% at 100, +20% at 0, linear between (§10); a squad
## with a Smuggler takes 10% off, with a Fence 20%.
func price(base: int, s: Squad = null) -> int:
	var f := 1.0 + float(data.rules["standing"]["price_swing"]) * (1.0 - reputation / 50.0)
	var off := 0.0
	if s:
		var cut: Dictionary = data.battle["traits"]["Black market"]["price"]
		for u in s.living():
			off = minf(off, float(cut.get(u.unit_class, 0.0)))
	return maxi(1, roundi(base * f * (1.0 + off)))


## A neutral squad's chance to join you (§16): 0.60 × (10 − units)/9 × (1 − alignment
## gap/100) × (0.5 + reputation/100). The gap is from your squad's alignment (leader twice).
func recruit_chance(s: Squad, neutral_units: int, neutral_alignment: float, large := false) -> float:
	var gap := absf(s.alignment() - neutral_alignment)
	var bonus := (1.0 + tech_value("diplomacy", "recruit")) * (1.0 + (tech_value("tamers", "recruit") if large else 0.0))
	return clampf(0.6 * (10 - neutral_units) / 9.0 * (1.0 - gap / 100.0) * (0.5 + reputation / 100.0) * bonus, 0.0, 1.0)


# --- Economy (SPEC §15.1, §16) ------------------------------------------------------

## Gold per day from the towns and towers you hold.
func income() -> int:
	var e: Dictionary = data.rules["economy"]
	var held := map.buildings.filter(func(b): return b["type"] in e["income_buildings"] and b["owner"] == "player")
	return roundi(held.size() * int(e["income_per_building"]) * (1.0 + tech_value("war_chest", "income")))


## Upkeep per day for the whole army: every unit in a squad or the recruit pool.
func army_upkeep() -> int:
	var total := 0
	for s in army.squads():
		total += upkeep(s)
	for u in army.pool:
		total += _unit_upkeep(u)
	return total


func _unit_upkeep(u: Unit) -> int:
	var k: Dictionary = data.rules["upkeep"]
	var c: Dictionary = u.info(data)
	return roundi(float(k["by_stage"][int(c["stage"]) - 1]) * float(k["size"][c["size"]]) * (1.0 + tech_value("quartermaster", "upkeep")))


## At noon: income comes in, then upkeep goes out. Gold never drops below zero; upkeep
## that can't be paid is lost for now (morale and loyalty, M4).
func _noon() -> void:
	var gain := income()
	var cost := army_upkeep()
	restock()
	gold += gain
	var paid := mini(gold, cost)
	gold -= paid
	noon_report = "Noon: +%d income, −%d upkeep%s. Gold %d." % [gain, paid, " (%d unpaid)" % (cost - paid) if paid < cost else "", gold]
	log.add(clock.tick, "economy", noon_report, -1, {"income": gain, "upkeep": cost, "paid": paid})


## 100 × (0.5 + reputation/100), once per liberation.
func liberation_bonus() -> int:
	return roundi(float(data.rules["economy"]["liberation_bonus"]) * (0.5 + reputation / 100.0))


func is_broke() -> bool:
	return gold <= 0


## What a squad sells for when you're broke: 50 × stage per unit.
func sell_value(s: Squad) -> int:
	var total := 0
	for u in s.units:
		total += int(data.rules["economy"]["sell_per_stage"]) * int(u.info(data)["stage"])
	return total


## Going broke (§15.1): with no gold, a squad can be sold for its value; it leaves the
## army and the map, and its items go back to the inventory.
func sell_squad(s: Squad) -> bool:
	if not is_broke() or s not in army.squads():
		return false
	var value := sell_value(s)
	for u in s.units:
		for slot in u.items.keys():
			army.unequip(u, slot)
	army.cells[army.cells.find(s)] = null
	squads.erase(s)
	gold += value
	log.add(clock.tick, "economy", "%s is sold for %d gold." % [s.name, value], s.id)
	return true


## The shop a squad can use where it stands: a building with a shop that the enemy
## doesn't hold, or a temple's services. {} if none.
func shop_at(s: Squad) -> Dictionary:
	if s.is_moving():
		return {}
	var b := building_at(s.hex)
	if b.is_empty() or b["owner"] == "enemy" or not (b.get("shop", false) or b["type"] == "temple"):
		return {}
	return b


## What a shop holds right now: item or consumable id -> how many are left (0 once
## sold out). Rolled once per shop: a few random items, every map consumable, and a
## few of the cure potions. Refilled to that at noon (restock()).
func shop_stock(b: Dictionary) -> Dictionary:
	if not b.get("shop", false):
		return {}
	if not b.has("stock"):
		var r := rng.get_stream("shops")
		var e: Dictionary = data.rules["economy"]
		var ids: Array = data.items["items"].keys().filter(func(id): return data.items["items"][id].get("requires", "") in tech or not data.items["items"][id].has("requires"))
		var full := {}
		for i in int(e["shop_items"]):
			var id: String = ids[r.randi() % ids.size()]
			full[id] = int(full.get(id, 0)) + int(e["item_stock"])
		var cures := []
		for id in data.items["consumables"]:
			var c: Dictionary = data.items["consumables"][id]
			if c.has("cures"):
				cures.append(id)
			else:
				full[id] = int(c["stock"])
		for i in range(cures.size() - 1, 0, -1):  # seeded shuffle
			var j := r.randi_range(0, i)
			var t = cures[i]
			cures[i] = cures[j]
			cures[j] = t
		for id in cures.slice(0, int(e["shop_cures"])):
			full[id] = int(data.items["consumables"][id]["stock"])
		b["full_stock"] = full
		b["stock"] = full.duplicate()
	return b["stock"]


## At noon every shop that's been opened refills to its full stock.
func restock() -> void:
	for b in map.buildings:
		if b.has("full_stock"):
			b["stock"] = b["full_stock"].duplicate()


func item_price(id: String, s: Squad = null) -> int:
	return price(int(data.items["items"][id]["price"]), s)


func supply_price(id: String, s: Squad = null) -> int:
	return price(int(data.items["consumables"][id]["price"]), s)


func serf_price(s: Squad = null) -> int:
	return price(int(data.rules["economy"]["serf_price"]), s)


func buy_item(b: Dictionary, id: String, s: Squad = null) -> bool:
	var stock := shop_stock(b)
	var cost := item_price(id, s)
	if int(stock.get(id, 0)) <= 0 or gold < cost:
		return false
	gold -= cost
	stock[id] -= 1
	army.add_item(id)
	log.add(clock.tick, "economy", "Bought a %s for %d gold." % [data.items["items"][id]["name"], cost])
	return true


func buy_supply(b: Dictionary, id: String, s: Squad = null) -> bool:
	var cost := supply_price(id, s)
	var stock := shop_stock(b)
	if int(stock.get(id, 0)) <= 0 or gold < cost:
		return false
	gold -= cost
	stock[id] -= 1
	army.supplies[id] = int(army.supplies.get(id, 0)) + 1
	log.add(clock.tick, "economy", "Bought a %s for %d gold." % [data.items["consumables"][id]["name"], cost])
	return true


## Serfs are sold at towns (and nomad camps) with shops (§16) and join the recruit pool.
func sells_serfs(b: Dictionary) -> bool:
	return b.get("shop", false) and b["type"] in data.rules["economy"]["serf_shops"]


func buy_serf(b: Dictionary, s: Squad = null) -> Unit:
	var cost := serf_price(s)
	if not sells_serfs(b) or gold < cost:
		return null
	gold -= cost
	var u := Unit.roll(data, "Serf", rng.get_stream("recruit"), names)
	army.pool.append(u)
	log.add(clock.tick, "economy", "%s the Serf is hired for %d gold and waits in the recruit pool." % [u.name, cost])
	return u


## Whether a map consumable would do anything for this unit: a Herb for a hurt
## living unit, a Revival Draught for a fallen one.
func supply_helps(u: Unit, id: String) -> bool:
	var item: Dictionary = data.items["consumables"][id]
	if item.get("revive", false):
		return not u.is_alive()
	return item.has("heal") and u.is_alive() and u.hp < u.max_hp(data)


## Uses a map consumable on a unit that needs it, anywhere on the map.
func use_supply(u: Unit, id: String) -> bool:
	var item: Dictionary = data.items["consumables"][id]
	if int(army.supplies.get(id, 0)) <= 0 or not supply_helps(u, id):
		return false
	army.supplies[id] = int(army.supplies[id]) - 1
	if item.get("revive", false):
		u.hp = u.max_hp(data)
		log.add(clock.tick, "economy", "%s is revived with a %s." % [u.name, item["name"]])
		var s := army.squad_of(u)
		if s and s.marching_home and s.leader == u:  # reviving the leader in time cancels the march (§11.3)
			s.marching_home = false
			s.entering_base = false
			s.path.clear()
			s.rally.clear()
		return true
	u.hp = mini(u.max_hp(data), u.hp + int(item["heal"]))
	log.add(clock.tick, "economy", "%s uses a %s." % [u.name, item["name"]])
	return true


## The cure potions the player could use in this battle right now: [potion id, unit] pairs.
func battle_supply_uses(b: Battle) -> Array:
	var out := []
	for id in data.items["consumables"]:
		var item: Dictionary = data.items["consumables"][id]
		if item.has("cures") and int(army.supplies.get(id, 0)) > 0:
			for u in b.sides[0].living():
				if b.has_status(u, item["cures"]):
					out.append([id, u])
	return out


## Uses a cure potion on one of the player's units in battle (§15.1).
func use_battle_supply(b: Battle, id: String, u: Unit) -> bool:
	var item: Dictionary = data.items["consumables"][id]
	if int(army.supplies.get(id, 0)) <= 0 or not item.has("cures") or not b.cure(u, item["cures"], item["name"]):
		return false
	army.supplies[id] = int(army.supplies[id]) - 1
	return true


# --- Base and deployment (SPEC §8.4, §6.5 Player Base, §15.1 services) ----------------

## Squads on the map at once, from the configurator (default 5).
func squad_cap() -> int:
	if settings.has("squad_cap"):
		return int(settings["squad_cap"])
	for f in data.config_fields:
		if f["key"] == "squad_cap":
			return int(f["default"])
	return 5


## Gold per day for the squad's units (§15.1): by stage, Large ×2, Tiny ×½.
func upkeep(s: Squad) -> int:
	var u: Dictionary = data.rules["upkeep"]
	var total := 0.0
	for unit in s.units:
		var c: Dictionary = unit.info(data)
		total += float(u["by_stage"][int(c["stage"]) - 1]) * float(u["size"][c["size"]])
	return roundi(total * (1.0 + tech_value("quartermaster", "upkeep")))


## Deploying costs one day of the squad's upkeep.
func deploy_cost(s: Squad) -> int:
	return upkeep(s)


## The hex a deployed squad appears on: the Player Base (your squads can share a hex).
func deploy_hex() -> int:
	return map.player_base


## Why the squad can't deploy, or "" if it can.
## Why the toolbar's Deploy Squad is off: the squad cap is reached, or no squad waits at
## the Player Base. "" when it's on (user's playtest notes, 2026-11-09).
func deploy_menu_blocker() -> String:
	if player_squads().size() >= squad_cap():
		return "The squad cap is %d on the map at once." % squad_cap()
	if not army.squads().any(func(s: Squad): return s not in squads):
		return "No squads are waiting at the Player Base."
	return ""


func deploy_blocker(s: Squad) -> String:
	if s in squads:
		return "Already on the map."
	if s.leader == null:
		return "It needs a leader."
	if not s.leader.is_alive():
		return "Its leader has fallen: revive them first."
	if player_squads().size() >= squad_cap():
		return "The squad cap is %d on the map at once." % squad_cap()
	if gold < deploy_cost(s):
		return "Not enough gold: deploying costs %d." % deploy_cost(s)
	return ""


## Pays the deploy cost and puts a squad from base on the map at deploy_hex(); with
## rally points, it sets off along them at once.
func deploy(s: Squad, points := PackedInt32Array()) -> bool:
	if deploy_blocker(s) != "":
		return false
	var cost := deploy_cost(s)
	gold -= cost
	s.hex = deploy_hex()
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	s.marching_home = false
	s.entering_base = false
	squads.append(s)
	log.add(clock.tick, "economy", "%s deploys from the Player Base for %d gold." % [s.name, cost], s.id)
	if not points.is_empty():
		order_move(s, points)
	return true


## A squad standing on the Player Base can go in; elsewhere it marches there and goes
## in on arrival.
func send_home(s: Squad) -> void:
	if s.hex == map.player_base:
		return_to_base(s)
	elif order_move(s, PackedInt32Array([map.player_base])):
		s.entering_base = true


func return_to_base(s: Squad) -> void:
	_leave_map(s)
	log.add(clock.tick, "map", "%s returns to the Player Base." % s.name, s.id)


func _leave_map(s: Squad) -> void:
	squads.erase(s)
	s.hex = -1
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	s.marching_home = false
	s.entering_base = false


## Healing and revival are bought at base: for units at base or in the pool.
func at_base(u: Unit) -> bool:
	var s := army.squad_of(u)
	return s == null or s not in squads


## Healing and revival can be bought at base, or by a squad standing in a temple (§6.5).
func can_service(u: Unit) -> bool:
	if at_base(u):
		return true
	var s := army.squad_of(u)
	return not s.is_moving() and building_at(s.hex).get("type", "") == "temple"


func heal_cost(u: Unit) -> int:
	return int(data.rules["services"]["heal"]) if u.is_alive() and u.hp < u.max_hp(data) else 0


func revive_cost(u: Unit) -> int:
	return int(data.rules["services"]["revive_per_stage"]) * int(u.info(data)["stage"]) if not u.is_alive() else 0


## Heals a hurt unit to full, or revives a fallen one at full HP, for gold. False if
## the unit isn't at base, needs nothing, or the gold is short.
func restore(u: Unit) -> bool:
	var cost := heal_cost(u) + revive_cost(u)
	if cost == 0 or cost > gold or not can_service(u):
		return false
	var revived := not u.is_alive()
	gold -= cost
	u.hp = u.max_hp(data)
	var s := army.squad_of(u)
	if s:
		s.refresh(data)
	log.add(clock.tick, "economy", "%s %s for %d gold." % [u.name, "is revived" if revived else "is healed", cost], s.id if s else -1)
	return true


## Squads can be changed at the Player Base, or while waiting there off the map.
func can_edit(s: Squad) -> bool:
	return s not in squads or (s.hex == map.player_base and not s.is_moving() and not s.marching_home)


## Whether a unit can be moved into `target` (null: the recruit pool) in Edit Units. A
## squad's formation can change anywhere, even out in the field; who is in it can change
## only where it can be edited (user's playtest notes, 2026-11-09).
func can_rearrange(u: Unit, target: Squad) -> bool:
	var from := army.squad_of(u)
	if from != null and from == target:
		return true
	return (from == null or can_edit(from)) and (target == null or can_edit(target))


## After Edit Units: squads emptied there leave the map.
func after_edit() -> void:
	for s in squads.duplicate():
		if s.side == "player" and s not in army.squads():
			squads.erase(s)


func _form(number: int, squad_name: String, at_hex: int, members: Array, side: String) -> Squad:
	var s := Squad.new(number, squad_name, at_hex)
	s.side = side
	if side == "player":
		s.tech = tech
	for m in members:
		var u := Unit.roll(data, m[0], rng.get_stream("recruit"), names)
		if s.add(data, u, m[1]):
			log.add(clock.tick, "progression", "%s the %s joins %s." % [u.name, u.unit_class, s.name], s.id,
					{"stats": u.stats, "alignment": u.alignment, "charisma": u.charisma, "growth": u.growth,
					"talent": u.talent, "luck": u.luck})
	s.morale = int(data.rules["starting_morale"])
	log.add(clock.tick, "map", "%s forms: travels as %s, speed tier %d." % [s.name, s.travel_name(), s.speed_tier], s.id)
	return s


## Ticks to cross one hex of multiplier 1 at this speed tier, slowed by casualties (SPEC §8.3).
func base_ticks(s: Squad) -> float:
	return float(data.rules["hex_seconds_by_tier"][s.speed_tier - 1]) * float(data.rules["ticks_per_real_second"]) \
			* s.casualty_multiplier(data)


## Ticks to enter hex `i`.
func step_ticks(s: Squad, i: int) -> float:
	var t := base_ticks(s) * pathfinder.hex_cost(i, s.travel_type, s.sky)
	if map.road[i] and not s.sky and s.side == "player" and "engineers" in tech:  # Engineers: bigger road bonus
		t *= float(data.tech["nodes"]["engineers"]["road"]) / float(data.rules["road_multiplier"])
	return t


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
	s.entering_base = false
	s.path = route
	s.rally = points.duplicate()
	s.progress = 0.0
	var to := map.hex_at(points[points.size() - 1]) if not points.is_empty() else map.hex_at(s.hex)
	log.add(clock.tick, "map", "%s ordered to %s via %d rally point%s: %d hexes, about %s." % [s.name, to,
			points.size(), "" if points.size() == 1 else "s", route.size(), duration_text(route_ticks(s, route))],
			s.id, {"path": Array(route)})
	return true


func player_squads() -> Array[Squad]:
	var out: Array[Squad] = []
	for s in squads:
		if s.side == "player":
			out.append(s)
	return out


## Neutrals fight both sides (§6.7); only same-side squads never fight.
func hostile(a: Squad, b: Squad) -> bool:
	return a.side != b.side


# --- Enemy squads (SPEC §17, §12.3 AI) -----------------------------------------------

## Gives an idle enemy squad a new order from EnemyAI.target_hex, if it needs one
## (none if it's already there or already moving).
func _run_enemy_ai() -> void:
	for s in squads:
		if s.side != "enemy" or s.living().is_empty():
			continue
		if s.hex == map.enemy_base and not s.is_moving():
			_revive_at_enemy_base(s)
		elif not s.marching_home and _fallen(s) > 0 and _fallen(s) >= s.units.size() * float(data.ai["go_home_fallen_share"]):
			s.marching_home = true
			s.goal = -1
			order_move(s, PackedInt32Array([map.enemy_base]))
		if s.is_moving() or s.marching_home:
			continue
		var target := EnemyAI.target_hex(self, s)
		if target >= 0 and target != s.hex and not order_move(s, PackedInt32Array([target])):
			s.unreachable[target] = true  # no route (water, say): pick something else next time
			s.goal = -1


func _fallen(s: Squad) -> int:
	return s.units.size() - s.living().size()


## The Enemy Base is the only place enemy units come back (user's playtest notes,
## 2026-11-09): a squad standing there has its fallen revived at full HP, and any
## march home ends. EnemyAI then sends it back to its post or its target.
func _revive_at_enemy_base(s: Squad) -> void:
	for u in s.units:
		if not u.is_alive():
			u.hp = u.max_hp(data)
	s.marching_home = false


## How many squads the enemy fields (user's playtest notes, 2026-11-10): half as many
## as the map has towns, at least a few, so it scales with the map.
func enemy_squad_count() -> int:
	var towns := map.buildings.filter(func(b): return b["type"] == "town").size()
	return maxi(int(data.enemy["min_squads"]), roundi(towns * float(data.enemy["squads_per_town"])))


## Places every enemy squad on the Enemy Base (§17, changed 2026-11-10): the Warlord
## and the base guard hold it; field squads march out from there to take buildings,
## the way the player's squads set out from the Player Base.
func place_enemies() -> void:
	var e: Dictionary = data.enemy
	var r := rng.get_stream("enemy")
	var builds: Array = e["builds"]
	var left := enemy_squad_count()
	for entry in e["roles"]:
		var count := left if str(entry["count"]) == "rest" else mini(left, int(entry["count"]))
		left -= count
		for k in count:
			var title: String = e["names"][entry["role"]]
			var s := add_squad("%s %d" % [title, k + 1] if count > 1 else title, map.enemy_base, builds[r.randi() % builds.size()], "enemy")
			s.balance_rows(data)
			s.role = entry["role"]
			s.post = map.enemy_base


## Gives an idle roamer a new order from NeutralAI.target_hex, if it needs one.
func _run_neutral_ai() -> void:
	for s in squads:
		if s.side != "neutral" or s.is_moving() or s.living().is_empty():
			continue
		var target := NeutralAI.target_hex(self, s)
		if target >= 0 and target != s.hex:
			order_move(s, PackedInt32Array([target]))


## Places one roamer squad per lair (§6.7): a race line native to the lair's home
## terrain, strength scaled by its danger. A lair with no matching line (an odd
## density/terrain mix) gets no squad.
func place_neutrals() -> void:
	var r := rng.get_stream("neutral")
	for lair in map.lairs:
		var units := NeutralSquads.roll(data, lair["home"], lair["danger"], r, names)
		if units.is_empty():
			continue
		var number := 1 + squads.filter(func(o: Squad): return o.side == "neutral").size() + 200
		var s := Squad.new(number, units[0].unit_class, lair["hex"])
		s.side = "neutral"
		s.role = "roamer"
		s.lair_hex = lair["hex"]
		for u in units:
			if s.add(data, u, "front"):
				log.add(clock.tick, "progression", "%s the %s joins %s." % [u.name, u.unit_class, s.name], s.id)
		s.balance_rows(data)
		s.morale = int(data.rules["starting_morale"])
		squads.append(s)


func _squad_on(i: int) -> Squad:
	for s in squads:
		if s.hex == i:
			return s
	return null


# --- Contact and sight (SPEC §11.1, §8.5) -------------------------------------------------

## Two hostile squads on the same or adjacent hexes fight. The squad that moved into
## contact attacks; the battle uses the defender's hex. A pair that just fought waits
## a short cooldown before fighting again. Meeting a neutral, the player chooses
## Recruit or Fight (§16) instead of fighting outright; an enemy-neutral fight (§6.7)
## resolves on the spot since neither side is the player's to watch.
func _check_contact() -> void:
	for i in squads.size():
		var a := squads[i]
		if a.living().is_empty():
			continue
		for j in range(i + 1, squads.size()):
			var b := squads[j]
			if not hostile(a, b) or b.living().is_empty():
				continue
			if Hex.distance(map.hex_at(a.hex), map.hex_at(b.hex)) > 1:
				continue
			if clock.tick < int(_contact_until.get(_pair(a, b), -1)):
				continue
			var defender := b if _moved.has(a) or not _moved.has(b) else a
			if a.side == "player" and b.side == "neutral":
				pending_recruit = {"player": a, "neutral": b, "defender": defender}
				return
			if b.side == "player" and a.side == "neutral":
				pending_recruit = {"player": b, "neutral": a, "defender": defender}
				return
			# The player's squad is always side 0, whoever moved in: the battle view, tactic,
			# tech and outcome text all read side 0 as "us".
			pending = start_battle(b, a, defender) if b.side == "player" else start_battle(a, b, defender)
			if a.side != "player" and b.side != "player":
				resolve_pending()
			return


func _pair(p: Squad, e: Squad) -> String:
	return "%d:%d" % [mini(p.id, e.id), maxi(p.id, e.id)]


## The neutral squad's class in a pending Recruit-or-Fight choice, without its count (§16).
func recruit_class() -> String:
	return pending_recruit["neutral"].units[0].unit_class if not pending_recruit.is_empty() else ""


## Resolves a pending Recruit-or-Fight choice (§16). Recruit rolls the chance: on
## success the neutrals join the recruit pool and the leader gains charisma; on
## failure they fight having resisted, taking their whole first round. Fight skips
## straight to a normal battle.
## Returns what happened, for the popup to show before any battle: {joined, chance,
## text}. "joined" is false for Fight as well.
func resolve_recruit(try_recruit: bool) -> Dictionary:
	var enc := pending_recruit
	pending_recruit = {}
	var player: Squad = enc["player"]
	var neutral: Squad = enc["neutral"]
	if try_recruit:
		var large: bool = neutral.units[0].info(data)["size"] == "Large"
		var chance := recruit_chance(player, neutral.living().size(), neutral.alignment(), large)
		var result := {"joined": false, "chance": chance}
		if rng.get_stream("recruit").randf() < chance:
			result["joined"] = true
			result["text"] = "The %s join you. %d %s wait in the recruit pool at the base." % [neutral.name, neutral.living().size(),
					"unit" if neutral.living().size() == 1 else "units"]
			for u in neutral.living():
				u.recruited = true
				u.loyalty = int(data.rules["starting_loyalty"])
				army.pool.append(u)
			if player.leader:
				change_charisma([player.leader], 3, "recruiting the %s" % neutral.units[0].unit_class)
			log.add(clock.tick, "map", "%s recruits the %s." % [player.name, neutral.name], player.id)
			squads.erase(neutral)
			return result
		log.add(clock.tick, "map", "The %s resist recruitment." % neutral.name, player.id)
		result["text"] = "The %s refuse to join (a %d%% chance: %s). They fight, and strike first." % [neutral.name,
				roundi(chance * 100), _recruit_drag(player, neutral)]
		pending = start_battle(player, neutral, neutral)
		pending.first_side = 1
		return result
	pending = start_battle(player, neutral, enc["defender"])
	return {"joined": false, "chance": 0.0, "text": ""}


## What held a recruit chance down most (§16's three factors): the band's size, the
## gap in alignment, or the army's reputation.
func _recruit_drag(player: Squad, neutral: Squad) -> String:
	var size := (10 - neutral.living().size()) / 9.0
	var ideals := 1.0 - absf(player.alignment() - neutral.alignment()) / 100.0
	var standing := 0.5 + reputation / 100.0
	var low := minf(size, minf(ideals, standing))
	if low >= 0.8:
		return "bad luck"
	if low == ideals:
		return "your squad's ideals are far from theirs"
	if low == standing:
		return "your reputation is low"
	return "a big band is hard to win over"


## Fights the pending battle to the end (the battle view may have played it already)
## and applies the outcome. Returns end_battle's outcome plus a short summary as "text".
func resolve_pending() -> Dictionary:
	var b := pending
	pending = null
	b.run()
	var key := _pair(b.sides[0], b.sides[1])
	var out := end_battle(b)
	if not b.ranged_only:
		_contact_until[key] = clock.tick + int(data.enemy["contact_cooldown_ticks"])
	out["text"] = battle_summary(b, out)
	return out


## How the battle went for side 0 (the player's squad, when there is one): "won" (the
## enemy was wiped out or lost the larger share of its HP), "lost", "retreated" or "even".
static func battle_result(out: Dictionary) -> String:
	if out["wiped"][1]:
		return "won"
	if out["wiped"][0]:
		return "lost"
	if out["retreated"] == 0:
		return "retreated"
	if out["retreated"] == 1 or out["hp_lost"][1] > out["hp_lost"][0]:
		return "won"
	if out["hp_lost"][0] > out["hp_lost"][1]:
		return "lost"
	return "even"


## After a fight with neutrals, they go back to their ground, beaten or victorious
## (user's playtest notes, 2026-11-09). Empty when side 1 isn't neutral.
static func neutral_line(b: Battle, out: Dictionary) -> String:
	if b.sides[1].side != "neutral":
		return ""
	return "The %s %s and return to the %s." % [b.sides[1].name,
			"are beaten back" if battle_result(out) == "won" else "are victorious", str(b.terrain["name"]).to_lower()]


## A one-line result for the map's banner. The player's squad wins or loses (against
## neutrals, who then go home); a fight between two computer squads just says what happened.
static func battle_summary(b: Battle, out: Dictionary) -> String:
	if b.sides[0].side == "player":
		var result := battle_result(out)
		if b.sides[1].side == "neutral":
			return "%s %s. %s" % [b.sides[0].name, "wins" if result == "won" else "loses", neutral_line(b, out)]
		return "%s %s." % [b.sides[0].name, {"won": "wins the battle", "lost": "loses the battle",
				"retreated": "retreats from the battle", "even": "fights the enemy to a draw"}[result]]
	var who := [b.sides[0].name, b.sides[1].name]
	var text := "%s %s %s: lost %d%% of its HP, took %d%% of theirs." % [who[0],
			"fired on" if b.ranged_only else "fought", who[1], roundi(out["hp_lost"][0] * 100), roundi(out["hp_lost"][1] * 100)]
	for side in 2:
		if out["wiped"][side]:
			text += " %s was wiped out." % who[side]
		elif out["leader_dead"][side]:
			text += " %s lost its leader." % who[side]
	if out["retreated"] >= 0:
		text += " %s retreated." % who[out["retreated"]]
	if out["pushed"] >= 0:
		text += " %s was pushed back." % who[out["pushed"]]
	return text


## Hidden sight radius from `viewer` to a hex (§8.5): 7, +2 if the viewer flies, +1 on
## its travel-type terrain (else −1), −2 if the target is in mountains, −1 in forest.
## Clamped to 5–10.
func sight(viewer: Squad, target_hex: int) -> int:
	var r: Dictionary = data.rules["sight"]
	var v := int(r["base"])
	if viewer.sky:
		v += int(r["flying"])
	v += int(r["on_travel_terrain"]) if _on_travel_terrain(viewer) else int(r["off_travel_terrain"])
	v += int(r["target_terrain"].get(data.terrains[map.terrain[target_hex]]["key"], 0))
	if viewer.side == "player":  # Aerial Scouts, Outriders: past the usual cap
		if viewer.sky:
			v += int(tech_value("aerial_scouts", "sight"))
		if viewer.living().any(func(u: Unit): return u.has_tag(data, "mounted")):
			v += int(tech_value("outriders", "sight"))
		return clampi(v, int(r["range"][0]), int(r["range"][1]) + int(tech_value("aerial_scouts", "sight") + tech_value("outriders", "sight")))
	return clampi(v, int(r["range"][0]), int(r["range"][1]))


## Whether any player squad can see this hex.
func seen(target_hex: int) -> bool:
	for s in squads:
		if s.side == "player" and not s.living().is_empty() \
				and Hex.distance(map.hex_at(s.hex), map.hex_at(target_hex)) <= sight(s, target_hex):
			return true
	return false


## Player squads always show; others only within sight.
func is_visible(s: Squad) -> bool:
	return s.side == "player" or debug_reveal or seen(s.hex)


func _reveal_sites() -> void:
	for i in map.buildings.size():
		var b: Dictionary = map.buildings[i]
		if (b["hidden"] or b["type"] == "lair") and not revealed.has(i) and seen(b["hex"]):
			revealed[i] = true
			log.add(clock.tick, "map", "A hidden site comes into view at %s." % map.hex_at(b["hex"]))
			if b["hidden"]:  # found (§13); lairs aren't hidden sites
				draw_card(_spotter(b["hex"]))


## The first of your squads that can see the hex.
func _spotter(target_hex: int) -> Squad:
	for s in player_squads():
		if Hex.distance(map.hex_at(s.hex), map.hex_at(target_hex)) <= sight(s, target_hex):
			return s
	return null


# --- Ranged map attacks (SPEC §11.2) ----------------------------------------------------

func can_fire(s: Squad) -> bool:
	for u in s.living():
		var kind: String = u.info(data)["front_attack" if u.row == "front" else "back_attack"]
		if Battle.base_kind(kind) in data.rules["ranged_attack"]["attack_kinds"]:
			return true
	return false


## 2 hexes, or 3 from high ground (mountains, towers); a longbow adds its range.
func fire_range(s: Squad) -> int:
	var r: Dictionary = data.rules["ranged_attack"]
	var high: bool = data.terrains[map.terrain[s.hex]]["key"] in r["high_ground_terrains"]
	for b in map.buildings:
		if b["hex"] == s.hex and b["type"] in r["high_ground_buildings"]:
			high = true
	var extra := 0
	for u in s.living():
		for slot in u.items:
			extra = maxi(extra, int(data.items["items"][u.items[slot]["id"]].get("range", 0)))
	return (int(r["high_ground_range"]) if high else int(r["range"])) + extra


## Visible hostile squads within range, if the squad has ranged units and its cooldown is over.
func fire_targets(s: Squad) -> Array[Squad]:
	var out: Array[Squad] = []
	if not can_fire(s) or clock.tick < s.fire_ready:
		return out
	for e in squads:
		if hostile(s, e) and is_visible(e) and not e.living().is_empty() \
				and Hex.distance(map.hex_at(s.hex), map.hex_at(e.hex)) <= fire_range(s):
			out.append(e)
	return out


## A ranged map attack: only Ranged and Magic units on both sides act, no push-back.
## Starts the squad's 120-tick cooldown and leaves the battle pending, like contact.
func fire(s: Squad, target: Squad) -> void:
	var b := start_battle(s, target, target)
	b.ranged_only = true
	for side in 2:
		for u in b.sides[side].living():
			b._join(u)
	s.fire_ready = clock.tick + int(data.rules["ranged_attack"]["cooldown_ticks"])
	pending = b


# --- Battles (SPEC §11) ------------------------------------------------------------

## Opens a battle between a player squad and an enemy, fought on the defender's hex.
func start_battle(player: Squad, enemy: Squad, defender: Squad) -> Battle:
	var info: Dictionary = data.terrains[map.terrain[defender.hex]]
	var stream := rng.get_stream("battle")
	if player.side == "player":
		last_battle = DebugTools.snapshot(player, enemy, stream)
	var b := Battle.new(data, player, enemy, info["key"], clock.is_day(), stream, settings.get("fairness", "both"))
	b.fairness_rules = debug_fairness.duplicate()
	b.attacker = 0 if defender == enemy else 1
	b.defense = [building_defense(player), building_defense(enemy)]
	b.odds = Threat.label(data, player, enemy)
	if player.side == "player":
		b.tech[0] = tech
	log.add(clock.tick, "battle", "Battle: %s against %s on %s. The enemy looks %s." % [player.name, enemy.name, info["name"],
			Threat.label(data, player, enemy).to_lower()], player.id)
	if player.side == "player":
		last_battle["battle"] = b
		if debug_force != "":
			DebugTools.force(b, debug_force)
	return b


## Ends a battle and applies its outcome on the map (§11.3, §11.6): a wiped-out player
## squad returns to base (anyone else leaves the map), a squad that lost its leader
## marches home (a neutral has none to march to, so it just fights on), a retreating
## squad steps back 1 hex and each unit loses 1 charisma, and the side that lost more
## of its HP is pushed back. Standing and XP are player-only (§16: an enemy-neutral
## fight has no player squad in it at all).
func end_battle(b: Battle) -> Dictionary:
	for e in b.events:
		log.add(clock.tick, "battle", b.log_line(e), b.sides[0].id, e.get("hidden", {}))
	var out := b.finish()
	for side in 2:
		var s := b.sides[side]
		var enemy := b.sides[1 - side]
		if out["wiped"][side]:
			s.path.clear()
			s.rally.clear()
			if s.side == "player":
				_leave_map(s)
				log.add(clock.tick, "battle", "%s is wiped out and carried back to base." % s.name, s.id)
			else:
				squads.erase(s)
				if s.side == "enemy":
					enemy_squads_defeated += 1
				log.add(clock.tick, "battle", "%s is wiped out." % s.name, s.id)
			continue
		if out["retreated"] == side:
			_push(s, enemy.hex, 1)
			if s.side == "player":
				change_charisma(s.units, -1, "retreating")
		elif out["pushed"] == side:
			_push(s, enemy.hex, int(data.battle["push_back"]["on_travel_terrain" if _on_travel_terrain(s) else "otherwise"]))
		if out["leader_dead"][side] and not s.marching_home and s.side != "neutral":
			s.marching_home = true
			order_move(s, PackedInt32Array([map.player_base if s.side == "player" else map.enemy_base]))
			s.entering_base = s.side == "player"
			log.add(clock.tick, "battle", "%s lost its leader and marches home." % s.name, s.id)
	_update_morale(b, out)
	_update_bonds(b)
	_update_loyalty_wins(b, out)
	_battle_standing(b, out)
	_award_xp(b, out)
	_neutral_leaves(b, out)
	return out


## A neutral squad is met once (user's playtest notes, 2026-11-09): after any battle
## with the player, win or lose, it goes back to its ground and leaves the map.
## The player's squad is always side 0, so a neutral here is side 1.
func _neutral_leaves(b: Battle, out: Dictionary) -> void:
	var s := b.sides[1]
	if s.side == "neutral" and b.sides[0].side == "player" and s in squads:
		squads.erase(s)
		log.add(clock.tick, "map", neutral_line(b, out), b.sides[0].id)


## Morale (§12.2): falls when outnumbered, the leader is hit, a unit dies, off home
## terrain (the leader's native one) or fighting at the wrong time of day (holy by
## night, evil by day); rises on a win. Both sides, win or lose, so an enemy or
## neutral squad's morale can fall low enough to be driven off (§11.6) too.
func _update_morale(b: Battle, out: Dictionary) -> void:
	var m: Dictionary = data.battle["morale"]
	for side in 2:
		var s := b.sides[side]
		var delta := 0
		var why: Array[String] = []
		if b.fought[side].size() < b.fought[1 - side].size():
			delta += int(m["outnumbered"])
			why.append("outnumbered")
		if s.leader and b.events.any(func(e): return e.get("type", "") == "attack" and e.get("hit", false) and e.get("target") == s.leader):
			delta += int(m["leader_hit"])
			why.append("leader hit")
		if b.fought[side].any(func(u: Unit): return not u.is_alive()):
			delta += int(m["unit_died"])
			why.append("a unit died")
		if s.leader and b.terrain["key"] != data.rules["travel_types"].get(s.leader.terrain(data), ""):
			delta += int(m["off_home_terrain"])
			why.append("off home terrain")
		var band := s.alignment_band(data)
		if (band == "holy" and not b.daytime) or (band == "evil" and b.daytime):
			delta += int(m["wrong_time_of_day"])
			why.append("the wrong time of day")
		if _won(out, side):
			delta += int(m["win"])
			why.append("a win")
		change_morale(s, delta, ", ".join(why))


## Bonds (§12.2): two units that fight battles_to_bond battles together in the same
## squad gain +5% damage and +5% dodge (Battle.gd) while both live; announced once.
func _update_bonds(b: Battle) -> void:
	var need := int(data.battle["bonds"]["battles_to_bond"])
	for side in 2:
		var squad := b.sides[side]
		var together: Array = b.fought[side]
		for i in together.size():
			for j in range(i + 1, together.size()):
				var a: Unit = together[i]
				var c: Unit = together[j]
				var key := "%d:%d" % [mini(a.get_instance_id(), c.get_instance_id()), maxi(a.get_instance_id(), c.get_instance_id())]
				squad.bond_battles[key] = int(squad.bond_battles.get(key, 0)) + 1
				var already: bool = squad.bonded_pairs.any(func(p: Array): return (p[0] == a and p[1] == c) or (p[0] == c and p[1] == a))
				if squad.bond_battles[key] >= need and not already:
					squad.bonded_pairs.append([a, c])
					log.add(clock.tick, "progression", "%s and %s have fought enough battles together to trust each other: they're bonded." % [a.name, c.name], squad.id)


## Loyalty (§12.2): a recruited unit's loyalty rises after a win.
func _update_loyalty_wins(b: Battle, out: Dictionary) -> void:
	for side in 2:
		if not _won(out, side):
			continue
		for u in b.fought[side]:
			if u.recruited:
				change_loyalty(u, int(data.rules["loyalty"]["win"]), "winning a battle")


## Every living unit of your squad earns XP (§9.4) and may level up; a leader reaching
## level 5, 10, 15 or 20 with enough charisma opens a slot (§8.2). Adds "xp" (unit ->
## amount) and "level_ups" (lines for the result screen) to the outcome.
func _award_xp(b: Battle, out: Dictionary) -> void:
	var s := b.sides[0]
	out["xp"] = {}
	out["level_ups"] = []
	if s.side != "player":  # an enemy-neutral fight (§6.7): no one to award XP to
		return
	# The share of the enemy's losses dealt by cards goes to the Opinion Leader's squad (§9.4, §13).
	var share := clampf(float(b.card_damage) / maxi(1, b.hp_lost(1)), 0.0, 1.0)
	var leader_squad := opinion_leader_squad()
	if leader_squad == s:
		share = 0.0
	var redirected := 0
	var retreat := float(data.rules["progression"]["retreat_xp_share"]) if out["retreated"] == 0 else 1.0
	for u in s.living():
		if u not in army.units():
			continue
		var full := roundi(Progression.battle_xp(data, s, b.sides[1], u) * retreat)
		var amount := roundi(full * (1.0 - share))
		redirected = maxi(redirected, full - amount)
		out["xp"][u] = amount
		_give_xp(s, u, amount, out)
	if redirected > 0 and leader_squad:
		for u in leader_squad.living():
			_give_xp(leader_squad, u, redirected, out)
		log.add(clock.tick, "progression", "%s earns %d XP each from the cards played." % [leader_squad.name, redirected], leader_squad.id)
	if not out["xp"].is_empty():
		log.add(clock.tick, "progression", "%s earns %s XP." % [s.name, "/".join(PackedStringArray(out["xp"].values().map(func(x): return str(x))))], s.id)


## Adds XP to a unit, with level-ups and the leader's slot growth (§8.2).
func _give_xp(s: Squad, u: Unit, amount: int, out: Dictionary) -> void:
		for gains in Progression.gain_xp(data, u, amount, rng.get_stream("progression")):
			var line := "%s%s reaches level %d: %s." % ["A prodigy shines! " if u.talent == "prodigy" else "", u.name, u.level, Progression.gains_text(gains)]
			out["level_ups"].append(line)
			log.add(clock.tick, "progression", line, s.id, {"growth": u.growth, "talent": u.talent})
			if u == s.leader and s.check_slot_growth(data):
				out["level_ups"].append("%s can now lead %d slots." % [u.name, s.capacity(data)])
				log.add(clock.tick, "progression", out["level_ups"][-1], s.id)


## Promotes a unit at base into one of its options (§9.4). Returns why not, or "" on success.
func promote(u: Unit, new_class: String) -> String:
	if not at_base(u):
		return "Promote at the Player Base."
	if new_class not in Progression.promotion_options(data, u):
		return "%s can't become a %s now." % [u.name, new_class]
	var s := army.squad_of(u)
	var old := u.unit_class
	if s:
		u.unit_class = new_class
		var fits := Squad.slots_filled(data, s.units) <= s.capacity(data)
		u.unit_class = old
		if not fits:
			return "A %s needs more room than %s has." % [new_class, s.name]
	var gains := Progression.promote(data, u, new_class)
	if s:
		if s.leader == u and not u.info(data)["can_lead"]:
			s.leader = army.best_leader(s)  # the new class can't lead: the next best unit takes over
		s.refresh(data)
	log.add(clock.tick, "progression", "%s is promoted from %s to %s: %s." % [u.name, old, new_class, Progression.gains_text(gains)], s.id if s else -1)
	_apply_tech()
	return ""


## Whether the battle hex is the squad's travel-type terrain (flyers always are).
func _on_travel_terrain(s: Squad) -> bool:
	if s.sky:
		return true
	var info: Dictionary = data.terrains[map.terrain[s.hex]]
	return s.travel_type != "" and (info["key"] == s.travel_type or info.get("native_as", "") == s.travel_type)


## Moves a squad up to `steps` hexes directly away from `from`, through hexes it can
## enter that no other squad holds. Its orders are dropped.
func _push(s: Squad, from: int, steps: int) -> void:
	s.path.clear()
	s.rally.clear()
	s.progress = 0.0
	var origin := map.hex_at(from)
	var start := s.hex
	for i in steps:
		var best := -1
		for n in map.neighbor_indices(s.hex):
			if pathfinder.hex_cost(n, s.travel_type, s.sky) == INF or _hostile_at(n, s):
				continue
			if best < 0 or Hex.distance(map.hex_at(n), origin) > Hex.distance(map.hex_at(best), origin):
				best = n
		if best < 0 or Hex.distance(map.hex_at(best), origin) <= Hex.distance(map.hex_at(s.hex), origin):
			break
		s.hex = best
	if s.hex != start:
		log.add(clock.tick, "battle", "%s is pushed back to %s." % [s.name, map.hex_at(s.hex)], s.id)


## Whether a squad hostile to s stands on the hex. Your squads can share hexes; hostile ones can't.
func _hostile_at(i: int, s: Squad) -> bool:
	for o in squads:
		if o.hex == i and hostile(s, o):
			return true
	return false


## The leader's charisma %, halved if the enemy's morale is 10–25; none at 25 or more (§11.6).
func drive_off_chance(s: Squad, enemy: Squad) -> float:
	var d: Dictionary = data.battle["drive_off"]
	if s.leader == null or not s.leader.is_alive() or enemy.morale >= int(d["morale_below"]):
		return 0.0
	var c := s.leader.charisma / 100.0
	return c / 2.0 if enemy.morale >= int(d["halved_from"]) else c


## Demands that a beaten enemy flee. On success it leaves the map for good.
func drive_off(s: Squad, enemy: Squad) -> bool:
	var ok := rng.get_stream("battle").randf() < drive_off_chance(s, enemy)
	if ok:
		squads.erase(enemy)
		if enemy.side == "enemy":
			enemy_squads_defeated += 1
	log.add(clock.tick, "battle", "%s %s." % [enemy.name, "flees the map" if ok else "refuses to flee"], s.id)
	return ok


static func duration_text(ticks: float) -> String:
	var minutes := roundi(ticks)
	return "%d h %02d m" % [minutes / 60, minutes % 60] if minutes >= 60 else "%d m" % minutes


func _move(s: Squad) -> void:
	if not s.is_moving():
		return
	s.progress += 1.0
	while s.is_moving() and s.progress >= step_ticks(s, s.path[0]):
		if _hostile_at(s.path[0], s):  # an enemy holds it: wait at the edge
			s.progress = step_ticks(s, s.path[0])
			break
		s.progress -= step_ticks(s, s.path[0])
		s.hex = s.path[0]
		s.path = s.path.slice(1)
		_moved[s] = true
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
