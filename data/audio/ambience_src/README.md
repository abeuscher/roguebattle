# Ambience sources

Environmental sounds for the map, as downloaded or recorded, never changed (Godot ignores this folder). Put them in `day/` or `night/`; a file whose name starts with `bed` is that state's looping background, everything else is a one-shot. `python tools/prepare_ambience.py` writes what the game plays to `data/audio/ambience/`. Note each sound's source and licence in `data/audio-asset-list.csv` (freesound.org: filter for CC0).

`any/` holds one-shots for day and night alike. A file whose name starts with a key of `audio.json` map_ambience `shot_needs` plays only while that holds: `clops` (a mounted unit on the move in sight), `waves` (a squad of yours near the sea), `river` (one beside a river). The files here now are synthesized drafts from `tools/draft_ambience.py` (2026-11-14): replace any by dropping a file of the same name over it, then run `prepare_ambience.py`.
