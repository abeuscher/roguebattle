class_name TitleScreen
extends Control
## Title (SPEC §4): title art and "Press Space". The art is a placeholder: a
## generated map, darkened, behind the name.

signal next


func setup(data: GameData) -> void:
	UiStyle.backdrop(self)
	var art := TextureRect.new()
	art.texture = ImageTexture.create_from_image(MinimapImage.build(MapGen.generate(data, 20261102), data))
	art.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_COVERED
	art.modulate = Color(0.45, 0.45, 0.5)
	add_child(art)
	var col := VBoxContainer.new()
	col.set_anchors_and_offsets_preset(PRESET_FULL_RECT)
	col.alignment = BoxContainer.ALIGNMENT_CENTER
	add_child(col)
	var title := UiStyle.label("LANDWAR", 120, Color("#f4ead2"))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_constant_override("outline_size", 12)
	title.add_theme_color_override("font_outline_color", Color(0.05, 0.05, 0.08))
	col.add_child(title)
	var press := UiStyle.label("Press Space", 28, UiStyle.ACCENT)
	press.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	col.add_child(press)


func _unhandled_key_input(event: InputEvent) -> void:
	if event.is_pressed() and (event as InputEventKey).keycode == KEY_SPACE:
		get_viewport().set_input_as_handled()
		next.emit()
