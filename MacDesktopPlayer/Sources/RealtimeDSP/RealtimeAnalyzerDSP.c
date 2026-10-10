//
//  RealtimeAnalyzerDSP.c
//  AudioSampleBuffer
//
//  Pure C DSP core — all heavy computation done with float* and vDSP.
//  Zero Objective-C, zero NSNumber boxing, zero ARC overhead in the hot path.
//
//  HPSS three-component decomposition (FitzGerald 2010 + Driedger 2014)
//  is performed over a sliding circular history of recent power spectra.
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

#define ANALYZER_DSP_MAX_MEDIAN_LEN     31
#define ANALYZER_DSP_SUPERFLUX_LAG      2
#define ANALYZER_DSP_SUPERFLUX_RADIUS   3
#define ANALYZER_DSP_SUPERFLUX_RING     (ANALYZER_DSP_SUPERFLUX_LAG + 1)

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

    // Sliding sample buffer per channel — accumulates input into an fftSize window
    float *sampleBuffer[2];     // [fftSize]
    int    sampleFill[2];       // valid samples currently in buffer (0..fftSize)

    // Pre-allocated work buffers (avoid per-frame malloc)
    float *window;              // Hanning window      [fftSize]
    float *windowedSamples;     // windowed copy       [fftSize]
    float *fftReals;            // split complex real  [halfFFTSize]
    float *fftImags;            // split complex imag  [halfFFTSize]
    float *magnitudes;          // |FFT|               [halfFFTSize]
    float *power;               // magnitudes^2        [halfFFTSize]
    float *weightedMags;        // magnitudes * aWeights [halfFFTSize]
    float *bandSpectrum;        // per-band max        [frequencyBands]
    float *smoothedSpectrum;    // after highlight     [frequencyBands]

    // Pre-computed tables
    float    *aWeights;         // A-weighting         [halfFFTSize]
    BandRange *bands;           // frequency ranges    [frequencyBands]
    int      *bandStartBin;     // per-band start bin index [frequencyBands]
    int      *bandEndBin;       // per-band end bin index   [frequencyBands]

    // Temporal smoothing buffers (per channel, max 2 channels)
    float *spectrumBuffer[2];   // [frequencyBands] each

    // Highlight kernel for vDSP_conv [0.25, 0.5, 0.25]
    float highlightKernel[3];

    // ── HPSS state ──────────────────────────────────────────────────────────
    int   timeMedianLen;        // L_h, odd, ≤ ANALYZER_DSP_MAX_MEDIAN_LEN
    int   freqMedianLen;        // L_p, odd, ≤ ANALYZER_DSP_MAX_MEDIAN_LEN
    float separationFactor;     // β ≥ 1 (Driedger)

    // Power-spectrum history per channel:
    // historyPower[ch][frame * halfFFTSize + bin], frames in [0, timeMedianLen)
    float *historyPower[2];
    int    historyWriteIdx[2];  // next write slot in the ring
    int    historyValidCount[2];

    // Per-frame HPSS scratch
    float *Hmag2;               // harmonic-enhanced power [halfFFTSize]
    float *Pmag2;               // percussive-enhanced power [halfFFTSize]
    float *Hpow;                // H component power (after masking)
    float *Ppow;                // P
    float *Rpow;                // R
    float *Hbands;              // [frequencyBands]
    float *Pbands;              // [frequencyBands]
    float *Rbands;              // [frequencyBands]

    // SuperFlux: keep previous max-filtered P spectra (lag = ANALYZER_DSP_SUPERFLUX_LAG)
    float *pMaxFilteredRing[2]; // [SUPERFLUX_RING * halfFFTSize]
    int    superfluxRingIdx[2];
    int    superfluxRingValid[2];

    // Scratch for median filtering (caller-thread reused)
    float medianScratch[ANALYZER_DSP_MAX_MEDIAN_LEN];
    float maxFilterScratch[ANALYZER_DSP_MAX_MEDIAN_LEN * 2 + 1];
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

