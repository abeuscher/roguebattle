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

## Open data issues (from session 001; items 1, 2 and the class names in 6 are settled by v3, see "After session 010")

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
- **Squad menu flow** (§5.3). Clicking a squad pauses the game (a hold) and opens its menu as a modal. Move closes the menu so the map can be clicked. The game stays held and the HUD says "Paused". Left-click adds rally points (unreachable hexes are refused with a message), right-click removes the last, clicking the last point again commits and resumes play right away (user request; the menu doesn't reopen), and Esc goes back to the menu. Closing the menu also resumes play. The spec says the menu is a modal and also that you click the map from it; this keeps both.
- **Menu actions:** Move and Return to base work. Edit squad, Use item and Deploy are shown greyed out until M3. Ranged attack will appear for squads with range (M2).
- **Test squad.** One placeholder squad ("Vanguard", from `placeholder_squad` in `data/rules.json`) stands at the Player Base. T cycles its travel type for testing. Since session 008 its units are rolled (Knight, two Fighters, Bowman, Acolyte); the Map 1 setup (M4 session 1) replaces it.
- **Logged to Map:** move orders (with route length and time, and the route itself as a hidden value), rally points reached, destination reached.

## Session 007 (2026-11-02)

- **Screen flow:** Title (Space) → Start (Start Game; Options greyed out until there are options) → Configurator → Game summary → Battlemap. After M3 the game opens on Edit Units before the battlemap (§4). Start shows only what exists; campaign, custom game, load, save and continue come later.
- **Configurator fields** live in `data/configurator.json`. On/off fields are check boxes; every other field is a slider over its options with a readout on the right (user request), and the screen is built from that list. Sections are collapsible; Size, Land shape and Terrain start open. Map size shows its hex dimensions. Screens' main way forward (Start Game, Next, Start) uses `UiStyle.ACTION`; other buttons are outlined. Map fields feed `MapGen`; game fields (victory, defeat, squad cap, fairness) go to `GameState.settings` for M2–M4 to use. Choosing a map type resets land %, offshore islands and terrain amounts to that type's values.
- **Settings the spec lists that the generator doesn't use yet:** neutral danger and roamer aggression (M4), plus the victory and defeat toggles, squad cap and fairness. They're saved and passed on.
- **"Island count and size" (§6.2)** sets Continent's offshore islands. Islands and Floating Isles still pick their own 2–4 / 3–5 large islands. The user is fine with this until playtesting.
- **Share code:** a version, the seed and every field's option index, bit-packed and written in 32 symbols (no I, L, O, U), in dash-separated groups of four: about 28 characters. Fields must only ever be added at the end of `configurator.json`, or old codes break (the version number guards against that).
- **Live preview** generates on a worker thread, so the screen stays responsive. A large map takes about 12 s while the screen keeps drawing at about 57 fps. If the settings haven't changed, the battlemap reuses the previewed map instead of generating it again.
- **Esc menu** (§5.3): Resume, Save settings, Options (greyed out), Return to title, Quit. It pauses play. "Save settings" stores the share code in `user://settings.json`; the configurator starts from it next time, seed included.
- **Removed** the R / P / S test keys. The configurator does their job.

## Session 008 (2026-11-03): units and squads

- **Rolling a unit** (§9.3, §12.2): base stats, then flex points (Flex min–max) scattered with key stats weighted ×3 (`unit_roll.flex_key_weight`). Growth chance 20–50% per non-key stat, talent 80/15/5, luck 0–20. Talent's "+10% growth chances" is read as +10 percentage points, applied at level-up (M3).
- **Starting charisma** isn't in the spec. Placeholder: rolled 5–15 (`unit_roll.charisma`), low enough that slot growth at level 5 (needs 25) must be earned.
- **Alignment leans** roll inside the bands: Evil 0–40, Neutral 41–59, Holy 60–100, Any 0–100. "By alignment" and "Varies by color" roll as Any.
- **Names**: first and last names are drawn independently from the CSV's distinct values; a full name is never reused within a run (`NameBook`, one per game).
- **Slots**: Small 1, Large 2, Tiny units share slots in pairs (an odd one takes a whole slot). Dead units keep their slots until revived. The first unit able to lead becomes the leader. A leader's earned slots stay with them. Banner bonuses come from `slot_growth.banners`, waiting for Herald and Standard-Bearer to reach the sheet.
- **Travel-type vote** uses living units. Sheet terrains map to terrain keys in `travel_types` (Water → shallow). If every unit is Water, the type becomes `deep`: shallow and deep water both cost ×1 (`native_as` / `natives_cross` in `terrain.json`). The sheet marks the frog and lizard lines "Amphibious", but they are all Water natives, so no separate amphibious rule is needed yet. If the leader flies, a tie goes to the first tied terrain in squad order. Lava natives still can't cross lava (Lava-walker is an aura, §8.3).
- **Casualty slowdown**: time per hex × (1 + dead units' slots ÷ the squad's slot capacity). One of five slots lost = ×1.2.
- **Squad menu** lists the squad's units by row, with level and HP, until Edit Units arrives (M3).

## Session 009 (2026-11-03): battle rules core

- **Battle numbers** live in `data/battle.json`: hit and crit, spread, breath and heal shares, terrain, day/night, element and matchup multipliers.
- **Turn order** (§11.3): rounds. Each round every living unit with attacks left acts once, highest Speed first; equal Speed is settled by a seeded random draw made at the start of the battle. A side that resisted recruitment goes first in round one. The battle ends when all attacks are spent or one side is down.
- **Targeting** (§11.3): plain Melee hits the front row, the back row only once the front is empty (from either row). Ranged, Magic, Breath, "Melee (any row)" and "Melee (reach 2nd row)" hit any row until the Mechanics tab defines reach and group attacks. Breath is single-target for now.
- **Tactics** are in already (targeting needs one): Best = most expected damage (ties: lowest HP), Strong = highest stat total (threat rating replaces it in session 3), Weak = lowest HP, Leader = the leader if reachable, else Best. Both sides default to Best.
- **Damage** (§11.4): weapons, armor and spell power count as 0 until items (M3). Breath = (STR + INT) × 0.5 × modifiers − MDEF × 0.5. Healing = INT ± spread, given to the ally missing the largest share of HP. Element multipliers apply to Magic and Breath only, as §11.4 writes them. Building defense multiplies damage taken by (1 − bonus); which bonus applies arrives with buildings (M3).
- **Hit chance**: 85% + AGI difference, minus 0.5% per target luck point (§12.2 dodge), then clamped 50–95%. Heals never miss.
- **Fairer dice** (§12.1): two-dice average for hits, a guaranteed hit after 3 misses in a row, and ramping crits using a pseudo-random distribution (chance C × n on the n-th try since the last crit, C chosen so the average is the listed chance). With the configurator's "Player only" setting, the enemy rolls plain dice.
- **Home terrain**: matches the battle hex's terrain or what it counts as (frozen lake = snow; any water = home for Water units). Difficulty-3 terrain gives −15% to non-natives. Flyers (Sky) get neither.
- **Matchup tags** (archer, mounted, spear, flyer, large, falconer, dragonslayer) are by role, class, sheet terrain or size in `battle.json`, since the sheet has no such columns. Mounted = Cavalry, Mounted archer, Mounted healer and Sky rider roles plus Valkyrie and Muse; spear = Spearman and Centurion; flyer = Sky terrain (so Angels and Imps, "low flyers" on other terrains, don't count). Falconer and Dragonslayer wait for the sheet.
- **Buff and Debuff** actions just wait until statuses arrive (session 3).
- **Balance check**: with placeholder data an even stage 2–3 fight costs each side about 12–16% of its HP, short of the 35–50% target. Session 5 tunes the data with the sim.

## Session 010 (2026-11-03): statuses, traits, outcomes

- **Battles step one turn at a time** (`Battle.step()`), so the battle view (session 7) can animate them and the player can retreat between turns. `run()` plays to the end; `finish()` clears statuses, removes Skeletons and reports the outcome; `GameState.end_battle()` applies it on the map.
- **Statuses** (§11.7) are data in `battle.json`. Harmful ones last the battle; Charm lasts the charmed unit's next turn; Sleep lasts until hit. Poison, Burn and Regen tick at the start of the unit's own turn, and Poison and Burn can kill. Blind takes 30% off after the 50–95% clamp, so it bites. Silence blocks Magic, Heal, Buff and Debuff actions (not Breath). A unit can't get a status it already has.
- **Who causes statuses** (§11.7, "assign casters from the sheet by element and role"): hits from Fire units can Burn, Ice can Freeze, Lightning can Shock and Dark can Poison, with a 20% chance per hit (placeholder). Siren and Naiad Charm; Basilisk Petrifies (not in the sheet yet). Water and Holy have no status. Snow natives resist Freeze and lava natives resist Burn. The Debuffers (Enchantress, Sorceress: "weakens enemies") give Weak (physical), preferring targets that don't have it yet.
- **Buffs**: Buffer units (Faerie, Pixie, Sylph) raise the whole squad's MDEF by 20% until the buffer's next turn. Herald, Standard-Bearer, Quartermaster, Provisioner and Sprite are mapped too, waiting for the sheet.
- **Traits**: the sheet has no Traits column, so only First strike and Charge ordering exist. First strike acts first in round one; Charge does too, but only for the side that started the battle. Charge comes from the sheet's Notes ("Charge"/"Charger": Lancer, Dragoon and the bison line) via `class_traits` in `battle.json` until the column exists.
- **Raise dead** (§9.7) is free at the start of the raiser's turn, once per battle, when the squad has a slot not used by a living unit. The Occultist and Necromancer classes aren't in the sheet yet.
- **Retreat** (§11.6) compares squad speed tiers (higher = faster). A failed retreat makes the squad's next turn, by whichever unit, a lost action.
- **Outcomes** (§11.3): the side that lost the larger share of its starting HP is pushed back (no push on a tie, a wipe-out or a retreat). Push-back steps away from the enemy's hex, into hexes the squad can enter that no other squad holds, and stops early if it can't get further away. Flyers count as on their travel terrain (1 hex). A wiped-out enemy squad leaves the map. A squad that loses its leader is ordered to its own base and flagged `marching_home`.
- **Drive-off** is a GameState call (`drive_off_chance`, `drive_off`); the battle-result screen (session 7) offers it. Squads start at morale 50 (`starting_morale`); what moves morale arrives in M4.
- **Threat rating** (§12.4) = stat total × (1 + 0.5 per attack beyond the first) × (1 + 0.1 per stage above 1) × HP share. Pre-battle label from the enemy:own ratio: below 0.8 Weaker, below 1.25 Even, below 1.75 Stronger, else Dangerous. The Strong tactic now targets the highest threat.
- **After-battle updates** (§11.3.5): only statuses clear for now. XP, charisma, alignment, morale, loyalty and bonds arrive with M3 and M4.

## After session 010: unit sheet v3 (2026-11-03)

The user added `data/units-landwar-v3.xlsx` (190 classes, Traits, Leader aura, XP rate and Formerly columns, plus Mechanics and Change log tabs). It answers open data issues 1, 2 and the class-name part of 6. Recorded for M2 session 4 (new), which switches to it:

- **The old `unit-table-final.xlsx` gets deleted** when the converter moves to v3, so only one unit sheet remains (user request).
- **Spec over sheet** where they differ (§21): buffs last until the buffer's next turn (sheet: the battle); Supply heals 2% max HP per in-game hour (sheet: per second); Harass lasts 60 ticks (sheet: 10 s); day and night apply to every unit by alignment band (sheet lists six units). Buff sizes follow the sheet (+10%) unless the spec gives a number.
- **Corrections to sessions 008–010:** Charge is "first attack ×1.5", not acting first; acting first in round 1 comes from First strike (Ronin, Kensei) and the Charge order aura. Amphibious units (frog and toad lines) move freely on land and water. Flyers are the sheet's Flyer list (including Angels, Imps and Sprites), not just Sky-terrain classes.
- **Positions within a row** (agreed with the user): each row is ordered left to right. A back-row unit is "behind" the front-row unit in the same position; a Large unit takes one position. Bulwark, Guard, Pushback, pierce and cleave use this, and Edit Units (M3) will let the player arrange it.
- **Debuff stats** (agreed): Enchantress and Sorceress lower STR, Seer and Oracle lower AGI, lion roar (Debuff row) lowers front-row STR, each −10% (sheet placeholder). Siren and Naiad charm.
- **Elemental statuses** (agreed): only Magic and Breath attacks, which carry the element, can cause Burn (Fire), Freeze (Ice), Shock (Lightning) or Poison (Dark). Other statuses come from named units (Siren, Naiad, Basilisk) and cards.
- **Still open: §18 coverage.** v3 adds Serf-line leaders on Mountain (Sapper) and Desert (Seer), but every Serf-line stage 2 unit is Plains, so four stage 2 units (weight 4) always outvote a stage 3 leader (weight 2). Not needed until M4 session 1; raise it then.

## Session 011 (2026-11-03): unit sheet v3

- **One sheet.** The converter reads `data/units-landwar-v3.xlsx`; `unit-table-final.xlsx` is deleted. It reports 0 problems. Traits become names ("Mounted: x1.5 ..." becomes "Mounted"; a lower-case part after ";" continues the previous trait). Leader aura becomes a name plus `leader_aura_text`. The Mechanics tab is exported to `data/mechanics.json`; the game reads its Flyer and Amphibious lists from there.
- **Numbers the game uses** for traits and auras are in `data/battle.json`, copied from the sheet's Mechanics tab and aura text (all placeholders there). Map-only auras (Harass, Pathfinder, Night march, Spotter, Siegecraft, Supply line, Sanctuary, Contacts, Foresight, Airlift, Sea lord, Lava-walker, Tailwind, Marsh step, Mirage, Stalk, Plunder) are listed but do nothing until their systems arrive. So are the map traits Pathfinder, Bridge, Supply, Black market, Banner (already used for slot growth) and Foresight.
- **Positions**: `Unit.col`, filled left to right per row by `Squad.add`; `Squad.across(u)` is the unit behind (or in front). A dead unit keeps its position. Pushback swaps a front unit with the one behind it (or moves it back if nobody is there).
- **Group attacks**: (row) hits every living unit in the chosen target's row; (all) the whole squad; (cleave 2) the target and the nearest living unit beside it; (pierce) the target and the unit behind it; (chain 3) the target and two more random enemies at −25% and −50%. Each target gets its own hit roll. Row and pierce follow normal reach rules for the first target. Heal (row) heals the row of the most hurt ally. Debuff (row) (lion roar) hits the enemy front row, or the back row once the front is empty.
- **Ward** gives the squad −30% magic damage taken until the warder acts again. **Dispel** is a magic hit that cancels the target's next Magic, Heal or Buff action.
- **Bulwark** applies to Melee and Ranged single-target choices and to the first target of group attacks; magic and breath ignore it. **Guard** redirects single-target hits only.
- **Damage classes**: Melee and Ranged are physical; Magic, Dispel and Breath count as magic for Ward, Stoneskin, Wardsong and Null field.
- **Charge** is first attack ×1.5; it lasts the unit's whole first attack, including every target of a group attack. **Riposte** counters at 50% damage with its own hit roll and can't be countered. **Mirage** makes the first hit that would land on the Djinn miss. **Regenerate** (5%) and the **Regrowth** aura (3%) heal at the start of each round. **Nullify** stops enemy Magic and Dispel actions in round 1. **Petrify** (Basilisk breath, 25%) and Charm last one turn.
- **Pack and Swarm** count other wolves (the wolf, ember wolf and wolfhound lines) or Tiny units in the squad, capped at +2. **Tamer** gives Large beasts (roles Beast, Breath beast) +1 attack in the front row.
- **Leader auras** work while the leader lives; stage 4 leaders get percentage effects ×1.5 (attack bonuses stay +1). Round-one extra attacks (Volley, Stampede) are a second turn at the end of round 1. Grave pact raises the side's first fallen non-Skeleton unit in its position. Remount heals mounted units 10% when the battle finishes. Fortify needs the squad to be standing still.
- **Flyers** are the Mechanics-tab Flyer list. Sky travel needs every unit to fly; flyers don't vote otherwise. Flyers skip the difficulty-3 penalty but still get their home-terrain bonus (Angels on desert). **Amphibious** squads (all units amphibious) move at ×1 on every passable terrain and deep water; water natives with amphibians get the deep-water travel type.
- **Balance check with v3 data**: the even stage 2–3 fight from session 009 now costs about 11% and 17% of HP. Session 5 tunes it.

## Session 012 (2026-11-03): battle sim and balance

- **Sim**: `rules/battle_sim.gd` (plain rules) and `tools/battle_sim.gd` (command line); builds in `data/sim_builds.json`, Map 1 style (a stage 3 leader and four stage 2 Serf-line units). Each trial rolls both squads fresh and fights with no healing between battles until one is routed: wiped out, or its leader dead (it marches home, §11.3). Ten battles without a rout is a draw. Who attacks alternates between trials. A battle takes about 6 ms; `all` with 100 trials takes about 1.5 minutes.
- **Tuning** (both placeholders, §22): `hp_per_con` 10 → 3 and `heal_int_share` 1.0 → 0.3. Damage (STR − PDEF) is small next to CON × 10 HP; with ×10 no squad was routed within 10 battles. Healing is cut by the same factor so it keeps its share against the smaller HP. Result over all 55 pairs: the loser loses 49% of its HP in the first battle (target 35–50%) and is routed in 2.7 battles (target 2–3). An even pair (vanguard vs shieldwall) goes 50/48 with the loser losing 38%.
- **Threat rating, revised**: offense (damage per battle against the average stage-2 unit, from STR or INT, attack count and group size; healing and support count) × durability (HP ÷ an average hit, half physical and half magic), summed per squad as total offense × total durability. The first version (stat total × attacks × stage) rated every sample pairing within 0.94–1.05 and couldn't tell builds apart. The new one picks the winner in 39 of 52 clear-cut pairs. Group weights and the support share are in `battle.json` (`threat`). The Strong tactic uses the unit version (√(offense × durability)).
- **Not met: "no build beats an evenly rated alternative more than 60%"** (§12.4). Fights are close to deterministic: fair dice, ±10% spread and similar rolled squads turn a small edge into 90–100% wins. Average win rates of the sample builds: lancers 82%, casters 75%, vanguard 75%, shieldwall 69%, spears 64%, archers 56%, berserkers 49%, ronin 28%, witches 24%, clerics 18%, skirmish 5%. Some of this is class stats in the sheet (Rogue: CON 9, PDEF 4; the Rogue skirmish build loses even with the Rogue in the back row), some is how the sample builds are put together. Class balance belongs in the sheet; re-run the sim after sheet changes. The threat rating now flags most of these gaps (skirmish vs vanguard rates 2.6), so the label warns the player.

## Session 013 (2026-11-03): enemy squads and contact

- **Enemy squads** (§17): `data/enemy.json` lists the roles in placement order (leader on the Enemy Base; base guard and raider on the nearest free hexes beside it; four garrisons and three wildcards on separate towns and towers, shuffled with the "enemy" RNG stream) and seven 4-unit builds without healers (a stage 3 Serf-line leader and three stage 2 units), picked at random. Every town and tower counts as enemy-held until liberation arrives (M3). They stand still until the AI (M4); scaling by threat and difficulty band comes then too. Enemy squads are numbered from 101 so player numbers stay 1–9.
- **Sides**: `Squad.side` is "player", "enemy" or "neutral". Only player and non-player squads are hostile; enemies and neutrals never fight each other (battles are always one player squad against one other, §11.1).
- **Contact** (§11.1): after each tick's moves, a player squad on or next to a hostile squad starts a battle (`GameState.pending`); the map holds until it's resolved. The squad that entered a new hex this tick attacks; if neither moved, the player squad attacks. Both squads' orders stop. Contact counts even if the enemy isn't visible. A pair that just fought waits 30 ticks (`contact_cooldown_ticks`, placeholder) before fighting again, so a battle without push-back doesn't repeat every tick; after that, still-adjacent squads fight again (§11.3). Until the battle view (session 7), the battlemap resolves the battle at once and shows a one-line result.
- **No stacking**: a moving squad waits at the edge of a hex another squad holds.
- **Ranged map attacks** (§11.2): a squad can fire if a living unit's current attack is Ranged or Magic. Range 2, or 3 standing on mountains or a tower. Targets must be visible and hostile. Only Ranged and Magic units on both sides act (the target answers with its own), with no push-back, and the firing squad reloads for 120 ticks. Numbers in `rules.json` (`ranged_attack`). Longbows (+1) wait for items.
- **Sight** (§8.5) is computed per player squad and target hex from `rules.json` (`sight`), clamped 5–10 and never shown. Enemy tokens draw only when some player squad sees them; clicking one shows its role, unit count and the threat label against your first squad.
- **Hidden sites and lairs** now start hidden on the map and appear once a player squad sees them (logged). H still shows them all for debugging. Lairs reveal the same way, since they're places on the map like hidden sites.


## Session 014 (2026-11-03): battle view and readable battle log

- **Battle log wording**: every action names the unit with its class ("Galad Traemane (Knight)"), says what kind of attack it was (strikes, shoots, blasts, breathes on, dispels, curses), and ends with the target's HP left or "falls". Rounds are marked ("-- Round 2 --") and each line is tagged with the acting squad ("[Vanguard]"). §19.1's hidden numbers (hit chance, roll, each damage multiplier that isn't ×1) go in the entry's hidden values, shown with the log's debug toggle. A roll of 0 means the streak breaker forced the hit.
- **Battle view** (§4): a modal over the map, which holds the clock. Each squad's back row is on the outside and the front rows face each other, with units stacked by position. Each card shows class, name, attack and count, an HP bar and statuses; the leader has a gold frame. Attacks lunge toward the target with a floating number (yellow with "!" for a crit, "miss" on a miss); heals float green, statuses purple. A running log sits under the field. Pacing is in `battle.json` (`view`: 0.6 s per action, ×1/×2/×4).
- **Controls**: Pause (Space), speed, tactic (applies from the next action), Retreat with its chance shown (takes effect between actions; disabled in ranged attacks), Skip to end. Cards (§11.3) wait for M3.
- **Result panel** (§4 Battle result): the outcome as a headline, HP lost and the fallen on each side, a lost leader, push-back, then Continue. XP waits for M3; statuses clear silently. The drive-off offer (§11.6) shows when the enemy lost the larger share of its HP, isn't wiped out and its morale is below 25. Morale doesn't move yet (M4), so in practice it doesn't show yet.
- **Ranged map attacks** open the battle view too (§11.1 lists them as a trigger): `GameState.fire` leaves the battle pending like contact does.

## Session 015 (2026-11-03): Edit Units, army and items

- **Army** (`rules/army.gd`): 16 numbered cells (squad number = cell + 1, `army_size` in rules.json), the recruit pool and the item stash. Until Map 1 setup (M4) the army comes from `rules.json` (`placeholder_army`): three squads, four recruits and a few items. Only the first squad starts on the map, at the Player Base (§8.4); the others wait at base until deployment (next session).
- **Moves**: drag a unit onto a squad card (row picked from its attacks: back for units that heal, support or attack at range from the back row; front otherwise), onto a slot in the squad detail (that row and position), or onto the pool. Dropping onto a unit swaps the two (between squads, or within one). A move that puts any squad over its slots is refused with a message and changes nothing. Dropping into an empty cell forms "Squad N". A squad emptied of units leaves the grid (and the map).
- **Leaders**: when the leader leaves, the best unit left that can lead takes over (living, then highest level, then highest stage). "Make leader" switches leader if the unit can lead and the squad still fits. A squad may have no leader in the grid (shown in red); deploying it will need one (next session).
- **Where edits happen**: squads at base, or standing still on the Player Base. Squads out in the field show "In the field" and are locked.
- **Items** (§15.2, `data/items.json`, all placeholders): every item is a stat bonus (weapons add STR, which is the "+ weapon" in §11.4's damage; armor PDEF; Necklace +2 CON for HP; Ring INT; Earring AGI; Bracelet PDEF). Melee weapons need a Melee attack in either row; bows need the archer tag; armor and jewelry fit anyone. Battle stats, HP and the threat rating include items. Equipping extra HP heals that much; removing it caps HP. A longbow adds +1 to ranged map attacks (§11.2). Enchanted weapons wait for shops (M3 session 4).
- **Items screen** (§4, kept in Edit Units rather than a separate screen): the gutter has Recruits and Items tabs. Items lists every item the army owns, one entry each, grouped by slot with free ones first; worn ones are greyed and say who has them (click to go to that unit). Drag a free item onto a unit (any view) or onto a slot box in the unit panel; units and slots that can't take it dim during the drag. Drag a worn item to another unit to move it, or back to the Items tab (or ×) to take it off.
- **Not yet**: the promotion badge and promotion choices (M3 session 6; the panel lists the next classes), renaming squads, deploy and return (next session).
- Opened with U on the battlemap.
- **Squad names** (not in the spec; the user's interim choice): a player squad is named after its leader's first name and class, "Demandred (Knight)", shown after its number ("#1 Demandred (Knight)") and wherever squads are named (HUD, battles, log). The name follows the leader when it changes; a squad without a leader is "Squad N". Enemy squads keep their role names. Editable names may come later.
- **Fix**: a unit dragged to the recruit pool was dropped from the army instead of joining the pool.

## Session 016 (2026-11-03): Player Base and deployment

- **The game opens on the map**, not Edit Units (user's change to §4). A toolbar at the bottom of the battlemap has Edit Units (U) and Deploy Squad (D). Only the first squad starts on the map (§8.4, §18).
- **Deploy** (user's design): Deploy Squad lists the squads at base with their cost; picking one (or pressing Deploy on a squad in Edit Units, which switches to the map) starts laying its route with the move tool, from the hex it will appear on. Clicking the last point again asks "Deploy [squad] for [cost] gold?"; Deploy pays and sets it off along the route, Cancel goes back to the route, Esc while laying it leaves the squad at base. It needs a living leader, room under the squad cap (configurator, default 5) and the gold. The squad appears on the Player Base, or the nearest free hex if another squad holds it.
- **Deploy cost** (not in the spec; user's choice): one day of the squad's upkeep from §15.1 (stage 1/2/3/4 = 5/10/20/35 gold per unit, Large ×2, Tiny ×½; `rules.json` `upkeep`), e.g. 60 gold for a stage-3 leader and four stage-2 units. Daily upkeep itself comes with the economy (session 4).
- **Return**: a squad standing on the Player Base goes in at once (Return in Edit Units, or Return to base in the squad menu). From anywhere else, Return to base marches it home and it goes in on arrival; any new move order cancels that. If another squad holds the base hex, arriving next to it counts. A squad whose leader fell marches home and goes in the same way. A wiped-out squad is carried straight into the base, off the map.
- **Services at base** (§15.1, `rules.json` `services`): heal a unit to full for 20 gold, revive a fallen unit for 50 × stage, with buttons in the unit panel and "Heal and revive all" in the squad detail. Revive restores full HP. Only for units at base (squads off the map, and the recruit pool); squads must go in first. Free healing over time at base (15% per day, §6.5) comes with building rest next session.
- **Squad menu**: Edit squad opens Edit Units on that squad when it's at the Player Base. The old placeholder Deploy button is gone, since deploying happens from base in Edit Units.
