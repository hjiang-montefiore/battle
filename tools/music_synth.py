#!/usr/bin/env python3
"""Procedural soundtrack. Pure stdlib, deterministic, composed -- not noise.

    python3 tools/music_synth.py            # writes game/assets/audio/music/*.wav
    python3 tools/music_synth.py --list     # the score plan and playback contract

This EXTENDS tools/audio_synth.py -- same Rng, env(), sine/sweep/noise,
lowpass, same determinism promise (byte-identical re-runs).  Where that file
makes sound effects, this one makes a SCORE: a shared key and tempo, a written
motif, and five-plus-two pieces built from the same harmonic system, so the
game can crossfade between emotional states without a key clash.

THE HARMONIC SYSTEM (stated, per the craft brief)
-------------------------------------------------
  KEY    D minor (natural).  Scale D E F G A Bb C.
  TEMPO  battle layers share 84 BPM, 4/4  (beat = 0.7143 s, bar = 2.8571 s).
         The menu runs at 72 BPM -- it never crossfades with battle music.
  MOTIF  four bars, written as note data in MOTIF below:
             D--F E | D--C D | G--F E | D------
         Every track quotes it: the menu states it twice on "brass", calm
         mutters the first phrase at half speed in a low register, action
         fragments it into stabs and plays it whole once, sting_epoch
         resolves it upward through a Picardy D major.
  LOOPS  battle_calm and battle_action are exactly 42 bars = 120.000 s;
         battle_peril is exactly 21 bars = 60.000 s.  Loop seams are
         seamless BY CONSTRUCTION: every event is placed with wrap-around
         (note tails past the end land at the start), and continuous drones
         have their frequencies snapped to a whole number of cycles per
         loop, so sample[0] follows sample[-1] as smoothly as any two
         adjacent samples.  verify() asserts this.
  MIX    music is normalised to peak 0.22 (~ -12.1 dB below the SFX bank's
         0.89).  The game's SFX sit ON TOP of this; do not boost the music
         bus to compensate.

PLAYBACK CONTRACT (for the UI/game team -- the player gets wired later)
-----------------------------------------------------------------------
  menu_theme      main menu + lobby.  90 s, plays once; on repeat, restart
                  after ~4 s of silence with a 2 s fade-in.  Stop with a 1 s
                  fade when the match loads.
  battle_calm /   Start BOTH at match start, sample-locked to one shared
  battle_action   playhead (both are exactly 120.000 s loops at 84 BPM), calm
                  at full music gain, action at 0.  On combat (any weapon
                  fired by or at the player's units in the last 8 s):
                  equal-power crossfade calm->action over 2.0 s.  Combat over:
                  crossfade back over 4.0 s.  Never restart the playhead
                  mid-match -- only move gains.
  battle_peril    ADDITIVE layer above action, not a replacement.  Exactly
                  60.000 s, so phase-lock it too: peril playhead = shared
                  playhead mod 60.  While the player's collapse timer runs,
                  fade it in over 2.0 s at 0.7 gain; fade out over 3.0 s when
                  the timer clears.
  sting_contact   fire-and-forget on the FIRST enemy contact of a match
                  (once per match).  Plays over whatever music is running.
  sting_epoch     fire-and-forget on each epoch advance.
  victory/defeat  already exist in audio_synth.py -- NOT duplicated here.
  Music bus at 1.0: the -12 dB headroom is baked into the files.

WHY IT SOUNDS THE WAY IT DOES
-----------------------------
War-film language, not chiptune: "strings" are detuned saw pairs through a
one-pole lowpass (the detune beats slowly, which is what reads as a section
rather than an organ); "brass" is the same saw pair with a slower attack and
a brighter cutoff; percussion is shaped noise exactly like audio_synth's kit
(kick = sine sweep + low noise thump, military snare = banded noise over a
190 Hz shell); the calm layer's pings are the sonar_ping idiom pulled into
key, because in this game a sonar ping IS music to somebody.
"""
import argparse
import math
import os
import struct
import sys
import wave
from functools import lru_cache

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from audio_synth import (RATE, Rng, apply_env, env, gain, highpass, lowpass,
                         mix, noise, normalise, sine, sweep)

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, "game", "assets", "audio", "music")

