# Landwar — Build Spec (first build: Map 1)

Version 1.0 · 2026-11-02

A real-time squad strategy game in the spirit of Ogre Battle and Symphony of War: The Nephilim Saga. You build an army of squads, send them across a generated hex map, and battles resolve automatically when squads meet. There is no story; play starts within about 20 seconds.

**Companion files:**

- `data/units-landwar-v3.xlsx`: the full roster (190 classes) and the source of truth for class stats, attacks, traits and leader auras.
- `data/unit-names.csv`: first and last names for generated units.

Where this spec and the spreadsheet disagree, this spec wins (see §21).

---

## 1. Principles

1. **The loop comes first.** Building squads and moving them over terrain has to be fun before anything else is added.
2. **Terrain decides fights,** not just travel time. Flyers are strong but limited.
3. **Fair, not punishing.** Randomness is shaped so bad streaks are short. Hidden numbers always leave a visible sign.
4. **Content is data.** Units, cards, tech, items, AI weights and names live in data files. Changing a number never means changing code.
5. **Rules are separate from drawing.** All game rules run without graphics, so a headless sim and tests can use them, and the art can change freely.
6. **Everything is seeded and logged.** The same seed and the same orders give the same result. Every event goes to a log the player can read.

## 2. Scope

**In scope:** one complete map, played start to finish (map 1), with the configurator, battlemap, Edit Units, battles, buildings, economy, cards, tech, neutrals, recruiting, enemy AI, log and debug tools.

**Out of scope for now:** maps 2 and 3, the between-map army turn, the campaign layer, save/load mid-map (seed plus settings rebuilds a map), audio, tutorial, difficulty settings, magic items, final art.

## 3. Terminology

| Term | Meaning |
| --- | --- |
| Squad | A group of units that moves and fights as one token on the map |
| Leader | The unit heading a squad. Only classes with Can lead = Yes |
| Unit / soldier | One member of a squad |
| Opinion Leader | The army's main leader. Starts on the map; receives card XP; its death loses the map (toggle) |
| Slot | Squad capacity. Small unit = 1, Large = 2, Tiny = 0.5 |
| Line | A class's promotion path (for example Serf > Fighter > Soldier > Sentinel / Champion) |
| Travel type | The single terrain a squad moves through as native (§8.3) |
| Tick | One in-game minute. The base unit of time |

## 4. Screens

All menus that open over the map are modals with a 50% dark overlay. Opening any modal pauses the game.

| Screen | Contents |
| --- | --- |
| Title | Title art. Press Space |
| Start | Options, Start Game. Later: Start Campaign, Custom Game, Load, Save, Continue |
| Configurator | Every map generation setting (§6), seed with a randomize button, a live minimap preview, victory and defeat toggles, squad cap, fairness toggle |
| Game summary | Game type, map size, seed. Confirm to start |
| Edit Units: army overview | A 4×4 grid of up to 16 squad cards, numbered left to right, top to bottom. Each card shows the leader, unit icons, travel type, speed, slots used and capacity, and a badge on any unit ready to promote. A gutter on the right holds the unassigned recruit pool. Drag units between squads and the pool |
| Edit Units: squad detail | The squad's front and back rows on the left. The selected unit on the right: name, class, level, stats, alignment, charisma, items, promotion options |
| Edit Units: items | Equip the three slots (§15.2). Minimal for now |
| Tech | The tech tree (§14) |
| Battlemap | The main view (§5) |
| Building popup | Opens when a building is selected: owner, type, alignment effect, shop yes/no, hints |
| Shop | Opens when a squad stands in a building with a shop |
| Battle | The two squads face off; units animate their actions in turn order (§11). Pause any time; change tactic, retreat, play cards |
| Battle result | A short summary: losses, XP, push-back, status changes |
| Log | Opens with L. Filter by squad and category (§19.1) |
| Debug panel | Opens with backtick. Left out of release builds (§19.2) |
| Victory / defeat | End-of-map summary with gold, reputation and stats |

**The game opens on Edit Units.** After the summary screen, the player starts on Edit Units with their 6 rolled squads, 3 random cards and starting tech points, so they can plan before the first move.

## 5. Battlemap

### 5.1 Perspective

- **Top-down with drawn depth,** like Nephilim Saga's map. The ground is seen from nearly straight above.
- **Coastlines, cliffs and raised land** show a short drop on their south edge, so landmasses read as raised.
- **Objects** (buildings, trees, mountains, units) are drawn slightly from the front and sorted by screen Y, so lower things draw in front.
- **Flyers** float a little above the ground with a soft shadow.
- **Hex grid,** with grid lines hidden by default and a toggle to show them.
- **Placeholder art** is fine until after milestone M4.

### 5.2 Camera and HUD

- **Zoom.** Only the battlemap zooms. It needs a wide zoom range for large maps, and the minimap handles long-range navigation.
- **HUD:** minimap, clock with day and night, game speed, pause state, gold, reputation, and the squad number list. Layout (playtest round 7, 2026-11-10): gold and a reputation meter top right; the squads in a drawer at the middle left (number and leader icon, names when open); the clock and speed under the minimap at the bottom right; the toolbar at the bottom centre.

### 5.3 Controls

- **Selecting a squad** pauses the game and opens the squad menu: Edit squad, Use item, Move, Ranged attack (when it has range), Return to base, Deploy (at base).
- **Move.** Left-click hexes to lay rally points in order. The path is shown as you build it. Left-clicking the last point again commits the path, then closing the menu resumes play.
- **Planning while paused.** You can give orders to as many squads as you like while paused, one at a time. There is no multi-select.
- **Squad numbers.** Clicking a squad's number in the HUD, or pressing 1–9, centers the map on it.
- **Space** pauses and resumes.
- **PgUp / PgDn** step through five game speeds: ultra slow ×0.25, slow ×0.5, normal ×1, fast ×2, ultra fast ×4.
- **Esc** opens the main menu: save settings, options, return to title, quit.
- **L** opens the log. **Backtick** opens the debug panel.

