//
//  AudioFeatureExtractor.m
//  AudioSampleBuffer
//

#import "AudioFeatureExtractor.h"
#import <Accelerate/Accelerate.h>
#import <QuartzCore/QuartzCore.h>

static const NSInteger kBeatHistorySize = 128;
static const NSInteger kEnergyHistorySize = 64;
static const float kBeatThresholdMultiplier = 1.4f;
static const float kEMAAlpha = 0.3f;

@implementation AudioFeatures

+ (instancetype)emptyFeatures {
    AudioFeatures *features = [[AudioFeatures alloc] init];
    features.bpm = 120.0f;
    features.energy = 0.0f;
    features.bassEnergy = 0.0f;
    features.midEnergy = 0.0f;
    features.highEnergy = 0.0f;
    features.spectralCentroid = 0.5f;
    features.spectralFlux = 0.0f;
    features.currentSegment = MusicSegmentUnknown;
    features.beatDetected = NO;
    features.segmentChanged = NO;
    features.timestamp = 0;
    return features;
}

- (id)copyWithZone:(NSZone *)zone {
    AudioFeatures *copy = [[AudioFeatures alloc] init];
    copy.bpm = self.bpm;
    copy.energy = self.energy;
    copy.bassEnergy = self.bassEnergy;
    copy.midEnergy = self.midEnergy;
    copy.highEnergy = self.highEnergy;
    copy.spectralCentroid = self.spectralCentroid;
    copy.spectralFlux = self.spectralFlux;
    copy.currentSegment = self.currentSegment;
    copy.beatDetected = self.beatDetected;
    copy.segmentChanged = self.segmentChanged;
    copy.timestamp = self.timestamp;
    return copy;
}

@end

@interface AudioFeatureExtractor ()

@property (nonatomic, strong) AudioFeatures *currentFeatures;
@property (nonatomic, strong) NSHashTable<id<AudioFeatureObserver>> *observers;

// 历史数据
@property (nonatomic, strong) NSMutableArray<NSNumber *> *energyHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *beatTimeHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *previousSpectrum;

// 节拍检测
@property (nonatomic, assign) float lastBassEnergy;
@property (nonatomic, assign) NSTimeInterval lastBeatTime;
@property (nonatomic, assign) float beatThreshold;
@property (nonatomic, assign) float averageBPM;

// 段落检测 - 增强版
@property (nonatomic, assign) float longTermEnergy;
@property (nonatomic, assign) float shortTermEnergy;
@property (nonatomic, assign) MusicSegment previousSegment;
@property (nonatomic, assign) NSTimeInterval segmentStartTime;

// 段落分析增强
@property (nonatomic, strong) NSMutableArray<NSNumber *> *energyEnvelope;      // 能量包络
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spectralContrast;    // 频谱对比
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *segmentHistory;  // 段落历史
@property (nonatomic, assign) float peakEnergy;                                // 峰值能量
@property (nonatomic, assign) float energyVariance;                            // 能量方差
@property (nonatomic, assign) float averageEnergy;                             // 平均能量
@property (nonatomic, assign) NSTimeInterval estimatedDuration;                // 估计时长
@property (nonatomic, assign) BOOL introDetected;                              // 是否检测到前奏
@property (nonatomic, assign) BOOL firstChorusDetected;                        // 是否检测到第一个副歌
@property (nonatomic, assign) NSTimeInterval firstChorusTime;                  // 第一个副歌时间
@property (nonatomic, assign) NSInteger chorusCount;                           // 副歌次数
@property (nonatomic, assign) float chorusEnergyThreshold;                     // 副歌能量阈值
@property (nonatomic, assign) NSInteger stableFrameCount;                      // 稳定帧计数

// EMA滤波后的值
@property (nonatomic, assign) float smoothedEnergy;
@property (nonatomic, assign) float smoothedBassEnergy;
@property (nonatomic, assign) float smoothedMidEnergy;
@property (nonatomic, assign) float smoothedHighEnergy;

// 时间
@property (nonatomic, assign) NSTimeInterval startTime;
@property (nonatomic, assign) NSInteger frameCount;

@end

@implementation AudioFeatureExtractor

