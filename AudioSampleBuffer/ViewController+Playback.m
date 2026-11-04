#import "ViewController+Private.h"

#import "AudioFileFormats.h"
#import "ViewController+PlaybackProgress.h"
#import "AudioSampleBuffer/RealtimeAnalyzer.h"
#import "AudioSampleBuffer-Swift.h"

#import <AVFoundation/AVFoundation.h>
#import <MediaPlayer/MediaPlayer.h>
#import <math.h>

static inline CGFloat ASBClamp01(CGFloat value) {
    return MIN(1.0, MAX(0.0, value));
}

static NSString *ASBActivityMeterBar(CGFloat value) {
    NSInteger count = (NSInteger)lrint(ASBClamp01(value) * 10.0);
    NSMutableString *bar = [NSMutableString stringWithCapacity:10];
    for (NSInteger idx = 0; idx < 10; idx++) {
        [bar appendString:(idx < count) ? @">" : @"."];
    }
    return bar;
}

static NSDictionary<NSString *, NSNumber *> *ASBActivityMeterParameters(AudioFeatures *features) {
    if (!features) return @{};
    CGFloat low = ASBClamp01(MAX(features.subBassEnergy, features.subOnlyEnergy));
    CGFloat transient = ASBClamp01(features.transientStrength + (features.transientHit ? 0.28 : 0.0));
    CGFloat harmonic = ASBClamp01(features.harmonicStrength + features.harmonicPeakRatio * 0.85);
    CGFloat noise = ASBClamp01(features.noiseStrength + (features.noiseFXActive ? 0.25 : 0.0));
    CGFloat high = ASBClamp01(features.highEnergy * 0.82 + features.spectralCentroid * 0.24);
    CGFloat electric = ASBClamp01(features.noiseStrength * 0.45 + features.spectralFlatness * 0.55 + features.distortionConfidence * 0.55);
    CGFloat chopped = ASBClamp01(MAX(features.stutterConfidence, MAX(features.gateConfidence, features.tremoloConfidence)));
    CGFloat sweep = ASBClamp01(features.filterSweepConfidence);
    CGFloat pan = ASBClamp01(features.autoPanConfidence);
    CGFloat echo = ASBClamp01(features.delayConfidence);
    CGFloat sidechain = ASBClamp01(features.sidechainConfidence);
    CGFloat energy = ASBClamp01(features.energy);
    CGFloat flatness = ASBClamp01(features.spectralFlatness);
    CGFloat mid = ASBClamp01(features.midEnergy);
    CGFloat electricBassLine = ASBClamp01(low * 0.42 + harmonic * 0.34 + mid * 0.18 + transient * 0.08 - features.subOnlyEnergy * 0.16);
    CGFloat electricGuitarTexture = ASBClamp01(mid * 0.28 + high * 0.24 + harmonic * 0.25 + electric * 0.20 + transient * 0.10);
    CGFloat distortedGuitar = ASBClamp01(features.distortionConfidence * 0.46 + high * 0.22 + flatness * 0.18 + harmonic * 0.16 + noise * 0.12);
    CGFloat pluckGrain = ASBClamp01(transient * 0.48 + high * 0.18 + features.harmonicPeakRatio * 0.22 + features.spectralFlux * 0.12);
    CGFloat soundWall = ASBClamp01(harmonic * 0.36 + noise * 0.24 + energy * 0.24 + features.distortionConfidence * 0.18 - transient * 0.10);
    CGFloat climax = features.currentSegment == MusicSegmentChorus ?
                      ASBClamp01(0.58 + energy * 0.42) : 0.0;
    BOOL legacyBassBeat = features.beatDetected && features.subBassEnergy <= 0.001f && features.bassEnergy > 0.0f;
    return @{
        @"activityLow": @(low),
        @"activityTransient": @(transient),
        @"activityHarmonic": @(harmonic),
        @"activityNoise": @(noise),
        @"activityHigh": @(high),
        @"activityElectric": @(electric),
        @"activityChopped": @(chopped),
        @"activitySweep": @(sweep),
        @"activityPan": @(pan),
        @"activityEcho": @(echo),
        @"activitySidechain": @(sidechain),
        @"activityEnergy": @(energy),
        @"activityFlatness": @(flatness),
        @"activityElectricBassLine": @(electricBassLine),
        @"activityElectricGuitarTexture": @(electricGuitarTexture),
        @"activityDistortedGuitar": @(distortedGuitar),
        @"activityPluckGrain": @(pluckGrain),
        @"activitySoundWall": @(soundWall),
        @"activityClimax": @(climax),
        @"vectorBeatDetected": @(features.beatDetected),
        @"vectorBeatIntensity": @(ASBClamp01(MAX(MAX(low, transient), legacyBassBeat ? features.bassEnergy : 0.0f))),
        @"vectorBeatKind": @((features.subBassHit || legacyBassBeat) ? 1 : 2),
        @"vectorBPM": @(features.bpm)
    };
}

static NSString *ASBMVTimeString(NSTimeInterval time) {
    NSInteger seconds = MAX(0, (NSInteger)floor(time));
    return [NSString stringWithFormat:@"%02ld:%02ld", (long)(seconds / 60), (long)(seconds % 60)];
}

// Sample the cached YAMNet electric-guitar class timeline at the current song
// position. Patches advance every 480 ms; interpolation keeps the visual cue
// smooth between adjacent model windows.
static NSDictionary<NSString *, NSNumber *> *ASBYAMNetGuitarControl(NSDictionary *analysis,
                                                                    NSTimeInterval playbackTime) {
    NSArray *patches = [analysis[@"patches"] isKindOfClass:NSArray.class] ? analysis[@"patches"] : nil;
    if (patches.count == 0 || playbackTime < 0.0) {
        return @{@"guitarYAMNetScore": @0.0, @"guitarYAMNetControl": @0.0};
    }
    double duration = [analysis[@"duration_sec"] doubleValue];
    if (duration > 0.0 && playbackTime >= duration) {
        return @{@"guitarYAMNetScore": @0.0, @"guitarYAMNetControl": @0.0};
    }
    double hop = [analysis[@"patch_hop_sec"] doubleValue];
    if (!isfinite(hop) || hop <= 0.0) hop = 0.48;
    NSInteger classIndex = [analysis[@"class_indices"][@"electric_guitar"] respondsToSelector:@selector(integerValue)] ?
        [analysis[@"class_indices"][@"electric_guitar"] integerValue] : 136;
    if (classIndex < 0) classIndex = 136;

    double patchLength = [analysis[@"patch_length_sec"] doubleValue];
    if (!isfinite(patchLength) || patchLength <= 0.0) patchLength = 0.96;
    // Each inference score describes a centered 0.96 s window. Align the
    // playback cursor to those centers instead of treating the window start as
    // its timestamp (the old mapping lagged the score timeline by 480 ms).
    double position = fmax(0.0, (playbackTime - patchLength * 0.5) / hop);
    NSUInteger firstIndex = MIN((NSUInteger)position, patches.count - 1);
    NSUInteger secondIndex = MIN(firstIndex + 1, patches.count - 1);
    NSDictionary *firstPatch = [patches[firstIndex] isKindOfClass:NSDictionary.class] ? patches[firstIndex] : nil;
    NSDictionary *secondPatch = [patches[secondIndex] isKindOfClass:NSDictionary.class] ? patches[secondIndex] : nil;
    NSArray *firstScores = [firstPatch[@"scores"] isKindOfClass:NSArray.class] ? firstPatch[@"scores"] : nil;
    NSArray *secondScores = [secondPatch[@"scores"] isKindOfClass:NSArray.class] ? secondPatch[@"scores"] : nil;
    double fraction = position - floor(position);
    NSInteger guitarClassIndex = [analysis[@"class_indices"][@"guitar"] respondsToSelector:@selector(integerValue)] ?
        [analysis[@"class_indices"][@"guitar"] integerValue] : 135;
    double electricScore = 0.0;
    double guitarScore = 0.0;
    if (firstScores.count > (NSUInteger)classIndex && secondScores.count > (NSUInteger)classIndex) {
        double a = [firstScores[(NSUInteger)classIndex] doubleValue];
        double b = [secondScores[(NSUInteger)classIndex] doubleValue];
        electricScore = fmax(0.0, fmin(1.0, a + (b - a) * fraction));
    }
    if (guitarClassIndex >= 0 && firstScores.count > (NSUInteger)guitarClassIndex &&
        secondScores.count > (NSUInteger)guitarClassIndex) {
        double a = [firstScores[(NSUInteger)guitarClassIndex] doubleValue];
        double b = [secondScores[(NSUInteger)guitarClassIndex] doubleValue];
        guitarScore = fmax(0.0, fmin(1.0, a + (b - a) * fraction));
    }
    // Some sustained or distorted leads score higher as the broader Guitar
    // AudioSet class than Electric guitar. Use either class for this recall-
    // focused PoC, and retain both values in diagnostics for later tuning.
    double score = fmax(electricScore, guitarScore);
    const double scoreFloor = 0.0008;
    const double scoreFullScale = 0.0095;
    // AudioSet confidence is low compared with a separated stem. This wider
    // mapping range lowers the PoC trigger threshold; tune against false hits.
    double control = fmax(0.0, fmin(1.0, (score - scoreFloor) / (scoreFullScale - scoreFloor)));
    return @{@"guitarYAMNetScore": @(score),
             @"guitarYAMNetElectricScore": @(electricScore),
             @"guitarYAMNetGenericScore": @(guitarScore),
             @"guitarYAMNetControl": @(control)};
}

// YAMNet's official 521-class map assigns class 24 to Singing. Its cached
// 0.96 s windows provide a phrase cue when there is no dedicated vocal stem.
static NSDictionary<NSString *, NSNumber *> *ASBYAMNetVocalControl(NSDictionary *analysis,
                                                                   NSTimeInterval playbackTime) {
    NSArray *patches = [analysis[@"patches"] isKindOfClass:NSArray.class] ? analysis[@"patches"] : nil;
    double duration = [analysis[@"duration_sec"] doubleValue];
    if (patches.count == 0 || playbackTime < 0.0 || (duration > 0.0 && playbackTime >= duration)) {
        return @{@"vocalYAMNetEnabled": @NO, @"vocalYAMNetControl": @0.0f};
    }
    double hop = [analysis[@"patch_hop_sec"] doubleValue];
    if (!isfinite(hop) || hop <= 0.0) hop = 0.48;
    double patchLength = [analysis[@"patch_length_sec"] doubleValue];
    if (!isfinite(patchLength) || patchLength <= 0.0) patchLength = 0.96;
    double position = fmax(0.0, (playbackTime - patchLength * 0.5) / hop);
    NSUInteger first = MIN((NSUInteger)position, patches.count - 1);
    NSUInteger second = MIN(first + 1, patches.count - 1);
    NSDictionary *firstPatch = [patches[first] isKindOfClass:NSDictionary.class] ? patches[first] : nil;
    NSDictionary *secondPatch = [patches[second] isKindOfClass:NSDictionary.class] ? patches[second] : nil;
    NSArray *a = [firstPatch[@"scores"] isKindOfClass:NSArray.class] ? firstPatch[@"scores"] : nil;
    NSArray *b = [secondPatch[@"scores"] isKindOfClass:NSArray.class] ? secondPatch[@"scores"] : nil;
    if (a.count <= 24 || b.count <= 24) return @{@"vocalYAMNetEnabled": @NO, @"vocalYAMNetControl": @0.0f};
    float score = [a[24] floatValue] + ([b[24] floatValue] - [a[24] floatValue]) * (float)(position - floor(position));
    return @{@"vocalYAMNetEnabled": @YES, @"vocalYAMNetControl": @(ASBClamp01((score - 0.02f) / 0.18f))};
}

static NSDictionary<NSString *, NSNumber *> *ASBGuitarVisualControl(NSTimeInterval playbackTime,
                                                                    NSDictionary *yamnetAnalysis) {
    NSDictionary *yamnet = ASBYAMNetGuitarControl(yamnetAnalysis, playbackTime);
    float modelLevel = [yamnet[@"guitarYAMNetControl"] floatValue];
    return @{
        @"guitarStemControlEnabled": @(yamnetAnalysis[@"patches"] != nil),
        @"guitarStemControl": @(modelLevel),
        @"guitarStemControlSource": @(modelLevel > 0.0f ? 1 : 0),
        @"guitarYAMNetScore": yamnet[@"guitarYAMNetScore"] ?: @0.0,
        @"guitarYAMNetControl": @(modelLevel)
    };
}

// Full-song 50 ms control curve generated from the desktop Demucs Guitar stem.
// The old 2:54-3:30 passage uses the same calibration and matches frame for frame.
static NSArray<NSNumber *> *ASBMingZiDemucsFullSongCurve(void) {
    static NSArray<NSNumber *> *curve;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSURL *url = [[NSBundle mainBundle] URLForResource:@"LiRongHao-MingZi-GuitarControl-Full"
                                             withExtension:@"csv"];
        NSString *contents = url ? [NSString stringWithContentsOfURL:url
                                                            encoding:NSUTF8StringEncoding error:nil] : nil;
        NSMutableArray<NSNumber *> *frames = [NSMutableArray arrayWithCapacity:5328];
        for (NSString *part in [contents componentsSeparatedByCharactersInSet:
                               [NSCharacterSet characterSetWithCharactersInString:@",\n\r"]]) {
            if (part.length == 0) continue;
            double value = part.doubleValue;
            if (!isfinite(value) || value < 0.0 || value > 1.0) {
                [frames removeAllObjects];
                break;
            }
            [frames addObject:@(value)];
        }
        curve = frames.count == 5328 ? frames.copy : @[];
        NSLog(@"[GuitarVisual] Demucs 全曲控制数据 %@：%lu 帧",
              curve.count ? @"已加载" : @"无效或缺失", (unsigned long)curve.count);
    });
    return curve;
}

static NSDictionary<NSString *, NSNumber *> *ASBMingZiDemucsVisualControl(MusicItem *item,
                                                                           NSTimeInterval duration,
                                                                           NSTimeInterval playbackTime) {
    if (!item) return nil;
    NSString *identity = [NSString stringWithFormat:@"%@ %@ %@", item.fileName ?: @"",
                          item.displayName ?: @"", item.artist ?: @""];
    BOOL matchingSong = [identity containsString:@"李荣浩"] && [identity containsString:@"名字"] &&
                        isfinite(duration) && fabs(duration - 266.37) < 2.0;
    if (!matchingSong) return nil;
    NSArray<NSNumber *> *curve = ASBMingZiDemucsFullSongCurve();
    if (curve.count == 0) return nil;
    float level = 0.0f;
    if (playbackTime >= 0.0 && playbackTime < 266.37) {
        double position = playbackTime * 20.0;
        NSUInteger index = MIN((NSUInteger)position, curve.count - 1);
        NSUInteger next = MIN(index + 1, curve.count - 1);
        level = curve[index].floatValue +
                (curve[next].floatValue - curve[index].floatValue) * (float)(position - floor(position));
    }
    return @{@"guitarStemControlEnabled": @YES,
             @"guitarStemControl": @(ASBClamp01(level)),
             @"guitarStemControlSource": @2};
}

