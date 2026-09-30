#!/usr/bin/env python3
"""Create the compact 50 ms control envelope for the isolated guitar PoC."""
import argparse
import wave
from pathlib import Path

import numpy as np


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("input", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--frame-ms", type=float, default=50.0)
    args = parser.parse_args()

    with wave.open(str(args.input), "rb") as source:
        if source.getsampwidth() != 2:
            raise SystemExit("expected 16-bit PCM WAV")
        rate = source.getframerate()
        channels = source.getnchannels()
        pcm = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
    audio = pcm.reshape(-1, channels).astype(np.float32).mean(axis=1) / 32768.0

    hop = max(1, round(rate * args.frame_ms / 1000.0))
    fft_size = 4096
    window = np.hanning(fft_size).astype(np.float32)
    frequencies = np.fft.rfftfreq(fft_size, 1.0 / rate)
    high_band = frequencies >= 1500.0
    levels = []
    for start in range(0, len(audio), hop):
        center = start + hop // 2
        left = center - fft_size // 2
        frame = np.zeros(fft_size, dtype=np.float32)
        src_left = max(0, left)
        src_right = min(len(audio), left + fft_size)
        if src_right > src_left:
            frame[src_left - left:src_right - left] = audio[src_left:src_right]
        power = np.abs(np.fft.rfft(frame * window)) ** 2
        levels.append(float(np.sqrt(power[high_band].sum())))

    values = np.asarray(levels, dtype=np.float32)
    floor = float(np.percentile(values, 12))
    ceiling = float(np.percentile(values, 96))
    if ceiling <= floor:
        raise SystemExit("guitar stem has no usable high-frequency dynamic range")
    normalized = np.clip((values - floor) / (ceiling - floor), 0.0, 1.0)
    # Keep small separated-stem leakage below the visual trigger threshold.
    normalized[normalized < 0.08] = 0.0
    args.output.parent.mkdir(parents=True, exist_ok=True)
    args.output.write_text(",".join(f"{value:.4f}" for value in normalized) + "\n")
    print(f"wrote {len(normalized)} frames at {1000.0 * hop / rate:.2f} ms/frame")
    print(f"high-band floor={floor:.3f} ceiling={ceiling:.3f}; active={np.mean(normalized > 0):.1%}")


if __name__ == "__main__":
    main()
