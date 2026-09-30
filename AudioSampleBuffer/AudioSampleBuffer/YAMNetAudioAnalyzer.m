#import "YAMNetAudioAnalyzer.h"
#import <AVFoundation/AVFoundation.h>
#import <Accelerate/Accelerate.h>
#import <CoreML/CoreML.h>
#import <CommonCrypto/CommonDigest.h>
#import <AudioToolbox/AudioToolbox.h>

static NSString * const kYAMNetModelVersion = @"yamnet-audioset-521-v1";
static const int kYAMNetSampleRate = 16000;
static const int kYAMNetFFTSize = 512;
static const int kYAMNetWindowSize = 400;
static const int kYAMNetHopSize = 160;
static const int kYAMNetMelBands = 64;
static const int kYAMNetPatchFrames = 96;
static const int kYAMNetPatchHopFrames = 48;
static const int kYAMNetClasses = 521;

static NSError *YAMNetError(NSInteger code, NSString *message) {
    return [NSError errorWithDomain:@"YAMNetAudioAnalyzer" code:code
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

@interface YAMNetAudioAnalyzer ()
@property (nonatomic, strong) dispatch_queue_t workQueue;
@property (nonatomic, strong, nullable) MLModel *model;
@property (nonatomic, strong) NSLock *modelLock;
@property (nonatomic, assign) BOOL modelInstallInProgress;
@property (nonatomic, assign) MLMultiArrayDataType modelInputType;
@end

@implementation YAMNetAudioAnalyzer

+ (instancetype)sharedAnalyzer {
    static YAMNetAudioAnalyzer *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [[self alloc] init]; });
    return instance;
}

- (instancetype)init {
    if ((self = [super init])) {
        dispatch_queue_attr_t queueAttributes = dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL,
                                                                                        QOS_CLASS_UTILITY, 0);
        _workQueue = dispatch_queue_create("app.audiosamplebuffer.yamnet", queueAttributes);
        _modelLock = [[NSLock alloc] init];
        [self loadInstalledModel];
        if (!self.model) {
            NSURL *bundledPackage = [[NSBundle mainBundle] URLForResource:@"YAMNet" withExtension:@"mlpackage"];
            if (bundledPackage) {
                if (@available(iOS 16.0, *)) {
                    NSLog(@"[YAMNet] Found bundled model package; preparing local model: %@", bundledPackage.lastPathComponent);
                    self.modelInstallInProgress = YES;
                    [self installModelAtURL:bundledPackage completion:^(NSError *error) {
                        if (error) {
                            NSLog(@"[YAMNet] MODEL PREPARATION FAILED: %@", error.localizedDescription);
                        } else {
                            NSLog(@"[YAMNet] MODEL READY: bundled package compiled and loaded (input=%@).", self.modelInputType == MLMultiArrayDataTypeFloat16 ? @"Float16" : @"Float32");
                        }
                    }];
                } else {
                    NSLog(@"[YAMNet] MODEL UNAVAILABLE: bundled FP16 model requires iOS 16 or newer.");
                }
            } else {
                NSLog(@"[YAMNet] MODEL MISSING: neither YAMNet.mlmodelc nor YAMNet.mlpackage exists in the app bundle.");
            }
        }
    }
    return self;
}

- (NSURL *)modelDirectoryURL {
    NSURL *support = [[[NSFileManager defaultManager] URLsForDirectory:NSApplicationSupportDirectory
                                                             inDomains:NSUserDomainMask] firstObject];
    return [support URLByAppendingPathComponent:@"YAMNet" isDirectory:YES];
}

- (NSURL *)compiledModelURL {
    return [[self modelDirectoryURL] URLByAppendingPathComponent:@"YAMNet.mlmodelc" isDirectory:YES];
}

- (BOOL)modelInstalled {
    return self.model != nil || self.modelInstallInProgress;
}

