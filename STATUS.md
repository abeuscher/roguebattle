# Status and handoff

Where the project stands, for picking up in a new session or on another machine. Update it at the end of each session.

## Where we are (2026-11-09)

- **M1 (Map), M2 (Battle), M3 (Army): all sessions done.** See the Status column in `ROADMAP.md`.
- **M3 milestone check:** the user has been playing between sessions and is happy with the state of it. The two pacing flags are still open; they're logged in `DECISIONS.md`:
  - Upkeep is about 225 gold a day against 50 per town held.
  - XP takes roughly 4 to 5 battles per level, against the spec's 2.5.
- **Session 024, M4 session 1, Map 1 setup (SPEC §18):**
  - `rules/map1_setup.gd` rolls the real starting army: 6 Serf-line squads (a stage 3 leader plus four stage 2 units), terrain coverage across the 6 and the front-line/healer-or-support soft rule. `GameState.setup_army()` now calls it instead of the old `placeholder_army` (removed from `rules.json`).
  - Terrain coverage is checked against each squad's leader, not the squad's actual (always-Plains) travel-type vote; see `DECISIONS.md` session 024.
  - The Opinion Leader is whichever of the 6 lands in army cell 0 (unchanged convention, now fed real squads); it's the only one that starts on the map, at the Player Base. Starting cards (3), tech points (3, already wired) and gold (500, already wired) unchanged.
  - Playtesting aid (user's request): a debug panel (backtick) with a Wide roster button, so testers don't need launch args — `ui/debug_panel.gd`, `GameState.reroll_wide_roster()`. This is the start of the real §19.2 debug panel (M4 session 6 fills in the rest).
  - Found via that tool and fixed: Herald (`can_lead: false`) could get picked as a squad's "leader," leaving the squad leaderless. See `DECISIONS.md`.
- **Session 025, M4 session 2, Enemy AI (SPEC §12.3, §17):**
  - `rules/enemy_ai.gd` (`EnemyAI`): the leader, base guard and garrisons hold their post (the existing contact/ranged-attack rules cover "fights anything within a short radius"); raiders and attacking wildcards march on the weakest player-held town or tower (least Threat defending it), or the Player Base if the player holds none; defending wildcards reinforce the nearest threatened enemy-held building, or hold their ground if nothing's threatened.
  - Scoped to map-level movement/targeting only, agreed with the user — in-battle tactic choice and a retreat threshold are deferred to a later AI session. See `DECISIONS.md` session 025.
  - `data/ai.json` (new): just `wildcard_attack_chance` for now. `Squad.ai_mode` is new, rolled once per wildcard in `place_enemies()`.
  - `tests/test_enemy_ai.gd`; also ran a real generated map 2000 ticks on 5 seeds headless with no hangs or crashes.
- **Last work (session 026), M4 session 3, Neutrals and recruiting (SPEC §6.7, §16):**
  - `rules/neutral_squads.gd` (`NeutralSquads.roll`): each lair gets one race-line squad (R/N/L/T lines, never a Serf line) native to its home terrain; danger (already computed at lair placement) picks how far along that line's stages it is and adds levels. `place_neutrals()` (called once at map start, next to `place_enemies()`) places one per lair.
  - `rules/neutral_ai.gd` (`NeutralAI`): a roamer chases the nearest living squad (player or enemy) within its patrol radius (`data/neutrals.json`), else wanders near its lair.
  - **Found and fixed a real bug:** `hostile()` never counted enemy against neutral as hostile (both sides of its old check compared to `"player"`), so §6.7's "neutrals fight both sides" silently didn't apply to the enemy half. Fixed, and `_check_contact()` now scans every pair, not just player-vs-hostile. An enemy-vs-neutral fight resolves immediately (no pause); a fight involving the player still opens the battle view.
  - That fix exposed a deeper assumption: `end_battle`/`_award_xp`/`_battle_standing` keyed off *position* ("side 0") assuming it was always the player, which only enemy-vs-neutral fights could ever violate. Reworked to key off each squad's actual `.side`. See `DECISIONS.md` session 026 for the full list (plus a pre-existing test that only passed because of the old assumption, now fixed).
  - Recruit-or-fight (§16): `GameState.pending_recruit` + `resolve_recruit()`, a new `ui/recruit_popup.gd` modal (shows the class, not the count). Recruit rolls the existing `recruit_chance()`; failure fights with the neutrals going first (`Battle.first_side`, a field that already existed for this but was never set until now).
  - `tests/test_neutrals.gd` (11 tests); also ran 5 real generated maps 3000 ticks each headless (full setup: army, enemies, neutrals) with no hangs or crashes.
- **Between sessions (2026-11-07), liberation popup:** liberating any building now opens a popup focused on it, with the card it draws (or a Seer/Oracle's choice of one) shown in the same dialog instead of a separate one. No Options toggle in the end — see `DECISIONS.md`, a liberation always draws a card, so a "only pop up when there's a card" toggle would never do anything; the user chose to always show it instead. `GameState.liberations` (queued, oldest first), `ui/liberation_popup.gd`.
- **Last work (session 027), M4 session 4, Hidden mechanics (SPEC §12.2):**
  - Morale and drive-off already existed (from M2) but nothing ever moved `Squad.morale` off its starting 50, so drive-off could never actually trigger. It now falls on being outnumbered, the leader getting hit, a unit dying, fighting off the leader's home terrain, or at the wrong time of day (holy by night, evil by day); it rises on a win, a liberation or resting in a temple. Both sides of every battle, not just the player's — an enemy or neutral squad has to be drivable-off too. Below 30 it's −10% damage (`Battle.modifier()`); below 25, drive-off (already built) becomes reachable. All numbers are placeholders in `data/battle.json`'s new `morale` key; the spec gives none.
  - Bonds (new): two units that fight 6 battles together in the same squad gain +5% damage and +5% dodge while both live, announced once in the log. Tracked on `Squad` (`bond_battles`, `bonded_pairs`), not `Unit` — an earlier draft stored it on `Unit` as direct Unit↔Unit references, which is a reference cycle RefCounted can't collect; caught because the full test suite started reporting leaked objects that a pre-change run didn't. See `DECISIONS.md`.
  - Loyalty (new, recruited neutrals only): `Unit.recruited`/`Unit.loyalty`, set when `resolve_recruit()` succeeds. Rises on a win or with high reputation; falls sitting unused in the recruit pool. Very low loyalty warns for a day (logged) before it may actually leave the army for good (`Army.remove()`, new) — never mid-battle, since this only runs on a day change.
  - Deferred: the spec's portrait-level visible signs (a shaken leader portrait, an uneasy one) — no portraits exist yet to shift. Every mechanic's log-line signal is in place, matching the ROADMAP's own verify line.
  - `tests/test_hidden_mechanics.gd` (19 tests); also ran 5 real generated maps 4000 ticks each headless with no hangs or crashes.
- **Last work (session 028), M4 session 5, Victory, defeat, end screen (SPEC §6.8, §4):**
  - Every configurator victory/defeat toggle is now checked, every tick (`GameState._check_game_over()`), and the map freezes for good the instant one fires (`step()` no-ops once `game_over` is set). Victory: defeat the enemy leader (default), reach the goal, defeat N enemy squads or all of them, hold a share of towns for a stretch of time, survive a timer. Defeat: the Opinion Leader dies (default), the Player Base is captured.
  - **"Player Base is captured" needed a real capture mechanic first** — nothing let the enemy take any building before this. Asked the user how far to take it; they chose full symmetric capture over an instant no-timer trigger or dropping it. `_capture()` (§6.5) now works for both sides: an unopposed enemy squad can retake a liberated town or tower, or take the Player Base, the same way you liberate one — flips the owner and logs it, with a morale bump but none of the player-only liberation flavor (gold, reputation, alignment, a card). The existing enemy AI (session 025) already marches raiders and attacking wildcards onto your weakest-held building, or the Player Base once you hold none, so no new AI targeting was needed.
  - `ui/end_screen.gd`: a modal like the other popups, naming why the map ended plus gold, reputation, enemy squads defeated, towns held, and tech points (the map-completion bonus from `data/tech.json`, awarded on victory only, finally wired up). The only way out is back to the title — no second map to continue to yet.
  - **Caught a real hang, not just a wrong test:** the first version defaulted the on-by-default toggles to `true` when a `GameState` had no settings at all, which is true of most of the test suite — so nearly every other test's map looked "lost" from its very first tick, freezing the clock for good. One pre-existing test looped `while clock.minute_of_day() != noon: step()`, which then never ends. Fixed by defaulting every toggle to off instead; the real game always supplies the full settings dict, so only ad hoc test `GameState`s were affected. See `DECISIONS.md`.
  - `tests/test_victory_defeat.gd` (16 tests); also ran 5 real generated maps headless end-to-end with no player orders at all (so each lost quickly) purely to confirm the new paths run without crashing.
- **Last work (session 029), M4 session 7, Variable map size (SPEC §6.1, §6.2):** done ahead of session 6, at the user's request, for faster playtesting.
  - The configurator's old 3-way "Map size" (Small/Medium/Large) is now two independent sliders, "Map width (hexes)" and "Map height (hexes)" (100–1200 and 60–675), defaulting to Small's 400×225. Landing exactly on a named size (Small, Medium, Large) still shows that name next to the numbers (`GameConfig.size_name()`); any other combination just shows the numbers, no "Custom" field needed anywhere else. `data/mapgen.json`'s `"sizes"` dict stays, just as the source for that naming and for `tools/map_preview.gd`'s CLI (which now also takes a literal `WxH` in place of a named size).
  - Every place that read the old `settings["size"]` string now reads `map.width`/`map.height` directly (both already existed on `MapData`): the new-map log line, the battlemap's info line, the share code, the summary screen. `GameConfig.CODE_VERSION` bumped to 2 so an old share code is cleanly rejected instead of silently misreading into the new field layout.
  - Checked generation at width/height down to 100×60 across four presets — all generate in well under a second with a sane building count and both bases placed; no floor beyond the slider's own 100/60 minimum was needed.
  - A red herring while testing: a "small map plays start to finish with zero player orders" test looked hung, but the actual cause was the test script itself holding a stale reference to an enemy squad that had been wiped in combat and removed from the live simulation — the game was fine, simulating normally without it. Rewrote that test around the survive-timer instead (deterministic, doesn't depend on how combat plays out) rather than chasing combat RNG. See `DECISIONS.md`.
  - `tests/test_map_size.gd` (4 tests, 269 total).
- **Tests:** 269 passing (`tools/run_tests.sh` on this Mac, `tools\run_tests.ps1` on Windows).

- **Last work (session 030), M4 session 6, Debug panel complete (SPEC §19.2, §19.1), plus the first playtest fixes:**
  - **Debug panel:** backtick now has every §19.2 tool, in tabs: Map, Time, Units, Resources, Battle, AI, Simulation. The rules are in `rules/debug_tools.gd` (`DebugTools`); the switches the simulation checks are `GameState.debug_*`. Battle replay runs on deep copies with the saved RNG state, so nothing on the map changes. Each fairness rule can be switched off. "Show hidden numbers" is one switch, `GameLog.show_hidden`, shared by the log panel and the battle view (§19.1's debug toggle).
  - **Playtest fixes (user's notes, 2026-11-08):**
    - Every generated squad (player, enemy, neutral) gets balanced rows: 3:2 or 2:3, and 2:2 for 4-unit enemies (`Squad.balance_rows()`).
    - Enemy routes are no longer drawn, since they gave away hidden squads.
    - Edit Units overview chips show the first name, and the level on a small corner earmark.
    - The liberation popup has a "View all cards" toggle that lists the hand.
  - `tools/run_tests.ps1` defaults to Godot 4.7.2. 283 tests passing.
- **Last work (session 031), M4 session 8, Playtest round 1:**
  - **Battle start:** `ui/encounter_popup.gd` pauses and centers the map, with Go to fight. The battle view then waits on a Fight button. That wait is the `battle_wait_for_fight` option, on by default. Ranged attacks and fights after the recruit popup skip the dialog.
  - **Options:** a real Options screen (`ui/options_screen.gd`), reached from the Start screen and the in-game menu. Defaults are in `data/options.json`; the player's choices are saved in `user://options.json` (`rules/player_options.gd`).
  - **Shops:**
    - Limited stock, shown left of each Buy button, refilled at noon (`shop_stock()` is now id -> count, plus `restock()`).
    - A Revival Draught (80 g) usable anywhere on the map.
    - One cure potion per status (8 of them), used from a new Items button in battle; each shop carries 4.
    - SPEC §15.1's consumables row is updated to match (the user's design call).
  - 290 tests passing.
- **Last work (session 032), M4 session 9, Playtest round 2:**
  - The battle view puts each party's name over its side with "vs." between them; the old title line is gone.
  - Recruit shows its result in the same popup before any battle ("They join you!" or "They refuse", with the chance and the main reason). `resolve_recruit()` returns `{joined, chance, text}`.
  - A neutral squad leaves the map after any battle with the player (`_neutral_leaves()` in `end_battle`).
  - The encounter camera glides and zooms to the fight (`MapCamera.fly_to()`, `encounter_camera` in `data/battle.json`) and stays on the map; the dialog appears below the squads once it lands.
  - XP after a retreat follows SPEC §9.4 (every survivor earns XP); left as is, waiting on the user's call. `RULES.md` corrected.
  - 290 tests passing.
- **Last work (session 033), M4 session 10, Playtest round 3:**
  - Battle view: a field of terrain hexes, small name tags, a "vs." box in the middle with the battle info; Cards opens a large picker and holds the battle until you play or close.
  - Map zoom: it worked, but pulled back if you were already zoomed in. Now it never zooms out, and it also flies to neutral meetings.
  - Retreat earns a quarter of the XP (SPEC §9.4 updated).
  - Enemy squads down half or more go home; only the Enemy Base revives enemy units; holding roles return to their `Squad.post`.
  - `hp_per_con` 3 → 4: front-row survival of a first battle 63% → 73% in the sim (which now reports it).
  - 293 tests passing.
- **Last work (session 035), M4 session 11, Playtest round 4:**
  - Bug: an enemy that walked into your squad could end up as side 0, so the result read backwards and the enemy got your tactic and tech. Contact now always puts the player on side 0.
  - The battle view has one Fight/Pause/Play button on the field. The log and controls show only while paused or waiting, in reserved space so nothing jumps. While it plays, the latest action shows beside the button.
  - The result replaces the field: Won/Lost/Retreated/Draw once at the top (`GameState.battle_result`), then two columns with HP lost and units lost. Neutral fights end with "<squad> wins/loses. The <neutrals> are beaten back / are victorious and return to the <terrain>." (`neutral_line`).
  - Edit Units lets you rearrange a squad that's out in the field (`can_rearrange`); adding or removing units still needs the base. Deploy Squad is greyed out at the cap or with nothing waiting (`deploy_menu_blocker`). New option: pause when the window loses focus (on by default).
  - 295 tests passing.

## Next up

- **M4 sessions 12 and 13 are planned in `ROADMAP.md` (playtest round 5):** session 12, "Even start", is next and changes how the game plays: every building starts neutral, building counts scale with land, the enemy (half as many squads as towns) starts at its base and decides between holding and moving on by a score with an 80/20 random element, and the player starts with a squad cap of 6 and a kit of items. Session 13 is battle-view polish, enemy squads turning home mid-route, and town names.
- **M4 milestone check: the first real playtest**, after sessions 12 and 13.
- **Unit portraits:** the user's first 8 large unit images are committed in `data/unit_art/` (not used in the game yet). Building them into the unit detail view is a future task in `ROADMAP.md`, waiting on more of the set.
- **Card art experiment (session 034, on top of 033):** every card is drawn as a picture card (`ui/card_face.gd`) using a simple SVG line drawing per animal in `data/card_art/`. Waiting on the user's verdict and their own concept.
- Then the post-M4 discussions in `ROADMAP.md`: campaign and progression first (the user's top item), then unit iconography and the other parked notes.
- Deferred from session 025: in-battle AI (a retreat threshold, and battle-tactic weighting per role) — currently the enemy side always uses the "best" tactic and never retreats mid-battle. Not scheduled to a specific M4 session yet.
- **Parked for discussion after M4** (user's own notes, logged 2026-11-06, not yet decided — see `ROADMAP.md`): half-slot front/rear placement with literal coverage; unit graphics (a playing-card-style attack view, a character sheet); class/ranged-vs-melee iconography in Edit Units; a small 3-stage campaign mode layered on the single-map game.
- Parked for later: plan icons and a more compact toolbar once its full button set is known (a note under M3 in `ROADMAP.md`).
- Open offer: extend click-off-to-close to the other small popups (building, deploy, supplies, cards). The user hasn't asked for it yet.

## How the user works

- **One git branch per session,** named `session-NNN` (next: `session-036`), cut from `main`.
- **Commit locally only:**
  - Never push or merge; the user merges and pushes, then says "continue".
  - Commit messages end with a `Co-Authored-By:` line naming whatever Claude model is doing the session (the harness's own attribution instructions say exactly what to write).
- **Session reports:** plain and brief. What changed, how to try it, and the merge note.
- **Questions:** UI and UX requests come in between sessions and are handled as they arrive. Ask (citing a SPEC section) only for real design questions, and log small calls in `DECISIONS.md`.
- **Leave user files alone:**
  - Don't kill the user's open Godot editor.
  - Don't touch `export_presets.cfg` or builds; they're gitignored.

## Practical notes

- **Godot 4.7.2** on both machines. Windows: `C:\Godot\Godot_v4.7.2-stable_win64_console.exe` (4.5.1 is still installed beside it; don't use it). macOS: `/Users/al/Downloads/Godot.app`. On Windows the Git Bash tool has `timeout`; Windows Python writes CRLF, which git normalizes.
- **First run after cloning:** run `godot --headless --path . --import` so the `class_name` scripts register before the tests run.
- **Screenshots:** a temporary SceneTree script in the project root. It builds a `Battlemap` in `_process` (not `_init`) using `GameConfig.create(data, seed)`, saves `root.get_texture().get_image()` to a PNG, then quits. **Drop `--headless`** for this one (confirmed 2026-11-07): under `--headless`, `root.get_texture()` comes back null (that flag forces a dummy rendering driver with no framebuffer at all), so `get_image()`/`save_png()` fail every time. Run the same script without `--headless` (still fine with `--resolution WxH`) and it renders through the real GPU backend (Vulkan on this Mac) and works — it briefly opens a real window on screen while it runs, then quits. `tools/map_preview.gd` stays headless-safe because it builds its PNG straight from map data (`MinimapImage.build`), never from a live render. Delete the script afterwards.
- **Parse errors:** a script that fails to parse makes a headless `-s` run hang. Use `--check-only -s res://file.gd` and wrap runs in `timeout`. On this Mac there's no `timeout`/`gtimeout` on PATH; rely on the shell tool's own timeout instead.
- **`-s` scripts must `extends SceneTree`,** not `Node`: a `Node`-based script loads but never ticks `_process` under `-s`, so it sits idle forever with no CPU use (easy to mistake for a hang). `tests/run_tests.gd` is the model to copy.
- **Types:** inferring a type from a Variant with `:=` is an error; give such variables an explicit type.
