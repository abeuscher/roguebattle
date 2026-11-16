class_name EndScreen
extends Control
## The victory/defeat screen (SPEC §4, §6.8). Since playtest round 21 a screen to pause
## on: the run in numbers counting up and, on a victory, the reward paid (a day's income
## and a sum per place held) over the user's video filling the screen (played once, then
## its loop clip over and over); a defeat shows the title and why instead. A modal over the frozen map. The
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
	if won and ResourceLoader.exists(str(look["victory_video"])):
		_victory(summary, look)
	else:
		_plain(summary, won)
	if won:
		_fireworks(int(look["fireworks"]))


## A victory: the user's video fills the screen (it says "Victory" itself), and the numbers
## sit in a dark see-through box along the bottom, below the castle of its closing loop.
func _victory(summary: Dictionary, look: Dictionary) -> void:
	var back := ColorRect.new()
	back.color = Color.BLACK
	back.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	add_child(back)
	var fit := AspectRatioContainer.new()
	fit.ratio = 16.0 / 9.0
	fit.stretch_mode = AspectRatioContainer.STRETCH_COVER  # fills any window shape, cropping the edges
	fit.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	fit.clip_contents = true
	add_child(fit)
	fit.add_child(_video(str(look["victory_video"]), str(look["victory_loop"])))
	var panel := PanelContainer.new()
	panel.add_theme_stylebox_override("panel", UiStyle.box(Color(0, 0, 0, float(look["stats_shade"])), 24))
	panel.anchor_left = 0.5
	panel.anchor_right = 0.5
	panel.anchor_top = float(look["stats_top"])
	panel.anchor_bottom = float(look["stats_top"])
	panel.grow_horizontal = GROW_DIRECTION_BOTH
	add_child(panel)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 48)
	panel.add_child(row)
	var numbers := VBoxContainer.new()
	numbers.add_theme_constant_override("separation", 8)
	row.add_child(numbers)
	numbers.add_child(UiStyle.section("The map in numbers"))
	var grid := _grid(4)
	numbers.add_child(grid)
	_stats(grid, summary)
	var right := VBoxContainer.new()
	right.add_theme_constant_override("separation", 8)
	row.add_child(right)
	if not summary["reward"].is_empty():
		right.add_child(UiStyle.section("Victory reward"))
		var pay := _grid(2)
		right.add_child(pay)
		_pay(pay, summary)
	var go := _to_title_button()
	go.size_flags_vertical = SIZE_SHRINK_END | SIZE_EXPAND
	right.add_child(go)


## A defeat (or a victory without its video): the title and why, over the frozen map.
func _plain(summary: Dictionary, won: bool) -> void:
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
	var facts := VBoxContainer.new()
	facts.add_theme_constant_override("separation", 10)
	facts.custom_minimum_size.x = 520
	col.add_child(facts)
	facts.add_child(UiStyle.section("The map in numbers"))
	var grid := _grid(2)
	facts.add_child(grid)
	_stats(grid, summary)
	if won and not summary["reward"].is_empty():
		facts.add_child(UiStyle.section("Victory reward"))
		var pay := _grid(2)
		facts.add_child(pay)
		_pay(pay, summary)
	else:
		_row(grid, "Gold", int(summary["gold"]), " g")
	var go := _to_title_button()
	go.size_flags_horizontal = SIZE_SHRINK_CENTER
	col.add_child(go)


func _grid(columns: int) -> GridContainer:
	var g := GridContainer.new()
	g.columns = columns
	g.add_theme_constant_override("h_separation", 40)
	g.add_theme_constant_override("v_separation", 8)
	return g


func _stats(grid: GridContainer, summary: Dictionary) -> void:
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


func _pay(pay: GridContainer, summary: Dictionary) -> void:
	var reward: Dictionary = summary["reward"]
	_row(pay, "A day's income", int(reward["income"]), " g", "+")
	_row(pay, "%d places held × %d g" % [int(reward["buildings"]), int(reward["per_building"])],
			int(reward["buildings"]) * int(reward["per_building"]), " g", "+")
	_row(pay, "Gold at the end", int(summary["gold"]), " g", "", UiStyle.ACCENT, 26)


func _to_title_button() -> Button:
	var go := UiStyle.button("Return to title", 300, true)
	go.pressed.connect(func(): to_title.emit())
	return go


## The user's video: the full piece once, then its loop clip over and over.
func _video(full: String, loop_clip: String) -> Control:
	var player := VideoStreamPlayer.new()
	player.stream = load(full)
	player.expand = true
	player.finished.connect(func():
		if ResourceLoader.exists(loop_clip):
			player.stream = load(loop_clip)
			player.loop = true
			player.play())
	player.ready.connect(player.play)
	return player


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