static NSDictionary<NSString *, NSNumber *> *ASBPhoneDemucsVisualControl(MusicItem *item,
                                                                         NSTimeInterval duration,
                                                                         NSTimeInterval playbackTime,
                                                                         NSDictionary *analysis) {
    if (!item || ![analysis[@"frames"] isKindOfClass:NSArray.class]) return nil;
    BOOL matchingDuration = isfinite(duration) && fabs(duration - [analysis[@"duration_sec"] doubleValue]) < 2.0;
    if (!matchingDuration) return nil;
    double hop = [analysis[@"frame_hop_sec"] doubleValue];
    if (!isfinite(hop) || hop <= 0.0) hop = 0.05;
    NSDictionary *stems = [analysis[@"stems"] isKindOfClass:NSDictionary.class] ? analysis[@"stems"] : @{};
    float (^sampleCurve)(NSArray<NSNumber *> *) = ^float(NSArray<NSNumber *> *frames) {
        if (frames.count == 0 || playbackTime < 0.0 || playbackTime >= duration) return 0.0f;
        double position = playbackTime / hop;
        NSUInteger index = MIN((NSUInteger)position, frames.count - 1);
        NSUInteger next = MIN(index + 1, frames.count - 1);
        return ASBClamp01(frames[index].floatValue +
            (frames[next].floatValue - frames[index].floatValue) * (float)(position - floor(position)));
    };
    NSDictionary *guitarStem = [stems[@"guitar"] isKindOfClass:NSDictionary.class] ? stems[@"guitar"] : nil;
    NSDictionary *pianoStem = [stems[@"piano"] isKindOfClass:NSDictionary.class] ? stems[@"piano"] : nil;
    NSDictionary *drumsStem = [stems[@"drums"] isKindOfClass:NSDictionary.class] ? stems[@"drums"] : nil;
    NSDictionary *otherStem = [stems[@"other"] isKindOfClass:NSDictionary.class] ? stems[@"other"] : nil;
    NSArray<NSNumber *> *guitarFrames = [guitarStem[@"frames"] isKindOfClass:NSArray.class] ? guitarStem[@"frames"] : analysis[@"frames"];
    NSArray<NSNumber *> *pianoFrames = [pianoStem[@"frames"] isKindOfClass:NSArray.class] ? pianoStem[@"frames"] : analysis[@"piano_frames"];
    NSArray<NSNumber *> *drumsFrames = [drumsStem[@"frames"] isKindOfClass:NSArray.class] ? drumsStem[@"frames"] : analysis[@"drums_frames"];
    NSArray<NSNumber *> *otherFrames = [otherStem[@"frames"] isKindOfClass:NSArray.class] ? otherStem[@"frames"] : analysis[@"other_frames"];
    BOOL hasGuitar = guitarFrames.count > 0;
    BOOL hasPiano = pianoFrames.count > 0;
    BOOL hasDrums = drumsFrames.count > 0;
    BOOL hasOther = otherFrames.count > 0;
    if (!hasGuitar && !hasPiano && !hasDrums && !hasOther) return nil;
    return @{@"guitarStemControlEnabled": @(hasGuitar),
             @"guitarStemControl": @(sampleCurve(guitarFrames ?: @[])),
             @"guitarStemControlSource": @3,
             @"pianoStemControlEnabled": @(hasPiano),
             @"pianoStemControl": @(sampleCurve(pianoFrames ?: @[])),
             @"drumsStemControlEnabled": @(hasDrums),
             @"drumsStemControl": @(sampleCurve(drumsFrames ?: @[])),
             @"otherStemControlEnabled": @(hasOther),
             @"otherStemControl": @(sampleCurve(otherFrames ?: @[]))};
}

static NSDictionary<NSString *, NSNumber *> *ASBMusicFeatureScopeValues(AudioFeatures *features) {
    if (!features) return @{};
    CGFloat low = ASBClamp01(MAX(features.subBassEnergy, features.subOnlyEnergy));
    CGFloat transient = ASBClamp01(features.transientStrength + (features.transientHit ? 0.28 : 0.0));
    CGFloat harmonic = ASBClamp01(features.harmonicStrength + features.harmonicPeakRatio * 0.85);
    CGFloat noise = ASBClamp01(features.noiseStrength + (features.noiseFXActive ? 0.25 : 0.0));
    CGFloat high = ASBClamp01(features.highEnergy * 0.82 + features.spectralCentroid * 0.24);
    CGFloat electric = ASBClamp01(features.noiseStrength * 0.45 + features.spectralFlatness * 0.55 + features.distortionConfidence * 0.55);
    CGFloat chopped = ASBClamp01(MAX(features.stutterConfidence, MAX(features.gateConfidence, features.tremoloConfidence)));
    CGFloat sweep = ASBClamp01(features.filterSweepConfidence);
    CGFloat echo = ASBClamp01(features.delayConfidence);
    CGFloat sidechain = ASBClamp01(features.sidechainConfidence);
    CGFloat energy = ASBClamp01(features.energy);
    CGFloat beat = ASBClamp01((features.beatDetected ? 0.42 : 0.0) + low * 0.48 + transient * 0.28);
    CGFloat kick = ASBClamp01((features.subBassHit ? 0.38 : 0.0) + low * 0.72);
    CGFloat bassline = ASBClamp01(harmonic * 0.58 + low * 0.36);
    CGFloat snareClap = ASBClamp01(transient * 0.78 + features.midEnergy * 0.18);
    CGFloat hihat = ASBClamp01(high * 0.72 + transient * 0.25);
    CGFloat lead = ASBClamp01(harmonic * 0.62 + high * 0.26);
    CGFloat pad = ASBClamp01(harmonic * 0.52 + echo * 0.26 + energy * 0.16);
    CGFloat pluck = ASBClamp01(transient * 0.54 + harmonic * 0.26 + high * 0.14);
    CGFloat riser = ASBClamp01(sweep * 0.78 + noise * 0.22);
    CGFloat drop = ASBClamp01(energy * 0.55 + low * 0.32 + sweep * 0.28 + noise * 0.18);
    CGFloat percussive = ASBClamp01(MAX(transient, chopped * 0.75));
    CGFloat flatness = ASBClamp01(features.spectralFlatness);
    CGFloat mid = ASBClamp01(features.midEnergy);
    CGFloat electricBassLine = ASBClamp01(low * 0.42 + harmonic * 0.34 + mid * 0.18 + transient * 0.08 - features.subOnlyEnergy * 0.16);
    CGFloat electricGuitarTexture = ASBClamp01(mid * 0.28 + high * 0.24 + harmonic * 0.25 + electric * 0.20 + transient * 0.10);
    CGFloat distortedGuitar = ASBClamp01(features.distortionConfidence * 0.46 + high * 0.22 + flatness * 0.18 + harmonic * 0.16 + noise * 0.12);
    CGFloat pluckGrain = ASBClamp01(transient * 0.48 + high * 0.18 + features.harmonicPeakRatio * 0.22 + features.spectralFlux * 0.12);
    CGFloat soundWall = ASBClamp01(harmonic * 0.36 + noise * 0.24 + energy * 0.24 + features.distortionConfidence * 0.18 - transient * 0.10);
    return @{
        @"beat": @(beat),
        @"kick": @(kick),
        @"subBass": @(low),
        @"bassline": @(bassline),
        @"snareClap": @(snareClap),
        @"hihat": @(hihat),
        @"lead": @(lead),
        @"pad": @(pad),
        @"pluck": @(pluck),
        @"riser": @(riser),
        @"drop": @(drop),
        @"transient": @(transient),
        @"harmonic": @(harmonic),
        @"percussive": @(percussive),
        @"noise": @(noise),
        @"flatness": @(flatness),
        @"electric": @(electric),
        @"chopped": @(chopped),
        @"sidechain": @(sidechain),
        @"electricBassLine": @(electricBassLine),
        @"electricGuitarTexture": @(electricGuitarTexture),
        @"distortedGuitar": @(distortedGuitar),
        @"pluckGrain": @(pluckGrain),
        @"soundWall": @(soundWall)
    };
}

static NSDictionary *ASBInstrumentTruthConfig(void) {
    static NSDictionary *config = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        NSString *path = [[NSBundle mainBundle] pathForResource:@"InstrumentTruthConfig" ofType:@"json"];
        if (!path) {
            config = @{};
            return;
        }

        NSData *data = [NSData dataWithContentsOfFile:path];
        if (!data) {
            config = @{};
            return;
        }

        NSError *error = nil;
        id object = [NSJSONSerialization JSONObjectWithData:data options:0 error:&error];
        config = [object isKindOfClass:[NSDictionary class]] ? object : @{};
        if (error) {
            NSLog(@"⚠️ InstrumentTruthConfig 解析失败: %@", error.localizedDescription);
        }
    });
    return config;
}

static NSString *ASBInstrumentTruthLabelID(NSString *featureKey) {
    static NSDictionary<NSString *, NSString *> *mapping = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        mapping = @{
            @"electricBassLine": @"electric_bass_line",
            @"electricGuitarTexture": @"electric_guitar_texture",
            @"distortedGuitar": @"distorted_guitar",
            @"pluckGrain": @"pluck_grain",
            @"soundWall": @"sound_wall"
        };
    });
    return mapping[featureKey];
}

static NSString *ASBInstrumentTruthDatasetName(NSString *datasetID) {
    static NSDictionary<NSString *, NSString *> *names = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        names = @{
            @"moisesdb": @"Moises",
            @"musdb18": @"MUSDB",
            @"slakh2100": @"Slakh"
        };
    });
    return names[datasetID] ?: datasetID;
}

static NSString *ASBInstrumentTruthSourceBadge(NSDictionary *labelConfig) {
    NSArray *priority = labelConfig[@"truth_priority"];
    if (![priority isKindOfClass:[NSArray class]]) return nil;

    NSMutableArray<NSString *> *datasetNames = [NSMutableArray array];
    for (NSDictionary *entry in priority) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSString *datasetID = entry[@"dataset"];
        if (![datasetID isKindOfClass:[NSString class]]) continue;
        NSString *name = ASBInstrumentTruthDatasetName(datasetID);
        if (![datasetNames containsObject:name]) {
            [datasetNames addObject:name];
        }
    }
    return datasetNames.count > 0 ? [datasetNames componentsJoinedByString:@"/"] : nil;
}

static NSString *ASBMusicFeatureDisplayName(NSString *featureKey, NSString *fallbackName) {
    NSString *truthID = ASBInstrumentTruthLabelID(featureKey);
    if (!truthID) return fallbackName;

    NSDictionary *labels = ASBInstrumentTruthConfig()[@"labels"];
    NSDictionary *labelConfig = [labels isKindOfClass:[NSDictionary class]] ? labels[truthID] : nil;
    if (![labelConfig isKindOfClass:[NSDictionary class]]) return fallbackName;

    NSString *displayName = labelConfig[@"display_name_zh"];
    if (![displayName isKindOfClass:[NSString class]] || displayName.length == 0) {
        displayName = fallbackName;
    }

    NSString *badge = ASBInstrumentTruthSourceBadge(labelConfig);
    return badge.length > 0 ? [NSString stringWithFormat:@"%@[%@]", displayName, badge] : displayName;
}

static UIBezierPath *ASBGuitarECGGridPath(CGRect bounds) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 1.0 || height <= 1.0) return path;

    for (NSInteger idx = 1; idx < 4; idx++) {
        CGFloat y = round((height / 4.0) * idx) + 0.5;
        [path moveToPoint:CGPointMake(0.0, y)];
        [path addLineToPoint:CGPointMake(width, y)];
    }
    for (NSInteger idx = 1; idx < 8; idx++) {
        CGFloat x = round((width / 8.0) * idx) + 0.5;
        [path moveToPoint:CGPointMake(x, 0.0)];
        [path addLineToPoint:CGPointMake(x, height)];
    }
    return path;
}

static UIBezierPath *ASBFlatLinePath(CGRect bounds, CGFloat baselineRatio) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 1.0 || height <= 1.0) return path;

    CGFloat midY = height * baselineRatio;
    [path moveToPoint:CGPointMake(0.0, midY)];
    [path addLineToPoint:CGPointMake(width, midY)];
    return path;
}

static UIBezierPath *ASBCenteredImpactWavePath(CGRect bounds,
                                               CGFloat baselineRatio,
                                               CGFloat amplitudeScale,
                                               CGFloat strength,
                                               CGFloat progress,
                                               NSInteger phaseOffset) {
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat width = CGRectGetWidth(bounds);
    CGFloat height = CGRectGetHeight(bounds);
    if (width <= 1.0 || height <= 1.0) return path;

    CGFloat midY = height * baselineRatio;
    CGFloat usableHeight = height * amplitudeScale * ASBClamp01(strength);
    NSInteger count = 29;
    NSInteger centerIndex = (count - 1) / 2;
    CGFloat clampedProgress = ASBClamp01(progress);

    CGFloat center = 0.5;

    for (NSInteger idx = 0; idx < count; idx++) {
        CGFloat t = (CGFloat)idx / (CGFloat)(count - 1);
        CGFloat shape = 0.0;
        NSInteger pointOffset = labs((int)idx - (int)centerIndex);
        CGFloat normalizedDistance = centerIndex > 0 ? (CGFloat)pointOffset / (CGFloat)centerIndex : 0.0;
        CGFloat delay = normalizedDistance * 0.56;
        CGFloat local = (clampedProgress - delay) / 0.34;
        if (local > 0.0 && local < 1.45) {
            CGFloat mainPhase = sin(MIN(local, 1.0) * M_PI);
            CGFloat tail = local <= 1.0 ? 1.0 : exp(-(local - 1.0) * 7.5);
            CGFloat envelope = mainPhase * tail;
            CGFloat spatial = 1.0 - normalizedDistance * 0.34;
            CGFloat toothSign = ((pointOffset + phaseOffset) % 2 == 0) ? 1.0 : -1.0;
            CGFloat centerEase = pointOffset == 0 ? 0.68 : 1.0;
            CGFloat taper = 0.86 + (1.0 - normalizedDistance) * 0.14;
            shape = toothSign * envelope * spatial * centerEase * taper;
        }
        CGFloat y = midY - shape * usableHeight;
        y = MIN(height - 4.0, MAX(4.0, y));
        CGPoint point = CGPointMake(t * width, y);
        if (idx == 0) {
            [path moveToPoint:point];
        } else {
            [path addLineToPoint:point];
        }
    }
    return path;
}

