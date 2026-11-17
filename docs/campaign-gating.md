# Landwar: unit grouping and campaign gating

(The user's proposal, 2026-11-17, kept as written. For the campaign sessions; nothing here is implemented yet.)

A proposal for making the 190-unit roster digestible by introducing it across several campaigns. Written for the campaign coding session. Nothing here is implemented yet, and the tier and pack placements are suggestions for Al to adjust.

## Core idea

Gate by **promotion line**, not by unit. The roster is 190 units but only 61 lines, and a player learns a line once. Each campaign declares which lines exist in it. Everything else is hidden from that campaign entirely: not recruitable, not promotable into, not fielded by the enemy, and not shown in the glossary.

## Proposed data changes

The units spreadsheet is the game's data source, so the coding agent should make and commit these changes itself.

Add five columns to the `Units` sheet. Every unit in a line gets the same values:

| Column | Values | Meaning |
|---|---|---|
| `Tier` | 0 to 4 | How much the line asks the player to understand (see below) |
| `Pack` | Plains, Forest, Mountain, Snow, Water, Swamp, Desert, Sky, Lava | Thematic pack. Same as the existing `Terrain` value of the line's stage 3 unit |
| `Side` | holy, evil, any | Which side of a pack the line belongs to, from `Alignment lean` |
| `Role group` | tank, striker, ranged, healer, caster, support | Six groups collapsing the 30-odd `Role` values, for UI filters |
| `Movement` | foot, mounted, flyer, swimmer | For UI filters and for gating by map type |

Units shared by two lines (Serf, the stage 2 classes, Tadpole, Wolf, Bobcat, Cuttlefish, War Bird, Drakeling) take the lowest tier of the lines they lead to, and are available if any of those lines is.

Add a per-campaign definition (format up to the coding agent) with:

- `tier_cap`: highest tier the player can recruit or promote into.
- `packs`: packs present in the campaign.
- `player_lines` / `enemy_lines`: optional explicit lists that override tier and pack, for lines that are enemy-only or player-only.
- `unlocks`: which lines each map offers on victory.

## Tiers: grouping by difficulty

| Tier | Teaches | Lines |
|---|---|---|
| 0 Core | Front row, back row, healing | Soldier, Swordfighter, Archer, Lancer, Cleric, Mage |
| 1 Counters | "This beats that" | Spearman, Crossbowman, Rogue, Skirmisher, Horse Archer, Scout, Enchantress, Spellbreaker, Falconer, Centaur |
| 2 Alignment | Holy and evil, day and night | Knight, Berserker, Shade, Ronin, Valkyrie, Witch, Occultist, and the seven folk lines (Elf, Troll, Gnome, Goblin, Wisp, Frog, Toad) |
| 3 Map and economy | Effects outside battle | Herald, Sapper, Quartermaster, Smuggler, Seer, Tamer |
| 4 Bodies and movement | 2-slot Large units, Tiny swarms, flyers, swimmers | All Large and Tiny lines, plus Angel, Imp, Eagle Rider, Mermaid, Sprite, Gustling. Dragons should come last within this tier |

Notes:

- Tier 0 is about 20 units and is enough for a first map.
- Falconer's anti-air is meaningless until flyers exist, so only offer it in a campaign that has them.
- Tamer is the gateway to Large beasts. Offer it just before the first Tier 4 unlock.

## Role, body and movement: grouping by type

Three filters for the Edit Units screen and the glossary, each derivable from the sheet:

- **Role group:** tank, striker, ranged, healer, caster, support.
- **Body:** Small, Large, Tiny (the existing `Size` column).
- **Movement:** foot, mounted, flyer, swimmer.

## Packs: grouping by theme

Most creatures are already paired by terrain and alignment, which gives each terrain a player side and an enemy side.

| Pack | Holy or neutral side | Evil side |
|---|---|---|
| Plains | Core humans, Centaur | Berserker, Occultist, Wisp line |
| Forest | Ronin, Falconer, Scout, Skirmisher, Rogue, Tamer, War Cat | Shade, Shadow Cat, Vampire Bats |
| Mountain | Sapper, Gnome, Arctic Wolf, Lion, Goat, Golem | Goblin, Hellhound, Bison |
| Snow | Elf, Sasquatch | Troll, Snow Serpent |
| Water | Frog, Octopus, Mermaid, Sea Dragon | Toad, Kraken |
| Swamp | Witch, Smuggler, Rats | (none; Witch branches by alignment) |
| Desert | Angel, Seer, Gustling | (none) |
| Sky | Gryphon, Eagle Rider, Sprite, Roc | Dragons by colour |
| Lava | Basilisk | Demon |

The packs are uneven. By unit count: Plains 52, Mountain 34, Forest 25, Sky 20, Water 20, Snow 15, Swamp 9, Desert 8, Lava 7. Swamp and Desert have no evil side of their own, so maps there need enemies borrowed from a neighbouring pack.

## Making the roster digestible in the game

- **Enemy first.** The player meets a new line by fighting it, then is offered it.
- **One unlock per map.** Winning a map offers one line from that map's pack, chosen from two or three. This caps a run at roughly 15 to 18 of the 61 lines and gives roguelike variety between runs.
- **Glossary shows only lines the player has met**, with blanks for the unseen stages of a line.
- **Promotion tree shows only branches unlocked in the current campaign.**
- **Later campaigns widen the whitelist** rather than starting from everything.

## Campaigns

### A. The elemental campaign (Al's plan, 12 maps plus a finale)

Twelve maps of differing terrain, each with an elemental boss who grants an artifact, then a final map against the demon classes.

- Start with Tier 0 only.
- Each map uses its terrain's pack. The evil side and the boss are the enemy.
- Winning offers one line from the pack's friendly side.
- The Demon line is enemy-only and unseen until the final map. Imps could appear as scouts a few maps earlier.
- Hidden entirely: packs whose terrain isn't used, and Tier 3 lines if the campaign has no shops or Tarot.

Open question: the sheet has 9 terrains and 8 elements (Fire, Ice, Water, Wind, Earth, Lightning, Holy, Dark). Twelve maps means some terrains repeat with a different element, or three bosses need new ground.

### B. The Beastmaster's Road (about 6 maps): teaches Large units

- **Premise:** a Tamer-led company travels terrain to terrain, taming one beast family per map.
- **Player unlocks:** Tamer first, then one choice per map: cats in Forest, wolves or lions in Mountain, Gryphon or Roc in Sky.
- **Enemy:** wild beasts of the same terrain, with rats as an early nuisance, ending with a coloured dragon as the final hunt.
- **Counters offered before the finale:** Spearman line (for Dragonslayer) and Falconer.
- **Teaches:** 2-slot units and the squad-size trade-off, Tiny swarms, flyers.
- **Hidden:** all casters beyond Cleric and Mage, and every folk line.

### C. Tides (about 4 maps): teaches movement

- **Premise:** an island chain where most of the map is water, swamp or sky.
- **Player unlocks:** Sapper (bridges), Mermaid, Frog, Octopus, Eagle Rider.
- **Enemy:** Toad, Kraken, Sea Dragon, ending with a Leviathan.
- **Teaches:** swimmers, flyers and bridging, so the map itself is the puzzle.
- **Hidden:** all cavalry and every Mountain, Snow and Lava line.

### D. The Caravan (3 maps): teaches the economy

- **Premise:** escort a caravan across the desert, with shops, reputation and Tarot at the centre.
- **Player unlocks:** Smuggler, Quartermaster, Herald, Seer.
- **Enemy:** raiders drawn from Tier 0 and Tier 1 humans, with a Djinn (Gustling line) as the boss.
- **Teaches:** the Tier 3 lines, which the other campaigns leave unused.
- **Hidden:** all Large and Tiny lines.

Together the four campaigns cover the tiers: elemental for the broad roster and alignment, Beastmaster for Large units, Tides for movement, Caravan for economy.

## Appendix: all 61 lines with proposed values

Line IDs match the `Line(s)` column in the sheet.

| Line | Promotion path | Tier | Pack | Side | Role group | Body | Movement |
|---|---|---|---|---|---|---|---|
| 1 | Serf > Fighter > Soldier > Sentinel / Champion | 0 | Plains | any | tank | Small | foot |
| 2 | Serf > Fighter > Spearman > Centurion / Dragonslayer | 1 | Plains | any | tank | Small | foot |
| 3 | Serf > Fighter > Knight > Paladin | 2 | Plains | holy | tank | Small | foot |
| 4 | Serf > Fighter > Berserker > Reaver | 2 | Plains | evil | striker | Small | foot |
| 5 | Serf > Fighter > Tamer > Beastlord | 3 | Forest | any | striker | Small | foot |
| 6 | Serf > Squire > Lancer > Dragoon | 0 | Plains | any | striker | Small | mounted |
| 7 | Serf > Squire > Horse Archer > Scythian | 1 | Plains | any | ranged | Small | mounted |
| 8 | Serf > Squire > Scout > Hussar | 1 | Forest | any | striker | Small | mounted |
| 9 | Serf > Bowman > Archer > Warbow | 0 | Plains | any | ranged | Small | foot |
| 10 | Serf > Bowman > Crossbowman > Arbalest | 1 | Plains | any | ranged | Small | foot |
| 11 | Serf > Bowman > Rogue > Assassin | 1 | Forest | any | striker | Small | foot |
| 12 | Serf > Bowman > Shade > Nightblade | 2 | Forest | evil | striker | Small | foot |
| 13 | Serf > Slinger > Swordfighter > Swordmaster | 0 | Plains | any | striker | Small | foot |
| 14 | Serf > Slinger > Skirmisher > Ranger | 1 | Forest | any | striker | Small | foot |
| 15 | Serf > Slinger > Ronin > Kensei | 2 | Forest | holy | striker | Small | foot |
| 16 | Serf > Acolyte > Cleric > Templar | 0 | Plains | holy | healer | Small | foot |
| 17 | Serf > Acolyte > Valkyrie > Warsinger | 2 | Plains | holy | healer | Small | mounted |
| 18 | Serf > Acolyte > Witch > Wicked Witch / Fairy Godmother | 2 | Swamp | any | caster | Small | foot |
| 19 | Serf > Apprentice > Mage > Fire Mage / Wind Mage / Earth Mage / Lightning Mage | 0 | Plains | any | caster | Small | foot |
| 20 | Serf > Apprentice > Occultist > Necromancer | 2 | Plains | evil | caster | Small | foot |
| 21 | Serf > Apprentice > Enchantress > Sorceress | 1 | Plains | any | caster | Small | foot |
| 22 | Serf > Slinger > Spellbreaker > Witch Hunter | 1 | Plains | any | caster | Small | foot |
| 23 | Serf > Bowman > Falconer > Hawkmaster | 1 | Forest | any | ranged | Small | foot |
| 24 | Serf > Squire > Herald > Standard-Bearer | 3 | Plains | any | support | Small | mounted |
| 25 | Serf > Fighter > Sapper > Siege Engineer | 3 | Mountain | any | support | Small | foot |
| 26 | Serf > Acolyte > Quartermaster > Provisioner | 3 | Plains | any | support | Small | foot |
| 27 | Serf > Slinger > Smuggler > Fence | 3 | Swamp | any | striker | Small | foot |
| 28 | Serf > Apprentice > Seer > Oracle | 3 | Desert | any | caster | Small | foot |
| R1 | Centaur > Spiritaur > Deitaur | 1 | Plains | any | healer | Small | mounted |
| R2 | Angel > Archangel > Seraphim | 4 | Desert | holy | healer | Small | flyer |
| R3 | Imp > Demon > Archdemon | 4 | Lava | evil | caster | Small | flyer |
| R4 | Eagle Rider > Eagle Knight > Eagle Lord | 4 | Sky | any | striker | Small | flyer |
| R5 | Mermaid > Siren > Naiad | 4 | Water | any | striker | Small | swimmer |
| R6 | Sprite > Faerie > Faerie Queen | 4 | Sky | any | support | Small | flyer |
| R7 | Gustling > Zephyr > Djinn | 4 | Desert | any | caster | Small | flyer |
| N1 | Elfling > Elf Squire > Elf > Royal Elf | 2 | Snow | holy | ranged | Small | foot |
| N2 | Trollkin > Trollboy > Troll > Big Troll | 2 | Snow | evil | striker | Small | foot |
| N3 | Gnomeboy > Gnome > Master Gnome > Mountaineer | 2 | Mountain | holy | striker | Small | foot |
| N4 | Goblin > Nobgoblin > Hobgoblin > Bobgoblin | 2 | Mountain | evil | striker | Small | foot |
| N5 | Wisp > Ghost > Spectre > Banshee | 2 | Plains | evil | striker | Small | foot |
| N6 | Tadpole > Frog > Frog Boy > Frog Man | 2 | Water | holy | striker | Small | swimmer |
| N7 | Tadpole > Toad > Toad Boy > Toad Shaman | 2 | Water | evil | striker | Small | swimmer |
| L1 | Drakeling > Wyrm > Dragon > Red Dragon / Blue Dragon / Silver Dragon / Black Dragon | 4 | Sky | any | striker | Large | flyer |
| L2 | Drakeling > Serpent > Sea Dragon > Leviathan | 4 | Water | any | striker | Large | swimmer |
| L3 | Drakeling > Snow Snake > Snow Serpent > Kuraokami | 4 | Snow | evil | striker | Large | foot |
| L4 | Wolf > Ember Wolf > Hellhound > Hellmaw | 4 | Mountain | evil | striker | Large | foot |
| L5 | Wolf > Wolfhound > Arctic Wolf > Winter Wolf | 4 | Mountain | holy | striker | Large | foot |
| L6 | Bobcat > Hell Cat > Shadow Cat > Sabretooth | 4 | Forest | evil | striker | Large | foot |
| L7 | Bobcat > Prowler > War Cat > White Tiger | 4 | Forest | holy | striker | Large | foot |
| L8 | Cuttlefish > Octopus > Battle Octopus > Octolord | 4 | Water | holy | tank | Large | swimmer |
| L9 | Cuttlefish > Kraken > Electro Kraken > Abyssal Kraken | 4 | Water | evil | tank | Large | swimmer |
| L10 | War Bird > Gryphon > Royal Gryphon > Sphinx | 4 | Sky | holy | striker | Large | flyer |
| L11 | War Bird > Stormhawk > Roc > Storm Roc | 4 | Sky | any | striker | Large | flyer |
| L12 | Bigfoot > Yeti > Sasquatch > Abominable | 4 | Snow | holy | tank | Large | foot |
| L13 | Goat > Battle Goat > Battle Ram > Chupacabra | 4 | Mountain | any | striker | Large | foot |
| L14 | Bison > Battle Bison > Battle Buffalo > Earthshaker | 4 | Mountain | evil | striker | Large | foot |
| L15 | Lion Cub > Lion > Pride Lion > Golden Lion | 4 | Mountain | holy | striker | Large | foot |
| L16 | Salamander > Cinder Lizard > Magma Lizard > Basilisk | 4 | Lava | any | striker | Large | foot |
| L17 | Mudling > Stoneguard > Monolith > Colossus | 4 | Mountain | any | tank | Large | foot |
| T1 | Rat > Giant Rat > Rat Pack > Rat King | 4 | Swamp | any | striker | Tiny | foot |
| T2 | Bat > Bat Swarm > Vampire Bats > Night Terror | 4 | Forest | evil | striker | Tiny | flyer |
