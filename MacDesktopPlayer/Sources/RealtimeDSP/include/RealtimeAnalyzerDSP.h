//
//  RealtimeAnalyzerDSP.h
//  AudioSampleBuffer
//
//  Pure C DSP core for RealtimeAnalyzer — eliminates NSNumber boxing overhead
//  and leverages Accelerate vDSP for vectorized computation.
//
//  Pipeline:
//    samples → window → FFT → magnitude → A-weighting → 80 log-spaced bands
//                                       → HPSS (FitzGerald 2010 + Driedger 2014)
//                                         → H / P / R magnitude spectra
//                                         → category features (sub-bass, transient,
//                                                              harmonic, noise/FX)
//

#ifndef RealtimeAnalyzerDSP_h
#define RealtimeAnalyzerDSP_h

#include <Accelerate/Accelerate.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

#pragma mark - Types

/// Opaque handle to the DSP context
typedef struct AnalyzerDSP *AnalyzerDSPRef;

/// Per-channel category-level features extracted by HPSS pipeline.
/// All values are normalized post-A-weighting, so magnitudes are
/// comparable across frames once temporally smoothed by the caller.
typedef struct {
    float subBass;            // 20–60 Hz energy from H component
    float bass;               // 60–120 Hz energy from H component
    float lowEnergy;          // subBass + bass convenience sum
    float transient;          // SuperFlux-style onset strength on P component
    float harmonic;           // total energy of H component
    float harmonicPeakRatio;  // H_peak / H_mean — closer to 1 = noise-like, ≫1 = strongly tonal
    float noise;              // total energy of R (residual) component
    float spectralFlatness;   // SFM 0..1 (Wiener entropy / arithmetic mean)
} AnalyzerCategoryFeatures;

#pragma mark - Lifecycle

/// Create a new DSP context.
/// @param fftSize        FFT window size (e.g. 4096). Must be power of 2.
/// @param frequencyBands Number of output bands (e.g. 80).
/// @param startFrequency Lower frequency bound in Hz (e.g. 50).
/// @param endFrequency   Upper frequency bound in Hz (e.g. 18000).
/// @param sampleRate     Sample rate in Hz used for A-weight computation (e.g. 44100).
/// @return Non-NULL handle on success.
AnalyzerDSPRef AnalyzerDSP_Create(int fftSize,
                                   int frequencyBands,
                                   float startFrequency,
                                   float endFrequency,
                                   float sampleRate);

/// Destroy the DSP context and free all memory.
void AnalyzerDSP_Destroy(AnalyzerDSPRef ref);

#pragma mark - Configuration

/// Set the spectrum smoothing factor (clamped to 0..1).
void AnalyzerDSP_SetSpectrumSmooth(AnalyzerDSPRef ref, float smooth);

/// Configure HPSS parameters (defaults: 11, 17, 1.8). Lengths must be odd & ≤ 31.
void AnalyzerDSP_SetHPSSParameters(AnalyzerDSPRef ref,
                                    int timeMedianLen,
                                    int freqMedianLen,
                                    float separationFactor);

#pragma mark - Processing

/// Run the full analysis pipeline on a single channel of float samples.
/// The result is written into the internal spectrum buffer and smoothed over time.
/// Samples are accumulated into an internal `fftSize` sliding window so the
/// caller may pass shorter chunks (e.g. tap bufferSize 2048 for fftSize 4096).
///
/// @param ref             DSP context.
/// @param samples         Pointer to incoming float samples for one channel.
/// @param sampleCount     Number of new samples (≤ fftSize). 0 → reuse last window.
/// @param channelIndex    Channel index (0 or 1).
/// @param amplitudeLevel  Amplitude scaling factor.
/// @param sampleRate      Actual sample rate of the buffer.
/// @param outBands        Output buffer of at least `frequencyBands` floats.
///                        Receives the smoothed spectrum for this channel.
void AnalyzerDSP_ProcessChannel(AnalyzerDSPRef ref,
                                const float *samples,
                                int sampleCount,
                                int channelIndex,
                                int amplitudeLevel,
                                float sampleRate,
                                float *outBands);

/// Legacy exact-frame path restored for live beat / background FX.
/// This matches the old 2048-frame analyzer behavior: no sliding accumulation,
/// just process the current exact frame.
void AnalyzerDSP_ProcessChannelLegacyExact(AnalyzerDSPRef ref,
                                           const float *samples,
                                           int channelIndex,
                                           int amplitudeLevel,
                                           float sampleRate,
                                           float *outBands);

/// Extended pipeline: also runs HPSS and returns 4-class category features
/// plus per-component band spectra for visualisation. Pass NULL for any
/// output you don't need; the others are still computed correctly.
void AnalyzerDSP_ProcessChannelExtended(AnalyzerDSPRef ref,
                                         const float *samples,
                                         int sampleCount,
                                         int channelIndex,
                                         int amplitudeLevel,
                                         float sampleRate,
                                         float *outBands,        // mixed (existing)
                                         float *outHBands,       // harmonic 80 bands
                                         float *outPBands,       // percussive 80 bands
                                         float *outRBands,       // residual / noise 80 bands
                                         AnalyzerCategoryFeatures *outCat);

#pragma mark - Accessors

/// Get the number of frequency bands.
int AnalyzerDSP_GetFrequencyBands(AnalyzerDSPRef ref);

/// Get the FFT size.
int AnalyzerDSP_GetFFTSize(AnalyzerDSPRef ref);

#ifdef __cplusplus
}
#endif

#endif /* RealtimeAnalyzerDSP_h */
