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
    int      *bandStartBin;     // per-band start bin index [frequencyBands]
    int      *bandEndBin;       // per-band end bin index   [frequencyBands]

    // Temporal smoothing buffers (per channel, max 2 channels)
    float *spectrumBuffer[2];   // [frequencyBands] each

    // Highlight kernel for vDSP_conv [0.25, 0.5, 0.25]
    float highlightKernel[3];
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

/// Precompute bin index range for each band (avoids per-frame division in hot path).
static void ComputeBandBins(int *bandStartBin, int *bandEndBin,
                            const BandRange *bands, int bandCount,
                            float bandWidth, int halfFFTSize) {
    for (int i = 0; i < bandCount; i++) {
        int startIdx = (int)(bands[i].lowerFrequency / bandWidth + 0.5f);
        int endIdx   = (int)(bands[i].upperFrequency / bandWidth + 0.5f);
        if (endIdx >= halfFFTSize) endIdx = halfFFTSize - 1;
        if (startIdx < 0) startIdx = 0;
        if (startIdx > endIdx) endIdx = startIdx;
        bandStartBin[i] = startIdx;
        bandEndBin[i]   = endIdx;
    }
}

/// 3-point weighted average smoothing via vDSP_conv: kernel [0.25, 0.5, 0.25]
static void HighlightWaveform(const float *input, float *output, int count,
                              const float *kernel) {
    if (count <= 2) {
        memcpy(output, input, (size_t)count * sizeof(float));
        return;
    }
    output[0] = input[0];
    output[count - 1] = input[count - 1];
    const unsigned long resultLen = (unsigned long)(count - 2);
    if (resultLen > 0) {
        vDSP_conv(input, 1, kernel, 1, output + 1, 1, resultLen, 3);
    }
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

    // Pre-compute band bin indices (avoids per-frame division in hot path)
    {
        const float bandWidth = sampleRate / (float)fftSize;
        ref->bandStartBin = (int *)calloc((size_t)frequencyBands, sizeof(int));
        ref->bandEndBin   = (int *)calloc((size_t)frequencyBands, sizeof(int));
        ComputeBandBins(ref->bandStartBin, ref->bandEndBin,
                       ref->bands, frequencyBands, bandWidth, ref->halfFFTSize);
    }

    // Highlight kernel for vDSP_conv: [0.25, 0.5, 0.25]
    ref->highlightKernel[0] = 0.25f;
    ref->highlightKernel[1] = 0.5f;
    ref->highlightKernel[2] = 0.25f;

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
    free(ref->bandStartBin);
    free(ref->bandEndBin);
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

    // ── Step 5: Map to frequency bands (precomputed bin indices + vDSP_maxv) ─
    const float ampScale = (float)amplitudeLevel;
    for (int i = 0; i < bands; i++) {
        int startIdx = ref->bandStartBin[i];
        int endIdx   = ref->bandEndBin[i];
        float maxVal = 0.0f;
        vDSP_Length len = (vDSP_Length)(endIdx - startIdx + 1);
        if (len > 0) {
            vDSP_maxv(ref->weightedMags + startIdx, 1, &maxVal, len);
        }
        ref->bandSpectrum[i] = maxVal * ampScale;
    }

    // ── Step 6: Highlight waveform (vDSP_conv 3-point kernel) ────────────
    HighlightWaveform(ref->bandSpectrum, ref->smoothedSpectrum, bands, ref->highlightKernel);

    // ── Step 7: Temporal smoothing (vectorized: buf = old*buf + new*smoothed) ─
    float *buf = ref->spectrumBuffer[channelIndex];
    const float oldFactor = ref->spectrumSmooth;
    const float newFactor = 1.0f - oldFactor;
    vDSP_vsmul(buf, 1, &oldFactor, buf, 1, (vDSP_Length)bands);
    vDSP_vsma(ref->smoothedSpectrum, 1, &newFactor, buf, 1, buf, 1, (vDSP_Length)bands);
    for (int i = 0; i < bands; i++) {
        float val = buf[i];
        buf[i] = (val == val) ? val : 0.0f;  // NaN → 0
        outBands[i] = buf[i];
    }
}

int AnalyzerDSP_GetFrequencyBands(AnalyzerDSPRef ref) {
    return ref ? ref->frequencyBands : 0;
}

int AnalyzerDSP_GetFFTSize(AnalyzerDSPRef ref) {
    return ref ? ref->fftSize : 0;
}
