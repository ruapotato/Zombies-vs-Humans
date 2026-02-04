#!/usr/bin/env python3
"""
Generate procedural sound effects for Zombies vs Humans game.
All sounds are mono, 16-bit PCM WAV files compatible with Godot.
"""

import numpy as np
from scipy.io import wavfile
import os

SAMPLE_RATE = 44100
OUTPUT_DIR = os.path.join(os.path.dirname(os.path.dirname(__file__)), 'assets', 'sounds')


def normalize(audio):
    """Normalize audio to 16-bit range."""
    audio = audio / np.max(np.abs(audio)) if np.max(np.abs(audio)) > 0 else audio
    return (audio * 32767).astype(np.int16)


def envelope(length, attack=0.01, decay=0.1, sustain=0.5, release=0.2):
    """Create an ADSR envelope."""
    samples = int(length * SAMPLE_RATE)
    attack_samples = int(attack * samples)
    decay_samples = int(decay * samples)
    release_samples = int(release * samples)
    sustain_samples = samples - attack_samples - decay_samples - release_samples

    env = np.concatenate([
        np.linspace(0, 1, max(1, attack_samples)),
        np.linspace(1, sustain, max(1, decay_samples)),
        np.ones(max(0, sustain_samples)) * sustain,
        np.linspace(sustain, 0, max(1, release_samples))
    ])
    return env[:samples] if len(env) >= samples else np.pad(env, (0, samples - len(env)))


def generate_hit_body():
    """Generate a thud sound for body hit."""
    duration = 0.15
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = 80
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 30)
    noise = np.random.randn(len(t)) * 0.3 * np.exp(-t * 40)
    audio += noise

    return normalize(audio)


def generate_hit_head():
    """Generate a splat/critical hit sound for headshot."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = 200
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 25)
    noise = np.random.randn(len(t)) * 0.5 * np.exp(-t * 20)
    high_freq = np.sin(2 * np.pi * 800 * t) * 0.3 * np.exp(-t * 40)

    audio = audio + noise + high_freq
    return normalize(audio)


def generate_headshot_kill():
    """Dramatic headshot kill sound - splat with impact."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    # Initial crack/pop
    crack = np.sin(2 * np.pi * 400 * t) * np.exp(-t * 50)
    crack += np.sin(2 * np.pi * 1200 * t) * 0.4 * np.exp(-t * 80)

    # Wet splat noise
    splat = np.random.randn(len(t)) * 0.7 * np.exp(-t * 15)

    # Low impact thud
    thud = np.sin(2 * np.pi * 60 * t) * 0.5 * np.exp(-t * 10)

    audio = crack + splat + thud
    return normalize(audio)


def generate_footstep():
    """Generate a footstep sound."""
    duration = 0.1
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = 100
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 50)
    noise = np.random.randn(len(t)) * 0.2 * np.exp(-t * 60)
    audio += noise

    return normalize(audio)


def generate_round_start():
    """Generate a round start fanfare/alert."""
    duration = 0.5
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    audio = np.zeros_like(t)

    for i, freq in enumerate([440, 554, 659]):
        start = int(i * 0.15 * SAMPLE_RATE)
        end = int((i + 1) * 0.15 * SAMPLE_RATE)
        note_t = t[start:end] - t[start]
        note_env = np.exp(-note_t * 5)
        audio[start:end] += np.sin(2 * np.pi * freq * note_t) * note_env
        audio[start:end] += np.sin(2 * np.pi * freq * 2 * note_t) * 0.3 * note_env

    return normalize(audio)


def generate_zombie_spawn():
    """Generate a zombie spawning sound."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = np.linspace(300, 80, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    audio = np.sin(phase) * envelope(duration, attack=0.05, decay=0.1, sustain=0.7, release=0.3)
    noise = np.random.randn(len(t)) * 0.2 * envelope(duration, attack=0.1, decay=0.2, sustain=0.4, release=0.3)
    audio += noise

    return normalize(audio)


def generate_tank_roar():
    """Generate a big zombie roar."""
    duration = 0.8
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq_base = 60
    audio = np.sin(2 * np.pi * freq_base * t)

    for harmonic in [2, 3, 4]:
        audio += np.sin(2 * np.pi * freq_base * harmonic * t) * (0.5 / harmonic)

    lfo = 1 + 0.3 * np.sin(2 * np.pi * 15 * t)
    audio *= lfo

    env = envelope(duration, attack=0.1, decay=0.2, sustain=0.6, release=0.3)
    audio *= env
    noise = np.random.randn(len(t)) * 0.3 * env
    audio += noise

    return normalize(audio)


def generate_pistol_fire():
    """Generic gunshot sound."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    noise = np.random.randn(len(t)) * 0.8 * np.exp(-t * 30)
    boom = np.sin(2 * np.pi * 100 * t) * 0.5 * np.exp(-t * 20)

    return normalize(noise + boom)


