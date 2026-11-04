# Status and handoff

Where the project stands, for picking up in a new session or on another machine. Update it at the end of each session.

## Where we are (2026-11-04)

- **M1 (Map), M2 (Battle), M3 (Army): all sessions done.** See the Status column in `ROADMAP.md`.
- **M3 milestone check:** the user has been playing between sessions and is happy with the state of it. The two pacing flags are still open; they're logged in `DECISIONS.md`:
  - Upkeep is about 225 gold a day against 50 per town held.
  - XP takes roughly 4 to 5 battles per level, against the spec's 2.5.
- **Last work (session 023):**
  - A clock icon before the speed dropdown and a calendar icon before the day and time.
  - A compact squad menu:
    - Stat icons at the top right: a terrain hex, the speed number and an alignment icon.
    - Slot boxes with first name, class and HP bar.
    - Clicking the overlay closes it.
  - Squads keep their route after a battle unless they're knocked back, wiped out or lose their leader.
- **Tests:** 204 passing (`tools\run_tests.ps1`).

## Next up

- **M4 session 1, Map 1 setup (SPEC §18):**
  - Roll 6 Serf-line squads with the coverage and soft rules.
  - The Opinion Leader.
  - Starting cards, tech and gold.
- After that, the rest of M4 in `ROADMAP.md` order.
- Parked for later: plan icons and a more compact toolbar once its full button set is known (a note under M3 in `ROADMAP.md`).
- Open offer: extend click-off-to-close to the other small popups (building, deploy, supplies, cards). The user hasn't asked for it yet.

## How the user works

- **One git branch per session,** named `session-NNN` (next: `session-024`), cut from `main`.
- **Commit locally only:**
  - Never push or merge; the user merges and pushes, then says "continue".
  - Commit messages end with `Co-Authored-By: Claude Opus 5.5 <noreply@anthropic.com>`.
- **Session reports:** plain and brief. What changed, how to try it, and the merge note.
- **Questions:** UI and UX requests come in between sessions and are handled as they arrive. Ask (citing a SPEC section) only for real design questions, and log small calls in `DECISIONS.md`.
- **Leave user files alone:**
  - Don't kill the user's open Godot editor.
  - Don't touch `export_presets.cfg` or builds; they're gitignored.

## Practical notes

- **Godot 4.5.1** console binary on the old machine: `C:\Godot\Godot_v4.5.1-stable_win64_console.exe`. The path may differ on the new machine.
- **First run after cloning:** run `godot --headless --path . --import` so the `class_name` scripts register before the tests run.
- **Screenshots:** a temporary SceneTree script in the project root. It builds a `Battlemap` in `_process` (not `_init`) using `GameConfig.create(data, seed)`, saves `root.get_texture().get_image()` to a PNG, then quits. Delete the script afterwards.
- **Parse errors:** a script that fails to parse makes a headless `-s` run hang. Use `--check-only -s res://file.gd` and wrap runs in `timeout`.
- **Types:** inferring a type from a Variant with `:=` is an error; give such variables an explicit type.
