#import "MVMomentAnalyzer.h"
#import "RealtimeAnalyzer.h"
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>

static NSString * const kMVVersion = @"mv-moments-v3";

@interface MVMomentAnalyzer ()
@property(nonatomic) dispatch_queue_t queue;
@end

@implementation MVMomentAnalyzer

+ (instancetype)sharedAnalyzer {
    static MVMomentAnalyzer *v;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ v = [self new]; });
    return v;
}

- (instancetype)init {
    if ((self = [super init])) _queue = dispatch_queue_create("com.audiosamplebuffer.mv-moments", dispatch_queue_attr_make_with_qos_class(DISPATCH_QUEUE_SERIAL, QOS_CLASS_UTILITY, 0));
    return self;
}

- (NSProgress *)analyzeFileAtURL:(NSURL *)url completion:(void (^)(NSArray<NSDictionary<NSString *,NSNumber *> *> *, BOOL, NSError *))completion {
    NSProgress *progress = [NSProgress progressWithTotalUnitCount:1000];
    progress.cancellable = YES;
    dispatch_async(self.queue, ^{
        if (progress.isCancelled) return;
        NSError *error = nil;
        NSDictionary *identity = [self identityForURL:url error:&error];
        NSString *cachePath = identity ? [self cachePathForKey:identity[@"key"]] : nil;
        NSArray *cached = identity ? [self cachedMomentsAtPath:cachePath duration:[identity[@"duration"] doubleValue]] : nil;
        if (!progress.isCancelled && cached) {
            NSLog(@"[MVMomentAnalyzer] cache hit duration=%.3f moments=%lu", [identity[@"duration"] doubleValue], (unsigned long)cached.count);
            [self deliver:cached hit:YES error:nil progress:progress completion:completion];
            return;
        }
        if (!url || error) {
            if (!error) error = [NSError errorWithDomain:@"MVMomentAnalyzer" code:1 userInfo:@{NSLocalizedDescriptionKey:@"Audio URL is missing."}];
            [self deliver:nil hit:NO error:error progress:progress completion:completion];
            return;
        }
        AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:&error];
        AVAudioFormat *format = file.processingFormat;
        if (!file || error || !format.isStandard || format.channelCount == 0) {
            if (!error) error = [NSError errorWithDomain:@"MVMomentAnalyzer" code:2 userInfo:@{NSLocalizedDescriptionKey:@"Unable to decode Float32 PCM audio."}];
            [self deliver:nil hit:NO error:error progress:progress completion:completion];
            return;
        }
        AVAudioPCMBuffer *buffer = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:2048];
        RealtimeAnalyzer *fft = [[RealtimeAnalyzer alloc] initWithFFTSize:2048];
        fft.legacyExactMode = YES;
        NSMutableArray *buckets = [NSMutableArray array];
        AVAudioFramePosition read = 0;
        while (!progress.isCancelled) @autoreleasepool {
            buffer.frameLength = 0;
            if (![file readIntoBuffer:buffer error:&error] || error) break;
            AVAudioFrameCount count = buffer.frameLength;
            if (!count) break;
            NSArray *channels = [fft analyse:buffer withAmplitudeLevel:5];
            if (!channels.count) { error = [NSError errorWithDomain:@"MVMomentAnalyzer" code:3 userInfo:@{NSLocalizedDescriptionKey:@"Decoder returned no channel data."}]; break; }
            double total = 0, high = 0;
            for (NSArray *bands in channels) for (NSUInteger i = 0; i < MIN((NSUInteger)80, bands.count); i++) {
                double x = MAX(0, [bands[i] doubleValue]) / channels.count;
                total += x;
                if (i >= 60) high += x;
            }
            double ratio = total > 0 ? high / total : 0;
            AVAudioFramePosition chunkStart = read;
            AVAudioFrameCount remaining = count;
            while (remaining > 0) {
                NSUInteger index = (NSUInteger)floor((double)chunkStart / format.sampleRate);
                AVAudioFramePosition bucketEnd = (AVAudioFramePosition)((index + 1) * format.sampleRate);
                AVAudioFrameCount portion = (AVAudioFrameCount)MIN((AVAudioFramePosition)remaining, bucketEnd - chunkStart);
                while (buckets.count <= index) [buckets addObject:[@{@"frames":@0, @"ratio":@0, @"energy":@0} mutableCopy]];
                NSMutableDictionary *b = buckets[index];
                b[@"frames"] = @([b[@"frames"] doubleValue] + portion);
                b[@"ratio"] = @([b[@"ratio"] doubleValue] + ratio * portion);
                b[@"energy"] = @([b[@"energy"] doubleValue] + total * portion);
                chunkStart += portion;
                remaining -= portion;
            }
            read += count;
            progress.completedUnitCount = MIN(999, (int64_t)(read * 1000.0 / MAX(1, file.length)));
        }
        if (progress.isCancelled) return;
        if (error) { [self deliver:nil hit:NO error:error progress:progress completion:completion]; return; }
        double duration = read / format.sampleRate;
        NSMutableArray *ratios = [NSMutableArray array], *energies = [NSMutableArray array];
        for (NSMutableDictionary *b in buckets) {
            double n = [b[@"frames"] doubleValue];
            if (n > 0) { b[@"ratio"] = @([b[@"ratio"] doubleValue] / n); b[@"energy"] = @([b[@"energy"] doubleValue] / n); [ratios addObject:b[@"ratio"]]; [energies addObject:b[@"energy"]]; }
        }
        NSArray *moments = [self moments:buckets duration:duration sampleRate:format.sampleRate ratios:ratios energies:energies];
        NSLog(@"[MVMomentAnalyzer] analyzed duration=%.3f moments=%lu", duration, (unsigned long)moments.count);
        if (!progress.isCancelled && identity) [self write:moments duration:duration path:cachePath];
        progress.completedUnitCount = 1000;
        [self deliver:moments hit:NO error:nil progress:progress completion:completion];
    });
    return progress;
}