+ (instancetype)sharedExtractor {
    static AudioFeatureExtractor *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AudioFeatureExtractor alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentFeatures = [AudioFeatures emptyFeatures];
        _observers = [NSHashTable weakObjectsHashTable];
        _energyHistory = [NSMutableArray arrayWithCapacity:kEnergyHistorySize];
        _beatTimeHistory = [NSMutableArray arrayWithCapacity:kBeatHistorySize];
        _previousSpectrum = [NSMutableArray array];
        
        _lastBassEnergy = 0;
        _lastBeatTime = 0;
        _beatThreshold = 0.3f;
        _averageBPM = 120.0f;
        
        _longTermEnergy = 0;
        _shortTermEnergy = 0;
        _previousSegment = MusicSegmentUnknown;
        _segmentStartTime = 0;
        
        // 段落分析增强初始化
        _energyEnvelope = [NSMutableArray arrayWithCapacity:300];  // 约5秒数据 @60fps
        _spectralContrast = [NSMutableArray arrayWithCapacity:300];
        _segmentHistory = [NSMutableArray array];
        _peakEnergy = 0;
        _energyVariance = 0;
        _averageEnergy = 0;
        _estimatedDuration = 180.0;  // 默认3分钟
        _introDetected = NO;
        _firstChorusDetected = NO;
        _firstChorusTime = 0;
        _chorusCount = 0;
        _chorusEnergyThreshold = 0.6;
        _stableFrameCount = 0;
        
        _smoothedEnergy = 0;
        _smoothedBassEnergy = 0;
        _smoothedMidEnergy = 0;
        _smoothedHighEnergy = 0;
        
        _startTime = CACurrentMediaTime();
        _frameCount = 0;
    }
    return self;
}

- (void)reset {
    self.currentFeatures = [AudioFeatures emptyFeatures];
    [self.energyHistory removeAllObjects];
    [self.beatTimeHistory removeAllObjects];
    [self.previousSpectrum removeAllObjects];
    
    self.lastBassEnergy = 0;
    self.lastBeatTime = 0;
    self.beatThreshold = 0.3f;
    self.averageBPM = 120.0f;
    
    self.longTermEnergy = 0;
    self.shortTermEnergy = 0;
    self.previousSegment = MusicSegmentUnknown;
    self.segmentStartTime = 0;
    
    // 重置增强段落分析
    [self.energyEnvelope removeAllObjects];
    [self.spectralContrast removeAllObjects];
    [self.segmentHistory removeAllObjects];
    self.peakEnergy = 0;
    self.energyVariance = 0;
    self.averageEnergy = 0;
    self.introDetected = NO;
    self.firstChorusDetected = NO;
    self.firstChorusTime = 0;
    self.chorusCount = 0;
    self.chorusEnergyThreshold = 0.6;
    self.stableFrameCount = 0;
    
    self.smoothedEnergy = 0;
    self.smoothedBassEnergy = 0;
    self.smoothedMidEnergy = 0;
    self.smoothedHighEnergy = 0;
    
    self.startTime = CACurrentMediaTime();
    self.frameCount = 0;
}

#pragma mark - Process Spectrum

- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum {
    [self processSpectrumData:spectrum sampleRate:44100.0f];
}

- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrum sampleRate:(float)sampleRate {
    if (spectrum.count == 0) return;
    
    self.frameCount++;
    NSTimeInterval currentTime = CACurrentMediaTime() - self.startTime;
    
    AudioFeatures *features = [[AudioFeatures alloc] init];
    features.timestamp = currentTime;
    
    NSInteger spectrumSize = spectrum.count;
    float nyquist = sampleRate / 2.0f;
    float binWidth = nyquist / spectrumSize;
    
    // 频段划分（基于FFT bin索引）
    NSInteger bassEnd = (NSInteger)(250.0f / binWidth);
    NSInteger midEnd = (NSInteger)(4000.0f / binWidth);
    
    bassEnd = MIN(bassEnd, spectrumSize);
    midEnd = MIN(midEnd, spectrumSize);
    
    // 计算各频段能量
    float bassSum = 0, midSum = 0, highSum = 0, totalSum = 0;
    float weightedSum = 0;
    
    for (NSInteger i = 0; i < spectrumSize; i++) {
        float value = [spectrum[i] floatValue];
        float absValue = fabsf(value);
        totalSum += absValue;
        
        if (i < bassEnd) {
            bassSum += absValue;
        } else if (i < midEnd) {
            midSum += absValue;
        } else {
            highSum += absValue;
        }
        
        weightedSum += absValue * i;
    }
    
    // 归一化
    float bassEnergy = (bassEnd > 0) ? (bassSum / bassEnd) : 0;
    float midEnergy = (midEnd > bassEnd) ? (midSum / (midEnd - bassEnd)) : 0;
    float highEnergy = (spectrumSize > midEnd) ? (highSum / (spectrumSize - midEnd)) : 0;
    float totalEnergy = totalSum / spectrumSize;
    
    // 频谱重心（亮度指标）
    float spectralCentroid = (totalSum > 0) ? (weightedSum / totalSum / spectrumSize) : 0.5f;
    
    // 频谱变化率（与上一帧的差异）
    float spectralFlux = [self calculateSpectralFlux:spectrum];
    
    // EMA平滑
    self.smoothedEnergy = kEMAAlpha * totalEnergy + (1 - kEMAAlpha) * self.smoothedEnergy;
    self.smoothedBassEnergy = kEMAAlpha * bassEnergy + (1 - kEMAAlpha) * self.smoothedBassEnergy;
    self.smoothedMidEnergy = kEMAAlpha * midEnergy + (1 - kEMAAlpha) * self.smoothedMidEnergy;
    self.smoothedHighEnergy = kEMAAlpha * highEnergy + (1 - kEMAAlpha) * self.smoothedHighEnergy;
    
    // 限制到 [0, 1]
    features.energy = MIN(1.0f, self.smoothedEnergy * 3.0f);
    features.bassEnergy = MIN(1.0f, self.smoothedBassEnergy * 4.0f);
    features.midEnergy = MIN(1.0f, self.smoothedMidEnergy * 4.0f);
    features.highEnergy = MIN(1.0f, self.smoothedHighEnergy * 5.0f);
    features.spectralCentroid = spectralCentroid;
    features.spectralFlux = MIN(1.0f, spectralFlux * 5.0f);
    
    // 节拍检测
    features.beatDetected = [self detectBeat:bassEnergy atTime:currentTime];
    
    // BPM估算
    features.bpm = self.averageBPM;
    
    // 段落检测
    MusicSegment newSegment = [self detectSegment:features];
    features.currentSegment = newSegment;
    features.segmentChanged = (newSegment != self.previousSegment);
    
    if (features.segmentChanged) {
        [self notifySegmentChange:self.previousSegment to:newSegment];
        self.previousSegment = newSegment;
        self.segmentStartTime = currentTime;
    }
    
    // 保存当前频谱用于下一帧比较
    self.previousSpectrum = [spectrum mutableCopy];
    
    // 更新历史
    [self updateEnergyHistory:features.energy];
    
    // 更新当前特征
    self.currentFeatures = features;
    
    // 通知观察者
    [self notifyFeaturesUpdate:features];
    
    if (features.beatDetected) {
        [self notifyBeatDetected:currentTime];
    }
}

#pragma mark - Beat Detection

- (BOOL)detectBeat:(float)bassEnergy atTime:(NSTimeInterval)currentTime {
    // 动态阈值：基于历史能量平均值
    float threshold = self.beatThreshold * kBeatThresholdMultiplier;
    
    // 检测低频能量突增
    BOOL energySpike = (bassEnergy > self.lastBassEnergy * 1.5f) && (bassEnergy > threshold);
    
    // 最小间隔（避免重复检测，假设最快200 BPM = 300ms间隔）
    BOOL minIntervalPassed = (currentTime - self.lastBeatTime) > 0.25;
    
    self.lastBassEnergy = bassEnergy;
    
    if (energySpike && minIntervalPassed) {
        // 记录节拍时间
        [self.beatTimeHistory addObject:@(currentTime)];
        if (self.beatTimeHistory.count > kBeatHistorySize) {
            [self.beatTimeHistory removeObjectAtIndex:0];
        }
        
        // 计算BPM
        [self updateBPMEstimate];
        
        // 更新动态阈值
        [self updateBeatThreshold:bassEnergy];
        
        self.lastBeatTime = currentTime;
        return YES;
    }
    
    return NO;
}

- (void)updateBPMEstimate {
    if (self.beatTimeHistory.count < 4) return;
    
    // 计算节拍间隔
    NSMutableArray<NSNumber *> *intervals = [NSMutableArray array];
    for (NSInteger i = 1; i < self.beatTimeHistory.count; i++) {
        float interval = [self.beatTimeHistory[i] floatValue] - [self.beatTimeHistory[i-1] floatValue];
        if (interval > 0.2 && interval < 2.0) { // 30-300 BPM范围
            [intervals addObject:@(interval)];
        }
    }
    
    if (intervals.count == 0) return;
    
    // 计算平均间隔
    float sum = 0;
    for (NSNumber *interval in intervals) {
        sum += interval.floatValue;
    }
    float avgInterval = sum / intervals.count;
    
    // 转换为BPM
    float bpm = 60.0f / avgInterval;
    
    // 限制到合理范围
    bpm = MAX(60.0f, MIN(200.0f, bpm));
    
    // 平滑更新
    self.averageBPM = 0.1f * bpm + 0.9f * self.averageBPM;
}

