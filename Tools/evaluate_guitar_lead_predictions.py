#!/usr/bin/env python3
"""Score per-window guitar-lead probabilities against a manifest."""

from __future__ import annotations

import argparse
import csv
import json
from collections import defaultdict
from pathlib import Path


def metrics(rows: list[dict], scores: dict[str, float], threshold: float) -> dict:
    tp = fp = tn = fn = 0
    song_rows: dict[str, list[tuple[int, int]]] = defaultdict(list)
    song_end: dict[str, float] = defaultdict(float)
    for row in rows:
        truth = int(row["target"])
        prediction = int(scores[row["id"]] >= threshold)
        song_rows[row["song_id"]].append((truth, prediction))
        song_end[row["song_id"]] = max(song_end[row["song_id"]], float(row["end_seconds"]))
        if truth and prediction:
            tp += 1
        elif not truth and prediction:
            fp += 1
        elif not truth and not prediction:
            tn += 1
        else:
            fn += 1

    precision = tp / (tp + fp) if tp + fp else 0.0
    recall = tp / (tp + fn) if tp + fn else 0.0
    specificity = tn / (tn + fp) if tn + fp else 0.0
    f1 = 2 * precision * recall / (precision + recall) if precision + recall else 0.0
    song_f1 = []
    for pairs in song_rows.values():
        if not any(t for t, _ in pairs) and not any(p for _, p in pairs):
            continue
        song_tp = sum(t and p for t, p in pairs)
        song_fp = sum((not t) and p for t, p in pairs)
        song_fn = sum(t and (not p) for t, p in pairs)
        p = song_tp / (song_tp + song_fp) if song_tp + song_fp else 0.0
        r = song_tp / (song_tp + song_fn) if song_tp + song_fn else 0.0
        song_f1.append(2 * p * r / (p + r) if p + r else 0.0)

    duration_minutes = sum(song_end.values()) / 60.0
    return {
        "songs": len(song_rows),
        "segments": len(rows),
        "tp": tp,
        "fp": fp,
        "tn": tn,
        "fn": fn,
        "precision": round(precision, 4),
        "recall": round(recall, 4),
        "specificity": round(specificity, 4),
        "f1": round(f1, 4),
        "positive_song_macro_f1": round(sum(song_f1) / len(song_f1), 4) if song_f1 else 0.0,
        "false_positive_windows_per_audio_minute": round(fp / duration_minutes, 4) if duration_minutes else 0.0,
    }


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("manifest", type=Path)
    parser.add_argument("predictions", type=Path, help="CSV columns: id,score (score is guitar-lead confidence in [0,1]).")
    parser.add_argument("--threshold", type=float, default=0.5)
    args = parser.parse_args()

    manifest = [json.loads(line) for line in args.manifest.read_text(encoding="utf-8").splitlines() if line.strip()]
    with args.predictions.open(newline="", encoding="utf-8") as file:
        prediction_rows = list(csv.DictReader(file))
    scores = {row["id"]: float(row["score"]) for row in prediction_rows}
    if len(scores) != len(prediction_rows):
        raise SystemExit("Duplicate prediction ids")
    if any(score < 0.0 or score > 1.0 for score in scores.values()):
        raise SystemExit("Prediction scores must be between 0 and 1")

    report = {"threshold": args.threshold, "splits": {}}
    for split in sorted({row["split"] for row in manifest}):
        rows = [row for row in manifest if row["split"] == split]
        expected = {row["id"] for row in rows}
        absent = expected - scores.keys()
        if absent:
            raise SystemExit(f"Missing {len(absent)} predictions for {split}, e.g. {sorted(absent)[:3]}")
        report["splits"][split] = metrics(rows, scores, args.threshold)
    print(json.dumps(report, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
