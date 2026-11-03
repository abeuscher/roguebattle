# Roadmap

Each session is small enough to finish, test and merge on its own (branch `session-NNN`). "Verify" is how the developer checks the work without the player. The player checks only at milestones (SPEC §23).

## M1: Map

Goal: a generated map the player can look at, and one squad they can move.

| # | Session | Spec | Verify | Status |
| --- | --- | --- | --- | --- |
| 1 | **Foundations and terrain.** Project, data pipeline and loader, hex math, seeded RNG streams, game log, map layers 1–3 for Continent, map preview tool | §1, §6.1–6.3, §9.1, §19.1, §20 | Tests (data, hex, RNG, log, mapgen determinism and terrain amounts); preview PNGs at all sizes; large map in under 5 s | Done |
| 2 | **All presets.** Islands, Archipelago, Floating Isles (air gaps, bridges), Highlands (cliffs, passes), River Valley (rivers, fords), Deep Forest, Tundra, Volcanic | §6.2–6.4 | Tests per preset (land %, presence of the preset's key features, reachability between landmasses where the preset promises it); a preview PNG per preset | Done |
| 3 | **Buildings, roads, bases.** Layers 4, 5 and 7: quadrant distribution, spacing, a building per terrain region, hidden sites, MST roads with loops, bridges and fords, bases on opposite sides. Lair sites (layer 6, placement only) | §6.5–6.7 | Tests: spacing, quadrant balance within one, no towns on mountains, roads connect every visible building, both bases reachable by ground; preview overlay PNGs | Done |
| 4 | **Battlemap view.** (Started early: chunked textured hex tiles and zoom/pan are in `ui/map_view.gd`.) Top-down with south-edge drops, Y-sorted objects (buildings, trees, mountains), grid toggle, camera pan and wide zoom, overlays (terrain, movement cost, roads, buildings per quadrant) | §5.1, §5.2, §19.2 overlays | Screenshots at several zoom levels on small and large maps, inspected; frame time on a large map | Done |
| 5 | **Clock, HUD, minimap.** Fixed-tick sim, pause (Space), five speeds (PgUp/PgDn), day and night, HUD (clock, speed, pause state, placeholder gold and reputation), minimap with click to jump, log viewer (L) with filters | §5.2, §5.3, §7, §19.1 | Tests: tick rate per speed, day boundaries; screenshot of HUD and log | Done |
| 6 | **Squad movement.** One placeholder squad with a fixed travel type and speed tier; hierarchical pathfinding (regions, then A*); terrain multipliers and roads; squad modal (pauses), rally points, commit by clicking the last point; movement logged | §5.3, §6.1, §8.3 (cost rules only), §20 | Tests: path cost rules, hierarchical path matches flat A* cost within tolerance, 100 random long routes on a medium map under a time budget; screenshot of a planned path | Done |
| 7 | **Configurator and flow.** Title, Start, Configurator (every map setting, seed and randomize, live minimap preview, victory and defeat toggles, squad cap, fairness toggle), share code, Game summary, into the battlemap | §4, §6.2, §6.8 (toggles only) | Tests: share code round-trips settings and seed; screenshots of each screen | Done |

**M1 milestone check:** the player spends five minutes generating and looking at maps and moving the squad.

## M2: Battle

| # | Session | Spec | Verify | Status |
| --- | --- | --- | --- | --- |
| 1 | **Units and squads.** Roll a unit (flex points, growth profile, luck, talent, alignment, name), squad rows, slots and Tiny sharing, travel-type vote, speed tier, casualty slowdown | §8.1–8.3, §9.2–9.3, §12.2 (rolls) | Tests: vote rules (Sky needs all flyers, ties go to leader, deep water rule), slot counting, no repeated names, rolls stay within flex range | Done |
| 2 | **Battle rules core.** Turn order, row attacks and counts, targeting (melee rows, reach, any row), damage formulas, hit and crit with the fairness rules, all modifiers in §11.5 | §11.3–11.5, §12.1 | Tests for each formula and modifier with fixed seeds | Done |
| 3 | **Traits, statuses, outcomes.** Statuses, buff duration, Raise dead, tactics, retreat, push-back, wipe-out, leader death march home, drive-off. Threat rating and pre-battle label | §9.7, §11.3–11.7, §12.4 | Tests per status and outcome; logged battles read correctly | Done |
| 4 | **Unit sheet v3.** Converter reads `units-landwar-v3.xlsx` (new line format, Traits, Leader aura, XP rate, Flyer and Amphibious lists from the Mechanics tab); the old `unit-table-final.xlsx` is deleted. Positions within rows. Group attacks (row, all, cleave 2, pierce, chain 3), Ward and Dispel. Battle traits and battle leader auras from the sheet, stage-4 auras ×1.5. Fixes: Charge = first attack ×1.5, amphibious units move freely on land | §9.1, §11.3–11.5, §21; sheet Mechanics tab | Tests per group attack, trait and aura; converter report clean; all 190 classes load |  |
| 5 | **Headless sim and balance metrics.** Command-line sim of N battles between two squads; win rate, average HP lost, time to rout | §12.4, §19.2 Simulation, §20 | Sim runs; an even stage-2 fight removes 35–50% HP per battle (tune data until it does) |  |
| 6 | **Enemy squads on the map and contact.** Static enemy squads placed at enemy buildings, adjacency triggers a battle, map pauses during battle, ranged map attacks with cooldown and high-ground range, sight radius and hidden enemies | §8.5, §11.1–11.2 | Tests: trigger rules, range rules, sight clamp 5–10 |  |
| 7 | **Battle view.** Two squads face off, actions animate in turn order, pause, tactic switch, retreat button, result screen; full battle log entries | §4 Battle, Battle result; §19.1 Battle | Screenshots mid-battle and of the result; log check against sim |  |

**M2 milestone check:** the player skims battle logs and watches a few battles.

## M3: Army

| # | Session | Spec | Verify |
| --- | --- | --- | --- |
| 1 | **Edit Units.** Army overview 4×4, recruit pool gutter, drag and drop, squad detail, items screen (minimal) | §4 Edit Units, §15.2 | Tests: moves respect slots and rows; screenshots |
| 2 | **Base and deployment.** Game opens on Edit Units, Player Base, deploy and return, squad cap, revive and heal at base | §4, §8.4, §6.5 Player Base | Tests: cap and deploy rules; screenshot |
| 3 | **Buildings and liberation.** Capture timer, Sapper speed, ground-only capture, building popup, defense and healing in buildings, nomad movement | §6.5 | Tests: capture timing, healing per day, nomad rules |
| 4 | **Economy and shops.** Income and upkeep at noon, liberation bonus, services, consumables, Serf purchase, going broke | §15.1, §16 Serfs | Tests: a scripted day's ledger matches hand-worked numbers |
| 5 | **Reputation, charisma, alignment.** All change events, price scaling, recruit chance factor | §9.5, §9.6, §10 | Tests per event |
| 6 | **Progression.** XP formula, level cost, growth, promotion and alignment branches, slot growth with charisma and banners | §8.2, §9.4 | Tests: XP and level math, promotion stat deltas, slot unlock rule |
| 7 | **Cards and tech.** All cards in battle and on map, card XP redirect, card draws; tech tree with tier gates and terrain nodes | §13, §14 | Tests: each card effect, tier gate at 80% of branch nodes |

**M3 milestone check:** a short play session.

## M4: Map 1

| # | Session | Spec | Verify |
| --- | --- | --- | --- |
| 1 | **Map 1 setup.** Roll 6 Serf-line squads with the coverage and soft rules, Opinion Leader, starting cards, tech and gold | §18 | Tests over many seeds: rules hold |
| 2 | **Enemy AI.** 10 squads with garrison, leader, base guard, raider and wildcard roles; weights from data | §12.3, §17 | Headless runs: roles behave (raider reaches a target, garrisons stay) |
| 3 | **Neutrals and recruiting.** Lairs, roamers, danger by distance, recruit or fight, race lines only from neutrals | §6.7, §16 | Tests: recruit chance formula; sim of roamer patrol |
| 4 | **Hidden mechanics.** Morale, loyalty, bonds, with their visible signs | §12.2 | Tests per rule; log messages appear |
| 5 | **Victory, defeat, end screen.** All victory options, defeat conditions, end-of-map summary and bonus | §6.8, §4 | Tests per condition |
| 6 | **Debug panel complete.** Every tool in §19.2; debug log toggle | §19.2, §19.1 | Each tool exercised; screenshot |

**M4 milestone check:** first real playtest.