# ── the stated system ──────────────────────────────────────────────
MUSIC_PEAK = 0.22          # ~ -12.1 dB below the SFX bank's 0.89 peak
BPM_BATTLE = 84.0          # shared by calm / action / peril
BPM_MENU = 72.0
BEAT = 60.0 / BPM_BATTLE
BAR = 4.0 * BEAT

# MIDI note numbers.  D minor: D=50 (D3), 62 (D4), 74 (D5).
def hz(midi):
    return 440.0 * 2.0 ** ((midi - 69) / 12.0)

# THE MOTIF: (semitones above D, start beat, duration beats).  Four bars.
#   D--F E | D--C D | G--F E | D------
MOTIF = [(0, 0.0, 2.0), (3, 2.0, 1.0), (2, 3.0, 1.0),
         (0, 4.0, 2.0), (-2, 6.0, 1.5), (0, 7.5, 0.5),
         (5, 8.0, 2.0), (3, 10.0, 1.0), (2, 11.0, 1.0),
         (0, 12.0, 4.0)]

# chord name -> (bass root midi, mid-register voicing)
CHORDS = {
    "Dm": (38, (50, 53, 57)),   # D2 | D3 F3 A3
    "Bb": (34, (46, 50, 53)),   # Bb1 | Bb2 D3 F3
    "F":  (41, (48, 53, 57)),   # F2 | C3 F3 A3
    "C":  (36, (48, 52, 55)),   # C2 | C3 E3 G3
    "Am": (45, (45, 48, 52)),   # A2 | A2 C3 E3
    "A":  (33, (45, 49, 52)),   # A1 | A2 C#3 E3  (dominant, turnaround)
    "D":  (38, (50, 54, 57)),   # D2 | D3 F#3 A3  (Picardy, sting_epoch only)
}


# ── instruments (lru_cached: identical notes render once) ──────────
def _saw2(n, f, det):
    """Two detuned naive saws.  The slow beat between them is the whole
    trick that makes this read as a string section, not an organ."""
    d1 = f * (1.0 - det) / RATE
    d2 = f * (1.0 + det) / RATE
    return [2.0 * ((d1 * i) % 1.0) + 2.0 * ((d2 * i) % 1.0) - 2.0
            for i in range(n)]


def _henv(n, a_s, r_s):
    """Attack / hold / cosine-release.  audio_synth's env() is attack-decay
    (percussive); pads and brass need a sustain, so this is the extension."""
    a = max(1, int(a_s * RATE))
    r = max(1, min(int(r_s * RATE), n))
    out = []
    for i in range(n):
        v = i / a if i < a else 1.0
        j = i - (n - r)
        if j >= 0:
            v *= 0.5 * (1.0 + math.cos(math.pi * j / r))
        out.append(v)
    return out


@lru_cache(maxsize=None)
def pad_note(midi, dur_s, cutoff, a_s, r_s):
    """Low-strings pad: detuned saw pair + sub-octave sine, lowpassed."""
    n = int(dur_s * RATE)
    f = hz(midi)
    sig = mix(_saw2(n, f, 0.004), gain(sine(n, 0.5 * f), 1.0))
    return apply_env(lowpass(sig, cutoff, 2), _henv(n, a_s, r_s))


@lru_cache(maxsize=None)
def brass_note(midi, dur_s, bright=0.2):
    """Brass-ish: same saw pair, slower attack, brighter cutoff."""
    n = int((dur_s + 0.30) * RATE)
    sig = lowpass(_saw2(n, hz(midi), 0.006), 600.0 + 2000.0 * bright, 2)
    return apply_env(sig, _henv(n, 0.06, 0.28))


