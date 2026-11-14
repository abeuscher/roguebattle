# Ambience sources

Environmental sounds for the map, as downloaded or recorded, never changed (Godot ignores this folder). Put them in `day/` or `night/`; a file whose name starts with `bed` is that state's looping background, everything else is a one-shot. `python tools/prepare_ambience.py` writes what the game plays to `data/audio/ambience/`. Note each sound's source and licence in `data/audio-asset-list.csv` (freesound.org: filter for CC0).
