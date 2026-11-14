"""Map ambience: the pools of sparse piano phrases the map plays by day and by night
(docs/map-ambience.md).

Writes data/audio/midi/map/<state>_NN.mid (8 bars each) and the two turns between them,
dawn.mid and dusk.mid (4 bars). Day and night share one skeleton, the roots D C G D, two
bars a chord, so each answers the other:

- Day: open major chords with an added 9th (Dadd9, C, G, D), the upper notes in the
  middle and high register, a little brighter and busier; the main motif's opening
  (A D F# E) rising in every third phrase.
- Night: the same roots turned minor (Dm, C5, Gm, Dm), lower, slower and sparser; the
  motif minor and an octave down; now and then one dissonant color note (Eb, a half step
  over the root, or Ab, the tritone) left hanging.

Every phrase is 3 to 7 notes by day and 3 to 6 by night, sustain pedal down through each chord. The phrases are drawn
at random from a fixed seed, so the same command always writes the same files; change
--seed for a new set, or --count for more or fewer. Render them with
tools/build_map_audio.py (or tools/render_audio.py "map/day_*").

    python tools/map_phrases.py [--count 10] [--seed 1]
"""
import argparse
import os
import random

import midi_draft as md

OUT = os.path.join(md.OUT, "map")
CHORD_BEATS = 8  # two bars of 4/4 per chord, four chords: 8 bars
SLOTS = [1, 1.5, 2, 3, 3.5, 4, 5, 5.5, 6]  # where upper notes may fall inside a chord (beats)

STATES = {
    "day": {
        "bpm": 60,
        "roots": ["D3", "C3", "G2", "D3"],
        "chords": [["D", "E", "F#", "A"], ["C", "D", "E", "G"], ["G", "A", "B", "D"], ["D", "F#", "A", "E"]],
        "range": ("A3", "A5"),
        "motif": [("A4", 1.5), ("D5", 1.5), ("F#5", 2), ("E5", 3)],
        "root_chance": 0.6,  # a low root on a chord after the first
        "tones": [2, 3, 1],  # weights for 0, 1 or 2 upper notes per chord
        "notes": (3, 7),  # notes per phrase, fewest and most
        "vel": (38, 56),
        "colors": [],
    },
    "night": {
        "bpm": 54,
        "roots": ["D2", "C2", "G1", "D2"],
        "chords": [["D", "F", "A"], ["C", "G"], ["G", "Bb", "D"], ["D", "F", "A"]],
        "range": ("D3", "D5"),
        "motif": [("A3", 2), ("D4", 2), ("F4", 2.5), ("E4", 4)],
        "root_chance": 0.75,
        "tones": [3, 3, 1],
        "notes": (3, 6),
        "vel": (28, 46),
        "colors": ["Eb", "Ab"],
    },
}
MOTIF_EVERY = 3  # every third phrase states the motif; the others hint at it at most


def pitches(classes: list, low: str, high: str) -> list:
    """Every pitch of the given pitch classes between low and high."""
    lo, hi = md.n(low), md.n(high)
    out = []
    for c in classes:
        p = md.n(c + "0")
        while p <= hi:
            if p >= lo:
                out.append(p)
            p += 12
    return sorted(out)