- (void)loadInstalledModel {
    if (@available(iOS 16.0, *)) {
        NSURL *compiledURL = [self compiledModelURL];
        if (![[NSFileManager defaultManager] fileExistsAtPath:compiledURL.path]) {
            compiledURL = [[NSBundle mainBundle] URLForResource:@"YAMNet" withExtension:@"mlmodelc"];
        }
        if (!compiledURL || ![[NSFileManager defaultManager] fileExistsAtPath:compiledURL.path]) return;
        NSError *error = nil;
        MLModel *model = [MLModel modelWithContentsOfURL:compiledURL error:&error];
        if (error || !model) {
            NSLog(@"[YAMNet] MODEL LOAD FAILED at %@: %@", compiledURL.path, error.localizedDescription);
            return;
        }
        self.model = model;
        self.modelInputType = model.modelDescription.inputDescriptionsByName[@"features"].multiArrayConstraint.dataType;
        NSLog(@"[YAMNet] MODEL READY: loaded %@ (input=%@, outputs=%lu).", compiledURL.lastPathComponent,
              self.modelInputType == MLMultiArrayDataTypeFloat16 ? @"Float16" : @"Float32",
              (unsigned long)model.modelDescription.outputDescriptionsByName.count);
    }
}

- (void)installModelAtURL:(NSURL *)modelURL completion:(void (^)(NSError * _Nullable))completion {
    self.modelInstallInProgress = YES;
    dispatch_async(self.workQueue, ^{
        NSError *error = nil;
        NSURL *sourceURL = modelURL;
        BOOL isDirectory = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:modelURL.path isDirectory:&isDirectory];
        if (!modelURL.isFileURL || ![[NSFileManager defaultManager] fileExistsAtPath:modelURL.path]) {
            error = YAMNetError(1, @"模型文件不存在；请提供本地 .mlmodel 或 .mlpackage 文件。");
        }
        NSURL *compiledURL = nil;
        if (!error) compiledURL = [MLModel compileModelAtURL:sourceURL error:&error];
        if (!error && !compiledURL) error = YAMNetError(2, @"Core ML 模型编译失败。");

        NSURL *destination = [self compiledModelURL];
        NSFileManager *fm = [NSFileManager defaultManager];
        if (!error) {
            [fm createDirectoryAtURL:[self modelDirectoryURL]
         withIntermediateDirectories:YES attributes:nil error:&error];
        }
        if (!error && [fm fileExistsAtPath:destination.path]) {
            [fm removeItemAtURL:destination error:&error];
        }
        if (!error) [fm copyItemAtURL:compiledURL toURL:destination error:&error];

        MLModel *loaded = nil;
        if (!error) loaded = [MLModel modelWithContentsOfURL:destination error:&error];
        if (!error && !loaded) error = YAMNetError(3, @"编译后的模型无法加载。");
        if (!error) {
            MLFeatureDescription *input = loaded.modelDescription.inputDescriptionsByName[@"features"];
            MLMultiArrayConstraint *constraint = input.multiArrayConstraint;
            BOOL supportedType = constraint.dataType == MLMultiArrayDataTypeFloat32;
            if (@available(iOS 16.0, *)) {
                supportedType = supportedType || constraint.dataType == MLMultiArrayDataTypeFloat16;
            }
            if (!constraint || constraint.shape.count != 3 ||
                constraint.shape[0].integerValue != 1 ||
                constraint.shape[1].integerValue != kYAMNetPatchFrames ||
                constraint.shape[2].integerValue != kYAMNetMelBands ||
                !supportedType) {
                error = YAMNetError(4, @"YAMNet 模型输入需为 [1, 96, 64] Float32 或当前系统支持的 Float16。");
            }
            if (loaded.modelDescription.outputDescriptionsByName.count == 0) {
                error = YAMNetError(5, @"模型没有可用输出。");
            }
        }
        if (!error) {
            [self.modelLock lock];
            self.model = loaded;
            self.modelInputType = loaded.modelDescription.inputDescriptionsByName[@"features"].multiArrayConstraint.dataType;
            self.modelInstallInProgress = NO;
            [self.modelLock unlock];
            NSLog(@"[YAMNet] MODEL READY: installed local model at %@ (input=%@).", destination.path,
                  self.modelInputType == MLMultiArrayDataTypeFloat16 ? @"Float16" : @"Float32");
        } else if ([fm fileExistsAtPath:destination.path]) {
            [fm removeItemAtURL:destination error:nil];
        }
        if (error) self.modelInstallInProgress = NO;
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error); });
    });
}

