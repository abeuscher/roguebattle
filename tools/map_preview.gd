extends SceneTree
## Writes a PNG of a generated map.
## godot --headless -s res://tools/map_preview.gd -- <seed> [size] [preset] [out.png]


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var seed := int(args[0]) if args.size() > 0 else 1
	var overrides := {}
	if args.size() > 1:
		overrides["size"] = args[1]
	if args.size() > 2:
		overrides["preset"] = args[2]
	var out: String = args[3] if args.size() > 3 else "user://map_%d.png" % seed
	var data := GameData.load_dir()
	var started := Time.get_ticks_msec()
	var map := MapGen.generate(data, seed, overrides)
	print("Generated %dx%d in %d ms" % [map.width, map.height, Time.get_ticks_msec() - started])
	MinimapImage.build(map, data).save_png(out)
	print("Wrote " + ProjectSettings.globalize_path(out))
	quit()