@lru_cache(maxsize=None)
def bass_note(midi, dur_s):
    n = int((dur_s + 0.08) * RATE)
    f = hz(midi)
    sig = lowpass(mix(sine(n, f), gain(_saw2(n, f, 0.002), 0.35)), 340.0)
    return apply_env(sig, env(n, 0.006, dur_s * 0.9))


@lru_cache(maxsize=None)
def ping_note(midi, dur_s=2.4):
    """audio_synth's sonar_ping idiom, pulled into key: a pitch, its 2.5 Hz
    detune ghost, and a faint octave."""
    n = int(dur_s * RATE)
    f = hz(midi)
    return mix(
        gain(apply_env(sine(n, f), env(n, 0.005, dur_s * 0.35)), 0.8),
        gain(apply_env(sine(n, f + 2.5), env(n, 0.005, dur_s * 0.5, 0.9)), 0.5),
        gain(apply_env(sine(n, 2.0 * f), env(n, 0.004, dur_s * 0.18)), 0.18))


@lru_cache(maxsize=None)
def drone_voice(midi, total_s, cutoff, trem_hz, trem_depth, mode="saw"):
    """A drone that is seamless over a total_s loop: its frequencies (and
    tremolo rate) are snapped to a whole number of cycles per loop, and the
    lowpass is warmed up for 0.5 s before the window we keep, so the filter
    is in periodic steady state at both ends."""
    n = int(round(total_s * RATE))
    warm = int(0.5 * RATE)
    f = round(hz(midi) * total_s) / total_s
    if mode == "sine":
        d = f / RATE
        raw = [math.sin(2.0 * math.pi * d * i) for i in range(n + warm)]
    else:
        f1 = round(f * 0.996 * total_s) / total_s
        f2 = round(f * 1.004 * total_s) / total_s
        d1, d2 = f1 / RATE, f2 / RATE
        raw = [2.0 * ((d1 * i) % 1.0) + 2.0 * ((d2 * i) % 1.0) - 2.0
               for i in range(n + warm)]
    if trem_hz > 0.0:
        th = round(trem_hz * total_s) / total_s
        w = 2.0 * math.pi * th / RATE
        base = 1.0 - trem_depth
        raw = [raw[i] * (base + trem_depth * 0.5 * (1.0 + math.sin(w * i)))
               for i in range(len(raw))]
    if cutoff > 0.0:
        raw = lowpass(raw, cutoff, 2)
    return raw[warm:]


# percussion: shaped noise, exactly the audio_synth kit's approach
@lru_cache(maxsize=None)
def kick():
    n = int(0.32 * RATE)
    r = Rng(0xB001)
    return mix(
        gain(apply_env(sweep(n, 118.0, 40.0, 0.5), env(n, 0.002, 0.20)), 1.0),
        gain(apply_env(lowpass(noise(n, r), 100.0, 2), env(n, 0.001, 0.10)), 1.2))


@lru_cache(maxsize=None)
def snare(soft=False):
    n = int(0.22 * RATE)
    r = Rng(0xB002)
    band = highpass(lowpass(noise(n, r), 6000.0), 1100.0)
    return mix(
        gain(apply_env(band, env(n, 0.0008, 0.05 if soft else 0.085)), 1.0),
        gain(apply_env(sine(n, 190.0), env(n, 0.001, 0.05)), 0.35))


@lru_cache(maxsize=None)
def hat():
    n = int(0.06 * RATE)
    r = Rng(0xB003)
    return apply_env(highpass(noise(n, r), 7000.0), env(n, 0.0005, 0.022))


@lru_cache(maxsize=None)
def tick():
    n = int(0.05 * RATE)
    return apply_env(sine(n, 1750.0), env(n, 0.001, 0.02))


