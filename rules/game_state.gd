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
	log.add(clock.tick, "system", "New map: seed %d, %s %s." % [map.seed, map.settings["preset"], map.settings["size"]],
			-1, {"settings": map.settings, "game": settings})


## Runs the simulation for one tick. Stops early if two hostile squads meet:
## `pending` then holds the battle until resolve_pending().
func step() -> void:
	if pending:
		return
	for event in clock.step():
		_clock_event(event)
	_moved.clear()
	_run_enemy_ai()
	for s in squads.duplicate():
		_move(s)
		if s.entering_base and s.hex == map.player_base:
			return_to_base(s)
	_capture()
	_reveal_sites()
	_check_contact()


## Daily rest, nomads every half day, the noon ledger (§7).
func _clock_event(event: String) -> void:
	if event == "new_day":
		log.add(clock.tick, "system", "Day %d begins." % clock.day())
		_rest()
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
		army.cells[i] = s
		if i == 0:
			squads.append(s)
	for i in int(data.cards["start"]):
		draw_card(null)


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
## (and nomads, as towns) give more to squads of their alignment; a base gives its own side.
func building_effect(b: Dictionary, s: Squad) -> Array:
	var info: Dictionary = data.buildings[b["type"]]
	if info.has("own_base"):
		var own: bool = info["owner"] == ("player" if s.side == "player" else "enemy")
		return [float(info["own_base"]["defense"]), float(info["own_base"]["rest"])] if own else [0.0, 0.0]
	if not info.has("defense"):
		return [0.0, 0.0]
	var k := 1 if info.get("aligned", "") == s.alignment_band(data) else 0
	return [float(info["defense"][k]), float(info["rest"][k])]


func building_defense(s: Squad) -> float:
	var b := building_at(s.hex)
	return building_effect(b, s)[0] if not b.is_empty() else 0.0


## Liberation (§6.5): a player squad with a living ground unit that stays in an enemy-held
## town or tower for 60 ticks takes it; Sapper lines take it twice as fast.
func _capture() -> void:
	var c: Dictionary = data.rules["capture"]
	for s in player_squads():
		var b := building_at(s.hex)
		if s.is_moving() or b.is_empty() or not data.buildings[b["type"]].get("capturable", false) or b["owner"] == "player" \
				or not s.living().any(func(u: Unit): return not u.has_tag(data, "flyer")):
			s.capture_ticks = 0.0
			continue
		var sapper := s.living().any(func(u: Unit): return u.has_tag(data, "sapper"))
		s.capture_ticks += float(c["sapper_speed"]) if sapper else 1.0
		if s.capture_ticks >= float(c["ticks"]):
			s.capture_ticks = 0.0
			b["owner"] = "player"
			log.add(clock.tick, "map", "%s liberates the %s at %s." % [s.name, data.buildings[b["type"]]["name"].to_lower(), map.hex_at(s.hex)], s.id)
			var bonus := liberation_bonus()
			gold += bonus
			log.add(clock.tick, "economy", "Liberation bonus: %d gold." % bonus, s.id, {"reputation": reputation})
			_liberated(s, b)


## Standing changes for a liberation (§9.5, §9.6, §10): reputation by the squad's
## alignment, +5 charisma for a leader whose alignment matches the building, and each
## unit's alignment +3 for a town or −3 for a tower.
func _liberated(s: Squad, b: Dictionary) -> void:
	var st: Dictionary = data.rules["standing"]
	var aligned: String = data.buildings[b["type"]].get("aligned", "")
	var what: String = data.buildings[b["type"]]["name"].to_lower()
	change_reputation(s, _swing(aligned, s.alignment_band(data)) * int(st["liberate_reputation"]), "%s liberated a %s" % [s.name, what])
	if s.leader and s.leader.alignment_band(data) == aligned:
		change_charisma([s.leader], int(st["liberate_charisma"]), "liberating a %s that matches their alignment" % what)
	change_alignment(s.units, int(st["liberate_alignment"]) * (1 if aligned == "holy" else -1), "liberating a %s" % what)
	draw_card(s)
	earn_tech_points(int(data.tech["points"]["liberation"]), "a liberation")


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


## Daily rest (§6.5): squads in buildings heal their living units by the building's
## share of max HP; squads and recruits at the Player Base rest as in their own base.
func _rest() -> void:
	for s in squads:
		var b := building_at(s.hex)
		if not b.is_empty():
			_heal_share(s.living(), building_effect(b, s)[1])
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


