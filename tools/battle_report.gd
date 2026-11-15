extends SceneTree
## Plays a battle report (the debug panel's Copy battle report, saved to a file) again and
## prints each event with its hidden numbers, to look into why a battle went as it did.
##   godot --headless --path . -s res://tools/battle_report.gd -- <report file>


func _initialize() -> void:
	var args := OS.get_cmdline_user_args()
	var b := DebugTools.from_report(GameData.load_dir(), FileAccess.get_file_as_string(args[0]) if not args.is_empty() else "")
	if b == null:
		print("Usage: -- <report file> (the text from the debug panel's Copy battle report)")
		quit()
		return
	DebugTools.replay_inputs(b, b.get_meta("inputs"))
	for e in b.events:
		print(b.log_line(e), "   ", e.get("hidden", ""))
	print("HP lost: ours %d%%, theirs %d%%" % [roundi(b.hp_lost_share(0) * 100), roundi(b.hp_lost_share(1) * 100)])
	quit()
