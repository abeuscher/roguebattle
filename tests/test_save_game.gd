extends TestCase
## Save game (ROADMAP M4 session 32): save then load reproduces the state exactly, the
## game plays on identically from there, and old or broken files are refused.

var d := GameData.load_dir()


## A real game on a small generated map, played for a while.
func _game(seed := 31) -> Array:
	var config := GameConfig.create(d, seed)
	config.values["width"] = 120
	config.values["height"] = 70
	config.fit_squad_cap()
	var map := MapGen.generate(d, config.seed, config.map_overrides())
	var st := GameState.new(d, map, GameLog.new(), config.game_settings())
	st.setup_army()
	st.place_enemies()
	st.place_neutrals()
	return [st, config]


## Plays ticks, settling whatever comes up the way a player might, the same way each time.
func _play(st: GameState, ticks: int) -> void:
	for i in ticks:
		st.step()
		if st.pending:
			st.resolve_pending()
		if not st.pending_recruit.is_empty():
			st.resolve_recruit(false)
		if not st.pending_rare.is_empty():
			st.resolve_rare(true)
		if st.pending:
			st.resolve_pending()
		st.liberations.clear()
		st.losses.clear()
		st.card_offer.clear()
		if st.game_over != "":
			return


## to_dict() with what legitimately differs between two copies taken out: instance ids
## (the bond keys are rebuilt from them), and when it was saved.
func _norm(x: Dictionary) -> Dictionary:
	var c := x.duplicate(true)
	c["meta"].erase("saved")
	for u in c["units"]:
		u.erase("iid")
	for s in c["squads"]:
		s["bond_battles"] = s["bond_battles"].values()
	return c


func _deploy_some(st: GameState) -> void:
	for s in st.army.squads():
		if s not in st.squads and st.deploy_blocker(s) == "":
			st.deploy(s, PackedInt32Array([st.map.enemy_base]))


func test_save_then_load_reproduces_the_state() -> void:
	var g := _game()
	var st: GameState = g[0]
	_deploy_some(st)
	_play(st, 900)
	check_eq(SaveGame.blocker(st), "", "free to save")
	var saved := SaveGame.to_dict(st, g[1])
	var loaded = SaveGame.from_dict(d, saved.duplicate(true), GameLog.new())
	check(loaded is Dictionary, "it loads: %s" % str(loaded) if loaded is String else "it loads")
	var back: GameState = loaded["state"]
	check(_norm(SaveGame.to_dict(back, g[1])) == _norm(saved), "saving the loaded game gives the same file")
	check_eq(back.squads.size(), st.squads.size(), "the same squads on the map")
	check_eq(back.gold, st.gold, "the same gold")
	check_eq(back.clock.tick, st.clock.tick, "the same time")
	var pairs := 0
	for s in back.squads:
		if s.side == "player" and s in back.army.cells:
			pairs += 1
			check(s.tech == back.tech and is_same(s.tech, back.tech), "player squads share the army's tech")
	check(pairs > 0, "squads on the map are the army's own")
	if st.opinion_leader:
		check(back.opinion_leader in back.army.units(), "the Opinion Leader is the same unit as in the army")


func test_the_game_plays_on_identically_after_loading() -> void:
	var g := _game(77)
	var st: GameState = g[0]
	_deploy_some(st)
	_play(st, 600)
	var loaded = SaveGame.from_dict(d, SaveGame.to_dict(st, g[1]), GameLog.new())
	var back: GameState = loaded["state"]
	_play(st, 1500)
	_play(back, 1500)
	check(_norm(SaveGame.to_dict(back, g[1])) == _norm(SaveGame.to_dict(st, g[1])), "the same game 1500 ticks later")
	check_eq(back.log.entries.size(), st.log.entries.size(), "the same log")


func test_slots_on_disk() -> void:
	SaveGame.dir = "user://test_saves/"
	var g := _game()
	var st: GameState = g[0]
	_play(st, 100)
	check_eq(SaveGame.write(2, st, g[1]), "", "saved to slot 2")
	var meta := SaveGame.summary(2)
	check_eq(int(meta["day"]), st.clock.day(), "the slot shows the day")
	check_eq(int(meta["gold"]), st.gold, "and the gold")
	var r = SaveGame.read(2, d, GameLog.new())
	check(r is Dictionary and r["state"].clock.tick == st.clock.tick, "read back")
	check(SaveGame.read(3, d, GameLog.new()) is String, "an empty slot says so")
	check(SaveGame.summary(3).is_empty(), "and lists as empty")
	DirAccess.remove_absolute(SaveGame.path(2))
	SaveGame.dir = "user://saves/"


func test_broken_and_old_files_are_refused() -> void:
	SaveGame.dir = "user://test_saves/"
	DirAccess.make_dir_recursive_absolute(SaveGame.dir)
	var f := FileAccess.open(SaveGame.path(1), FileAccess.WRITE)
	f.store_var(["not", "a", "save"])
	f.close()
	var r = SaveGame.read(1, d, GameLog.new())
	check(r is String and r.contains("damaged"), "a broken file: %s" % str(r))
	var g := _game()
	var old := SaveGame.to_dict(g[0], g[1])
	old["version"] = 0
	f = FileAccess.open(SaveGame.path(1), FileAccess.WRITE)
	f.store_var(old)
	f.close()
	r = SaveGame.read(1, d, GameLog.new())
	check(r is String and r.contains("version"), "an old version: %s" % str(r))
	var moved := SaveGame.to_dict(g[0], g[1])
	moved["terrain_hash"] = 12345
	r = SaveGame.from_dict(d, moved, GameLog.new())
	check(r is String and r.contains("map"), "a map that no longer generates the same: %s" % str(r))
	DirAccess.remove_absolute(SaveGame.path(1))
	SaveGame.dir = "user://saves/"


func test_not_mid_battle() -> void:
	var g := _game()
	var st: GameState = g[0]
	var ours: Squad = st.player_squads()[0]
	var foe: Squad = st.squads.filter(func(s: Squad): return s.side == "enemy")[0]
	st.pending = st.start_battle(ours, foe, foe)
	check(SaveGame.blocker(st) != "", "no saving with a battle waiting")
	check(SaveGame.write(1, st, g[1]) != "", "write refuses too")