/// Map (already-A-weighted) magnitude spectrum to log-spaced bands via per-band max.
static void ProjectToBands(const float *weightedMags,
                           const int *bandStartBin,
                           const int *bandEndBin,
                           int bandCount,
                           float scale,
                           float *outBandsRaw) {
    for (int i = 0; i < bandCount; i++) {
        int startIdx = bandStartBin[i];
        int endIdx   = bandEndBin[i];
        float maxVal = 0.0f;
        vDSP_Length len = (vDSP_Length)(endIdx - startIdx + 1);
        if (len > 0) {
            vDSP_maxv(weightedMags + startIdx, 1, &maxVal, len);
        }
        outBandsRaw[i] = maxVal * scale;
    }
}

// Insertion-sort-based median for small odd lengths (≤ 31). Returns median value.
// Mutates the scratch array.
static inline float MedianSmall(float *scratch, int n) {
    for (int i = 1; i < n; i++) {
        float v = scratch[i];
        int j = i - 1;
        while (j >= 0 && scratch[j] > v) {
            scratch[j + 1] = scratch[j];
            j--;
        }
        scratch[j + 1] = v;
    }
    return scratch[n / 2];
}

// 1-D symmetric max filter over a window radius `r` on `input` of length `n`,
// written to `output`. Brute force; cheap because r ≤ ~3 in practice.
static void MaxFilter1D(const float *input, float *output, int n, int r) {
    if (n <= 0) return;
    if (r <= 0) {
        memcpy(output, input, (size_t)n * sizeof(float));
        return;
    }
    for (int i = 0; i < n; i++) {
        int lo = i - r; if (lo < 0) lo = 0;
        int hi = i + r; if (hi >= n) hi = n - 1;
        float m = input[lo];
        for (int k = lo + 1; k <= hi; k++) {
            if (input[k] > m) m = input[k];
        }
        output[i] = m;
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

    // HPSS defaults (FitzGerald 2010 + Driedger 2014)
    ref->timeMedianLen    = 11;
    ref->freqMedianLen    = 17;
    ref->separationFactor = 1.8f;

    // FFT setup
    ref->fftSetup = vDSP_create_fftsetup(ref->log2n, kFFTRadix2);

    // Allocate work buffers
    ref->window          = (float *)calloc((size_t)fftSize,            sizeof(float));
    ref->windowedSamples = (float *)calloc((size_t)fftSize,            sizeof(float));
    ref->fftReals        = (float *)calloc((size_t)ref->halfFFTSize,   sizeof(float));
    ref->fftImags        = (float *)calloc((size_t)ref->halfFFTSize,   sizeof(float));
    ref->magnitudes      = (float *)calloc((size_t)ref->halfFFTSize,   sizeof(float));
    ref->power           = (float *)calloc((size_t)ref->halfFFTSize,   sizeof(float));
    ref->weightedMags    = (float *)calloc((size_t)ref->halfFFTSize,   sizeof(float));
    ref->bandSpectrum    = (float *)calloc((size_t)frequencyBands,     sizeof(float));
    ref->smoothedSpectrum= (float *)calloc((size_t)frequencyBands,     sizeof(float));

    // Per-channel sample-accumulation buffers
    for (int ch = 0; ch < 2; ch++) {
        ref->sampleBuffer[ch] = (float *)calloc((size_t)fftSize, sizeof(float));
        ref->sampleFill[ch]   = 0;
    }

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

    // HPSS scratch
    ref->Hmag2 = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->Pmag2 = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->Hpow  = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->Ppow  = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->Rpow  = (float *)calloc((size_t)ref->halfFFTSize, sizeof(float));
    ref->Hbands = (float *)calloc((size_t)frequencyBands, sizeof(float));
    ref->Pbands = (float *)calloc((size_t)frequencyBands, sizeof(float));
    ref->Rbands = (float *)calloc((size_t)frequencyBands, sizeof(float));

    // History rings: timeMedianLen frames × halfFFTSize per channel
    for (int ch = 0; ch < 2; ch++) {
        ref->historyPower[ch] = (float *)calloc((size_t)(ref->timeMedianLen * ref->halfFFTSize),
                                                 sizeof(float));
        ref->historyWriteIdx[ch]   = 0;
        ref->historyValidCount[ch] = 0;
        ref->pMaxFilteredRing[ch]  = (float *)calloc((size_t)(ANALYZER_DSP_SUPERFLUX_RING * ref->halfFFTSize),
                                                       sizeof(float));
        ref->superfluxRingIdx[ch]   = 0;
        ref->superfluxRingValid[ch] = 0;
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
    free(ref->power);
    free(ref->weightedMags);
    free(ref->bandSpectrum);
    free(ref->smoothedSpectrum);
    free(ref->aWeights);
    free(ref->bands);
    free(ref->bandStartBin);
    free(ref->bandEndBin);
    free(ref->Hmag2);
    free(ref->Pmag2);
    free(ref->Hpow);
    free(ref->Ppow);
    free(ref->Rpow);
    free(ref->Hbands);
    free(ref->Pbands);
    free(ref->Rbands);
    for (int ch = 0; ch < 2; ch++) {
        free(ref->spectrumBuffer[ch]);
        free(ref->sampleBuffer[ch]);
        free(ref->historyPower[ch]);
        free(ref->pMaxFilteredRing[ch]);
    }
    free(ref);
}

void AnalyzerDSP_SetSpectrumSmooth(AnalyzerDSPRef ref, float smooth) {
    if (!ref) return;
    if (smooth < 0.0f) smooth = 0.0f;
    if (smooth > 1.0f) smooth = 1.0f;
    ref->spectrumSmooth = smooth;
}

void AnalyzerDSP_SetHPSSParameters(AnalyzerDSPRef ref,
                                    int timeMedianLen,
                                    int freqMedianLen,
                                    float separationFactor) {
    if (!ref) return;
    if (timeMedianLen < 3)  timeMedianLen = 3;
    if (timeMedianLen > ANALYZER_DSP_MAX_MEDIAN_LEN) timeMedianLen = ANALYZER_DSP_MAX_MEDIAN_LEN;
    if ((timeMedianLen & 1) == 0) timeMedianLen += 1;
    if (freqMedianLen < 3)  freqMedianLen = 3;
    if (freqMedianLen > ANALYZER_DSP_MAX_MEDIAN_LEN) freqMedianLen = ANALYZER_DSP_MAX_MEDIAN_LEN;
    if ((freqMedianLen & 1) == 0) freqMedianLen += 1;
    if (separationFactor < 1.0f) separationFactor = 1.0f;

    if (timeMedianLen != ref->timeMedianLen) {
        // Reallocate history rings
        for (int ch = 0; ch < 2; ch++) {
            free(ref->historyPower[ch]);
            ref->historyPower[ch] = (float *)calloc((size_t)(timeMedianLen * ref->halfFFTSize),
                                                     sizeof(float));
            ref->historyWriteIdx[ch]   = 0;
            ref->historyValidCount[ch] = 0;
        }
    }
    ref->timeMedianLen    = timeMedianLen;
    ref->freqMedianLen    = freqMedianLen;
    ref->separationFactor = separationFactor;
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Sample accumulation
// ─────────────────────────────────────────────────────────────────────────────

static void AccumulateSamples(AnalyzerDSPRef ref,
                               int channelIndex,
                               const float *samples,
                               int sampleCount) {
    const int N = ref->fftSize;
    float *buf = ref->sampleBuffer[channelIndex];

    if (sampleCount <= 0) return;

    if (sampleCount >= N) {
        // New buffer entirely overwrites window: copy last N samples.
        memcpy(buf, samples + (sampleCount - N), (size_t)N * sizeof(float));
        ref->sampleFill[channelIndex] = N;
    } else {
        // Shift left by sampleCount, append new samples at the end.
        int retain = N - sampleCount;
        memmove(buf, buf + sampleCount, (size_t)retain * sizeof(float));
        memcpy(buf + retain, samples, (size_t)sampleCount * sizeof(float));
        int newFill = ref->sampleFill[channelIndex] + sampleCount;
        if (newFill > N) newFill = N;
        ref->sampleFill[channelIndex] = newFill;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - HPSS pipeline
// ─────────────────────────────────────────────────────────────────────────────

/// Push current power spectrum into the time-history ring and produce a
/// horizontally-median-filtered spectrum (harmonic enhancement).
/// Bin k is replaced by the median of historyPower[*, k] over timeMedianLen frames.
static void TimeMedianFilter(AnalyzerDSPRef ref, int channelIndex,
                              const float *currentPower, float *outHEnhanced) {
    const int half = ref->halfFFTSize;
    const int Lh = ref->timeMedianLen;
    float *ring = ref->historyPower[channelIndex];

    // Insert current frame at writeIdx
    int writeIdx = ref->historyWriteIdx[channelIndex];
    memcpy(ring + (size_t)writeIdx * half, currentPower, (size_t)half * sizeof(float));
    ref->historyWriteIdx[channelIndex] = (writeIdx + 1) % Lh;
    if (ref->historyValidCount[channelIndex] < Lh) {
        ref->historyValidCount[channelIndex] += 1;
    }

    int valid = ref->historyValidCount[channelIndex];
    // For each bin, sort the column and pick median
    float *scratch = ref->medianScratch;
    for (int k = 0; k < half; k++) {
        for (int t = 0; t < valid; t++) {
            scratch[t] = ring[t * half + k];
        }
        outHEnhanced[k] = MedianSmall(scratch, valid);
    }
}

/// Vertical (frequency) median filter over the current power spectrum →
/// percussive enhancement. For bin k, output = median over [k-r..k+r].
static void FreqMedianFilter(AnalyzerDSPRef ref, const float *currentPower,
                              float *outPEnhanced) {
    const int half = ref->halfFFTSize;
    const int Lp = ref->freqMedianLen;
    const int r = Lp / 2;
    float *scratch = ref->medianScratch;

    for (int k = 0; k < half; k++) {
        int lo = k - r; if (lo < 0) lo = 0;
        int hi = k + r; if (hi >= half) hi = half - 1;
        int len = hi - lo + 1;
        for (int j = 0; j < len; j++) scratch[j] = currentPower[lo + j];
        outPEnhanced[k] = MedianSmall(scratch, len);
    }
}

/// Driedger 2014 soft mask with separation factor β. Three-component output
/// (H, P, R) such that H + P + R == originalPower (in expectation).
static void DriedgerSoftMask(AnalyzerDSPRef ref,
                              const float *currentPower,
                              const float *Hmag2,
                              const float *Pmag2,
                              float *outHpow,
                              float *outPpow,
                              float *outRpow) {
    const int half = ref->halfFFTSize;
    const float beta = ref->separationFactor;
    const float eps  = 1e-12f;

    for (int k = 0; k < half; k++) {
        float h = Hmag2[k];
        float p = Pmag2[k];
        // Driedger criteria: a bin is clearly H if H >= β*P, clearly P if P >= β*H, else R.
        float maskH = 0.0f, maskP = 0.0f, maskR = 0.0f;
        if (h >= beta * p) {
            maskH = 1.0f;
        } else if (p >= beta * h) {
            maskP = 1.0f;
        } else {
            maskR = 1.0f;
        }
        // To avoid hard cliffs at the boundary, blend with a small amount of soft mask
        // based on relative magnitudes — keeps temporal envelopes smooth.
        float softH = (h + eps) / (h + p + eps);
        float softP = 1.0f - softH;
        // Mix: 80% hard / 20% soft for stability with default β=1.8
        const float hard = 0.8f;
        maskH = hard * maskH + (1.0f - hard) * softH;
        maskP = hard * maskP + (1.0f - hard) * softP;
        maskR = (maskH + maskP > 1.0f) ? 0.0f : (1.0f - maskH - maskP);

        float src = currentPower[k];
        outHpow[k] = maskH * src;
        outPpow[k] = maskP * src;
        outRpow[k] = maskR * src;
    }
}

// ─────────────────────────────────────────────────────────────────────────────
#pragma mark - Process Channel
// ─────────────────────────────────────────────────────────────────────────────

static void RunFFTPipeline(AnalyzerDSPRef ref,
                            int channelIndex,
                            int amplitudeLevel,
                            float *outBandsRaw) {
    (void)channelIndex;
    const int N    = ref->fftSize;
    const int half = ref->halfFFTSize;
    const int bands = ref->frequencyBands;
    const float *samples = ref->sampleBuffer[channelIndex];

    // ── Step 1: Apply Hanning window ──────────────────────────────────────
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

    // Cache power = |X|^2 for HPSS reuse downstream
    vDSP_vsq(ref->magnitudes, 1, ref->power, 1, (vDSP_Length)half);

    // ── Step 4: Apply A-weighting (vectorized multiply) ──────────────────
    vDSP_vmul(ref->magnitudes, 1, ref->aWeights, 1, ref->weightedMags, 1, (vDSP_Length)half);

    // ── Step 5: Map to frequency bands ─────────────────────────────────────
    ProjectToBands(ref->weightedMags, ref->bandStartBin, ref->bandEndBin,
                   bands, (float)amplitudeLevel, ref->bandSpectrum);

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
        outBandsRaw[i] = buf[i];
    }
}

void AnalyzerDSP_ProcessChannel(AnalyzerDSPRef ref,
                                const float *samples,
                                int sampleCount,
                                int channelIndex,
                                int amplitudeLevel,
                                float sampleRate,
                                float *outBands) {
    (void)sampleRate;
    if (!ref || !outBands) return;
    if (channelIndex < 0 || channelIndex > 1) return;

    if (samples && sampleCount > 0) {
        AccumulateSamples(ref, channelIndex, samples, sampleCount);
    }
    RunFFTPipeline(ref, channelIndex, amplitudeLevel, outBands);
}

void AnalyzerDSP_ProcessChannelExtended(AnalyzerDSPRef ref,
                                         const float *samples,
                                         int sampleCount,
                                         int channelIndex,
                                         int amplitudeLevel,
                                         float sampleRate,
                                         float *outBands,
                                         float *outHBands,
                                         float *outPBands,
                                         float *outRBands,
                                         AnalyzerCategoryFeatures *outCat) {
    if (!ref) return;
    if (channelIndex < 0 || channelIndex > 1) return;

    if (samples && sampleCount > 0) {
        AccumulateSamples(ref, channelIndex, samples, sampleCount);
    }

    const int half  = ref->halfFFTSize;
    const int N     = ref->fftSize;
    const int bands = ref->frequencyBands;

    // Run the standard FFT pipeline (also fills `power` and `magnitudes`).
    // Use a function-scope scratch so the buffer outlives any nested usage.
    float bandsScratch[bands];
    float *bandsOut = outBands ? outBands : bandsScratch;
    RunFFTPipeline(ref, channelIndex, amplitudeLevel, bandsOut);

    // ── HPSS: time-median (harmonic) and frequency-median (percussive) ────
    TimeMedianFilter(ref, channelIndex, ref->power, ref->Hmag2);
    FreqMedianFilter(ref, ref->power, ref->Pmag2);

    // ── Driedger soft mask → H, P, R power ────────────────────────────────
    DriedgerSoftMask(ref, ref->power, ref->Hmag2, ref->Pmag2,
                     ref->Hpow, ref->Ppow, ref->Rpow);

    // ── Build A-weighted band spectra for H/P/R for visualisation ─────────
    // Convert power → magnitude, then A-weight, then band-project.
    float magScratch[half];
    const float ampScale = (float)amplitudeLevel;

    if (outHBands) {
        for (int k = 0; k < half; k++) magScratch[k] = sqrtf(ref->Hpow[k]);
        vDSP_vmul(magScratch, 1, ref->aWeights, 1, magScratch, 1, (vDSP_Length)half);
        ProjectToBands(magScratch, ref->bandStartBin, ref->bandEndBin,
                       bands, ampScale, ref->Hbands);
        HighlightWaveform(ref->Hbands, outHBands, bands, ref->highlightKernel);
    }
    if (outPBands) {
        for (int k = 0; k < half; k++) magScratch[k] = sqrtf(ref->Ppow[k]);
        vDSP_vmul(magScratch, 1, ref->aWeights, 1, magScratch, 1, (vDSP_Length)half);
        ProjectToBands(magScratch, ref->bandStartBin, ref->bandEndBin,
                       bands, ampScale, ref->Pbands);
        HighlightWaveform(ref->Pbands, outPBands, bands, ref->highlightKernel);
    }
    if (outRBands) {
        for (int k = 0; k < half; k++) magScratch[k] = sqrtf(ref->Rpow[k]);
        vDSP_vmul(magScratch, 1, ref->aWeights, 1, magScratch, 1, (vDSP_Length)half);
        ProjectToBands(magScratch, ref->bandStartBin, ref->bandEndBin,
                       bands, ampScale, ref->Rbands);
        HighlightWaveform(ref->Rbands, outRBands, bands, ref->highlightKernel);
    }

    // ── Category features ─────────────────────────────────────────────────
    if (outCat) {
        AnalyzerCategoryFeatures cat;
        memset(&cat, 0, sizeof(cat));

        const float binWidth = sampleRate / (float)N;
        // Sub-Bass: 20-60 Hz, Bass: 60-120 Hz on H component.
        int sbStart = (int)(20.0f  / binWidth + 0.5f);
        int sbEnd   = (int)(60.0f  / binWidth + 0.5f);
        int bsEnd   = (int)(120.0f / binWidth + 0.5f);
        if (sbStart < 1) sbStart = 1;       // skip DC
        if (sbEnd >= half) sbEnd = half - 1;
        if (bsEnd >= half) bsEnd = half - 1;
        if (sbEnd < sbStart) sbEnd = sbStart;
        if (bsEnd < sbEnd)   bsEnd = sbEnd;

        // Use H component magnitude — robust against drum hits leaking into bass reading.
        // sqrt(Hpow) → per-bin magnitude; we sum (avg) over bin range
        float sbSum = 0.0f, bsSum = 0.0f;
        int sbCount = 0, bsCount = 0;
        for (int k = sbStart; k <= sbEnd; k++) { sbSum += sqrtf(ref->Hpow[k]); sbCount++; }
        for (int k = sbEnd + 1; k <= bsEnd; k++) { bsSum += sqrtf(ref->Hpow[k]); bsCount++; }
        cat.subBass = (sbCount > 0) ? (sbSum / (float)sbCount) : 0.0f;
        cat.bass    = (bsCount > 0) ? (bsSum / (float)bsCount) : 0.0f;
        cat.lowEnergy = cat.subBass + cat.bass;

        // Harmonic: total energy + peak-to-mean ratio of H magnitude.
        float Hmean = 0.0f, Hmax = 0.0f;
        // Limit to musically-relevant range (skip DC / above 8 kHz)
        int hStart = 1;
        int hEnd   = (int)(8000.0f / binWidth + 0.5f);
        if (hEnd >= half) hEnd = half - 1;
        if (hEnd < hStart) hEnd = hStart;
        for (int k = hStart; k <= hEnd; k++) {
            float m = sqrtf(ref->Hpow[k]);
            Hmean += m;
            if (m > Hmax) Hmax = m;
        }
        int hLen = hEnd - hStart + 1;
        Hmean = (hLen > 0) ? (Hmean / (float)hLen) : 0.0f;
        cat.harmonic = Hmean;
        cat.harmonicPeakRatio = (Hmean > 1e-9f) ? (Hmax / Hmean) : 0.0f;

        // Noise: total R energy + global SFM (geometric mean / arithmetic mean of full power).
        float Rsum = 0.0f;
        for (int k = 1; k < half; k++) Rsum += sqrtf(ref->Rpow[k]);
        cat.noise = (half > 1) ? (Rsum / (float)(half - 1)) : 0.0f;

        // SFM over A-weighted magnitudes — avoid super-low / super-high silent bins.
        int sfmStart = (int)(80.0f   / binWidth + 0.5f);
        int sfmEnd   = (int)(8000.0f / binWidth + 0.5f);
        if (sfmStart < 1) sfmStart = 1;
        if (sfmEnd >= half) sfmEnd = half - 1;
        if (sfmEnd > sfmStart) {
            double logSum = 0.0;
            double linSum = 0.0;
            int n = 0;
            for (int k = sfmStart; k <= sfmEnd; k++) {
                float v = ref->magnitudes[k];
                if (v < 1e-9f) v = 1e-9f;
                logSum += log((double)v);
                linSum += (double)v;
                n++;
            }
            if (n > 0 && linSum > 0.0) {
                double geo = exp(logSum / (double)n);
                double ari = linSum / (double)n;
                cat.spectralFlatness = (float)(geo / ari);
                if (cat.spectralFlatness > 1.0f) cat.spectralFlatness = 1.0f;
                if (cat.spectralFlatness < 0.0f) cat.spectralFlatness = 0.0f;
            }
        }

        // ── SuperFlux on P (Böck 2013) ────────────────────────────────────
        // Reuse magScratch as P magnitude buffer (already allocated above).
        for (int k = 0; k < half; k++) magScratch[k] = sqrtf(ref->Ppow[k]);

        int ringIdx = ref->superfluxRingIdx[channelIndex];
        float *ring = ref->pMaxFilteredRing[channelIndex];
        float *currentSlot = ring + (size_t)ringIdx * half;
        // Symmetric ±radius bin max filter on P magnitude.
        MaxFilter1D(magScratch, currentSlot, half, ANALYZER_DSP_SUPERFLUX_RADIUS);

        // Update ring index AFTER computing this slot.
        ref->superfluxRingIdx[channelIndex] = (ringIdx + 1) % ANALYZER_DSP_SUPERFLUX_RING;
        if (ref->superfluxRingValid[channelIndex] < ANALYZER_DSP_SUPERFLUX_RING) {
            ref->superfluxRingValid[channelIndex] += 1;
        }

        // Flux: half-wave-rectified diff between current P magnitude and lagged max-filtered P.
        float flux = 0.0f;
        if (ref->superfluxRingValid[channelIndex] >= ANALYZER_DSP_SUPERFLUX_RING) {
            int lagIdx = (ringIdx + ANALYZER_DSP_SUPERFLUX_RING - ANALYZER_DSP_SUPERFLUX_LAG)
                          % ANALYZER_DSP_SUPERFLUX_RING;
            float *lagSlot = ring + (size_t)lagIdx * half;
            for (int k = 0; k < half; k++) {
                float diff = magScratch[k] - lagSlot[k];
                if (diff > 0.0f) flux += diff;
            }
            flux /= (float)half;
        }
        cat.transient = flux;

        *outCat = cat;
    }
}

void AnalyzerDSP_ProcessChannelLegacyExact(AnalyzerDSPRef ref,
                                           const float *samples,
                                           int channelIndex,
                                           int amplitudeLevel,
                                           float sampleRate,
                                           float *outBands) {
    (void)sampleRate;
    if (!ref || !samples || !outBands) return;
    if (channelIndex < 0 || channelIndex > 1) return;

    const int N = ref->fftSize;
    const int half = ref->halfFFTSize;
    const int bands = ref->frequencyBands;

    vDSP_vmul(samples, 1, ref->window, 1, ref->windowedSamples, 1, (vDSP_Length)N);

    DSPSplitComplex splitComplex = { ref->fftReals, ref->fftImags };
    vDSP_ctoz((const DSPComplex *)ref->windowedSamples, 2, &splitComplex, 1, (vDSP_Length)half);
    vDSP_fft_zrip(ref->fftSetup, &splitComplex, 1, ref->log2n, FFT_FORWARD);

    splitComplex.imagp[0] = 0.0f;
    float normFactor = 1.0f / (float)N;
    vDSP_vsmul(splitComplex.realp, 1, &normFactor, splitComplex.realp, 1, (vDSP_Length)half);
    vDSP_vsmul(splitComplex.imagp, 1, &normFactor, splitComplex.imagp, 1, (vDSP_Length)half);
    vDSP_zvabs(&splitComplex, 1, ref->magnitudes, 1, (vDSP_Length)half);
    ref->magnitudes[0] *= 0.5f;

    vDSP_vmul(ref->magnitudes, 1, ref->aWeights, 1, ref->weightedMags, 1, (vDSP_Length)half);

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

    HighlightWaveform(ref->bandSpectrum, ref->smoothedSpectrum, bands, ref->highlightKernel);

    float *buf = ref->spectrumBuffer[channelIndex];
    const float oldFactor = ref->spectrumSmooth;
    const float newFactor = 1.0f - oldFactor;
    vDSP_vsmul(buf, 1, &oldFactor, buf, 1, (vDSP_Length)bands);
    vDSP_vsma(ref->smoothedSpectrum, 1, &newFactor, buf, 1, buf, 1, (vDSP_Length)bands);
    for (int i = 0; i < bands; i++) {
        float val = buf[i];
        buf[i] = (val == val) ? val : 0.0f;
        outBands[i] = buf[i];
    }
}

int AnalyzerDSP_GetFrequencyBands(AnalyzerDSPRef ref) {
    return ref ? ref->frequencyBands : 0;
}

int AnalyzerDSP_GetFFTSize(AnalyzerDSPRef ref) {
    return ref ? ref->fftSize : 0;
}
