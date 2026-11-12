"""Draft music as General MIDI (ROADMAP M5 session 1).

Writes data/audio/midi/<cue>.mid for the main map theme (day) and three stingers,
from the cue list in data/audio-asset-list.csv (bars, tempo, instruments, direction).
No libraries: a small Standard MIDI File writer is below. Render the files with
tools/render_audio.py.

    python tools/midi_draft.py
"""
import os
import struct

OUT = os.path.join(os.path.dirname(__file__), "..", "data", "audio", "midi")
TPB = 480  # ticks per beat

# General MIDI programs (0-based) and drum notes
TRUMPET, TROMBONE, FRENCH_HORN, BRASS = 56, 57, 60, 61
STRINGS, PIZZICATO, TIMPANI = 48, 45, 47
GLOCKENSPIEL, TUBULAR_BELLS, BANJO, ACOUSTIC_BASS = 9, 14, 105, 32
KICK, SNARE, CRASH = 36, 38, 49
DRUMS = 9  # the drum channel

NOTE = {"C": 0, "D": 2, "E": 4, "F": 5, "G": 7, "A": 9, "B": 11}


def n(name: str) -> int:
    """'F#5' -> 78 (C4 = 60)."""
    pitch = NOTE[name[0]]
    rest = name[1:]
    while rest and rest[0] in "#b":
        pitch += 1 if rest[0] == "#" else -1
        rest = rest[1:]
    return pitch + 12 * (int(rest) + 1)


CHORDS = {  # root, then the triad (or 7th) as pitch classes above C
    "D": ["D", "F#", "A"], "G": ["G", "B", "D"], "A": ["A", "C#", "E"], "A7": ["A", "C#", "E", "G"],
    "Bm": ["B", "D", "F#"], "F#m": ["F#", "A", "C#"], "Em": ["E", "G", "B"],
}


class Track:
    def __init__(self, name: str, channel: int, program: int | None):
        self.name, self.channel, self.program = name, channel, program
        self.events = []  # (tick, order, bytes)

    def note(self, beat: float, length: float, pitch: int, vel: int) -> None:
        on, off = round(beat * TPB), round((beat + length) * TPB) - 1
        self.events.append((on, 1, bytes([0x90 | self.channel, pitch, vel])))
        self.events.append((off, 0, bytes([0x80 | self.channel, pitch, 0])))

    def line(self, beat: float, notes: list, vel: int) -> float:
        """Plays [(name or None for a rest, beats), ...] from `beat`; returns where it ends."""
        for name, length in notes:
            if name:
                self.note(beat, length * 0.95, n(name), vel)
            beat += length
        return beat

    def bend(self, beat: float, semitones: float) -> None:
        """Pitch bend (the default range is +-2 semitones)."""
        v = max(0, min(16383, round(8192 + semitones / 2.0 * 8191)))
        self.events.append((round(beat * TPB), 2, bytes([0xE0 | self.channel, v & 0x7F, v >> 7])))

    def chunk(self) -> bytes:
        body = bytearray()
        body += _vlq(0) + b"\xff\x03" + _vlq(len(self.name)) + self.name.encode()
        if self.program is not None:
            body += _vlq(0) + bytes([0xC0 | self.channel, self.program])
        last = 0
        for tick, _, data in sorted(self.events, key=lambda e: (e[0], e[1])):
            body += _vlq(tick - last) + data
            last = tick
        body += _vlq(0) + b"\xff\x2f\x00"
        return b"MTrk" + struct.pack(">I", len(body)) + bytes(body)


def _vlq(v: int) -> bytes:
    out = [v & 0x7F]
    v >>= 7
    while v:
        out.append(0x80 | (v & 0x7F))
        v >>= 7
    return bytes(reversed(out))


def write(cue: str, bpm: float, tracks: list, beats: float) -> None:
    """A format 1 file: a tempo track, then one track per part. `beats` is the cue's
    length, stored as a marker the render tool reads for loop and trim points."""
    tempo = bytearray(_vlq(0) + b"\xff\x51\x03" + struct.pack(">I", round(60_000_000 / bpm))[1:])
    tempo += _vlq(0) + b"\xff\x58\x04\x04\x02\x18\x08"  # 4/4
    tempo += _vlq(round(beats * TPB)) + b"\xff\x06" + _vlq(3) + b"end"  # marker: the cue's end
    tempo += _vlq(0) + b"\xff\x2f\x00"
    data = b"MThd" + struct.pack(">IHHH", 6, 1, len(tracks) + 1, TPB)
    data += b"MTrk" + struct.pack(">I", len(tempo)) + bytes(tempo)
    for t in tracks:
        data += t.chunk()
    os.makedirs(OUT, exist_ok=True)
    with open(os.path.join(OUT, cue + ".mid"), "wb") as f:
        f.write(data)
    print("wrote %s.mid (%.1f s at %g BPM)" % (cue, beats * 60 / bpm, bpm))


