extends SceneTree
## Headless battle sim (SPEC §12.4, §19.2). Builds come from data/sim_builds.json.
##   godot --headless --path . -s res://tools/battle_sim.gd -- <build a> <build b> [trials] [seed] [terrain]
##   godot --headless --path . -s res://tools/battle_sim.gd -- all [trials] [seed]
## "all" plays every pair and checks the §12.4 targets: an even fight costs the loser
## 35–50% of its HP and routs it in 2–3 battles, and no build beats an evenly rated
## one more than 60% of the time.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var data := GameData.load_dir()
	var builds: Dictionary = JSON.parse_string(FileAccess.get_file_as_string("res://data/sim_builds.json"))
	builds.erase("_about")
	if args.is_empty():
		print("Usage: -- <build a> <build b> [trials] [seed] [terrain]   or   -- all [trials] [seed]")
		print("Builds: " + ", ".join(builds.keys()))
		quit()
		return
	if args[0] == "all":
		_all(data, builds, int(args[1]) if args.size() > 1 else 200, int(args[2]) if args.size() > 2 else 1)
	else:
		var r := BattleSim.run(data, builds[args[0]], builds[args[1]], int(args[2]) if args.size() > 2 else 500,
				int(args[3]) if args.size() > 3 else 1, args[4] if args.size() > 4 else "plains")
		print(BattleSim.report(args[0], args[1], r))
	quit()


func _all(data: GameData, builds: Dictionary, trials: int, seed: int) -> void:
	var keys := builds.keys()
	var lost := 0.0
	var rout := 0.0
	var front := 0.0
	var back := 0.0
	var pairs := 0
	var worst := 0.0
	var worst_pair := ""
	var calls := 0
	var right := 0
	var points := []
	for i in keys.size():
		for j in range(i + 1, keys.size()):
			var r := BattleSim.run(data, builds[keys[i]], builds[keys[j]], trials, seed + i * 100 + j)
			print(BattleSim.report(keys[i], keys[j], r))
			lost += r["loser_hp_lost"]
			rout += r["battles_to_rout"]
			front += r["front_survival"]
			back += r["back_survival"]
			pairs += 1
			var ratio: float = r["threat_ratio"]
			var top: float = maxf(r["win_a"], r["win_b"])
			points.append([ratio, r["win_b"]])
			if absf(r["win_a"] - r["win_b"]) > 0.2:
				calls += 1
				right += int((ratio > 1.0) == (r["win_b"] > r["win_a"]))
			if ratio >= 0.8 and ratio < 1.25 and top > worst:
				worst = top
				worst_pair = "%s vs %s" % [keys[i], keys[j]]
	print("")
	print("Average first-battle HP lost by the loser: %.0f%% (target 35-50%%)" % (lost / pairs * 100))
	print("Average battles to rout: %.1f (target 2-3)" % (rout / pairs))
	print("Units alive after a first battle: front row %.0f%%, back row %.0f%%" % [front / pairs * 100, back / pairs * 100])
	points.sort_custom(func(p, q): return p[0] < q[0])
	print("Threat ratio -> second build's win share: " + ", ".join(points.map(func(p): return "%.2f:%.0f%%" % [p[0], p[1] * 100])))
	print("The higher-rated build won %d of %d clear-cut pairs" % [right, calls])
	print("Highest win rate between evenly rated builds: %.0f%% (%s; target at most 60%%)" % [worst * 100, worst_pair])
