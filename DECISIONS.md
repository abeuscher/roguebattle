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

## Session 004 (2026-11-02)

- **Raised land.** Land hexes draw a short earth-colored face under each lower edge that meets water (0.3 hex deep), and a deeper one over air gaps (0.9 hex, Floating Isles). Cliffs draw the same face onto any lower neighbor. Mountains aren't raised; their peaks are objects instead.
- **Objects.** Trees (two variants) and peaks (two variants) are upright sprites drawn over forest and mountain hexes, with a little per-hex jitter for variety. They're batched in full-width strips two rows tall, drawn top to bottom, so lower objects overlap higher ones. Buildings and lairs are sprites in the same sorted layer. A hex with a building or lair gets no tree or peak.
- **Road links.** `MapData.road` now records which neighbors each road hex connects to (bits 0–5), so only real road links are drawn. 64 marks a road hex with no links (a lone river bridge). Any nonzero value still means "road here".
- **Movement cost rule** lives in `rules/movement.gd` (§8.3): difficulty 1/2/3 cost ×1/×1.5/×2 (`difficulty_multiplier` in `data/rules.json`), the squad's travel type counts as 1, roads ×0.75 for non-Sky, Sky ×1 everywhere. Impassable terrain can only be crossed by bridge. The movement overlay shows a ground squad with no native terrain.
- **Debug overlays** (§19.2): terrain, movement cost, roads, buildings per quadrant (counts in the HUD), lair danger. The sight-radius overlay waits for squads (M2). Trees and peaks hide while an overlay is on. In the viewer, O cycles overlays and G toggles the grid; the debug panel (M4) will call the same `MapView.overlay` and `MapView.show_grid`.
- **Frame time** on a large map with vsync off: about 2.6 ms zoomed all the way out, 0.4 ms zoomed in.

## Session 005 (2026-11-02)

- **Clock** (`rules/game_clock.gd`): 4.8 ticks per real second × game speed, with fractions carried between frames. The game starts on Day 1 at 08:00 (`start_minute`, placeholder). `step()` reports scheduled events: new day and half day at 00:00, noon and half day at 12:00, dawn at 06:00, dusk at 18:00. Noon income, nomad moves and daily healing hook in during M3.
- **Pause vs holds.** Space sets the player's pause. Open menus (and later battles) place a hold, which stops time whatever the pause says and restores the previous state when released.
- **Game state** (`rules/game_state.gd`) holds the map, clock, log, RNG streams, gold (500) and reputation (50). Scenes only read it and pass input in.
- **Night tint.** The map tints blue at night, with an hour of dusk after 18:00 and of dawn before 06:00. The HUD isn't tinted.
- **Logged to System:** new map (settings as hidden values), day changes, game speed changes, pause and resume.
- **The log** opens with L as a modal (50% dark overlay, pauses play), with category and squad filters and a "show hidden values" debug toggle. The squad filter lists the squads that appear in the log.
- **Esc main menu** (§5.3) waits for the title and start screens (session 7). Keys 1–9 and the squad number list wait for squads (session 6).

## Session 006 (2026-11-02)

- **Pathfinding** (`rules/pathfinder.gd`, §6.1). Two steps:
  1. Region to region. The map is cut into 16×16 blocks, each split into the connected areas a squad can walk (regions). One Dijkstra back from the goal's region gives the region route. A link between regions is priced at their center distance × the cheaper of their average terrain cost and the cheapest border crossing, so road crossings make cheap links and the route follows roads.
  2. Hex to hex. A* inside the blocks of that route plus a one-block margin, guessing straight-line distance.

  Routes come out within about 10% of a whole-map search. A long route (300+ hexes) on a medium map takes about 125 ms. The region graph is built once per travel profile (about 0.6–0.8 s on medium, the first time a profile is used). I tried steering the hex search with region costs to make it faster: it was 4× faster but routes were up to 28% worse and ignored roads, so I dropped it.
- **Movement** (§8.3). Each hex costs (1.0 / 0.6 / 0.3 s by speed tier) × 4.8 ticks × the hex's time multiplier. Squads keep partial progress between ticks, and the token slides smoothly between hexes. Casualty slowdown waits for units (M2).
- **Squad menu flow** (§5.3). Clicking a squad pauses the game (a hold) and opens its menu as a modal. Move closes the menu so the map can be clicked. The game stays held and the HUD says "Paused while planning". Left-click adds rally points (unreachable hexes are refused with a message), right-click removes the last, clicking the last point again commits, and Esc goes back to the menu. Closing the menu resumes play. The spec says the menu is a modal and also that you click the map from it; this keeps both.
- **Menu actions:** Move and Return to base work. Edit squad, Use item and Deploy are shown greyed out until M3. Ranged attack will appear for squads with range (M2).
- **Test squad.** One placeholder squad ("Vanguard", plains, speed tier 2, from `placeholder_squad` in `data/rules.json`) stands at the Player Base. T cycles its travel type (plains, forest, mountain, swamp, snow, desert, Sky, none) for testing. This all goes away when real squads arrive in M2.
- **Logged to Map:** move orders (with route length and time, and the route itself as a hidden value), rally points reached, destination reached.
