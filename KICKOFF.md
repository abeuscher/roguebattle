# Kickoff prompt: first Code session

Paste everything below the line into Claude Code at the repo root.

---

You're building **Landwar**, a real-time squad strategy game in Godot 4. The full design is in `SPEC.md`. Read it completely before writing any code. The roster is in `data/units-landwar-v3.xlsx` and the name list in `data/unit-names.csv`.

## Ground rules

- **The spec is the design.** Don't redesign. If something in the spec is unclear, contradictory, or would make the code much bigger, stop and ask me, citing the section number. For small gaps, pick the simplest reading, note it in `DECISIONS.md`, and keep going.
- **Smaller codebase over clever code.** No speculative abstractions, plugins or frameworks we don't need yet.
- **Check the installed Godot version** (`godot --version`) and use the documentation for that exact version. Don't guess at APIs.
- **Rules stay separate from drawing.** Game rules are plain GDScript classes that never touch scene nodes, so tests and the headless sim can run them (SPEC §20).
- **Content lives in data.** Never hard-code a stat, price or class. Put placeholder numbers in data files.
- **Everything is seeded and logged** (SPEC §1, §19.1).
- **Communication.** Keep updates plain and brief. Tell me what changed and how to try it, not how you did it.

## I am not the bottleneck

I only playtest at milestones (SPEC §23). Inside a milestone, check your own work:

- Automated tests run headless.
- The headless battle sim, once it exists.
- Screenshots of new screens, which you inspect yourself.

Only stop for me at a milestone, or when a real design question blocks you. At each milestone, give me a short note: what to launch, what to try, and what to look for.

## First session

1. **Project setup.**
   - Create the Godot project.
   - Folder layout: `rules/` (pure game logic), `scenes/`, `ui/`, `data/`, `tools/`, `tests/`.
   - A `.gitignore` for Godot.
   - A one-command way to run the tests headless, documented in `README.md`.
2. **`CLAUDE.md`** at the root, with:
   - Plain, brief communication.
   - Prefer a smaller codebase.
   - Look up docs for the installed Godot version rather than guessing.
   - The spec is the design; ask before deviating.
   - Rules stay separate from scene nodes.
   - Content lives in data.
3. **Data pipeline.** Write `tools/xlsx_to_json.py`, which converts the spreadsheet's Units and Role templates sheets to JSON in `data/`. Then:
   - Write a loader in `rules/` with tests that check every class loads.
   - Check that lines resolve (each stage's next class exists).
   - Check that sizes map to slots (Small 1, Large 2, Tiny 0.5).
   - Report any data problems you find in the sheet instead of silently fixing them.
4. **`ROADMAP.md`.** Break milestones M1–M4 into sessions, each small enough to finish, test and merge on its own. Each session needs a goal, the spec sections it covers, and how it will be verified. Keep M1 lean: the aim is a generated map I can look at and a squad I can move.
5. **Start M1, session 1.** Stop at the end of the session with a short summary and what's next.

## Reminders from the spec that are easy to miss

- **Time:** 1 tick = 1 in-game minute, a day = 1,440 ticks, 5 real minutes per day at normal speed (§7).
- **Hex grid:** axial coordinates, chunked rendering, hierarchical pathfinding. Medium maps are 800×450 (§6.1).
- **Squad travel type:** a weighted plurality vote, not every unit's terrain. Sky needs every unit to fly (§8.3).
- **Modals:** selecting a squad pauses the game and opens a modal. Rally-point paths commit by clicking the last point again (§5.3).
- **Game start:** the game opens on Edit Units, not the map (§4, §18).
- **Precedence:** where the spreadsheet and the spec disagree, follow the spec (§21).
