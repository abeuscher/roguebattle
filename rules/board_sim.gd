class_name BoardSim
extends RefCounted
## Headless whole-map sim (playtest round 16: enemy pace and board scale). Plays a single
## map game with a simple scripted player: as many squads as the squad cap, each built like
## an enemy squad (so the two sides are matched unit for unit), starting at the Player
## Base, and each idle squad sent to the nearest town, tower or temple it doesn't hold that
## no other squad of yours is heading for (the "scramble" the user described). The Opinion
## Leader defeat is off, so a run plays its full length.
## The enemy plays as in the game. Battles resolve on their own; meetings with neutrals
## fight. It measures, over `days` game days:
## - the share of towns, towers and temples each side holds, every 6 game hours;
## - how many battles the player fought;
## - the response gap: whenever the enemy starts taking a building of yours, how many hexes
##   away your nearest squad was.

const SAMPLE_TICKS := 360  # every 6 game hours
const KINDS := ["town", "tower", "temple"]
const RETURN_TICKS := 720  # half a game day to revive and redeploy
const AREA := 50  # hexes on a side of the squares battles are counted in (the spread of the fighting)


static func run(data: GameData, width: int, height: int, seed: int, days: float, overrides := {}, respond := true) -> Dictionary:
	var cfg := GameConfig.create(data, seed)
	cfg.set_value("width", width)
	cfg.set_value("height", height)
	cfg.set_value("defeat_leader", false)
	for k in overrides:
		cfg.set_value(k, overrides[k])
	var map := MapGen.generate(data, cfg.seed, cfg.map_overrides())
	var st := GameState.new(data, map, GameLog.new(), cfg.game_settings())
	st.place_enemies()
	st.place_neutrals()
	st.gold = 1000000  # the sim measures the board, not the purse
	var mine := _field_squads(st)
	var away := {}  # squad -> the tick it left the map (wiped out, or home leaderless)
	var places := map.buildings.filter(func(b): return b["type"] in KINDS)
	var out := {"size": "%dx%d" % [width, height], "places": places.size(), "your_squads": 0, "enemy_squads": 0,
			"samples": [], "battles": 0, "first_battle": -1, "gaps": [], "held": 0, "lost": 0, "spots": {}, "end": "", "tech": []}
	var t := 0
	var started := {}  # building hex -> true while the enemy is mid-capture of it (so each attempt counts once)
	while t < days * GameClock.TICKS_PER_DAY and st.game_over == "":
		_return(st, mine, away, t)
		if t % SAMPLE_TICKS == 0 and mine.size() < st.field_cap():  # the cap grew with buildings held (round 19): form another
			mine.append(_field_squad(st, mine.size()))
		_orders(st, places)
		st.step()
		t += 1
		if st.pending:
			if st.pending.sides[0].side == "player":
				if out["first_battle"] < 0:
					out["first_battle"] = t
				out["battles"] += 1
				out["spots"][_area(map, st.pending.sides[1].hex)] = true
			st.resolve_pending()
		if not st.pending_recruit.is_empty():
			st.resolve_recruit(false)
			if st.pending:
				out["battles"] += 1
				out["spots"][_area(map, st.pending.sides[1].hex)] = true
				st.resolve_pending()
		st.pending_rare = {}
		st.liberations.clear()
		st.losses.clear()
		if not st.card_offer.is_empty():
			st.choose_card(st.card_offer[0])
		for e in st.squads:
			if e.side != "enemy" or e.capture_ticks <= 0.0:
				continue
			var b := st.building_at(e.hex)
			if b.get("owner", "") != "player" or started.has(e.hex):
				continue
			started[e.hex] = true
			if respond:
				_defend(st, e.hex)
			var near := -1
			for p in st.player_squads():
				var dist := Hex.distance(map.hex_at(p.hex), map.hex_at(e.hex))
				if near < 0 or dist < near:
					near = dist
			out["gaps"].append(near)
		for h in started.keys():
			var owner: String = st.building_at(h).get("owner", "")
			if owner != "player" or not st.squads.any(func(e: Squad): return e.side == "enemy" and e.hex == h):
				out["held" if owner == "player" else "lost"] += 1
				started.erase(h)
		if t % SAMPLE_TICKS == 0:
			out["samples"].append(_shares(places))
		if t % GameClock.TICKS_PER_DAY == 0:
			out["tech"].append(st.tech_points)  # tech points earned by each day's end (none spent)
	out["your_squads"] = st.player_squads().size()
	out["enemy_squads"] = st.squads.filter(func(s: Squad): return s.side == "enemy").size()
	out["end"] = st.game_over_reason
	out["days"] = t / float(GameClock.TICKS_PER_DAY)
	return out


## As many squads as the cap, each built like an enemy squad (enemy.json builds plus the
## single map's extra members), at the Player Base.
static func _field_squads(st: GameState) -> Array:
	var out := []
	for i in st.squad_cap():
		out.append(_field_squad(st, i))
	return out


