"""Render the MIDI drafts to audio the game plays (ROADMAP M5 session 1).

data/audio/midi/<cue>.mid -> data/audio/music/<cue>.wav (loops) or
data/audio/stingers/<cue>.wav or data/audio/effects/<cue>.wav (one-shots), through FluidSynth and a General MIDI
SoundFont. Godot can't play MIDI, so the .mid files are the source and these WAVs are
what ships (Godot compresses them on import).

- A loop is cut to exactly its length (the MIDI's "end" marker); the reverb tail that
  rings past the end is laid back over the start, as it sounds when the loop repeats,
  so it loops without a click or a gap.
- A one-shot keeps its tail until it fades out, then gets a short fade.
- Every cue is levelled to the same loudness (RMS), never past a -1 dBFS peak, so a
  sparse cue (the night theme) doesn't come out louder than a full one. With --group,
  every cue named in one run gets the same gain instead, so a pool of phrases keeps the
  dynamics it was written with (a soft phrase stays soft).
- Cues in a folder (map/day_01, from tools/map_phrases.py) are one-shots that go to
  data/audio/music/<folder>/, ending where they fall silent. Name them with a pattern:
  "map/day_*".

Engines (--engine), for something better than General MIDI (docs/map-ambience.md):
- fluidsynth (the default): FluidSynth and a SoundFont.
- pianoteq: Pianoteq's own command-line render, with --preset (a preset name as Pianoteq
  lists it). Set PIANOTEQ to its program, or put it under tools/audio_bin/pianoteq/.
- vst3: any VST3 instrument (--plugin path.vst3) through Spotify's Pedalboard
  (pip install pedalboard). --state keeps the instrument's settings: run once with
  --edit to open the plugin's window, choose a sound, close it, and the settings are
  saved to the --state file for every later render. A .vstpreset file works as --state too.
Any engine can then go through a VST3 effect (--fx, --fx-state, --edit-fx the same way)
and a room: --ir is an impulse response (a WAV recording of a real space), mixed in at
--wet. --tail is how long to render past the end to catch the ring-out.

Needs (kept out of git, in tools/audio_bin/):
- FluidSynth: https://github.com/FluidSynth/fluidsynth/releases (the win10-x64 zip,
  unpacked to tools/audio_bin/fluidsynth/), or set FLUIDSYNTH to its fluidsynth.exe,
  or have fluidsynth on the PATH.
- GeneralUser GS: https://github.com/mrbumpy409/GeneralUser-GS (GeneralUser-GS.sf2 in
  tools/audio_bin/), or set SOUNDFONT.

    python tools/render_audio.py [cue or pattern ...] [options]
"""
import argparse
import glob
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import wave

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
BIN = os.path.join(ROOT, "tools", "audio_bin")
MIDI = os.path.join(ROOT, "data", "audio", "midi")
LOOPS = {"map_day", "map_night", "army", "battle_plains", "battle_forest", "battle_mountain", "battle_swamp", "end_victory", "end_defeat", "intro_music"}  # music cues; the rest are one-shots
EFFECTS = {"click", "firework"}  # one-shots that go to data/audio/effects/ (the rest to stingers/)
RATE = 44100
PEAK = 10 ** (-1.0 / 20)  # -1 dBFS
LOUDNESS = 10 ** (-18.5 / 20)  # target RMS (the day theme's level at its peak limit)
TAIL_SECONDS = 4.0  # rendered past a cue's end to catch its ring-out (--tail)
TAIL_LIMIT = {"victory_riff": 0.8, "click": 0.08, "firework": 0.3}  # one-shots whose ring-out is cut short: seconds kept past the cue's end


def tool_paths() -> tuple:
    fs = (os.environ.get("FLUIDSYNTH") or next(iter(glob.glob(os.path.join(BIN, "fluidsynth", "**", "fluidsynth.exe"), recursive=True)), "")
          or shutil.which("fluidsynth") or "")
    sf = os.environ.get("SOUNDFONT") or os.path.join(BIN, "GeneralUser-GS.sf2")
    if not fs or not os.path.exists(fs):
        sys.exit("FluidSynth not found: unpack it to tools/audio_bin/fluidsynth/ or set FLUIDSYNTH (see this file's notes).")
    if not os.path.exists(sf):
        sys.exit("SoundFont not found: put GeneralUser-GS.sf2 in tools/audio_bin/ or set SOUNDFONT.")
    return fs, sf


def pianoteq_path() -> str:
    pt = (os.environ.get("PIANOTEQ") or next(iter(glob.glob(os.path.join(BIN, "pianoteq", "**", "Pianoteq*.exe"), recursive=True)), "")
          or shutil.which("pianoteq") or "")
    if not pt or not os.path.exists(pt):
        sys.exit("Pianoteq not found: set PIANOTEQ to its program, or put it under tools/audio_bin/pianoteq/.")
    return pt


