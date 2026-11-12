"""Original backing track + key sounds for the LingoSphere intro video.

Everything is synthesised here (no samples), 120 BPM, downbeat at 1.5 s where
the typing starts. Scene changes and key presses come from the stage logs.
"""
import re
import sys
import wave

import numpy as np

SR = 44100
BEAT = 0.5
START = 1.5      # first downbeat (title card ends)
END_HIT = 17.0   # closing card
TOTAL = 19.0
rng = np.random.default_rng(7)

left = np.zeros(int(SR * (TOTAL + 1)))
right = np.zeros_like(left)


def add(sig, t, gain=1.0, pan=0.0):
    i = int(t * SR)
    if i < 0:
        sig = sig[-i:]
        i = 0
    n = min(len(sig), len(left) - i)
    if n <= 0:
        return
    left[i:i + n] += sig[:n] * gain * (1 - max(0, pan))
    right[i:i + n] += sig[:n] * gain * (1 + min(0, pan))


def tone(freq, dur, harmonics=(1.0,), decay=None, attack=0.004):
    t = np.arange(int(dur * SR)) / SR
    sig = sum(a * np.sin(2 * np.pi * freq * (h + 1) * t) for h, a in enumerate(harmonics))
    env = np.minimum(1, t / attack)
    if decay:
        env = env * np.exp(-t / decay)
    fade = np.minimum(1, (dur - t) / 0.01)
    return sig * env * fade


def noise(dur, decay, highpass=True):
    n = rng.standard_normal(int(dur * SR))
    if highpass:
        n = np.diff(n, prepend=0)
    t = np.arange(len(n)) / SR
    return n * np.exp(-t / decay)


def kick():
    t = np.arange(int(0.28 * SR)) / SR
    freq = 46 + 95 * np.exp(-t / 0.035)
    return np.sin(2 * np.pi * np.cumsum(freq) / SR) * np.exp(-t / 0.11)


def note(semitones_from_a4):
    return 440.0 * 2 ** (semitones_from_a4 / 12)


# chords: C  Am  F  G  (semitones from A4 for root in the bass octave, and triad)
CHORDS = [
    (-33, [3, 7, 10]),    # C:  C E G
    (-36, [0, 3, 7]),     # Am: A C E
    (-40, [-4, 0, 3]),    # F:  F A C
    (-38, [-2, 2, 5]),    # G:  G B D
]

# ---- intro pickup (title card)
add(noise(1.5, 9.0) * np.linspace(0, 1, int(1.5 * SR)) ** 2, 0.0, 0.05)
for i, semi in enumerate([3, 7, 10, 15]):
    add(tone(note(semi), 0.5, (1, 0.4, 0.15), decay=0.22), 0.15 + i * 0.33, 0.16, pan=(-0.4, 0.4)[i % 2])

# ---- groove
beat_times = np.arange(START, END_HIT - 1e-6, BEAT)
duck = np.ones_like(left)
for index, t in enumerate(beat_times):
    add(kick(), t, 0.80)
    i = int(t * SR)
    n = int(0.22 * SR)
    duck[i:i + n] *= 1 - 0.55 * np.exp(-np.arange(n) / SR / 0.07)
    if index % 2 == 1:
        add(noise(0.2, 0.045), t, 0.13)
    add(noise(0.06, 0.012), t + BEAT / 2, 0.06, pan=0.25)

music_l = np.zeros_like(left)
music_r = np.zeros_like(left)


def madd(sig, t, gain, pan=0.0):
    i = int(t * SR)
    n = min(len(sig), len(left) - i)
    music_l[i:i + n] += sig[:n] * gain * (1 - max(0, pan))
    music_r[i:i + n] += sig[:n] * gain * (1 + min(0, pan))


bars = int(np.ceil((END_HIT - START) / (4 * BEAT)))
for bar in range(bars):
    root, triad = CHORDS[bar % 4]
    bar_start = START + bar * 4 * BEAT
    for eighth in range(8):
        t = bar_start + eighth * BEAT / 2
        if t >= END_HIT:
            break
        if eighth in (0, 3, 5, 6):
            madd(tone(note(root), 0.24, (1, 0.5, 0.2), decay=0.16), t, 0.42)
    for sixteenth in range(16):
        t = bar_start + sixteenth * BEAT / 4
        if t >= END_HIT:
            break
        semi = triad[(0, 1, 2, 1, 2, 0, 1, 2)[sixteenth % 8]] + (12 if sixteenth % 8 in (4, 6) else 0)
        madd(tone(note(semi), 0.3, (1, 0.35, 0.2, 0.08), decay=0.085), t, 0.085,
             pan=0.5 if sixteenth % 2 else -0.5)
    length = min(4 * BEAT, END_HIT - bar_start)
    for semi in triad:
        madd(tone(note(semi - 12), length, (1, 0.25), attack=0.08), bar_start, 0.045)

# echo on the melodic layer
delay = int(0.375 * SR)
for buf in (music_l, music_r):
    buf[delay:] += 0.28 * buf[:-delay].copy()
left += music_l * duck
right += music_r * duck

# ---- scene accents
scene_times = [START] + [float(a) for a in sys.argv[2].split(",")]
for t in scene_times:
    sweep = noise(0.3, 5.0) * np.linspace(0, 1, int(0.3 * SR)) ** 3
    add(sweep, t - 0.3, 0.07)
    add(noise(0.9, 0.22), t, 0.10)

# ---- closing chord
for semi in (-21, -9, 3, 7, 10, 15):
    add(tone(note(semi), 2.0, (1, 0.4, 0.2, 0.1), decay=0.75, attack=0.006), END_HIT, 0.11,
        pan=0.3 if semi % 2 else -0.3)
add(noise(1.6, 0.45), END_HIT, 0.14)
add(kick(), END_HIT, 0.85)

# ---- key sounds from the stage logs: "<time> <name>" per line
for line in open(sys.argv[1]):
    match = re.match(r"([\d.]+) (\w+)", line)
    if not match:
        continue
    t, name = float(match.group(1)), match.group(2)
    if name == "key":
        click = tone(2100 + rng.uniform(-150, 150), 0.03, (1, 0.5), decay=0.006, attack=0.0005)
        add(click + noise(0.03, 0.004) * 0.25, t, 0.16, pan=rng.uniform(-0.2, 0.2))
    elif name == "open":
        add(tone(note(15), 0.18, (1, 0.3), decay=0.06), t, 0.20)
    elif name == "commit":
        add(tone(note(19), 0.5, (1, 0.25, 0.1), decay=0.12), t, 0.22)
        add(tone(note(27), 0.6, (1, 0.25, 0.1), decay=0.16), t + 0.07, 0.22)

# ---- master
n = int(TOTAL * SR)
mix = np.stack([left[:n], right[:n]], axis=1)
mix = np.tanh(mix * 1.5)
mix /= np.max(np.abs(mix)) / 0.89
fade = int(0.5 * SR)
mix[-fade:] *= np.linspace(1, 0, fade)[:, None]
mix[:int(0.02 * SR)] *= np.linspace(0, 1, int(0.02 * SR))[:, None]
with wave.open(sys.argv[3], "wb") as out:
    out.setnchannels(2)
    out.setsampwidth(2)
    out.setframerate(SR)
    out.writeframes((mix * 32767).astype("<i2").tobytes())
print("wrote", sys.argv[3], "seconds", n / SR)
