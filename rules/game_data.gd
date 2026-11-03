class_name GameData
extends RefCounted
## Loads the JSON content in data/. The game reads only these files.

var units: Dictionary = {}          # class name -> class dict
var lines: Dictionary = {}          # line id -> Array of stages, each an Array of class names
var role_templates: Dictionary = {}
var rules: Dictionary = {}
var battle: Dictionary = {}         # battle formulas and matchups
var mechanics: Dictionary = {}      # the sheet's Mechanics tab: name -> rule, numbers, used_by
var enemy: Dictionary = {}          # enemy roles and squad builds
var tag_cache: Dictionary = {}      # "class|tag" -> bool, filled by Unit.has_tag
var threat_ref: Dictionary = {}     # average stage-2 base stats, filled by Threat.reference
var terrains: Array = []            # index = terrain id
var terrain_ids: Dictionary = {}    # key -> terrain id
var mapgen: Dictionary = {}
var buildings: Dictionary = {}      # building type -> placement rules
var config_fields: Array = []       # configurator settings, in share-code order
var first_names: PackedStringArray = []
var last_names: PackedStringArray = []


static func load_dir(dir: String = "res://data") -> GameData:
	var d := GameData.new()
	for u in _read_json(dir.path_join("units.json")):
		d.units[u["class"]] = u
	d.lines = _read_json(dir.path_join("lines.json"))
	d.role_templates = _read_json(dir.path_join("role_templates.json"))
	d.rules = _read_json(dir.path_join("rules.json"))
	d.battle = _read_json(dir.path_join("battle.json"))
	d.mechanics = _read_json(dir.path_join("mechanics.json"))
	d.enemy = _read_json(dir.path_join("enemy.json"))
	d.terrains = _read_json(dir.path_join("terrain.json"))
	for i in d.terrains.size():
		d.terrain_ids[d.terrains[i]["key"]] = i
	d.mapgen = _read_json(dir.path_join("mapgen.json"))
	d.buildings = _read_json(dir.path_join("buildings.json"))
	d.config_fields = _read_json(dir.path_join("configurator.json"))
	d._load_names(dir.path_join("unit-names.csv"))
	return d


func slots_for(unit_class: Dictionary) -> float:
	return float(rules["size_slots"][unit_class["size"]])


## The classes one stage after `class_name` on each of its lines.
func next_classes(unit_class_name: String) -> PackedStringArray:
	var out := PackedStringArray()
	for line_id in units[unit_class_name]["lines"]:
		var stages: Array = lines[line_id]
		for i in stages.size() - 1:
			if unit_class_name in stages[i]:
				for c in stages[i + 1]:
					if c not in out:
						out.append(c)
	return out


func _load_names(path: String) -> void:
	var f := FileAccess.open(path, FileAccess.READ)
	f.get_csv_line()  # header
	while not f.eof_reached():
		var row := f.get_csv_line()
		if row.size() < 2:
			continue
		if row[0] != "" and row[0] not in first_names:
			first_names.append(row[0])
		if row[1] != "" and row[1] not in last_names:
			last_names.append(row[1])


static func _read_json(path: String) -> Variant:
	var parsed = JSON.parse_string(FileAccess.get_file_as_string(path))
	assert(parsed != null, "Bad JSON: " + path)
	return parsed
