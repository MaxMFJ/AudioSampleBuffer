# General electric-guitar lead detector PoC

This PoC evaluates a detector against **songs not used to fit it**. The target
is a clean or distorted electric-guitar lead that dominates at least 2.5 s of a
5 s window. Acoustic guitar is retained as a negative/confounder class. This is
an operational first label, not a claim that every guitar lead is sustained.

## Current benchmark metadata

The LeadInstrumentDetection repository contains MedleyDB metadata for 109 songs
and 8,025 overlapping 5 s windows. It does not contain the song or stem audio.
The manifest builder makes a fixed, reproducible, song-disjoint 70/15/15 split,
stratified by whether a song has any positive electric-guitar lead window:

```sh
python3 Tools/build_medleydb_guitar_lead_manifest.py
```

The manifest is written under `build/guitar_poc/` and includes the expected
`mix.mp3` path, time range, lead labels, positive duration, and split. To use
the repository's original split instead, pass `--split-policy provided`.
Never split windows independently: windows from one song must stay together.

The current fixed split contains 76 train, 17 validation, and 16 test songs.
At the 2.5 s target threshold, there are 22 positive training songs, 5
validation songs, and 4 test songs. That test set is a useful initial check but
too small for a strong generalization claim. Add more licensed, multi-genre
songs before treating a score as release evidence.

## Audio needed

The checked-out repository only supplies the JSON annotations. For each
manifest row, the corresponding 5 s mixture is expected at
`<MedleyDB>/v1_segmented/<seg_audio_dir>/mix.mp3`. MedleyDB also has the
original mix, stem, metadata, and instrument-activity annotations. The project
website offers a sample archive and requires access requests for the full
audio collection. Its license is non-commercial research use; check the terms
before distributing audio or using it commercially.

## Prediction file and report

Once a model writes one confidence per manifest `id`, save CSV with exactly
these columns:

```csv
id,score
AClassicEducation_NightOwl-0,0.13
```

Then compute per-split precision, recall, specificity, F1, positive-song macro
F1, and false-positive windows per audio minute:

```sh
python3 Tools/evaluate_guitar_lead_predictions.py \
  build/guitar_poc/medleydb_guitar_lead_manifest.jsonl \
  build/guitar_poc/guitar_lead_scores.csv \
  --threshold 0.5
```

Report the held-out `test` metrics as the primary result. Use `valid` only to
choose a threshold. Do not use the 李荣浩《名字》 segment to fit the model and
then report it as held-out validation; keep it as a separate final listening
check.

## Baselines

- The LeadInstrumentDetection repo provides a guitar-solo classifier
  checkpoint, but its stock inference script assumes the authors' audio
  directory and CUDA. A local-WAV CPU/MPS wrapper is still needed; its labels
  are broader than sustained feedback/lead tone.
- The musicnn repository has small pretrained guitar-tagging weights. Its
  `guitar` tag is song-content tagging, not an isolated stem or an explicit
  sustained-lead event, so treat it as a weak baseline only.
- A separate Guitar RoFormer separator is available locally at
  `build/guitar_poc/roformer_models/becruily_guitar.ckpt` (about 45 MB). It
  successfully separated the existing 266 s 李荣浩《名字》 mix in about 109 s
  on this Mac. This is a useful extraction path, but it is a separator rather
  than a detector: it always produces a guitar estimate and does not decide
  whether the target lead event is present.
- A one-song leakage diagnostic compares the 2:54–3:30 Demucs and RoFormer
  guitar outputs with the corresponding Demucs vocal, drum, and bass stems. At
  a fixed 1.5 kHz gate (35% of the Demucs guitar P90) and a 150 ms persistence
  rule, the drum stem still crosses the gate on 18.2% of frames, vocal on 4.3%,
  and bass on 0%; guitar outputs remain active on 84.3% and 86.9%. This is
  **not** a classifier precision/recall score and does not measure leakage in
  the original mix. It demonstrates that a high-frequency amplitude gate
  alone cannot reliably distinguish guitar sustain from cymbals.
- Reproduce the stem leakage diagnostic with `Tools/evaluate_guitar_stem_control.py`;
  the current report is `build/guitar_poc/lead_guitar_leakage_diagnostic.json`.
- The same fixed gate was also evaluated over the complete 266 s song. With a
  150 ms persistence rule, the vocal stem crosses it on 23.7% of frames and
  drums on 15.9%; guitar output is active on 35.4% (Demucs) and 50.5%
  (RoFormer). This whole-song diagnostic is in
  `build/guitar_poc/lead_guitar_full_song_leakage_diagnostic.json` and confirms
  that thresholding the separated high-frequency stem is not a sufficiently
  selective general event detector.
- The checked-out LeadInstrumentDetection repository still has MedleyDB
  annotations only, with no corresponding audio. The public sample download
  was attempted but observed at only about 10–20 KiB/s; that incomplete
  transfer was stopped. No held-out, multi-song prediction score exists yet.
