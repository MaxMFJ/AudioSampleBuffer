#!/usr/bin/env python3
"""Measure whether a guitar stem's high-frequency envelope is selective.

This is a leakage diagnostic for separated stems, not a guitar classifier. It
uses a threshold fixed from the reference guitar stem and reports how often
other stems cross that same threshold, with an optional persistence gate.
"""

from __future__ import annotations

import argparse
import json
import wave
from pathlib import Path

import numpy as np


def read_mono_pcm16(path: Path) -> tuple[np.ndarray, int]:
    with wave.open(str(path), "rb") as source:
        if source.getsampwidth() != 2:
            raise ValueError(f"{path}: expected 16-bit PCM WAV")
        rate = source.getframerate()
        channels = source.getnchannels()
        samples = np.frombuffer(source.readframes(source.getnframes()), dtype="<i2")
    if channels < 1 or samples.size % channels:
        raise ValueError(f"{path}: invalid interleaved PCM data")
    audio = samples.reshape(-1, channels).astype(np.float32).mean(axis=1) / 32768.0
    return audio, rate


def high_band_envelope(audio: np.ndarray, rate: int, frame_ms: float, cutoff_hz: float) -> np.ndarray:
    fft_size = 4096
    hop = max(1, round(rate * frame_ms / 1000.0))
    window = np.hanning(fft_size).astype(np.float32)
    frequencies = np.fft.rfftfreq(fft_size, 1.0 / rate)
    band = frequencies >= cutoff_hz
    envelope = []
    for start in range(0, len(audio), hop):
        center = start + hop // 2
        left = center - fft_size // 2
        frame = np.zeros(fft_size, dtype=np.float32)
        src_left = max(0, left)
        src_right = min(len(audio), left + fft_size)
        if src_right > src_left:
            frame[src_left - left : src_right - left] = audio[src_left:src_right]
        spectrum = np.fft.rfft(frame * window)
        envelope.append(float(np.sqrt(np.square(np.abs(spectrum[band])).sum())))
    return np.asarray(envelope, dtype=np.float32)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reference", required=True, type=Path, help="Known guitar WAV used to set the gate")
    parser.add_argument(
        "--candidate",
        action="append",
        required=True,
        metavar="NAME=PATH",
        help="WAV to evaluate; may be supplied multiple times",
    )
    parser.add_argument("--frame-ms", type=float, default=50.0)
    parser.add_argument("--highpass-hz", type=float, default=1500.0)
    parser.add_argument("--reference-p90-ratio", type=float, default=0.35)
    parser.add_argument("--persistence-frames", type=int, default=3)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()

    if args.frame_ms <= 0 or args.highpass_hz < 0 or args.reference_p90_ratio <= 0:
        parser.error("frame, high-pass, and threshold ratio must be positive")
    if args.persistence_frames < 1:
        parser.error("persistence frames must be at least 1")

    reference_audio, reference_rate = read_mono_pcm16(args.reference)
    reference_env = high_band_envelope(reference_audio, reference_rate, args.frame_ms, args.highpass_hz)
    threshold = float(np.percentile(reference_env, 90) * args.reference_p90_ratio)
    results = []

    for spec in args.candidate:
        if "=" not in spec:
            parser.error(f"candidate must have NAME=PATH form: {spec}")
        name, raw_path = spec.split("=", 1)
        path = Path(raw_path)
        audio, rate = read_mono_pcm16(path)
        env = high_band_envelope(audio, rate, args.frame_ms, args.highpass_hz)
        ratio = min(len(reference_env), len(env)) / max(len(reference_env), len(env))
        if ratio < 0.98:
            raise SystemExit(f"duration mismatch for {name}: {len(env)} vs {len(reference_env)} frames")
        active = env > threshold
        if args.persistence_frames == 1:
            sustained = active
        else:
            sustained = np.convolve(
                active.astype(np.int32),
                np.ones(args.persistence_frames, dtype=np.int32),
                mode="valid",
            ) == args.persistence_frames
        results.append(
            {
                "name": name,
                "path": str(path),
                "duration_seconds": round(len(audio) / rate, 3),
                "frames": int(len(env)),
                "high_band_rms": round(float(np.sqrt(np.mean(env**2))), 6),
                "high_band_p50_p90_p99": [round(float(x), 6) for x in np.percentile(env, [50, 90, 99])],
                "above_reference_gate_fraction": round(float(np.mean(active)), 6),
                "persistent_gate_fraction": round(float(np.mean(sustained)), 6),
            }
        )

    report = {
        "diagnostic_only": True,
        "reference": str(args.reference),
        "frame_ms": args.frame_ms,
        "highpass_hz": args.highpass_hz,
        "gate_definition": f"{args.reference_p90_ratio} * reference P90",
        "gate_threshold": round(threshold, 6),
        "persistence_frames": args.persistence_frames,
        "persistence_ms": round(args.persistence_frames * args.frame_ms, 1),
        "candidates": results,
    }
    encoded = json.dumps(report, ensure_ascii=False, indent=2)
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        args.output.write_text(encoded + "\n", encoding="utf-8")
    print(encoded)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