- (NSString *)sha256ForURL:(NSURL *)url error:(NSError **)error {
    NSFileHandle *handle = [NSFileHandle fileHandleForReadingFromURL:url error:error];
    if (!handle) return nil;
    CC_SHA256_CTX context;
    CC_SHA256_Init(&context);
    @try {
        while (YES) {
            NSData *chunk = [handle readDataOfLength:1024 * 1024];
            if (chunk.length == 0) break;
            CC_SHA256_Update(&context, chunk.bytes, (CC_LONG)chunk.length);
        }
    } @catch (NSException *exception) {
        if (error) *error = YAMNetError(9, exception.reason ?: @"读取歌曲文件失败。");
        return nil;
    } @finally {
        [handle closeAndReturnError:nil];
    }
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256_Final(digest, &context);
    NSMutableString *hex = [NSMutableString stringWithCapacity:CC_SHA256_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_SHA256_DIGEST_LENGTH; i++) [hex appendFormat:@"%02x", digest[i]];
    return hex;
}

- (NSURL *)cacheURLForDigest:(NSString *)digest {
    NSURL *caches = [[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory
                                                            inDomains:NSUserDomainMask] firstObject];
    NSURL *directory = [caches URLByAppendingPathComponent:@"YAMNetAnalysis" isDirectory:YES];
    return [[directory URLByAppendingPathComponent:[NSString stringWithFormat:@"%@-%@.json", kYAMNetModelVersion, digest]] copy];
}

- (NSDictionary *)cachedAnalysisForAudioAtURL:(NSURL *)audioURL {
    NSError *error = nil;
    NSString *digest = [self sha256ForURL:audioURL error:&error];
    if (!digest) return nil;
    NSData *data = [NSData dataWithContentsOfURL:[self cacheURLForDigest:digest] options:NSDataReadingMappedIfSafe error:nil];
    if (!data) return nil;
    id value = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [value isKindOfClass:NSDictionary.class] ? value : nil;
}

- (void)analyzeAudioAtURL:(NSURL *)audioURL completion:(void (^)(NSDictionary *, NSError *))completion {
    dispatch_async(self.workQueue, ^{
        CFAbsoluteTime analysisStartedAt = CFAbsoluteTimeGetCurrent();
        NSLog(@"[YAMNet] ANALYSIS START: %@", audioURL.lastPathComponent ?: audioURL.absoluteString);
        if (!audioURL.isFileURL) {
            NSLog(@"[YAMNet] ANALYSIS FAILED: input is not a local file URL.");
            dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(nil, YAMNetError(10, @"YAMNet 当前只分析本地音频文件。")); });
            return;
        }
        NSError *error = nil;
        NSString *digest = [self sha256ForURL:audioURL error:&error];
        if (digest) {
            NSData *cached = [NSData dataWithContentsOfURL:[self cacheURLForDigest:digest] options:NSDataReadingMappedIfSafe error:nil];
            NSDictionary *cachedResult = cached ? [NSJSONSerialization JSONObjectWithData:cached options:0 error:nil] : nil;
            if ([cachedResult isKindOfClass:NSDictionary.class]) {
                NSArray *cachedPatches = [cachedResult[@"patches"] isKindOfClass:NSArray.class] ? cachedResult[@"patches"] : @[];
                NSLog(@"[YAMNet] CACHE HIT: %@ (%lu windows, %.2f sec).", [self cacheURLForDigest:digest].path,
                      (unsigned long)cachedPatches.count, [cachedResult[@"duration_sec"] doubleValue]);
                dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(cachedResult, nil); });
                return;
            }
        }
        NSLog(@"[YAMNet] CACHE MISS: running full-track PCM analysis.");
        [self.modelLock lock];
        MLModel *model = self.model;
        [self.modelLock unlock];
        if (!model) error = YAMNetError(11, @"尚未安装 YAMNet Core ML 模型；请先调用 installModelAtURL: 安装工程内模型。");

        NSMutableData *pcm = nil;
        double duration = 0;
        if (!error) pcm = [self decodeAudioURL:audioURL duration:&duration error:&error];
        NSDictionary *result = nil;
        if (!error) {
            NSLog(@"[YAMNet] PCM READY: %.2f sec, %lu mono Float32 samples at %d Hz.", duration,
                  (unsigned long)(pcm.length / sizeof(float)), kYAMNetSampleRate);
            NSLog(@"[YAMNet] INFERENCE START: model=%@.", kYAMNetModelVersion);
            result = [self runModel:model pcm:pcm duration:duration digest:digest sourceURL:audioURL error:&error];
        }
        if (error) NSLog(@"[YAMNet] ANALYSIS FAILED: %@", error.localizedDescription);
        if (!error && result) {
            NSData *json = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingFragmentsAllowed error:&error];
            if (json) {
                NSURL *cacheURL = [self cacheURLForDigest:digest];
                [[NSFileManager defaultManager] createDirectoryAtURL:cacheURL.URLByDeletingLastPathComponent
                                          withIntermediateDirectories:YES attributes:nil error:&error];
                if (!error) [json writeToURL:cacheURL options:NSDataWritingAtomic error:&error];
                if (!error) {
                    NSArray *patches = [result[@"patches"] isKindOfClass:NSArray.class] ? result[@"patches"] : @[];
                    NSLog(@"[YAMNet] ANALYSIS COMPLETE: %@ | %.2f sec audio | %lu windows | cache=%@ | elapsed=%.2f sec.",
                          audioURL.lastPathComponent, duration, (unsigned long)patches.count, cacheURL.path,
                          CFAbsoluteTimeGetCurrent() - analysisStartedAt);
                }
            }
        }
        if (error) NSLog(@"[YAMNet] CACHE WRITE/ANALYSIS FAILED: %@", error.localizedDescription);
        dispatch_async(dispatch_get_main_queue(), ^{ if (completion) completion(error ? nil : result, error); });
    });
}

