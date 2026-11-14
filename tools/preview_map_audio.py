"""Hear the map's ambience before the game plays it (docs/map-ambience.md).

Mixes a few minutes of what the map would sound like, from the rendered phrases
(data/audio/music/map/), the prepared ambience (data/audio/ambience/) and the settings in
data/audio.json "map_ambience" (gaps, rests, volumes), into one WAV in logs/ (git-ignored).
Tune the settings or the pools, run it again, listen. A part with no files yet (no
ambience prepared, say) is left out.

    python tools/preview_map_audio.py [--state day|night|cycle|title|victory] [--minutes 6] [--seed 1]

cycle: half the time by day, the dusk turn, then night (beds crossfading at the turn).
title, victory: those screens' beds (no ambience), the first phrase at once.
"""
import argparse
import glob
import json
import os
import random

import numpy as np

import render_audio as ra

ROOT = ra.ROOT
RATE = ra.RATE


def res(path: str) -> str:
    return os.path.join(ROOT, path.replace("res://", "").replace("/", os.sep))


def load(path: str) -> np.ndarray:
    rate, x = ra.read_wav(path)
    return ra.stereo(ra.resample(x, rate))


def db(v: float) -> float:
    return 10 ** (v / 20)


def add(mix: np.ndarray, x: np.ndarray, at: float, g: float, pan: float = 0.0) -> None:
    i = round(at * RATE)
    if i >= len(mix):
        return
    x = x[:len(mix) - i]
    lr = np.array([np.cos((pan + 1) * np.pi / 4), np.sin((pan + 1) * np.pi / 4)]) * np.sqrt(2)
    mix[i:i + len(x)] += x * g * lr


def phrases(mix: np.ndarray, cfg: dict, plan: list, rng: random.Random) -> float:
    """Lays the phrase pools along the plan [(state, start, end)]; returns the share of
    time a phrase was sounding."""
    folder = res(cfg["phrases"])
    pcs = {s: cfg["pools"][s] for s, _, _ in plan}
    pools = {s: [load(p) for p in sorted(glob.glob(os.path.join(folder, pc["prefix"] + "*.wav")))] for s, pc in pcs.items()}
    turns = {k: os.path.join(folder, v) for k, v in cfg["turns"].items()}
    t, last, sounding = (rng.uniform(2, 8) if "turn_in" in pcs[plan[0][0]] else 0.0), None, 0.0
    for i, (state, start, end) in enumerate(plan):
        pool, pc = pools[state], pcs[state]
        g = db(cfg["phrase_db"] + pc.get("db", 0.0))
        gap, rest = pc.get("gap", cfg["gap"]), pc.get("rest_chance", cfg["rest_chance"])
        if not pool:
            print("  no %s phrases in %s: render them first (tools/build_map_audio.py)" % (state, os.path.relpath(folder, ROOT)))
            t = end
            continue
        t = max(t, start)
        while t < end:
            if rng.random() < rest:
                t += len(pool[0]) / RATE
                continue
            k = rng.choice([j for j in range(len(pool)) if j != last] or [0])
            last = k
            add(mix, pool[k], t, g)
            sounding += len(pool[k]) / RATE
            t += len(pool[k]) / RATE + rng.uniform(*gap)
        turn = "dusk" if state == "day" else "dawn"
        if i + 1 < len(plan) and os.path.exists(turns[turn]):
            x = load(turns[turn])
            add(mix, x, t, g)
            sounding += len(x) / RATE
            t += len(x) / RATE + rng.uniform(*cfg["gap"]) / 2
            last = None
    return sounding / (len(mix) / RATE)


def ambience(mix: np.ndarray, cfg: dict, plan: list, rng: random.Random) -> None:
    folder = res(cfg["ambience"])
    fade = cfg["bed_fade"]
    for state, start, end in plan:
        if "ambience" not in cfg["pools"][state]:
            continue
        files = sorted(glob.glob(os.path.join(folder, cfg["pools"][state]["ambience"], "*.wav")))
        beds = [f for f in files if os.path.basename(f).lower().startswith("bed")]
        shots = [load(f) for f in files if f not in beds]
        if beds:
            bed = load(beds[0])
            a, b = round(max(0, start - fade / 2) * RATE), round(min(len(mix) / RATE, end + fade / 2) * RATE)
            reps = np.tile(bed, ((b - a) // len(bed) + 1, 1))[:b - a]
            env = np.ones(b - a)
            f = min(round(fade * RATE), (b - a) // 2)
            if start > 0:
                env[:f] = np.linspace(0, 1, f)
            if end < len(mix) / RATE:
                env[-f:] = np.linspace(1, 0, f)
            mix[a:b] += reps * env[:, None] * db(cfg["bed_db"])
        t = start + rng.uniform(*cfg["shot_gap"])
        while shots and t < end:
            x = shots[rng.randrange(len(shots))]
            pitch = 1 + rng.uniform(-cfg["shot_pitch"], cfg["shot_pitch"])
            src = np.arange(len(x))
            x = np.stack([np.interp(np.arange(0, len(x) - 1, pitch), src, x[:, c]) for c in range(2)], axis=1)
            add(mix, x, t, db(rng.uniform(*cfg["shot_db"])), rng.uniform(-cfg["shot_pan"], cfg["shot_pan"]))
            t += len(x) / RATE + rng.uniform(*cfg["shot_gap"])
        if not files:
            print("  no %s ambience in %s: add sounds and run tools/prepare_ambience.py" % (state, os.path.relpath(folder, ROOT)))


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--state", choices=["day", "night", "cycle", "title", "victory"], default="cycle")
    ap.add_argument("--minutes", type=float, default=6.0)
    ap.add_argument("--seed", type=int, default=1)
    ap.add_argument("--out", default="", help="default: logs/map_preview_<state>.wav")
    a = ap.parse_args()
    cfg = json.load(open(os.path.join(ROOT, "data", "audio.json"), encoding="utf-8"))["map_ambience"]
    seconds = a.minutes * 60
    plan = [("day", 0, seconds / 2), ("night", seconds / 2, seconds)] if a.state == "cycle" else [(a.state, 0, seconds)]
    rng = random.Random(a.seed)
    mix = np.zeros((round(seconds * RATE), 2))
    share = phrases(mix, cfg, plan, rng)
    ambience(mix, cfg, plan, rng)
    peak = np.abs(mix).max()
    if peak > ra.PEAK:
        mix *= ra.PEAK / peak
    out = a.out or os.path.join(ROOT, "logs", "map_preview_%s.wav" % a.state)
    ra.save(out, mix, 1.0)
    print("%s: %.1f min, music sounding %d%% of the time -> %s" % (a.state, a.minutes, round(share * 100), os.path.relpath(out, ROOT)))