- (void)updateBeatThreshold:(float)currentEnergy {
    // 自适应阈值
    self.beatThreshold = 0.8f * self.beatThreshold + 0.2f * currentEnergy * 0.7f;
    self.beatThreshold = MAX(0.1f, MIN(0.5f, self.beatThreshold));
}

#pragma mark - Spectral Flux

- (float)calculateSpectralFlux:(NSArray<NSNumber *> *)spectrum {
    if (self.previousSpectrum.count == 0 || self.previousSpectrum.count != spectrum.count) {
        return 0;
    }
    
    float flux = 0;
    for (NSInteger i = 0; i < spectrum.count; i++) {
        float diff = [spectrum[i] floatValue] - [self.previousSpectrum[i] floatValue];
        if (diff > 0) {
            flux += diff * diff;
        }
    }
    
    return sqrtf(flux / spectrum.count);
}

#pragma mark - Segment Detection

- (MusicSegment)detectSegment:(AudioFeatures *)features {
    NSTimeInterval currentTime = features.timestamp;
    NSTimeInterval timeSinceStart = currentTime - self.startTime;
    NSTimeInterval timeSinceSegmentStart = currentTime - self.segmentStartTime;
    
    // === 防抖动：段落必须保持最小时间 ===
    static const NSTimeInterval kMinSegmentDuration = 10.0;  // 最少10秒
    static const NSTimeInterval kMinChorusDuration = 15.0;   // 副歌至少15秒
    static const NSInteger kMaxChorusCount = 4;              // 一首歌最多4个副歌
    
    if (timeSinceSegmentStart < kMinSegmentDuration && self.previousSegment != MusicSegmentUnknown) {
        return self.previousSegment;
    }
    
    // 更新能量统计 (多时间尺度)
    float alphaLong = 0.005f;      // 长期 (~3秒)
    float alphaShort = 0.08f;      // 短期 (~0.2秒)
    
    self.longTermEnergy = alphaLong * features.energy + (1 - alphaLong) * self.longTermEnergy;
    self.shortTermEnergy = alphaShort * features.energy + (1 - alphaShort) * self.shortTermEnergy;
    
    // 更新能量包络历史
    [self.energyEnvelope addObject:@(features.energy)];
    if (self.energyEnvelope.count > 600) {  // 约10秒数据
        [self.energyEnvelope removeObjectAtIndex:0];
    }
    
    // 更新频谱对比历史
    float contrast = features.highEnergy - features.bassEnergy;
    [self.spectralContrast addObject:@(contrast)];
    if (self.spectralContrast.count > 600) {
        [self.spectralContrast removeObjectAtIndex:0];
    }
    
    // 计算统计量
    [self updateSegmentStatistics:features];
    
    // === 检测音乐类型：低能量音乐 vs 高能量音乐 ===
    BOOL isLowEnergyMusic = (self.peakEnergy < 0.4);
    
    // === 智能段落检测 ===
    
    // 1. 前奏检测 (开头15-30秒)
    if (!self.introDetected && timeSinceStart < 30.0) {
        // 前奏条件：时间早 + 能量相对较低
        float introThreshold = isLowEnergyMusic ? 
            (self.averageEnergy + 0.05) : 
            (self.chorusEnergyThreshold * 0.6);
        
        if (features.energy < introThreshold || timeSinceStart < 10.0) {
            return MusicSegmentIntro;
        }
        self.introDetected = YES;
    }
    
    // 2. 尾奏检测 (歌曲后期，能量持续下降)
    if (timeSinceStart > 90.0) {  // 至少1.5分钟后
        float recentEnergyTrend = [self calculateRecentEnergyTrend];
        
        // 能量持续下降
        if (recentEnergyTrend < -0.02 && 
            self.shortTermEnergy < self.averageEnergy * 0.6) {
            
            self.stableFrameCount++;
            if (self.stableFrameCount > 60) {  // 约1秒稳定
                return MusicSegmentOutro;
            }
        } else {
            self.stableFrameCount = 0;
        }
    }
    
    // 3. 副歌/高潮检测
    // 对于低能量音乐，使用相对能量比较
    float energyRatio = (self.averageEnergy > 0.01) ? 
        (features.energy / self.averageEnergy) : 1.0;
    
    float energyDelta = features.energy - self.averageEnergy;
    
    // 副歌特征评分
    float chorusScore = 0;
    
    if (isLowEnergyMusic) {
        // 低能量音乐：基于相对变化
        if (energyRatio > 1.3) chorusScore += 0.4;        // 能量比平均高30%
        if (energyDelta > 0.03) chorusScore += 0.3;       // 绝对差值
        if (features.spectralFlux > 0.2) chorusScore += 0.3;  // 频谱变化
    } else {
        // 高能量音乐：基于绝对值
        if (features.energy > self.chorusEnergyThreshold) chorusScore += 0.35;
        if (self.shortTermEnergy > self.longTermEnergy * 1.25) chorusScore += 0.25;
        if (features.highEnergy > 0.3) chorusScore += 0.2;
        if (features.bassEnergy > self.averageEnergy * 0.8) chorusScore += 0.2;
    }
    
    // 副歌检测阈值 (使用滞后效应防止震荡)
    float enterChorusThreshold = 0.7;   // 进入副歌需要高分
    float exitChorusThreshold = 0.4;    // 退出副歌需要低分
    
    BOOL inChorus = (self.previousSegment == MusicSegmentChorus);
    BOOL shouldBeChorus = inChorus ? 
        (chorusScore >= exitChorusThreshold) : 
        (chorusScore >= enterChorusThreshold);
    
    // 限制副歌数量
    if (shouldBeChorus && !inChorus && self.chorusCount >= kMaxChorusCount) {
        shouldBeChorus = NO;  // 已经有足够多的副歌了
    }
    
    // 副歌持续时间检查
    if (inChorus && timeSinceSegmentStart < kMinChorusDuration) {
        return MusicSegmentChorus;  // 副歌还没持续够时间
    }
    
    if (shouldBeChorus) {
        if (!inChorus) {
            self.chorusCount++;
            if (!self.firstChorusDetected) {
                self.firstChorusDetected = YES;
                self.firstChorusTime = currentTime;
                // 动态调整阈值
                self.chorusEnergyThreshold = features.energy * 0.9;
            }
        }
        return MusicSegmentChorus;
    }
    
    // 4. 过渡段检测
    // 从副歌出来后的短暂过渡
    if (self.previousSegment == MusicSegmentChorus && 
        timeSinceSegmentStart >= kMinSegmentDuration) {
        
        // 能量下降明显
        if (chorusScore < 0.35 && energyRatio < 1.1) {
            return MusicSegmentBridge;
        }
    }
    
    // 5. 主歌（默认状态）
    // 从前奏进入主歌
    if (self.previousSegment == MusicSegmentIntro && timeSinceSegmentStart >= kMinSegmentDuration) {
        return MusicSegmentVerse;
    }
    
    // 从过渡段进入主歌
    if (self.previousSegment == MusicSegmentBridge && timeSinceSegmentStart >= kMinSegmentDuration) {
        return MusicSegmentVerse;
    }
    
    // 从副歌回到主歌（经过过渡段或直接）
    if (self.previousSegment == MusicSegmentChorus && 
        timeSinceSegmentStart >= kMinSegmentDuration &&
        !shouldBeChorus) {
        return MusicSegmentVerse;
    }
    
    // 保持当前段落
    if (self.previousSegment != MusicSegmentUnknown) {
        return self.previousSegment;
    }
    
    return MusicSegmentVerse;
}