- (NSMutableData *)decodeAudioURL:(NSURL *)url duration:(double *)duration error:(NSError **)error {
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:url options:nil];
    AVAssetTrack *track = [[asset tracksWithMediaType:AVMediaTypeAudio] firstObject];
    if (!track) { if (error) *error = YAMNetError(12, @"音频文件中没有音轨。"); return nil; }
    NSError *readerError = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&readerError];
    if (!reader) { if (error) *error = readerError; return nil; }
    NSDictionary *settings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(kYAMNetSampleRate),
        AVNumberOfChannelsKey: @1,
        AVLinearPCMBitDepthKey: @32,
        AVLinearPCMIsFloatKey: @YES,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO
    };
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:track outputSettings:settings];
    output.alwaysCopiesSampleData = NO;
    if (![reader canAddOutput:output]) { if (error) *error = YAMNetError(13, @"无法创建 16 kHz 单声道 PCM 解码器。"); return nil; }
    [reader addOutput:output];
    if (![reader startReading]) { if (error) *error = reader.error ?: YAMNetError(14, @"音频解码启动失败。"); return nil; }
    NSMutableData *pcm = [NSMutableData data];
    while (reader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sample = [output copyNextSampleBuffer];
        if (!sample) break;
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sample);
        if (block) {
            size_t totalLength = 0;
            char *bytes = NULL;
            OSStatus status = CMBlockBufferGetDataPointer(block, 0, NULL, &totalLength, &bytes);
            if (status == kCMBlockBufferNoErr && bytes && totalLength) [pcm appendBytes:bytes length:totalLength];
        }
        CFRelease(sample);
    }
    if (reader.status == AVAssetReaderStatusFailed) { if (error) *error = reader.error ?: YAMNetError(15, @"音频解码失败。"); return nil; }
    if (pcm.length < sizeof(float)) { if (error) *error = YAMNetError(16, @"解码后 PCM 为空。"); return nil; }
    if (duration) *duration = (double)(pcm.length / sizeof(float)) / kYAMNetSampleRate;
    return pcm;
}

static float YAMNetMel(float hz) { return 2595.0f * log10f(1.0f + hz / 700.0f); }
static float YAMNetMelToHz(float mel) { return 700.0f * (powf(10.0f, mel / 2595.0f) - 1.0f); }

