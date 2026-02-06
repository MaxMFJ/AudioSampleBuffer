#import "RealtimeAnalyzer.h"
#import "RealtimeAnalyzerDSP.h"

@interface RealtimeAnalyzer ()

@property (nonatomic, assign) int fftSize;
@property (nonatomic, assign) NSUInteger frequencyBands;
@property (nonatomic, assign) AnalyzerDSPRef dspRef;

@end

@implementation RealtimeAnalyzer

- (void)dealloc {
    if (_dspRef != NULL) {
        AnalyzerDSP_Destroy(_dspRef);
        _dspRef = NULL;
    }
}

- (instancetype)initWithFFTSize:(int)fftSize {
    if (self = [super init]) {
        _fftSize = fftSize;
        _frequencyBands = 80;
        _dspRef = AnalyzerDSP_Create(fftSize,
                                      (int)_frequencyBands,
                                      50.0f,      // startFrequency
                                      18000.0f,   // endFrequency
                                      44100.0f);  // sampleRate for A-weight
    }
    return self;
}

- (NSArray *)analyse:(AVAudioPCMBuffer *)buffer withAmplitudeLevel:(int)amplitudeLevel {
    if (!_dspRef) return @[];

    float *const *floatChannelData = buffer.floatChannelData;
    if (!floatChannelData) return @[];

    AVAudioChannelCount channelCount = buffer.format.channelCount;
    BOOL isInterleaved = buffer.format.isInterleaved;
    float actualSampleRate = (float)buffer.format.sampleRate;
    int N = _fftSize;
    int bands = (int)_frequencyBands;

    // Pre-allocate C arrays for output (stack allocation — no heap cost)
    float outBands[bands];

    NSMutableArray *result = [NSMutableArray arrayWithCapacity:channelCount];

    if (isInterleaved && channelCount > 1) {
        // ── Deinterleave on the stack ────────────────────────────────────
        float *interleaved = floatChannelData[0];
        int totalSamples = N * (int)channelCount;

        for (AVAudioChannelCount ch = 0; ch < channelCount && ch < 2; ch++) {
            float channelSamples[N];
            int idx = 0;
            for (int j = (int)ch; j < totalSamples; j += (int)channelCount) {
                if (idx < N) channelSamples[idx++] = interleaved[j];
            }
            // Zero-fill if we got fewer samples than N
            while (idx < N) channelSamples[idx++] = 0.0f;

            // Process through C DSP core
            AnalyzerDSP_ProcessChannel(_dspRef, channelSamples,
                                       (int)ch, amplitudeLevel,
                                       actualSampleRate, outBands);

            // Convert to NSArray only at the boundary
            NSMutableArray *channelResult = [NSMutableArray arrayWithCapacity:bands];
            for (int i = 0; i < bands; i++) {
                [channelResult addObject:@(outBands[i])];
            }
            [result addObject:channelResult];
        }
    } else {
        // ── Non-interleaved (typical case) ───────────────────────────────
        for (AVAudioChannelCount ch = 0; ch < channelCount && ch < 2; ch++) {
            float *channelData = floatChannelData[ch];

            // Process through C DSP core
            AnalyzerDSP_ProcessChannel(_dspRef, channelData,
                                       (int)ch, amplitudeLevel,
                                       actualSampleRate, outBands);

            // Convert to NSArray only at the boundary
            NSMutableArray *channelResult = [NSMutableArray arrayWithCapacity:bands];
            for (int i = 0; i < bands; i++) {
                [channelResult addObject:@(outBands[i])];
            }
            [result addObject:channelResult];
        }
    }

    return result.copy;
}

@end
