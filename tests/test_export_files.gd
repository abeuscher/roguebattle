extends TestCase
## SVGs the game reads as text (to recolor and size them) must be kept as files on
## export: an imported texture alone isn't exported, and a build shows blank icons
## (user's Windows export, 2026-11-13).


func test_raw_svgs_are_kept_for_export() -> void:
	for dir in ["res://data/unit_icons/", "res://ui/icons/", "res://data/card_art/"]:
		for f in DirAccess.get_files_at(dir):
			if f.ends_with(".svg"):
				var imp := FileAccess.get_file_as_string(dir + f + ".import")
				check(imp.contains("importer=\"keep\""), "%s%s is kept as is on export" % [dir, f])