def voicing(chord: str, low: str) -> list:
    """The chord's notes stacked upward from the octave of `low` (e.g. 'D3')."""
    base = n(low)
    out = []
    for name in CHORDS[chord]:
        p = n(name + "0")
        while p < base:
            p += 12
        out.append(p)
    return sorted(out)


# --- Main map theme (day) -------------------------------------------------------------
# 32 bars at 112, D major: A (the main motif) A' B (horn melody) A'' ending on the
# dominant so it loops back to bar 1. Trumpet, French horn, strings, pizzicato, light snare.

DAY_CHORDS = [  # one entry per bar; a list splits the bar into halves
    "D", "G", "D", "A", "D", "G", "A", "D",
    "D", "Bm", "G", "A", "D", "Bm", ["G", "A"], "D",
    "G", "A", "F#m", "Bm", "G", "A", "Em", "A7",
    "D", "G", "D", "A", "D", "G", "A", "A7",
]

MOTIF = [("A4", .5), ("A4", .5), ("D5", 1), ("F#5", 1.5), ("E5", .5)]  # the score's main motif

TRUMPET_A = MOTIF + [
    ("D5", 1.5), ("B4", .5), ("G4", 2),
    ("A4", .5), ("A4", .5), ("D5", 1), ("F#5", 1), ("A5", 1),
    ("E5", 1.5), ("C#5", .5), ("A4", 2),
    ("F#5", 1), ("E5", .5), ("D5", .5), ("F#5", 1), ("A5", 1),
    ("B5", 1.5), ("A5", .5), ("G5", 1), ("B4", 1),
]
TRUMPET_SECTIONS = [
    TRUMPET_A + [("A4", 1), ("C#5", 1), ("E5", 1), ("G5", 1), ("F#5", 2), ("D5", 1), (None, 1)],
    MOTIF + [
        ("D5", 1.5), ("B4", .5), ("F#4", 2),
        ("G4", .5), ("B4", .5), ("D5", 1), ("G5", 1.5), ("F#5", .5),
        ("E5", 2), ("C#5", 1), ("A4", 1),
    ] + MOTIF + [
        ("F#5", 1), ("D5", 1), ("B4", 1), ("D5", 1),
        ("B4", 1), ("D5", 1), ("C#5", 1), ("E5", 1),
        ("D5", 3), (None, 1),
    ],
    [(None, 24),  # B: the horn has the tune; the trumpet comes back for the turn
     ("B4", .5), ("B4", .5), ("E5", 1), ("G5", 1), ("E5", 1),
     ("A4", .5), ("A4", .5), ("C#5", .5), ("E5", .5), ("G5", 1), ("A5", 1)],
    TRUMPET_A + [("A4", 1), ("C#5", 1), ("E5", 1), ("A5", 1), ("G5", 2), ("E5", 1), ("C#5", 1)],
]
HORN_B = [
    ("B4", 2), ("D5", 1), ("B4", 1),
    ("C#5", 2), ("E5", 1), ("C#5", 1),
    ("A4", 1.5), ("F#4", .5), ("A4", 1), ("C#5", 1),
    ("B4", 3), ("F#4", 1),
    ("G4", 1), ("B4", 1), ("D5", 2),
    ("E5", 1.5), ("D5", .5), ("C#5", 1), ("A4", 1),
    ("G4", 2), ("B4", 2),
    ("A4", 2), ("C#5", 2),
]


