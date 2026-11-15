"""Draft the map's environmental sounds by synthesis (user, 2026-11-14: Claude drafts them,
the user replaces any with recordings or open-licence sounds).

Writes raw drafts to data/audio/ambience_src/<day|night|any>/, where the user's own files
go too; tools/prepare_ambience.py then makes what the game plays. Seeded, so a run gives
the same files. Only numpy.

    python tools/draft_ambience.py [name ...]

Day: bed (wind and grass), birds_1-3, banner, gust. Night: bed (crickets, low wind), owl,
crow, creak, gust. Any time, played only when their condition holds (audio.json
map_ambience shot_needs): clops_1-2 (a mounted unit on the move), waves_1-2 (a squad near
the sea), river_1-2 (a squad near a river). No bells, and nothing a unit in the game could
make (no wolves, sheep or frogs), so the ambience never sounds like a squad.
"""
import os
import sys
import wave

import numpy as np

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
OUT = os.path.join(ROOT, "data", "audio", "ambience_src")
RATE = 44100


def t(seconds: float) -> np.ndarray:
    return np.arange(int(seconds * RATE)) / RATE


def noise(rng, seconds: float) -> np.ndarray:
    return rng.standard_normal(int(seconds * RATE))


def band(x: np.ndarray, lo: float, hi: float, tilt: float = 0.0) -> np.ndarray:
    """Band-pass by FFT, with an optional spectral tilt (dB per octave, negative = darker)."""
    f = np.fft.rfftfreq(len(x), 1 / RATE)
    spec = np.fft.rfft(x)
    gain = ((f >= lo) & (f <= hi)).astype(float)
    edge = 0.25  # soft edges, a quarter octave
    gain += np.where(f < lo, np.exp(-((np.log2(np.maximum(f, 1) / lo)) / edge) ** 2), 0)
    gain += np.where(f > hi, np.exp(-((np.log2(f / hi)) / edge) ** 2), 0)
    if tilt:
        gain *= (np.maximum(f, 20) / 1000) ** (tilt / 6.02)
    return np.fft.irfft(spec * gain, len(x))


def smooth(rng, seconds: float, rate_hz: float) -> np.ndarray:
    """A slow random curve between 0 and 1, changing about rate_hz times a second."""
    n = max(4, int(seconds * rate_hz) + 4)
    pts = rng.random(n)
    x = np.linspace(0, n - 3, int(seconds * RATE))
    i = np.floor(x).astype(int)
    u = x - i
    return pts[i] * (1 - u) + pts[i + 1] * u  # linear between random points


def env(n: int, attack: float, release: float) -> np.ndarray:
    a, r = max(1, int(attack * RATE)), max(1, int(release * RATE))
    e = np.ones(n)
    e[:a] = np.linspace(0, 1, a)
    e[-r:] *= np.linspace(1, 0, r)
    return e


def place(out: np.ndarray, sound: np.ndarray, at: float) -> None:
    i = int(at * RATE)
    j = min(len(out), i + len(sound))
    out[i:j] += sound[:j - i]


def norm(x: np.ndarray, peak: float = 0.8) -> np.ndarray:
    return x / max(np.abs(x).max(), 1e-9) * peak


# --- The sounds ----------------------------------------------------------------------

def wind(rng, seconds: float, lo=80, hi=900) -> np.ndarray:
    w = band(noise(rng, seconds), lo, hi, -4)
    return w * (0.35 + 0.65 * smooth(rng, seconds, 0.15))


def day_bed(rng):
    s = 70
    grass = band(noise(rng, s), 2500, 9000, -2) * (0.3 + 0.7 * smooth(rng, s, 0.4)) * 0.35
    return norm(wind(rng, s) + grass)


def night_bed(rng):
    s = 70
    out = wind(rng, s, 60, 500) * 0.6
    for k in range(5):  # crickets: groups of short 4-5 kHz pulses, each at its own pace
        f = rng.uniform(4200, 5200)
        period = rng.uniform(0.7, 1.4)
        pulse = np.sin(2 * np.pi * f * t(0.018)) * env(int(0.018 * RATE), 0.003, 0.008)
        level = rng.uniform(0.15, 0.4)
        at = rng.uniform(0, period)
        while at < s - 0.2:
            for p in range(rng.integers(2, 5)):
                place(out, pulse * level, at + p * 0.035)
            at += period * rng.uniform(0.85, 1.15)
    return norm(out)


def bird(rng):
    out = np.zeros(int(2.4 * RATE))
    at = 0.05
    for note in range(rng.integers(3, 8)):
        d = rng.uniform(0.06, 0.16)
        x = t(d)
        f0, f1 = rng.uniform(2500, 4500), rng.uniform(2500, 5500)
        f = f0 + (f1 - f0) * x / d
        trill = 1 + 0.04 * np.sin(2 * np.pi * rng.uniform(25, 45) * x)
        tone = np.sin(2 * np.pi * np.cumsum(f * trill) / RATE) * env(len(x), 0.01, 0.03)
        place(out, tone * rng.uniform(0.5, 1.0), at)
        at += d + rng.uniform(0.03, 0.14)
    return norm(out[:int((at + 0.2) * RATE)])


def banner(rng):
    s = 2.2
    flap = (0.5 + 0.5 * np.sin(2 * np.pi * rng.uniform(5, 8) * t(s))) ** 3
    x = band(noise(rng, s), 150, 2500, -3) * flap * env(int(s * RATE), 0.3, 0.6)
    return norm(x, 0.7)


