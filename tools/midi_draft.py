"""Draft music as General MIDI (ROADMAP M5 session 1).

Writes data/audio/midi/<cue>.mid for the main map themes (day, night) and three stingers,
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
PIANO, SLAP_BASS, JAZZ_GUITAR, FRETLESS_BASS = 0, 36, 26, 35
KICK, SIDE_STICK, SNARE, HAT, OPEN_HAT, CRASH = 36, 37, 38, 42, 46, 49
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
# Draft 2 (user's notes, 2026-11-12: more funk inside the pentatonic scale, more bass,
# less trumpet, piano instead of horn). 32 bars at 112, D major pentatonic (D E F# A B)
# for every melody note. A D-G vamp; A (trumpet motif, then rests) A' B (piano tune)
# A'' ending on A so it loops back. Slap bass leads the mix; a funk kit (16th hats,
# ghost snares, kicks off the beat); piano stabs on the 16ths. Draft 3 (user, same day):
# the trumpet's part on clean electric guitar, nothing else changed. Draft 4: jazz guitar.

DAY_CHORDS = [
    "D", "G", "D", "G", "D", "G", "Em", "A",
    "D", "G", "D", "G", "Bm", "G", "Em", "A",
    "Bm", "G", "Bm", "G", "Em", "G", "A", "A",
    "D", "G", "D", "G", "D", "G", "Em", "A",
]
PIANO_VOICING = {  # rootless, near middle C, mostly pentatonic tones
    "D": ["F#4", "A4", "B4", "E5"], "G": ["G4", "B4", "D5", "E5"], "Em": ["G4", "B4", "D5", "E5"],
    "Bm": ["A4", "B4", "D5", "F#5"], "A": ["G4", "A4", "D5", "E5"],
}
BASS_ROOT = {"D": "D2", "G": "G2", "Em": "E2", "Bm": "B1", "A": "A1"}

MOTIF = [("A4", .25), ("A4", .5), ("D5", .75), ("F#5", .5), ("E5", .5), ("D5", .5), (None, 1)]  # the main motif, funked
ANSWER = [(None, .5), ("B4", .25), ("D5", .25), ("E5", .5), ("D5", .5), ("B4", 1), (None, 1)]
REST = [(None, 4)]
TRUMPET_A = MOTIF + ANSWER + REST + REST + [
    ("A4", .25), ("A4", .5), ("D5", .75), ("F#5", .5), ("A5", .5), ("F#5", .5), (None, 1),
    (None, .5), ("E5", .25), ("F#5", .25), ("E5", .5), ("D5", .5), ("B4", 1), (None, 1),
] + REST
TRUMPET_SECTIONS = [
    TRUMPET_A + [(None, 2), ("E5", .5), ("D5", .5), ("B4", .5), ("A4", .5)],
    TRUMPET_A + [(None, 2), ("A4", .25), ("B4", .25), ("D5", .5), ("E5", 1)],
    REST * 7 + [(None, 2), ("A4", .25), ("B4", .25), ("D5", .5), ("E5", 1)],
    TRUMPET_A + [(None, 2), ("E5", .5), ("F#5", .5), ("A5", 1)],
]
PIANO_B = [  # the B tune, all pentatonic, syncopated
    ("B4", .75), ("D5", .25), ("E5", .5), ("D5", .5), ("B4", .5), ("A4", .5), ("B4", 1),
    (None, .5), ("D5", .25), ("E5", .25), ("D5", .5), ("B4", .5), ("D5", .75), ("E5", .25), ("D5", 1),
    ("F#5", .75), ("E5", .25), ("D5", .5), ("B4", .5), ("D5", .5), ("E5", .5), ("F#5", 1),
    ("A5", .5), ("F#5", .25), ("E5", .25), ("D5", 1), (None, 2),
    ("E5", .75), ("D5", .25), ("B4", .5), ("A4", .5), ("B4", .5), ("D5", .5), ("E5", 1),
    (None, .5), ("B4", .25), ("D5", .25), ("E5", .5), ("F#5", .5), ("E5", .75), ("D5", .25), ("B4", 1),
    ("A4", .5), ("B4", .25), ("D5", .25), ("E5", 1), ("D5", .5), ("B4", .5), ("A4", 1),
    (None, 4),
]
STABS = [(.5, .2), (1.25, .2), (2.5, .4), (3.25, .2), (3.75, .2)]  # piano comping, beat and length


def day_theme(reps: int = 1) -> tuple:
    trumpet = Track("Guitar", 0, JAZZ_GUITAR)  # draft 4: the lead on jazz guitar (draft 3: clean electric; 2: trumpet)
    piano = Track("Piano", 1, PIANO)
    bass = Track("Slap Bass", 2, SLAP_BASS)
    strings = Track("Strings", 3, STRINGS)
    drums = Track("Drums", DRUMS, None)
    bars = len(DAY_CHORDS)
    for rep in range(reps):
        start = rep * bars * 4
        beat = start
        for section in TRUMPET_SECTIONS:
            beat = trumpet.line(beat, section, 84)
        piano.line(start + 64, PIANO_B, 88)
        for bar, chord in enumerate(DAY_CHORDS):
            b = start + bar * 4
            in_b = 16 <= bar < 24
            last = bar == bars - 1
            # piano: stabs on the 16ths; in B, one soft chord under its own tune
            if in_b:
                for p in PIANO_VOICING[chord][:3]:
                    piano.note(b, 3.8, n(p) - 12, 48)
                for p in voicing(chord, "D3"):
                    strings.note(b, 3.95, p, 44)
            else:
                for at, length in STABS:
                    for p in PIANO_VOICING[chord]:
                        piano.note(b + at, length, n(p), 70 if at in (.5, 2.5) else 60)
            # slap bass: root, ghost, octave pop, fifth, and a chromatic step into the next bar
            r = n(BASS_ROOT[chord])
            nxt = n(BASS_ROOT[DAY_CHORDS[(bar + 1) % bars]])
            for at, p, length, vel in [
                (0, r, .45, 118), (.75, r, .2, 70), (1, r + 12, .2, 108), (1.5, r + 7, .2, 92),
                (2, r, .2, 104), (2.5, r, .2, 76), (2.75, r + 12, .2, 104), (3.25, r + 7, .2, 88),
                (3.5, r + 10 if chord in ("Em", "Bm") else r + 9, .2, 90), (3.75, nxt - 1, .2, 96),
            ]:
                bass.note(b + at, length, p, vel)
            # drums: 16th hats (accents on the 8ths), kick on 1, the "a" of 2 and the "and" of 3,
            # snare on 2 and 4 with ghosts; lighter in B; a snare fill into the loop
            for k in range(16):
                if in_b and k % 2:
                    continue
                drums.note(b + k * .25, .2, HAT, 72 if k % 2 == 0 else 46)
            for at, vel in [(0, 100), (1.75, 82), (2.5, 92)]:
                drums.note(b + at, .2, KICK, vel - (16 if in_b else 0))
            drums.note(b + 1, .2, SNARE, 98)
            drums.note(b + 3, .2, SNARE, 98)
            if not in_b:
                drums.note(b + 2.25, .2, SNARE, 34)
                drums.note(b + 3.75, .2, SNARE, 38)
            if bar % 2 == 1 and not in_b:
                drums.note(b + 3.5, .2, OPEN_HAT, 64)
            if last:
                for k in range(8):
                    drums.note(b + 2 + k * .25, .2, SNARE, 50 + k * 7)
        if rep == 0:
            drums.note(start, .5, CRASH, 56)  # only the very first downbeat
    return [trumpet, piano, bass, strings, drums], bars * 4


# --- Main map theme (night) -----------------------------------------------------------
# Draft 1 (user, 2026-11-12: just drum and bass to start, a more somber variant of the
# day theme). Same tempo and length as the day theme so they crossfade. The day's D-G
# vamp turned minor (Dm-Gm); a fretless bass carries the motif where the day's guitar
# does; a half-time kit (rimshot on 3, soft hats, few kicks); B thins out almost to
# nothing; bar 32 turns on A (a C#, the minor key's leading note) back to the top.

NIGHT_CHORDS = [
    "Dm", "Gm", "Dm", "Gm", "Dm", "Gm", "Bb", "A",
    "Dm", "Gm", "Dm", "Gm", "Dm", "Gm", "Bb", "A",
    "Bb", "Gm", "Bb", "Gm", "Gm", "Bb", "A", "A",
    "Dm", "Gm", "Dm", "Gm", "Dm", "Gm", "Bb", "A",
]
NIGHT_ROOT = {"Dm": "D2", "Gm": "G1", "Bb": "Bb1", "A": "A1"}
NIGHT_PHRASES = {  # bar of each 8-bar section -> the bass's phrase (the day's guitar bars)
    0: [("A2", .25), ("A2", .5), ("D3", .75), ("F3", .5), ("E3", .5), ("D3", .5), ("D2", 1)],  # the motif, minor
    1: [("G2", .5), ("Bb2", .25), ("D3", .25), ("F3", .5), ("D3", .5), ("Bb2", 1), ("G1", 1)],
    4: [("A2", .25), ("A2", .5), ("D3", .75), ("F3", .5), ("A3", .5), ("F3", .5), ("D2", 1)],
    5: [("G2", .5), ("F3", .25), ("G3", .25), ("F3", .5), ("D3", .5), ("Bb2", 1), ("G1", 1)],
    7: [("A1", 1), ("E2", .5), ("G2", .5), ("A2", .5), ("C#3", .5), ("E3", 1)],  # the turn back to Dm
}


def night_theme() -> tuple:
    bass = Track("Fretless Bass", 0, FRETLESS_BASS)
    drums = Track("Drums", DRUMS, None)
    for bar, chord in enumerate(NIGHT_CHORDS):
        b = bar * 4
        in_b = 16 <= bar < 24
        r = n(NIGHT_ROOT[chord])
        minor = chord.endswith("m")
        if not in_b and bar % 8 in NIGHT_PHRASES:
            bass.line(b, NIGHT_PHRASES[bar % 8], 96)
        elif in_b:  # long, low notes
            bass.note(b, 2.4, r, 92)
            bass.note(b + 2.5, .9, r + 7, 70)
            bass.note(b + 3.5, .45, r + 12, 62)
        else:  # the groove: a long root, a ghost, the fifth, the octave, a seventh (or fifth)
            for at, p, length, vel in [(0, r, 1.25, 100), (1.5, r, .2, 54), (1.75, r + 7, .7, 82),
                                       (2.75, r + 12, .45, 78), (3.5, r + (10 if minor else 7), .45, 72)]:
                bass.note(b + at, length, p, vel)
        # half-time kit: kick on 1 (and the "a" of 2), rimshot on 3, soft 8th hats
        for k in range(8):
            if in_b and k % 2:
                continue
            drums.note(b + k * .5, .2, HAT, 52 if k % 2 == 0 else 34)
        drums.note(b, .2, KICK, 96 if not in_b else 74)
        if not in_b:
            drums.note(b + 1.75, .2, KICK, 66)
        drums.note(b + 2, .2, SIDE_STICK, 88 if not in_b else 64)
        if bar % 4 == 3 and not in_b:
            drums.note(b + 3.5, .2, OPEN_HAT, 50)
        if bar == len(NIGHT_CHORDS) - 1:
            for k in range(4):
                drums.note(b + 3 + k * .25, .2, SIDE_STICK, 44 + k * 10)
    drums.note(0, .5, CRASH, 36)
    return [bass, drums], len(NIGHT_CHORDS) * 4


# --- Stingers --------------------------------------------------------------------------

def victory_riff() -> tuple:
    """Half a bar at 150 (draft 3, user 2026-11-12: four notes, shorter): a rising
    trumpet run on the motif's notes, a second trumpet under the top note, timpani, and a
    snare roll into a crash on the last note."""
    t1, t2 = Track("Trumpet 1", 0, TRUMPET), Track("Trumpet 2", 1, TRUMPET)
    timp = Track("Timpani", 2, TIMPANI)
    drums = Track("Drums", DRUMS, None)
    t1.line(0, [("A4", .25), ("D5", .25), ("F#5", .5), ("A5", 1)], 110)
    t2.line(1, [("F#5", 1)], 96)
    timp.note(0, .25, n("A2"), 80)
    timp.note(.5, .25, n("A2"), 90)
    timp.note(1, 1, n("D2"), 104)
    for k in range(8):  # 32nd notes over the first beat, rising
        drums.note(k * .125, .1, SNARE, 50 + k * 7)
    drums.note(1, .5, CRASH, 100)
    drums.note(1, .25, KICK, 100)
    return [t1, t2, timp, drums], 2


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
    """Half a bar at 140 (user, 2026-11-12: half the first draft's length, the bells'
    three notes on trumpet): a fast glockenspiel run up, then the trumpet answers."""
    glock = Track("Glockenspiel", 0, GLOCKENSPIEL)
    trumpet = Track("Trumpet", 1, TRUMPET)
    glock.line(0, [(p, .125) for p in ["D5", "F#5", "A5", "D6", "E6", "F#6", "A6"]] + [("D7", 1.125)], 96)
    trumpet.line(.875, [("A4", .25), ("F#4", .25), ("D5", .625)], 96)
    return [glock, trumpet], 2


if __name__ == "__main__":
    tracks, beats = day_theme()
    write("map_day", 112, tracks, beats)
    write("map_night", 112, *night_theme())
    write("victory_riff", 150, *victory_riff())
    write("town_riff", 130, *town_riff())
    write("hidden_item", 140, *hidden_item_sound())