- (void)deliver:(NSArray *)moments hit:(BOOL)hit error:(NSError *)error progress:(NSProgress *)progress completion:(void (^)(NSArray *, BOOL, NSError *))completion {
    if (progress.isCancelled) return;
    dispatch_async(dispatch_get_main_queue(), ^{ if (!progress.isCancelled && completion) completion(moments, hit, error); });
}

- (void)collectBuckets:(NSArray *)buckets duration:(double)duration sampleRate:(double)sampleRate maxRatio:(double)maxRatio maxEnergy:(double)maxEnergy kind:(NSInteger)kind into:(NSMutableArray *)out test:(BOOL (^)(NSDictionary *bucket))test {
    NSUInteger start = NSNotFound;
    for (NSUInteger i = 0; i < buckets.count; i++) {
        BOOL selected = test(buckets[i]);
        if (selected && start == NSNotFound) start = i;
        if ((!selected || i + 1 == buckets.count) && start != NSNotFound) {
            NSUInteger end = selected ? i + 1 : i;
            double frames = 0;
            for (NSUInteger j = start; j < end; j++) frames += [buckets[j][@"frames"] doubleValue];
            if (frames >= 4.0 * sampleRate) {
                double ratio = 0, energy = 0;
                for (NSUInteger j = start; j < end; j++) { ratio += [buckets[j][@"ratio"] doubleValue]; energy += [buckets[j][@"energy"] doubleValue]; }
                ratio /= end - start; energy /= end - start;
                [out addObject:@{@"start": @(start), @"end": @(MIN(duration, (double)end)), @"score": @((ratio / maxRatio * .7 + energy / maxEnergy * .3) * 100), @"kind": @(kind)}];
            }
            start = NSNotFound;
        }
    }
}

- (NSArray *)moments:(NSArray *)buckets duration:(double)duration sampleRate:(double)sampleRate ratios:(NSArray *)ratios energies:(NSArray *)energies {
    if (!ratios.count) return @[];
    NSArray *r = [ratios sortedArrayUsingSelector:@selector(compare:)], *e = [energies sortedArrayUsingSelector:@selector(compare:)];
    double ratioCut = [r[(NSUInteger)floor((r.count - 1) * .72)] doubleValue], energyCut = [e[(NSUInteger)floor((e.count - 1) * .45)] doubleValue];
    double brightCut = [r[(NSUInteger)floor((r.count - 1) * .88)] doubleValue], energyFloor = [e[(NSUInteger)floor((e.count - 1) * .25)] doubleValue];
    double maxRatio = MAX(1e-12, [r.lastObject doubleValue]), maxEnergy = MAX(1e-12, [e.lastObject doubleValue]);
    NSMutableArray *out = [NSMutableArray array];
    // kind 1: loud and bright, the sustained high-energy portion of the whole song.
    [self collectBuckets:buckets duration:duration sampleRate:sampleRate maxRatio:maxRatio maxEnergy:maxEnergy kind:1 into:out test:^BOOL(NSDictionary *bucket) {
        double ratio = [bucket[@"ratio"] doubleValue], energy = [bucket[@"energy"] doubleValue];
        return ratio > 0.0 && energy > 1e-6 && ratio >= ratioCut && energy >= energyCut;
    }];
    // kind 2: bright but below the chorus energy, a candidate for an exposed instrument passage.
    [self collectBuckets:buckets duration:duration sampleRate:sampleRate maxRatio:maxRatio maxEnergy:maxEnergy kind:2 into:out test:^BOOL(NSDictionary *bucket) {
        double ratio = [bucket[@"ratio"] doubleValue], energy = [bucket[@"energy"] doubleValue];
        return ratio >= brightCut && energy >= energyFloor && energy < energyCut;
    }];
    return [out sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *lhs, NSDictionary *rhs) {
        return [lhs[@"start"] compare:rhs[@"start"]];
    }];
}

