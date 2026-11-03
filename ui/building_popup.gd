class_name BuildingPopup
extends Control
## The building popup (SPEC §4): owner, type, what it gives squads of each alignment,
## shop yes or no, liberation progress, and a liberated town's hint about hidden sites.
## A modal: 50% dark overlay.

signal closed

const OWNERS := {"player": "Held by you", "enemy": "Held by the enemy", "neutral": "Belongs to no one"}


func setup(state: GameState, b: Dictionary) -> void:
	var data := state.data
	var info: Dictionary = data.buildings[b["type"]]
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.5)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 560
	panel.add_child(col)
	col.add_child(UiStyle.label(info["name"], 26))
	col.add_child(UiStyle.label(OWNERS[b["owner"]], 17, UiStyle.ACCENT))
	var lines := []
	if info.has("own_base"):
		lines.append("Squads of its side defend +%d%% and heal %d%% a day here." % [_pct(info["own_base"]["defense"]), _pct(info["own_base"]["rest"])])
		if b["type"] == "player_base":
			lines.append("Deploy squads, heal and revive in Edit Units.")
	elif info.has("defense"):
		var d: Array = info["defense"]
		var r: Array = info["rest"]
		if info.has("aligned"):
			lines.append("%s squads defend +%d%% and heal %d%% a day here; others +%d%% and %d%%." % [str(info["aligned"]).capitalize(),
					_pct(d[1]), _pct(r[1]), _pct(d[0]), _pct(r[0])])
		else:
			lines.append("Any squad defends +%d%% and heals %d%% a day here." % [_pct(d[0]), _pct(r[0])])
	if info.get("capturable", false) and b["owner"] != "player":
		var c: Dictionary = data.rules["capture"]
		lines.append("Liberate it by keeping a squad with a ground unit here for %d minutes (%d with a Sapper)." % [int(c["ticks"]),
				int(float(c["ticks"]) / float(c["sapper_speed"]))])
		var p := state.capture_progress(b)
		if p > 0.0:
			lines.append("Liberating: %d%% done." % _pct(p))
	if b["type"] == "nomads":
		lines.append("A town on the move: it travels every half day.")
	lines.append("Shop: %s" % ("yes (shops open with the economy)" if b.get("shop", false) else "no"))
	if b.get("hint", false):
		var h := state.hint(b)
		lines.append(("Local news: " + h) if b["owner"] == "player" and h != "" else
				("Liberate it to hear the local news." if b["owner"] != "player" else "No news of anything hidden nearby."))
	for t in lines:
		var l := UiStyle.label(t, 16, Color(0.85, 0.87, 0.9))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(l)
	var close := UiStyle.button("Close (Esc)", 180)
	close.pressed.connect(func(): closed.emit())
	col.add_child(close)


static func _pct(v: Variant) -> int:
	return roundi(float(v) * 100)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