@lru_cache(maxsize=None)
def timp(midi):
    n = int(0.9 * RATE)
    f = hz(midi)
    r = Rng(0xB004)
    return mix(
        gain(apply_env(sweep(n, f * 1.5, f, 0.4), env(n, 0.003, 0.45)), 1.0),
        gain(apply_env(lowpass(noise(n, r), 90.0, 2), env(n, 0.002, 0.25)), 0.8))


# ── score plumbing ─────────────────────────────────────────────────
def place(buf, sig, t, g=1.0, wrap=False):
    """Add sig into buf at time t.  wrap=True folds anything past the end
    back to the start -- this is what makes the loops seamless."""
    i0 = int(round(t * RATE))
    L = len(buf)
    if wrap:
        for i, v in enumerate(sig):
            buf[(i0 + i) % L] += v * g
    else:
        for i, v in enumerate(sig):
            j = i0 + i
            if j < 0:
                continue
            if j >= L:
                break
            buf[j] += v * g


def play_motif(buf, notes, t0, beat, base, g, wrap, bright=0.2, stretch=1.0):
    for semi, sb, db in notes:
        place(buf, brass_note(base + semi, db * beat * stretch, bright),
              t0 + sb * beat * stretch, g, wrap)


def _samples(bars, bar_s):
    return int(round(bars * bar_s * RATE))


# ── the pieces ─────────────────────────────────────────────────────
def make_menu():
    """90 s, 27 bars at 72 BPM.  Restrained: low pads, the motif twice on
    brass, a quiet military snare from bar 12, timpani on the pillars."""
    beat = 60.0 / BPM_MENU
    bar = 4.0 * beat
    buf = [0.0] * _samples(27, bar)

    # opening low drone, D2 + A2, before any harmony declares itself
    place(buf, pad_note(38, 8 * bar + 3.0, 300.0, 3.0, 3.0), 0.0, 0.9)
    place(buf, pad_note(45, 8 * bar + 3.0, 300.0, 4.0, 3.0), 0.0, 0.5)

    # two-bar chords, bars 4..23, then a final Dm dying exactly at 90 s
    seq = ["Dm", "Bb", "F", "Am", "Dm", "Bb", "F", "C", "Bb", "C"]
    for k, name in enumerate(seq):
        t = (4 + 2 * k) * bar
        root, voic = CHORDS[name]
        place(buf, pad_note(root, 2 * bar + 2.5, 380.0, 1.8, 2.2), t, 0.55)
        for m in voic:
            place(buf, pad_note(m, 2 * bar + 2.5, 500.0, 2.2, 2.2), t, 0.32)
    root, voic = CHORDS["Dm"]
    place(buf, pad_note(root, 3 * bar, 380.0, 2.0, 3.0), 24 * bar, 0.6)
    for m in voic + (62,):
        place(buf, pad_note(m, 3 * bar, 500.0, 2.5, 3.0), 24 * bar, 0.3)

    # the motif, stated twice; second pass brighter with an octave shadow
    play_motif(buf, MOTIF, 8 * bar, beat, 62, 0.55, False, bright=0.25)
    play_motif(buf, MOTIF, 16 * bar, beat, 62, 0.60, False, bright=0.45)
    play_motif(buf, MOTIF, 16 * bar, beat, 74, 0.22, False, bright=0.55)

    # quiet military snare, bars 12..22
    s16 = bar / 16.0
    patt = [(0, .50), (2, .22), (4, .32), (6, .22),
            (8, .45), (10, .22), (12, .32), (15, .18)]
    for b in range(12, 23):
        for st, v in patt:
            place(buf, snare(True), b * bar + st * s16, v * 0.5)

    # timpani pillars on the section roots
    for b, m, v in [(4, 38, 0.7), (12, 38, 0.8), (20, 34, 0.7), (24, 38, 0.9)]:
        place(buf, timp(m), b * bar, v)
    return buf


