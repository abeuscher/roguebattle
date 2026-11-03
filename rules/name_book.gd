class_name NameBook
extends RefCounted
## Unit names for one run (SPEC §9.3): first and last names from unit-names.csv
## combine independently, and no full name repeats.

var first: PackedStringArray
var last: PackedStringArray
var used := {}  # full name -> true


func _init(data: GameData) -> void:
	first = data.first_names
	last = data.last_names


func take(rng: RandomNumberGenerator) -> String:
	for attempt in 50:
		var n := "%s %s" % [first[rng.randi() % first.size()], last[rng.randi() % last.size()]]
		if not used.has(n):
			used[n] = true
			return n
	for f in first:  # nearly full: take the first free pairing
		for l in last:
			var n := "%s %s" % [f, l]
			if not used.has(n):
				used[n] = true
				return n
	var n := "Unit %d" % used.size()
	used[n] = true
	return n
