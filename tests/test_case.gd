class_name TestCase
extends RefCounted
## Base for test files. Methods named test_* run in file order.

var failures: PackedStringArray = []


func check(ok: bool, message: String) -> void:
	if not ok:
		failures.append(message)


func check_eq(actual: Variant, expected: Variant, message: String) -> void:
	if actual != expected:
		failures.append("%s (got %s, expected %s)" % [message, actual, expected])
