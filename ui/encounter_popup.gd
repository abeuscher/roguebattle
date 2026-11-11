class_name EncounterPopup
extends Control
## Shown when one of your squads runs into a hostile one (SPEC §11.1): the map is
## paused and the camera has flown to the fight; Begin Battle opens the battle view, and
## Edit Squad opens the squad in Edit Units first (playtest round 9).
## A modal, with a light shade and the panel in the lower part of the screen so the
## two squads stay in view at its center.

signal go
signal use_item
signal edit

var _odds: Label
var _battle: Battle


## `supplies`: the army's herbs and revivals, for Use item (user's playtest notes, 2026-11-10).
func setup(b: Battle, state_supplies: Dictionary) -> void:
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
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 22))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 460
	panel.add_child(col)
	var ours := b.sides[0]
	var who := ours.leader.name.get_slice(" ", 0) if ours.leader else ours.name
	col.add_child(UiStyle.label("%s's party has encountered the enemy" % who, 24))
	_battle = b
	_odds = UiStyle.label("", 17, Color(0.8, 0.82, 0.86))
	col.add_child(_odds)
	refresh()
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	col.add_child(row)
	var button := UiStyle.button("Begin Battle", 240, true)
	button.pressed.connect(func(): go.emit())
	row.add_child(button)
	var herbs := 0
	for id in state_supplies:
		herbs += int(state_supplies[id])
	var items := UiStyle.button("Use item(s)", 160)
	items.disabled = herbs == 0
	items.tooltip_text = "Heal or revive units of this squad before the fight." if herbs > 0 else "No supplies: buy herbs at a shop."
	items.focus_mode = FOCUS_NONE
	items.pressed.connect(func(): use_item.emit())
	row.add_child(items)
	var squad := UiStyle.button("Edit Squad", 160)
	squad.tooltip_text = "Change the formation before the fight."
	squad.focus_mode = FOCUS_NONE
	squad.pressed.connect(func(): edit.emit())
	row.add_child(squad)
	button.grab_focus.call_deferred()


## How the enemy looks, again after Use item changed the squad.
func refresh() -> void:
	_odds.text = "%s  ·  they look %s" % [_battle.sides[1].name, _battle.odds.to_lower()]
