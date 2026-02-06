//
//  RealtimeAnalyzerDSP.h
//  AudioSampleBuffer
//
//  Pure C DSP core for RealtimeAnalyzer — eliminates NSNumber boxing overhead
//  and leverages Accelerate vDSP for vectorized computation.
//

#ifndef RealtimeAnalyzerDSP_h
#define RealtimeAnalyzerDSP_h

#include <Accelerate/Accelerate.h>
#include <stdbool.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Opaque handle to the DSP context
typedef struct AnalyzerDSP *AnalyzerDSPRef;

#pragma mark - Lifecycle

/// Create a new DSP context.
/// @param fftSize        FFT window size (e.g. 2048). Must be power of 2.
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

#pragma mark - Processing

/// Run the full analysis pipeline on a single channel of float samples.
/// The result is written into the internal spectrum buffer and smoothed over time.
///
/// @param ref             DSP context.
/// @param samples         Pointer to `fftSize` float samples for one channel.
/// @param channelIndex    Channel index (0 or 1).
/// @param amplitudeLevel  Amplitude scaling factor.
/// @param sampleRate      Actual sample rate of the buffer (for bandwidth calc).
/// @param outBands        Output buffer of at least `frequencyBands` floats.
///                        Receives the smoothed spectrum for this channel.
void AnalyzerDSP_ProcessChannel(AnalyzerDSPRef ref,
                                const float *samples,
                                int channelIndex,
                                int amplitudeLevel,
                                float sampleRate,
                                float *outBands);

#pragma mark - Accessors

/// Get the number of frequency bands.
int AnalyzerDSP_GetFrequencyBands(AnalyzerDSPRef ref);

/// Get the FFT size.
int AnalyzerDSP_GetFFTSize(AnalyzerDSPRef ref);

#ifdef __cplusplus
}
#endif

#endif /* RealtimeAnalyzerDSP_h */