static void ASBRunImpactAnimation(CAShapeLayer *layer,
                                  CGRect bounds,
                                  CGFloat baselineRatio,
                                  CGFloat amplitudeScale,
                                  CGFloat strength,
                                  NSInteger phaseOffset,
                                  CFTimeInterval duration,
                                  NSString *animationKey,
                                  CGFloat baseOpacity,
                                  CGFloat opacityBoost,
                                  CGFloat baseLineWidth,
                                  CGFloat lineWidthBoost) {
    UIBezierPath *flatPath = ASBFlatLinePath(bounds, baselineRatio);
    NSArray<NSNumber *> *keyTimes = @[@0.0, @0.12, @0.24, @0.38, @0.56, @0.78, @1.0];
    NSArray<NSNumber *> *progresses = @[@0.0, @0.16, @0.30, @0.48, @0.67, @0.84, @1.0];
    NSMutableArray *paths = [NSMutableArray arrayWithCapacity:progresses.count];
    for (NSNumber *progress in progresses) {
        CGFloat p = progress.doubleValue;
        UIBezierPath *path = p <= 0.001 || p >= 0.999
            ? flatPath
            : ASBCenteredImpactWavePath(bounds, baselineRatio, amplitudeScale, strength, p, phaseOffset);
        [paths addObject:(__bridge id)path.CGPath];
    }

    CGFloat clampedStrength = ASBClamp01(strength);
    CAKeyframeAnimation *pathAnimation = [CAKeyframeAnimation animationWithKeyPath:@"path"];
    pathAnimation.values = paths;
    pathAnimation.keyTimes = keyTimes;

    CAKeyframeAnimation *opacityAnimation = [CAKeyframeAnimation animationWithKeyPath:@"opacity"];
    opacityAnimation.values = @[
        @(baseOpacity),
        @(baseOpacity + opacityBoost * 0.68 * clampedStrength),
        @(baseOpacity + opacityBoost * 0.92 * clampedStrength),
        @(baseOpacity + opacityBoost * 1.00 * clampedStrength),
        @(baseOpacity + opacityBoost * 0.74 * clampedStrength),
        @(baseOpacity + opacityBoost * 0.34 * clampedStrength),
        @(baseOpacity)
    ];
    opacityAnimation.keyTimes = keyTimes;

    CAKeyframeAnimation *lineWidthAnimation = [CAKeyframeAnimation animationWithKeyPath:@"lineWidth"];
    lineWidthAnimation.values = @[
        @(baseLineWidth),
        @(baseLineWidth + lineWidthBoost * 0.60 * clampedStrength),
        @(baseLineWidth + lineWidthBoost * 0.94 * clampedStrength),
        @(baseLineWidth + lineWidthBoost * 1.00 * clampedStrength),
        @(baseLineWidth + lineWidthBoost * 0.66 * clampedStrength),
        @(baseLineWidth + lineWidthBoost * 0.26 * clampedStrength),
        @(baseLineWidth)
    ];
    lineWidthAnimation.keyTimes = keyTimes;

    CAAnimationGroup *group = [CAAnimationGroup animation];
    group.animations = @[pathAnimation, opacityAnimation, lineWidthAnimation];
    group.duration = duration;
    group.removedOnCompletion = YES;
    group.fillMode = kCAFillModeRemoved;
    group.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionEaseOut];

    [layer removeAnimationForKey:animationKey];
    layer.path = flatPath.CGPath;
    layer.opacity = baseOpacity;
    layer.lineWidth = baseLineWidth;
    [layer addAnimation:group forKey:animationKey];
}

@implementation ViewController (Playback)

- (NSDictionary<NSString *, NSNumber *> *)guitarVisualControlForCurrentPlayback {
    NSTimeInterval playbackTime = self.player.currentTime;
    NSDictionary *analysis = self.player.lastYAMNetAnalysis;
    MusicItem *item = !self.isPlatformQueueActive && self.currentIndex >= 0 && self.currentIndex < (NSInteger)self.displayedMusicItems.count ?
                      self.displayedMusicItems[self.currentIndex] : nil;
    BOOL vectorAssaultSelected = self.visualEffectManager.currentEffectType == VisualEffectTypeVectorAssault;
    BOOL useAvailableStemCurves = self.guitarDemucsOnDeviceExperimentEnabled || vectorAssaultSelected;
    NSDictionary *phoneDemucsControl = useAvailableStemCurves ?
        ASBPhoneDemucsVisualControl(item, self.player.duration, playbackTime,
                                    self.player.lastHTDemucsStemAnalysis) : nil;
    NSDictionary *demucsControl = self.guitarDemucsExperimentEnabled ?
        ASBMingZiDemucsVisualControl(item, self.player.duration, playbackTime) : nil;
    NSMutableDictionary<NSString *, NSNumber *> *control = [(phoneDemucsControl ?: (self.guitarDemucsOnDeviceExperimentEnabled ?
        ASBGuitarVisualControl(playbackTime, analysis) : (demucsControl ?: ASBGuitarVisualControl(playbackTime, analysis))) ?: @{}) mutableCopy];
    [control addEntriesFromDictionary:ASBYAMNetVocalControl(analysis, playbackTime)];
    // Renderer dictionaries merge; clear stems that the current song has not supplied.
    for (NSString *stem in @[@"piano", @"drums", @"other"]) {
        NSString *enabledKey = [stem stringByAppendingString:@"StemControlEnabled"];
        NSString *levelKey = [stem stringByAppendingString:@"StemControl"];
        if (!control[enabledKey]) {
            control[enabledKey] = @NO;
            control[levelKey] = @0.0f;
        }
    }
    control[@"songPlaybackTime"] = @(playbackTime);
    control[@"songIsPlaying"] = @(self.player.isPlaying || self.isPlatformQueueActive);
    control[@"songDuration"] = @(self.player.duration);
    NSString *platformTrackID = [self.currentPlatformTrackInfo[@"trackID"] isKindOfClass:NSString.class] ? self.currentPlatformTrackInfo[@"trackID"] : nil;
    NSString *platformName = [self.currentPlatformTrackInfo[@"title"] isKindOfClass:NSString.class] ? self.currentPlatformTrackInfo[@"title"] : nil;
    NSString *songKey = self.isPlatformQueueActive ? (platformTrackID ?: platformName ?: @"platform-track") : (item.fileName.length > 0 ? item.fileName : (item.displayName ?: @""));
    control[@"songIdentity"] = @((NSUInteger)(songKey.length > 0 ? songKey.hash : (NSUInteger)self.currentIndex + 1));
    BOOL usingDemucs = phoneDemucsControl != nil || (!self.guitarDemucsOnDeviceExperimentEnabled && demucsControl != nil);
    BOOL hiveSelected = self.visualEffectManager.currentEffectType == VisualEffectTypeCellularWormhole;
    BOOL hasYAMNetTimeline = analysis[@"patches"] != nil;
    BOOL hasGuitarTimeline = usingDemucs || hasYAMNetTimeline;
    BOOL targetStemEffectSelected = hiveSelected ||
        self.visualEffectManager.currentEffectType == VisualEffectTypeGlassResonance ||
        self.visualEffectManager.currentEffectType == VisualEffectTypeMirrorStrata;
    BOOL active = hiveSelected && hasGuitarTimeline &&
                  [control[@"guitarStemControl"] floatValue] > 0.12f;
    if (active != self.dedicatedGuitarVisualActive) {
        self.dedicatedGuitarVisualActive = active;
        if (active) {
            if (phoneDemucsControl) {
                NSLog(@"[GuitarVisual] 深空蜂巢 Phone Demucs 吉他触发开始: control=%.3f, playback=%.2fs",
                      [control[@"guitarStemControl"] floatValue], playbackTime);
            } else {
                NSLog(@"[GuitarVisual] 深空蜂巢 %@ 吉他触发开始: electric=%.4f guitar=%.4f control=%.3f, playback=%.2fs",
                      usingDemucs ? @"Demucs" : @"YAMNet",
                      [control[@"guitarYAMNetElectricScore"] floatValue],
                      [control[@"guitarYAMNetGenericScore"] floatValue],
                      [control[@"guitarStemControl"] floatValue], playbackTime);
            }
        } else if (hiveSelected) {
            NSLog(@"[GuitarVisual] 深空蜂巢 %@ 吉他触发结束; playback=%.2fs",
                  usingDemucs ? (phoneDemucsControl ? @"Phone Demucs" : @"Demucs") : @"YAMNet", playbackTime);
        }
    }
    NSInteger playbackLogBucket = (NSInteger)floor(playbackTime / 2.0);
    if (targetStemEffectSelected && playbackLogBucket != self.separatedStemLastLogBucket) {
        self.separatedStemLastLogBucket = playbackLogBucket;
        NSInteger playbackSecond = (NSInteger)floor(playbackTime);
        NSString *effectName = hiveSelected ? @"深空蜂巢" :
            (self.visualEffectManager.currentEffectType == VisualEffectTypeGlassResonance ? @"玻璃回旋" : @"镜层回廊");
        NSString *source = phoneDemucsControl ? @"PhoneDemucs" :
            (usingDemucs ? @"DesktopDemucs" : (hasYAMNetTimeline ? @"YAMNet(fallback)" : @"pending"));
        NSDictionary *stemAnalysis = self.player.lastHTDemucsStemAnalysis;
        NSDictionary *stems = [stemAnalysis[@"stems"] isKindOfClass:NSDictionary.class] ? stemAnalysis[@"stems"] : @{};
        NSDictionary *guitarEntry = [stems[@"guitar"] isKindOfClass:NSDictionary.class] ? stems[@"guitar"] : @{};
        NSDictionary *pianoEntry = [stems[@"piano"] isKindOfClass:NSDictionary.class] ? stems[@"piano"] : @{};
        NSDictionary *drumsEntry = [stems[@"drums"] isKindOfClass:NSDictionary.class] ? stems[@"drums"] : @{};
        NSUInteger guitarFrames = [guitarEntry[@"frames"] isKindOfClass:NSArray.class] ? [guitarEntry[@"frames"] count] : 0;
        NSUInteger pianoFrames = [pianoEntry[@"frames"] isKindOfClass:NSArray.class] ? [pianoEntry[@"frames"] count] : 0;
        NSUInteger drumsFrames = [drumsEntry[@"frames"] isKindOfClass:NSArray.class] ? [drumsEntry[@"frames"] count] : 0;
        NSLog(@"[StemVisual] effect=%@ source=%@ time=%02ld:%02ld guitar=%.3f piano=%.3f drums=%.3f phoneDemucsEnabled=%@ cachedFrames(g=%lu,p=%lu,d=%lu) duration=%.2f analysisDuration=%.2f",
              effectName, source, (long)(playbackSecond / 60), (long)(playbackSecond % 60),
              [control[@"guitarStemControl"] floatValue], [control[@"pianoStemControl"] floatValue],
              [control[@"drumsStemControl"] floatValue], self.guitarDemucsOnDeviceExperimentEnabled ? @"YES" : @"NO",
              (unsigned long)guitarFrames, (unsigned long)pianoFrames, (unsigned long)drumsFrames,
              self.player.duration, [stemAnalysis[@"duration_sec"] doubleValue]);
    }
    if (hiveSelected && hasGuitarTimeline && playbackLogBucket != self.dedicatedGuitarLastScoreLogSecond) {
        self.dedicatedGuitarLastScoreLogSecond = playbackLogBucket;
        NSInteger playbackSecond = (NSInteger)floor(playbackTime);
        if (phoneDemucsControl) {
            NSLog(@"[DemucsStems] time=%02ld:%02ld guitar=%.3f piano=%.3f drums=%.3f",
                  (long)(playbackSecond / 60), (long)(playbackSecond % 60),
                  [control[@"guitarStemControl"] floatValue],
                  [control[@"pianoStemControl"] floatValue],
                  [control[@"drumsStemControl"] floatValue]);
        } else if (usingDemucs) {
            NSLog(@"[GuitarVisual] Desktop Demucs full-song check: time=%02ld:%02ld control=%.3f triggerThreshold=0.12",
                  (long)(playbackSecond / 60), (long)(playbackSecond % 60),
                  [control[@"guitarStemControl"] floatValue]);
        } else {
            NSLog(@"[GuitarVisual] YAMNet guitar check: time=%02ld:%02ld electric=%.4f guitar=%.4f max=%.4f control=%.3f triggerThreshold=0.12",
                  (long)(playbackSecond / 60), (long)(playbackSecond % 60),
                  [control[@"guitarYAMNetElectricScore"] floatValue],
                  [control[@"guitarYAMNetGenericScore"] floatValue],
                  [control[@"guitarYAMNetScore"] floatValue],
                  [control[@"guitarStemControl"] floatValue]);
        }
    } else if (hiveSelected && !hasGuitarTimeline && playbackTime >= 174.0 && playbackTime < 210.0 &&
               playbackLogBucket != self.dedicatedGuitarLastScoreLogSecond) {
        self.dedicatedGuitarLastScoreLogSecond = playbackLogBucket;
        NSLog(@"[GuitarVisual] guitar analysis 尚未就绪: time=%.2fs", playbackTime);
    }
    if (!hiveSelected) self.dedicatedGuitarVisualActive = NO;
    return control;
}

- (void)ensureMusicFeatureScopeGuitarECGInOverlay:(UIView *)overlay {
    if (self.musicFeatureScopeGuitarECGView.superview == overlay) return;

    if (!self.musicFeatureScopeGuitarECGView) {
        UIView *graphView = [[UIView alloc] initWithFrame:CGRectZero];
        graphView.userInteractionEnabled = NO;
        graphView.backgroundColor = [UIColor colorWithWhite:0.02 alpha:0.18];
        graphView.layer.cornerRadius = 6.0;
        graphView.layer.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        graphView.layer.borderColor = [UIColor colorWithRed:1.0 green:0.78 blue:0.32 alpha:0.28].CGColor;
        graphView.clipsToBounds = YES;

        CAShapeLayer *gridLayer = [CAShapeLayer layer];
        gridLayer.fillColor = UIColor.clearColor.CGColor;
        gridLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.72 blue:0.24 alpha:0.14].CGColor;
        gridLayer.lineWidth = 0.8;
        [graphView.layer addSublayer:gridLayer];

        CAShapeLayer *waveLayer = [CAShapeLayer layer];
        waveLayer.fillColor = UIColor.clearColor.CGColor;
        waveLayer.strokeColor = [UIColor colorWithRed:1.0 green:0.82 blue:0.34 alpha:0.96].CGColor;
        waveLayer.lineWidth = 1.8;
        waveLayer.lineCap = kCALineCapButt;
        waveLayer.lineJoin = kCALineJoinMiter;
        waveLayer.shadowColor = [UIColor colorWithRed:1.0 green:0.64 blue:0.20 alpha:1.0].CGColor;
        waveLayer.shadowOpacity = 0.72;
        waveLayer.shadowRadius = 7.0;
        waveLayer.shadowOffset = CGSizeZero;
        [graphView.layer addSublayer:waveLayer];

        CAShapeLayer *bassLayer = [CAShapeLayer layer];
        bassLayer.fillColor = UIColor.clearColor.CGColor;
        bassLayer.strokeColor = [UIColor colorWithRed:0.54 green:0.96 blue:0.62 alpha:0.90].CGColor;
        bassLayer.lineWidth = 1.5;
        bassLayer.lineCap = kCALineCapButt;
        bassLayer.lineJoin = kCALineJoinMiter;
        bassLayer.shadowColor = [UIColor colorWithRed:0.24 green:0.92 blue:0.46 alpha:1.0].CGColor;
        bassLayer.shadowOpacity = 0.48;
        bassLayer.shadowRadius = 5.0;
        bassLayer.shadowOffset = CGSizeZero;
        [graphView.layer addSublayer:bassLayer];

        UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
        label.textColor = [UIColor colorWithRed:1.0 green:0.84 blue:0.42 alpha:0.94];
        label.font = [UIFont monospacedSystemFontOfSize:10.5 weight:UIFontWeightBold];
        label.adjustsFontSizeToFitWidth = YES;
        label.minimumScaleFactor = 0.72;
        [graphView addSubview:label];

        self.musicFeatureScopeGuitarECGView = graphView;
        self.musicFeatureScopeGuitarECGGridLayer = gridLayer;
        self.musicFeatureScopeGuitarECGLayer = waveLayer;
        self.musicFeatureScopeBassECGLayer = bassLayer;
        self.musicFeatureScopeGuitarECGLabel = label;
    } else {
        [self.musicFeatureScopeGuitarECGView removeFromSuperview];
    }

    [overlay addSubview:self.musicFeatureScopeGuitarECGView];
}