def _vlq(t: bytes, i: int) -> tuple:
    v = 0
    while True:
        b = t[i]
        i += 1
        v = (v << 7) | (b & 0x7F)
        if not b & 0x80:
            return v, i


def midi_events(path: str) -> tuple:
    """All of a file's events as (tick, status byte or 0xFF for meta, data), plus its ticks per beat."""
    d = open(path, "rb").read()
    tpb = struct.unpack(">H", d[12:14])[0]
    i, out = 14, []
    while i + 8 <= len(d):
        size = struct.unpack(">I", d[i + 4:i + 8])[0]
        t, j, tick, status = d[i + 8:i + 8 + size], 0, 0, 0
        i += 8 + size
        while j < len(t):
            delta, j = _vlq(t, j)
            tick += delta
            if t[j] == 0xFF:
                kind = t[j + 1]
                size2, j = _vlq(t, j + 2)
                out.append((tick, 0xFF, bytes([kind]) + t[j:j + size2]))
                j += size2
            elif t[j] in (0xF0, 0xF7):
                size2, j = _vlq(t, j + 1)
                j += size2
            else:
                if t[j] & 0x80:
                    status = t[j]
                    j += 1
                n = 1 if status & 0xF0 in (0xC0, 0xD0) else 2
                out.append((tick, status, t[j:j + n]))
                j += n
    return sorted(out, key=lambda e: e[0]), tpb


def _seconds(events: list, tpb: int):
    """A function from ticks to seconds, following the file's tempo changes."""
    tempos = [(0, 500000)] + [(tick, int.from_bytes(data[1:], "big")) for tick, s, data in events if s == 0xFF and data[0] == 0x51]
    def at(tick: int) -> float:
        secs, last, tempo = 0.0, 0, 500000
        for t, tp in tempos:
            if t > tick:
                break
            secs += (t - last) / tpb * tempo / 1e6
            last, tempo = t, tp
        return secs + (tick - last) / tpb * tempo / 1e6
    return at


def cue_seconds(path: str) -> float:
    """The cue's length: the tick of the "end" marker, at the file's tempo."""
    events, tpb = midi_events(path)
    for tick, s, data in events:
        if s == 0xFF and data == b"\x06end":
            return _seconds(events, tpb)(tick)
    sys.exit("%s has no end marker" % path)


