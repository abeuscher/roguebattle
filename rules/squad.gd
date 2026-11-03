class_name Squad
extends RefCounted
## A squad on the map. For M1 it only moves; units, rows and the travel-type
## vote arrive in M2 (SPEC §8).

var id: int
var name: String
var hex: int
var travel_type := ""  # terrain key it moves through as native ("" = none)
var sky := false
var speed_tier := 2
var path := PackedInt32Array()  # hexes still to enter, in order
var rally := PackedInt32Array()  # rally points still ahead, each also on the path
var progress := 0.0  # ticks spent so far toward entering path[0]


func _init(squad_id: int, squad_name: String, at_hex: int) -> void:
	id = squad_id
	name = squad_name
	hex = at_hex


func is_moving() -> bool:
	return not path.is_empty()


func travel_name() -> String:
	return "Sky" if sky else (travel_type.capitalize() if travel_type != "" else "None")
