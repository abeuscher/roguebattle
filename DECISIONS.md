# Decisions

Small calls made where the spec left a gap. Newest at the bottom. Anything here can be overturned.

## Session 001 (2026-11-02)

- **Spreadsheet file.** The repo has `unit-table-final.xlsx`, not `units-landwar-v3.xlsx`. It's in `data/` under its real name. The converter uses `units-landwar-v3.xlsx` when present and falls back to it otherwise. See "Open data issues" below.
- **Hex layout.** Pointy-top hexes. Maps are width×height rectangles in odd-r offset layout (odd rows shifted half a hex right); all logic uses axial (q, r).
- **Impassable terrain** is marked `"impassable": true` in `data/terrain.json`, with no difficulty number.
- **Ticks per day (1,440)** is a code constant, because a tick is defined as one minute. Ticks per real second, the game speeds and slots per size are in `data/rules.json`.
- **Terrain amounts** (none/low/medium/high) are fractions of land: 0 / 3% / 10% / 20% (placeholders in `data/mapgen.json`). Each terrain takes the best-scoring hexes from a noise field. Snow favors the north, lava sits along mountain ridges, swamps sit low and wet.
- **Continent land %** defaults to 55 with 3 medium offshore islands (placeholders). Small blobs that break off the main landmass are removed, so the default map has one continent.
- **Shallow water** is the 2-hex shelf around land. Everything further out is deep.
- **Test runner** is a small homemade script (`tests/run_tests.gd`), not GUT. It uses Godot 4.5's `Logger` to fail any test that raises a script error.
- **Logs** go to `user://logs/game-<time>.log`.

## Open data issues (need the v3 sheet or an answer)

1. **Wrong sheet version.** The sheet has 160 classes; the spec says 190. It has no Traits, Leader aura or XP rate columns and no Mechanics tab. Level cost (§9.4), traits and auras (§11) depend on these. M1 doesn't need them; M2 battle traits and M3 levelling do.
2. **Classes the spec names that the sheet lacks:** Herald, Standard-Bearer, Quartermaster, Provisioner, Sapper, Occultist, Necromancer, Seer, Oracle, Falconer, Dragonslayer, Smuggler/Fence, Sprite, Faerie Queen. No Tiny units and no T lines exist.
3. **§18 terrain coverage can't be met.** Serf lines only reach Plains, Forest and Swamp. The spec wants Mountain and Desert covered too.
4. **Terrain names differ.** The sheet uses `Water` and `Sky`; the spec splits shallow and deep water and calls flyers' travel type Sky. Plan: `Water` = water native (full speed on shallow and deep).
5. **Alignment leans** include `By alignment` (Witch) and `Varies by color` (dragons) beside Any, Holy, Evil and Neutral. Plan: treat both as Any at roll time; the branch is chosen at promotion (§9.4).
6. **Names worth checking before release.** `unit-names.csv` uses well-known character names from published novels (al'Thor, Cauthon, Gamgee, Vimes and others). A few class names are existing characters or trademarks (Lion-O, Balto, Cujo).