- (void)updateMusicFeatureScopeGuitarECGWithValue:(CGFloat)value
                                        bassValue:(CGFloat)bassValue
                                        transient:(CGFloat)transient
                                            frame:(CGRect)frame {
    if (!self.musicFeatureScopeGuitarECGView) return;

    self.musicFeatureScopeGuitarECGView.frame = frame;
    CGRect bounds = self.musicFeatureScopeGuitarECGView.bounds;
    self.musicFeatureScopeGuitarECGLabel.frame = CGRectMake(10.0, 5.0, CGRectGetWidth(bounds) - 20.0, 16.0);
    self.musicFeatureScopeGuitarECGLabel.text = [NSString stringWithFormat:@"moises %.2f  slakh %.2f", value, bassValue];

    self.musicFeatureScopeGuitarECGGridLayer.frame = bounds;
    self.musicFeatureScopeGuitarECGLayer.frame = bounds;
    self.musicFeatureScopeBassECGLayer.frame = bounds;
    self.musicFeatureScopeGuitarECGGridLayer.path = ASBGuitarECGGridPath(bounds).CGPath;

    (void)transient;
    CGFloat guitarRaw = ASBClamp01(value);
    CGFloat bassRaw = ASBClamp01(bassValue);
    CGFloat triggerThreshold = 0.38;
    CFTimeInterval now = CACurrentMediaTime();
    BOOL guitarActive = guitarRaw > triggerThreshold;
    BOOL bassActive = bassRaw > triggerThreshold;

    UIBezierPath *guitarFlatPath = ASBFlatLinePath(bounds, 0.38);
    UIBezierPath *bassFlatPath = ASBFlatLinePath(bounds, 0.72);

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.musicFeatureScopeGuitarECGLayer.path = guitarFlatPath.CGPath;
    self.musicFeatureScopeGuitarECGLayer.opacity = 0.28;
    self.musicFeatureScopeGuitarECGLayer.lineWidth = 1.0;
    self.musicFeatureScopeBassECGLayer.path = bassFlatPath.CGPath;
    self.musicFeatureScopeBassECGLayer.opacity = 0.24;
    self.musicFeatureScopeBassECGLayer.lineWidth = 0.95;
    [CATransaction commit];

    if (guitarActive) {
        if (now >= self.musicFeatureScopeGuitarImpactCooldownUntil) {
            CFTimeInterval guitarPulseDuration = 0.42;
            self.musicFeatureScopeGuitarImpactCooldownUntil = now + guitarPulseDuration;
            CGFloat strength = 0.72 + ASBClamp01((guitarRaw - triggerThreshold) / (1.0 - triggerThreshold)) * 0.28;
            ASBRunImpactAnimation(self.musicFeatureScopeGuitarECGLayer,
                                  bounds,
                                  0.38,
                                  0.50,
                                  strength,
                                  0,
                                  guitarPulseDuration,
                                  @"guitarImpact",
                                  0.28,
                                  0.62,
                                  1.0,
                                  1.55);
        }
    } else {
        [self.musicFeatureScopeGuitarECGLayer removeAnimationForKey:@"guitarImpact"];
        self.musicFeatureScopeGuitarImpactCooldownUntil = 0.0;
    }

    if (bassActive) {
        if (now >= self.musicFeatureScopeBassImpactCooldownUntil) {
            CFTimeInterval bassPulseDuration = 0.46;
            self.musicFeatureScopeBassImpactCooldownUntil = now + bassPulseDuration;
            CGFloat strength = 0.70 + ASBClamp01((bassRaw - triggerThreshold) / (1.0 - triggerThreshold)) * 0.30;
            ASBRunImpactAnimation(self.musicFeatureScopeBassECGLayer,
                                  bounds,
                                  0.72,
                                  0.46,
                                  strength,
                                  1,
                                  bassPulseDuration,
                                  @"bassImpact",
                                  0.24,
                                  0.58,
                                  0.95,
                                  1.38);
        }
    } else {
        [self.musicFeatureScopeBassECGLayer removeAnimationForKey:@"bassImpact"];
        self.musicFeatureScopeBassImpactCooldownUntil = 0.0;
    }
}

- (void)updateAudioActivityMeterOverlayWithFeatures:(AudioFeatures *)features {
    BOOL shouldShow = self.visualEffectManager.currentEffectType == VisualEffectTypeAudioActivityMeter && features != nil;
    if (!shouldShow) {
        self.audioActivityMeterOverlayView.hidden = YES;
        return;
    }

    UIView *container = self.visualEffectManager.effectContainerView ?: self.view;
    if (!self.audioActivityMeterOverlayView) {
        UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
        overlay.userInteractionEnabled = NO;
        overlay.backgroundColor = [UIColor clearColor];
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        NSArray<NSString *> *names = @[
            @"低频", @"鼓点瞬态", @"旋律谐波", @"空气噪声",
            @"高音", @"电流撕裂", @"切碎门控", @"扫频",
            @"左右移动", @"回声空间", @"侧链呼吸", @"整体能量"
        ];
        for (NSString *name in names) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.textColor = [UIColor colorWithWhite:0.94 alpha:0.95];
            label.font = [UIFont monospacedSystemFontOfSize:13.0 weight:UIFontWeightSemibold];
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.72;
            label.text = name;
            [overlay addSubview:label];
            [labels addObject:label];
        }
        self.audioActivityMeterOverlayView = overlay;
        self.audioActivityMeterLabels = labels;
        [container addSubview:overlay];
    } else if (self.audioActivityMeterOverlayView.superview != container) {
        [self.audioActivityMeterOverlayView removeFromSuperview];
        [container addSubview:self.audioActivityMeterOverlayView];
    }

    self.audioActivityMeterOverlayView.hidden = NO;
    [container bringSubviewToFront:self.audioActivityMeterOverlayView];

    CGFloat width = MAX(260.0, MIN(container.bounds.size.width - 36.0, 390.0));
    CGFloat height = 420.0;
    CGFloat x = (container.bounds.size.width - width) * 0.5;
    CGFloat y = MAX(86.0, (container.bounds.size.height - height) * 0.5);
    self.audioActivityMeterOverlayView.frame = CGRectMake(x, y, width, height);

    NSDictionary<NSString *, NSNumber *> *values = ASBActivityMeterParameters(features);
    NSArray<NSString *> *keys = @[
        @"activityLow", @"activityTransient", @"activityHarmonic", @"activityNoise",
        @"activityHigh", @"activityElectric", @"activityChopped", @"activitySweep",
        @"activityPan", @"activityEcho", @"activitySidechain", @"activityEnergy"
    ];
    NSArray<NSString *> *names = @[
        @"低频", @"鼓点瞬态", @"旋律谐波", @"空气噪声",
        @"高音", @"电流撕裂", @"切碎门控", @"扫频",
        @"左右移动", @"回声空间", @"侧链呼吸", @"整体能量"
    ];
    CGFloat rowTop = 44.0;
    CGFloat rowH = 24.0;
    CGFloat rowGap = 9.5;
    for (NSInteger idx = 0; idx < self.audioActivityMeterLabels.count; idx++) {
        UILabel *label = self.audioActivityMeterLabels[idx];
        CGFloat value = ASBClamp01(values[keys[idx]].doubleValue);
        label.frame = CGRectMake(18.0, rowTop + idx * (rowH + rowGap), width - 36.0, rowH);
        label.text = [NSString stringWithFormat:@"%@  %@  %.2f", names[idx], ASBActivityMeterBar(value), value];
        label.alpha = 0.42 + value * 0.58;
    }
}

- (void)updateMusicFeatureScopeOverlayWithFeatures:(AudioFeatures *)features {
    BOOL shouldShow = self.visualEffectManager.currentEffectType == VisualEffectTypeMusicFeatureScope && features != nil;
    if (!shouldShow) {
        self.musicFeatureScopeOverlayView.hidden = YES;
        self.musicFeatureScopeGuitarECGView.hidden = YES;
        [self.musicFeatureScopeGuitarECGLayer removeAllAnimations];
        [self.musicFeatureScopeBassECGLayer removeAllAnimations];
        self.musicFeatureScopeGuitarImpactCooldownUntil = 0.0;
        self.musicFeatureScopeBassImpactCooldownUntil = 0.0;
        return;
    }

    UIView *container = self.visualEffectManager.effectContainerView ?: self.view;
    if (!self.musicFeatureScopeOverlayView) {
        UIView *overlay = [[UIView alloc] initWithFrame:CGRectZero];
        overlay.userInteractionEnabled = NO;
        overlay.backgroundColor = [UIColor clearColor];
        NSMutableArray<UILabel *> *labels = [NSMutableArray array];
        for (NSInteger idx = 0; idx < 24; idx++) {
            UILabel *label = [[UILabel alloc] initWithFrame:CGRectZero];
            label.textColor = [UIColor colorWithWhite:0.96 alpha:0.96];
            label.font = [UIFont monospacedSystemFontOfSize:11.2 weight:UIFontWeightSemibold];
            label.adjustsFontSizeToFitWidth = YES;
            label.minimumScaleFactor = 0.62;
            [overlay addSubview:label];
            [labels addObject:label];
        }
        self.musicFeatureScopeOverlayView = overlay;
        self.musicFeatureScopeLabels = labels;
        [self ensureMusicFeatureScopeGuitarECGInOverlay:overlay];
        [container addSubview:overlay];
    } else if (self.musicFeatureScopeOverlayView.superview != container) {
        [self.musicFeatureScopeOverlayView removeFromSuperview];
        [container addSubview:self.musicFeatureScopeOverlayView];
    }
    [self ensureMusicFeatureScopeGuitarECGInOverlay:self.musicFeatureScopeOverlayView];

    self.musicFeatureScopeOverlayView.hidden = NO;
    self.musicFeatureScopeGuitarECGView.hidden = NO;
    [container bringSubviewToFront:self.musicFeatureScopeOverlayView];

    CGFloat width = MAX(300.0, MIN(container.bounds.size.width - 24.0, 560.0));
    CGFloat height = MIN(container.bounds.size.height - 92.0, 520.0);
    CGFloat x = (container.bounds.size.width - width) * 0.5;
    CGFloat y = MAX(56.0, (container.bounds.size.height - height) * 0.5);
    self.musicFeatureScopeOverlayView.frame = CGRectMake(x, y, width, height);

    NSDictionary<NSString *, NSNumber *> *values = ASBMusicFeatureScopeValues(features);
    CGFloat guitarECGValue = ASBClamp01(values[@"electricGuitarTexture"].doubleValue);
    CGFloat bassECGValue = ASBClamp01(values[@"electricBassLine"].doubleValue);
    CGFloat guitarECGTransient = ASBClamp01(values[@"transient"].doubleValue);
    NSArray<NSString *> *keys = @[
        @"beat", @"kick", @"subBass", @"bassline", @"snareClap", @"hihat", @"lead", @"pad",
        @"pluck", @"riser", @"drop", @"transient", @"harmonic", @"percussive", @"noise", @"flatness",
        @"electric", @"chopped", @"sidechain", @"electricBassLine", @"electricGuitarTexture",
        @"distortedGuitar", @"pluckGrain", @"soundWall"
    ];
    NSArray<NSString *> *names = @[
        @"拍点 Beat", @"大鼓 Kick", @"重低音 Sub", @"低音线 Bassline",
        @"啪声 Snare", @"碎亮 Hi-hat", @"主旋律 Lead", @"铺底 Pad",
        @"短拨 Pluck", @"上升 Riser", @"爆开 Drop", @"声音头 Transient",
        @"有调 Harmonic", @"敲击 Perc", @"空气 Noise", @"沙散 Flatness",
        @"电流撕裂", @"切碎门控", @"一吸一放", @"斯线",
        @"纹理", @"失真", @"拨弦", @"持续音墙"
    ];

    NSInteger count = MIN(self.musicFeatureScopeLabels.count, keys.count);
    NSInteger leftCount = (count + 1) / 2;
    CGFloat gutter = 16.0;
    CGFloat columnWidth = (width - gutter) * 0.5;
    CGFloat ecgHeight = MIN(86.0, MAX(58.0, height * 0.16));
    CGFloat labelAreaHeight = MAX(240.0, height - ecgHeight - 18.0);
    CGFloat rowH = MIN(20.0, MAX(14.0, labelAreaHeight / 13.0 - 4.0));
    CGFloat rowGap = 4.0;
    for (NSInteger idx = 0; idx < count; idx++) {
        UILabel *label = self.musicFeatureScopeLabels[idx];
        BOOL rightColumn = idx >= leftCount;
        NSInteger row = rightColumn ? idx - leftCount : idx;
        CGFloat value = ASBClamp01(values[keys[idx]].doubleValue);
        CGFloat labelX = rightColumn ? columnWidth + gutter : 0.0;
        label.frame = CGRectMake(labelX, row * (rowH + rowGap), columnWidth, rowH);
        NSString *displayName = ASBMusicFeatureDisplayName(keys[idx], names[idx]);
        label.text = [NSString stringWithFormat:@"%@  %@  %.2f", displayName, ASBActivityMeterBar(value), value];
        label.alpha = 0.30 + value * 0.70;
        BOOL truthBacked = ASBInstrumentTruthLabelID(keys[idx]) != nil;
        if (truthBacked) {
            label.textColor = value > 0.66 ? [UIColor colorWithRed:1.0 green:0.86 blue:0.46 alpha:0.98] : [UIColor colorWithRed:0.98 green:0.78 blue:0.36 alpha:0.92];
        } else {
            label.textColor = value > 0.66 ? [UIColor colorWithRed:0.80 green:1.0 blue:0.62 alpha:0.98] : [UIColor colorWithWhite:0.96 alpha:0.90];
        }
    }

    CGFloat ecgY = MIN(height - ecgHeight, leftCount * (rowH + rowGap) + 10.0);
    CGRect ecgFrame = CGRectMake(0.0, ecgY, width, ecgHeight);
    [self updateMusicFeatureScopeGuitarECGWithValue:guitarECGValue
                                          bassValue:bassECGValue
                                          transient:guitarECGTransient
                                              frame:ecgFrame];
}

#pragma mark - App Lifecycle

