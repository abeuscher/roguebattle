class_name EncounterPopup
extends Control
## Shown when one of your squads runs into a hostile one (SPEC §11.1): the map is
## paused and the camera has flown to the fight; Begin Battle opens the battle view, Heal
## uses supplies first, and View Squad and Map puts the dialog aside, paused, with the
## squad's menu open, so you can shop, heal or move other squads first; it comes back when
## time runs again (playtest round 16, replacing Edit Squad).
## A modal, with a light shade and the panel in the lower part of the screen so the
## two squads stay in view at its center.

signal go
signal heal  # the Heal window, before the fight
signal view  # the squad's menu and the map, paused; the dialog comes back on resuming

var _odds: Label
var _battle: Battle
var _panel: PanelContainer
var _heal: Button
var _heal_face: Control
var _state: GameState


## `game_state`: for whether Heal has anything to do (its supplies; no healing for gold before a fight).
func setup(b: Battle, game_state: GameState) -> void:
	_state = game_state
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.2)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	center.anchor_top = 0.62
	center.anchor_bottom = 0.9
	add_child(center)
	var panel := PanelContainer.new()
	_panel = panel
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 460
	panel.add_child(col)
	var ours := b.sides[0]
	var who := ours.leader.name.get_slice(" ", 0) if ours.leader else ours.name
	var title := "%s's party has encountered the enemy" % who
	col.add_child(UiStyle.title_row(UiStyle.label(title, 22), Callable()))
	_battle = b
	_odds = UiStyle.label("", 17, Color(0.8, 0.82, 0.86))
	col.add_child(_odds)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var button := UiStyle.button("Begin Battle", 240, true)
	button.pressed.connect(func(): go.emit())
	row.add_child(button)
	var items := UiStyle.button("", 160)
	_heal = items
	# The red cross beside the word, the two centred together (a Button's own icon sits at its left edge).
	var face := HBoxContainer.new()
	face.add_theme_constant_override("separation", 8)
	face.alignment = BoxContainer.ALIGNMENT_CENTER
	face.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	face.mouse_filter = MOUSE_FILTER_IGNORE
	var cross := TextureRect.new()
	cross.texture = UiStyle.svg("medical-cross", 22)
	cross.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	face.add_child(cross)
	face.add_child(UiStyle.label("Heal", 18, Color.WHITE))
	_heal_face = face
	items.add_child(face)
	items.focus_mode = FOCUS_NONE
	items.pressed.connect(func(): heal.emit())
	row.add_child(items)
	var squad := UiStyle.button("View Squad and Map", 220)
	squad.tooltip_text = "Look over the squad and the map, paused: shop, heal or give orders first.\nThis comes back when you resume."
	squad.focus_mode = FOCUS_NONE
	squad.pressed.connect(func(): view.emit())
	row.add_child(squad)
	refresh()
	button.grab_focus.call_deferred()


## Where a player tip points (Battlemap._offer_tip): "panel", the dialog.
func anchor(name: String) -> Rect2:
	return _panel.get_global_rect() if name == "panel" else Rect2()


## How the enemy looks, and whether Heal has anything to do, again after Heal changed the squad.
## Heal is grey with no supplies, or with everyone at full HP (round 19).
func refresh() -> void:
	var blocked := _state.heal_blocked(_battle.sides[0], false)
	_heal.disabled = blocked != ""
	_heal_face.modulate.a = 0.45 if _heal.disabled else 1.0
	_heal.tooltip_text = blocked if _heal.disabled else "Heal or revive units of this squad before the fight."
	var lead := _battle.sides[1].name
	_odds.text = "%s  ·  they look %s" % [lead, _battle.odds.to_lower()]
