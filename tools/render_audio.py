"""Render the MIDI drafts to audio the game plays (ROADMAP M5 session 1).

data/audio/midi/<cue>.mid -> data/audio/music/<cue>.wav (loops) or
data/audio/stingers/<cue>.wav (one-shots), through FluidSynth and a General MIDI
SoundFont. Godot can't play MIDI, so the .mid files are the source and these WAVs are
what ships (Godot compresses them on import).

- A loop is cut to exactly its length (the MIDI's "end" marker); the reverb tail that
  rings past the end is laid back over the start, as it sounds when the loop repeats,
  so it loops without a click or a gap.
- A one-shot keeps its tail until it fades out, then gets a short fade.
- Every cue is levelled to the same loudness (RMS), never past a -1 dBFS peak, so a
  sparse cue (the night theme) doesn't come out louder than a full one.

Needs (kept out of git, in tools/audio_bin/):
- FluidSynth: https://github.com/FluidSynth/fluidsynth/releases (the win10-x64 zip,
  unpacked to tools/audio_bin/fluidsynth/), or set FLUIDSYNTH to its fluidsynth.exe.
- GeneralUser GS: https://github.com/mrbumpy409/GeneralUser-GS (GeneralUser-GS.sf2 in
  tools/audio_bin/), or set SOUNDFONT.

    python tools/render_audio.py [cue ...]
"""
import glob
import os
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BIN = os.path.join(ROOT, "tools", "audio_bin")
MIDI = os.path.join(ROOT, "data", "audio", "midi")
LOOPS = {"map_day", "map_night", "army", "battle"}  # music cues; the rest are one-shots
RATE = 44100
PEAK = 10 ** (-1.0 / 20)  # -1 dBFS
LOUDNESS = 10 ** (-18.5 / 20)  # target RMS (the day theme's level at its peak limit)
TAIL_SECONDS = 4.0  # rendered past a cue's end to catch its ring-out


def tool_paths() -> tuple:
    fs = os.environ.get("FLUIDSYNTH") or next(iter(glob.glob(os.path.join(BIN, "fluidsynth", "**", "fluidsynth.exe"), recursive=True)), "")
    sf = os.environ.get("SOUNDFONT") or os.path.join(BIN, "GeneralUser-GS.sf2")
    if not fs or not os.path.exists(fs):
        sys.exit("FluidSynth not found: unpack it to tools/audio_bin/fluidsynth/ or set FLUIDSYNTH (see this file's notes).")
    if not os.path.exists(sf):
        sys.exit("SoundFont not found: put GeneralUser-GS.sf2 in tools/audio_bin/ or set SOUNDFONT.")
    return fs, sf


def cue_seconds(path: str) -> float:
    """The cue's length: the tick of the "end" marker in the tempo track, at its tempo."""
    d = open(path, "rb").read()
    tpb = struct.unpack(">H", d[12:14])[0]
    length = struct.unpack(">I", d[18:22])[0]
    t, i, tick, tempo = d[22:22 + length], 0, 0, 500000
    while i < len(t):
        delta = 0
        while True:
            b = t[i]
            i += 1
            delta = (delta << 7) | (b & 0x7F)
            if not b & 0x80:
                break
        tick += delta
        kind, size = t[i + 1], t[i + 2]
        data = t[i + 3:i + 3 + size]
        i += 3 + size
        if kind == 0x51:
            tempo = int.from_bytes(data, "big")
        elif kind == 0x06 and data == b"end":
            return tick / tpb * tempo / 1e6
    sys.exit("%s has no end marker" % path)


def render(fs: str, sf: str, mid: str) -> np.ndarray:
    """FluidSynth's render, as float stereo samples, padded with silence for the tail."""
    padded = tempfile.NamedTemporaryFile(suffix=".mid", delete=False).name
    out = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    try:
        _pad_midi(mid, padded)
        subprocess.run([fs, "-ni", "-q", "-r", str(RATE), "-g", "0.6", "-F", out, sf, padded], check=True)
        with wave.open(out) as w:
            raw = w.readframes(w.getnframes())
            width, channels = w.getsampwidth(), w.getnchannels()
        dtype = {2: np.int16, 4: np.int32}[width]
        x = np.frombuffer(raw, dtype=dtype).astype(np.float64) / float(np.iinfo(dtype).max)
        return x.reshape(-1, channels)
    finally:
        for p in (padded, out):
            if os.path.exists(p):
                os.remove(p)


def _pad_midi(src: str, dst: str) -> None:
    """A copy whose tempo track ends TAIL_SECONDS of ticks later, so the render runs on
    past the last note and catches the reverb."""
    d = bytearray(open(src, "rb").read())
    tpb = struct.unpack(">H", d[12:14])[0]
    length = struct.unpack(">I", d[18:22])[0]
    end = 22 + length
    assert d[end - 4:end] == b"\x00\xff\x2f\x00"
    pad = round(TAIL_SECONDS * 2 * tpb)  # generous: two beats a second covers tempos down to 60
    vlq = [pad & 0x7F]
    pad >>= 7
    while pad:
        vlq.insert(0, 0x80 | (pad & 0x7F))
        pad >>= 7
    d[end - 4:end] = bytes(vlq) + b"\xff\x2f\x00"
    d[18:22] = struct.pack(">I", length - 4 + len(vlq) + 3)
    open(dst, "wb").write(bytes(d))


def make_loop(x: np.ndarray, seconds: float) -> np.ndarray:
    n = round(seconds * RATE)
    out = x[:n].copy()
    tail = x[n:]
    out[:len(tail)] += tail[:n]
    return out


def make_one_shot(x: np.ndarray, seconds: float) -> np.ndarray:
    loud = np.nonzero(np.abs(x).max(axis=1) > 10 ** (-60 / 20))[0]
    end = max(round(seconds * RATE), (loud[-1] + 1) if len(loud) else 0)
    out = x[:end].copy()
    fade = min(len(out), round(0.05 * RATE))
    out[len(out) - fade:] *= np.linspace(1, 0, fade)[:, None]
    return out


def save(path: str, x: np.ndarray) -> None:
    x = x * min(PEAK / max(1e-9, np.abs(x).max()), LOUDNESS / max(1e-9, np.sqrt((x ** 2).mean())))
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(x.shape[1])
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((x * 32767).round().astype("<i2").tobytes())


def _mark_loop(wav: str) -> None:
    """Sets Godot's import of a music cue to loop forward over the whole file (the
    importer's loop_mode 2). A file Godot hasn't imported yet gets it on the next run."""
    imp = wav + ".import"
    if not os.path.exists(imp):
        print("  run Godot's import, then this tool again, to mark %s as a loop" % os.path.basename(wav))
        return
    s = open(imp, encoding="utf-8").read()
    if "edit/loop_mode=2" not in s:
        open(imp, "w", encoding="utf-8", newline="\n").write(s.replace("edit/loop_mode=0", "edit/loop_mode=2"))


if __name__ == "__main__":
    fs, sf = tool_paths()
    cues = sys.argv[1:] or sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(MIDI, "*.mid")))
    for cue in cues:
        mid = os.path.join(MIDI, cue + ".mid")
        seconds = cue_seconds(mid)
        x = render(fs, sf, mid)
        loop = cue in LOOPS
        out = os.path.join(ROOT, "data", "audio", "music" if loop else "stingers", cue + ".wav")
        y = make_loop(x, seconds) if loop else make_one_shot(x, seconds)
        save(out, y)
        if loop:
            _mark_loop(out)
        print("%s: %.2f s%s -> %s" % (cue, len(y) / RATE, " (loop)" if loop else "", os.path.relpath(out, ROOT)))
