#import "HTDemucsMacAnalyzer.h"

#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreML/CoreML.h>
#import <CommonCrypto/CommonDigest.h>
#import <AppKit/AppKit.h>

static const NSInteger kHTDMSampleRate = 44100;
static const NSInteger kHTDMSegmentSeconds = 7;
static const NSInteger kHTDMHopSamples = 220500; // 5 s; overlap-and-add covers the full track.
static const NSInteger kHTDMFFTSize = 4096;
static NSString * const kHTDMModelVersion = @"htdemucs6s-guitar-piano-drums-ios16-v1";
#define ASB_CLAMP(value, low, high) fminf((high), fmaxf((low), (value)))

static NSError *HTDMError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"HTDemucsMacAnalyzer" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface HTDemucsMacAnalyzer ()
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong) NSLock *modelLock;
@property (nonatomic, strong) NSLock *jobLock;
@property (nonatomic, strong, nullable) MLModel *model;
@property (nonatomic, assign) NSUInteger jobGeneration;
@end

@implementation HTDemucsMacAnalyzer

+ (instancetype)sharedAnalyzer {
    static HTDemucsMacAnalyzer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        _workQueue = dispatch_queue_create("app.audiosamplebuffer.htdemucs-guitar",
                                            dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
        _modelLock = [[NSLock alloc] init];
        _jobLock = [[NSLock alloc] init];
    }
    return self;
}

- (BOOL)isJobGenerationCurrent:(NSUInteger)generation error:(NSError **)error {
    [self.jobLock lock];
    BOOL current = (self.jobGeneration == generation);
    [self.jobLock unlock];
    if (!current && error && !*error) {
        *error = HTDMError(13, @"歌曲已切换，Demucs 分析已停止。");
    }
    return current;
}

- (void)cancelCurrentAnalysis {
    [self.jobLock lock];
    self.jobGeneration += 1;
    [self.jobLock unlock];
}

