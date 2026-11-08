# Landwar — Rules, as implemented

This describes how the game actually plays right now, not the full design (that's `SPEC.md`). It's written for a player, not a developer. Almost every number below is a placeholder for balance purposes (per `SPEC.md` §22) and will change; what's described as a *mechanic* is the stable part.

**Keep this current.** Whenever a session adds, changes or finishes a game rule, update the relevant section here (or add one) in the same session. The "Not yet in the game" section at the bottom is the checklist — move an item out of it once it's real, instead of leaving this file stale.

---

## Starting a map

- **Title → Start → Configurator → Game summary → the map.** The configurator sets every map-generation option (size, land shape, terrain amounts, building density, road coverage, neutral density, victory/defeat toggles, squad cap, a fairness toggle), with a seed you can randomize and a live minimap preview. Settings plus seed can be copied as a short share code and reproduce the exact same map.
- **Map sizes:** Small (400×225 hexes, the default), Medium, Large.
- **Map 1's setup** (the only map that exists so far) always gives you 6 starting squads, the Opinion Leader on the map, 3 random cards, 3 tech points and 500 gold — see "Your starting army" below.
- The game opens on the battlemap with your one deployed squad standing on the Player Base.

## The map

- **Hex grid**, axial coordinates, rendered in chunks for performance on large maps.
- **Terrain and difficulty for a squad not native to it:** Plains 1, Forest/Desert/Snow 2, Mountain/Swamp 3, Shallow water 3, Deep water/Lava/Cliffs/Air gaps impassable to ground squads. A squad's own travel-type terrain always counts as difficulty 1 for it, whatever the listed difficulty is. Every landmass is guaranteed reachable on foot from the rest of the map (a shallow ford, a mountain pass, a bridge, or similar), even if slow.
- **Map presets** (Continent, Islands, Archipelago, Floating Isles, Highlands, River Valley, Deep Forest, Tundra, Volcanic) change the terrain mix and favor different squad types; Continent is the default and most balanced.
- **Buildings:** Player Base and Enemy Base (spawn points), towns and towers (liberate by standing a living ground unit in one for 60 ticks — twice as fast with a Sapper-line unit), temples (pay to heal/revive; free slow healing for anyone), nomad camps (a town that relocates every half day and always has a shop), and hidden sites (treasure, a card, a rare recruit or a lair — hidden until a squad's sight reaches them).
- **Roads** connect the visible buildings and bases; a non-flying squad moves at ×0.75 time on them.
- **Day and night:** day 06:00–18:00, night 18:00–06:00. Holy units fight +15% by day and −15% at night; evil units the reverse; neutral units are unaffected.
- **Game speed:** five tiers (×0.25, ×0.5, ×1, ×2, ×4), PgUp/PgDn to change, Space to pause. A day at normal speed takes 5 real minutes. Opening any menu or a battle pauses the clock too.
- **Fog of war:** terrain is always visible; enemy and neutral squads only show within your nearest squad's sight radius (base 7 hexes, further out while flying or on your own travel terrain, closer in mountains or forest, clamped 5–10 and never shown as a number). Hidden sites reveal the same way.
- **The log (L)** records every battle action, every map order and arrival, every economic flow, and every progression change, filterable by squad and category. A debug toggle in it shows the hidden numbers behind each entry (hit chance, the actual roll, growth, luck, and so on).

## Squads and movement

- Each squad has a **front row** and a **back row**; a unit's class decides whether it fights (and is attacked) from the front or back.
- **Slots:** every squad starts with 5. A Small unit costs 1 slot, Large costs 2, and two Tiny units can share a single slot. A leader earns +1 slot at level 5/10/15/20, but only if their charisma is at least 5 × their level at that moment (a Herald or Standard-Bearer in the squad helps toward this).
- **Travel type:** a squad's one native terrain, decided by a weighted vote of its living units' home terrain (Small 1, the leader and Large units 2, Tiny ½; ties go to the leader). Moving through that terrain costs the squad its base speed; other terrain costs more (see difficulty above). A squad that's entirely flyers moves as Sky (flies over everything but air gaps); a squad that's entirely water natives or amphibians can cross deep water.
- **Speed tier** is set by the squad's slowest living unit and decides how fast it crosses a hex; losing units to death slows the squad further, proportional to the slots lost.
- **Deployment:** at the start, only the Opinion Leader's squad is on the map. Other squads deploy from the Player Base (via Edit Units or the Deploy button), costing one day of their upkeep in gold, and appear on the Player Base; you lay their route as you deploy them. A squad cap (default 5, set in the configurator) limits how many of your squads can be on the map at once. A squad returns to base by marching there and going in on arrival, or instantly if it's already standing on the Player Base.
- **Giving orders:** click a squad to open its menu (this pauses the game); Move lets you click hexes to lay a chain of rally points, and clicking the last point again commits the route. You can plan routes for as many squads as you like, one at a time, while paused.
- **Squads of yours can share a hex** freely. A hex held by a hostile squad blocks movement; your squad waits at its edge instead of stacking on it.

## Units

- **Stats:** STR, CON (drives HP), INT, SPD (turn order), AGI (hit and dodge), PDEF, MDEF, plus Alignment (0–100: evil ≤40, neutral 41–59, holy ≥60) and Charisma (0–100).
- **Rolling a new unit:** starts from its class's base stats, adds a random number of "flex" points weighted toward the class's key stats, rolls its alignment inside its class's lean, and gets a unique first and last name (no repeats within a run).
- **Hidden traits**, rolled once and never shown directly: a growth profile (each non-key stat has its own chance to grow at a level-up, guaranteed at least once every 3 levels), a talent tier (Ordinary/Gifted/Prodigy, each raising XP and growth chances), and luck (a little extra crit chance, dodge, and better draws). These only ever show up as a visible effect — a Prodigy's level-up gets a flourish, a lucky unit does well more often.
- **Morale**, per squad (0–100, starts at 50, never shown as a number): falls when the squad's outnumbered in a battle, its leader gets hit, a unit of it dies, it fights off its leader's home terrain, or at the wrong time of day for its alignment (holy by night, evil by day); rises on a win, a liberation, or resting in a temple. Applies to every squad, not just yours — an enemy or neutral one has to be driveable-off too. Below 30, the squad deals 10% less damage; below 25, your leader can try to drive a beaten enemy off the map for good instead of letting it recover, for a charisma-based chance. A log line marks every change.
- **Loyalty**, recruited neutrals only (§16; a unit you roll fresh for a Serf-line squad never has it): rises after a win or while reputation is high, falls sitting unused in the recruit pool. If it drops very low, the unit gets a day's warning (logged) before it might actually leave the army for good on the next day change — never mid-battle.
- **Bonds:** two units that fight 6 battles together in the same squad gain +5% damage and +5% dodge while both stay alive, announced once in the log.
- **XP and levels:** every living unit on the winning side of a battle earns XP, more against a stronger enemy and with a more charismatic leader. A level costs the class's XP rate × a fixed amount. Key stats always go up a level; other stats follow the hidden growth roll.
- **Promotion** becomes available at level 3, 6 and 9 (into the class's next line stage), only at the Player Base, only if the squad still fits its slots afterward; where a line branches by alignment, the unit's current band decides which branches are open.
- **Leaders:** whichever living unit that can lead was added to the squad first. If the leader is removed, the best remaining leader-capable unit (alive, highest level, highest stage) takes over automatically.

## Battle

- **Trigger:** a player squad and a hostile squad land on the same or adjacent hexes, or you order a ranged attack from the squad menu. The map pauses and the battle view opens, played on the defending hex's terrain.
- **Turn order:** every living unit with attacks left acts once per round, fastest (SPD) first, until both sides are out of attacks or one side is wiped. A squad that resisted recruitment, or has First strike/Charge, can act first.
- **Targeting:** plain melee hits the front row first (the back row only once the front is empty); ranged and magic can hit any row; several classes have group attacks (hit a whole row, the whole squad, a cleave, a pierce, a chain) per their class sheet.
- **Your controls mid-battle:** switch tactic any time (Best/Strong/Weak/Leader — who your units focus), retreat, or play any cards in your hand.
- **Damage:** physical is (STR + weapon) × modifiers − (PDEF + armor); magic is (INT + spell power) × modifiers − MDEF, then an element multiplier; healing scales with INT. Hit chance is 85% plus the attacker's AGI edge over the target's, minus a little per target luck, clamped 50–95% (never shown as the raw number — you see the shaped, fairer version: two dice averaged, a guaranteed hit after 3 misses in a row, and crit chance that climbs after every non-crit). Damage always varies ±10%.
- **Modifiers** that multiply together: home terrain (+15%, or −15% on difficulty-3 terrain away from home), day/night by alignment, element match-ups (strong/weak pairs), a few class-vs-class bonuses (archers vs flyers, mounted vs mounted, and so on), the defending building's bonus, and each class's own traits and auras from the sheet.
- **Status effects** (poison, burn, freeze, shock, petrify, sleep, charm, blind, silence, fear, weak, haste, protect, regen, cleanse) all clear at the end of the battle; a unit native to an element's terrain resists the matching one.
- **Retreat:** your chance is 50% plus 20% per speed tier you have on the enemy, clamped 10–90%. Success steps your squad back a hex and costs each unit a point of charisma; failure costs the squad its next action.
- **Outcomes:** a wiped-out squad is carried back to its base needing full revival; a squad that loses its leader marches home on its own (reviving the leader in time cancels this); otherwise the side that lost the larger HP share gets pushed back 1 hex (2 if it wasn't on its travel terrain). A squad keeps its current orders after a battle unless it was pushed back, retreated, wiped out, or lost its leader. If a beaten enemy's morale is low enough, your leader can try to drive it off the map for good instead of letting it recover (see "Morale" above).

## Buildings and the economy

- **Liberating** a town or tower (stand a living ground unit there for 60 ticks, twice as fast with a Sapper) flips its owner, gives reputation and alignment swings, +5 charisma to a matching-alignment leader, a gold bonus, a card, and a tech point. A popup names what you took, focuses the camera on it, and shows the card you drew (or lets you pick one, if a Seer or Oracle offers a choice) right there.
- **Resting in a building** heals a squad's living units a share of their max HP each day: 15% in your own base, 15% in a town/tower matching your alignment, 10% otherwise, 5% in a temple. Squads and the recruit pool at the Player Base heal the base's 15% too.
- **Income and upkeep**, settled every noon: you earn gold per town/tower you hold, then pay upkeep for every unit in the army (in a squad or the recruit pool, fallen units included) — upkeep scales with a unit's stage and size. Gold never goes negative; unpaid upkeep is currently just lost (no morale/loyalty penalty yet — see below).
- **Going broke:** at zero gold, any squad can be sold from Edit Units for a gold value based on its units' stages; it leaves the army, the map and loses its items.
- **Shops** open from the squad menu when a squad stands still in a building with one (not enemy-held). Towns and nomad camps also sell Serfs into your recruit pool. Every shop stocks herbs and a handful of random items, priced by your reputation (and cheaper still for a squad with a Smuggler or Fence). Temples sell healing and revival from the same screen.
- **Services and consumables:** heal a hurt unit to full, or revive a fallen one, for gold — only at the Player Base, in the recruit pool, or for a squad standing still in a temple. Herbs (+30 HP) are a carried consumable, used from the squad menu.

## Reputation, charisma and alignment

- **Reputation** is one army-wide 0–100 meter (starting at 50). It rises or falls with liberations and with time spent in a matching-alignment building, moving opposite ways for holy vs. evil squads (neutral squads don't move it). It sets your liberation bonus size, shop prices (cheaper near 100, pricier near 0) and your chance to recruit a neutral squad you meet — doubled for a squad with a Smuggler or Fence on prices.
- **Charisma**, per unit: up from liberating a matching building (leader only), from beating a notably stronger enemy; down from retreating or beating a much weaker one.
- **Alignment**, per unit, each battle: up against an even-or-stronger enemy, down against a weaker one; liberating a town pushes every unit's alignment toward holy, a tower toward evil.

## Cards

- You start with 3 random cards, and draw one more per building liberated or hidden site found (a Seer-led squad chooses from 2 options, an Oracle from 3; a Foresight leader previews what's coming). No limit on cards held or played.
- Most cards are played during a battle (stat boosts, heals, attacks on the whole enemy squad, debuffs, extra turns); Rooster and Fox are played from the map and jump the clock to the next noon or midnight.
- XP that comes specifically from card damage is redirected to the Opinion Leader's squad instead of whichever squad is fighting (unless that's the same squad).

## Tech tree

- One army-wide tree, four tiers, six branches (Arms, Archery, Arcana, Cavalry, Beasts and flyers, Logistics) plus a terrain node per terrain per tier. You start with 3 tech points, earning more from liberations, battle wins, and a bonus for finishing the map in victory.
- A node costs its tier number in points. A tier opens once 80% of the previous tier's branch nodes (not counting terrain nodes) are bought. Spend any time from the Tech screen.

## Your starting army (Map 1 setup)

- **6 squads**, each a stage-3 leader plus four stage-2 units, rolled only from the basic "Serf" promotion lines (never the rarer race lines).
- Between the 6 leaders, every terrain a Serf line can reach (Plains, Forest, Swamp, Mountain, Desert) is covered by at least one squad's leader. Each squad also always has at least one front-line unit and one healer-or-support unit; everything else about the roll is random.
- One of the 6, chosen at random, is the Opinion Leader's squad — the only one that starts deployed, standing on the Player Base. The other 5 wait in your Edit Units roster.
- You also start with 3 random cards, 3 tech points and 500 gold.

## The enemy

Ten enemy squads (4 units each, no healers) are placed at the start, with distinct jobs:

- **1 Leader** — holds the Enemy Base and never moves.
- **1 Base guard** — stationed beside the Enemy Base, never moves.
- **4 Garrisons** — each holds one enemy-owned town or tower, never moves.
- **1 Raider** — marches on whichever player-held town or tower currently has the weakest defense, or the Player Base if you don't hold any; re-targets whenever it's free to move again.
- **3 Wildcards** — each rolls, once, to either act like a raider (marching on your weakest-held building) or to defend (march to reinforce the nearest enemy-held building that a player squad is actively fighting for); a defending wildcard that has nothing to reinforce just holds its ground.

A squad that holds its post (leader, base guard, garrison) only ever moves if it's pushed back from losing a fight there — it never goes looking for a fight on its own. The enemy can retake a building the same way you liberate one: a living ground unit of theirs sitting unopposed in it for 60 ticks flips it back, including your own Player Base.

## Neutrals and recruiting

- **Lairs** are scattered off-road, each home to one race (never a Serf-line class) native to that spot's terrain; the further a lair is from the Player Base, the stronger and higher-level its squad. Unlike towns and towers, you can't tell a lair is there until a squad's sight reaches it.
- Each lair's squad **roams** a short patrol around its lair, chasing down the nearest player or enemy squad that wanders into range; with nothing nearby it just wanders near home. Neutrals fight both you and the enemy — an enemy squad that stumbles into one fights it out on its own, with no pause for you to watch.
- **Meeting one yourself** offers a choice: you're told its class, not how many of them there are, then pick Recruit or Fight.
  - **Recruit** rolls a chance from the neutrals' numbers, how far your squad's alignment is from theirs, and your reputation; success adds them to your recruit pool for free and gives your leader +3 charisma, no fight at all. Failure means they fight you having resisted — they get a full round of attacks before you do.
  - **Fight** skips the roll and goes straight into a normal battle.
- This is the only way the rarer race lines (the sheet's R, N, L and T lines) enter your army — they never appear in a starting squad or an ordinary promotion.

## Victory and defeat

- The configurator turns each condition on or off; any one you've enabled ends the map the moment it's met (checked every tick). If both a defeat and a victory condition are met on the same tick, defeat wins.
- **Victory**, any you've enabled: defeat the enemy leader (on by default — their squad never moves from the Enemy Base, so this always means beating or driving it off there); reach the goal (stand a living squad on the Enemy Base's hex); defeat a set number of enemy squads, or all of them; hold a share of the map's towns and towers for a set stretch of time running (losing the share partway through resets the clock); or just survive until a timer runs out.
- **Defeat**, any you've enabled: the Opinion Leader dies (on by default); the Player Base is captured — the enemy takes it the same way you liberate a town, so this only becomes a real threat once you're not holding ground for them to march on instead.
- The map freezes the instant it ends — no more movement, battles or ticking — and a summary shows the result, the day you ended on, your gold and reputation, enemy squads defeated, and towns held. From there the only way out is back to the title; there's no second map yet.

---

## Not yet in the game

These are named in the design but not working yet — don't expect them when testing. See `ROADMAP.md` for the plan and `STATUS.md` for current session.

- **The full debug panel.** Backtick opens a small panel with just a "Wide roster" playtesting button. The rest of §19.2's tools (reveal map, teleport a squad, time controls, spawn/edit units, force a battle result, AI inspection, a headless sim runner) aren't built yet. Some debug aids exist outside that panel already: O cycles map overlays, G toggles the hex grid, H reveals hidden sites, and F8 cycles a squad's travel type for testing.
- **In-battle AI tactics and retreat.** The enemy side always fights with the default "Best" tactic and never retreats mid-battle. A retreat threshold and per-role tactic weighting are planned but not scheduled to a specific session yet.
- **Morale and loyalty portraits.** Both are fully working and logged (see "Units" above), but the spec's visual signs — a leader's portrait shifting from confident to shaken, an uneasy portrait at low loyalty — have no portraits to shift yet.
- **Maps 2 and 3, the campaign layer, difficulty settings, and final art** are all explicitly out of scope for this build (`SPEC.md` §2).