- (void)hadEnterBackGround {
    NSLog(@"🔄 进入后台，停止所有GPU渲染...");
    self.isInBackground = YES;
    if (self.isBackgroundMediaEffectActive) {
        [self.backgroundVideoPlayer pause];
        self.backgroundVideoLayer.hidden = NO;
    }
    [self.animationCoordinator applicationDidEnterBackground];

    [self.visualEffectManager pauseRendering];

    if (self.visualEffectManager.metalView) {
        self.visualEffectManager.metalView.paused = YES;
        self.visualEffectManager.metalView.delegate = nil;
        NSLog(@"✅ Metal视图已暂停并移除delegate");
    }

    if (self.fpsDisplayLink) {
        self.fpsDisplayLink.paused = YES;
        NSLog(@"✅ FPS监控已暂停");
    }

    if (self.spectrumView) {
        [self.spectrumView pauseRendering];
        NSLog(@"✅ 频谱视图已暂停");
    }

    NSLog(@"🎵 检查播放状态: isPlaying=%@, isPaused=%@",
          self.player.isPlaying ? @"YES" : @"NO",
          self.player.isPaused ? @"YES" : @"NO");

    self.wasPlayingBeforeBackground = self.player.isPlaying;
    NSLog(@"🔖 记录后台前播放状态: %@", self.wasPlayingBeforeBackground ? @"播放中" : @"已暂停/停止");

    if (self.player && self.player.isPlaying) {
        NSLog(@"🎵 后台音乐播放: 保持音频会话激活");
        [self updateNowPlayingInfo];

        NSDictionary *nowPlaying = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
        NSLog(@"✅ 后台播放信息已更新:");
        NSLog(@"   - 标题: %@", nowPlaying[MPMediaItemPropertyTitle]);
        NSLog(@"   - 播放速率: %@", nowPlaying[MPNowPlayingInfoPropertyPlaybackRate]);
    } else if (self.player.isPaused) {
        NSLog(@"🎵 播放已暂停，进入后台（engine和session已在暂停时处理）");
    } else {
        NSLog(@"⚠️ 进入后台时没有音乐在播放");
    }

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView pauseSpinning];
        NSLog(@"✅ 黑胶唱片动画已暂停");
    }

    NSLog(@"✅ 后台处理完成，GPU渲染已完全停止");
}

- (void)hadEnterForeGround {
    NSLog(@"🔄 回到前台，恢复GPU渲染...");
    self.isInBackground = NO;
    [self.animationCoordinator applicationDidBecomeActive];

    if (self.visualEffectManager.metalView) {
        self.visualEffectManager.metalView.paused = NO;
        NSLog(@"✅ Metal视图已准备恢复");
    }

    [self.visualEffectManager resumeRendering];

    if (self.fpsDisplayLink) {
        self.fpsDisplayLink.paused = NO;
        NSLog(@"✅ FPS监控已恢复");
    }

    if (self.spectrumView) {
        [self.spectrumView resumeRendering];
        NSLog(@"✅ 频谱视图已恢复");
    }

    if (self.isShowingVinylRecord && self.player.isPlaying) {
        [self.vinylRecordView resumeSpinning];
        NSLog(@"✅ 黑胶唱片动画已恢复");
    }

    if (self.player.isPaused) {
        NSLog(@"🎵 播放器处于暂停状态，等待用户手动恢复");
    }

    self.wasPlayingBeforeBackground = NO;

    if (self.isBackgroundMediaEffectActive) {
        [self playSelectedBackgroundMediaIfNeeded];
    }

    NSLog(@"✅ 前台恢复完成，GPU渲染已重新启动");
}

- (void)karaokeModeDidStart {
    NSLog(@"🎤 收到卡拉OK模式开始通知，停止主界面音频播放");
    [self resetMVMomentAnalysisForCurrentTrack];
    [self.signatureMVClip stop];
    [self.player stop];
    [self.visualEffectManager pauseRendering];
}

- (void)karaokeModeDidEnd {
    NSLog(@"🎤 收到卡拉OK模式结束通知");
    [self.visualEffectManager resumeRendering];
    self.shouldPreventAutoResume = NO;
    NSLog(@"🎤 卡拉OK模式结束，等待用户手动播放");
}

#pragma mark - AudioSpectrumPlayerDelegate

- (void)playerDidGenerateSpectrum:(nonnull NSArray *)spectrums {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateBackground) {
            return;
        }

        [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];

        if (self.animationCoordinator.spectrumManager) {
            [self.animationCoordinator updateSpectrumAnimations:spectrums];
        }

        if (spectrums.count > 0) {
            NSArray *firstChannelData = spectrums.firstObject;
            NSArray *secondChannelData = spectrums.count > 1 ? spectrums[1] : nil;
            self.latestSpectrumData = firstChannelData;
            [self.visualEffectManager updateSpectrumData:firstChannelData];
            if (!self.player.extendedAnalysisEnabled) {
                AudioFeatureExtractor *extractor = [AudioFeatureExtractor sharedExtractor];
                [extractor processStereoSpectrumData:firstChannelData
                                       rightSpectrum:secondChannelData
                                          sampleRate:44100.0f];
                self.latestAudioFeatures = extractor.currentFeatures;
                if (self.latestAudioFeatures) {
                    NSMutableDictionary *params = [ASBActivityMeterParameters(self.latestAudioFeatures) mutableCopy];
                    params[@"subBass"] = @(self.latestAudioFeatures.subBassEnergy);
                    params[@"transient"] = @(self.latestAudioFeatures.transientStrength);
                    params[@"harmonic"] = @(self.latestAudioFeatures.harmonicStrength);
                    params[@"noise"] = @(self.latestAudioFeatures.noiseStrength);
                    [params addEntriesFromDictionary:[self guitarVisualControlForCurrentPlayback]];
                    [self.visualEffectManager setRenderParameters:params];
                }
                [self updateAudioActivityMeterOverlayWithFeatures:self.latestAudioFeatures];
                [self updateMusicFeatureScopeOverlayWithFeatures:self.latestAudioFeatures];
            }
        } else {
            self.latestSpectrumData = nil;
            self.latestAudioFeatures = nil;
            [self updateAudioActivityMeterOverlayWithFeatures:nil];
            [self updateMusicFeatureScopeOverlayWithFeatures:nil];
        }
    });
}

- (void)playerDidGenerateExtendedAnalysis:(RealtimeAnalyzerResult *)result {
    if (result.frames.count == 0) return;
    RealtimeAnalyzerFrame *first = result.frames.firstObject;
    if (!first) return;

    dispatch_async(dispatch_get_main_queue(), ^{
        AudioFeatureExtractor *extractor = [AudioFeatureExtractor sharedExtractor];
        NSArray<NSNumber *> *bands = first.bands ?: @[];
        NSArray<NSNumber *> *rightBands = nil;
        if (result.frames.count > 1) {
            RealtimeAnalyzerFrame *right = result.frames[1];
            rightBands = right.bands;
        }
        [extractor processStereoSpectrumData:bands
                               rightSpectrum:rightBands
                            categoryFeatures:first.category];
        self.latestAudioFeatures = extractor.currentFeatures;
        NSMutableDictionary *params = [ASBActivityMeterParameters(self.latestAudioFeatures) mutableCopy];
        params[@"subBass"] = @(self.latestAudioFeatures.subBassEnergy);
        params[@"transient"] = @(self.latestAudioFeatures.transientStrength);
        params[@"harmonic"] = @(self.latestAudioFeatures.harmonicStrength);
        params[@"noise"] = @(self.latestAudioFeatures.noiseStrength);
        [params addEntriesFromDictionary:[self guitarVisualControlForCurrentPlayback]];
        [self.visualEffectManager setRenderParameters:params];
        [self updateAudioActivityMeterOverlayWithFeatures:self.latestAudioFeatures];
        [self updateMusicFeatureScopeOverlayWithFeatures:self.latestAudioFeatures];
    });
}

- (void)didFinishPlay {
    if (self.shouldPreventAutoResume) {
        NSLog(@"⏹️ 播放结束，但用户在其他页面，不自动播放下一首");
        return;
    }

    if (self.isPlatformQueueActive) {
        if (self.isSingleLoopMode) {
            [[NSNotificationCenter defaultCenter] postNotificationName:@"PlatformMusicReplayCurrent" object:nil];
        } else {
            [self playNext];
        }
        return;
    }

    if (self.isSingleLoopMode) {
        NSLog(@"🔂 单曲循环：重新播放当前歌曲");
        [self playCurrentTrack];
        return;
    }

    self.currentIndex += 1;
    if (self.currentIndex >= self.displayedMusicItems.count) {
        self.currentIndex = 0;
    }

    if (self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
        [self.musicLibrary recordPlayForMusic:musicItem];
    }

    [self updateAudioSelection];
    [self playCurrentTrack];
}

- (void)playerDidLoadLyrics:(LRCParser *)parser {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (parser) {
            NSLog(@"✅ 歌词加载成功: %@ - %@", parser.artist ?: @"未知", parser.title ?: @"未知");
            NSLog(@"   歌词行数: %lu", (unsigned long)parser.lyrics.count);
            self.lyricsContainer.hidden = NO;
            self.lyricsView.parser = parser;
            [self updateVisualLyricsOverlayForCurrentIndex:0];
        } else {
            NSLog(@"⚠️ 未找到歌词");
            self.lyricsContainer.hidden = NO;
            self.lyricsView.parser = nil;
            [self updateVisualLyricsOverlayForCurrentIndex:-1];
        }
        [self refreshVisualLyricsOverlayVisibility];
        if (parser) {
            [self fetchAppleMusicArtworkForCurrentItemIfNeeded];
        }
    });
}

- (void)playerDidStartPlaying {
    NSLog(@"🎵 播放器已开始播放，更新系统媒体信息");

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.75 green:0.25 blue:0.15 alpha:0.9];
    });

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateNowPlayingInfo];
        NSLog(@"✅ 播放开始后已更新完整媒体信息");
        [self updateProgressWithDuration:self.player.duration];
    });
}

- (void)playerDidUpdateTime:(NSTimeInterval)currentTime {
    if (self.automaticVideoEnabled) {
        [self.signatureMVClip updateWithTitle:self.nowPlayingTitleLabel.text
                                        time:currentTime
                                     playing:self.player.isPlaying
                                   mvMoments:self.mvMomentCandidates ?: @[]];
    }
    [self.lyricsView updateWithTime:currentTime];
    [self updateProgressWithCurrentTime:currentTime];
    [self updateVisualLyricsOverlayForCurrentIndex:self.lyricsView.currentIndex];

    NSArray<NSNumber *> *spectrum = self.latestSpectrumData ?: @[];
    CGFloat bass = 0.0, mid = 0.0, treble = 0.0;
    NSUInteger spectrumCount = MIN(spectrum.count, (NSUInteger)80);
    for (NSUInteger i = 0; i < spectrumCount; i++) {
        CGFloat value = [spectrum[i] doubleValue];
        if (i <= 16) {
            bass += value;
        } else if (i <= 48) {
            mid += value;
        } else {
            treble += value;
        }
    }
    if (spectrumCount > 0) {
        bass /= 17.0;
        mid /= 32.0;
        treble /= 31.0;
    }
    [self animateVisualLyricsOverlayWithBass:bass mid:mid treble:treble];

    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastNowPlayingUpdateTime >= 5.0) {
        self.lastNowPlayingUpdateTime = now;

        NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
        if (nowPlayingInfo) {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(currentTime);
            if (self.player.isPlaying) {
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
            }
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
        }
    }
}

- (NSString *)videoMomentDescription:(NSDictionary *)moment {
    NSDictionary *names = @{@"kaisa_solo": @"标志性舞蹈", @"group_dance": @"标志性舞蹈", @"signature_dance": @"标志性舞蹈",
                            @"social_hotspot": @"社交热点", @"chorus": @"副歌", @"drop": @"Drop", @"climax": @"高潮",
                            @"energy_peak": @"高能高潮", @"instrument_focus": @"乐器突出"};
    NSString *status = moment[@"semanticStatus"];
    NSString *kind = [status isEqual:@"lrc_repetition"] ? @"歌词重复" : ([status isEqual:@"whole_song_spectrum"] ? @"整曲频谱" : ([status isEqual:@"model_inference"] ? @"结构推断" : @"来源描述"));
    NSString *support = [moment[@"spectrumSupport"] isEqual:@"energy"] ? @" · 高能吻合" : ([moment[@"spectrumSupport"] isEqual:@"bright"] ? @" · 高频吻合" : @"");
    return [NSString stringWithFormat:@"%@（%@%@）", names[moment[@"label"]] ?: @"候选片段", kind, support];
}

- (void)showPlaybackToast:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.font = [UIFont systemFontOfSize:14 weight:UIFontWeightMedium];
    toast.textColor = UIColor.whiteColor;
    toast.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.92];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;
    CGFloat width = 120;
    CGFloat height = 40;
    toast.frame = CGRectMake((CGRectGetWidth(self.view.bounds) - width) / 2,
                              CGRectGetHeight(self.view.bounds) - 180,
                              width,
                              height);
    toast.alpha = 0;
    [self.view addSubview:toast];
    [UIView animateWithDuration:0.25 animations:^{
        toast.alpha = 1;
    } completion:^(BOOL finished) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.25 animations:^{
                toast.alpha = 0;
            } completion:^(BOOL finished) {
                [toast removeFromSuperview];
            }];
        });
    }];
}

- (void)showMomentNotice:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:nil message:message preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (NSArray<NSDictionary<NSString *, id> *> *)momentMarkersFromMoments:(NSArray<NSDictionary *> *)moments {
    NSMutableArray *markers = [NSMutableArray array];
    for (NSDictionary *moment in moments) {
        [markers addObject:@{@"start": moment[@"start"] ?: @0, @"end": moment[@"end"] ?: @0, @"label": moment[@"label"] ?: @""}];
    }
    return markers;
}

- (void)performanceControlChooseBilibiliVideo {
    if (self.mvAudioPath.length == 0) {
        [self showMomentNotice:@"请先播放歌曲，再选择 B 站视频"];
        return;
    }
    __weak typeof(self) weakSelf = self;
    [BilibiliMVResolverBridge.sharedResolver searchVideosForSong:self.mvAudioTitle ?: @"" artist:self.mvAudioArtist ?: @"" completion:^(NSArray<NSDictionary<NSString *,NSString *> *> *rows, NSString *errorMessage) {
        typeof(self) self = weakSelf;
        if (!self) return;
        if (errorMessage.length || rows.count == 0) {
            [self showMomentNotice:errorMessage.length ? errorMessage : @"没有找到可选的 B 站视频"];
            return;
        }
        UIAlertController *list = [UIAlertController alertControllerWithTitle:@"选择 B 站视频" message:@"选中的视频会替换自动匹配结果，并按它重新对齐时间表。" preferredStyle:UIAlertControllerStyleActionSheet];
        for (NSDictionary<NSString *, NSString *> *row in rows) {
            NSString *title = row[@"title"] ?: @"未命名视频";
            NSMutableArray<NSString *> *parts = [NSMutableArray array];
            if (row[@"author"].length) [parts addObject:row[@"author"]];
            if (row[@"duration"].length) [parts addObject:row[@"duration"]];
            NSString *detail = [parts componentsJoinedByString:@" · "];
            NSString *label = detail.length ? [NSString stringWithFormat:@"%@\n%@", title, detail] : title;
            [list addAction:[UIAlertAction actionWithTitle:label style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
                [self bilibiliMVUserDidSelectVideoID:row[@"id"] title:row[@"title"]];
            }]];
        }
        [list addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        UIPopoverPresentationController *popover = list.popoverPresentationController;
        popover.sourceView = self.view;
        popover.sourceRect = CGRectMake(CGRectGetMidX(self.view.bounds), CGRectGetMidY(self.view.bounds), 1, 1);
        [self presentViewController:list animated:YES completion:nil];
    }];
}