- (NSString *)digestForURL:(NSURL *)url error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!handle) return nil;
    CC_SHA256_CTX context; CC_SHA256_Init(&context);
    @try {
        while (YES) {
            NSData *part = [handle readDataOfLength:1024 * 1024];
            if (part.length == 0) break;
            CC_SHA256_Update(&context, part.bytes, (CC_LONG)part.length);
        }
    } @catch (NSException *exception) {
        if (error) *error = HTDMError(1, exception.reason ?: @"读取音频文件失败。");
        [handle closeAndReturnError:nil];
        return nil;
    }
    [handle closeAndReturnError:nil];
    unsigned char bytes[CC_SHA256_DIGEST_LENGTH]; CC_SHA256_Final(bytes, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (NSUInteger i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", bytes[i]];
    return hex;
}

- (NSURL *)cacheURLForDigest:(NSString *)digest {
    NSURL *caches = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject];
    NSURL *folder = [caches URLByAppendingPathComponent:@"HTDemucsStems" isDirectory:YES];
    return [folder URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.json", kHTDMModelVersion, digest]];
}

- (nullable NSDictionary *)cachedAnalysisForAudioAtURL:(NSURL *)audioURL {
    NSError *error = nil;
    NSString *digest = [self digestForURL:audioURL error:&error];
    if (!digest) return nil;
    NSData *data = [NSData dataWithContentsOfURL:[self cacheURLForDigest:digest] options:NSDataReadingMappedIfSafe error:nil];
    id value = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (MLModel *)loadModel:(NSError **)error {
    [self.modelLock lock];
    if (self.model) { MLModel *model = self.model; [self.modelLock unlock]; return model; }
    NSBundle *bundle = [NSBundle mainBundle];
    NSURL *compiled = [bundle URLForResource:@"HTDemucs6s_Guitar_iOS16" withExtension:@"mlmodelc"];
    NSURL *package = [bundle URLForResource:@"HTDemucs6s_Guitar_iOS16" withExtension:@"mlpackage"];
    if (!compiled && package) compiled = [MLModel compileModelAtURL:package error:error];
    if (!compiled) {
        [self.modelLock unlock];
        if (error && !*error) *error = HTDMError(2, @"工程内未找到 HTDemucs 吉他、钢琴、鼓模型。");
        return nil;
    }
    MLModelConfiguration *configuration = [[MLModelConfiguration alloc] init];
    // Keep separation off the GPU so the live Metal wallpaper keeps its frame budget.
    configuration.computeUnits = MLComputeUnitsCPUAndNeuralEngine;
    self.model = [MLModel modelWithContentsOfURL:compiled configuration:configuration error:error];
    MLModel *result = self.model;
    [self.modelLock unlock];
    return result;
}

- (void)unloadModel {
    [self.modelLock lock];
    MLModel *releasedModel = self.model;
    self.model = nil;
    [self.modelLock unlock];
    // Drop our strong reference outside the lock; Core ML can then release its
    // model-side CPU/GPU resources when the in-flight prediction is finished.
    releasedModel = nil;
    NSLog(@"[DemucsMac] HTDemucs model object released after the job.");
}

- (NSMutableData *)readStereoPCMAtURL:(NSURL *)url generation:(NSUInteger)generation
                          sampleRate:(double *)sampleRate error:(NSError **)error {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [asset tracksWithMediaType:AVMediaTypeAudio].firstObject;
    if (!track) { if (error) *error = HTDMError(3, @"音频文件没有可读的音轨。"); return nil; }
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM), AVSampleRateKey: @(kHTDMSampleRate), AVNumberOfChannelsKey: @2,
        AVLinearPCMBitDepthKey: @32, AVLinearPCMIsFloatKey: @YES, AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO
    };
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:error];
    if (!reader) return nil;
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) { if (error) *error = HTDMError(4, @"无法建立 HTDemucs 音频解码器。"); return nil; }
    [reader addOutput:output];
    if (![reader startReading]) { if (error) *error = reader.error ?: HTDMError(5, @"音频解码启动失败。"); return nil; }
    NSMutableData *pcm = [NSMutableData data];
    CMSampleBufferRef sample = NULL;
    while ((sample = [output copyNextSampleBuffer])) {
        if (![self isJobGenerationCurrent:generation error:error]) {
            CFRelease(sample);
            [reader cancelReading];
            return nil;
        }
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
        size_t length = CMBlockBufferGetDataLength(block);
        NSUInteger oldLength = pcm.length;
        [pcm setLength:oldLength + length];
        char *destination = (char *)pcm.mutableBytes + oldLength;
        OSStatus status = CMBlockBufferCopyDataBytes(block, 0, length, destination);
        CFRelease(sample);
        if (status != kCMBlockBufferNoErr) { if (error) *error = HTDMError(6, @"读取 PCM 数据失败。"); return nil; }
    }
    if (reader.status == AVAssetReaderStatusFailed) { if (error) *error = reader.error ?: HTDMError(7, @"解码音频失败。"); return nil; }
    if (pcm.length < sizeof(float) * 2) { if (error) *error = HTDMError(8, @"解码后的 PCM 为空。"); return nil; }
    if (sampleRate) *sampleRate = kHTDMSampleRate;
    return pcm;
}