## After a battle (§9.5, §9.6): each living unit of your squad shifts alignment +2
## against an equal or stronger enemy and −2 against a weaker one; after a win, each
## gains 1 charisma against a stronger enemy and loses 1 against a much weaker one.
## A win: the enemy is wiped out, or (no one retreated) it lost the larger share of its HP.
func _battle_standing(b: Battle, out: Dictionary) -> void:
	var st: Dictionary = data.rules["standing"]
	var units := b.sides[0].living().filter(func(u: Unit): return u in army.units())
	var weaker := b.odds in ["Weaker", "Much weaker"]
	change_alignment(units, int(st["battle_alignment"]) * (-1 if weaker else 1), "fighting a %s enemy" % b.odds.to_lower())
	var won: bool = out["wiped"][1] or (out["retreated"] < 0 and out["hp_lost"][1] > out["hp_lost"][0])
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


## The items a shop sells, rolled once per shop.
func shop_stock(b: Dictionary) -> Array:
	if not b.get("shop", false):
		return []
	if not b.has("stock"):
		var r := rng.get_stream("shops")
		var ids: Array = data.items["items"].keys().filter(func(id): return data.items["items"][id].get("requires", "") in tech or not data.items["items"][id].has("requires"))
		b["stock"] = []
		for i in int(data.rules["economy"]["shop_items"]):
			b["stock"].append(ids[r.randi() % ids.size()])
	return b["stock"]


func item_price(id: String, s: Squad = null) -> int:
	return price(int(data.items["items"][id]["price"]), s)


func supply_price(id: String, s: Squad = null) -> int:
	return price(int(data.items["consumables"][id]["price"]), s)


func serf_price(s: Squad = null) -> int:
	return price(int(data.rules["economy"]["serf_price"]), s)


func buy_item(b: Dictionary, id: String, s: Squad = null) -> bool:
	var stock := shop_stock(b)
	var cost := item_price(id, s)
	if id not in stock or gold < cost:
		return false
	gold -= cost
	stock.erase(id)
	army.add_item(id)
	log.add(clock.tick, "economy", "Bought a %s for %d gold." % [data.items["items"][id]["name"], cost])
	return true


func buy_supply(b: Dictionary, id: String, s: Squad = null) -> bool:
	var cost := supply_price(id, s)
	if not b.get("shop", false) or gold < cost:
		return false
	gold -= cost
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


## Uses a consumable on a living unit that needs it (a Herb heals 30 HP).
func use_supply(u: Unit, id: String) -> bool:
	var item: Dictionary = data.items["consumables"][id]
	if int(army.supplies.get(id, 0)) <= 0 or not u.is_alive() or u.hp >= u.max_hp(data):
		return false
	army.supplies[id] = int(army.supplies[id]) - 1
	u.hp = mini(u.max_hp(data), u.hp + int(item["heal"]))
	log.add(clock.tick, "economy", "%s uses a %s." % [u.name, item["name"]])
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


func hostile(a: Squad, b: Squad) -> bool:
	return (a.side == "player") != (b.side == "player")


# --- Enemy squads (SPEC §17, §12.3 AI) -----------------------------------------------

## Gives an idle enemy squad a new order from EnemyAI.target_hex, if it needs one
## (none if it's already there or already moving).
func _run_enemy_ai() -> void:
	for s in squads:
		if s.side != "enemy" or s.is_moving() or s.living().is_empty():
			continue
		var target := EnemyAI.target_hex(self, s)
		if target >= 0 and target != s.hex:
			order_move(s, PackedInt32Array([target]))


## Places the enemy's squads by role: the leader on the Enemy Base, the base guard and
## raider next to it, garrisons and wildcards on separate enemy-held buildings
## (towns and towers until liberation arrives). A wildcard rolls Attack or Defend
## once here (§17); the leader, base guard and garrisons just hold their post.
func place_enemies() -> void:
	var e: Dictionary = data.enemy
	var r := rng.get_stream("enemy")
	var sites := []
	for b in map.buildings:
		if b["type"] in e["enemy_buildings"]:
			sites.append(b["hex"])
	for i in range(sites.size() - 1, 0, -1):  # seeded shuffle
		var j := r.randi_range(0, i)
		var t = sites[i]
		sites[i] = sites[j]
		sites[j] = t
	var builds: Array = e["builds"]
	for entry in e["roles"]:
		var count := int(entry["count"])
		for k in count:
			var at := -1
			match entry["at"]:
				"enemy_base":
					at = map.enemy_base
				"near_enemy_base":
					at = _free_near(map.enemy_base)
				_:
					while not sites.is_empty() and at < 0:
						var h: int = sites.pop_front()
						if _squad_on(h) == null:
							at = h
			if at < 0:
				at = _free_near(map.enemy_base)
			var title: String = e["names"][entry["role"]]
			var s := add_squad("%s %d" % [title, k + 1] if count > 1 else title, at, builds[r.randi() % builds.size()], "enemy")
			s.role = entry["role"]
			if s.role == "wildcard":
				s.ai_mode = "attack" if r.randf() < float(data.ai["wildcard_attack_chance"]) else "defend"