- (void)bilibiliMVUserDidSelectVideo:(NSNotification *)notification {
    [self bilibiliMVUserDidSelectVideoID:notification.userInfo[@"bvid"] title:notification.userInfo[@"title"]];
}

- (void)bilibiliMVUserDidSelectVideoID:(NSString *)bvid title:(NSString *)videoTitle {
    if (![bvid hasPrefix:@"BV"]) return;
    if (self.mvAudioPath.length == 0) {
        [self showMomentNotice:@"请先播放歌曲，再指定 B 站视频"];
        return;
    }
    NSLog(@"[BiliMV] 手动指定当前歌曲：歌曲=%@，BV=%@，标题=%@", self.mvAudioTitle, bvid, videoTitle ?: @"");
    self.automaticVideoEnabled = YES;
    [NSUserDefaults.standardUserDefaults setBool:YES forKey:@"AutomaticVideoMatchingEnabled"];
    self.performanceControlPanel.automaticVideoEnabled = YES;
    [self resetMVMomentAnalysisForCurrentTrack];
    [self.signatureMVClip stop];
    [self beginMVTimelinePreferredVideoID:bvid videoTitle:videoTitle];
}

- (void)performanceControlShowVideoTimelineEvidence {
    UIAlertController *list = [UIAlertController alertControllerWithTitle:@"视频时间轴依据"
        message:self.mvMomentCandidates.count ? @"副歌和热点来自歌词或外部时间；高能段与乐器突出来自整曲频谱，播放时按时间表展示。这些理由都不是逐帧核实。" : @"当前没有可用时间表。首次检索在后台进行；缺少依据或对齐失败会跳过视频。"
        preferredStyle:UIAlertControllerStyleAlert];
    for (NSDictionary *moment in [self.mvMomentCandidates subarrayWithRange:NSMakeRange(0, MIN((NSUInteger)12, self.mvMomentCandidates.count))]) {
        NSString *title = [NSString stringWithFormat:@"%@–%@ %@", ASBMVTimeString([moment[@"start"] doubleValue]), ASBMVTimeString([moment[@"end"] doubleValue]), [self videoMomentDescription:moment]];
        [list addAction:[UIAlertAction actionWithTitle:title style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            NSString *message = [NSString stringWithFormat:@"歌曲 %@–%@\n视频 %@–%@\n\n原文依据：\n%@\n\n来源：%@", ASBMVTimeString([moment[@"start"] doubleValue]), ASBMVTimeString([moment[@"end"] doubleValue]), ASBMVTimeString([moment[@"videoStart"] doubleValue]), ASBMVTimeString([moment[@"videoEnd"] doubleValue]), moment[@"sourceExcerpt"] ?: @"", moment[@"sourceURL"] ?: @""];
            UIAlertController *detail = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleAlert];
            NSURL *source = [NSURL URLWithString:moment[@"sourceURL"] ?: @""];
            if ([source.scheme isEqualToString:@"https"]) {
                [detail addAction:[UIAlertAction actionWithTitle:@"打开来源" style:UIAlertActionStyleDefault handler:^(UIAlertAction *open) {
                    [UIApplication.sharedApplication openURL:source options:@{} completionHandler:nil];
                }]];
            }
            [detail addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
            [self presentViewController:detail animated:YES completion:nil];
        }]];
    }
    [list addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:list animated:YES completion:nil];
}

- (void)performanceControlDidChangeAutomaticVideoEnabled:(BOOL)enabled {
    self.automaticVideoEnabled = enabled;
    [NSUserDefaults.standardUserDefaults setBool:enabled forKey:@"AutomaticVideoMatchingEnabled"];
    if (!enabled) {
        [self resetMVMomentAnalysisForCurrentTrack];
        [self.signatureMVClip stop];
    }
}

// The immutable schedule survives pause and seek; only a new track/stop cancels it.
- (void)resetMVMomentAnalysisForCurrentTrack {
    [self.mvMomentAnalysisProgress cancel];
    self.mvMomentAnalysisProgress = nil;
    self.mvMomentAnalysisGeneration += 1;
    self.mvMomentCandidates = @[];
    self.mvMomentStatusLabel.hidden = YES;
    [self.progressView setMomentMarkers:@[]];
}

- (void)prepareAndPlayAudioPath:(NSString *)path title:(NSString *)title artist:(NSString *)artist {
    [self resetMVMomentAnalysisForCurrentTrack];
    [self.signatureMVClip stop];
    self.mvAudioPath = path;
    self.mvAudioTitle = title;
    self.mvAudioArtist = artist;
    // Music starts immediately; media download, alignment and AI run independently.
    [self.player playWithFileName:path songName:title artist:artist];
    if (self.isShowingVinylRecord) [self.vinylRecordView startSpinning];
    if (!self.automaticVideoEnabled) return;
    [self beginMVTimelinePreferredVideoID:nil videoTitle:nil];
}

- (void)beginMVTimelinePreferredVideoID:(NSString *)bvid videoTitle:(NSString *)videoTitle {
    if (!self.automaticVideoEnabled || self.mvAudioPath.length == 0) return;
    NSURL *url = [self.mvAudioPath hasPrefix:@"/"] ? [NSURL fileURLWithPath:self.mvAudioPath] : [[NSBundle mainBundle] URLForResource:self.mvAudioPath withExtension:nil];
    if (!url) return;
    self.mvMomentStatusLabel.hidden = YES;
    [self.progressView setMomentMarkers:@[]];
    NSUInteger generation = self.mvMomentAnalysisGeneration;
    __weak typeof(self) weakSelf = self;
    self.mvMomentAnalysisProgress = [MVTimelineCoordinator.shared analyzeSongURL:url title:self.mvAudioTitle ?: @"" artist:self.mvAudioArtist ?: @"" preferredVideoID:bvid preferredVideoTitle:videoTitle completion:^(NSURL *videoURL, NSArray<NSDictionary<NSString *, id> *> *moments, BOOL cacheHit, NSString *errorMessage) {
        typeof(self) self = weakSelf;
        if (!self || !self.automaticVideoEnabled || generation != self.mvMomentAnalysisGeneration) return;
        (void)cacheHit;
        self.mvMomentAnalysisProgress = nil;
        if (!videoURL || !moments) {
            self.mvMomentStatusLabel.hidden = YES;
            [self.progressView setMomentMarkers:@[]];
            NSLog(@"[MVMoment] %@", errorMessage ?: @"没有可核对的来源选段，已跳过视频");
            if ([errorMessage hasPrefix:@"音视频校准失败"]) {
                [self showPlaybackToast:@"同步失败"];
            }
            return;
        }
        self.mvMomentCandidates = moments;
        self.mvMomentStatusLabel.hidden = YES;
        [self.progressView setMomentMarkers:[self momentMarkersFromMoments:moments]];
        [self.signatureMVClip prepareResolvedVideoURL:videoURL song:self.mvAudioTitle];
        // The current song clock decides which future/current windows can run.
        [self.signatureMVClip updateWithTitle:self.mvAudioTitle time:self.player.currentTime playing:self.player.isPlaying mvMoments:moments];
    }];
}

#pragma mark - Playback Controls

- (void)previousButtonTapped:(UIButton *)sender {
    NSLog(@"⏮️ 点击上一首按钮");
    [self playPrevious];
}

- (void)nextButtonTapped:(UIButton *)sender {
    NSLog(@"⏭️ 点击下一首按钮");
    [self playNext];
}

- (void)playPauseButtonTapped:(UIButton *)sender {
    if (self.player.isPlaying) {
        NSLog(@"⏸️ 暂停播放");
        [self pausePlayback];
    } else if (self.player.isPaused) {
        NSLog(@"▶️ 恢复播放（从暂停位置 %.2fs）", self.player.currentTime);
        [self resumePlayback];
    } else {
        NSLog(@"▶️ 开始播放新曲目");
        if (self.displayedMusicItems.count > 0) {
            [self playCurrentTrack];
            if (@available(iOS 13.0, *)) {
                [self.playPauseButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
            }
            [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.75 green:0.25 blue:0.15 alpha:0.9];
        } else {
            NSLog(@"⚠️ 播放列表为空");
        }
    }
}

- (void)loopButtonTapped:(UIButton *)sender {
    self.isSingleLoopMode = !self.isSingleLoopMode;

    if (self.isSingleLoopMode) {
        NSLog(@"🔂 切换为单曲循环模式");
        if (@available(iOS 13.0, *)) {
            [self.loopButton setImage:[UIImage systemImageNamed:@"repeat.1"] forState:UIControlStateNormal];
        }
        [self.loopButton setTitle:@"" forState:UIControlStateNormal];
        self.loopButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.5 alpha:0.85];
        self.loopButton.layer.borderColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.6 alpha:0.8].CGColor;
    } else {
        NSLog(@"🔁 切换为列表循环模式");
        if (@available(iOS 13.0, *)) {
            [self.loopButton setImage:[UIImage systemImageNamed:@"repeat"] forState:UIControlStateNormal];
        }
        [self.loopButton setTitle:@"" forState:UIControlStateNormal];
        self.loopButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.7 alpha:0.85];
        self.loopButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.8 alpha:0.8].CGColor;
    }
}