- (BOOL)calculateChunk:(const float *)pcm totalFrames:(NSUInteger)totalFrames start:(NSUInteger)start
                  model:(MLModel *)model frameSums:(float *)frameSums frameWeights:(float *)frameWeights
             frameCount:(NSUInteger)frameCount stemCount:(NSUInteger *)stemCountOut error:(NSError **)error {
    const NSUInteger segmentFrames = kHTDMSampleRate * kHTDMSegmentSeconds;
    NSError *arrayError = nil;
    MLMultiArray *input = [[MLMultiArray alloc] initWithShape:@[@1, @2, @(segmentFrames)]
                                                     dataType:MLMultiArrayDataTypeFloat32 error:&arrayError];
    if (!input) { if (error) *error = arrayError; return NO; }
    float *in = input.dataPointer;
    NSUInteger available = MIN(segmentFrames, totalFrames - start);
    NSUInteger padLeft = (segmentFrames - available) / 2;
    memset(in, 0, segmentFrames * 2 * sizeof(float));
    for (NSUInteger i = 0; i < available; i++) {
        in[padLeft + i] = pcm[(start + i) * 2];
        in[segmentFrames + padLeft + i] = pcm[(start + i) * 2 + 1];
    }
    MLFeatureValue *inputValue = [MLFeatureValue featureValueWithMultiArray:input];
    MLDictionaryFeatureProvider *provider = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{@"audio": inputValue} error:&arrayError];
    id<MLFeatureProvider> prediction = provider ? [model predictionFromFeatures:provider error:&arrayError] : nil;
    MLMultiArray *sources = [prediction featureValueForName:@"sources"].multiArrayValue;
    NSUInteger sourceCount = sources.shape.count >= 4 ? sources.shape[1].unsignedIntegerValue : 0;
    if (!sources || sourceCount == 0 || sourceCount > 3 || sources.shape[2].unsignedIntegerValue != 2 ||
        sources.shape[3].unsignedIntegerValue != segmentFrames ||
        (sources.dataType != MLMultiArrayDataTypeFloat32 && sources.dataType != MLMultiArrayDataTypeFloat16)) {
        if (error) *error = arrayError ?: HTDMError(9, @"HTDemucs 输出格式不符合预期。");
        return NO;
    }
    if (*stemCountOut > 0 && *stemCountOut != sourceCount) {
        if (error) *error = HTDMError(9, @"HTDemucs 分段输出的音轨数量不一致。");
        return NO;
    }
    *stemCountOut = sourceCount;
    const NSUInteger stemSamples = segmentFrames * 2;
    float *convertedStems = NULL;
    const float *stems = sources.dataPointer;
    if (sources.dataType == MLMultiArrayDataTypeFloat16) {
        convertedStems = malloc(stemSamples * sourceCount * sizeof(float));
        if (!convertedStems) { if (error) *error = HTDMError(10, @"Demucs 输出缓冲区分配失败。"); return NO; }
        vImage_Buffer sourceBuffer = { .data = sources.dataPointer, .height = 1,
            .width = stemSamples * sourceCount, .rowBytes = stemSamples * sourceCount * sizeof(uint16_t) };
        vImage_Buffer destinationBuffer = { .data = convertedStems, .height = 1,
            .width = stemSamples * sourceCount, .rowBytes = stemSamples * sourceCount * sizeof(float) };
        vImage_Error conversion = vImageConvert_Planar16FtoPlanarF(&sourceBuffer, &destinationBuffer, 0);
        if (conversion != kvImageNoError) {
            free(convertedStems);
            if (error) *error = HTDMError(11, @"无法将 Demucs Float16 输出转换为 Float32。");
            return NO;
        }
        stems = convertedStems;
    }
    const NSUInteger validStart = padLeft;
    const NSUInteger validEnd = MIN(segmentFrames, padLeft + available);
    const NSUInteger hop = (NSUInteger)llround(kHTDMSampleRate * 0.05);
    const NSUInteger firstFrame = (start + validStart) / hop;
    const NSUInteger lastFrame = MIN((NSUInteger)ceil((double)(start + validEnd) / hop), frameCount);
    float *window = calloc(kHTDMFFTSize, sizeof(float));
    float *real = calloc(kHTDMFFTSize / 2, sizeof(float));
    float *imag = calloc(kHTDMFFTSize / 2, sizeof(float));
    FFTSetup setup = vDSP_create_fftsetup((vDSP_Length)log2(kHTDMFFTSize), kFFTRadix2);
    if (!window || !real || !imag || !setup) {
        free(window); free(real); free(imag); if (setup) vDSP_destroy_fftsetup(setup);
        free(convertedStems);
        if (error) *error = HTDMError(12, @"频谱分析缓冲区分配失败。"); return NO;
    }
    for (NSUInteger index = firstFrame; index < lastFrame; index++) {
        NSInteger globalCenter = (NSInteger)(index * hop + hop / 2);
        NSInteger localCenter = globalCenter - (NSInteger)start + (NSInteger)padLeft;
        for (NSUInteger sourceIndex = 0; sourceIndex < sourceCount; sourceIndex++) {
            const float *stem = stems + sourceIndex * stemSamples;
            for (NSInteger n = 0; n < kHTDMFFTSize; n++) {
                NSInteger sampleIndex = localCenter - kHTDMFFTSize / 2 + n;
                float mono = 0.0f;
                if (sampleIndex >= (NSInteger)validStart && sampleIndex < (NSInteger)validEnd) {
                    float left = stem[sampleIndex];
                    float right = stem[segmentFrames + sampleIndex];
                    mono = (left + right) * 0.5f;
                }
                float hann = 0.5f - 0.5f * cosf((2.0f * (float)M_PI * n) / (kHTDMFFTSize - 1));
                window[n] = mono * hann;
            }
            DSPSplitComplex split = { .realp = real, .imagp = imag };
            vDSP_ctoz((DSPComplex *)window, 2, &split, 1, kHTDMFFTSize / 2);
            vDSP_fft_zrip(setup, &split, 1, (vDSP_Length)log2(kHTDMFFTSize), FFT_FORWARD);
            double power = 0.0;
            NSUInteger firstEnergyBin = sourceIndex == 0 ? 140 : 1;
            for (NSUInteger bin = firstEnergyBin; bin < kHTDMFFTSize / 2; bin++) {
                power += (double)real[bin] * real[bin] + (double)imag[bin] * imag[bin];
            }
            NSUInteger localSample = (NSUInteger)MAX(0, MIN((NSInteger)segmentFrames - 1, localCenter));
            float blend = (float)MIN(localSample + 1, segmentFrames - localSample);
            float level = (float)sqrt(power);
            frameSums[sourceIndex * frameCount + index] += level * blend;
        }
        NSUInteger localSample = (NSUInteger)MAX(0, MIN((NSInteger)segmentFrames - 1, localCenter));
        frameWeights[index] += (float)MIN(localSample + 1, segmentFrames - localSample);
    }
    vDSP_destroy_fftsetup(setup);
    free(window); free(real); free(imag);
    free(convertedStems);
    return YES;
}

