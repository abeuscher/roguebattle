"""Get environmental sounds ready for the map's ambience (docs/map-ambience.md).

data/audio/ambience_src/<day|night>/<name>.<wav, or anything ffmpeg reads> (downloads
and recordings as they came, never changed; Godot ignores that folder) ->
data/audio/ambience/<day|night>/<name>.wav (what the game plays):

- A file named bed*.* is the background bed (wind and grass, crickets): cut to at most
  --bed-seconds, its end crossfaded into its start so it loops without a seam, levelled
  to -24 dB RMS, and set to loop on Godot's import.
- Anything else is a one-shot (a bird, a bell, an owl): silence below -50 dB trimmed from
  both ends, short fades, levelled while sounding to -20 dB RMS. The game sets the final
  volumes (audio.json "map_ambience"); these just start every file level with the rest.
- All at 44.1 kHz, 16-bit, keeping stereo (mono stays mono), never past -1 dBFS.

WAV files are read directly; other formats (mp3, flac, ogg) need ffmpeg on the PATH.
Run it after adding or replacing a sound, then let Godot import (and run it once more
for a new bed, so its import is set to loop):

    python tools/prepare_ambience.py [name ...]
"""
import argparse
import glob
import os
import shutil
import subprocess
import sys
import tempfile

import numpy as np

import render_audio as ra

ROOT = ra.ROOT
SOURCE = os.path.join(ROOT, "data", "audio", "ambience_src")
OUT = os.path.join(ROOT, "data", "audio", "ambience")
STATES = ["day", "night"]
PEAK = 10 ** (-1 / 20)
BED_LOUDNESS = 10 ** (-24 / 20)
SHOT_LOUDNESS = 10 ** (-20 / 20)
SILENCE = 10 ** (-50 / 20)
SOUNDING = 10 ** (-40 / 20)  # samples above this count toward a one-shot's loudness
CROSSFADE = 4.0  # seconds of a bed's end laid over its start
PAD, FADE_IN, FADE_OUT = 0.02, 0.01, 0.15  # seconds


def decode(path: str) -> np.ndarray:
    if path.lower().endswith(".wav"):
        rate, x = ra.read_wav(path)
        return ra.resample(x, rate)[:, :2]
    ff = shutil.which("ffmpeg")
    if not ff:
        sys.exit("%s isn't a WAV: install ffmpeg (or convert it to WAV) first" % os.path.relpath(path, ROOT))
    tmp = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    try:
        subprocess.run([ff, "-y", "-loglevel", "error", "-i", path, "-ar", str(ra.RATE), "-c:a", "pcm_s16le", tmp], check=True)
        rate, x = ra.read_wav(tmp)
        return x[:, :2]
    finally:
        os.remove(tmp)


def make_bed(x: np.ndarray, seconds: float) -> np.ndarray:
    """At most `seconds` long, the last CROSSFADE seconds faded into the first (equal power)."""
    x = x[:round((seconds + CROSSFADE) * ra.RATE)]
    n = round(CROSSFADE * ra.RATE)
    if len(x) < 3 * n:
        sys.exit("a bed needs at least %g s of sound" % (3 * CROSSFADE))
    out = x[:len(x) - n].copy()
    t = np.linspace(0, np.pi / 2, n)[:, None]
    out[:n] = x[:n] * np.sin(t) + x[len(x) - n:] * np.cos(t)
    return out


def make_shot(x: np.ndarray) -> np.ndarray:
    loud = np.nonzero(np.abs(x).max(axis=1) > SILENCE)[0]
    if not len(loud):
        sys.exit("silent file")
    a = max(0, loud[0] - round(PAD * ra.RATE))
    b = min(len(x), loud[-1] + 1 + round(PAD * ra.RATE))
    out = x[a:b].copy()
    fi, fo = min(len(out), round(FADE_IN * ra.RATE)), min(len(out), round(FADE_OUT * ra.RATE))
    out[:fi] *= np.linspace(0, 1, fi)[:, None]
    out[len(out) - fo:] *= np.linspace(1, 0, fo)[:, None]
    return out


def level(x: np.ndarray, target: float, gate: float = 0.0) -> float:
    sounding = x[np.abs(x).max(axis=1) > gate] if gate else x
    rms = np.sqrt((sounding ** 2).mean()) if len(sounding) else 1e-9
    return min(PEAK / max(1e-9, np.abs(x).max()), target / max(1e-9, rms))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("names", nargs="*", help="only these sounds (file names without extension)")
    ap.add_argument("--bed-seconds", type=float, default=120.0, help="longest a bed loop may be (default 120)")
    a = ap.parse_args()
    found = 0
    for state in STATES:
        for path in sorted(glob.glob(os.path.join(SOURCE, state, "*.*"))):
            name = os.path.splitext(os.path.basename(path))[0]
            if a.names and name not in a.names:
                continue
            found += 1
            x = decode(path)
            bed = name.lower().startswith("bed")
            y = make_bed(x, a.bed_seconds) if bed else make_shot(x)
            g = level(y, BED_LOUDNESS) if bed else level(y, SHOT_LOUDNESS, SOUNDING)
            out = os.path.join(OUT, state, name + ".wav")
            ra.save(out, y, g)
            if bed:
                ra._mark_loop(out)
            print("%s/%s: %.2f s%s -> %s" % (state, name, len(y) / ra.RATE, " (loop)" if bed else "", os.path.relpath(out, ROOT)))
    if not found:
        print("No sounds in %s/<day|night>/ yet" % os.path.relpath(SOURCE, ROOT))
