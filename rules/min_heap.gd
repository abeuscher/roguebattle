class_name MinHeap
extends RefCounted
## Binary min-heap of int items by float priority, for pathfinding.

var _pri := PackedFloat32Array()
var _item := PackedInt32Array()


func is_empty() -> bool:
	return _item.is_empty()


func push(item: int, priority: float) -> void:
	_pri.append(priority)
	_item.append(item)
	var i := _item.size() - 1
	while i > 0:
		var p := (i - 1) / 2
		if _pri[p] <= _pri[i]:
			break
		_swap(i, p)
		i = p


func pop() -> int:
	var top := _item[0]
	var last := _item.size() - 1
	_pri[0] = _pri[last]
	_item[0] = _item[last]
	_pri.resize(last)
	_item.resize(last)
	var i := 0
	while true:
		var l := i * 2 + 1
		var r := l + 1
		var m := i
		if l < last and _pri[l] < _pri[m]:
			m = l
		if r < last and _pri[r] < _pri[m]:
			m = r
		if m == i:
			break
		_swap(i, m)
		i = m
	return top


func _swap(a: int, b: int) -> void:
	var p := _pri[a]
	_pri[a] = _pri[b]
	_pri[b] = p
	var t := _item[a]
	_item[a] = _item[b]
	_item[b] = t
