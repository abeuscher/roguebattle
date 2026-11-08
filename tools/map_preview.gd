extends SceneTree
## Writes a PNG of a generated map.
## godot --headless -s res://tools/map_preview.gd -- <seed> [size] [preset] [out.png]
## [size] is "small"/"medium"/"large" (§6.1) or a custom "WxH", e.g. "200x120".


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 1
	var data := GameData.load_dir()
	var overrides := {}
	if args.size() > 1:
		var token: String = args[1]
		if data.mapgen["sizes"].has(token):
			var dims: Array = data.mapgen["sizes"][token]
			overrides["width"] = int(dims[0])
			overrides["height"] = int(dims[1])
		elif "x" in token:
			var parts := token.split("x")
			overrides["width"] = int(parts[0])
			overrides["height"] = int(parts[1])
	if args.size() > 2:
		overrides["preset"] = args[2]
	var out: String = args[3] if args.size() > 3 else "user://map_%d.png" % seed
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed, overrides)
	print("Generated %dx%d in %d ms" % [map.width, map.height, Time.get_ticks_msec() - started])
	MinimapImage.build(map, data).save_png(out)
	print("Wrote " + ProjectSettings.globalize_path(out))
	quit()