#pragma mark - Segment Analysis Helpers

- (void)updateSegmentStatistics:(AudioFeatures *)features {
    // 更新峰值能量
    if (features.energy > self.peakEnergy) {
        self.peakEnergy = features.energy;
        // 动态调整副歌阈值
        self.chorusEnergyThreshold = self.peakEnergy * 0.75;
    }
    
    // 计算平均能量（使用长期滑动平均）
    if (self.energyEnvelope.count > 0) {
        float sum = 0;
        for (NSNumber *e in self.energyEnvelope) {
            sum += e.floatValue;
        }
        self.averageEnergy = sum / self.energyEnvelope.count;
        
        // 计算能量方差
        float variance = 0;
        for (NSNumber *e in self.energyEnvelope) {
            float diff = e.floatValue - self.averageEnergy;
            variance += diff * diff;
        }
        self.energyVariance = variance / self.energyEnvelope.count;
    }
}

- (float)calculateRecentEnergyTrend {
    // 计算最近能量的趋势（正=上升，负=下降）
    if (self.energyEnvelope.count < 60) return 0;  // 至少需要1秒数据
    
    NSInteger recentCount = MIN(60, self.energyEnvelope.count);
    NSInteger startIdx = self.energyEnvelope.count - recentCount;
    
    float firstHalf = 0, secondHalf = 0;
    NSInteger halfCount = recentCount / 2;
    
    for (NSInteger i = 0; i < halfCount; i++) {
        firstHalf += [self.energyEnvelope[startIdx + i] floatValue];
        secondHalf += [self.energyEnvelope[startIdx + halfCount + i] floatValue];
    }
    
    firstHalf /= halfCount;
    secondHalf /= halfCount;
    
    return secondHalf - firstHalf;
}

