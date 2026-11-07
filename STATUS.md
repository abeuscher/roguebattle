# Status and handoff

Where the project stands, for picking up in a new session or on another machine. Update it at the end of each session.

## Where we are (2026-11-06)

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
- **Tests:** 230 passing (`tools/run_tests.sh` on this Mac, `tools\run_tests.ps1` on Windows).

## Next up

- **M4 session 4, Hidden mechanics (SPEC §12.2):** morale, loyalty, bonds, with their visible signs.
- After that, the rest of M4 in `ROADMAP.md` order. M4 session 6 (debug panel) can build on `ui/debug_panel.gd` rather than starting fresh.
- Deferred from session 025: in-battle AI (a retreat threshold, and battle-tactic weighting per role) — currently the enemy side always uses the "best" tactic and never retreats mid-battle. Not scheduled to a specific M4 session yet.
- **Parked for discussion after M4** (user's own notes, logged 2026-11-06, not yet decided — see `ROADMAP.md`): half-slot front/rear placement with literal coverage; unit graphics (a playing-card-style attack view, a character sheet); class/ranged-vs-melee iconography in Edit Units; a small 3-stage campaign mode layered on the single-map game.
- Parked for later: plan icons and a more compact toolbar once its full button set is known (a note under M3 in `ROADMAP.md`).
- Open offer: extend click-off-to-close to the other small popups (building, deploy, supplies, cards). The user hasn't asked for it yet.

## How the user works

- **One git branch per session,** named `session-NNN` (next: `session-027`), cut from `main`.
- **Commit locally only:**
  - Never push or merge; the user merges and pushes, then says "continue".
  - Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Session reports:** plain and brief. What changed, how to try it, and the merge note.
- **Questions:** UI and UX requests come in between sessions and are handled as they arrive. Ask (citing a SPEC section) only for real design questions, and log small calls in `DECISIONS.md`.
- **Leave user files alone:**
  - Don't kill the user's open Godot editor.
  - Don't touch `export_presets.cfg` or builds; they're gitignored.

## Practical notes

- **Godot 4.5.1** console binary on the old machine: `C:\Godot\Godot_v4.5.1-stable_win64_console.exe`. The new machine (macOS) uses **Godot 4.7.2**, installed at `/Users/al/Downloads/Godot.app`.
- **First run after cloning:** run `godot --headless --path . --import` so the `class_name` scripts register before the tests run.
- **Screenshots:** a temporary SceneTree script in the project root. It builds a `Battlemap` in `_process` (not `_init`) using `GameConfig.create(data, seed)`, saves `root.get_texture().get_image()` to a PNG, then quits. **Doesn't work under `--headless` on this machine** (confirmed 2026-11-07): `root.get_texture()` comes back null (the dummy rendering driver headless forces has no framebuffer to read), so `get_image()`/`save_png()` fail. `tools/map_preview.gd` gets away with it because it builds the PNG straight from map data (`MinimapImage.build`), not from a live render — that data-driven approach is the only one that's actually worked here. A real screenshot of a scene would need a non-headless run (or a virtual display), which isn't set up on this machine. Delete the script afterwards.
- **Parse errors:** a script that fails to parse makes a headless `-s` run hang. Use `--check-only -s res://file.gd` and wrap runs in `timeout`. On this Mac there's no `timeout`/`gtimeout` on PATH; rely on the shell tool's own timeout instead.
- **`-s` scripts must `extends SceneTree`,** not `Node`: a `Node`-based script loads but never ticks `_process` under `-s`, so it sits idle forever with no CPU use (easy to mistake for a hang). `tests/run_tests.gd` is the model to copy.
- **Types:** inferring a type from a Variant with `:=` is an error; give such variables an explicit type.
