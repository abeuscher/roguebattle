class_name GameLog
extends RefCounted
## The one log for everything (SPEC §19.1). Plain text for the player, with
## hidden values kept apart so the debug toggle can show them.

const CATEGORIES := ["battle", "map", "economy", "progression", "system"]
const TICKS_PER_DAY := 1440  # 1 tick = 1 in-game minute (SPEC §7)

var entries: Array[Dictionary] = []
var _file: FileAccess


## Pass a path to also write every entry to a file (one per session).
func _init(file_path: String = "") -> void:
	if file_path != "":
		DirAccess.make_dir_recursive_absolute(file_path.get_base_dir())
		_file = FileAccess.open(file_path, FileAccess.WRITE)


func add(tick: int, category: String, text: String, squad_id: int = -1, hidden: Dictionary = {}) -> void:
	assert(category in CATEGORIES, "Unknown log category: " + category)
	var entry := {"tick": tick, "category": category, "text": text, "squad": squad_id, "hidden": hidden}
	entries.append(entry)
	if _file:
		_file.store_line(format(entry, true))
		_file.flush()


func filtered(category: String = "", squad_id: int = -1) -> Array[Dictionary]:
	return entries.filter(func(e): return (category == "" or e["category"] == category) \
			and (squad_id == -1 or e["squad"] == squad_id))


static func format(entry: Dictionary, show_hidden: bool = false) -> String:
	var t: int = entry["tick"]
	var line := "D%d %02d:%02d [%s] %s" % [t / TICKS_PER_DAY + 1, (t % TICKS_PER_DAY) / 60, t % 60, entry["category"], entry["text"]]
	if show_hidden and not entry["hidden"].is_empty():
		line += " " + JSON.stringify(entry["hidden"])
	return line
