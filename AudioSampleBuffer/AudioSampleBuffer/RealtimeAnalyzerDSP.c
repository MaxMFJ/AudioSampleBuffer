//
//  RealtimeAnalyzerDSP.c
//  AudioSampleBuffer
//
//  Pure C DSP core — all heavy computation done with float* and vDSP.
//  Zero Objective-C, zero NSNumber boxing, zero ARC overhead in the hot path.
//

#include "RealtimeAnalyzerDSP.h"
#include <stdlib.h>
#include <string.h>
#include <math.h>

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Internal Types
// ─────────────────────────────────────────────────────────────────────────────

typedef struct {
    float lowerFrequency;
    float upperFrequency;
} BandRange;

struct AnalyzerDSP {
    // Configuration
    int   fftSize;
    int   halfFFTSize;          // fftSize / 2
    int   frequencyBands;
    float startFrequency;
    float endFrequency;
    float spectrumSmooth;       // 0..1, default 0.65

    // FFT
    FFTSetup    fftSetup;
    vDSP_Length log2n;

    // Pre-allocated work buffers (avoid per-frame malloc)
    float *window;              // Hanning window    [fftSize]
    float *windowedSamples;     // windowed copy     [fftSize]
    float *fftReals;            // split complex real [halfFFTSize]
    float *fftImags;            // split complex imag [halfFFTSize]
    float *magnitudes;          // |FFT|             [halfFFTSize]
    float *weightedMags;        // magnitudes * aWeights [halfFFTSize]
    float *bandSpectrum;        // per-band max      [frequencyBands]
    float *smoothedSpectrum;    // after highlight   [frequencyBands]

    // Pre-computed tables
    float    *aWeights;         // A-weighting       [halfFFTSize]
    BandRange *bands;           // frequency ranges   [frequencyBands]

    // Temporal smoothing buffers (per channel, max 2 channels)
    float *spectrumBuffer[2];   // [frequencyBands] each
};

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Internal Helpers
// ─────────────────────────────────────────────────────────────────────────────

/// Compute A-weighting coefficients for `halfFFTSize` bins.
static void ComputeAWeights(float *weights, int halfFFTSize, int fftSize, float sampleRate) {
    const float deltaF = sampleRate / (float)fftSize;

    const float c1 = 12194.217f * 12194.217f;
    const float c2 = 20.598997f * 20.598997f;
    const float c3 = 107.65265f * 107.65265f;
    const float c4 = 737.86223f * 737.86223f;

    for (int i = 0; i < halfFFTSize; i++) {
        float freq = (float)i * deltaF;
        float f2 = freq * freq;                       // f^2
        float num = c1 * f2 * f2;                      // c1 * f^4
        float den = (f2 + c2)
                    * sqrtf((f2 + c3) * (f2 + c4))
                    * (f2 + c1);
        weights[i] = (den > 0.0f) ? (1.2589f * num / den) : 0.0f;
    }
}

/// Build logarithmically-spaced frequency band ranges.
static void ComputeBands(BandRange *bands, int count,
                         float startFreq, float endFreq) {
    const float n = log2f(endFreq / startFreq) / (float)count;
    float lower = startFreq;
    for (int i = 0; i < count; i++) {
        float upper = lower * powf(2.0f, n);
        if (i == count - 1) upper = endFreq;
        bands[i].lowerFrequency = lower;
        bands[i].upperFrequency = upper;
        lower = lower * powf(2.0f, n);
    }
}

/// Find the maximum value in magnitudes[startIdx .. endIdx].
/// Uses vDSP_maxv for vectorized max.
static inline float FindMaxInRange(const float *magnitudes, int totalBins,
                                   float lowerFreq, float upperFreq,
                                   float bandWidth) {
    int startIdx = (int)(lowerFreq / bandWidth + 0.5f);
    int endIdx   = (int)(upperFreq / bandWidth + 0.5f);
    if (endIdx >= totalBins) endIdx = totalBins - 1;
    if (startIdx >= totalBins || startIdx > endIdx) return 0.0f;

    vDSP_Length count = (vDSP_Length)(endIdx - startIdx + 1);
    if (count == 1) return magnitudes[startIdx];

    float maxVal = 0.0f;
    vDSP_maxv(magnitudes + startIdx, 1, &maxVal, count);
    return maxVal;
}

