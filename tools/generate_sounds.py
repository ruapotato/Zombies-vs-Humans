#!/usr/bin/env python3
"""
Generate procedural sound effects for Zombies vs Humans game.
Uses scipy and numpy to create WAV files.
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
        np.linspace(0, 1, attack_samples),
        np.linspace(1, sustain, decay_samples),
        np.ones(max(0, sustain_samples)) * sustain,
        np.linspace(sustain, 0, release_samples)
    ])
    return env[:samples]


def generate_hit_body():
    """Generate a thud sound for body hit."""
    duration = 0.15
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    
    # Low frequency thud with quick decay
    freq = 80
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 30)
    
    # Add some noise for impact texture
    noise = np.random.randn(len(t)) * 0.3 * np.exp(-t * 40)
    audio += noise
    
    return normalize(audio)


def generate_hit_head():
    """Generate a splat/critical hit sound for headshot."""
    duration = 0.2
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    
    # Higher pitch impact
    freq = 200
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 25)
    
    # Add burst of noise for splat effect
    noise = np.random.randn(len(t)) * 0.5 * np.exp(-t * 20)
    
    # Add high frequency component
    high_freq = np.sin(2 * np.pi * 800 * t) * 0.3 * np.exp(-t * 40)
    
    audio = audio + noise + high_freq
    return normalize(audio)


def generate_footstep():
    """Generate a footstep sound."""
    duration = 0.1
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    
    # Low thump
    freq = 100
    audio = np.sin(2 * np.pi * freq * t) * np.exp(-t * 50)
    
    # Add subtle noise for floor texture
    noise = np.random.randn(len(t)) * 0.2 * np.exp(-t * 60)
    audio += noise
    
    return normalize(audio)


def generate_round_start():
    """Generate a round start fanfare/alert."""
    duration = 0.5
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    
    # Rising tone sequence
    audio = np.zeros_like(t)
    
    # Three ascending notes
    for i, freq in enumerate([440, 554, 659]):
        start = int(i * 0.15 * SAMPLE_RATE)
        end = int((i + 1) * 0.15 * SAMPLE_RATE)
        note_t = t[start:end] - t[start]
        note_env = np.exp(-note_t * 5)
        audio[start:end] += np.sin(2 * np.pi * freq * note_t) * note_env
        # Add harmonics
        audio[start:end] += np.sin(2 * np.pi * freq * 2 * note_t) * 0.3 * note_env
    
    return normalize(audio)


def generate_zombie_spawn():
    """Generate a zombie spawning sound."""
    duration = 0.4
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    
    # Descending growl
    freq_start = 300
    freq_end = 80
    freq = np.linspace(freq_start, freq_end, len(t))
    phase = 2 * np.pi * np.cumsum(freq) / SAMPLE_RATE
    audio = np.sin(phase) * envelope(duration, attack=0.05, decay=0.1, sustain=0.7, release=0.3)
    
    # Add distortion/growl texture
    noise = np.random.randn(len(t)) * 0.2 * envelope(duration, attack=0.1, decay=0.2, sustain=0.4, release=0.3)
    audio += noise
    
    return normalize(audio)


def generate_tank_roar():
    """Generate a big zombie roar."""
    duration = 0.8
    t = np.linspace(0, duration, int(SAMPLE_RATE * duration))
    
    # Deep base roar
    freq_base = 60
    audio = np.sin(2 * np.pi * freq_base * t)
    
    # Add multiple harmonics for richness
    for harmonic in [2, 3, 4]:
        audio += np.sin(2 * np.pi * freq_base * harmonic * t) * (0.5 / harmonic)
    
    # Modulate with LFO for growl effect
    lfo = 1 + 0.3 * np.sin(2 * np.pi * 15 * t)
    audio *= lfo
    
    # Apply envelope
    env = envelope(duration, attack=0.1, decay=0.2, sustain=0.6, release=0.3)
    audio *= env
    
    # Add noise for texture
    noise = np.random.randn(len(t)) * 0.3 * env
    audio += noise
    
    return normalize(audio)


def main():
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    
    sounds = {
        'hit_body.wav': generate_hit_body,
        'hit_head.wav': generate_hit_head,
        'footstep.wav': generate_footstep,
        'round_start.wav': generate_round_start,
        'zombie_spawn.wav': generate_zombie_spawn,
        'tank_roar.wav': generate_tank_roar,
    }
    
    for filename, generator in sounds.items():
        filepath = os.path.join(OUTPUT_DIR, filename)
        audio = generator()
        wavfile.write(filepath, SAMPLE_RATE, audio)
        print(f"Generated: {filepath}")


if __name__ == '__main__':
    main()