- (NSDictionary *)analyzeURL:(NSURL *)url generation:(NSUInteger)generation error:(NSError **)error {
    NSString *digest = [self digestForURL:url error:error];
    if (!digest) return nil;
    NSURL *cacheURL = [self cacheURLForDigest:digest];
    NSData *cached = [NSData dataWithContentsOfURL:cacheURL options:NSDataReadingMappedIfSafe error:nil];
    NSDictionary *cachedObject = cached ? [NSJSONSerialization JSONObjectWithData:cached options:0 error:nil] : nil;
    if ([cachedObject isKindOfClass:NSDictionary.class]) { NSLog(@"[DemucsMac] CACHE HIT: %@", url.lastPathComponent); return cachedObject; }

    if (![self isJobGenerationCurrent:generation error:error]) return nil;

    CFAbsoluteTime started = CFAbsoluteTimeGetCurrent();
    MLModel *model = [self loadModel:error];
    if (!model) return nil;
    double sampleRate = 0.0;
    NSMutableData *pcmData = [self readStereoPCMAtURL:url generation:generation sampleRate:&sampleRate error:error];
    if (!pcmData) return nil;
    if (![self isJobGenerationCurrent:generation error:error]) return nil;
    NSUInteger totalFrames = pcmData.length / (sizeof(float) * 2);
    const NSUInteger hop = (NSUInteger)llround(sampleRate * 0.05);
    NSUInteger curveCount = (NSUInteger)ceil((double)totalFrames / hop);
    float *sums = calloc(curveCount * 3, sizeof(float));
    float *weights = calloc(curveCount, sizeof(float));
    NSUInteger stemCount = 0;
    if (!sums || !weights) { free(sums); free(weights); if (error) *error = HTDMError(12, @"乐器曲线缓冲区分配失败。"); return nil; }
    const float *pcm = pcmData.bytes;
    for (NSUInteger start = 0; start < totalFrames; start += kHTDMHopSamples) {
        if (![self isJobGenerationCurrent:generation error:error]) {
            free(sums); free(weights); return nil;
        }
        __block BOOL chunkSucceeded = NO;
        @autoreleasepool {
            chunkSucceeded = [self calculateChunk:pcm totalFrames:totalFrames start:start model:model
                                         frameSums:sums frameWeights:weights frameCount:curveCount
                                         stemCount:&stemCount error:error];
        }
        if (!chunkSucceeded) {
            free(sums); free(weights); return nil;
        }
        if (![self isJobGenerationCurrent:generation error:error]) {
            free(sums); free(weights); return nil;
        }
    }
    // PCM is no longer needed after the final chunk; release its full-track
    // allocation before building and serializing the small envelope.
    pcmData = nil;
    NSArray<NSString *> *stemNames = @[@"guitar", @"piano", @"drums"];
    NSMutableDictionary *stemCurves = [NSMutableDictionary dictionaryWithCapacity:stemCount];
    for (NSUInteger stemIndex = 0; stemIndex < stemCount; stemIndex++) {
        NSMutableArray<NSNumber *> *raw = [NSMutableArray arrayWithCapacity:curveCount];
        const float *stemSums = sums + stemIndex * curveCount;
        for (NSUInteger i = 0; i < curveCount; i++) {
            [raw addObject:@(weights[i] > 0.0f ? stemSums[i] / weights[i] : 0.0f)];
        }
        NSArray<NSNumber *> *sorted = [raw sortedArrayUsingComparator:^NSComparisonResult(NSNumber *a, NSNumber *b) { return [a compare:b]; }];
        float floor = sorted[(NSUInteger)(sorted.count * 0.12)].floatValue;
        float ceiling = sorted[MIN(sorted.count - 1, (NSUInteger)(sorted.count * 0.96))].floatValue;
        NSMutableArray<NSNumber *> *frames = [NSMutableArray arrayWithCapacity:curveCount];
        for (NSNumber *number in raw) {
            float value = ceiling > floor ? ASB_CLAMP((number.floatValue - floor) / (ceiling - floor), 0.0f, 1.0f) : 0.0f;
            if (value < 0.08f) value = 0.0f;
            [frames addObject:@(value)];
        }
        stemCurves[stemNames[stemIndex]] = @{@"frames": frames};
    }
    free(sums); free(weights);
    NSArray<NSNumber *> *guitarFrames = stemCurves[@"guitar"][@"frames"] ?: @[];
    NSMutableDictionary *result = [@{@"model_version": kHTDMModelVersion,
                                     @"duration_sec": @((double)totalFrames / sampleRate),
                                     @"frame_hop_sec": @0.05,
                                     @"stem_order": [stemNames subarrayWithRange:NSMakeRange(0, stemCount)],
                                     @"stems": stemCurves,
                                     @"frames": guitarFrames} mutableCopy];
    if (stemCount > 1) result[@"piano_frames"] = stemCurves[@"piano"][@"frames"];
    if (stemCount > 2) result[@"drums_frames"] = stemCurves[@"drums"][@"frames"];
    if (![self isJobGenerationCurrent:generation error:error]) return nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (json) {
        [[NSFileManager defaultManager] createDirectoryAtURL:cacheURL.URLByDeletingLastPathComponent
                                withIntermediateDirectories:YES attributes:nil error:nil];
        [json writeToURL:cacheURL options:NSDataWritingAtomic error:nil];
    }
    NSLog(@"[DemucsMac] ANALYSIS COMPLETE: %.2f s audio, %lu frames, elapsed %.2f s, cache %@",
          [result[@"duration_sec"] doubleValue], (unsigned long)guitarFrames.count,
          CFAbsoluteTimeGetCurrent() - started, cacheURL.lastPathComponent);
    return result;
}

- (void)analyzeAudioAtURL:(NSURL *)audioURL completion:(void (^)(NSDictionary *, NSError *))completion {
    void (^completionCopy)(NSDictionary *, NSError *) = [completion copy];
    NSURL *audioURLCopy = [audioURL copy];
    [self.jobLock lock];
    NSUInteger generation = ++self.jobGeneration;
    [self.jobLock unlock];
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        NSDictionary *result = nil;
        @autoreleasepool {
            result = [self analyzeURL:audioURLCopy generation:generation error:&error];
            [self unloadModel];
        }
        // Freeze the callback payload before leaving this queue's autorelease pool.
        NSDictionary *deliveredResult = result ? [result copy] : nil;
        NSError *deliveredError = error ? [error copy] : nil;
        void (^deliveredCompletion)(NSDictionary *, NSError *) = completionCopy;
        dispatch_async(dispatch_get_main_queue(), ^{
            if (deliveredCompletion) deliveredCompletion(deliveredResult, deliveredError);
        });
    });
}

@end
