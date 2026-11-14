# Map ambience

The plan for what the map sounds like (user, 2026-11-13). The map is on screen for most of a game, often paused, so its music has to sit in the background for a long time without wearing on the player. The funk day and night themes are good tunes but too busy for that, and don't match the game's tone. In their place: **sparse piano phrases with silence between them, over environmental sound**, the day and night versions built on one skeleton so they clearly answer each other. Holy units flourish by day and evil ones by night, so night is the same music made sinister.

## The music: a pool of phrases, not a loop

- **Per state (day, night):** about 10 phrases, each 8 bars (about 32 s by day at 60 BPM, 36 s by night at 54), 3 to 7 piano notes, sustain pedal down, soft. No hummable tune: a catchy line is what makes background music intrude.
- **Silence is part of it:** after each phrase, 20 to 50 s of nothing; now and then a phrase is sat out. Music sounds about 40 to 50% of the time.
- **Never the same phrase twice in a row.**
- **Turns:** at dusk the phrase playing finishes, then a 4-bar turn (the day's progression ending minor), then the night pool; at dawn the night's turn ends major.

## Day and night: one skeleton

The same roots, two bars each, in both: **D, C, G, D**.

| | Bars 1-2 | 3-4 | 5-6 | 7-8 |
| --- | --- | --- | --- | --- |
| Day | D (add 9) | C | G | D |
| Night | Dm | C (open fifth) | Gm | Dm |

- **Day:** C to G to D is the church "amen" close, right for the holy side. Middle and high register, open chords, a lighter room.
- **Night:** the same roots with minor thirds. Lower, slower, sparser, a longer, darker room. Now and then one color note left hanging: Eb (a half step over the root) or Ab (the tritone against D, the most unstable interval).
- **The motif:** the score's main motif opens with A D F# E. Day plays it rising in every third phrase; night plays it minor (A D F E), an octave down.
- **One instrument, two moods:** the same piano renders both pools, with a different preset (night softer, duller, a little detuned) and a different room (a chapel by day, a crypt by night).

## The ambience

- **Bed:** a 1 to 2 minute loop per state, very quiet: wind and grass by day, crickets and low wind by night. It crossfades over 8 s at dusk and dawn.
- **One-shots:** one every 6 to 25 s, at a random volume, pitched a little up or down, panned at random. Day: songbirds, a distant chapel bell, a stream, far-off hammering, sheep, a banner flapping. Night: an owl, distant wolves, a crow, creaking timber, a gust.
- **The bell turned:** the day's chapel bell, an octave down with a long tail, struck once at night. The holy sound made sinister, as the music is.
- **Later, maybe:** sounds tied to map features (birds near forests, water near rivers, bells near temples), so the soundscape changes as the camera moves.

## In the game (not built yet; ROADMAP M5, map ambience)

- The `Sound` node plays the map in this mode instead of the `map_day`/`map_night` loops: pick a phrase, play it, wait, repeat; at a turn, finish, play the turn, switch pools. The bed and one-shots run alongside on the Effects bus.
- The numbers (gaps, rest chance, volumes, shot spacing, pitch and pan) are `data/audio.json` `map_ambience`.
- It keeps playing while the game is paused (the map sits paused a lot).
- Stingers and voice lines still dip the music, as now.

## The title and victory beds

Added 2026-11-13 (user): the title screen and the end-of-map victory screen move to the same piano. The battle themes, the army theme, the defeat loop and the stingers stay as they are for now (the stingers should stand out more against the piano).

- **Each a small pool** of about 4 phrases on the day's skeleton (D C G D), the motif opening rising in each; victory broader and fuller than the title.
- **Short gaps** (a few seconds) and the first phrase at once: these screens are seen briefly, so long silences would greet the player with nothing.
- **No ambience bed:** that stays the map's.
- **The menus** play the day pool, so it carries on into a map that starts by day.
- Rendered with the day's piano and room; played by the same player as the map (ROADMAP M5 session 11).

## The tools

Each runs on its own; `tools/build_map_audio.py` strings them together.

| Step | Tool | Does |
| --- | --- | --- |
| 1 | `tools/map_phrases.py [--count 10] [--seed 1]` | Writes the pools and turns as MIDI to `data/audio/midi/map/` (the sources; committed). A new seed draws a new set. |
| 2 | `tools/render_audio.py "map/day_*" map/dusk --group [engine and room options]` | Renders them to `data/audio/music/map/`. `--group` levels a pool together so soft phrases stay soft. |
| 3 | `tools/prepare_ambience.py` | `data/audio/ambience_src/<day,night>/` (downloads as they came) to `data/audio/ambience/<day,night>/`: beds cut into seamless loops, one-shots trimmed, all levelled. |
| 4 | `tools/preview_map_audio.py [--state day,night,cycle] [--minutes 6]` | Mixes a few minutes of what the map would sound like, with the `audio.json` settings, to `logs/` to listen to. |
| all | `tools/build_map_audio.py [--keep-midi] [--preview]` | Steps 1 to 4, each state with its own render settings (`RENDER` at the top of the file). |

As with the other music, rendered WAVs are committed once the user approves them; the MIDI sources every round.

### Render engines

`render_audio.py --engine`:

- **fluidsynth** (the default): FluidSynth and GeneralUser GS, as for the rest of the score. Fine for drafts; the General MIDI piano decays fast and sounds plain.
- **pianoteq**: Modartt's modelled piano (paid, with a trial), through its own command-line render; `--preset` picks the preset. Hammer hardness, soft pedal, detuning and lid make day and night one piano in two moods. Set `PIANOTEQ` to the program or put it under `tools/audio_bin/pianoteq/`.
- **vst3**: any VST3 instrument (`--plugin`), through Spotify's Pedalboard (`pip install pedalboard`). Run once with `--edit` to open the plugin's window and choose a sound; closing it saves the settings to the `--state` file for every later render.

And for every engine: `--fx` (a VST3 effect, with `--fx-state`/`--edit-fx` the same way), and `--ir` with `--wet`: convolution with an impulse response, a WAV recording of a real space.

### Worth installing (all free unless marked)

- `pip install pedalboard` (the vst3 engine and `--fx`).
- **Instruments:** Pianoteq (paid; trial), or a felt piano from Pianobook (free sampled instruments, played in Decent Sampler), or Spitfire LABS Soft Piano. Surge XT if pads or drones are ever wanted under the piano.
- **Rooms:** Valhalla Supermassive (a VST3 reverb, as `--fx`), and impulse responses from the OpenAIR library (a chapel for day, a cave or crypt for night) in `tools/audio_bin/ir/`.
- **Environmental sounds:** freesound.org (filter for CC0) and the free Sonniss GDC bundles. Note each sound's source and licence in the asset list.
- **Later:** Stable Audio Open runs on an 8 GB GPU and generates sound effects and field recordings from text; check its licence (Stability AI Community License) before shipping anything from it.

Machine-specific files (programs, plugin settings, impulse responses) stay in the git-ignored `tools/audio_bin/`.
