class_name PlayerOptions
extends RefCounted
## The player's options (the Options screen): the defaults from data/options.json,
## overridden by whatever the player saved. Not game rules; nothing here changes how
## a map plays out, only how it's shown.

const PATH := "user://options.json"


## Option id -> value: every option in the data, saved values where there are any.
static func load_values(data: GameData, path := PATH) -> Dictionary:
	var out := {}
	for id in data.options["options"]:
		out[id] = data.options["options"][id]["default"]
	if FileAccess.file_exists(path):
		var saved = JSON.parse_string(FileAccess.get_file_as_string(path))
		if saved is Dictionary:
			for id in saved:
				if out.has(id):
					out[id] = saved[id]
	return out


static func save_values(values: Dictionary, path := PATH) -> void:
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f:
		f.store_string(JSON.stringify(values))
