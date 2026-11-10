# Landwar: working rules

Real-time squad strategy game in Godot 4.7.2 (GDScript). The design is `SPEC.md`; the plan is `ROADMAP.md`; small calls made along the way are in `DECISIONS.md`. Where things stand and what comes next is in `STATUS.md`: read it first in a new session. `RULES.md` is the game's rules as actually implemented (not the full design) — a living summary for a player or tester, not a developer.

## How to work

- **Communicate plainly and briefly.** Say what changed and how to try it, not how it was done.
- **Prefer a smaller codebase.** No speculative abstractions, plugins or frameworks. Write the simplest thing that meets the spec.
- **The spec is the design.** Don't redesign. If the spec is unclear, contradictory, or would make the code much bigger, stop and ask, citing the section number. For small gaps, pick the simplest reading, log it in `DECISIONS.md`, and continue.
- **Godot docs for the installed version (4.7.2).** Don't guess at APIs. Dump the exact reference with `godot --headless --doctool <dir>` and grep `<dir>/doc/classes/*.xml`, or use docs.godotengine.org/en/4.7.
- **Keep `RULES.md` current.** When a session adds, changes or finishes a game rule (not internal refactors), update `RULES.md` in that same session: add what's now true, and move anything out of its "Not yet in the game" section once it's real.

## Code rules

- **Rules stay separate from scene nodes.** Everything in `rules/` is plain classes (RefCounted or static) that never touch the scene tree, so tests and the headless sim can run them. Scenes in `scenes/` and `ui/` only display state and pass on input.
- **Content lives in data.** Never hard-code a stat, price, class or tunable number. Put it in `data/*.json` (placeholders are fine). Unit data comes from the spreadsheet via `python tools/xlsx_to_json.py`; never hand-edit `units.json`, `lines.json`, `role_templates.json` or `mechanics.json`. The sheet is `data/units-landwar-v3.xlsx`; trait and aura numbers the game uses live in `data/battle.json`. After changing the sheet's Icon columns, also run `python tools/unit_icons.py` (writes `data/unit_icons/`).
- **Everything is seeded and logged.** Randomness comes from `RngStreams` (one stream per system, derived from the game seed). Events go to `GameLog`.
- Scenes are built mostly in code with small `.tscn` files.

## Layout

- `rules/`: game logic (hex math, map generation, data loading, log, RNG)
- `scenes/`, `ui/`: drawing and input
- `data/`: JSON content, the source spreadsheet, names CSV
- `tools/`: converter, map preview, test script
- `tests/`: headless tests (`test_*.gd`, methods `test_*`)

## Checking work

- Tests: `tools\run_tests.ps1` on Windows, `tools/run_tests.sh` on macOS/Linux (optional name filter as first argument). Must be green before a session closes.
- Map images: `godot --headless --path . -s res://tools/map_preview.gd -- <seed> [size] [preset] [out.png]`, then look at the PNG.
- A script that fails to parse makes a headless `-s` run sit idle forever. Wrap ad-hoc runs in `timeout`, and use `--check-only -s res://path.gd` to find the error. By Godot 4's defaults, inferring a type from a Variant with `:=` (e.g. `var x := array.max()`) is an error; give such variables an explicit type.
- The user playtests only at milestones (SPEC §23). Check your own work in between.