def make_calm():
    """120.000 s seamless loop, 42 bars at 84 BPM.  Sparse tension bed:
    low open-fifth pads, sonar pings in key (with an echo), a slow pulse,
    the motif's first phrase muttered at half speed.  Nothing is dying."""
    buf = [0.0] * _samples(42, BAR)
    wrap = True

    chords = ["Dm", "Bb", "Dm", "C", "Dm", "Bb", "Am"]     # 7 x 6 bars = 42
    pings = [74, 77, 81, 79, 74, 77, 76]                    # a chord tone each
    for k, name in enumerate(chords):
        t = k * 6 * BAR
        root, _ = CHORDS[name]
        dur = 6 * BAR + 3.0
        place(buf, pad_note(root, dur, 260.0, 2.5, 3.0), t, 0.80, wrap)
        place(buf, pad_note(root + 7, dur, 300.0, 3.0, 3.0), t, 0.45, wrap)
        place(buf, pad_note(root + 12, dur, 340.0, 3.5, 3.0), t, 0.30, wrap)
        place(buf, ping_note(pings[k]), t + BEAT, 0.50, wrap)
        place(buf, ping_note(pings[k]), t + BEAT + 0.9, 0.22, wrap)  # echo

    for b in range(0, 42, 2):                               # the slow pulse
        place(buf, kick(), b * BAR, 0.28, wrap)
    for b in range(1, 42, 4):
        place(buf, tick(), b * BAR + 2 * BEAT, 0.16, wrap)

    # first phrase of the motif, dark and low, half speed
    play_motif(buf, MOTIF[:6], 12 * BAR, BEAT, 50, 0.40, wrap,
               bright=0.05, stretch=2.0)
    play_motif(buf, MOTIF[:6], 24 * BAR, BEAT, 50, 0.35, wrap,
               bright=0.0, stretch=2.0)
    return buf


def make_action():
    """120.000 s seamless loop, same key and tempo as battle_calm so the
    game can crossfade.  Driving shaped-noise percussion, ostinato eighth
    bass, the motif fragmented into stabs and stated once whole, and a
    two-bar dominant turnaround so the loop pulls back to bar 0."""
    buf = [0.0] * _samples(42, BAR)
    wrap = True
    s16 = BAR / 16.0
    chord_bars = (["Dm", "Dm", "Bb", "Bb", "Dm", "Dm", "C", "C"] * 5)[:40] \
        + ["A", "A"]

    for b, name in enumerate(chord_bars):
        root, voic = CHORDS[name]
        third = voic[1] - voic[0]
        # ostinato bass: root-heavy eighths with the chord's own third
        for i, iv in enumerate([0, 0, 7, 0, 0, 12, third, 7]):
            place(buf, bass_note(root + iv, 0.30),
                  b * BAR + i * BEAT / 2.0, 0.75, wrap)
        if b % 2 == 0:
            # glue pad + short brass stab on each chord change
            place(buf, pad_note(root + 12, 2 * BAR + 1.5, 480.0, 0.6, 1.5),
                  b * BAR, 0.40, wrap)
            for m in voic:
                place(buf, brass_note(m + 12, 0.5, 0.5), b * BAR, 0.16, wrap)
        # drums
        for st in [0, 3, 8, 11] + ([14] if b % 4 == 3 else []):
            place(buf, kick(), b * BAR + st * s16, 0.9, wrap)
        for st, v in [(4, .9), (12, .9), (7, .3)] + \
                ([(15, .28)] if b % 2 else []):
            place(buf, snare(v < 0.5), b * BAR + st * s16, v, wrap)
        for st in range(0, 16, 2):
            place(buf, hat(), b * BAR + st * s16,
                  0.5 if st in (0, 8) else 0.35, wrap)
        if b % 8 == 7:                                      # snare fill
            for st in range(8, 16):
                place(buf, snare(True), b * BAR + st * s16,
                      0.35 + 0.07 * (st - 8), wrap)

    # the motif, fragmented into high stabs...
    frags = {2: "a", 6: "b", 10: "a", 14: "c", 18: "a",
             22: "b", 30: "a", 34: "b", 38: "c"}
    FR = {"a": (0, 3, 2), "b": (5, 7, 10), "c": (7, 10, 12)}
    for b, fname in sorted(frags.items()):
        for semi, tb in zip(FR[fname], (0.0, 1.5, 2.5)):
            place(buf, brass_note(74 + semi, 0.45 * BEAT, 0.8),
                  b * BAR + tb * BEAT, 0.40, wrap)
    # ...stated once whole over bars 24-27...
    play_motif(buf, MOTIF, 24 * BAR, BEAT, 74, 0.45, wrap, bright=0.7)
    # ...and a held E5 over the A-major turnaround, leaning back to Dm
    place(buf, brass_note(76, 4.0, 0.6), 40 * BAR, 0.40, wrap)
    return buf


