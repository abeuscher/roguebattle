class_name PlayerTips
extends RefCounted
## Player tips (ROADMAP M4 session 33): which tip, if any, is due at a moment of the
## game. A tip shows once, only while the player's "show_tips" option is on, and only
## in the game modes it names; tips seen are kept in the options ("tips_seen"), not the
## save. Text, moments and anchors live in data/tips.json.


## The id of the first unseen tip for `moment` in game mode `mode`, or "" if none.
static func due(data: GameData, options: Dictionary, moment: String, mode: String) -> String:
	if not bool(options.get("show_tips", true)):
		return ""
	var seen: Array = options.get("tips_seen", [])
	for id in data.tips.get("tips", {}):
		var t: Dictionary = data.tips["tips"][id]
		if t["moment"] == moment and id not in seen and (not t.has("modes") or mode in t["modes"]):
			return id
	return ""


## Remembers that a tip was shown, so it never shows again. `save`: write the options file.
static func mark_seen(options: Dictionary, id: String, save := true) -> void:
	var seen: Array = options.get("tips_seen", []).duplicate()
	if id not in seen:
		seen.append(id)
	options["tips_seen"] = seen
	if save:
		PlayerOptions.save_values(options)
