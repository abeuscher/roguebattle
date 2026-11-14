"""Build the map's ambience in one go (docs/map-ambience.md): the tools below, in order.

1. tools/map_phrases.py writes the day and night phrase pools, the dusk and dawn
   turns, and the title and victory beds as MIDI (skip with --keep-midi, to keep hand-edited files).
2. tools/render_audio.py renders each state with its own settings (RENDER below): the
   same instrument, a different preset and room, so day and night are one piano in two
   moods; the title and victory beds as the day. Each pool is levelled as a group so
   soft phrases stay soft.
3. tools/prepare_ambience.py readies the environmental sounds, if there are any.
4. With --preview, tools/preview_map_audio.py mixes a few minutes of the result into
   logs/map_preview_cycle.wav to listen to.

Each tool also runs on its own (see its notes); this only strings them together.

    python tools/build_map_audio.py [--count 10] [--seed 1] [--keep-midi] [--preview]
"""
import argparse
import os
import subprocess
import sys

TOOLS = os.path.dirname(os.path.abspath(__file__))

# How each state renders: extra render_audio.py options. FluidSynth and the General MIDI
# piano until better is installed; for example, with Pianoteq and two impulse responses
# in tools/audio_bin/ir/:
#   "day":   ["--engine", "pianoteq", "--preset", "<a bright preset>", "--ir", "tools/audio_bin/ir/chapel.wav", "--wet", "0.25"],
#   "night": ["--engine", "pianoteq", "--preset", "<a soft, detuned preset>", "--ir", "tools/audio_bin/ir/crypt.wav", "--wet", "0.45"],
# or a VST3 instrument (settings chosen once with --edit, see render_audio.py):
#   "day":   ["--engine", "vst3", "--plugin", "<path to .vst3>", "--state", "tools/audio_bin/states/piano_day.bin"],
RENDER = {
    "day": ["--tail", "8"],
    "night": ["--tail", "10"],
}
RENDER["beds"] = RENDER["day"]  # the title and victory beds: the day's piano and room
CUES = {"day": ["map/day_*", "map/dusk"], "night": ["map/night_*", "map/dawn"], "beds": ["map/title_*", "map/victory_*"]}


def run(tool: str, *args: str) -> None:
    print("> %s %s" % (tool, " ".join(args)))
    subprocess.run([sys.executable, os.path.join(TOOLS, tool), *args], check=True)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--count", default="10", help="phrases per state (default 10)")
    ap.add_argument("--seed", default="1", help="a different seed draws a different set of phrases")
    ap.add_argument("--keep-midi", action="store_true", help="render the MIDI as it is, without writing it again")
    ap.add_argument("--preview", action="store_true", help="then mix a preview to logs/")
    a = ap.parse_args()
    if not a.keep_midi:
        run("map_phrases.py", "--count", a.count, "--seed", a.seed)
    for state in CUES:
        run("render_audio.py", *CUES[state], "--group", *RENDER[state])
    run("prepare_ambience.py")
    if a.preview:
        run("preview_map_audio.py")