def make_peril():
    """60.000 s seamless loop, the layer ABOVE action (played additively).
    High dissonant pedal -- A5 against Bb5, a minor second, tremolo -- a
    throbbing D1 sub, sixteenth hats, Eb (the flat second) stabs, and a
    rising sweep every 7 bars.  All drone/tremolo rates are snapped to
    whole cycles per loop so the seam is inaudible."""
    T = 60.0
    buf = [0.0] * int(round(T * RATE))
    wrap = True
    s16 = BAR / 16.0

    place(buf, drone_voice(81, T, 2600.0, 7.0, 0.35), 0.0, 0.20)   # A5
    place(buf, drone_voice(82, T, 2600.0, 5.5, 0.35), 0.0, 0.18)   # Bb5 vs A5
    place(buf, drone_voice(26, T, 0.0, 1.4, 0.6, "sine"), 0.0, 0.9)  # D1 throb

    for b in [2, 9, 16]:                                    # rising dread
        n4 = int(4.0 * RATE)
        sg = lowpass(sweep(n4, 587.33, 1174.66, 1.2), 2200.0)
        place(buf, apply_env(sg, _henv(n4, 2.8, 0.9)), b * BAR, 0.30, wrap)

    for b in range(21):
        for st in range(16):
            place(buf, hat(), b * BAR + st * s16,
                  0.42 if st % 4 == 2 else 0.26, wrap)
        for st in (4, 12):                     # aligns with action's backbeat
            place(buf, snare(True), b * BAR + st * s16, 0.22, wrap)
    for b in (0, 7, 14):                       # Eb5: the flat second, held
        place(buf, brass_note(75, 2.0, 0.4), b * BAR + 2 * BEAT, 0.25, wrap)
    return buf


def make_contact():
    """4 s sting: first enemy contact.  A low hit, then a rising minor
    arpeggio (D-F-A) that does not resolve, plus a ping shimmer."""
    buf = [0.0] * int(4.0 * RATE)
    place(buf, kick(), 0.0, 1.3)
    place(buf, timp(38), 0.0, 1.0)
    r = Rng(0xC001)
    nb = int(1.2 * RATE)
    place(buf, apply_env(lowpass(noise(nb, r), 140.0, 2),
                         env(nb, 0.004, 0.5)), 0.0, 1.1)
    for m, t, d in [(62, 0.35, 0.35), (65, 0.80, 0.35), (69, 1.25, 2.2)]:
        place(buf, brass_note(m, d, 0.15), t, 0.6)
    place(buf, ping_note(74, 2.0), 1.6, 0.25)
    return buf


def make_epoch():
    """6 s sting: epoch advance.  The motif's opening, compressed and
    bright, rising G-A into a held D5 over a Picardy D MAJOR pad --
    the one place the score is allowed sunlight."""
    buf = [0.0] * int(6.0 * RATE)
    place(buf, timp(38), 0.0, 0.6)
    play_motif(buf, MOTIF[:4], 0.0, BEAT, 62, 0.55, False,
               bright=0.6, stretch=0.5)
    for m, t, d in [(67, 2.30, 0.4), (69, 2.75, 0.4), (74, 3.20, 2.2)]:
        place(buf, brass_note(m, d, 0.8), t, 0.50)
    for m in (50, 62, 66, 69, 74):                          # D major, F#4 in
        place(buf, pad_note(m, 2.9, 900.0, 0.3, 1.8), 3.1, 0.28)
    place(buf, ping_note(86, 1.8), 3.4, 0.30)
    return buf