def phrase(state: str, index: int, seed: int) -> list:
    """One 8-bar phrase: [(beat, pitch, velocity)], sorted by beat."""
    s = STATES[state]
    rng = random.Random("%s-%d-%d" % (state, seed, index))
    lo_v, hi_v = s["vel"]
    roots, uppers = [], []
    for ci in range(4):
        start = ci * CHORD_BEATS
        if ci == 0 or rng.random() < s["root_chance"]:
            roots.append((start + rng.choice([0, 0, 0, 0.5]), md.n(s["roots"][ci]), rng.randint(lo_v, hi_v)))
        pool = pitches(s["chords"][ci], *s["range"])
        k = rng.choices([0, 1, 2], weights=s["tones"])[0]
        for b in sorted(rng.sample(SLOTS, k)):
            uppers.append((start + b + rng.uniform(-0.06, 0.06), rng.choice(pool), rng.randint(lo_v, hi_v)))
    motif = []
    if index % MOTIF_EVERY == 0:
        # the motif over the first two chords, in place of whatever was drawn there
        uppers = [u for u in uppers if u[0] >= 2 * CHORD_BEATS]
        b = 2.0
        for name, length in s["motif"]:
            motif.append((b, md.n(name), min(127, hi_v + 6)))
            b += length
    fewest, most = s["notes"]
    while uppers and len(roots) + len(motif) + len(uppers) > most:
        uppers.pop(rng.randrange(len(uppers)))
    while len(roots) > 1 and len(roots) + len(motif) + len(uppers) > most:
        roots.pop(rng.randrange(1, len(roots)))  # the first chord keeps its root
    while len(roots) + len(motif) + len(uppers) < fewest:
        ci = rng.randrange(4)
        uppers.append((ci * CHORD_BEATS + rng.choice(SLOTS), rng.choice(pitches(s["chords"][ci], *s["range"])), rng.randint(lo_v, hi_v)))
    if s["colors"] and index % MOTIF_EVERY != 0 and rng.random() < 0.4:
        # one note turned to a dissonant color, never in the first chord
        late = [i for i, u in enumerate(uppers) if u[0] >= CHORD_BEATS]
        if late:
            i = rng.choice(late)
            b, p, v = uppers[i]
            uppers[i] = (b, min(pitches(s["colors"], *s["range"]), key=lambda c: abs(c - p)), v)
    return sorted(roots + motif + uppers)


def pedal(t: md.Track, beat: float, down: bool) -> None:
    t.events.append((round(beat * md.TPB), 2, bytes([0xB0 | t.channel, 64, 127 if down else 0])))


def piano(notes: list, span: float, chord_beats: float) -> md.Track:
    """A piano track: each note held to the end of its chord (the last chord rings on past
    the end), the pedal down through each chord and lifted just before the next."""
    t = md.Track("piano", 0, md.PIANO)
    chords = round(span / chord_beats)
    for ci in range(chords):
        pedal(t, ci * chord_beats + 0.02, True)
        if ci < chords - 1:
            pedal(t, (ci + 1) * chord_beats - 0.08, False)
    pedal(t, span + 6, False)
    for b, p, v in notes:
        end = (int(b // chord_beats) + 1) * chord_beats
        t.note(b, (end + 6 if end >= span else end - 0.1) - b, p, v)
    return t


# The turns: 4 bars, a chord a bar. Dusk is the day's progression ending minor; dawn is
# the night's ending major (the F# where F was).
DUSK = [(0, "D3", 44), (1.5, "F#4", 40), (4, "C3", 42), (6, "E4", 36), (8, "G2", 40), (9.5, "D4", 36),
        (12, "D2", 40), (12.6, "A3", 34), (13.2, "F4", 38)]
DAWN = [(0, "D2", 36), (1.5, "F4", 32), (4, "C2", 36), (6, "Eb4", 30), (8, "G1", 38), (9.5, "Bb3", 32),
        (12, "D3", 42), (12.6, "A4", 40), (13.2, "F#5", 44)]


def write(cue: str, bpm: float, notes: list, span: float, chord_beats: float) -> None:
    md.write("map/" + cue, bpm, [piano(notes, span, chord_beats)], span)


if __name__ == "__main__":
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--count", type=int, default=10, help="phrases per state (default 10)")
    ap.add_argument("--seed", type=int, default=1, help="a different seed draws a different set")
    a = ap.parse_args()
    os.makedirs(OUT, exist_ok=True)
    for old in os.listdir(OUT):
        if old.endswith(".mid"):
            os.remove(os.path.join(OUT, old))
    for state, s in STATES.items():
        for i in range(a.count):
            notes = phrase(state, i, a.seed)
            write("%s_%02d" % (state, i + 1), s["bpm"], notes, 4 * CHORD_BEATS, CHORD_BEATS)
    write("dusk", STATES["day"]["bpm"], [(b, md.n(p), v) for b, p, v in DUSK], 16, 4)
    write("dawn", STATES["night"]["bpm"], [(b, md.n(p), v) for b, p, v in DAWN], 16, 4)