- (void)audioEffectsButtonTapped:(UIButton *)sender {
    if (self.audioEffectsPanel) return;

    CGFloat width = MIN(370.0, CGRectGetWidth(self.view.bounds) - 32.0);
    CGFloat height = MIN(540.0, CGRectGetHeight(self.view.bounds) - 32.0);
    CGFloat panelX = (CGRectGetWidth(self.view.bounds) - width) / 2.0;
    CGFloat panelY = (CGRectGetHeight(self.view.bounds) - height) / 2.0;
    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    overlay.backgroundColor = [UIColor colorWithWhite:0 alpha:0.56];

    UIButton *backdrop = [UIButton buttonWithType:UIButtonTypeCustom];
    backdrop.frame = overlay.bounds;
    backdrop.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [backdrop addTarget:self action:@selector(dismissAudioEffectsPanel) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:backdrop];

    UIView *card = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, width, height)];
    card.backgroundColor = [UIColor colorWithRed:0.075 green:0.085 blue:0.12 alpha:0.98];
    card.layer.cornerRadius = 22;
    card.layer.borderWidth = 1;
    card.layer.borderColor = [UIColor colorWithWhite:1 alpha:0.15].CGColor;
    [overlay addSubview:card];

    UILabel *title = [[UILabel alloc] initWithFrame:CGRectMake(20, 17, width - 76, 30)];
    title.text = @"均衡器";
    title.textColor = UIColor.whiteColor;
    title.font = [UIFont systemFontOfSize:21 weight:UIFontWeightBold];
    [card addSubview:title];

    UIButton *close = [UIButton buttonWithType:UIButtonTypeSystem];
    [close setImage:[UIImage systemImageNamed:@"xmark.circle.fill"] forState:UIControlStateNormal];
    close.tintColor = [UIColor colorWithWhite:1 alpha:0.65];
    close.frame = CGRectMake(width - 48, 14, 32, 32);
    [close addTarget:self action:@selector(dismissAudioEffectsPanel) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:close];

    UILabel *subtitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 48, width - 40, 20)];
    subtitle.text = @"10 段均衡 · 点击频率可改带宽和滤波类型";
    subtitle.textColor = [UIColor colorWithWhite:1 alpha:0.62];
    subtitle.font = [UIFont systemFontOfSize:12];
    [card addSubview:subtitle];

    UIScrollView *presets = [[UIScrollView alloc] initWithFrame:CGRectMake(14, 76, width - 28, 38)];
    presets.showsHorizontalScrollIndicator = NO;
    NSArray<NSDictionary *> *presetChoices = @[
        @{@"title": @"原声", @"value": @(AudioSpectrumEQPresetFlat)},
        @{@"title": @"低频", @"value": @(AudioSpectrumEQPresetBass)},
        @{@"title": @"人声", @"value": @(AudioSpectrumEQPresetVocal)},
        @{@"title": @"明亮", @"value": @(AudioSpectrumEQPresetBright)},
        @{@"title": @"蓝调", @"value": @(AudioSpectrumEQPresetBlues)},
        @{@"title": @"摇滚", @"value": @(AudioSpectrumEQPresetRock)},
        @{@"title": @"爵士", @"value": @(AudioSpectrumEQPresetJazz)},
        @{@"title": @"流行", @"value": @(AudioSpectrumEQPresetPop)},
        @{@"title": @"古典", @"value": @(AudioSpectrumEQPresetClassical)},
        @{@"title": @"电子", @"value": @(AudioSpectrumEQPresetElectronic)},
        @{@"title": @"原声乐器", @"value": @(AudioSpectrumEQPresetAcoustic)},
        @{@"title": @"自定义", @"value": @(AudioSpectrumEQPresetCustom)},
    ];
    CGFloat presetX = 0;
    for (NSDictionary *choice in presetChoices) {
        UIButton *presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
        presetButton.frame = CGRectMake(presetX, 2, 68, 32);
        presetButton.tag = 520 + [choice[@"value"] integerValue];
        [presetButton setTitle:choice[@"title"] forState:UIControlStateNormal];
        presetButton.titleLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
        presetButton.layer.cornerRadius = 10;
        [presetButton addTarget:self action:@selector(audioEffectsPresetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [presets addSubview:presetButton];
        presetX += 74;
    }
    presets.contentSize = CGSizeMake(presetX, 38);
    presets.tag = 510;
    [card addSubview:presets];

    UILabel *preampTitle = [[UILabel alloc] initWithFrame:CGRectMake(18, 116, 55, 34)];
    preampTitle.text = @"前级";
    preampTitle.textColor = [UIColor colorWithWhite:1 alpha:0.88];
    preampTitle.font = [UIFont systemFontOfSize:12 weight:UIFontWeightMedium];
    [card addSubview:preampTitle];
    self.audioEffectsPreampSlider = [[UISlider alloc] initWithFrame:CGRectMake(76, 116, width - 145, 34)];
    self.audioEffectsPreampSlider.minimumValue = -24.0f;
    self.audioEffectsPreampSlider.maximumValue = 12.0f;
    self.audioEffectsPreampSlider.value = [self.player.equalizerConfiguration[@"preampDB"] floatValue];
    [self.audioEffectsPreampSlider addTarget:self action:@selector(audioEffectsPreampChanged:) forControlEvents:UIControlEventValueChanged];
    [self.audioEffectsPreampSlider addTarget:self action:@selector(audioEffectsBandEditingEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
    [card addSubview:self.audioEffectsPreampSlider];
    self.audioEffectsPreampLabel = [[UILabel alloc] initWithFrame:CGRectMake(width - 64, 116, 48, 34)];
    self.audioEffectsPreampLabel.textAlignment = NSTextAlignmentRight;
    self.audioEffectsPreampLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
    self.audioEffectsPreampLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
    [card addSubview:self.audioEffectsPreampLabel];
    [self refreshAudioEffectsPanelValues];

    NSArray<NSDictionary<NSString *, id> *> *bandConfigurations = self.player.equalizerConfiguration[@"bands"];
    UIScrollView *bandsScroll = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 154, width, MAX(150, height - 224))];
    bandsScroll.showsVerticalScrollIndicator = YES;
    [card addSubview:bandsScroll];
    self.audioEffectsBandSliders = [NSMutableArray arrayWithCapacity:bandConfigurations.count];
    self.audioEffectsGainLabels = [NSMutableArray arrayWithCapacity:bandConfigurations.count];
    self.audioEffectsBandFrequencyButtons = [NSMutableArray arrayWithCapacity:bandConfigurations.count];
    NSArray<NSNumber *> *gains = self.player.equalizerBandGains;
    for (NSUInteger index = 0; index < bandConfigurations.count; index++) {
        float frequencyHz = [bandConfigurations[index][@"frequencyHz"] floatValue];
        NSString *frequencyText = frequencyHz >= 1000.0f
            ? [NSString stringWithFormat:@"%.1fk", frequencyHz / 1000.0f]
            : [NSString stringWithFormat:@"%.0f", frequencyHz];
        CGFloat rowY = 7 + index * 43;
        UIButton *frequency = [UIButton buttonWithType:UIButtonTypeSystem];
        frequency.frame = CGRectMake(12, rowY, 62, 34);
        [frequency setTitle:frequencyText forState:UIControlStateNormal];
        [frequency setTitleColor:[UIColor colorWithWhite:1 alpha:0.88] forState:UIControlStateNormal];
        frequency.titleLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
        frequency.backgroundColor = [UIColor colorWithWhite:1 alpha:0.06];
        frequency.layer.cornerRadius = 8;
        frequency.tag = index;
        frequency.accessibilityLabel = [NSString stringWithFormat:@"配置 %@ 频段参数", frequencyText];
        [frequency addTarget:self action:@selector(audioEffectsBandDetailTapped:) forControlEvents:UIControlEventTouchUpInside];
        [bandsScroll addSubview:frequency];
        [self.audioEffectsBandFrequencyButtons addObject:frequency];

        UISlider *slider = [[UISlider alloc] initWithFrame:CGRectMake(76, rowY, width - 145, 34)];
        slider.minimumValue = -24.0f;
        slider.maximumValue = 12.0f;
        slider.value = gains[index].floatValue;
        slider.minimumTrackTintColor = [UIColor colorWithRed:0.25 green:0.78 blue:0.63 alpha:1];
        slider.maximumTrackTintColor = [UIColor colorWithWhite:1 alpha:0.18];
        slider.tag = index;
        [slider addTarget:self action:@selector(audioEffectsBandChanged:) forControlEvents:UIControlEventValueChanged];
        [slider addTarget:self action:@selector(audioEffectsBandEditingEnded:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside | UIControlEventTouchCancel];
        [bandsScroll addSubview:slider];
        [self.audioEffectsBandSliders addObject:slider];

        UILabel *gainLabel = [[UILabel alloc] initWithFrame:CGRectMake(width - 64, rowY, 48, 34)];
        gainLabel.text = [NSString stringWithFormat:@"%+.1f", gains[index].floatValue];
        gainLabel.textAlignment = NSTextAlignmentRight;
        gainLabel.textColor = [UIColor colorWithWhite:1 alpha:0.78];
        gainLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightRegular];
        [bandsScroll addSubview:gainLabel];
        [self.audioEffectsGainLabels addObject:gainLabel];
    }

    bandsScroll.contentSize = CGSizeMake(width, bandConfigurations.count * 43 + 8);

    UIButton *reset = [UIButton buttonWithType:UIButtonTypeSystem];
    [reset setTitle:@"重置为原声" forState:UIControlStateNormal];
    reset.tintColor = [UIColor colorWithRed:0.55 green:0.86 blue:0.77 alpha:1];
    reset.titleLabel.font = [UIFont systemFontOfSize:14 weight:UIFontWeightSemibold];
    reset.frame = CGRectMake(18, height - 54, width - 36, 40);
    reset.backgroundColor = [UIColor colorWithWhite:1 alpha:0.07];
    reset.layer.cornerRadius = 12;
    [reset addTarget:self action:@selector(resetAudioEffects) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:reset];

    self.audioEffectsPanel = overlay;
    [self.view addSubview:overlay];
    [self refreshAudioEffectsPanelValues];
    overlay.alpha = 0;
    card.transform = CGAffineTransformMakeScale(0.96, 0.96);
    [UIView animateWithDuration:0.22 animations:^{
        overlay.alpha = 1;
        card.transform = CGAffineTransformIdentity;
    }];
}

- (void)audioEffectsPresetButtonTapped:(UIButton *)sender {
    AudioSpectrumEQPreset preset = (AudioSpectrumEQPreset)(sender.tag - 520);
    self.player.equalizerPreset = preset;
    [self refreshAudioEffectsPanelValues];
    [self.audioEffectsButton setTitle:@" EQ" forState:UIControlStateNormal];
    self.audioEffectsButton.backgroundColor = preset == AudioSpectrumEQPresetFlat
        ? [UIColor colorWithWhite:1.0 alpha:0.10]
        : [UIColor colorWithRed:0.13 green:0.48 blue:0.42 alpha:0.92];
}

- (void)audioEffectsBandChanged:(UISlider *)sender {
    [self.player setEqualizerGain:sender.value atBand:(NSUInteger)sender.tag];
    self.audioEffectsGainLabels[sender.tag].text = [NSString stringWithFormat:@"%+.1f", sender.value];
    [self refreshAudioEffectsPresetButtons];
    [self.audioEffectsButton setTitle:@" EQ" forState:UIControlStateNormal];
    self.audioEffectsButton.backgroundColor = [UIColor colorWithRed:0.13 green:0.48 blue:0.42 alpha:0.92];
}

- (void)audioEffectsPreampChanged:(UISlider *)sender {
    [self.player setEqualizerPreampGain:sender.value];
    self.audioEffectsPreampLabel.text = [NSString stringWithFormat:@"%+.1f", sender.value];
    [self refreshAudioEffectsPresetButtons];
    self.audioEffectsButton.backgroundColor = [UIColor colorWithRed:0.13 green:0.48 blue:0.42 alpha:0.92];
}

- (void)audioEffectsBandDetailTapped:(UIButton *)sender {
    NSUInteger bandIndex = (NSUInteger)sender.tag;
    NSArray<NSDictionary<NSString *, id> *> *bands = self.player.equalizerConfiguration[@"bands"];
    if (bandIndex >= bands.count) return;
    NSDictionary *band = bands[bandIndex];
    NSDictionary<NSString *, NSString *> *typeTitles = @{
        @"parametric": @"钟形均衡", @"lowShelf": @"低架均衡", @"highShelf": @"高架均衡",
        @"lowPass": @"低通滤波", @"highPass": @"高通滤波", @"bandPass": @"带通滤波", @"bandStop": @"带阻滤波",
    };
    NSString *title = [NSString stringWithFormat:@"%@ 频段", sender.currentTitle ?: @""];
    UIAlertController *sheet = [UIAlertController alertControllerWithTitle:title
        message:[NSString stringWithFormat:@"%@ · 带宽 %.2f oct", typeTitles[band[@"type"]] ?: @"钟形均衡", [band[@"bandwidthOctaves"] floatValue]]
        preferredStyle:UIAlertControllerStyleActionSheet];
    __weak typeof(self) weakSelf = self;
    [sheet addAction:[UIAlertAction actionWithTitle:@"编辑中心频率和带宽" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        typeof(self) self = weakSelf;
        if (!self) return;
        UIAlertController *edit = [UIAlertController alertControllerWithTitle:@"频段参数" message:@"频率单位为 Hz，带宽单位为 oct。" preferredStyle:UIAlertControllerStyleAlert];
        [edit addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.keyboardType = UIKeyboardTypeDecimalPad;
            field.placeholder = @"中心频率 Hz";
            field.text = [NSString stringWithFormat:@"%.0f", [band[@"frequencyHz"] floatValue]];
        }];
        [edit addTextFieldWithConfigurationHandler:^(UITextField *field) {
            field.keyboardType = UIKeyboardTypeDecimalPad;
            field.placeholder = @"带宽 oct";
            field.text = [NSString stringWithFormat:@"%.2f", [band[@"bandwidthOctaves"] floatValue]];
        }];
        [edit addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
        [edit addAction:[UIAlertAction actionWithTitle:@"应用" style:UIAlertActionStyleDefault handler:^(UIAlertAction *apply) {
            float frequency = edit.textFields[0].text.floatValue;
            float bandwidth = edit.textFields[1].text.floatValue;
            [self updateEqualizerBandAtIndex:bandIndex changes:@{@"frequencyHz": @(frequency), @"bandwidthOctaves": @(bandwidth)}];
        }]];
        [self presentViewController:edit animated:YES completion:nil];
    }]];
    NSArray<NSString *> *filterTypes = @[@"parametric", @"lowShelf", @"highShelf", @"lowPass", @"highPass", @"bandPass", @"bandStop"];
    for (NSString *type in filterTypes) {
        [sheet addAction:[UIAlertAction actionWithTitle:[NSString stringWithFormat:@"类型：%@", typeTitles[type]] style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self updateEqualizerBandAtIndex:bandIndex changes:@{@"type": type}];
        }]];
    }
    BOOL enabled = [band[@"enabled"] boolValue];
    [sheet addAction:[UIAlertAction actionWithTitle:enabled ? @"停用此频段" : @"启用此频段" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [self updateEqualizerBandAtIndex:bandIndex changes:@{@"enabled": @(!enabled)}];
    }]];
    [sheet addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    UIPopoverPresentationController *popover = sheet.popoverPresentationController;
    popover.sourceView = sender;
    popover.sourceRect = sender.bounds;
    [self presentViewController:sheet animated:YES completion:nil];
}

- (void)updateEqualizerBandAtIndex:(NSUInteger)bandIndex changes:(NSDictionary<NSString *, id> *)changes {
    NSMutableDictionary *configuration = [self.player.equalizerConfiguration mutableCopy];
    NSMutableArray *bands = [configuration[@"bands"] mutableCopy];
    if (bandIndex >= bands.count) return;
    NSMutableDictionary *band = [bands[bandIndex] mutableCopy];
    [band addEntriesFromDictionary:changes];
    bands[bandIndex] = band;
    configuration[@"bands"] = bands;
    configuration[@"profileID"] = @"custom";
    configuration[@"source"] = @"user";
    configuration[@"metadata"] = @{};
    NSError *error = nil;
    if (![self.player applyEqualizerConfiguration:configuration error:&error]) {
        [self showPlaybackToast:error.localizedDescription ?: @"频段参数无效"];
        return;
    }
    [self refreshAudioEffectsPanelValues];
}

- (void)audioEffectsBandEditingEnded:(UISlider *)sender {
    [self.player saveEqualizerSettings];
}

- (void)refreshAudioEffectsPanelValues {
    NSArray<NSNumber *> *gains = self.player.equalizerBandGains;
    for (NSUInteger index = 0; index < MIN(gains.count, self.audioEffectsBandSliders.count); index++) {
        float gain = gains[index].floatValue;
        self.audioEffectsBandSliders[index].value = gain;
        self.audioEffectsGainLabels[index].text = [NSString stringWithFormat:@"%+.1f", gain];
    }
    NSDictionary *configuration = self.player.equalizerConfiguration;
    self.audioEffectsPreampSlider.value = [configuration[@"preampDB"] floatValue];
    self.audioEffectsPreampLabel.text = [NSString stringWithFormat:@"%+.1f", [configuration[@"preampDB"] floatValue]];
    NSArray<NSDictionary<NSString *, id> *> *bands = configuration[@"bands"];
    for (NSUInteger index = 0; index < MIN(bands.count, self.audioEffectsBandFrequencyButtons.count); index++) {
        float frequency = [bands[index][@"frequencyHz"] floatValue];
        NSString *frequencyText = frequency >= 1000.0f
            ? [NSString stringWithFormat:@"%.1fk", frequency / 1000.0f]
            : [NSString stringWithFormat:@"%.0f", frequency];
        [self.audioEffectsBandFrequencyButtons[index] setTitle:frequencyText forState:UIControlStateNormal];
    }
    [self refreshAudioEffectsPresetButtons];
}

- (void)refreshAudioEffectsPresetButtons {
    UIScrollView *presets = (UIScrollView *)[self.audioEffectsPanel viewWithTag:510];
    for (UIView *view in presets.subviews) {
        if (![view isKindOfClass:UIButton.class]) continue;
        UIButton *button = (UIButton *)view;
        BOOL selected = (button.tag - 520) == self.player.equalizerPreset;
        button.backgroundColor = selected ? [UIColor colorWithRed:0.20 green:0.55 blue:0.46 alpha:1] : [UIColor colorWithWhite:1 alpha:0.07];
        [button setTitleColor:selected ? UIColor.whiteColor : [UIColor colorWithWhite:1 alpha:0.75] forState:UIControlStateNormal];
    }
}

- (void)resetAudioEffects {
    self.player.equalizerPreset = AudioSpectrumEQPresetFlat;
    [self refreshAudioEffectsPanelValues];
    [self.audioEffectsButton setTitle:@" EQ" forState:UIControlStateNormal];
    self.audioEffectsButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
}

- (void)dismissAudioEffectsPanel {
    [self.audioEffectsPanel removeFromSuperview];
    self.audioEffectsPanel = nil;
    self.audioEffectsBandSliders = nil;
    self.audioEffectsGainLabels = nil;
    self.audioEffectsBandFrequencyButtons = nil;
    self.audioEffectsPreampSlider = nil;
    self.audioEffectsPreampLabel = nil;
}

#pragma mark - Remote Commands