static func _field_squad(st: GameState, i: int) -> Squad:
	var r := st.rng.get_stream("board_sim")
	var builds: Array = st.data.enemy["builds"]
	var extra: Array = st.data.rules["single_map"]["enemy_builds"]["extra"]
	var members: Array = builds[r.randi() % builds.size()].duplicate()
	members += Map1Setup.extra_members(st.data, r, r.randi_range(int(extra[0]), int(extra[1])))
	var s := st.add_squad("Squad %d" % (i + 1), st.map.player_base, members)
	s.balance_rows(st.data)
	return s


## A squad of yours that left the map (wiped out, or home without its leader) comes back
## at the Player Base, healed, RETURN_TICKS later, as a player would revive and redeploy it.
static func _return(st: GameState, mine: Array, away: Dictionary, t: int) -> void:
	for s in mine:
		if s in st.squads and not s.living().is_empty() and not s.crawling():
			continue
		if not away.has(s):
			away[s] = t
		elif t - int(away[s]) >= RETURN_TICKS:
			away.erase(s)
			for u in s.units:
				u.hp = u.max_hp(st.data)
			s.refresh(st.data)
			s.hex = st.map.player_base
			s.path.clear()
			s.rally.clear()
			s.marching_home = false
			s.entering_base = false
			if s not in st.squads:
				st.squads.append(s)


## The enemy has started taking a building of yours: the squad of yours that can get there
## soonest goes to defend it, through a temple portal when it stands in a temple you hold
## and another you hold is nearer the building (what a player would do).
static func _defend(st: GameState, hex: int) -> void:
	var to := st.map.hex_at(hex)
	var best: Squad = null
	var best_cost := -1
	var best_gate := -1
	for s in st.player_squads():
		if s.crawling():
			continue
		var cost := Hex.distance(st.map.hex_at(s.hex), to)
		var gate := -1
		for g in st.portal_targets(s):
			var via := Hex.distance(st.map.hex_at(g), to)
			if via < cost:
				cost = via
				gate = g
		if best == null or cost < best_cost:
			best = s
			best_cost = cost
			best_gate = gate
	if best == null:
		return
	if best_gate >= 0:
		st.portal(best, best_gate)
	st.order_move(best, PackedInt32Array([hex]))


## Each idle squad of yours heads for the nearest town, tower or temple you don't hold that
## no other squad of yours is going for (one standing on one it doesn't hold waits there,
## taking it).
static func _orders(st: GameState, places: Array) -> void:
	var taken := {}
	for s in st.player_squads():
		if s.is_moving():
			taken[s.path[s.path.size() - 1]] = true
	for s in st.player_squads():
		if s.is_moving() or s.crawling():
			continue
		var here := st.building_at(s.hex)
		if not here.is_empty() and here["type"] in KINDS and here["owner"] != "player":
			continue
		var best := {}
		var best_d := -1
		for b in places:
			if b["owner"] == "player" or taken.has(b["hex"]):
				continue
			var d := Hex.distance(st.map.hex_at(s.hex), st.map.hex_at(b["hex"]))
			if best_d < 0 or d < best_d:
				best = b
				best_d = d
		if not best.is_empty() and st.order_move(s, PackedInt32Array([best["hex"]])):
			taken[best["hex"]] = true


## Which AREA-hex square of the map a hex is in: battles in many squares are spread over
## many fronts, in few, one lane.
static func _area(map: MapData, hex: int) -> Vector2i:
	var o := Hex.to_offset(map.hex_at(hex))
	return Vector2i(o.x / AREA, o.y / AREA)


static func _shares(places: Array) -> Array:
	var you := 0
	var them := 0
	for b in places:
		if b["owner"] == "player":
			you += 1
		elif b["owner"] == "enemy":
			them += 1
	return [you / float(maxi(1, places.size())), them / float(maxi(1, places.size()))]


## One line per run: who holds what at each day's end, battles, and the response gap.
static func report(r: Dictionary) -> String:
	var lines := PackedStringArray()
	var per_day := GameClock.TICKS_PER_DAY / SAMPLE_TICKS
	var held := PackedStringArray()
	for i in range(per_day - 1, r["samples"].size(), per_day):
		var s: Array = r["samples"][i]
		held.append("d%d %d%%/%d%%" % [i / per_day + 1, roundi(s[0] * 100), roundi(s[1] * 100)])
	var gaps: Array = r["gaps"]
	gaps.sort()
	var median: int = gaps[gaps.size() / 2] if not gaps.is_empty() else -1
	var close := gaps.filter(func(g: int): return g <= 10).size()
	lines.append("%s: %d places, first battle %s, you %d squads, enemy %d | held you/enemy: %s | battles %d in %d areas | enemy moves on yours: %d (held %d, lost %d), nearest squad median %d hexes, within 10 %d | %s" % [
			r["size"], r["places"], ("%.1f h" % (r["first_battle"] / 60.0)) if r["first_battle"] >= 0 else "none", r["your_squads"], r["enemy_squads"], ", ".join(held), r["battles"], r["spots"].size(), gaps.size(), r["held"], r["lost"], median, close,
			r["end"] if r["end"] != "" else "%.1f days" % r["days"]])
	return "\n".join(lines)