## 6. Map generation

### 6.1 Grid and sizes

The map uses axial hex coordinates.

| Size | Hexes | Note |
| --- | --- | --- |
| Small | 400×225 | Default for map 1 |
| Medium | 800×450 | 360,000 hexes. A speed-2 squad crosses open plains in about 8 minutes |
| Large | 1200×675 | Generation takes a few seconds |
| Extra large (later) | 1920×1080 | Needs chunked generation; not in this build |

Render in chunks. Pathfinding must be hierarchical (region to region, then hex to hex) so long routes on medium and large maps stay fast.

### 6.2 Layers

The generator runs these layers in order. Each layer reads the ones before it.

| # | Layer | Settings | Default |
| --- | --- | --- | --- |
| 1 | Size | Small, Medium, Large | Small |
| 2 | Land shape | Preset map type, land %, island count and size | Continent |
| 3 | Terrain features | Amount of each terrain (none, low, medium, high) | Medium mix; desert and lava low |
| 4 | Buildings | Density, number of hidden sites | Medium |
| 5 | Roads | Coverage (none, main, full); chance of a road to a hidden site | Main; 25% |
| 6 | Neutrals | Density, danger, roamer aggression | Low |
| 7 | Bases and goal | Spawn side, victory conditions | Opposite sides; defeat the enemy leader |

Every map has a seed. The same settings plus the same seed always rebuild the same map. Settings plus seed can be copied as a short share code.

### 6.3 Terrain

