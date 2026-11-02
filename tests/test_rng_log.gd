extends TestCase


func test_streams_are_seeded_and_independent() -> void:
	var a := RngStreams.new(42)
	var b := RngStreams.new(42)
	var seq_a := [a.get_stream("battle").randi(), a.get_stream("battle").randi()]
	b.get_stream("map").randi()  # drawing from another system must not shift battle
	var seq_b := [b.get_stream("battle").randi(), b.get_stream("battle").randi()]
	check_eq(seq_a, seq_b, "battle stream unaffected by map stream")
	check(RngStreams.new(43).get_stream("battle").randi() != RngStreams.new(42).get_stream("battle").randi(),
			"different seeds differ")


func test_log_filter_and_format() -> void:
	var log := GameLog.new()
	log.add(0, "system", "Seed 42")
	log.add(1440 + 12 * 60 + 5, "map", "Squad 1 moves", 1, {"path_cost": 7})
	log.add(1500, "map", "Squad 2 moves", 2)
	check_eq(log.filtered("map").size(), 2, "filter by category")
	check_eq(log.filtered("", 1).size(), 1, "filter by squad")
	check_eq(GameLog.format(log.entries[1]), "D2 12:05 [map] Squad 1 moves", "plain format")
	check(GameLog.format(log.entries[1], true).contains("path_cost"), "debug format shows hidden values")
