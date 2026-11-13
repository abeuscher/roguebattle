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
	UiStyle.close_on_click(shade, center, func(): closed.emit())
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	col.custom_minimum_size.x = 560
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("%s  ·  %s" % [b["name"], info["name"]] if b.has("name") else state.site_name(b), 26), func(): closed.emit()))
	var lines: Array
	if b["type"] == "hidden_site":  # nobody owns a site: just what it is and what it does
		lines = [_site_about(state, b)]
	else:
		col.add_child(UiStyle.label(OWNERS[b["owner"]], 17, UiStyle.ACCENT))
		if b["owner"] != "player" and not state.seen(b["hex"]):  # out of sight: only its name, owner and shop (playtest notes, 2026-11-11)
			lines = ["Shop: yes" if b.get("shop", false) else "Shop: no", "Out of your squads' sight."]
		else:
			lines = _details(state, b, info)
	if b.has("god"):  # the temple's god (the Gods of Perinea, round 11)
		_god(col, state.data.gods["gods"][b["god"]])
	for t in lines:
		var l := UiStyle.label(t, 16, Color(0.85, 0.87, 0.9))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(l)


## A god's name and domain, then how they look and how they show themselves.
func _god(col: VBoxContainer, g: Dictionary) -> void:
	col.add_child(UiStyle.section("Its god"))
	col.add_child(UiStyle.label("%s, god of %s" % [g["name"], g["domain"]], 18, Color("#f4ead2")))
	for t in [g["appearance"], g["manifestation"]]:
		var l := UiStyle.label(t, 15, Color(0.72, 0.74, 0.8))
		l.autowrap_mode = TextServer.AUTOWRAP_WORD
		col.add_child(l)
	var gap := Control.new()
	gap.custom_minimum_size.y = 4
	col.add_child(gap)
	col.add_child(UiStyle.section("The temple"))


## Everything about a building in sight or held: defense and rest, liberating, shop,
## temple services, local news.
func _details(state: GameState, b: Dictionary, info: Dictionary) -> Array:
	var data := state.data
	var lines := []
	if info.has("own_base"):
		if float(info["own_base"]["rest"]) > 0.0:
			lines.append("Squads of its side defend +%d%% and heal %d%% a day here." % [_pct(info["own_base"]["defense"]), _pct(info["own_base"]["rest"])])
		else:
			lines.append("Squads of its side defend +%d%% here, but don't heal." % _pct(info["own_base"]["defense"]))
		if b["type"] == "enemy_base":
			lines.append("Fallen enemy units come back here one at a time, one every %s." % GameState.duration_text(int(state.data.enemy["base_revive_ticks"])))
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
		var verb := "Liberate" if info.get("liberation", true) else "Take"  # a temple is just taken (session 059)
		lines.append("%s it by keeping a squad with a ground unit here for %d minutes (%d with a Sapper)." % [verb, int(c["ticks"]),
				int(float(c["ticks"]) / float(c["sapper_speed"]))])
		var p := state.capture_progress(b)
		if p > 0.0:
			lines.append("%s: %d%% done." % ["Liberating" if verb == "Liberate" else "Taking", _pct(p)])
	if b["type"] == "nomads":
		lines.append("A town on the move: it travels every half day.")
	if b.get("shop", false):
		lines.append("Shop: yes. %s" % ("Liberate it to trade here." if b["owner"] == "enemy" else
				"Stand a squad here and choose Shop in its squad menu."))
	else:
		lines.append("Shop: no")
	if b["type"] == "temple":
		lines.append("Healing and revival: stand a squad here and choose Temple services in its squad menu.")
		lines.append("Once yours: squads resting here train each day (more XP for lower levels), and its portal steps a squad at once to any other temple you hold.")
	if b.get("hint", false):
		var h := state.hint(b)
		lines.append(("Local news: " + h) if b["owner"] == "player" and h != "" else
				("Liberate it to hear the local news." if b["owner"] != "player" else "No news of anything hidden nearby."))
	return lines


## A hidden site's line: what claiming it gives, or for a lair whether it's still guarded.
func _site_about(state: GameState, b: Dictionary) -> String:
	var k: Dictionary = state.data.buildings["hidden_site"]["kind_info"][b["kind"]]
	if b["kind"] != "lair":
		return k["about"]
	var text: String = k["about"] % [_pct(k["defense"]), _pct(k["rest"])]
	return text + (" The guard is gone." if state.guard_of(b) == null else " Its guard is still here.")


static func _pct(v: Variant) -> int:
	return roundi(float(v) * 100)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_ESCAPE:
		closed.emit()
		get_viewport().set_input_as_handled()