- (NSDictionary *)identityForURL:(NSURL *)url error:(NSError **)error {
    if (!url) return nil;
    NSDictionary *v = [url resourceValuesForKeys:@[NSURLFileSizeKey, NSURLContentModificationDateKey] error:error];
    if (!v) return nil;
    AVAudioFile *f = [[AVAudioFile alloc] initForReading:url error:error]; if (!f) return nil;
    NSDate *mtime = v[NSURLContentModificationDateKey] ?: [NSDate distantPast];
    NSString *raw = [NSString stringWithFormat:@"%@|%@|%@|%.9f", kMVVersion, url.standardizedURL.path, v[NSURLFileSizeKey] ?: @0, mtime.timeIntervalSince1970];
    unsigned char digest[CC_SHA256_DIGEST_LENGTH]; CC_SHA256(raw.UTF8String, (CC_LONG)strlen(raw.UTF8String), digest);
    NSMutableString *hex = [NSMutableString string]; for (NSUInteger i=0;i<CC_SHA256_DIGEST_LENGTH;i++) [hex appendFormat:@"%02x", digest[i]];
    return @{@"key":hex, @"duration":@(f.length / f.processingFormat.sampleRate)};
}

- (NSString *)cachePathForKey:(NSString *)key {
    NSURL *dir = [[[[NSFileManager defaultManager] URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask] firstObject] URLByAppendingPathComponent:@"MVMoments" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:dir withIntermediateDirectories:YES attributes:nil error:nil];
    return [[dir URLByAppendingPathComponent:key] URLByAppendingPathExtension:@"json"].path;
}

- (NSArray *)cachedMomentsAtPath:(NSString *)path duration:(double)duration {
    NSData *data = [NSData dataWithContentsOfFile:path]; NSDictionary *o = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![o isKindOfClass:NSDictionary.class] || ![o[@"version"] isEqual:kMVVersion] || ![o[@"duration"] isKindOfClass:NSNumber.class] || !isfinite([o[@"duration"] doubleValue]) || [o[@"duration"] doubleValue] < 0 || fabs([o[@"duration"] doubleValue] - duration) > .01 || ![o[@"moments"] isKindOfClass:NSArray.class]) return nil;
    double previousEnd = 0;
    for (NSDictionary *m in o[@"moments"]) {
        if (![m isKindOfClass:NSDictionary.class] || ![m[@"start"] isKindOfClass:NSNumber.class] || ![m[@"end"] isKindOfClass:NSNumber.class] || ![m[@"score"] isKindOfClass:NSNumber.class] || ![m[@"kind"] isKindOfClass:NSNumber.class] || ([m[@"kind"] integerValue] != 1 && [m[@"kind"] integerValue] != 2)) return nil;
        double start = [m[@"start"] doubleValue], end = [m[@"end"] doubleValue], score = [m[@"score"] doubleValue];
        if (!isfinite(start) || !isfinite(end) || !isfinite(score) || start < 0 || end <= start || end > duration + .001 || start < previousEnd) return nil;
        previousEnd = end;
    }
    return o[@"moments"];
}

- (void)write:(NSArray *)moments duration:(double)duration path:(NSString *)path {
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":kMVVersion, @"duration":@(duration), @"moments":moments ?: @[]} options:0 error:nil];
    [data writeToFile:path options:NSDataWritingAtomic error:nil];
}
@end