/// 3-point weighted average smoothing: weights = {0.5, 1.0, 0.5}, sum = 2.0
static void HighlightWaveform(const float *input, float *output, int count) {
    if (count <= 2) {
        memcpy(output, input, (size_t)count * sizeof(float));
        return;
    }

    // First element: pass through
    output[0] = input[0];

    // Middle elements: weighted average
    const float invTotalWeight = 1.0f / 2.0f;  // 0.5 + 1.0 + 0.5 = 2.0
    for (int i = 1; i < count - 1; i++) {
        output[i] = (input[i - 1] * 0.5f
                   + input[i]     * 1.0f
                   + input[i + 1] * 0.5f) * invTotalWeight;
    }

    // Last element: pass through
    output[count - 1] = input[count - 1];
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Public API
// ─────────────────────────────────────────────────────────────────────────────

AnalyzerDSPRef AnalyzerDSP_Create(int fftSize,
                                   int frequencyBands,
                                   float startFrequency,
                                   float endFrequency,
                                   float sampleRate) {
    AnalyzerDSPRef ref = (AnalyzerDSPRef)calloc(1, sizeof(struct AnalyzerDSP));
    if (!ref) return NULL;

    ref->fftSize        = fftSize;
    ref->halfFFTSize    = fftSize / 2;
    ref->frequencyBands = frequencyBands;
    ref->startFrequency = startFrequency;
    ref->endFrequency   = endFrequency;
    ref->spectrumSmooth = 0.65f;
    ref->log2n          = (vDSP_Length)roundf(log2f((float)fftSize));

    // FFT setup
    ref->fftSetup = vDSP_create_fftsetup(ref->log2n, kFFTRadix2);

    // Allocate work buffers
    ref->window          = (float *)calloc((size_t)fftSize,        sizeof(float));
    ref->windowedSamples = (float *)calloc((size_t)fftSize,        sizeof(float));
    ref->fftReals        = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->fftImags        = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->magnitudes      = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->weightedMags    = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->bandSpectrum    = (float *)calloc((size_t)frequencyBands,  sizeof(float));
    ref->smoothedSpectrum= (float *)calloc((size_t)frequencyBands,  sizeof(float));

    // Pre-compute Hanning window (done once, reused every frame)
    vDSP_hann_window(ref->window, (vDSP_Length)fftSize, vDSP_HANN_NORM);

    // Pre-compute A-weighting table
    ref->aWeights = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ComputeAWeights(ref->aWeights, ref->halfFFTSize, fftSize, sampleRate);

    // Pre-compute frequency band ranges
    ref->bands = (BandRange *)calloc((size_t)frequencyBands, sizeof(BandRange));
    ComputeBands(ref->bands, frequencyBands, startFrequency, endFrequency);

    // Spectrum smoothing buffers (2 channels)
    for (int ch = 0; ch < 2; ch++) {
        ref->spectrumBuffer[ch] = (float *)calloc((size_t)frequencyBands, sizeof(float));
    }

    return ref;
}

void AnalyzerDSP_Destroy(AnalyzerDSPRef ref) {
    if (!ref) return;
    if (ref->fftSetup) vDSP_destroy_fftsetup(ref->fftSetup);
    free(ref->window);
    free(ref->windowedSamples);
    free(ref->fftReals);
    free(ref->fftImags);
    free(ref->magnitudes);
    free(ref->weightedMags);
    free(ref->bandSpectrum);
    free(ref->smoothedSpectrum);
    free(ref->aWeights);
    free(ref->bands);
    for (int ch = 0; ch < 2; ch++) free(ref->spectrumBuffer[ch]);
    free(ref);
}

void AnalyzerDSP_SetSpectrumSmooth(AnalyzerDSPRef ref, float smooth) {
    if (!ref) return;
    if (smooth < 0.0f) smooth = 0.0f;
    if (smooth > 1.0f) smooth = 1.0f;
    ref->spectrumSmooth = smooth;
}

void AnalyzerDSP_ProcessChannel(AnalyzerDSPRef ref,
                                const float *samples,
                                int channelIndex,
                                int amplitudeLevel,
                                float sampleRate,
                                float *outBands) {
    if (!ref || !samples || !outBands) return;
    if (channelIndex < 0 || channelIndex > 1) return;

    const int N    = ref->fftSize;
    const int half = ref->halfFFTSize;
    const int bands = ref->frequencyBands;

    // ── Step 1: Apply Hanning window ──────────────────────────────────────
    // vDSP_vmul: element-wise multiply samples * window → windowedSamples
    vDSP_vmul(samples, 1, ref->window, 1, ref->windowedSamples, 1, (vDSP_Length)N);

    // ── Step 2: Pack into split complex and run FFT ──────────────────────
    DSPSplitComplex splitComplex = { ref->fftReals, ref->fftImags };
    vDSP_ctoz((const DSPComplex *)ref->windowedSamples, 2, &splitComplex, 1, (vDSP_Length)half);
    vDSP_fft_zrip(ref->fftSetup, &splitComplex, 1, ref->log2n, FFT_FORWARD);

    // ── Step 3: Normalize and compute magnitudes ─────────────────────────
    splitComplex.imagp[0] = 0.0f;
    float normFactor = 1.0f / (float)N;
    vDSP_vsmul(splitComplex.realp, 1, &normFactor, splitComplex.realp, 1, (vDSP_Length)half);
    vDSP_vsmul(splitComplex.imagp, 1, &normFactor, splitComplex.imagp, 1, (vDSP_Length)half);
    vDSP_zvabs(&splitComplex, 1, ref->magnitudes, 1, (vDSP_Length)half);
    ref->magnitudes[0] *= 0.5f;  // DC component adjustment

    // ── Step 4: Apply A-weighting (vectorized multiply) ──────────────────
    vDSP_vmul(ref->magnitudes, 1, ref->aWeights, 1, ref->weightedMags, 1, (vDSP_Length)half);

    // ── Step 5: Map to frequency bands (find max per band) ───────────────
    const float bandWidth = sampleRate / (float)N;
    const float ampScale = (float)amplitudeLevel;
    for (int i = 0; i < bands; i++) {
        float maxVal = FindMaxInRange(ref->weightedMags, half,
                                      ref->bands[i].lowerFrequency,
                                      ref->bands[i].upperFrequency,
                                      bandWidth);
        ref->bandSpectrum[i] = maxVal * ampScale;
    }

    // ── Step 6: Highlight waveform (3-point weighted average) ────────────
    HighlightWaveform(ref->bandSpectrum, ref->smoothedSpectrum, bands);

    // ── Step 7: Temporal smoothing ───────────────────────────────────────
    float *buf = ref->spectrumBuffer[channelIndex];
    const float oldFactor = ref->spectrumSmooth;
    const float newFactor = 1.0f - oldFactor;
    for (int i = 0; i < bands; i++) {
        float val = buf[i] * oldFactor + ref->smoothedSpectrum[i] * newFactor;
        // Replace NaN with 0
        buf[i] = (val == val) ? val : 0.0f;  // NaN != NaN
        outBands[i] = buf[i];
    }
}

int AnalyzerDSP_GetFrequencyBands(AnalyzerDSPRef ref) {
    return ref ? ref->frequencyBands : 0;
}

int AnalyzerDSP_GetFFTSize(AnalyzerDSPRef ref) {
    return ref ? ref->fftSize : 0;
}
