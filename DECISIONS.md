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

## After session 001 (requested by the user)

- **Textured terrain.** Each terrain gets a hex tile drawn in code (`ui/terrain_tiles.gd`): its color plus one whole motif per hex (tree, peak, grass, dunes, drifts, water drops, lava rocks, cliff hatching). Water stays plain blue. Region borders follow hex edges, and no motif is cut at a border. Placeholder art until after M4.
- **Map view** draws hexes with one MultiMesh per terrain per 64×64-hex chunk, over a flat-color copy that hides gaps when zoomed far out. World hex size is 32; tiles are drawn at 48 so they stay sharp up close.

## Session 002 (2026-11-02)

- **Reachable on foot, always.** After generation, every landmass is joined to the largest by the cheapest crossing: deep water becomes a shallow ford, cliffs become a mountain pass, lava gets a gap, air gaps get a bridge (`crossing` in `data/terrain.json`). Islands are reachable by slow shallow channels, which punishes ground armies without making the map unwinnable.
- **Bridges are roads.** `MapData.road` marks road hexes; a road on impassable terrain is a bridge. Session 3 adds land roads to the same layer.
- **Rivers** are 1-hex-wide deep water running from inland to the sea, winding along a noise field. They can join. Crossings alternate bridge and ford every 18 hexes (placeholder). Continent has 2 rivers, River Valley 8, Islands 1.
- **Cliffs** are now a terrain amount (default low). They take the crests of the mountain ranges, so they form spines inside ranges; reachability cuts passes through them.
- **Islands / Floating Isles** split the map between 2–4 (or 3–5) island centers with a wandering water or air channel between them. Floating Isles use air gaps instead of sea, with no shallows.
- **Archipelago** cuts the land with a network of thin straits and keeps islands as small as 6 hexes.
- **Deep Forest / Tundra** scale one terrain's amount up (`terrain_scale`), since the spec's levels stop at high.
- **Frozen lakes** (user request) are their own terrain, light blue, only in Tundra: about 15% of the snow, cut out as blobs. Same difficulty as snow, and `"native_as": "snow"` in `data/terrain.json` means snow natives count as native there too. Later movement and battle rules must read `native_as`.
- **Volcanic ash plains** are plain plains; there is no ash terrain in §6.3. Volcanic adds 8 short lava flows running down from the mountains.

## Session 003 (2026-11-02)

- **Bases come first.** The spec lists bases and goal as layer 7, but roads (layer 5) must link the spawn and goal, so bases are placed before the other buildings. Default spawn side: player west, enemy east (`spawn_side`: west, east, north, south). Each base goes in the outer 12% of buildable land on its side, near the middle of that side.
- **Goal = Enemy Base** for now. "Reach the goal" will use the same hex until the configurator says otherwise.
- **Building counts** at medium density on a small map: 16 towns, 10 towers, 4 temples, 2 nomad camps, 8 hidden sites (placeholders). Counts scale with map area and with density (none 0, low ×0.5, medium ×1, high ×1.5).
- **Quadrants.** Towns, towers and temples are split n/4 per quadrant; the remainder goes to random quadrants, so counts stay within one of each other.
- **Temples** prefer high ground (mountains or hexes next to them) in their quadrant, falling back to any land.
- **Order inside layer 4:** temples, towns, towers, then roads, then nomads (they need roads for their 50% road bias) and hidden sites (they must be off-road).
- **Roads** link the visible buildings (bases, towns, towers, temples) with a minimum spanning tree per landmass, plus 15% extra short links for loops at "main" (50% at "full"). Routes favor plains, avoid forest, swamp and mountains, and reuse existing roads. They stop at the open sea, lava and cliffs, and cross rivers by bridge. Islands get their own networks; roads don't cross the shallow channels between them. Fords on rougher settings are not done yet.
- **Hidden-site roads** run from the site to the nearest existing road (none when road coverage is "none").
- **Lairs** pick a home terrain from the sheet's Terrain column (Water lairs sit in shallows, Sky lairs on mountains, Lava lairs on lava), at least 4 hexes from roads and 15 (scaled by map width) from both bases. Danger = distance from the Player Base ÷ distance between bases, clamped to 0–1.
- **Rule 3 (§6.5):** any terrain region of 0.4% of the map or more (360 hexes on small) with no building or lair gets a lair (or a tower if neutrals are off). This adds about 3–7 lairs on top of the density count. At 0.2% it added far more.
- **Speed.** Small maps take about 1.1 s, medium about 5 s, large about 11 s. The user confirmed this is fine: the spec's "a few seconds" means not minutes, so no speed pass is planned.
