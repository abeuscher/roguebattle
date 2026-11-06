class_name NeutralSquads
extends RefCounted
## Rolls a lair's squad (SPEC §6.7, §16): one race line native to the lair's home
## terrain, with danger (0..1) picking how far along its stages the squad is and
## adding levels; 1-9 units of that class (GameState.place_neutrals adds as many
## as the squad's slots actually fit, same as any squad).


## The units for one neutral squad, or empty if no race line calls `home` native.
static func roll(data: GameData, home: String, danger: float, rng: RandomNumberGenerator, names: NameBook) -> Array[Unit]:
	var stages := _pick_line(data, home, rng)
	var out: Array[Unit] = []
	if stages.is_empty():
		return out
	var stage_index := clampi(floori(danger * stages.size()), 0, stages.size() - 1)
	var level := 1 + roundi(danger * float(data.neutrals["level_span"]))
	for i in rng.randi_range(1, 9):
		var u := Unit.roll(data, _pick_class(stages[0], rng), rng, names)
		for s in range(1, stage_index + 1):
			Progression.promote(data, u, _pick_class(stages[s], rng))
		for l in level - 1:
			Progression.level_up(data, u, rng)
		out.append(u)
	return out


static func _pick_class(stage: Array, rng: RandomNumberGenerator) -> String:
	return stage[rng.randi() % stage.size()]


## A random race line (the sheet's R, N, L, T lines; never a Serf line, §16) whose
## first stage is native to `home`, or empty if none is.
static func _pick_line(data: GameData, home: String, rng: RandomNumberGenerator) -> Array:
	var candidates: Array = []
	for line_id in data.lines:
		if line_id.is_valid_int():
			continue
		var stages: Array = data.lines[line_id]
		if data.units[stages[0][0]]["terrain"] == home:
			candidates.append(stages)
	return candidates[rng.randi() % candidates.size()] if not candidates.is_empty() else []
