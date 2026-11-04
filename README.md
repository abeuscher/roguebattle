# Landwar

A real-time squad strategy game in Godot 4.5.1. Design: [SPEC.md](SPEC.md). Plan: [ROADMAP.md](ROADMAP.md).

## Run the game

Open the folder in Godot 4.5.1 and press F5, or:

```
godot --path .
```

Title → Start → Configurator (every map setting, live preview, seed, share code) → summary → battlemap. On the battlemap, the bottom toolbar has Edit Units (U: squads, recruits, items, heal and revive at base) and Deploy Squad (D: pick a squad at base, lay its route like a move, confirm the cost). Keep a squad with a ground unit in an enemy town or tower for an hour to liberate it; click a building for its popup. Gold: income from held towns and towers and upkeep for every unit at noon; shops (squad menu, standing in a liberated building with a shop) sell Serfs, herbs and items; temples heal and revive. click a squad to see its units, choose Move, click hexes to lay rally points and click the last one again to commit. Space pauses, PgUp/PgDn change speed, U opens Edit Units (drag units between squads, rows and the recruit pool; click a squad for its detail and items), L opens the log, Esc opens the menu, the minimap jumps the view. Wheel zooms, drag pans, F fits, H shows or hides hidden sites and lairs, G toggles the hex grid, O cycles debug overlays, T changes the test squad's travel type. Enemy squads (red flags, marked with their role's initial) show only within sight; move next to one to fight, or choose Ranged attack in the squad menu. Battles open the battle view: watch it play out, pause with Space, change tactic, retreat or skip to the end. L shows the full battle log; tick "Show hidden values" for hit chances, rolls and modifiers.

## Run the tests

```
tools\run_tests.ps1
```

This runs every test headless and exits non-zero on any failure. Pass a word to run only matching tests (`tools\run_tests.ps1 mapgen`). The script finds Godot through `$env:GODOT`, then `godot` on PATH, then `C:\Godot\Godot_v4.5.1-stable_win64_console.exe`.

The raw commands:

```
godot --headless --path . --import
godot --headless --path . -s res://tests/run_tests.gd
```

## Update unit data

After editing the spreadsheet in `data/`:

```
python tools/xlsx_to_json.py [path/to/sheet.xlsx]
```

This reads `data/units-landwar-v3.xlsx` and rewrites `data/units.json`, `lines.json`, `role_templates.json` and `mechanics.json`, and lists any sheet problems in `data/data_report.txt`. It needs `openpyxl` (`pip install openpyxl`).

## Battle sim

```
godot --headless --path . -s res://tools/battle_sim.gd -- vanguard shieldwall 500
godot --headless --path . -s res://tools/battle_sim.gd -- all 100
```

Squad builds live in `data/sim_builds.json`. One pair reports win rates, the HP each side loses in the first battle and how many battles it takes to rout the loser. `all` plays every pair (about 1.5 minutes at 100 trials) and checks the balance targets of SPEC §12.4.

## Preview a map

```
godot --headless --path . -s res://tools/map_preview.gd -- <seed> [small|medium|large] [preset] [out.png]
```
