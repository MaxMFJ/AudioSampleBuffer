# HPSS 4-Class DSP Validation

This note records the validation workflow for the new DSP split:
- Sub-Bass / Bass (20-120 Hz, from H component)
- Transient (SuperFlux on P component)
- Harmonic (H component energy + peak ratio)
- Noise/FX (R component + spectral flatness)

## Build Validation

- Ran local simulator build:
  - `xcodebuild -project "AudioSampleBuffer.xcodeproj" -scheme "AudioSampleBuffer" -configuration Debug -sdk iphonesimulator build`
  - Result: `BUILD SUCCEEDED`

## Runtime Validation Checklist

Use three representative clips:
1. `castanets + violin` mixture
2. `kick-heavy EDM loop`
3. `white-noise sweep / riser`

For each clip, verify:
- `subBassEnergy` rises strongly on kick/sub content.
- `transientStrength` spikes on attacks (snare/hihat/pluck).
- `harmonicStrength` remains stable on tonal sustained notes.
- `noiseStrength` and `spectralFlatness` rise on riser/noise sections.
- `subBassHit` cadence yields stable BPM estimation.

## Expected CPU Profile

With FFT 4096 and tap chunk 2048 (50% overlap):
- Analyzer remains real-time on iPhone-class devices.
- Target budget: DSP processing under 1 ms/frame in Time Profiler.

## Instruments Procedure

1. Launch app in Debug on simulator/device.
2. Start `Instruments -> Time Profiler`.
3. Play the three test clips above for at least 30 seconds each.
4. Confirm no sustained hot spot in:
   - `AnalyzerDSP_ProcessChannelExtended`
   - `TimeMedianFilter`
   - `FreqMedianFilter`
5. Save traces for regression comparison.

# HPSS 4-Class DSP Validation

This note records the validation workflow for the new DSP split:
- Sub-Bass / Bass (20-120 Hz, from H component)
- Transient (SuperFlux on P component)
- Harmonic (H component energy + peak ratio)
- Noise/FX (R component + spectral flatness)

## Build Validation

- Ran local simulator build:
  - `xcodebuild -project "AudioSampleBuffer.xcodeproj" -scheme "AudioSampleBuffer" -configuration Debug -sdk iphonesimulator build`
  - Result: `BUILD SUCCEEDED`

## Runtime Validation Checklist

Use three representative clips:
1. `castanets + violin` mixture
2. `kick-heavy EDM loop`
3. `white-noise sweep / riser`

For each clip, verify:
- `subBassEnergy` rises strongly on kick/sub content.
- `transientStrength` spikes on attacks (snare/hihat/pluck).
- `harmonicStrength` remains stable on tonal sustained notes.
- `noiseStrength` and `spectralFlatness` rise on riser/noise sections.
- `subBassHit` cadence yields stable BPM estimation.

## Expected CPU Profile

With FFT 4096 and tap chunk 2048 (50% overlap):
- Analyzer remains real-time on iPhone-class devices.
- Target budget: DSP processing under 1 ms/frame in Time Profiler.

## Instruments Procedure

1. Launch app in Debug on simulator/device.
2. Start `Instruments -> Time Profiler`.
3. Play the three test clips above for at least 30 seconds each.
4. Confirm no sustained hot spot in:
   - `AnalyzerDSP_ProcessChannelExtended`
   - `TimeMedianFilter`
   - `FreqMedianFilter`
5. Save traces for regression comparison.

