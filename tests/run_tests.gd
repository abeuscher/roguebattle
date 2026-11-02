extends SceneTree
## Headless test runner: godot --headless -s res://tests/run_tests.gd [-- name_filter]
## Runs every test_* method in tests/test_*.gd. A script error inside a test fails it.


class ErrorCatcher extends Logger:
	var count := 0

	func _log_error(_function: String, file: String, line: int, code: String, rationale: String,
			_editor_notify: bool, error_type: int, _backtraces: Array[ScriptBacktrace]) -> void:
		if error_type != ERROR_TYPE_WARNING:
			count += 1
			printerr("  error: %s %s (%s:%d)" % [code, rationale, file, line])


func _initialize() -> void:
	var catcher := ErrorCatcher.new()
	OS.add_logger(catcher)
	var args := OS.get_cmdline_user_args()
	var filter: String = args[0] if args.size() > 0 else ""
	var passed := 0
	var failed := 0
	var files := Array(DirAccess.get_files_at("res://tests")).filter(
			func(f): return f.begins_with("test_") and f.ends_with(".gd") and f != "test_case.gd")
	files.sort()
	for file in files:
		var script: GDScript = load("res://tests/" + file)
		for m in script.get_script_method_list():
			var name: String = m["name"]
			if not name.begins_with("test_") or (filter != "" and filter not in file + "." + name):
				continue
			var t: TestCase = script.new()
			var errors_before := catcher.count
			var started := Time.get_ticks_msec()
			t.call(name)
			var ms := Time.get_ticks_msec() - started
			if t.failures.is_empty() and catcher.count == errors_before:
				passed += 1
				print("PASS %s.%s (%d ms)" % [file.get_basename(), name, ms])
			else:
				failed += 1
				print("FAIL %s.%s" % [file.get_basename(), name])
				for f in t.failures:
					print("  - " + f)
	print("\n%d passed, %d failed" % [passed, failed])
	OS.remove_logger(catcher)
	quit(1 if failed > 0 or passed == 0 else 0)
