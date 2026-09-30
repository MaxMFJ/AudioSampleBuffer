#!/usr/bin/env python3
"""Build a song-disjoint MedleyDB lead-guitar evaluation manifest.

The public MedleyDB metadata bundled with the LeadInstrumentDetection repo
contains 5-second windows and instrument-lead annotations, but not the audio.
This script records expected audio paths and reports which files are available.
It never copies or redistributes dataset audio.
"""

from __future__ import annotations

import argparse
import json
import random
from collections import defaultdict
from pathlib import Path


ELECTRIC_GUITAR_LABELS = (
    "clean_electric_guitar",
    "distorted_electric_guitar",
)


def timecode_seconds(value: str) -> float:
    minutes, rest = value.split(":", 1)
    return int(minutes) * 60.0 + float(rest)


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--metadata",
        type=Path,
        default=Path("build/guitar_poc/LeadInstrumentDetection/datasets/MedleyDB/v1_segmented/metadata.json"),
    )
    parser.add_argument(
        "--audio-root",
        type=Path,
        default=Path("build/guitar_poc/LeadInstrumentDetection/datasets/MedleyDB/v1_segmented"),
        help="Root containing the metadata's seg_audio_dir paths (normally v1_segmented).",
    )
    parser.add_argument(
        "--output",
        type=Path,
        default=Path("build/guitar_poc/medleydb_guitar_lead_manifest.jsonl"),
    )
    parser.add_argument(
        "--min-guitar-seconds",
        type=float,
        default=2.5,
        help="Positive if annotated clean/distorted electric-guitar lead lasts at least this long in the 5s window.",
    )
    parser.add_argument(
        "--split-policy",
        choices=("stratified", "provided"),
        default="stratified",
        help="Use a reproducible song-disjoint stratified split, or preserve the repository's original split.",
    )
    parser.add_argument("--seed", type=int, default=20260929)
    args = parser.parse_args()

    metadata = json.loads(args.metadata.read_text(encoding="utf-8"))
    if not isinstance(metadata, dict) or not metadata:
        raise SystemExit(f"No segment records in {args.metadata}")

    split_by_song: dict[str, str] = {}
    rows = []
    for segment_key, item in metadata.items():
        seg_dir = item["seg_audio_dir"]
        parts = Path(seg_dir).parts
        if len(parts) < 3 or parts[0] != "data":
            raise SystemExit(f"Unexpected seg_audio_dir for {segment_key}: {seg_dir}")
        song_id = parts[1]
        original_split = item["split"]

        guitar_seconds = 0.0
        lead_labels = []
        for annotation in item.get("annotations", []):
            lead_label = annotation["lead"].split("#", 1)[-1].strip().lower()
            lead_labels.append(lead_label)
            if lead_label in ELECTRIC_GUITAR_LABELS:
                start = timecode_seconds(annotation["start"])
                end = timecode_seconds(annotation["end"])
                guitar_seconds += max(0.0, end - start)

        audio_path = args.audio_root / Path(seg_dir) / "mix.mp3"
        rows.append(
            {
                "id": segment_key,
                "song_id": song_id,
                "split": original_split,
                "original_split": original_split,
                "audio_path": str(audio_path),
                "start_seconds": timecode_seconds(item["original_start"]),
                "end_seconds": timecode_seconds(item["original_end"]),
                "target": int(guitar_seconds >= args.min_guitar_seconds),
                "electric_guitar_lead_seconds": round(guitar_seconds, 3),
                "lead_labels": sorted(set(lead_labels)),
            }
        )

    if args.split_policy == "stratified":
        by_song: dict[str, list[dict]] = defaultdict(list)
        for row in rows:
            by_song[row["song_id"]].append(row)

        ratios = {"train": 0.70, "valid": 0.15, "test": 0.15}
        assignment: dict[str, str] = {}
        for class_target in (0, 1):
            songs = sorted(
                song_id
                for song_id, song_rows in by_song.items()
                if int(any(row["target"] for row in song_rows)) == class_target
            )
            random.Random(args.seed + class_target).shuffle(songs)
            exact = {name: len(songs) * ratio for name, ratio in ratios.items()}
            counts = {name: int(exact[name]) for name in ratios}
            remainder = len(songs) - sum(counts.values())
            for name in sorted(ratios, key=lambda key: exact[key] - counts[key], reverse=True)[:remainder]:
                counts[name] += 1
            offset = 0
            for name in ratios:
                for song_id in songs[offset : offset + counts[name]]:
                    assignment[song_id] = name
                offset += counts[name]

        for row in rows:
            row["split"] = assignment[row["song_id"]]
            row["split_policy"] = args.split_policy
            row["split_seed"] = args.seed
    else:
        for row in rows:
            row["split_policy"] = args.split_policy
            row["split_seed"] = None

    for row in rows:
        split = row["split"]
        song_id = row["song_id"]
        previous = split_by_song.setdefault(song_id, split)
        if previous != split:
            raise SystemExit(f"Song leakage: {song_id} appears in {previous} and {split}")

    split_songs: dict[str, set[str]] = defaultdict(set)
    for row in rows:
        split_songs[row["split"]].add(row["song_id"])
    split_names = sorted(split_songs)
    for i, left in enumerate(split_names):
        for right in split_names[i + 1 :]:
            overlap = split_songs[left] & split_songs[right]
            if overlap:
                raise SystemExit(f"Song overlap between {left} and {right}: {sorted(overlap)[:3]}")

    args.output.parent.mkdir(parents=True, exist_ok=True)
    with args.output.open("w", encoding="utf-8") as out:
        for row in rows:
            out.write(json.dumps(row, ensure_ascii=False) + "\n")

    summary = {}
    for split in split_names:
        split_rows = [row for row in rows if row["split"] == split]
        summary[split] = {
            "songs": len(split_songs[split]),
            "segments": len(split_rows),
            "positive_segments": sum(row["target"] for row in split_rows),
            "guitar_positive_songs": len({row["song_id"] for row in split_rows if row["target"]}),
            "available_audio_segments": sum(Path(row["audio_path"]).is_file() for row in split_rows),
        }

    print(json.dumps({"manifest": str(args.output), "total_segments": len(rows), "splits": summary}, ensure_ascii=False, indent=2))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