def day_theme(reps: int = 1) -> tuple:
    trumpet = Track("Trumpet", 0, TRUMPET)
    horn = Track("French Horn", 1, FRENCH_HORN)
    strings = Track("Strings", 2, STRINGS)
    pizz = Track("Pizzicato", 3, PIZZICATO)
    drums = Track("Snare", DRUMS, None)
    bars = len(DAY_CHORDS)
    for rep in range(reps):
        start = rep * bars * 4
        beat = start
        for section in TRUMPET_SECTIONS:
            beat = trumpet.line(beat, section, 100)
        horn.line(start + 64, HORN_B, 92)
        for bar, chord in enumerate(DAY_CHORDS):
            b = start + bar * 4
            halves = chord if isinstance(chord, list) else [chord, chord]
            in_b = 16 <= bar < 24
            for h, c in enumerate(halves):
                # strings: the chord, held; a little fuller in B
                for p in voicing(c, "D3"):
                    strings.note(b + h * 2, 1.95, p, 62 if in_b else 52)
                # horn: chord tones under the trumpet, outside B
                if not in_b:
                    horn.note(b + h * 2, 1.9, voicing(c, "E4")[0], 70)
                # pizzicato: root and fifth
                root = voicing(c, "D2")[0]
                fifth = n(CHORDS[c][2] + "0")
                while fifth <= root:
                    fifth += 12
                pizz.note(b + h * 2, .5, root, 84)
                pizz.note(b + h * 2 + 1, .5, fifth, 72)
            # light snare: 2 and 4, a pickup into the next bar, a soft kick on 1 and 3
            drums.note(b + 1, .25, SNARE, 58)
            drums.note(b + 3, .25, SNARE, 58)
            drums.note(b + 3.5, .25, SNARE, 40)
            if not in_b:
                drums.note(b, .25, KICK, 64)
                drums.note(b + 2, .25, KICK, 54)
        if rep == 0:
            drums.note(start, .5, CRASH, 50)  # only the very first downbeat
    return [trumpet, horn, strings, pizz, drums], bars * 4


# --- Stingers --------------------------------------------------------------------------

def victory_riff() -> tuple:
    """1 bar at 120: a trumpet fanfare on the motif's notes, timpani under it."""
    t1, t2 = Track("Trumpet 1", 0, TRUMPET), Track("Trumpet 2", 1, TRUMPET)
    timp = Track("Timpani", 2, TIMPANI)
    third = 1 / 3
    t1.line(0, [("A4", third), ("A4", third), ("A4", third), ("D5", .5), ("F#5", .5), ("A5", 2)], 110)
    t2.line(0, [(None, 2), ("F#5", 2)], 96)
    t2.line(0, [(None, 1), ("A4", .5), ("D5", .5)], 90)
    for k in range(4):
        timp.note(k * .25, .25, n("A2"), 70 + k * 6)
    timp.note(1, .5, n("D2"), 104)
    timp.note(2, 2, n("D2"), 96)
    return [t1, t2, timp], 4


def town_riff() -> tuple:
    """2 bars at 130: a bouncy banjo with two pitch-bent 'boings', a plucked bass."""
    banjo = Track("Banjo", 0, BANJO)
    bass = Track("Bass", 1, ACOUSTIC_BASS)
    banjo.line(0, [("D4", .5), ("D4", .5), ("A4", 1), ("F#4", .5), ("A4", .5), ("B4", .5), ("A4", .5),
                   ("F#4", .5), ("E4", .5), ("D4", 1), (None, .5), ("D5", 1.5)], 104)
    for at in (1, 7.5):  # boing: start a tone low and spring up to the note
        banjo.bend(at, -1.5)
        for k in range(1, 7):
            banjo.bend(at + k * .04, -1.5 + k * .3)
        banjo.bend(at + .4, 0)
    bass.line(0, [("D2", 1), ("A2", 1), ("D2", 1), ("A2", 1), ("D2", 1), ("A2", 1), ("D2", 2)], 92)
    return [banjo, bass], 8


def hidden_item_sound() -> tuple:
    """1 bar at 140: glockenspiel running up, then tubular bells ringing in sequence."""
    glock = Track("Glockenspiel", 0, GLOCKENSPIEL)
    bells = Track("Tubular Bells", 1, TUBULAR_BELLS)
    glock.line(0, [(p, .25) for p in ["D5", "F#5", "A5", "D6", "E6", "F#6", "A6"]] + [("D7", 2.25)], 96)
    bells.line(1.75, [("A5", .5), ("F#5", .5), ("D6", 1.25)], 88)
    return [glock, bells], 4


if __name__ == "__main__":
    tracks, beats = day_theme()
    write("map_day", 112, tracks, beats)
    write("victory_riff", 120, *victory_riff())
    write("town_riff", 130, *town_riff())
    write("hidden_item", 140, *hidden_item_sound())
