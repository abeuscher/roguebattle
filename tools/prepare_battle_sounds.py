"""Get the user's battle sounds ready for the game (ROADMAP M5 session 6).

data/audio/battle_src/<sound>.wav (the user's files, never changed; Godot ignores that
folder) -> data/audio/battle/<sound>.wav (what the game plays):

- Mono (as prepare_voice.py).
- Trimmed: silence below -50 dB cut from both ends, so the sound lands on the hit, with
  a 5 ms fade in and a 30 ms fade out (no clicks).
- Short: at most MAX_SECONDS, the last FADE_OUT of it faded, so a long sound doesn't run
  over the next action at a fast battle speed.
- Levelled on the quiet side (user, 2026-11-14: audible over the music, never
  overpowering): every sound to the same loudness while sounding (RMS over the part
  above -40 dB, LOUDNESS), never past a PEAK. audio.json's cue "db" fine-tunes in game.

Run it after adding or replacing a sound, then let Godot import:

    python tools/prepare_battle_sounds.py [sound ...]
"""
import glob
import os
import sys

import numpy as np

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from prepare_voice import mono, read, write  # noqa: E402

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCE = os.path.join(ROOT, "data", "audio", "battle_src")
OUT = os.path.join(ROOT, "data", "audio", "battle")
SILENCE = 10 ** (-50 / 20)
SOUNDING = 10 ** (-40 / 20)  # samples above this count toward the loudness
LOUDNESS = 10 ** (-24 / 20)  # the voice lines are -17: these sit well under them
PEAK = 10 ** (-6 / 20)
FADE_IN, FADE_TAIL = 0.005, 0.03  # seconds
MAX_SECONDS, FADE_OUT = 1.2, 0.25


def trim(x: np.ndarray, rate: int) -> np.ndarray:
    loud = np.nonzero(np.abs(x) > SILENCE)[0]
    y = x[loud[0]:loud[-1] + 1].copy() if len(loud) else x.copy()
    if len(y) > MAX_SECONDS * rate:
        y = y[:round(MAX_SECONDS * rate)]
        n = round(FADE_OUT * rate)
        y[-n:] *= np.linspace(1, 0, n)
    a, b = min(len(y) // 2, round(FADE_IN * rate)), min(len(y) // 2, round(FADE_TAIL * rate))
    y[:a] *= np.linspace(0, 1, a)
    y[len(y) - b:] *= np.linspace(1, 0, b)
    return y


def level(x: np.ndarray) -> np.ndarray:
    sounding = x[np.abs(x) > SOUNDING]
    rms = np.sqrt((sounding ** 2).mean()) if len(sounding) else 1e-9
    return x * min(LOUDNESS / max(rms, 1e-9), PEAK / max(np.abs(x).max(), 1e-9))


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(SOURCE, "*.wav")))
    for name in names:
        x, rate = read(os.path.join(SOURCE, name + ".wav"))
        y = level(trim(mono(x), rate))
        write(os.path.join(OUT, name + ".wav"), y, rate)
        print("%-9s %.2f s -> %.2f s, peak %.1f dB" % (name, len(x) / rate, len(y) / rate, 20 * np.log10(np.abs(y).max())))