def read_wav(path: str) -> tuple:
    """(sample rate, float samples [frames, channels]) from a 16, 24 or 32-bit PCM or a
    32-bit float WAV (the wave module reads no float files, so the header is read here)."""
    d = open(path, "rb").read()
    i, fmt, data = 12, None, None
    while i + 8 <= len(d):
        cid, size = d[i:i + 4], struct.unpack("<I", d[i + 4:i + 8])[0]
        if cid == b"fmt ":
            fmt = struct.unpack("<HHIIHH", d[i + 8:i + 24])
        elif cid == b"data":
            data = d[i + 8:i + 8 + size]
        i += 8 + size + (size & 1)
    if fmt is None or data is None:
        sys.exit("%s isn't a WAV file this tool reads" % path)
    code, channels, rate, _, _, bits = fmt
    if code == 0xFFFE:  # extensible: the real format is in the subformat GUID
        code = struct.unpack("<H", d[d.index(b"fmt ") + 32:d.index(b"fmt ") + 34])[0]
    if code == 3:
        x = np.frombuffer(data, dtype="<f4" if bits == 32 else "<f8").astype(np.float64)
    elif bits == 24:
        a = np.frombuffer(data[:len(data) // 3 * 3], dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        x = (a[:, 0] | (a[:, 1] << 8) | (a[:, 2] << 16))
        x = np.where(x >= 1 << 23, x - (1 << 24), x) / float(1 << 23)
    elif bits in (8, 16, 32):
        dtype = {8: np.uint8, 16: "<i2", 32: "<i4"}[bits]
        x = np.frombuffer(data, dtype=dtype).astype(np.float64)
        x = (x - 128) / 128 if bits == 8 else x / float(2 ** (bits - 1))
    else:
        sys.exit("%s: %d-bit samples aren't supported" % (path, bits))
    x = x[:len(x) // channels * channels].reshape(-1, channels)
    return rate, x


def resample(x: np.ndarray, rate: int) -> np.ndarray:
    if rate == RATE:
        return x
    n = round(len(x) * RATE / rate)
    src = np.arange(len(x)) / rate
    dst = np.arange(n) / RATE
    return np.stack([np.interp(dst, src, x[:, c]) for c in range(x.shape[1])], axis=1)


def stereo(x: np.ndarray) -> np.ndarray:
    return np.repeat(x, 2, axis=1) if x.shape[1] == 1 else x[:, :2]


def render(fs: str, sf: str, mid: str, tail: float = TAIL_SECONDS) -> np.ndarray:
    """FluidSynth's render, as float stereo samples, padded with silence for the tail."""
    padded = tempfile.NamedTemporaryFile(suffix=".mid", delete=False).name
    out = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    try:
        _pad_midi(mid, padded, tail)
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


def render_pianoteq(pt: str, mid: str, preset: str, tail: float) -> np.ndarray:
    padded = tempfile.NamedTemporaryFile(suffix=".mid", delete=False).name
    out = tempfile.NamedTemporaryFile(suffix=".wav", delete=False).name
    try:
        _pad_midi(mid, padded, tail)
        cmd = [pt, "--headless", "--midi", padded, "--wav", out, "--rate", str(RATE), "--bit-depth", "24"]
        if preset:
            cmd[2:2] = ["--preset", preset]
        subprocess.run(cmd, check=True)
        rate, x = read_wav(out)
        return stereo(resample(x, rate))
    finally:
        for p in (padded, out):
            if os.path.exists(p):
                os.remove(p)


def load_plugin(path: str, state: str):
    try:
        import pedalboard
    except ImportError:
        sys.exit("The vst3 engine and --fx need Pedalboard: pip install pedalboard")
    plugin = pedalboard.load_plugin(path)
    if state and os.path.exists(state):
        if state.lower().endswith(".vstpreset"):
            plugin.load_preset(state)
        else:
            plugin.raw_state = open(state, "rb").read()
    return plugin


def edit_plugin(path: str, state: str) -> None:
    """Opens the plugin's own window; its settings are saved to `state` when it closes."""
    if not state:
        sys.exit("--edit and --edit-fx need a file to keep the settings in (--state or --fx-state)")
    plugin = load_plugin(path, state)
    print("Close the plugin's window to save its settings to %s" % os.path.relpath(state))
    plugin.show_editor()
    os.makedirs(os.path.dirname(os.path.abspath(state)), exist_ok=True)
    open(state, "wb").write(plugin.raw_state)


def render_vst3(plugin, mid: str, tail: float) -> np.ndarray:
    events, tpb = midi_events(mid)
    at = _seconds(events, tpb)
    messages = [(bytes([s]) + data, at(tick)) for tick, s, data in events if s != 0xFF]
    plugin.reset()
    y = plugin(messages, duration=cue_seconds(mid) + tail, sample_rate=RATE, num_channels=2)
    return stereo(np.asarray(y, dtype=np.float64).T)


def through_fx(plugin, x: np.ndarray) -> np.ndarray:
    plugin.reset()
    y = plugin(x.T.astype(np.float32), RATE)
    return stereo(np.asarray(y, dtype=np.float64).T)


def room(x: np.ndarray, ir_path: str, wet: float) -> np.ndarray:
    """Convolution with an impulse response (normalised to unit energy), mixed in at `wet`."""
    rate, ir = read_wav(ir_path)
    ir = stereo(resample(ir, rate))
    ir /= max(1e-9, np.sqrt((ir ** 2).sum() / 2))
    n = len(x) + len(ir) - 1
    size = 1 << (n - 1).bit_length()
    y = np.stack([np.fft.irfft(np.fft.rfft(x[:, c], size) * np.fft.rfft(ir[:, c], size), size)[:n] for c in range(2)], axis=1)
    dry = np.zeros_like(y)
    dry[:len(x)] = x
    return (1 - wet) * dry + wet * y


def _pad_midi(src: str, dst: str, tail: float = TAIL_SECONDS) -> None:
    """A copy whose tempo track ends `tail` seconds of ticks later, so the render runs on
    past the last note and catches the reverb."""
    d = bytearray(open(src, "rb").read())
    tpb = struct.unpack(">H", d[12:14])[0]
    length = struct.unpack(">I", d[18:22])[0]
    end = 22 + length
    assert d[end - 4:end] == b"\x00\xff\x2f\x00"
    pad = round(tail * 2 * tpb)  # generous: two beats a second covers tempos down to 60
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


def make_one_shot(x: np.ndarray, seconds: float, limit: float | None = None, trim: bool = False) -> np.ndarray:
    """Keeps the cue to its end and its ring-out down to -60 dB; `trim` (pool phrases)
    ends it where it falls silent even before the end, so the player's gaps are real."""
    loud = np.nonzero(np.abs(x).max(axis=1) > 10 ** (-60 / 20))[0]
    end = (loud[-1] + 1) if len(loud) else 0
    if not trim:
        end = max(round(seconds * RATE), end)
    if limit is not None:
        end = min(end, round((seconds + limit) * RATE))
    out = x[:end].copy()
    fade = min(len(out), round((limit / 2 if limit else 0.05) * RATE))
    out[len(out) - fade:] *= np.linspace(1, 0, fade)[:, None]
    return out


def gain(x: np.ndarray) -> float:
    """The gain that brings a cue to the target loudness without passing the peak limit."""
    return min(PEAK / max(1e-9, np.abs(x).max()), LOUDNESS / max(1e-9, np.sqrt((x ** 2).mean())))


def save(path: str, x: np.ndarray, g: float | None = None) -> None:
    x = x * (gain(x) if g is None else g)
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


def cues_for(patterns: list) -> list:
    """Cue names from names or patterns ("map/day_*"); none given: every top-level cue."""
    if not patterns:
        return sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(MIDI, "*.mid")))
    out = []
    for pat in patterns:
        if any(c in pat for c in "*?["):
            found = sorted(glob.glob(os.path.join(MIDI, pat + ".mid")))
            if not found:
                sys.exit("No MIDI matches %s" % pat)
            out += [os.path.relpath(p, MIDI)[:-4].replace(os.sep, "/") for p in found]
        else:
            out.append(pat)
    return out


def out_path(cue: str) -> str:
    if "/" in cue:
        return os.path.join(ROOT, "data", "audio", "music", *cue.split("/")) + ".wav"
    folder = "music" if cue in LOOPS else "effects" if cue in EFFECTS else "stingers"
    return os.path.join(ROOT, "data", "audio", folder, cue + ".wav")


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description="Render data/audio/midi cues to the WAVs the game plays (see this file's notes).")
    ap.add_argument("cues", nargs="*", help='cue names or patterns, e.g. town_riff "map/night_*" (default: every top-level cue)')
    ap.add_argument("--engine", choices=["fluidsynth", "pianoteq", "vst3"], default="fluidsynth")
    ap.add_argument("--preset", default="", help="Pianoteq preset name")
    ap.add_argument("--plugin", default="", help="VST3 instrument (engine vst3)")
    ap.add_argument("--state", default="", help="the instrument's saved settings (.bin from --edit, or a .vstpreset)")
    ap.add_argument("--edit", action="store_true", help="open the instrument's window first and save its settings to --state")
    ap.add_argument("--fx", default="", help="a VST3 effect every cue goes through")
    ap.add_argument("--fx-state", default="", help="the effect's saved settings")
    ap.add_argument("--edit-fx", action="store_true", help="open the effect's window first and save its settings to --fx-state")
    ap.add_argument("--ir", default="", help="impulse response WAV for the room")
    ap.add_argument("--wet", type=float, default=0.35, help="how much of the room to mix in, 0-1 (default 0.35)")
    ap.add_argument("--tail", type=float, default=TAIL_SECONDS, help="seconds rendered past the end (default %g)" % TAIL_SECONDS)
    ap.add_argument("--group", action="store_true", help="one gain for every cue in this run (keeps a pool's dynamics)")
    a = ap.parse_args()

    if a.edit:
        edit_plugin(a.plugin, a.state)
    if a.edit_fx:
        edit_plugin(a.fx, a.fx_state)
    if (a.edit or a.edit_fx) and not a.cues:
        sys.exit(0)
    if a.engine == "fluidsynth":
        fs, sf = tool_paths()
    elif a.engine == "pianoteq":
        pt = pianoteq_path()
    else:
        if not a.plugin:
            sys.exit("--engine vst3 needs --plugin")
        instrument = load_plugin(a.plugin, a.state)
    fx = load_plugin(a.fx, a.fx_state) if a.fx else None

    done = []
    for cue in cues_for(a.cues):
        mid = os.path.join(MIDI, cue + ".mid")
        seconds = cue_seconds(mid)
        if a.engine == "fluidsynth":
            x = render(fs, sf, mid, a.tail)
        elif a.engine == "pianoteq":
            x = render_pianoteq(pt, mid, a.preset, a.tail)
        else:
            x = render_vst3(instrument, mid, a.tail)
        if fx:
            x = through_fx(fx, x)
        if a.ir:
            x = room(x, a.ir, a.wet)
        loop = cue in LOOPS
        y = make_loop(x, seconds) if loop else make_one_shot(x, seconds, TAIL_LIMIT.get(cue), trim="/" in cue)
        done.append((cue, out_path(cue), y, loop))
    g = min(gain(y) for _, _, y, _ in done) if a.group and done else None
    for cue, out, y, loop in done:
        save(out, y, g)
        if loop:
            _mark_loop(out)
        print("%s: %.2f s%s -> %s" % (cue, len(y) / RATE, " (loop)" if loop else "", os.path.relpath(out, ROOT)))
