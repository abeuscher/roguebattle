class_name EndScreen
extends Control
## The victory/defeat screen (SPEC §4, §6.8). Since playtest round 21 a screen to pause
## on: why the map ended, the run in numbers counting up, and on a victory the reward
## paid (a day's income and a sum per place held), the user's video (played once, then
## its loop clip over and over) and a few fireworks. A modal over the frozen map. The
## only way out is back to the title; there's no further map to continue to yet.

signal to_title

const VICTORY := Color("#7ee08a")
const DEFEAT := Color("#c8402f")
const SOFT := Color(0.8, 0.82, 0.86)
const COUNT_SECONDS := 1.4  # how long each number takes to count up

var _counted := 0  # numbers started counting, for their stagger


func setup(state: GameState) -> void:
	var summary := state.end_summary()
	var won: bool = summary["outcome"] == "victory"
	var look: Dictionary = state.data.rules["end_screen"]
	set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.75)
	shade.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(shade)
	var center := CenterContainer.new()
	center.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(center)
	var panel := PanelContainer.new()
	var frame := UiStyle.box(UiStyle.PANEL, 30)
	frame.set_border_width_all(2)
	frame.border_color = Color(VICTORY if won else DEFEAT, 0.6)
	panel.add_theme_stylebox_override("panel", frame)
	center.add_child(panel)
	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 14)
	panel.add_child(col)
	var title := UiStyle.label("Victory!" if won else "Defeat", 64, VICTORY if won else DEFEAT)
	title.add_theme_font_override("font", UiStyle.title_font())
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(title)
	var reason := UiStyle.label(str(summary["reason"]), 22, UiStyle.TITLE)
	reason.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(reason)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation", 36)
	col.add_child(body)
	if won and ResourceLoader.exists(str(look["victory_video"])):
		body.add_child(_video(str(look["victory_video"]), str(look["victory_loop"])))
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 10)
	facts.custom_minimum_size.x = 520
	body.add_child(facts)
	facts.add_child(UiStyle.section("The map in numbers"))
	var grid := GridContainer.new()
	grid.columns = 2
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", 8)
	facts.add_child(grid)
	_row(grid, "Days", int(summary["day"]))
	_row(grid, "Battles won", int(summary["battles_won"]))
	_row(grid, "Battles lost", int(summary["battles_lost"]))
	_row(grid, "Places liberated", int(summary["liberated"]))
	_row(grid, "Enemy squads defeated", int(summary["enemy_squads_defeated"]))
	_row(grid, "Towns and towers held", int(summary["towns_held"]), " of %d" % int(summary["towns_total"]))
	_row(grid, "Squads in the field", int(summary["squads_out"]))
	_row(grid, "Units in the army", int(summary["army_size"]))
	_row(grid, "Reputation", int(summary["reputation"]))
	_row(grid, "Tech points", int(summary["tech_points"]))
	var reward: Dictionary = summary["reward"]
	if won and not reward.is_empty():
		facts.add_child(UiStyle.section("Victory reward"))
		var pay := GridContainer.new()
		pay.columns = 2
		pay.add_theme_constant_override("h_separation", 40)
		pay.add_theme_constant_override("v_separation", 8)
		facts.add_child(pay)
		_row(pay, "A day's income", int(reward["income"]), " g", "+")
		_row(pay, "%d places held × %d g" % [int(reward["buildings"]), int(reward["per_building"])],
				int(reward["buildings"]) * int(reward["per_building"]), " g", "+")
		_row(pay, "Gold at the end", int(summary["gold"]), " g", "", UiStyle.ACCENT, 26)
	else:
		_row(grid, "Gold", int(summary["gold"]), " g")
	var go := UiStyle.button("Return to title", 300, true)
	go.size_flags_horizontal = SIZE_SHRINK_CENTER
	go.pressed.connect(func(): to_title.emit())
	col.add_child(go)
	if won:
		_fireworks(int(look["fireworks"]))


## The user's video: the full piece once, then its loop clip over and over.
func _video(full: String, loop_clip: String) -> Control:
	var box := PanelContainer.new()
	var edge := UiStyle.box(Color.BLACK, 0)
	edge.set_border_width_all(2)
	edge.border_color = Color(VICTORY, 0.5)
	box.add_theme_stylebox_override("panel", edge)
	var player := VideoStreamPlayer.new()
	player.stream = load(full)
	player.expand = true
	player.custom_minimum_size = Vector2(720, 540)
	box.add_child(player)
	player.finished.connect(func():
		if ResourceLoader.exists(loop_clip):
			player.stream = load(loop_clip)
			player.loop = true
			player.play())
	player.ready.connect(player.play)
	return box


## A label and a number that counts up to `value`, a beat after the one before it.
func _row(grid: GridContainer, what: String, value: int, unit := "", sign := "", ink := Color.WHITE, px := 20) -> void:
	grid.add_child(UiStyle.label(what, px - 2, SOFT))
	var n := UiStyle.label("%s0%s" % [sign, unit], px, ink)
	n.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	n.size_flags_horizontal = SIZE_EXPAND_FILL
	grid.add_child(n)
	var t := create_tween()
	t.tween_interval(0.25 + 0.12 * _counted)
	t.tween_method(func(k: float): n.text = "%s%d%s" % [sign, roundi(value * k), unit], 0.0, 1.0, COUNT_SECONDS) \
			.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	_counted += 1


## A few fireworks shows over the screen, a couple of seconds apart.
func _fireworks(shows: int) -> void:
	var r := RandomNumberGenerator.new()  # looks only: no game randomness involved
	for i in shows:
		get_tree().create_timer(0.4 + i * 2.2).timeout.connect(func():
			if not is_inside_tree():
				return
			var f := Fireworks.new()
			var screen := get_viewport_rect().size
			f.position = Vector2(screen.x * (0.12 + 0.76 * r.randf()), screen.y * r.randf_range(0.2, 0.45))
			f.scale = Vector2.ONE * 1.6
			add_child(f))
