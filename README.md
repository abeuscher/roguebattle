# Landwar

A real-time squad strategy game in Godot 4.5.1. Design: [SPEC.md](SPEC.md). Plan: [ROADMAP.md](ROADMAP.md).

## Run the game

Open the folder in Godot 4.5.1 and press F5, or:

```
godot --path .
```

Title → Start → Configurator (every map setting, live preview, seed, share code) → summary → battlemap. On the battlemap: click the test squad to see its rolled units, choose Move, click hexes to lay rally points and click the last one again to commit. Space pauses, PgUp/PgDn change speed, L opens the log, Esc opens the menu, the minimap jumps the view. Wheel zooms, drag pans, F fits, H shows or hides hidden sites and lairs, G toggles the hex grid, O cycles debug overlays, T changes the test squad's travel type.

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

This rewrites `data/units.json`, `lines.json` and `role_templates.json`, and lists any sheet problems in `data/data_report.txt`. It needs `openpyxl` (`pip install openpyxl`).

## Preview a map

```
godot --headless --path . -s res://tools/map_preview.gd -- <seed> [small|medium|large] [preset] [out.png]
```
