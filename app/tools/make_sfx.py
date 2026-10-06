"""Generate the placeholder sound effects in app/assets/audio/.

Standard library only (wave, math, struct). Every effect is a short mono
16-bit WAV at 22.05 kHz built from sine/square tones with simple envelopes,
so the whole set stays well under 200 KB.

These are PLACEHOLDERS. To use real sounds, drop files with the same names
into assets/audio/ (same format is simplest: .wav) - no code change needed.
The file for each effect is named in `Sounds.assetFor` in
lib/settings/app_settings.dart, and test/sfx_assets_test.dart fails if one
is missing.

Run from anywhere:  python app/tools/make_sfx.py
"""

import math
import os
import random
import struct
import wave

RATE = 22050
OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "assets", "audio")


def tone(freq, dur, vol=0.5, shape="sine", attack=0.005, release=0.05, slide_to=None):
    """One note as a list of floats in [-1, 1]."""
    n = int(RATE * dur)
    out = []
    phase = 0.0
    for i in range(n):
        t = i / RATE
        f = freq if slide_to is None else freq + (slide_to - freq) * (i / max(1, n - 1))
        phase += 2 * math.pi * f / RATE
        if shape == "square":
            s = 1.0 if math.sin(phase) >= 0 else -1.0
            s *= 0.6  # squares are loud
        elif shape == "tri":
            s = 2 / math.pi * math.asin(math.sin(phase))
        else:
            s = math.sin(phase)
        env = 1.0
        if t < attack:
            env = t / attack
        elif t > dur - release:
            env = max(0.0, (dur - t) / release)
        out.append(s * env * vol)
    return out


def noise(dur, vol=0.3, release=0.05, seed=321):
    rnd = random.Random(seed)
    n = int(RATE * dur)
    out = []
    for i in range(n):
        t = i / RATE
        env = max(0.0, 1 - t / dur) if release is None else (
            1.0 if t < dur - release else max(0.0, (dur - t) / release))
        out.append((rnd.random() * 2 - 1) * vol * env)
    return out


def silence(dur):
    return [0.0] * int(RATE * dur)


def mix(*tracks):
    n = max(len(t) for t in tracks)
    return [sum(t[i] for t in tracks if i < len(t)) for i in range(n)]


def seq(*parts):
    out = []
    for p in parts:
        out.extend(p)
    return out


def write(name, samples):
    os.makedirs(OUT, exist_ok=True)
    path = os.path.join(OUT, name + ".wav")
    peak = max(1e-9, max(abs(s) for s in samples))
    scale = min(1.0, 0.9 / peak)
    frames = b"".join(
        struct.pack("<h", int(max(-1.0, min(1.0, s * scale)) * 32767)) for s in samples
    )
    with wave.open(path, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(frames)
    print(f"{name + '.wav':18} {os.path.getsize(path):7d} bytes")


# Note frequencies (equal temperament).
C5, D5, E5, F5, G5, A5, B5 = 523.25, 587.33, 659.25, 698.46, 783.99, 880.0, 987.77
C6, E6, G6 = 1046.5, 1318.5, 1568.0
C4, E4, G4 = 261.63, 329.63, 392.0


EFFECTS = {
    # A soft click for a keyboard key - very short so fast typing stays clean.
    "tap": lambda: mix(tone(1800, 0.025, 0.35, "tri", 0.001, 0.02),
                       noise(0.012, 0.15, None)),
    # Rising major third: "yes".
    "correct": lambda: seq(tone(E5, 0.08, 0.5, "tri", 0.003, 0.03),
                           tone(B5, 0.16, 0.5, "tri", 0.003, 0.1)),
    # Low falling buzz: "no".
    "wrong": lambda: tone(220, 0.22, 0.45, "square", 0.003, 0.08, slide_to=150),
    # Crowd-ish burst plus a bright fanfare.
    "goal": lambda: mix(
        seq(tone(G5, 0.1, 0.4, "square", 0.003, 0.03),
            tone(C6, 0.1, 0.4, "square", 0.003, 0.03),
            tone(E6, 0.35, 0.4, "square", 0.003, 0.2)),
        noise(0.6, 0.12, None, seed=7)),
    # Two neutral descending notes: the round ended with no goal.
    "round_over": lambda: seq(tone(G4, 0.14, 0.5, "tri", 0.005, 0.05),
                              tone(C4, 0.26, 0.5, "tri", 0.005, 0.16)),
    # Major arpeggio up to a held top note.
    "win": lambda: seq(tone(C5, 0.11, 0.45, "square", 0.003, 0.03),
                       tone(E5, 0.11, 0.45, "square", 0.003, 0.03),
                       tone(G5, 0.11, 0.45, "square", 0.003, 0.03),
                       tone(C6, 0.5, 0.45, "square", 0.003, 0.35)),
    # Slow sad slide down.
    "lose": lambda: seq(tone(G4, 0.18, 0.45, "tri", 0.005, 0.05),
                        tone(311.13, 0.18, 0.45, "tri", 0.005, 0.05),
                        tone(261.63, 0.45, 0.45, "tri", 0.005, 0.3, slide_to=240)),
    # The 3-2-1 countdown beat.
    "tick": lambda: tone(1000, 0.06, 0.5, "sine", 0.002, 0.045),
    # Two quick bright pings: an opponent was found.
    "match_found": lambda: seq(tone(A5, 0.09, 0.45, "sine", 0.003, 0.04),
                               silence(0.03),
                               tone(E6, 0.22, 0.45, "sine", 0.003, 0.15)),
}


if __name__ == "__main__":
    for name, make in EFFECTS.items():
        write(name, make())