- (NSDictionary *)runModel:(MLModel *)model pcm:(NSData *)pcm duration:(double)duration digest:(NSString *)digest sourceURL:(NSURL *)sourceURL error:(NSError **)error {
    const float *audio = pcm.bytes;
    NSUInteger sampleCount = pcm.length / sizeof(float);
    const NSUInteger minSamples = kYAMNetWindowSize + kYAMNetHopSize * (kYAMNetPatchFrames - 1);
    const NSUInteger patchHopSamples = kYAMNetPatchHopFrames * kYAMNetHopSize;
    NSUInteger paddedLength = MAX(sampleCount, minSamples);
    if (paddedLength > minSamples) {
        NSUInteger remaining = paddedLength - minSamples;
        paddedLength = minSamples + ((remaining + patchHopSamples - 1) / patchHopSamples) * patchHopSamples;
    }
    NSUInteger frameCount = (paddedLength + kYAMNetHopSize - 1) / kYAMNetHopSize;
    NSUInteger patchCount = frameCount < kYAMNetPatchFrames ? 0 : 1 + (frameCount - kYAMNetPatchFrames) / kYAMNetPatchHopFrames;
    if (patchCount == 0) { if (error) *error = YAMNetError(17, @"音频太短，不能组成 YAMNet 输入窗口。"); return nil; }

    float *logMel = calloc(frameCount * kYAMNetMelBands, sizeof(float));
    float *windowed = calloc(kYAMNetFFTSize, sizeof(float));
    float *magnitudes = calloc(kYAMNetFFTSize / 2 + 1, sizeof(float));
    float *melWeights = calloc(kYAMNetMelBands * (kYAMNetFFTSize / 2 + 1), sizeof(float));
    float *fftReal = calloc(kYAMNetFFTSize / 2, sizeof(float));
    float *fftImag = calloc(kYAMNetFFTSize / 2, sizeof(float));
    if (!logMel || !windowed || !magnitudes || !melWeights || !fftReal || !fftImag) {
        if (error) *error = YAMNetError(18, @"YAMNet 特征缓冲分配失败。");
        free(logMel); free(windowed); free(magnitudes); free(melWeights); free(fftReal); free(fftImag); return nil;
    }

    const float melMin = YAMNetMel(125.0f), melMax = YAMNetMel(7500.0f);
    float edgeHz[66];
    for (int i = 0; i < kYAMNetMelBands + 2; i++) {
        float mel = melMin + (melMax - melMin) * (float)i / (float)(kYAMNetMelBands + 1);
        edgeHz[i] = YAMNetMelToHz(mel);
    }
    for (int band = 0; band < kYAMNetMelBands; band++) {
        float left = edgeHz[band], center = edgeHz[band + 1], right = edgeHz[band + 2];
        for (int bin = 0; bin <= kYAMNetFFTSize / 2; bin++) {
            float hz = (float)bin * kYAMNetSampleRate / kYAMNetFFTSize;
            float weight = hz < center ? (hz - left) / (center - left) : (right - hz) / (right - center);
            melWeights[band * (kYAMNetFFTSize / 2 + 1) + bin] = MAX(0.0f, weight);
        }
    }

    FFTSetup setup = vDSP_create_fftsetup(9, kFFTRadix2);
    if (!setup) {
        if (error) *error = YAMNetError(19, @"无法创建 Accelerate FFT。");
        free(logMel); free(windowed); free(magnitudes); free(melWeights); free(fftReal); free(fftImag);
        return nil;
    }
    if (setup) {
        for (NSUInteger frame = 0; frame < frameCount; frame++) {
            memset(windowed, 0, sizeof(float) * kYAMNetFFTSize);
            NSUInteger start = frame * kYAMNetHopSize;
            for (int n = 0; n < kYAMNetWindowSize; n++) {
                NSUInteger index = start + (NSUInteger)n;
                float sample = index < sampleCount ? audio[index] : 0.0f;
                float hann = 0.5f - 0.5f * cosf((2.0f * (float)M_PI * n) / kYAMNetWindowSize);
                windowed[n] = sample * hann;
            }
            DSPSplitComplex split = { fftReal, fftImag };
            vDSP_ctoz((const DSPComplex *)windowed, 2, &split, 1, kYAMNetFFTSize / 2);
            vDSP_fft_zrip(setup, &split, 1, 9, FFT_FORWARD);
            magnitudes[0] = fabsf(fftReal[0]) * 0.5f;
            for (int bin = 1; bin < kYAMNetFFTSize / 2; bin++) magnitudes[bin] = hypotf(fftReal[bin], fftImag[bin]) * 0.5f;
            magnitudes[kYAMNetFFTSize / 2] = fabsf(fftImag[0]) * 0.5f;
            float *row = logMel + frame * kYAMNetMelBands;
            for (int band = 0; band < kYAMNetMelBands; band++) {
                const float *weights = melWeights + band * (kYAMNetFFTSize / 2 + 1);
                float sum = 0.0f;
                vDSP_dotpr(magnitudes, 1, weights, 1, &sum, kYAMNetFFTSize / 2 + 1);
                row[band] = logf(sum + 0.001f);
            }
        }
        vDSP_destroy_fftsetup(setup);
    }

    NSMutableArray *patches = [NSMutableArray arrayWithCapacity:patchCount];
    NSString *inputName = @"features";
    NSString *outputName = model.modelDescription.outputDescriptionsByName.allKeys.firstObject;
    NSError *predictionError = nil;
    for (NSUInteger patch = 0; patch < patchCount && !predictionError; patch++) {
        MLMultiArray *input = [[MLMultiArray alloc] initWithShape:@[@1, @(kYAMNetPatchFrames), @(kYAMNetMelBands)]
                                                        dataType:self.modelInputType
                                                           error:&predictionError];
        if (!input) break;
        float *target = self.modelInputType == MLMultiArrayDataTypeFloat32 ? input.dataPointer : NULL;
        NSUInteger frameStart = patch * kYAMNetPatchHopFrames;
        for (NSUInteger frame = 0; frame < kYAMNetPatchFrames; frame++) {
            const float *source = logMel + (frameStart + frame) * kYAMNetMelBands;
            if (target) {
                memcpy(target + frame * kYAMNetMelBands, source, sizeof(float) * kYAMNetMelBands);
            } else {
                for (int band = 0; band < kYAMNetMelBands; band++) {
                    input[(NSInteger)(frame * kYAMNetMelBands + band)] = @(source[band]);
                }
            }
        }
        MLDictionaryFeatureProvider *provider = [[MLDictionaryFeatureProvider alloc] initWithDictionary:@{
            inputName: [MLFeatureValue featureValueWithMultiArray:input]
        } error:&predictionError];
        id<MLFeatureProvider> output = provider ? [model predictionFromFeatures:provider error:&predictionError] : nil;
        MLMultiArray *scores = [output featureValueForName:outputName].multiArrayValue;
        if (!scores || scores.count != kYAMNetClasses) {
            if (!predictionError) predictionError = YAMNetError(20, @"Core ML 输出不是 521 类 YAMNet 分数。");
            break;
        }
        NSMutableArray *scoreRow = [NSMutableArray arrayWithCapacity:kYAMNetClasses];
        for (NSUInteger index = 0; index < kYAMNetClasses; index++) [scoreRow addObject:@(scores[index].floatValue)];
        NSTimeInterval startSeconds = (NSTimeInterval)(patch * kYAMNetPatchHopFrames * kYAMNetHopSize) / kYAMNetSampleRate;
        [patches addObject:@{@"start": @(startSeconds), @"center": @(startSeconds + 0.48), @"scores": scoreRow}];
    }

    free(logMel); free(windowed); free(magnitudes); free(melWeights); free(fftReal); free(fftImag);
    if (predictionError) { if (error) *error = predictionError; return nil; }
    NSLog(@"[YAMNet] INFERENCE COMPLETE: %lu windows x %d class scores.", (unsigned long)patches.count, kYAMNetClasses);
    return @{
        @"schema_version": @1,
        @"model_version": kYAMNetModelVersion,
        @"source_sha256": digest ?: @"",
        @"source": sourceURL.lastPathComponent ?: @"",
        @"sample_rate_hz": @(kYAMNetSampleRate),
        @"duration_sec": @(duration),
        @"patch_length_sec": @0.96,
        @"patch_hop_sec": @0.48,
        @"class_indices": @{@"guitar": @135, @"electric_guitar": @136},
        @"patches": patches
    };
}

@end
