#!/usr/bin/env python3
"""Prepare and optionally run YAMNet Core ML on an interleaved PCM file.

The Core ML package published at Yehor/YAMNet-CoreML accepts YAMNet log-mel
patches, not raw PCM. This tool implements that front-end for signed 16-bit
little-endian mono PCM, then runs each 0.96 s patch through Core ML when a model
path is supplied.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any

import librosa
import numpy as np


SAMPLE_RATE = 16_000
FFT_SIZE = 512
WINDOW_SIZE = 400  # 25 ms at 16 kHz
HOP_SIZE = 160      # 10 ms at 16 kHz
MEL_BANDS = 64
PATCH_FRAMES = 96
PATCH_HOP_FRAMES = 48  # 50% overlap; 0.48 s output cadence
MEL_MIN_HZ = 125.0
MEL_MAX_HZ = 7_500.0
LOG_OFFSET = 0.001
YAMNET_ELECTRIC_GUITAR_INDEX = 136
YAMNET_GUITAR_INDEX = 135


def load_pcm16_mono(path: Path, source_rate: int) -> np.ndarray:
    raw = np.fromfile(path, dtype="<i2")
    if raw.size == 0:
        raise ValueError(f"PCM file is empty: {path}")
    audio = raw.astype(np.float32) / 32768.0
    if source_rate != SAMPLE_RATE:
        audio = librosa.resample(audio, orig_sr=source_rate, target_sr=SAMPLE_RATE)
    return np.asarray(audio, dtype=np.float32)


def yamnet_log_mel_patches(audio: np.ndarray) -> np.ndarray:
    """Return [patch, 96, 64] float32 YAMNet-compatible log-mel patches."""
    # Match YAMNet's waveform padding: enough samples for the first complete
    # patch, then round up to a whole 0.48 s patch hop.
    min_samples = int(round((PATCH_FRAMES * HOP_SIZE / SAMPLE_RATE +
                             WINDOW_SIZE / SAMPLE_RATE - HOP_SIZE / SAMPLE_RATE) * SAMPLE_RATE))
    patch_hop_samples = PATCH_HOP_FRAMES * HOP_SIZE
    padded_length = max(len(audio), min_samples)
    extra_hops = int(np.ceil(max(0, padded_length - min_samples) / patch_hop_samples))
    padded_length = min_samples + extra_hops * patch_hop_samples
    padded_audio = np.pad(audio, (0, max(0, padded_length - len(audio))))

    # tf.signal.stft uses frames starting at sample 0 and a periodic Hann
    # window. Its FFT frame is 512 samples while the non-zero window is 400.
    frame_count = int(np.ceil(len(padded_audio) / HOP_SIZE))
    stft_padded_length = (frame_count - 1) * HOP_SIZE + WINDOW_SIZE
    stft_audio = np.pad(padded_audio, (0, max(0, stft_padded_length - len(padded_audio))))
    frames = np.lib.stride_tricks.sliding_window_view(stft_audio, WINDOW_SIZE)[::HOP_SIZE]
    frames = frames[:frame_count]
    periodic_hann = 0.5 - 0.5 * np.cos(2.0 * np.pi * np.arange(WINDOW_SIZE) / WINDOW_SIZE)
    magnitude = np.abs(np.fft.rfft(frames * periodic_hann[None, :], n=FFT_SIZE, axis=1)).T.astype(np.float32)
    mel_filter = librosa.filters.mel(
        sr=SAMPLE_RATE,
        n_fft=FFT_SIZE,
        n_mels=MEL_BANDS,
        fmin=MEL_MIN_HZ,
        fmax=MEL_MAX_HZ,
        htk=True,
        norm=None,
        dtype=np.float32,
    )
    # YAMNet uses magnitude (not power), then log(mel + 0.001).
    mel = mel_filter @ magnitude
    log_mel = np.log(mel + LOG_OFFSET).T.astype(np.float32)

    patches = []
    for start in range(0, log_mel.shape[0] - PATCH_FRAMES + 1, PATCH_HOP_FRAMES):
        patches.append(log_mel[start : start + PATCH_FRAMES])
    if not patches:
        raise ValueError("PCM did not produce any YAMNet feature patches")
    return np.stack(patches).astype(np.float32)


def run_coreml(model_path: Path, patches: np.ndarray) -> np.ndarray:
    try:
        import coremltools as ct
    except ImportError as exc:
        raise RuntimeError("Install coremltools in the active Python environment") from exc

    model = ct.models.MLModel(str(model_path), compute_units=ct.ComputeUnit.ALL)
    descriptions = model.get_spec().description
    input_name = descriptions.input[0].name
    input_dtype = np.float16 if descriptions.input[0].type.multiArrayType.dataType == 65552 else np.float32
    output_names = [item.name for item in descriptions.output]
    scores = []
    for patch in patches:
        result: dict[str, Any] = model.predict({input_name: patch[None, ...].astype(input_dtype)})
        output_name = "Identity" if "Identity" in result else output_names[0]
        row = np.asarray(result[output_name], dtype=np.float32).reshape(-1)
        if row.size <= YAMNET_ELECTRIC_GUITAR_INDEX:
            raise ValueError(f"Expected 521 YAMNet scores, received {row.size}")
        scores.append(row)
    return np.stack(scores)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pcm", type=Path, help="mono signed PCM16 little-endian file")
    parser.add_argument("--sample-rate", type=int, default=44_100, help="source PCM sample rate")
    parser.add_argument("--model", type=Path, help="YAMNet.mlpackage or compiled Core ML model path")
    parser.add_argument("--output-prefix", type=Path, help="output prefix; defaults beside input")
    args = parser.parse_args()

    prefix = args.output_prefix or args.pcm.with_suffix("")
    prefix.parent.mkdir(parents=True, exist_ok=True)
    audio = load_pcm16_mono(args.pcm, args.sample_rate)
    patches = yamnet_log_mel_patches(audio)
    features_path = prefix.with_name(prefix.name + "-yamnet-features.npz")
    np.savez_compressed(
        features_path,
        features=patches,
        sample_rate=np.int32(SAMPLE_RATE),
        patch_hop_seconds=np.float32(PATCH_HOP_FRAMES * HOP_SIZE / SAMPLE_RATE),
        source=str(args.pcm),
    )
    print(f"PCM: {audio.size / SAMPLE_RATE:.2f}s @ {SAMPLE_RATE} Hz mono")
    print(f"YAMNet input patches: {patches.shape} (patch hop 0.48s)")
    print(f"Saved features: {features_path}")

    if not args.model:
        print("Inference skipped: pass --model /path/to/YAMNet.mlpackage")
        return

    scores = run_coreml(args.model, patches)
    csv_path = prefix.with_name(prefix.name + "-yamnet-scores.csv")
    with csv_path.open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["patch_start_sec", "patch_center_sec", "electric_guitar", "guitar"])
        hop_seconds = PATCH_HOP_FRAMES * HOP_SIZE / SAMPLE_RATE
        for i, row in enumerate(scores):
            start = i * hop_seconds
            writer.writerow([
                f"{start:.3f}",
                f"{start + 0.48:.3f}",
                f"{row[YAMNET_ELECTRIC_GUITAR_INDEX]:.7f}",
                f"{row[YAMNET_GUITAR_INDEX]:.7f}",
            ])
    summary = {
        "model": str(args.model),
        "source_pcm": str(args.pcm),
        "source_rate_hz": args.sample_rate,
        "inference_rate_hz": SAMPLE_RATE,
        "duration_sec": round(audio.size / SAMPLE_RATE, 4),
        "patch_count": int(len(scores)),
        "patch_length_sec": 0.96,
        "patch_hop_sec": 0.48,
        "class_indices": {"electric_guitar": YAMNET_ELECTRIC_GUITAR_INDEX, "guitar": YAMNET_GUITAR_INDEX},
        "score_note": "Generic AudioSet class confidence; not a guitar-lead probability.",
        "scores_csv": str(csv_path),
    }
    summary_path = prefix.with_name(prefix.name + "-yamnet-summary.json")
    summary_path.write_text(json.dumps(summary, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Saved model scores: {csv_path}")
    print(f"Saved summary: {summary_path}")


if __name__ == "__main__":
    main()