## The nearest hex to `center` (not center itself) that a ground squad can stand on and no squad holds.
func _free_near(center: int) -> int:
	var seen_hexes := {center: true}
	var frontier := [center]
	while not frontier.is_empty():
		var next := []
		for h in frontier:
			for n in map.neighbor_indices(h):
				if seen_hexes.has(n):
					continue
				seen_hexes[n] = true
				if Movement.hex_multiplier(map, data, n) < INF and _squad_on(n) == null:
					return n
				next.append(n)
		frontier = next
	return center


func _squad_on(i: int) -> Squad:
	for s in squads:
		if s.hex == i:
			return s
	return null


# --- Contact and sight (SPEC §11.1, §8.5) -------------------------------------------------

## Two hostile squads on the same or adjacent hexes fight. The squad that moved into
## contact attacks; the battle uses the defender's hex. A pair that just fought waits
## a short cooldown before fighting again.
func _check_contact() -> void:
	for p in squads:
		if p.side != "player" or p.living().is_empty():
			continue
		for e in squads:
			if not hostile(p, e) or e.living().is_empty():
				continue
			if Hex.distance(map.hex_at(p.hex), map.hex_at(e.hex)) > 1:
				continue
			if clock.tick < int(_contact_until.get(_pair(p, e), -1)):
				continue
			var defender := e if _moved.has(p) or not _moved.has(e) else p
			pending = start_battle(p, e, defender)
			return


func _pair(p: Squad, e: Squad) -> String:
	return "%d:%d" % [p.id, e.id]


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


static func battle_summary(b: Battle, out: Dictionary) -> String:
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
	return s.side == "player" or seen(s.hex)


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
	var b := Battle.new(data, player, enemy, info["key"], clock.is_day(), rng.get_stream("battle"), settings.get("fairness", "both"))
	b.attacker = 0 if defender == enemy else 1
	b.defense = [building_defense(player), building_defense(enemy)]
	b.odds = Threat.label(data, player, enemy)
	b.tech[0] = tech
	log.add(clock.tick, "battle", "Battle: %s against %s on %s. The enemy looks %s." % [player.name, enemy.name, info["name"],
			Threat.label(data, player, enemy).to_lower()], player.id)
	return b


## Ends a battle and applies its outcome on the map (§11.3, §11.6): a wiped-out player
## squad returns to base (an enemy one leaves the map), a squad that lost its leader
## marches home, a retreating squad steps back 1 hex and each unit loses 1 charisma,
## and the side that lost more of its HP is pushed back.
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
			if side == 0:
				_leave_map(s)
				log.add(clock.tick, "battle", "%s is wiped out and carried back to base." % s.name, s.id)
			else:
				squads.erase(s)
				log.add(clock.tick, "battle", "%s is wiped out." % s.name, s.id)
			continue
		if out["retreated"] == side:
			_push(s, enemy.hex, 1)
			if side == 0:
				change_charisma(s.units, -1, "retreating")
		elif out["pushed"] == side:
			_push(s, enemy.hex, int(data.battle["push_back"]["on_travel_terrain" if _on_travel_terrain(s) else "otherwise"]))
		if out["leader_dead"][side] and not s.marching_home:
			s.marching_home = true
			order_move(s, PackedInt32Array([map.player_base if side == 0 else map.enemy_base]))
			s.entering_base = side == 0
			log.add(clock.tick, "battle", "%s lost its leader and marches home." % s.name, s.id)
	_battle_standing(b, out)
	_award_xp(b, out)
	return out


## Every living unit of your squad earns XP (§9.4) and may level up; a leader reaching
## level 5, 10, 15 or 20 with enough charisma opens a slot (§8.2). Adds "xp" (unit ->
## amount) and "level_ups" (lines for the result screen) to the outcome.
func _award_xp(b: Battle, out: Dictionary) -> void:
	var s := b.sides[0]
	out["xp"] = {}
	out["level_ups"] = []
	# The share of the enemy's losses dealt by cards goes to the Opinion Leader's squad (§9.4, §13).
	var share := clampf(float(b.card_damage) / maxi(1, b.hp_lost(1)), 0.0, 1.0)
	var leader_squad := opinion_leader_squad()
	if leader_squad == s:
		share = 0.0
	var redirected := 0
	for u in s.living():
		if u not in army.units():
			continue
		var full := Progression.battle_xp(data, s, b.sides[1], u)
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
