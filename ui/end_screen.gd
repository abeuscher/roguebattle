class_name EndScreen
extends Control
## The victory/defeat screen (SPEC §4, §6.8): why the map ended, and a short
## summary of gold, reputation and other stats. A modal: 50% dark overlay.
## The only way out is back to the title; there's no further map to continue to yet.

signal to_title

const VICTORY := Color("#7ee08a")
const DEFEAT := Color("#c8402f")


func setup(state: GameState) -> void:
	var summary := state.end_summary()
	var won: bool = summary["outcome"] == "victory"
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.6)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(UiStyle.PANEL, 26))
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 12)
	col.custom_minimum_size.x = 440
	panel.add_child(col)
	col.add_child(UiStyle.title_row(UiStyle.label("Victory!" if won else "Defeat", 32, VICTORY if won else DEFEAT), Callable()))
	col.add_child(UiStyle.label(str(summary["reason"]), 18))
	var lines := [
		"Day %d" % int(summary["day"]),
		"Gold: %d" % int(summary["gold"]),
		"Reputation: %d" % int(summary["reputation"]),
		"Enemy squads defeated: %d" % int(summary["enemy_squads_defeated"]),
		"Towns held: %d of %d" % [int(summary["towns_held"]), int(summary["towns_total"])],
		"Tech points: %d" % int(summary["tech_points"]),
	]
	for t in lines:
		col.add_child(UiStyle.label(t, 16, Color(0.85, 0.87, 0.9)))
	var go := UiStyle.button("Return to title", 280, true)
	go.pressed.connect(func(): to_title.emit())
	col.add_child(go)