def generate_reload():
    """Reload click sound."""
    duration = 0.3
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    click = np.sin(2 * np.pi * 1000 * t) * 0.3 * np.exp(-t * 100)
    slide = np.random.randn(len(t)) * 0.4 * envelope(duration, attack=0.05, decay=0.1, sustain=0.2, release=0.1)

    return normalize(click + slide)


def generate_empty_clip():
    """Empty gun click."""
    duration = 0.08
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    click = np.sin(2 * np.pi * 800 * t) * np.exp(-t * 80)
    return normalize(click)


def generate_player_hurt():
    """Player taking damage sound."""
    duration = 0.25
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = 150
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 15)
    audio += np.sin(2 * np.pi * freq * 1.5 * t) * 0.3 * np.exp(-t * 20)
    noise = np.random.randn(len(t)) * 0.2 * np.exp(-t * 25)

    return normalize(audio + noise)


def generate_purchase():
    """Purchase/buy sound."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    audio = np.sin(2 * np.pi * 880 * t) * np.exp(-t * 15)
    audio += np.sin(2 * np.pi * 1100 * t) * 0.5 * np.exp(-t * 18)

    return normalize(audio)


def generate_denied():
    """Action denied sound."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    audio = np.sin(2 * np.pi * 200 * t) * np.exp(-t * 15)
    audio += np.sin(2 * np.pi * 250 * t) * 0.5 * np.exp(-t * 18)

    return normalize(audio)


def generate_points_gain():
    """Points earned sound."""
    duration = 0.12
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    audio = np.sin(2 * np.pi * 600 * t) * np.exp(-t * 25)
    return normalize(audio)


def generate_weapon_switch():
    """Weapon switch sound."""
    duration = 0.12
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    audio = np.sin(2 * np.pi * 400 * t) * np.exp(-t * 40)
    noise = np.random.randn(len(t)) * 0.3 * np.exp(-t * 50)

    return normalize(audio + noise)


def generate_player_down():
    """Player going down sound."""
    duration = 0.6
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = np.linspace(400, 100, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    audio = np.sin(phase) * np.exp(-t * 4)

    return normalize(audio)


def generate_player_revive():
    """Reviving sound - pulsing beep."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    pulse = (np.sin(2 * np.pi * 5 * t) > 0).astype(float)
    audio = np.sin(2 * np.pi * 500 * t) * 0.5 * pulse * np.exp(-t * 3)

    return normalize(audio)


def generate_player_revived():
    """Successfully revived sound."""
    duration = 0.3
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = np.linspace(300, 600, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    audio = np.sin(phase) * np.exp(-t * 6)

    return normalize(audio)


def generate_jump():
    """Jump sound."""
    duration = 0.12
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))

    freq = np.linspace(100, 250, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    audio = np.sin(phase) * np.exp(-t * 30)
    noise = np.random.randn(len(t)) * 0.2 * np.exp(-t * 40)

    return normalize(audio + noise)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)

    sounds = {
        'hit_body.wav': generate_hit_body,
        'hit_head.wav': generate_hit_head,
        'headshot_kill.wav': generate_headshot_kill,
        'footstep.wav': generate_footstep,
        'round_start.wav': generate_round_start,
        'zombie_spawn.wav': generate_zombie_spawn,
        'tank_roar.wav': generate_tank_roar,
        'pistol_fire.wav': generate_pistol_fire,
        'reload.wav': generate_reload,
        'empty_clip.wav': generate_empty_clip,
        'player_hurt.wav': generate_player_hurt,
        'purchase.wav': generate_purchase,
        'denied.wav': generate_denied,
        'points_gain.wav': generate_points_gain,
        'weapon_switch.wav': generate_weapon_switch,
        'player_down.wav': generate_player_down,
        'player_revive.wav': generate_player_revive,
        'player_revived.wav': generate_player_revived,
        'jump.wav': generate_jump,
    }

    for filename, generator in sounds.items():
        filepath = os.path.join(OUTPUT_DIR, filename)
        audio = generator()
        wavfile.write(filepath, SAMPLE_RATE, audio)
        print(f"Generated: {filepath}")

    print(f"\nGenerated {len(sounds)} sound effects!")


if __name__ == '__main__':
    main()