- (float)calculateSpectralChange {
    // 计算频谱对比度的变化
    if (self.spectralContrast.count < 30) return 0;
    
    NSInteger recentCount = MIN(30, self.spectralContrast.count);
    NSInteger startIdx = self.spectralContrast.count - recentCount;
    
    float maxChange = 0;
    float prevContrast = [self.spectralContrast[startIdx] floatValue];
    
    for (NSInteger i = 1; i < recentCount; i++) {
        float currentContrast = [self.spectralContrast[startIdx + i] floatValue];
        float change = fabsf(currentContrast - prevContrast);
        if (change > maxChange) {
            maxChange = change;
        }
        prevContrast = currentContrast;
    }
    
    return maxChange;
}

#pragma mark - Energy History

- (void)updateEnergyHistory:(float)energy {
    [self.energyHistory addObject:@(energy)];
    if (self.energyHistory.count > kEnergyHistorySize) {
        [self.energyHistory removeObjectAtIndex:0];
    }
}

#pragma mark - Observer Management

- (void)addObserver:(id<AudioFeatureObserver>)observer {
    [self.observers addObject:observer];
}

- (void)removeObserver:(id<AudioFeatureObserver>)observer {
    [self.observers removeObject:observer];
}

- (void)notifyFeaturesUpdate:(AudioFeatures *)features {
    for (id<AudioFeatureObserver> observer in self.observers) {
        if ([observer respondsToSelector:@selector(audioFeatureExtractor:didUpdateFeatures:)]) {
            [observer audioFeatureExtractor:self didUpdateFeatures:features];
        }
    }
}

- (void)notifyBeatDetected:(NSTimeInterval)time {
    for (id<AudioFeatureObserver> observer in self.observers) {
        if ([observer respondsToSelector:@selector(audioFeatureExtractor:didDetectBeatAtTime:)]) {
            [observer audioFeatureExtractor:self didDetectBeatAtTime:time];
        }
    }
}

- (void)notifySegmentChange:(MusicSegment)oldSegment to:(MusicSegment)newSegment {
    NSString *oldName = [self segmentNameForType:oldSegment];
    NSString *newName = [self segmentNameForType:newSegment];
    
    NSLog(@"🎭 段落变化: %@ → %@ (能量:%.2f, 峰值:%.2f, 平均:%.2f, 副歌次数:%ld)",
          oldName, newName, 
          self.shortTermEnergy, self.peakEnergy, self.averageEnergy,
          (long)self.chorusCount);
    
    // 记录段落历史
    [self.segmentHistory addObject:@{
        @"from": @(oldSegment),
        @"to": @(newSegment),
        @"time": @(self.currentFeatures.timestamp),
        @"energy": @(self.shortTermEnergy)
    }];
    
    for (id<AudioFeatureObserver> observer in self.observers) {
        if ([observer respondsToSelector:@selector(audioFeatureExtractor:didChangeSegmentFrom:to:)]) {
            [observer audioFeatureExtractor:self didChangeSegmentFrom:oldSegment to:newSegment];
        }
    }
}

- (NSString *)segmentNameForType:(MusicSegment)segment {
    switch (segment) {
        case MusicSegmentIntro: return @"前奏";
        case MusicSegmentVerse: return @"主歌";
        case MusicSegmentChorus: return @"副歌";
        case MusicSegmentBridge: return @"过渡";
        case MusicSegmentOutro: return @"尾奏";
        default: return @"未知";
    }
}

@end
