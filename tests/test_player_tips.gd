extends TestCase
## Player tips (ROADMAP M4 session 33): a tip shows once, never again after it's
## dismissed, not at all with tips off, and only in the game modes it names.

var d := GameData.load_dir()


func _options() -> Dictionary:
	return PlayerOptions.load_values(d, "user://no_such_options.json")  # the defaults


func test_the_first_tip_is_due_on_the_opening_edit_units() -> void:
	var o := _options()
	check(bool(o["show_tips"]), "tips are on by default")
	check_eq(PlayerTips.due(d, o, "edit_units_open", "single_map"), "build_squad", "the squad-building tip")
	check(str(d.tips["tips"]["build_squad"]["text"]).begins_with("To begin creating a new squad"), "with the agreed text")
	check_eq(d.tips["tips"]["build_squad"]["anchor"], "recruit_pool", "pointing at the recruit pool")


func test_a_tip_shows_once() -> void:
	var o := _options()
	PlayerTips.mark_seen(o, "build_squad", false)
	check_eq(PlayerTips.due(d, o, "edit_units_open", "single_map"), "", "dismissed: never again")
	PlayerTips.mark_seen(o, "build_squad", false)
	check_eq((o["tips_seen"] as Array).count("build_squad"), 1, "remembered once")


func test_no_tips_when_turned_off() -> void:
	var o := _options()
	o["show_tips"] = false
	check_eq(PlayerTips.due(d, o, "edit_units_open", "single_map"), "", "tips off: none")


func test_only_in_its_modes_and_at_its_moment() -> void:
	var o := _options()
	check_eq(PlayerTips.due(d, o, "edit_units_open", "campaign"), "", "a single map tip doesn't show in the campaign start")
	check_eq(PlayerTips.due(d, o, "somewhere_else", "single_map"), "", "nor at another moment")


func test_every_tip_is_complete() -> void:
	for id in d.tips["tips"]:
		var t: Dictionary = d.tips["tips"][id]
		check(t.has("moment") and t.has("anchor") and str(t.get("text", "")) != "", "%s has a moment, an anchor and text" % id)


## Quick start tips (playtest round 13): to the Garrison's town, then the first battle.
func test_quick_start_tips_lead_to_the_garrison_and_the_first_battle() -> void:
	var o := _options()
	check_eq(PlayerTips.due(d, o, "map_open", "quick_start"), "march", "Quick start opens on the march to the Garrison")
	check_eq(d.tips["tips"]["march"]["anchor"], "garrison_town", "pointing at its town")
	check(str(d.tips["tips"]["march"]["text"]).contains("{town}"), "named in the text")
	check_eq(PlayerTips.due(d, o, "map_open", "single_map"), "deploy", "a single map still gets the deploy tip there")
	PlayerTips.mark_seen(o, "march", false)
	check_eq(PlayerTips.due(d, o, "map_open", "quick_start"), "deploy", "and Quick start gets it after the march")
	for mode in ["single_map", "campaign", "quick_start"]:
		check_eq(PlayerTips.due(d, o, "encounter_open", mode), "first_battle", "the first battle tip in %s" % mode)
	check_eq(PlayerTips.due(d, o, "edit_units_open", "quick_start"), "build_squad", "building squads in Quick start too")