| Terrain | Difficulty for non-natives | Notes | Native lines (see the sheet's Terrain column) |
| --- | --- | --- | --- |
| Plains | 1 | Default ground | Many |
| Forest | 2 | Cover; slows cavalry | Yes |
| Desert | 2 | Rare by default | Yes (few) |
| Snow and ice | 2 | | Yes |
| Mountain | 3 | High ground (+1 ranged range); towers can be built here, towns cannot | Yes |
| Swamp | 3 | No roads | Yes |
| Shallow water | 3 | Ground squads cross by boat, slowly and vulnerable | Water natives and amphibious units move at full speed |
| Deep water | Impassable | Crossed only by bridges, or by squads where every unit is a water native or amphibious | Yes |
| River | Deep or shallow | Bridges and fords mark the crossings | |
| Lava | Impassable for ground | Damages anything that stops on it. Rare by default | Yes (few) |
| Cliffs | Impassable | Create chokepoints; flyers ignore them | No |
| Air gap | Impassable | Space between floating landmasses; flyers only | No |
| Road and bridge | ×0.75 travel time | Ground squads only | |

### 6.4 Presets

| Preset | Shape | Favors | Punishes |
| --- | --- | --- | --- |
| Continent | One landmass, mixed terrain | Balanced armies | Nothing in particular |
| Islands | 2–4 large islands | Water natives, flyers | Ground-only armies |
| Archipelago | Many small islands, shallows between | Water natives, light units | Heavy, slow squads |
| Floating Isles | Landmasses split by air gaps, a few bridges | Flyers, bridge holders | Armies that can't hold chokepoints |
| Highlands | Mountain ranges, narrow passes | Mountain natives | Cavalry |
| River Valley | Rivers with bridges and fords | Whoever holds the crossings | Off-road squads |
| Deep Forest | Dense woods, few clearings | Forest natives | Cavalry, long-range archers |
| Tundra | Snow, ice, frozen lakes | Snow natives | Everyone else |
| Volcanic | Lava flows, ash plains | Squads that keep to roads | Squads that stop in the wrong place |
| No Ocean | All land, edge to edge (added 2026-11-10) | Ground armies | Water natives |

Land % runs 25–100 (changed 2026-11-10). Presets built on water cap it so they keep their sea (Islands and Floating Isles 70, Archipelago 60). Islands are joined by wide, winding shallows like reefs and sandbars, and a sizable island gets more than one where another landmass is near.

### 6.5 Buildings

| Building | What it does | Placement |
| --- | --- | --- |
| Player Base | Spawn point. Holds the recruit pool; deploy squads, revive, heal and spend tech here. Routed squads return here | Spawn side |
| Enemy Base | The enemy leader's home; the default victory target | Far side |
| Town | Liberate by moving a ground unit in. Some have a shop. Some give hints about nearby hidden sites | Plains, forest, snow, desert; never mountains |
| Tower | Home to evil residents. Can have a shop. Reputation runs opposite to towns | Any land, including mountains |
| Temple | Pay to heal or revive. Squads inside heal slowly for free, whatever their alignment. Taken like a town (changed 2026-11-11), but with no liberation rewards; the enemy takes them too, as a low priority. A temple you hold trains the squads resting in it and has a portal to every other temple you hold (below) | High ground or remote spots |
| Nomads | A town on the move: 4–6 hexes every half day. Each move has a 20% chance of staying hidden until the next half day. Always has a shop | Never on water, lava or mountains. 50% more likely to spawn along a road, 25% more likely far from other buildings |
| Hidden site | Treasure, a card, a secret temple, a rare recruit or a lair. Seen from afar, claimed by stepping onto it. Treasure, card and rare recruit are one-time and leave the map once claimed; a secret temple works as a temple; a lair is guarded by a neutral squad (Recruit or Fight, §16) and afterwards shelters squads like a town (changed 2026-11-11) | Off-road; revealed when a squad comes within sight |

**Distribution rules**

1. Split the map into four quadrants and spread towns, towers and temples roughly evenly, within one of each other. Placement inside a quadrant is random, which leaves clusters, gaps and open ground.
2. Minimum spacing between buildings is about 3 hexes.
3. Every sizable region of a terrain gets at least one building or lair.
4. The density setting scales the totals. Hidden sites have their own count.
5. Totals also scale with the map's land (changed 2026-11-10): the base counts are for the default map's land, and a map with more or less land gets proportionally more or fewer buildings, hidden sites and lairs.

**Who holds what at the start (changed 2026-11-10).** Every building except the two bases starts neutral. Both sides set out from their base to take buildings; a neutral town or tower taken by the player counts as a full liberation (bonus gold, reputation, alignment, a card), the same as one taken back from the enemy.

**Liberation and capture.** A squad with at least one ground unit that stays in a building for 60 ticks (placeholder) captures it. Sapper lines capture twice as fast. Only ground units can capture.

**Temples you hold** (user's answers, 2026-11-11). Taking a temple gives no bonus gold, reputation, alignment, card or conscripts, and losing one costs no reputation. *Portals:* a squad standing in a temple you hold can step at once to any other temple you hold (player only for now; no time in transit). *Training:* a squad resting in a temple you hold earns XP each day, more for lower-level units (placeholder: 30 ÷ the unit's level). A pantheon that gives temples more meaning is planned for later.

**Defense and rest in buildings**

| Building | Defense bonus | HP healed per day |
| --- | --- | --- |
| Temple | 5% | 5% (or pay for a full heal or revive) |
| Town or tower not matching the squad's alignment, or a middle-band squad | 10% | 10% |
| Town or tower matching the squad's alignment (town = holy, tower = evil) | 15% | 15% |
| Own Base | 15% | 15% |
| Lair (hidden site, once its guard is gone) | 10% | 10% |

Nomad camps count as towns.

### 6.6 Roads

1. Link all visible buildings, the spawn and the goal with a minimum spanning tree.
2. Add extra links for loops, according to the coverage setting.
3. Route each road along the cheapest path over the terrain, avoiding forest, swamp and mountains where possible.
4. Roads stop at deep water and lava. Rivers get bridges, or fords on rougher settings.
5. Each hidden site has a 25% chance (setting) of a road leading to it.

### 6.7 Neutral squads

- **Make-up.** 1–9 units, all of one class.
- **Lairs** sit in their natives' home terrain, away from roads and both bases.
- **Roamers** patrol a radius around their lair and attack anything that enters it.
- **Danger** (level and stage) rises with distance from the Player Base.
- Neutrals fight both the player and the enemy.
- Recruitment rules are in §16.

### 6.8 Victory and defeat

**Victory.** The default is defeating the enemy leader at the Enemy Base. Other options in the configurator, one or more:

- Reach the goal.
- Defeat N enemy squads, or all of them.
- Hold all towns, or N% of them, for T ticks.
- Survive until a timer runs out.

**Defeat.**

- The Opinion Leader dies (on by default, toggle).
- The Player Base is captured (assumption; see §22).
- Death by penury (playtest round 9): 3 noons running in debt, or debt past about 2 days' upkeep of a full field army (§15.1). Always on.

## 7. Time

- **Ticks and days.** 1 tick = 1 in-game minute; 1 day = 1,440 ticks.
- **Speed.** At normal speed a day lasts 5 real minutes, which is 4.8 ticks per real second. Game speed multiplies this rate.
- **Day and night.** Day runs 06:00–18:00 and night 18:00–06:00. Some effects can force day or night.
- **Scheduled events:**
  - Noon: income and upkeep.
  - Every half day: nomads move.
  - Daily: garrison reputation and building healing.
- **Battles pause the map clock.**

## 8. Squads

### 8.1 Rows

Each squad has a front row and a back row. A unit uses its Front attack and count in the front row, and its Back attack and count in the back row (from the sheet).

### 8.2 Slots and growth

- **Base.** Every squad starts with 5 slots (6 in single map mode, §18). Small = 1, Large = 2, Tiny = 0.5; any two Tiny units can share a slot.
- **Growth.** The leader earns +1 slot at level 5, 10, 15 and 20, but only if their charisma is at least 5 × their level at that moment:

| Slots | Leader level | Charisma needed |
| --- | --- | --- |
| 5 | Any | None |
| 6 | 5 | 25 |
| 7 | 10 | 50 |
| 8 | 15 | 75 |
| 9 | 20 | 100 |

- **Banners.** A Herald adds +1 and a Standard-Bearer +2 charisma toward this check only.
- **Expected pace.** Over a three-map run most leaders reach 7 slots. Nine slots is a long-campaign goal.

### 8.3 Travel type and movement

- **Travel type.** Each squad has one travel type, chosen by a weighted vote of its units' terrains. Small units count 1, the leader and large units count 2, tiny units count ½. The most weight wins, and ties go to the leader's terrain.
  - **Sky** can only win if every unit flies. Otherwise flyers' votes are dropped.
  - **Deep water** can only be crossed if every unit is a water native or amphibious.
- **Speed tier** is the slowest unit's tier. Time per hex at normal game speed: tier 1 = 1.0 s, tier 2 = 0.6 s, tier 3 = 0.3 s (×4.8 for ticks).
- **Terrain multiplier.** Difficulty 1 = ×1, 2 = ×1.5, 3 = ×2. The squad's travel type always counts as difficulty 1.
- **Roads** give ×0.75 for non-Sky squads. Sky squads move at ×1 everywhere.
- **Casualties.** A dead unit slows the squad by its share of the squad's slots. One of five slots lost = 20% slower.
- **Map-crossing auras** (Sea Lord, Airlift, Lava-walker, Tailwind) override these rules for their squad. They are deliberate exceptions and belong only to race-line leaders.

### 8.4 Deployment

- At the start, only the Opinion Leader's squad is on the map.
- Other squads deploy from the Player Base and can return there.
- A squad cap limits how many squads are on the map at once. It defaults to 6 (one per starting squad; changed 2026-11-10) and can be set in the configurator.

### 8.5 Visibility

- Terrain is always visible.
- Enemy and neutral squads are visible only within a hidden sight radius of one of your squads:

| Factor | Effect |
| --- | --- |
| Base | 7 hexes |
| Your squad flies | +2 |
| Your squad is on its travel-type terrain | +1, otherwise −1 |
| The target is in mountains | −2 |
| The target is in forest | −1 |

- The result is clamped to 5–10 and never shown as a number.
- **Buildings you hold see too** (playtest round 9): each reveals enemies within a radius by type, towers furthest, temples middle, towns least (placeholders 8, 6 and 4 hexes; the Player Base 4).
- Hidden sites reveal when they come within sight.

## 9. Units

### 9.1 Data

Read classes from the sheet: stage, lines, size, slots, can lead, alignment lean, terrain, speed tier, role, key stats, base stats, flex range, front and back attack and count, element, traits, leader aura, XP rate. Convert the sheet to data files the game loads (see KICKOFF.md).

### 9.2 Stats

- **Combat stats:** STR, CON (HP), INT, SPD (turn order), AGI (hit and dodge), PDEF, MDEF.
- **Per-unit values:** Alignment (0–100) and Charisma (0–100).
- **HP** = CON × 10 (placeholder).
- **Alignment bands:** evil 40 or below, neutral 41–59, holy 60 and up. A new unit rolls its alignment inside its class's lean.

### 9.3 Rolling a new unit

1. Start from the class's base stats.
2. Roll flex points (Flex min to max) and scatter them, weighted toward key stats.
3. Roll the hidden growth profile, luck and talent tier (§12.2).
4. Assign a name from `unit-names.csv`. First and last names combine independently, with no repeats in a run.

### 9.4 XP, levels and promotion

- **Who earns XP.** Every unit alive at the end of a battle earns XP = 40 × level ratio × charisma factor × talent bonus. A squad that retreated earns 0.25 of that (user's playtest notes, 2026-11-09).
  - **Level ratio:** enemy squad average level ÷ own squad average level, clamped 0.5–2.
  - **Charisma factor:** 0.5 + leader charisma ÷ 100.
  - **Talent bonus:** see §12.2.
  - **Catch-up** (2026-11-11): a unit below its squad's average level earns +25% per level under, at most double.
- **Level cost.** A level costs 100 XP × the class's XP rate (from the sheet).
- **Level-up.** Key stats +1 every level. Other stats follow the hidden growth profile (§12.2).
- **Promotion** is available at level 3 (stage 2), 6 (stage 3) and 9 (stage 4). It adds the difference between the new class's base stats and the old one's. Where the sheet shows an alignment branch (Witch, dragon colors), the bands decide which branch is available.
- **Card XP.** XP from card effects goes to the Opinion Leader's squad, not the fighting squad. Only the card-caused share is redirected.
- **Expected pace.** About 2.5 even battles per level. A stage 2 unit reaches stage 4 in about 15 battles, which is roughly 5 per squad per map across three medium maps.

### 9.5 Charisma changes

- Leader liberates a building matching their alignment: +5.
- Leader succeeds at a recruitment: +3.
- Each unit, after beating a stronger squad: +1.
- Each unit, after beating a much weaker squad: −1.
- Each unit, when its squad retreats: −1.

### 9.6 Alignment changes (each unit in the squad)

- Battle against an equal or stronger squad: +2.
- Battle against a weaker squad: −2.
- Liberating a town: +3. Liberating a tower: −3.

### 9.7 Skeletons (Raise dead)

Occultist and Necromancer lines can, once per battle, fill an empty slot with a Skeleton:

- Serf base stats, with three random stats each gaining +1d4.
- Dark element.
- Removed after the battle.

## 10. Reputation

- **Scale.** One army-wide meter, 0–100, starting at 50.
- **Squad alignment** = the average of its units' alignment, with the leader counted twice.

| Event | Holy squad (60+) | Evil squad (≤40) | Neutral squad |
| --- | --- | --- | --- |
| Liberates a town | +5 | −5 | 0 |
| Liberates a tower | −5 | +5 | 0 |
| Stays in a town, per day | +1 | −1 | 0 |
| Stays in a tower, per day | −1 | +1 | 0 |
| The enemy retakes a building of yours (round 9, 2026-11-11) | −3 | −3 | −3 |

- **Effects:**
  - Recruit chance ×(0.5 + reputation/100).
  - Liberation bonus and end-of-map bonus scale the same way.
  - Shop prices: −20% at 100, +20% at 0, linear between (placeholder).
- **Smuggler / Fence** lines double reputation swings and lower prices (from the sheet).

## 11. Battle

### 11.1 When battles happen

- A battle is always one player squad against one enemy or neutral squad. Squads never team up.
- **Triggers:** two hostile squads on adjacent hexes, or a ranged attack ordered from the squad menu.
- The map pauses and the battle view opens. The battle uses the defender's hex terrain.

### 11.2 Ranged attacks on the map

- A squad with Ranged (or ranged Magic) units can fire at an enemy squad 2 hexes away, or 3 from high ground (mountains, towers).
- Only ranged units act, and the target answers only with its own ranged units.
- No push-back. Cooldown of 120 ticks per squad (placeholder).
- A longbow adds +1 hex of range, and lets its archer fire from the back row at full damage in close battles.

### 11.3 Flow

1. **Turn order.** All units on both sides act in Speed order, highest first, using their row's attack count, until all attacks are spent. Traits such as First strike and Charge order apply. A neutral squad that resisted recruitment takes its whole first round before you.
2. **Targeting.**
   - Melee hits the front row first, and the back row only when the front is empty. Back-row Melee can hit the enemy front row.
   - Ranged and Magic can hit any row.
   - Melee (any row), (reach 2nd row), group attacks, Bulwark, Guard, Pounce and the other traits follow the sheet's Mechanics tab.
3. **Player controls during battle:**
   - Tactic, switchable any time: Best (each unit hits the target it hurts most), Strong (focus the strongest), Weak (focus the weakest), Leader (focus the leader).
   - Retreat.
   - Play any number of cards.
4. **Outcomes:**
   - **Wiped out:** the squad goes to the Player Base, with every unit needing revival.
   - **Leader dies:** the squad stays on the map but automatically marches home, at half speed and shown with a skull (round 9, 2026-11-11). Reviving the leader in time cancels the march.
   - **A unit dies:** the squad slows (§8.3).
   - **Otherwise:** the side that lost the larger share of its HP is pushed back 1 hex if the battle hex matches its travel type, or 2 hexes if not.
   - If the squads are still adjacent, another battle can follow.
5. **After the battle:** XP, charisma, alignment, morale, loyalty and bonds update, and all statuses clear.

### 11.4 Damage

- **Physical:** (STR + weapon) × modifiers − (PDEF + armor). Minimum 1.
- **Magic:** (INT + spell power) × modifiers − MDEF, then the element multiplier.
- **Breath:** based on STR + INT; ignores half of MDEF.
- **Healing:** based on INT.
- **Hit chance:** 85% + 1% per point of attacker AGI over target AGI, clamped 50–95%.
- **Crit:** base 5% (+0.5% per luck point), ×1.5 damage.
- **Front row:** front-row units take 20% less damage from every attack (added 2026-11-10 at the user's request: they died too often and too fast; the number is in data).
- **Damage spread:** ±10%.

### 11.5 Modifiers (multiply together)

| Modifier | Effect |
| --- | --- |
| Home terrain | +15% when the battle hex is the unit's home terrain; −15% on difficulty-3 terrain for it |
| Day and night | Holy units +15% by day, −15% at night. Evil units the reverse. Neutral units unaffected |
| Element | Pairs Fire/Ice, Water/Lightning, Earth/Wind, Holy/Dark. ×1.5 against the opposite element, ×0.75 against the same element (placeholder) |
| Anti-air | Archer lines ×1.5 against flyers. Falconer lines ×2 and ignore Bulwark |
| Mounted | Mounted ×1.5 against Mounted. Spear lines ×1.5 against Mounted |
| Giant-killer | Dragonslayer ×1.5 against Large units |
| Building | Defender's building defense bonus (§6.5) |
| Traits and auras | As in the sheet |
| Statuses | §11.7 |

### 11.6 Retreat and driving enemies off

- **Retreat chance:** 50% + 20% per speed tier your squad has over the enemy, clamped 10–90%.
  - **Success:** the battle ends, your squad steps back 1 hex, and each unit loses 1 charisma.
  - **Failure:** your squad loses its next action.
- **Driving enemies off:** at the end of a battle, if the losing enemy squad's morale is below 25, your leader can demand it flee. The chance is the leader's charisma %, halved if the enemy's morale is 10–25. On success the squad leaves the map for good, with no XP. Neutral squads use recruitment instead (§16). The demand is offered only when its chance is 25% or more; lower odds feel like zero to a player (playtest round 9).

### 11.7 Status effects

Every status clears at the end of the battle. Units native to an element's terrain resist the matching status (for example snow natives ignore Freeze and lava natives ignore Burn). Assign casters from the sheet by element and role. Cards are noted where they apply.

| Status | Effect |
| --- | --- |
| Poison | −5% max HP at the start of each of its turns |
| Burn | −5% max HP per turn and −10% physical damage |
| Freeze | Speed halved |
| Shock | 30% chance to lose each attack (Angelfish card) |
| Petrify | Can't act or be healed; takes half damage (Basilisk trait) |
| Sleep | Skips turns until hit |
| Charm | Attacks its own squad for one turn (Siren / Naiad debuff) |
| Blind | Hit chance −30% |
| Silence | Can't cast magic or heal |
| Fear | One fewer attack this battle |
| Weak (physical) | +25% physical damage taken (Mouse card) |
| Weak (magic) | +25% magic damage taken (Mink card) |
| Haste | Speed +50% (Cheetah card) |
| Protect | PDEF and MDEF +20% |
| Regen | Heals 5% max HP each turn |
| Cleanse | Removes all harmful statuses (Walrus card cleanses the squad) |

**Buff units:** Herald and Standard-Bearer raise PDEF; Quartermaster and Provisioner raise AGI; Sprite, Faerie and Faerie Queen raise MDEF.

**Buff duration:** a unit's buff lasts until that unit's next turn. A card's buff lasts for the rest of the battle (both rounds; changed at the user's request, 2026-11-10).

## 12. Fairness and hidden mechanics

Hidden numbers are never shown, but each leaves a sign the player can see.

### 12.1 Shaping randomness

These apply to both sides by default. A configurator toggle makes them player-only.

- **Two-dice hit roll.** The roll is the average of two d100 rolls against the shown chance.
- **Ramping crits.** Crit chance starts below its listed value, rises after each non-crit, and resets on a crit. Same average.
- **Streak breaker.** After 3 misses in a row by the same unit in a battle, its next attack hits.
- **Damage spread.** Only ±10%.

### 12.2 Hidden unit traits

| Trait | Rule | Visible sign |
| --- | --- | --- |
| Growth profile | Rolled at recruitment. Each non-key stat gets a hidden growth chance (20–50%). Every non-key stat grows at least once every 3 levels | Units diverge over time |
| Talent tier | Ordinary 80%; Gifted 15% (+15% XP, +10% growth chances); Prodigy 5% (+25% XP, +20% growth chances) | A Prodigy's level-up line gets a flourish |
| Luck | 0–20. Each point: +0.5% crit, +0.5% dodge, slightly better card draws, slightly better recruit rolls when leading | Lucky units feel lucky |
| Morale | Per squad, 0–100. Falls when outnumbered, the leader is hit, a unit dies, off home terrain, or fighting at the wrong time of day. Rises with wins, liberations, home terrain and temple rest. Below 30: −10% damage. Below 25: can be driven off (§11.6) | Leader portrait shifts from confident to shaken |
| Loyalty | Recruited neutrals only. Rises with wins and high reputation; falls when unused. Very low at day change: may leave, never mid-battle and never without a day's warning | Uneasy portrait for a day |
| Bonds | Two units that fight 6 battles in the same squad bond: +5% damage and +5% dodge while both live | A log message announces it |

### 12.3 AI and difficulty

- AI weights (target priority, retreat threshold, how roles value buildings versus squads) live in a data file.
- No dynamic difficulty. Difficulty settings come later.

### 12.4 Balance metrics (developer only)

| Metric | Target or use |
| --- | --- |
| Stat budget | Classes at the same stage have similar stat totals (the sheet's Stat total column) |
| Threat rating | One number per unit and squad, from stats, attacks per battle and stage. Scales enemies and neutrals, guides the AI, and drives a pre-battle label: Weaker, Even, Stronger or Dangerous |
| Time to rout | An even stage-2 fight routs the loser over 2–3 battles. One battle removes about 35–50% of the loser's HP |
| Simulated win rates | No squad build beats an evenly rated alternative more than 60% of the time |

## 13. Cards

- **Start:** 3 random cards.
- **Earning:** draw 1 card per building liberated or card site claimed (§6.5). Seer lines choose from 2 cards and Oracle lines from 3; the Foresight aura previews the next card.
- **Limits:** none on cards held or played per battle.
- **Rarity:** each card has a draw weight (1 unless rarer); Phoenix is rare (playtest round 9).
- **XP:** card-caused XP goes to the Opinion Leader's squad.

| Group | Card | Effect |
| --- | --- | --- |
| Stat boost | Panther | +STR |
| Stat boost | Elephant | +CON |
| Stat boost | Owl | +INT |
| Stat boost | Cheetah | +SPD |
| Stat boost | Raccoon | +AGI |
| Stat boost | Turtle | +PDEF |
| Stat boost | Hippo | +MDEF |
| Heal | Dolphin | +50 HP to all your units |
| Heal | Whale | All your units healed to full |
| Heal | Narwhal | A temporary healer joins behind your squad at its average level and casts heal-all twice |
| Heal | Walrus | Cleanses all debuffs from your squad |
| Heal | Phoenix (rare) | Every fallen unit in your squad comes back with half its max HP |
| Attack | Tiger | Physical attack on the whole enemy squad |
| Attack | Crocodile | Water magic attack |
| Attack | Rhino | Earth magic attack |
| Attack | Condor | Wind attack |
| Attack | Angelfish | Lightning attack |
| Attack | Mouse | Enemy weak to physical |
| Attack | Mink | Enemy weak to magic |
| Environment | Rooster | Time jumps to noon |
| Environment | Fox | Time jumps to midnight |
| Environment | Chameleon | This battle plays as if on the attackers' home terrain; the map doesn't change |
| Environment | Sloth | The enemy loses a turn |
| Environment | Unicorn | Your squad gets an extra turn |

Rooster and Fox can be played on the map. All other cards are played in battle.

## 14. Tech tree

- **Structure.** Army-wide, four tiers. A tier opens when at least 80% of the previous tier's **branch** nodes are bought. Terrain nodes don't count toward the gate.
- **Costs.** Nodes cost the tier number in points.
- **Starting points:** 3. Points are earned from liberations, battle wins and finishing a map (placeholders).
- **Where to spend:** the Tech screen, any time.

| Branch | Tier 1 | Tier 2 | Tier 3 | Tier 4 |
| --- | --- | --- | --- | --- |
| Arms | Shield Wall: +10% front-row defense | Steelworking: steel armor in shops | Drill: stage 3+ melee units +1 attack | Veterans: +10% HP for stage 4 units |
| Archery | Longbow Training: longbows in shops | Skyhunters: anti-air bonus +0.5 | Volley: archers split shots across 2 targets | Deadeye: higher bow crit |
| Arcana | Field Medicine: squads heal a little after each battle | Elemental Focus: +element damage | Mage Regiments: casters don't slow their squad | Archmagi: casters gain a spell |
| Cavalry | Barding: +defense for mounted units | Charge: cavalry strike first attacking on plains | Outriders: +1 sight for cavalry | Lance Rush: Charge on any non-hostile terrain |
| Beasts and flyers | Aerial Scouts: +1 sight for flyers | Tamers: better recruit chance for large units | Pack Bond: large units +defense when two share a squad | Sky Lords: flyers ignore weather |
| Logistics | Engineers: bigger road bonus | Quartermaster: −10% upkeep | Diplomacy: better recruit chance for all neutrals | War Chest: +10% town income |

**Terrain nodes.** One node per terrain per tier (9 per tier). Each raises the attack and defense of units native to that terrain by +1 at tier 1, +2 at tier 2, +3 at tier 3 and +4 at tier 4.

## 15. Economy and items

### 15.1 Gold

All values are placeholders.

| Flow | Rule |
| --- | --- |
| Starting gold | 2 days' upkeep of a full field army (the squad cap of full squads) on this map, at least 500 (round 10, 2026-11-11) |
| Town and tower income | 50 gold per day each, at noon |
| Liberation bonus | 100 × (0.5 + reputation/100), once per liberation |
| Upkeep | Per unit per day at noon, for squads on the map only; units in the recruit pool and squads at base cost nothing. Stage 1 = 5, stage 2 = 10, stage 3 = 20, stage 4 = 35. Large ×2, Tiny ×0.5. Then × the map's towns and towers ÷ a reference count (a Small map's, 28), so cost follows what the map can pay: holding half a map's towns and towers covers a full field army at stage 2 with room to spare (round 10, 2026-11-11). Deploying a squad costs one day of its upkeep |
| End-of-map bonus | Scaled by reputation, like the liberation bonus |
| Going broke | At zero gold, the player can pull a squad back to base for gold equal to its total value. Tune so this gives room to recover rather than prolonging a loss |
| Services | Cure one status 10, heal a unit to full 20, revive 50 × stage |
| Debt | Gold can go below zero at noon (playtest round 9). Nothing can be bought while in debt; the HUD and the noon ledger count the noons. 3 noons running in debt, or debt past about 2 days' upkeep of a full field army, is a defeat (§6.8). Selling a squad stays the way out |
| Consumables | Herb (+30 HP) 15; Revival Draught (revive a fallen unit anywhere on the map) 80; one cure potion per status, used in battle (Antidote for poison, and so on) 10–20. Shops hold limited stock, refilled at noon (user's playtest notes, 2026-11-08) |

### 15.2 Items

- **Slots.** Each unit has three: weapon, armor and jewelry.
- **Armor:** Bronze, Iron, Steel give PDEF +2 / +4 / +6.
- **Melee weapons:** Dagger, Sword, Club, Mace. One version each; any melee class can use any of them.
- **Bows:** Bow, Longbow (§11.2). Archer classes only.
- **Enchanted weapons:** any weapon plus an element, adding element damage (for example Sword of Fire = +2 physical, +1 fire).
- **Jewelry:** Necklace (HP), Ring (INT), Earring (AGI), Bracelet (PDEF).
- **Shops vary** (playtest round 9): each shop stocks a random number of item kinds and a random count of each, and about one shop per map holds one very rare item with a big buff, not restocked once sold.
- **Kept minimal** until magic items exist. Later work leans on Nephilim's item handling with simple D&D-style rules.

## 16. Recruiting

- **Serfs** are bought at towns with shops (placeholder: 50 gold).
- **Neutral squads.** When your squad meets one, you're told the class but not the count, and choose Recruit or Fight.
  - **Chance** = 0.60 × (10 − units)/9 × (1 − alignment gap/100) × (0.5 + reputation/100). The alignment gap is between the neutrals and your squad's alignment, with the leader counted twice.
  - **Success:** the units go to the recruit pool at the Player Base, and the leader gains +3 charisma.
  - **Failure:** the neutrals take their whole first round before you, then normal rules apply.
  - **A second chance** (playtest round 9): after any battle the player wins against neutrals without wiping them out, Recruit or Let them go is offered once more. They join at the HP they have left; a refusal or Let them go sends them home. Otherwise a neutral squad still goes home after its one battle.
- **Race lines** (the sheet's R, N, L and T lines) come only from neutrals, hidden sites and recruiter traits. They never appear in starting squads.

## 17. Enemy

Changed 2026-11-10 (the user's "even start"): the enemy fields half as many squads as the map has towns (at least 3), and every one starts on the Enemy Base.

| Squads | Role | Behavior |
| --- | --- | --- |
| 1 | Leader | Holds the Enemy Base |
| 1 | Base guard | Holds the Enemy Base with the leader |
| The rest | Field | March out to take towns and towers, then weigh holding against moving on |

- **Field squads' choice.** On a town or tower the enemy doesn't hold, a field squad stays until it's taken. Otherwise it scores holding where it is against moving to each neutral or player-held town or tower that no other enemy squad is after:
  - A building's value: towns above towers, more toward the middle of the map between the two bases, double if the player holds it.
  - Holding: the value, raised by player strength nearby, and nothing if another enemy squad already holds it.
  - Moving: the target's value, lowered with distance.
  - It makes the higher-scoring choice 80% of the time and flips a coin between holding and the best move the other 20%. A squad that holds thinks again a few hours later.
- **Going home.** A squad that has lost half its units or more goes home to the Enemy Base, the only place enemy units revive.
- **Revival at the Enemy Base is slow** (changed 2026-11-10, so the player can wear the leader down and then beat it): a squad standing there brings back one fallen unit, leader first, at full HP every 2 game hours (in data), and stays until all are back if it came home to revive. Living units don't heal there at all.
- **Make-up.** Enemy squads have 4 units and no healers.
- **Scaling.** Strength comes from the threat rating and the map's difficulty band.
- **Weights.** AI weights come from data (§12.3).

## 18. Map 1 setup

- **6 player squads,** each a stage 3 leader plus four stage 2 units, rolled from Serf lines only.
- **Single map mode** (user's design, 2026-11-10; a configurator Game mode beside this campaign start, which stays the three-map plan). The Opinion Leader starts alone in squad 1 on the map; the other 29 units start in the recruit pool: stage 3 leaders up to the squads-on-the-map cap + 1 in all (user's notes, 2026-11-11; every Serf-line terrain covered before repeats), 3 stage 1 Large race-line units (an exception to the race-line rule below), 10 Serfs, and stage 2 units for the rest of the 30 (at least 4 front-line and 4 healer or support, each capped at half of them). Squads have 6 base slots. A squad needs a leader to deploy, so leaders set how many squads take the field. The squads-on-the-map default follows map size (6/8/10). An XP rate setting (default 150%, 100–300%) multiplies battle XP in this mode only. Numbers in `rules.json` "single_map".
- **Terrain coverage.** Across the 6, each Serf-reachable terrain (Plains, Forest, Swamp, Mountain, Desert) is at least one squad's travel type.
- **Soft rule.** Each squad has at least one front-line unit and one healer or support unit. Everything else is random.
- **Starting state:**
  - One squad is the Opinion Leader's, and only it starts on the map, at the Player Base.
  - 3 random cards, 3 tech points, 500 gold.
  - A starting kit (2026-11-10): 6 random items that need no tech, 5 Revival Draughts and 20 Herbs.
  - The squad cap defaults to 6, one per starting squad (still set in the configurator).
- **Enemy:** half as many squads as towns, all at the Enemy Base, with the roles in §17.
- **Neutrals and hidden sites** per configurator settings.
- **Default size:** Small.

## 19. Log, debug and names

### 19.1 Game log

- One log for everything, opened in-game with L.
- Filterable by squad and category, and written to a file each session.
- Plain-language by default, with no hidden numbers. A debug toggle shows hidden values (growth, luck, morale, loyalty, AI targets).

| Category | Records |
| --- | --- |
| Battle | Every action: attacker, target, shown hit chance, roll, damage, each modifier, statuses, outcome, push-back |
| Map | Orders and paths, arrivals, liberations, recruit attempts with chance, nomad moves, enemy role changes |
| Economy | Income, upkeep, bonuses, purchases, squads sold when broke |
| Progression | Level-ups with stat gains, promotions, slot unlocks, charisma, alignment, reputation and bond changes |
| System | Seed, settings, game speed changes |

### 19.2 Debug panel (backtick)

| Area | Tools |
| --- | --- |
| Map | Reveal all enemies and hidden sites; regenerate from a seed; overlays (hex grid, terrain, movement cost, roads, buildings per quadrant, lair danger, sight radius) |
| Time | Set time of day; skip N hours; freeze the clock |
| Units | Build a squad unit by unit (class and level from dropdowns, remove any unit, see the squad as it grows) and place it at the cursor for the player, the enemy or neutrals; set a squad's alignment; teleport a squad; heal or revive all; remove a squad |
| Resources | Add gold, tech points or any card |
| Battle | Force win, loss or draw; replay the last battle with the same rolls; show hidden numbers; toggle each fairness rule |
| AI | Show each enemy squad's role and target; freeze enemy AI |
| Simulation | Run N headless battles between two chosen squads; report win rate and average HP lost |

### 19.3 Names

First and last names come from `data/unit-names.csv`, mixed independently, with no repeats in a run. Names appear on Edit Units, in the log, and in level-up and bond messages.

## 20. Technical approach

- **Engine.** Godot 4 and GDScript, for PC with mouse and keyboard. Target 1920×1080, scaled to other screens. Use the documentation for the Godot version actually installed.
- **Rules are plain classes** with no dependency on scene nodes: map generation, movement, battle, progression, economy, AI. Scenes only display state and pass on input.
- **Fixed-tick simulation** in ticks. Game speed changes the tick rate; rendering interpolates.
- **Seeded RNG.** One seeded generator per system (map, battle, recruitment, loot) derived from the game seed, so systems don't disturb each other's sequences.
- **Data.** A tool script converts the spreadsheet to JSON in `data/`. The game reads only the JSON. Re-run the tool whenever the sheet changes.
- **Hex map.** Axial coordinates, chunked rendering, and hierarchical pathfinding (region graph, then A* within regions).
- **Scenes built mostly in code,** with small `.tscn` files, so changes stay readable in diffs.
- **Tests and sim.** Automated tests run headless and cover battle math, map generation validity (reachability, building rules, road connectivity), pathfinding, and travel-type voting. A headless battle sim runs from the command line.

## 21. Reconciled with unit sheet v3

The sheet is the source of truth for classes. These values override it:

| Topic | Value used |
| --- | --- |
| Home terrain | +15% home, −15% on difficulty-3 terrain |
| Day and night | By alignment band for every unit; neutral unaffected |
| Amphibious | Full speed on land, shallow and deep water |
| Supply (Quartermaster lines) | 2% max HP per in-game hour |
| Harass aura | Lasts 60 ticks |
| Sapper lines | Capture towns and towers ×2 faster (no forts) |
| Seer, Oracle, Foresight | Work on the animal cards |
| Flyers | One flyer type |
| Back-row melee | Can reach the enemy front row |
| Tiny sharing | Any two Tiny units share a slot |
| Pack | Bonus capped at +2 |
| Map-crossing auras | Kept as exceptions (§8.3) |
| Sheet "open questions" | Answered by this spec (slowest-member speed, leader death, slot curve, terrain costs) |

## 22. Placeholders and assumptions

All numbers marked placeholder are for tuning after milestone M4. Assumptions the developer should flag if they cause problems:

- Losing the Player Base is a defeat condition.
- Capture time of 60 ticks.
- HP = CON × 10.
- Element multipliers ×1.5 / ×0.75.
- Ranged cooldown of 120 ticks.
- Serf price of 50 gold.
- Shop price swing of ±20% by reputation.

## 23. Milestones

The player tests only at milestones. Between them, the developer checks its own work with tests, sim runs and screenshots.

| Milestone | Delivers | Player check |
| --- | --- | --- |
| M1: Map | Data pipeline, configurator, map generation (all layers), battlemap with zoom, minimap and overlays, one squad following a rally-point path, game speed and pause, log | 5-minute look at generated maps |
| M2: Battle | Squads, travel type, enemy squads on the map, contact and ranged battles, battle view, full battle log, headless sim | Skim battle logs; watch a few battles |
| M3: Army | Edit Units, deployment, buildings, liberation, economy, shops, cards, tech, reputation, progression | Short session |
| M4: Map 1 | Full map 1: 6 squads, enemy AI roles, neutrals and recruiting, hidden mechanics, victory and defeat, debug panel complete | First real playtest |

After each real playtest the player notes: what felt good, what dragged, what confused, and one change.
