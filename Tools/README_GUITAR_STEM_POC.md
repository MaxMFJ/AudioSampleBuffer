# Sustained electric guitar stem PoC

## Decision target

Extract the sustained/lead electric-guitar layer from a full song and use only
that file as an audio-analysis input. This is an offline separation experiment;
it does not make a remix, identify song sections, or generate an event timeline.

## Candidate models

1. **Mel-Band RoFormer Guitar (becruily)** — first candidate. Its published
   config is explicitly trained for `Guitar` with `Other` as the residual
   source, rather than relying on a generic `Other` stem. The checkpoint is
   about 45 MB. It is a guitar stem, not a lead-only classifier, so rhythm
   guitar may also pass through.
2. **Demucs `htdemucs_6s`** — easy baseline. It adds `guitar` and `piano` to
   vocals/drums/bass/other. The upstream project describes guitar quality as
   okay with substantial bleed/artifacts; treat it as a baseline, not a clean
   signal guarantee.
3. **BS-RoFormer MVSep Mega 53 stems** — follow-up if the first two do not
   isolate the lead sufficiently. It has `electric-guitar` and `guitar`
   outputs, but is memory-heavy (upstream recommends at least 16 GB VRAM) and
   reports overlapping stems. This is not the first local test on this Mac.

## Run the first baseline

```sh
python3 -m venv .venv-demucs
source .venv-demucs/bin/activate
python -m pip install -U pip demucs soundfile numpy
python Tools/demucs_stem_probe.py "/path/to/climax-song.mp3" --out build/guitar_poc
```

Listen to `build/guitar_poc/htdemucs_6s/<track>/guitar.wav` alongside the
original at matched loudness. In the chorus/climax, check whether sustained
guitar notes remain continuous while drums, vocals, bass and cymbals no longer
cause comparable activity. The script also writes `summary.json` and
`frames.csv` for offline RMS/band-energy curves. Those curves measure the
candidate control signal; they do not by themselves prove source purity.