- (void)setupRemoteCommandCenter {
    NSLog(@"🎵 开始配置系统媒体控制（iOS 16+ 优化）...");

    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSLog(@"✅ Step 1: 音频会话由 AudioSpectrumPlayer 管理");
    NSLog(@"   当前类别: %@", audioSession.category);
    NSLog(@"   混音模式: %@", self.player.allowMixWithOthers ? @"开启" : @"关闭");

    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    NSLog(@"✅ Step 2: 已启用远程控制事件接收");

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    [commandCenter.playCommand removeTarget:nil];
    [commandCenter.pauseCommand removeTarget:nil];
    [commandCenter.nextTrackCommand removeTarget:nil];
    [commandCenter.previousTrackCommand removeTarget:nil];
    [commandCenter.togglePlayPauseCommand removeTarget:nil];

    commandCenter.togglePlayPauseCommand.enabled = NO;

    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 播放");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.shouldPreventAutoResume) {
                NSLog(@"   ⚠️ 已禁止播放（用户在其他页面）");
                return;
            }
            if (self.player.isPaused) {
                NSLog(@"   从暂停位置恢复播放（%.2fs）", self.player.currentTime);
                [self resumePlayback];
            } else if (!self.player.isPlaying) {
                NSLog(@"   开始播放当前曲目");
                [self playCurrentTrack];
            }
            self.wasPlayingBeforeBackground = NO;
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 暂停");
        dispatch_async(dispatch_get_main_queue(), ^{
            if (self.player.isPlaying) {
                [self pausePlayback];
            }
            self.wasPlayingBeforeBackground = NO;
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 下一首");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playNext];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 上一首");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playPrevious];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];

    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;

    NSLog(@"✅ Step 3: 远程命令已注册并启用");
    NSLog(@"📋 最终配置状态:");
    NSLog(@"   • 音频会话类别: %@", audioSession.category);
    NSLog(@"   • 音频会话模式: %@", audioSession.mode);
    NSLog(@"   • 混音模式: %@", self.player.allowMixWithOthers ? @"✅ 允许混音" : @"❌ 独占播放");
    NSLog(@"   • 播放命令: %@", commandCenter.playCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 暂停命令: %@", commandCenter.pauseCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 下一首命令: %@", commandCenter.nextTrackCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 上一首命令: %@", commandCenter.previousTrackCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 切换播放命令: %@ (应该禁用)", commandCenter.togglePlayPauseCommand.isEnabled ? @"❌ 启用了" : @"✅ 已禁用");
    NSLog(@"✅ 系统媒体控制配置完成（iOS 16+ 优化）");
}

- (BOOL)canBecomeFirstResponder {
    return YES;
}

- (void)forceUpdateNowPlayingInfo {
    NSLog(@"🔍 强制设置播放信息测试...");

    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = @"测试歌曲";
    info[MPMediaItemPropertyArtist] = @"测试艺术家";
    info[MPMediaItemPropertyPlaybackDuration] = @(180.0);
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(0.0);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);

    UIImage *testArtwork = [self createDefaultArtworkImage];
    if (testArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:testArtwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return testArtwork;
        }];
        info[MPMediaItemPropertyArtwork] = artwork;
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;

    NSLog(@"✅ 强制设置完成");
    NSLog(@"   当前播放信息: %@", [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo);

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   音频会话类别: %@", session.category);
    NSLog(@"   音频会话选项: %lu", (unsigned long)session.categoryOptions);
    NSLog(@"   其他音频播放中: %@", @([session isOtherAudioPlaying]));
    NSLog(@"   音频会话激活: ✅ (已设置)");

    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    NSLog(@"   播放命令启用: %@", @(commandCenter.playCommand.isEnabled));
    NSLog(@"   暂停命令启用: %@", @(commandCenter.pauseCommand.isEnabled));
}

- (void)updateNowPlayingInfoImmediate {
    if (self.isPlatformQueueActive) return;
    if (self.currentIndex >= self.displayedMusicItems.count) {
        NSLog(@"⚠️ 无法更新播放信息: 索引超出范围");
        return;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];

    NSString *title = @"正在播放";
    if (musicItem.displayName) {
        title = musicItem.displayName;
    } else if (musicItem.fileName) {
        title = [musicItem.fileName stringByDeletingPathExtension];
    }
    nowPlayingInfo[MPMediaItemPropertyTitle] = title;
    nowPlayingInfo[MPMediaItemPropertyArtist] = @"AudioSampleBuffer";
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = @"本地音乐";

    UIImage *defaultArtwork = [self createDefaultArtworkImage];
    if (defaultArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:defaultArtwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return defaultArtwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
        NSLog(@"   - 封面图片: ✅ 已设置 (%.0fx%.0f)", defaultArtwork.size.width, defaultArtwork.size.height);
    }

    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(0.0);

    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = nowPlayingInfo;

    NSLog(@"✅ 立即设置播放信息成功:");
    NSLog(@"   - 标题: %@", title);
    NSLog(@"   - 艺术家: %@", nowPlayingInfo[MPMediaItemPropertyArtist]);
    NSLog(@"   - 播放速率: %@", nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate]);

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   - 音频会话类别: %@", session.category);
    NSLog(@"   - 音频会话选项: %lu (0=独占, 1=混音)", (unsigned long)session.categoryOptions);
    NSLog(@"   - 其他音频播放中: %@", @(session.isOtherAudioPlaying));

    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        center.nowPlayingInfo = nowPlayingInfo;
        NSLog(@"🔄 二次确认播放信息已设置");
    });
}

- (UIImage *)createDefaultArtworkImage {
    if (self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];

        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        }

        if (fileUrl) {
            UIImage *musicCover = [self musicImageWithMusicURL:fileUrl];
            if (musicCover) {
                NSLog(@"✅ 使用音乐真实封面 (%.0fx%.0f): %@", musicCover.size.width, musicCover.size.height, musicItem.fileName);
                return musicCover;
            }
        }
    }

    UIImage *appIcon = [UIImage imageNamed:@"none_image"];
    if (appIcon) {
        NSLog(@"✅ 使用 App Icon 作为默认封面 (%.0fx%.0f)", appIcon.size.width, appIcon.size.height);
        return appIcon;
    }

    UIImage *noneImage = [UIImage imageNamed:@"none_image"];
    if (noneImage) {
        NSLog(@"✅ 使用默认封面图片: none_image (%.0fx%.0f)", noneImage.size.width, noneImage.size.height);
        return noneImage;
    }

    NSLog(@"⚠️ none_image 图片未找到，使用程序生成的默认封面");

    CGSize size = CGSizeMake(512, 512);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();

    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:1.0].CGColor
    ];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(size.width, size.height), 0);

    UIBezierPath *musicNote = [UIBezierPath bezierPath];
    CGFloat centerX = size.width / 2;
    CGFloat centerY = size.height / 2;
    [musicNote moveToPoint:CGPointMake(centerX - 30, centerY + 40)];
    [musicNote addLineToPoint:CGPointMake(centerX - 30, centerY - 40)];
    [musicNote addLineToPoint:CGPointMake(centerX + 30, centerY - 50)];
    [musicNote addLineToPoint:CGPointMake(centerX + 30, centerY + 30)];
    [[UIColor whiteColor] setStroke];
    musicNote.lineWidth = 8;
    [musicNote stroke];

    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);

    return image;
}

- (void)updateNowPlayingInfo {
    if (self.isPlatformQueueActive) return;
    if (self.currentIndex >= self.displayedMusicItems.count) {
        return;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];

    if (musicItem.displayName) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = musicItem.displayName;
    } else if (musicItem.fileName) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = [musicItem.fileName stringByDeletingPathExtension];
    }

    if (self.player.lyricsParser && self.player.lyricsParser.artist) {
        nowPlayingInfo[MPMediaItemPropertyArtist] = self.player.lyricsParser.artist;
    } else {
        nowPlayingInfo[MPMediaItemPropertyArtist] = @"未知艺术家";
    }

    if (self.player.lyricsParser && self.player.lyricsParser.album) {
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = self.player.lyricsParser.album;
    }

    UIImage *artwork = [self createDefaultArtworkImage];
    if (artwork) {
        MPMediaItemArtwork *artworkItem = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkItem;
    }

    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(self.player.duration);
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
    if (self.player.isPlaying) {
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
    }

    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    NSLog(@"🎵 已更新系统播放信息: %@", nowPlayingInfo[MPMediaItemPropertyTitle]);
}

#pragma mark - Public Playback API

- (void)pausePlayback {
    NSLog(@"⏸️ 暂停播放");
    if (self.automaticVideoEnabled) {
        [self.signatureMVClip updateWithTitle:self.nowPlayingTitleLabel.text time:self.player.currentTime playing:NO];
    }
    [self.player pause];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView pauseSpinning];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.3 alpha:0.9];
    });

    [self.player pauseEngine];
    [self deactivateAudioSessionForPause];

    NSLog(@"✅ 已暂停播放（engine已暂停，session已deactivate，控制中心将显示播放按钮）");
}

- (void)deactivateAudioSessionForPause {
    NSError *error = nil;
    BOOL success = [[AVAudioSession sharedInstance] setActive:NO
                                                  withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation
                                                        error:&error];
    if (success) {
        NSLog(@"✅ AudioSession 已 deactivate（系统将更新播放按钮）");
    } else {
        NSLog(@"⚠️ AudioSession deactivate 返回: %@ (按钮仍会更新)", error.localizedDescription);
    }
}

- (void)resumePlayback {
    NSLog(@"▶️ 恢复播放");
    [self.player configureAudioSession];
    [self.player resume];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView resumeSpinning];
    }

    dispatch_async(dispatch_get_main_queue(), ^{
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.75 green:0.25 blue:0.15 alpha:0.9];
    });

    NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
    if (nowPlayingInfo) {
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    }

    NSLog(@"✅ 已恢复播放（从 %.2fs 继续）", self.player.currentTime);
}

- (void)playCurrentTrack {
    NSLog(@"🎵 [playCurrentTrack] 开始...");
    NSLog(@"   当前索引: %ld", (long)self.currentIndex);
    NSLog(@"   列表总数: %lu", (unsigned long)self.displayedMusicItems.count);

    if (self.currentIndex >= self.displayedMusicItems.count) {
        NSLog(@"⚠️ 索引超出范围: %ld / %lu", (long)self.currentIndex, (unsigned long)self.displayedMusicItems.count);
        return;
    }

    MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
    NSLog(@"   歌曲: %@", musicItem.fileName);
    NSLog(@"   路径: %@", musicItem.filePath);

    NSString *playPath = nil;
    if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
        playPath = musicItem.decryptedPath;
        NSLog(@"🎵 播放已解密文件: %@", playPath);
    } else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
        NSLog(@"🔓 解密NCM文件: %@", musicItem.fileName);
        NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
        playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];

        if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
            NSLog(@"✅ 解密成功: %@", playPath);
        }
    } else if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
        playPath = musicItem.filePath;
        NSLog(@"🎵 播放云下载文件（完整路径）: %@", playPath);
    } else {
        playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
        NSLog(@"🎵 播放Bundle文件: %@", playPath);
    }

    if (playPath.length == 0) {
        NSLog(@"❌ [playCurrentTrack] playPath 为空！");
        return;
    }

    NSLog(@"🎵 [playCurrentTrack] 最终播放路径: %@", playPath);
    [self updateNowPlayingInfoImmediate];

    NSString *songName = musicItem.displayName ?: [musicItem.fileName stringByDeletingPathExtension];
    NSString *artist = musicItem.artist ?: @"";
    if (artist.length == 0 && songName.length > 0 && [songName containsString:@" - "]) {
        NSArray *parts = [songName componentsSeparatedByString:@" - "];
        if (parts.count >= 2) {
            artist = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            songName = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        }
    }

    self.player.htDemucsGuitarAnalysisEnabled = self.guitarDemucsOnDeviceExperimentEnabled;
    [[NSNotificationCenter defaultCenter] postNotificationName:@"PlatformMusicClearQueue" object:nil];
    [self prepareAndPlayAudioPath:playPath title:songName artist:artist];

    if (self.isShowingVinylRecord) {
        [self.vinylRecordView startSpinning];
    }
}

#pragma mark - Audio Session

- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];

    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        NSLog(@"🎧 音频会话中断开始");
        self.wasPlayingBeforeInterruption = self.player.isPlaying;
        NSLog(@"   中断前播放状态: %@", self.wasPlayingBeforeInterruption ? @"播放中" : @"已暂停");

        if (self.player.isPlaying) {
            [self pausePlayback];
        }
    } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        NSLog(@"🎧 音频会话中断结束");

        if (self.shouldPreventAutoResume) {
            NSLog(@"   ⚠️ 已禁止自动恢复播放（用户可能在其他页面）");
            return;
        }

        if (!self.wasPlayingBeforeInterruption) {
            NSLog(@"   ⚠️ 中断前未播放，不恢复播放");
            return;
        }

        AVAudioSessionInterruptionOptions options = [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        BOOL shouldResume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;

        NSLog(@"   是否应该恢复播放: %@", shouldResume ? @"是" : @"否");

        if (shouldResume) {
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (error) {
                NSLog(@"❌ 重新激活音频会话失败: %@", error);
            } else {
                NSLog(@"✅ 音频会话已重新激活");
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self playCurrentTrack];
                    NSLog(@"✅ 已恢复播放");
                    self.wasPlayingBeforeInterruption = NO;
                });
            }
        }
    }
}

- (void)handleAudioSessionRouteChange:(NSNotification *)notification {
    AVAudioSessionRouteChangeReason reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];

    NSLog(@"🎧 音频路由变化，原因: %lu", (unsigned long)reason);

    switch (reason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
            NSLog(@"🎧 新音频设备连接");

            AVAudioSession *session = [AVAudioSession sharedInstance];
            AVAudioSessionRouteDescription *currentRoute = session.currentRoute;

            for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
                NSLog(@"   输出设备: %@ (%@)", output.portName, output.portType);

                if ([output.portType isEqualToString:AVAudioSessionPortHeadphones] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
                    NSLog(@"✅ 检测到耳机/蓝牙设备连接");
                }
            }
            break;
        }

        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
            NSLog(@"🎧 音频设备断开");

            AVAudioSessionRouteDescription *previousRoute = notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
            for (AVAudioSessionPortDescription *output in previousRoute.outputs) {
                NSLog(@"   断开的设备: %@ (%@)", output.portName, output.portType);

                if ([output.portType isEqualToString:AVAudioSessionPortHeadphones] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
                    NSLog(@"⚠️ 耳机/蓝牙设备已断开，暂停播放");
                    if (self.player.isPlaying) {
                        [self pausePlayback];
                        NSLog(@"✅ 已自动暂停播放");
                    }
                }
            }
            break;
        }

        case AVAudioSessionRouteChangeReasonCategoryChange: {
            NSLog(@"🎧 音频类别变化");

            AVAudioSession *session = [AVAudioSession sharedInstance];
            NSLog(@"   新类别: %@", session.category);
            NSLog(@"   新模式: %@", session.mode);

            if (self.player.isPlaying) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self.player configureAudioSession];
                    NSLog(@"✅ 已重新配置音频会话");
                });
            }
            break;
        }

        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"🎧 音频路由被覆盖");
            break;

        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"🎧 从睡眠中唤醒");
            break;

        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"⚠️ 当前类别没有合适的音频路由");
            break;

        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            NSLog(@"🎧 音频路由配置变化");
            break;

        default:
            NSLog(@"🎧 其他路由变化原因: %lu", (unsigned long)reason);
            break;
    }

    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *currentRoute = session.currentRoute;
    NSLog(@"📋 当前音频路由:");
    for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
        NSLog(@"   输出: %@ (%@)", output.portName, output.portType);
    }
    for (AVAudioSessionPortDescription *input in currentRoute.inputs) {
        NSLog(@"   输入: %@ (%@)", input.portName, input.portType);
    }
}

@end
