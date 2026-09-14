#import "ViewController+Private.h"

#import "AudioFileFormats.h"
#import "ViewController+PlaybackProgress.h"
#import "AudioSampleBuffer/RealtimeAnalyzer.h"

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
        @"activityClimax": @(climax)
    };
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

    [self.player playWithFileName:playPath songName:songName artist:artist];

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