The targeted RoFormer checkpoint/config are available at
[`becruily/mel-band-roformer-guitar`](https://huggingface.co/becruily/mel-band-roformer-guitar).
The repository provides a config and checkpoint, but no model card or
documented ready-to-run CLI recipe. For this run, `audio-separator 0.47.0` was
used with a local model-registry entry. Its bundled RoFormer code defaulted the
mask-estimator MLP expansion factor to 4 instead of honoring the checkpoint's
configured value 1, so the isolated virtualenv implementation was patched to
pass that value through. No app/repository source code was modified for this
compatibility workaround. The exact inference invocation was:

```sh
audio-separator "build/guitar_poc/input/李荣浩 - 名字.mp3" \
  --model_filename becruily_guitar.ckpt \
  --model_file_dir build/guitar_poc/roformer_models \
  --output_dir build/guitar_poc/melband_output \
  --output_format WAV --single_stem Guitar
```

Export the model's Guitar stem to WAV, then run the probe in analysis-only mode:

```sh
python Tools/demucs_stem_probe.py "/path/to/climax-song.mp3" \
  --skip-demucs --separated-dir "/path/to/roformer-output"
```

The separated directory must contain `guitar.wav` (or `guitar.flac` / `guitar.mp3`).

## Acceptance for this visual-control use

- The target's sustained guitar notes are clearly audible and remain present
  through their decays/reverb tails.
- Non-guitar events in the chosen passage do not create similarly strong
  sustained activity in the guitar file.
- Feed the guitar WAV alone to the existing analyzer and compare its activity
  curve against the full mix. Do not mix the original back into that input.
- If the six-stem Demucs file has obvious drum/vocal/bass leakage, try the
  guitar-targeted RoFormer or the 53-stem model before deciding whether the
  signal is clean enough.

## First run: 李荣浩《名字》

The project QQMP3 API returned the matching track metadata and a direct MP3
stream. The local input is `build/guitar_poc/input/李荣浩 - 名字.mp3` (266.37 s).
Its credits list guitar (李荣浩), bass (李荣浩), and drums (李彦超).

Both candidates completed separation on the full song:

| Model | Guitar output | Run time | Whole-file RMS |
|---|---|---:|---:|
| Demucs `htdemucs_6s` | `build/guitar_poc/separated/htdemucs_6s/李荣浩 - 名字/guitar.wav` | 28 s | -22.66 dBFS |
| Mel-Band RoFormer Guitar (`becruily`) | `build/guitar_poc/melband_output/李荣浩 - 名字_(Guitar)_becruily_guitar.wav` | 109 s on Apple Silicon MPS | -22.55 dBFS |

The frame curves are in `build/guitar_poc/separated/frames.csv` and
`build/guitar_poc/melband_probe/frames.csv`. The first chorus (51–70 s) measures
-26.1 dBFS for Demucs and -22.7 dBFS for RoFormer; the final chorus (203–240 s)
measures -19.5 and -20.0 dBFS respectively. Both produce an activity signal
that rises in the climactic passages, while RoFormer retains more level in
the quieter early verses. These values are not separation-purity scores:
neither input nor output stems have an independent clean-guitar reference.

Nineteen-second chorus audition files (51–70 s) are in `build/guitar_poc/previews/`.
The two stem previews are loudness-normalized for listening comparison only;
use the original WAV stems, not these previews, for audio analysis.

**PoC finding:** a usable, time-aligned Guitar stem can be extracted from this
full song with both models, and its energy curve is available to drive analysis
without feeding drums/vocals/bass from the original mix. Whether residual bleed
is low enough to avoid unwanted visual triggers still needs a brief listening
check of the two files. The stem represents Guitar generally; it does not
classify lead versus rhythm guitar.

## Deep Space Honeycomb visual-control PoC

`李荣浩-名字-02m54-03m30-Demucs-Guitar-stereo.wav` is converted to the bundled
50 ms high-band envelope `AudioSampleBuffer/Resources/LiRongHao-MingZi-GuitarControl.csv`.
During playback of 李荣浩《名字》, the visual renderer samples that envelope only
between 174 and 210 seconds; the isolated WAV is never added to audible playback.
The Cellular Wormhole / 深空蜂巢 renderer uses this dedicated control during the
matched segment, launching a pink lead-guitar color front at the throat and
spreading it outward. Its surface tint fades back to the selected palette after
the control envelope falls. Regenerate the compact curve with:

```sh
python3 Tools/make_guitar_stem_control.py \
  "build/guitar_poc/clips/李荣浩-名字-02m54-03m30-Demucs-Guitar-stereo.wav" \
  "AudioSampleBuffer/Resources/LiRongHao-MingZi-GuitarControl.csv"
```

This is a song-specific PoC based on the existing Demucs guitar stem. It does
not classify guitars in arbitrary songs.

## Full-song A/B experiment in 深空蜂巢

The app now bundles `LiRongHao-MingZi-GuitarControl-Full.csv`, a 50 ms control
curve for the full 266.37 s Demucs Guitar stem. It is a small derived signal,
not the WAV stem or the 45 MB separation model. Generate it from the full stem:

```sh
.venv-demucs/bin/python Tools/make_guitar_stem_control.py \
  "build/guitar_poc/separated/htdemucs_6s/李荣浩 - 名字/guitar.wav" \
  "AudioSampleBuffer/Resources/LiRongHao-MingZi-GuitarControl-Full.csv" \
  --calibration-start-sec 174 --calibration-end-sec 210
```

The 174–210 s portion uses the previous PoC's scale and matches its 720
control frames exactly. In the effect selector, choose 深空蜂巢 and tap its
settings gear. The “电脑分离数据（Demucs）” switch is off by default. When enabled,
only a track whose title/artist match 李荣浩《名字》 and duration is within 2 s of
266.37 s uses the full-song curve. All other tracks continue to use YAMNet.
Turning the switch off restores YAMNet control immediately; YAMNet analysis
and its cache remain enabled while the experiment switch is on.

The console prints `[GuitarVisual] Demucs full-song check` or
`[GuitarVisual] YAMNet guitar check` every two seconds while 深空蜂巢 is selected.
This is a one-song visual comparison, not evidence that a generic guitar
detector works on other songs.

## On-device Demucs handover experiment

The settings panel has a separate **手机本地 Demucs（实验）** switch. With it
enabled, any local song starts immediately while YAMNet remains the control
source. In parallel, the app reads the track, runs the bundled
HTDemucs6s Guitar Core ML model in 7-second chunks with 2 seconds of overlap,
and writes only a 50 ms guitar control envelope into the app cache. When the
full curve is ready, 深空蜂巢 switches sources at the current playback time;
replays can reuse the content-hash cache. The existing **电脑分离数据（Demucs）**
switch remains available for the bundled offline reference curve for 李荣浩《名字》.

The model package is 186 MB and targets iOS 16, matching the app's minimum OS.
The simulator app bundle is approximately 287 MB including both YAMNet and
Demucs resources. The model is converted from the local `htdemucs_6s` checkpoint
and emits the guitar source only. The Core ML package conversion passed its
numerical comparison against the PyTorch wrapper on macOS, and the Xcode
simulator build succeeds.

This is wired for a real-device experiment, not yet accepted as a phone
performance result: the connected iPhone was unavailable during this build, so
on-device inference time, peak memory, thermal behavior, and the final visual
handover still need to be measured on the phone. The phone cache stores only
the derived control curve; it does not store a separated WAV or replace the
original playback audio.
