extends SceneTree
## Headless whole-map sim (BoardSim; playtest round 16): who holds the map over time, how
## often the sides fight, and how far your squads are when the enemy moves on your holdings.
##   godot --headless --path . -s res://tools/board_sim.gd -- [days] [seeds] [WxH ...] [--no-defence] [--no-front] [--round18]
## --round18 plays it without round 19's forward squads, growing caps and enemy comebacks.
## Defaults: 4 days, 3 seeds, 100x45 400x225 600x400; your squads answer threats unless --no-defence.


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var data := GameData.load_dir()
	var days := float(args[0]) if args.size() > 0 else 4.0
	var seeds := int(args[1]) if args.size() > 1 else 3
	var respond := "--no-defence" not in args
	if "--no-front" in args:  # the enemy as before round 16's lever 2: no raiders, occupiers or spread starts, no front limit
		data.ai["force"] = {"raider_share": 0.0, "occupier_share": 0.0, "front_starts": 0.0}
		data.ai["front"]["reach"] = 100000
	if "--round18" in args:  # as before round 19: no forward squads, no cap growth, no comebacks
		data.ai["force"]["forward"] = 0
		data.rules["cap_growth"]["buildings_per_squad"] = 100000
		data.enemy["return"]["on"] = false
	args = PackedStringArray(Array(args).filter(func(a): return not a.begins_with("--")))
	var sizes: Array = Array(args.slice(2)) if args.size() > 2 else ["100x45", "400x225", "600x400"]
	for size in sizes:
		var wh: PackedStringArray = str(size).split("x")
		for seed in seeds:
			print(BoardSim.report(BoardSim.run(data, int(wh[0]), int(wh[1]), 100 + seed, days, {}, respond)))
	quit()