# ── output + verification ──────────────────────────────────────────
TRACKS = [
    ("menu_theme", make_menu, 90.0, False,
     "main menu -- pads, the motif twice, quiet military snare"),
    ("battle_calm", make_calm, 120.0, True,
     "in-match bed, nothing dying -- pads, sonar pings in key, slow pulse"),
    ("battle_action", make_action, 120.0, True,
     "combat -- same key/tempo as calm for crossfade; drums, ostinato, motif"),
    ("battle_peril", make_peril, 60.0, True,
     "collapse-timer layer ABOVE action -- minor-second pedal, D1 throb"),
    ("sting_contact", make_contact, 4.0, False,
     "first enemy contact -- low hit, rising minor, unresolved"),
    ("sting_epoch", make_epoch, 6.0, False,
     "epoch advance -- the motif resolving upward through D major"),
]


def write_music(name, sig):
    os.makedirs(OUT, exist_ok=True)
    sig = normalise(sig, MUSIC_PEAK)      # -12 dB headroom is baked in here
    path = os.path.join(OUT, name + ".wav")
    with wave.open(path, "w") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(RATE)
        w.writeframes(b"".join(
            struct.pack("<h", int(max(-1.0, min(1.0, v)) * 32767))
            for v in sig))
    return path


def build_all():
    made = []
    for name, fn, want, loops, note in TRACKS:
        made.append((name, write_music(name, fn()), want, loops, note))
    return made


def verify(made):
    """Decode everything back and assert the promises: duration, peak at the
    stated headroom, non-silence, and loop seams no rougher than the signal's
    own roughest adjacent samples."""
    for name, path, want, loops, _ in made:
        with wave.open(path, "r") as w:
            assert w.getnchannels() == 1 and w.getsampwidth() == 2
            assert w.getframerate() == RATE
            nf = w.getnframes()
            s = struct.unpack("<%dh" % nf, w.readframes(nf))
        dur = nf / RATE
        assert abs(dur - want) < 0.01, (name, "duration", dur, want)
        peak = max(abs(v) for v in s)
        want_peak = MUSIC_PEAK * 32767
        assert want_peak * 0.90 <= peak <= want_peak + 2, (name, "peak", peak)
        rms = math.sqrt(sum(v * v for v in s) / nf)
        assert rms > 100.0, (name, "near-silent", rms)
        if loops:
            dmax = 0
            prev = s[0]
            for v in s[1:]:
                d = abs(v - prev)
                if d > dmax:
                    dmax = d
                prev = v
            seam = abs(s[0] - s[-1])
            assert seam <= dmax, (name, "loop seam", seam, dmax)
        yield name, dur, peak / 32767.0, rms / 32767.0


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--list", action="store_true")
    args = ap.parse_args()
    if args.list:
        print(__doc__)
        sys.exit(0)
    print("composing (D minor, battle layers at %g BPM)..." % BPM_BATTLE)
    made = build_all()
    total = 0.0
    for name, dur, peak, rms in verify(made):
        total += dur
        print("  %-16s %6.2f s  peak %.3f  rms %.3f  ok" %
              (name, dur, peak, rms))
    print("\n%d tracks, %.1f s (%.2f min) of music -> %s"
          % (len(made), total, total / 60.0, os.path.relpath(OUT, ROOT)))
    print("normalised to peak %.2f (%.1f dB below the 0.89 SFX bank)"
          % (MUSIC_PEAK, 20.0 * math.log10(MUSIC_PEAK / 0.89)))