def gust(rng):
    s = 3.2
    e = np.sin(np.pi * t(s) / s) ** 2
    return norm(band(noise(rng, s), 120, 1600, -4) * e, 0.7)


def owl(rng):
    out = np.zeros(int(2.6 * RATE))
    at = 0.05
    for hoot, (f, d) in enumerate([(380, 0.35), (360, 0.25), (370, 0.7)]):
        x = t(d)
        wob = 1 + 0.01 * np.sin(2 * np.pi * 6 * x)
        tone = np.sin(2 * np.pi * np.cumsum(f * wob) / RATE) + 0.25 * np.sin(4 * np.pi * np.cumsum(f * wob) / RATE)
        breath = band(noise(rng, d), 300, 1200) * 0.15
        place(out, (tone + breath) * env(len(x), 0.06, 0.12), at)
        at += d + (0.12 if hoot == 0 else 0.35)
    return norm(out)


def crow(rng):
    out = np.zeros(int(2.2 * RATE))
    at = 0.05
    for caw in range(rng.integers(2, 4)):
        d = rng.uniform(0.28, 0.4)
        x = t(d)
        f = 520 - 90 * x / d
        saw = 2 * ((np.cumsum(f) / RATE) % 1) - 1
        rough = 1 + 0.5 * np.sin(2 * np.pi * 70 * x)
        tone = band(saw * rough, 700, 2600) * env(len(x), 0.02, 0.08)
        place(out, tone, at)
        at += d + rng.uniform(0.15, 0.3)
    return norm(out)


def creak(rng):
    s = 1.8
    out = np.zeros(int(s * RATE))
    rate = np.linspace(rng.uniform(25, 40), rng.uniform(60, 110), int(s * RATE))
    phase = np.cumsum(rate) / RATE
    ticks = np.nonzero(np.diff(np.floor(phase)) > 0)[0]
    click = band(noise(rng, 0.012), 400, 2500) * env(int(0.012 * RATE), 0.001, 0.008)
    for i in ticks:
        if i + len(click) < len(out):
            out[i:i + len(click)] += click
    body = sum(np.sin(2 * np.pi * fr * t(s)) for fr in (180, 290, 470))
    return norm(band(out, 150, 3000) * (1 + 0.3 * body) * env(len(out), 0.1, 0.4), 0.7)


def clops(rng):
    s = 2.6
    out = np.zeros(int(s * RATE))
    knock = np.zeros(int(0.06 * RATE))
    knock[:int(0.03 * RATE)] = band(noise(rng, 0.03), 700, 4000) * env(int(0.03 * RATE), 0.001, 0.025)
    hoof = knock + 0.8 * np.sin(2 * np.pi * 160 * t(0.06)) * np.exp(-t(0.06) * 60)
    beat = rng.uniform(0.26, 0.32)  # a trot: hooves in pairs
    at = 0.05
    while at < s - 0.2:
        place(out, hoof * rng.uniform(0.7, 1.0), at)
        place(out, hoof * rng.uniform(0.5, 0.8), at + 0.07)
        at += beat * rng.uniform(0.95, 1.05)
    return norm(out * env(len(out), 0.2, 0.6), 0.7)


def waves(rng):
    s = 6.0
    x = t(s)
    swell = np.clip(x / 2.2, 0, 1) ** 2
    crash = np.exp(-np.clip(x - 2.2, 0, None) * 0.9) * (x >= 2.2)
    e = np.where(x < 2.2, swell * 0.5, 0.5 + crash * 0.5)
    roar = band(noise(rng, s), 80, 6000, -3) * e
    hiss = band(noise(rng, s), 2500, 10000) * np.clip(crash, 0, 1) * 0.4
    return norm((roar + hiss) * env(len(x), 0.3, 1.2), 0.7)


def river(rng):
    s = 5.0
    out = band(noise(rng, s), 300, 3500, -2) * (0.4 + 0.6 * smooth(rng, s, 3)) * 0.5
    for k in range(int(s * 18)):  # bubbles: short rising blips
        d = rng.uniform(0.02, 0.06)
        x = t(d)
        f = rng.uniform(300, 1400) * (1 + 0.6 * x / d)
        blip = np.sin(2 * np.pi * np.cumsum(f) / RATE) * env(len(x), 0.004, 0.02)
        place(out, blip * rng.uniform(0.1, 0.35), rng.uniform(0, s - d))
    return norm(out * env(len(out), 0.6, 1.2), 0.7)


SOUNDS = {
    "day/bed": day_bed, "day/birds_1": bird, "day/birds_2": bird, "day/birds_3": bird,
    "day/banner": banner, "day/gust": gust,
    "night/bed": night_bed, "night/owl": owl, "night/crow": crow, "night/creak": creak, "night/gust": gust,
    "any/clops_1": clops, "any/clops_2": clops, "any/waves_1": waves, "any/waves_2": waves,
    "any/river_1": river, "any/river_2": river,
}


def write(path: str, x: np.ndarray) -> None:
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes((np.clip(x, -1, 1) * 32767).round().astype("<i2").tobytes())


if __name__ == "__main__":
    names = sys.argv[1:] or list(SOUNDS)
    for i, name in enumerate(SOUNDS):
        if name not in names and name.split("/")[-1] not in names:
            continue
        rng = np.random.default_rng(1000 + i)  # each sound its own seed, so one can be redone alone
        x = SOUNDS[name](rng)
        write(os.path.join(OUT, name + ".wav"), x)
        print("%-14s %.1f s" % (name, len(x) / RATE))
