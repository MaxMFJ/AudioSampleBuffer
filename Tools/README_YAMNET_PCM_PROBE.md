# YAMNet Core ML PCM probe

This probe feeds the saved 36-second mono Guitar-stem PCM clip through YAMNet's
Core ML input pipeline. It does not change audible playback or bundle a model
into the app.

The published Core ML package expects one precomputed `Float16` log-mel patch
with shape `[1, 96, 64]`, rather than raw PCM. The tool resamples to 16 kHz,
computes 25 ms / 10 ms STFT frames with a periodic Hann window, maps magnitude
spectra to 64 mel bands from 125 to 7,500 Hz, applies `log(mel + 0.001)`, and
frames complete 0.96-second patches every 0.48 seconds. This follows the
official YAMNet feature definition.

## Recreate the Core ML package

The Core ML model used here was converted locally from the official TensorFlow
YAMNet checkpoint. The `.h5` weights and conversion intermediates live under
the ignored `build/guitar_poc` directory, so they do not enlarge the project
package. Download the official checkpoint and YAMNet source files into
`build/guitar_poc/yamnet_source`, then convert in a Python environment with
TensorFlow, `tf-keras`, `coremltools`, and NumPy installed:

```sh
python Tools/convert_yamnet_to_coreml.py \
  build/guitar_poc/yamnet_source \
  build/guitar_poc/yamnet_coreml/YAMNet.mlpackage
```

The converted model accepts a Float16 tensor shaped `[1, 96, 64]` and requires
iOS 16 or newer. The model itself classifies AudioSet classes; it does not
identify a guitar lead or sustain specifically.

The app target includes this 7.2 MB model package as a project resource;
Xcode compiles it into the app bundle. The app requires iOS 16 or newer. The
521-class score timeline is cached under Caches by the source audio SHA-256 and
YAMNet model version; no audio or model download is required.

## Run the PCM probe

The complete PCM-to-Core-ML inference command used for this PoC is:

```sh
python Tools/run_yamnet_coreml_on_pcm.py \
  "build/guitar_poc/clips/李荣浩-名字-02m54-03m30-Demucs-Guitar-mono.s16le" \
  --sample-rate 44100 \
  --model "build/guitar_poc/yamnet_coreml/YAMNet.mlpackage" \
  --output-prefix "build/guitar_poc/clips/李荣浩-名字-02m54-03m30-Demucs-Guitar"
```

This writes `*-yamnet-features.npz` (`[74, 96, 64]` for this clip),
`*-yamnet-scores.csv` with generic `Electric guitar` / `Guitar` class scores at
0.48-second intervals, and a JSON run summary. The CSV scores are not
probabilities for lead guitar or sustain. Since the input is already a
Demucs Guitar stem, this result proves the PCM-to-Core-ML path works but cannot
measure how often a full-mix input is falsely triggered by drums or vocals.
