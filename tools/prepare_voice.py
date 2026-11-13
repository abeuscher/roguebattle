"""Get the user's voice recordings ready for the game (ROADMAP M5 session 4).

data/audio/voice/<line>.wav (the user's recordings, never changed; Godot ignores that
folder) -> data/audio/lines/<line>.wav (what the game plays):

- Mono: channels that match are averaged; if they differ (a stray right channel, as in
  victory.wav) the louder one is kept.
- Trimmed: silence below -50 dB cut from both ends, keeping 20 ms, with 10 ms fades.
- Levelled: every line to the same loudness while speaking (RMS over the voiced part,
  -17 dB), never past a -1 dBFS peak, so no line is much louder than another.

Run it after adding or replacing a recording, then let Godot import:

    python tools/prepare_voice.py [line ...]
"""
import glob
import os
import sys
import wave

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCE = os.path.join(ROOT, "data", "audio", "voice")
OUT = os.path.join(ROOT, "data", "audio", "lines")
SILENCE = 10 ** (-50 / 20)
VOICED = 10 ** (-35 / 20)  # samples above this count toward the loudness
LOUDNESS = 10 ** (-17 / 20)
PEAK = 10 ** (-1 / 20)
PAD, FADE = 0.02, 0.01  # seconds


def read(path: str) -> tuple:
    with wave.open(path) as w:
        channels, width, rate = w.getnchannels(), w.getsampwidth(), w.getframerate()
        raw = w.readframes(w.getnframes())
    if width == 3:
        a = np.frombuffer(raw, dtype=np.uint8).reshape(-1, 3).astype(np.int32)
        x = a[:, 0] | (a[:, 1] << 8) | (a[:, 2] << 16)
        x = np.where(x >= 1 << 23, x - (1 << 24), x) / float(1 << 23)
    else:
        dtype = {2: np.int16, 4: np.int32}[width]
        x = np.frombuffer(raw, dtype=dtype) / float(np.iinfo(dtype).max)
    return x.reshape(-1, channels).astype(np.float64), rate


def mono(x: np.ndarray) -> np.ndarray:
    if x.shape[1] == 1:
        return x[:, 0]
    if np.corrcoef(x[:, 0], x[:, 1])[0, 1] > 0.95:
        return x.mean(axis=1)
    return x[:, int(np.argmax(np.sqrt((x ** 2).mean(axis=0))))]


def trim(x: np.ndarray, rate: int) -> np.ndarray:
    loud = np.nonzero(np.abs(x) > SILENCE)[0]
    if not len(loud):
        return x
    pad = round(PAD * rate)
    y = x[max(0, loud[0] - pad):min(len(x), loud[-1] + pad)].copy()
    fade = min(len(y) // 2, round(FADE * rate))
    y[:fade] *= np.linspace(0, 1, fade)
    y[len(y) - fade:] *= np.linspace(1, 0, fade)
    return y


def level(x: np.ndarray) -> np.ndarray:
    voiced = x[np.abs(x) > VOICED]
    rms = np.sqrt((voiced ** 2).mean()) if len(voiced) else 1e-9
    return x * min(LOUDNESS / max(rms, 1e-9), PEAK / max(np.abs(x).max(), 1e-9))


def write(path: str, x: np.ndarray, rate: int) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(rate)
        w.writeframes((np.clip(x, -1, 1) * 32767).round().astype("<i2").tobytes())


if __name__ == "__main__":
    names = sys.argv[1:] or sorted(os.path.splitext(os.path.basename(p))[0] for p in glob.glob(os.path.join(SOURCE, "*.wav")))
    for name in names:
        x, rate = read(os.path.join(SOURCE, name + ".wav"))
        y = level(trim(mono(x), rate))
        write(os.path.join(OUT, name + ".wav"), y, rate)
        print("%s: %.2f s -> %.2f s, peak %.1f dB" % (name, len(x) / rate, len(y) / rate, 20 * np.log10(np.abs(y).max())))
