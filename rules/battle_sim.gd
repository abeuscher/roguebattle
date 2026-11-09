class_name BattleSim
## Headless battle simulation (SPEC §12.4, §19.2): many battles between two squad
## builds, freshly rolled each trial. Reports win rate, HP lost per battle and how
## many battles it takes to rout the loser with no healing in between. A squad is
## routed when it's wiped out or its leader dies (it then marches home, §11.3).

const MAX_BATTLES := 10  # a trial that hasn't routed anyone by then counts as a draw


## A squad rolled from a build: [[class, row], ...]; the first unit able to lead leads.
static func roll_squad(data: GameData, build: Array, rng: RandomNumberGenerator, names: NameBook, id: int) -> Squad:
	var s := Squad.new(id, "Side %d" % id, 0)
	for m in build:
		s.add(data, Unit.roll(data, m[0], rng, names), m[1])
	return s


## Runs `trials` trials. Each trial rolls both squads and fights until one is routed.
## Returns win shares, the first battle's HP loss for the eventual loser and winner,
## and the average number of battles to rout.
static func run(data: GameData, build_a: Array, build_b: Array, trials: int, seed: int,
		terrain := "plains", daytime := true) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	var wins := [0, 0]
	var draws := 0
	var loser_lost := 0.0
	var winner_lost := 0.0
	var battles_total := 0
	var threat_ratio := 0.0
	var alive := {"front": 0, "back": 0}  # units still standing after each trial's first battle, both sides
	var seen := {"front": 0, "back": 0}
	for trial in trials:
		var names := NameBook.new(data)
		var sides := [roll_squad(data, build_a, rng, names, 1), roll_squad(data, build_b, rng, names, 2)]
		threat_ratio += Threat.squad(data, sides[1]) / maxf(0.001, Threat.squad(data, sides[0]))
		var first_lost := [0.0, 0.0]
		var battles := 0
		var winner := -1
		while battles < MAX_BATTLES:
			var b := Battle.new(data, sides[0], sides[1], terrain, daytime, rng)
			b.attacker = trial % 2  # alternate who starts, so Charge-type effects even out
			b.run()
			var out := b.finish()
			if battles == 0:
				first_lost = out["hp_lost"]
				for s in sides:
					for u in s.units:
						seen[u.row] += 1
						alive[u.row] += int(u.is_alive())
			battles += 1
			var routed := [out["wiped"][0] or out["leader_dead"][0], out["wiped"][1] or out["leader_dead"][1]]
			if routed[0] != routed[1]:
				winner = 1 if routed[0] else 0
				break
			if routed[0]:  # both routed in the same battle: the one that lost more of its HP loses
				winner = 1 if out["hp_lost"][0] > out["hp_lost"][1] else 0
				break
		if winner < 0:
			draws += 1
			continue
		wins[winner] += 1
		battles_total += battles
		loser_lost += first_lost[1 - winner]
		winner_lost += first_lost[winner]
	var decided := maxi(1, trials - draws)
	return {"trials": trials, "win_a": float(wins[0]) / trials, "win_b": float(wins[1]) / trials,
			"draws": float(draws) / trials, "loser_hp_lost": loser_lost / decided,
			"winner_hp_lost": winner_lost / decided, "battles_to_rout": float(battles_total) / decided,
			"threat_ratio": threat_ratio / trials,
			"front_survival": float(alive["front"]) / maxi(1, seen["front"]),
			"back_survival": float(alive["back"]) / maxi(1, seen["back"])}


static func report(name_a: String, name_b: String, r: Dictionary) -> String:
	return "%s vs %s (%d trials, threat ratio %.2f): %s wins %.0f%%, %s wins %.0f%%, draws %.0f%%. First battle: loser loses %.0f%% HP, winner %.0f%%. Battles to rout: %.1f. Survive the first battle: front %.0f%%, back %.0f%%" % [
			name_a, name_b, r["trials"], r["threat_ratio"], name_a, r["win_a"] * 100, name_b, r["win_b"] * 100,
			r["draws"] * 100, r["loser_hp_lost"] * 100, r["winner_hp_lost"] * 100, r["battles_to_rout"], r["front_survival"] * 100, r["back_survival"] * 100]
