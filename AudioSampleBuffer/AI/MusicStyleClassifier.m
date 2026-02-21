//
//  MusicStyleClassifier.m
//  AudioSampleBuffer
//

#import "MusicStyleClassifier.h"

static const NSInteger kHistorySize = 60;  // 约2秒的累积数据（30fps）

@implementation MusicStyleResult

+ (instancetype)resultWithStyle:(MusicStyle)style confidence:(float)confidence {
    MusicStyleResult *result = [[MusicStyleResult alloc] init];
    result.primaryStyle = style;
    result.primaryConfidence = confidence;
    result.secondaryStyle = MusicStyleUnknown;
    result.secondaryConfidence = 0;
    result.styleProbabilities = @{@(style): @(confidence)};
    return result;
}

@end

@interface MusicStyleClassifier ()

@property (nonatomic, strong) MusicStyleResult *currentResult;

// 累积数据
@property (nonatomic, strong) NSMutableArray<NSNumber *> *energyHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *bassEnergyHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *highEnergyHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *spectralFluxHistory;
@property (nonatomic, strong) NSMutableArray<NSNumber *> *bpmHistory;

// 风格关键词
@property (nonatomic, strong) NSDictionary<NSString *, NSNumber *> *styleKeywords;

@end

@implementation MusicStyleClassifier

+ (instancetype)sharedClassifier {
    static MusicStyleClassifier *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MusicStyleClassifier alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentResult = [MusicStyleResult resultWithStyle:MusicStyleUnknown confidence:0];
        _energyHistory = [NSMutableArray arrayWithCapacity:kHistorySize];
        _bassEnergyHistory = [NSMutableArray arrayWithCapacity:kHistorySize];
        _highEnergyHistory = [NSMutableArray arrayWithCapacity:kHistorySize];
        _spectralFluxHistory = [NSMutableArray arrayWithCapacity:kHistorySize];
        _bpmHistory = [NSMutableArray arrayWithCapacity:kHistorySize];
        
        [self setupStyleKeywords];
    }
    return self;
}

- (void)setupStyleKeywords {
    self.styleKeywords = @{
        // 电子/EDM
        @"edm": @(MusicStyleElectronic),
        @"electronic": @(MusicStyleElectronic),
        @"电子": @(MusicStyleElectronic),
        @"techno": @(MusicStyleElectronic),
        @"house": @(MusicStyleElectronic),
        @"trance": @(MusicStyleElectronic),
        @"dubstep": @(MusicStyleElectronic),
        @"synthwave": @(MusicStyleElectronic),
        
        // 摇滚
        @"rock": @(MusicStyleRock),
        @"摇滚": @(MusicStyleRock),
        @"punk": @(MusicStyleRock),
        @"grunge": @(MusicStyleRock),
        @"alternative": @(MusicStyleRock),
        
        // 金属
        @"metal": @(MusicStyleMetal),
        @"重金属": @(MusicStyleMetal),
        @"metalcore": @(MusicStyleMetal),
        @"hardcore": @(MusicStyleMetal),
        
        // 古典
        @"classical": @(MusicStyleClassical),
        @"古典": @(MusicStyleClassical),
        @"symphony": @(MusicStyleClassical),
        @"交响": @(MusicStyleClassical),
        @"orchestra": @(MusicStyleClassical),
        @"piano": @(MusicStyleClassical),
        @"钢琴": @(MusicStyleClassical),
        @"violin": @(MusicStyleClassical),
        
        // 爵士
        @"jazz": @(MusicStyleJazz),
        @"爵士": @(MusicStyleJazz),
        @"swing": @(MusicStyleJazz),
        @"blues": @(MusicStyleJazz),
        @"蓝调": @(MusicStyleJazz),
        
        // 嘻哈
        @"hip hop": @(MusicStyleHipHop),
        @"hiphop": @(MusicStyleHipHop),
        @"rap": @(MusicStyleHipHop),
        @"说唱": @(MusicStyleHipHop),
        @"嘻哈": @(MusicStyleHipHop),
        @"trap": @(MusicStyleHipHop),
        
        // 流行
        @"pop": @(MusicStylePop),
        @"流行": @(MusicStylePop),
        
        // 氛围
        @"ambient": @(MusicStyleAmbient),
        @"氛围": @(MusicStyleAmbient),
        @"chill": @(MusicStyleAmbient),
        @"轻音乐": @(MusicStyleAmbient),
        @"meditation": @(MusicStyleAmbient),
        @"relax": @(MusicStyleAmbient),
        
        // R&B
        @"r&b": @(MusicStyleRnB),
        @"rnb": @(MusicStyleRnB),
        @"soul": @(MusicStyleRnB),
        
        // 舞曲
        @"dance": @(MusicStyleDance),
        @"disco": @(MusicStyleDance),
        @"舞曲": @(MusicStyleDance),
        
        // 乡村
        @"country": @(MusicStyleCountry),
        @"乡村": @(MusicStyleCountry),
        @"folk": @(MusicStyleCountry),
        @"民谣": @(MusicStyleCountry),
        
        // 原声
        @"acoustic": @(MusicStyleAcoustic),
        @"原声": @(MusicStyleAcoustic),
        @"unplugged": @(MusicStyleAcoustic),
    };
}

- (void)reset {
    [self.energyHistory removeAllObjects];
    [self.bassEnergyHistory removeAllObjects];
    [self.highEnergyHistory removeAllObjects];
    [self.spectralFluxHistory removeAllObjects];
    [self.bpmHistory removeAllObjects];
    self.currentResult = [MusicStyleResult resultWithStyle:MusicStyleUnknown confidence:0];
}

#pragma mark - Classification

- (MusicStyleResult *)classifyWithFeatures:(AudioFeatures *)features {
    return [self classifyWithFeatures:features accumulate:YES];
}

- (MusicStyleResult *)classifyWithFeatures:(AudioFeatures *)features accumulate:(BOOL)accumulate {
    if (accumulate) {
        [self updateHistory:features];
    }
    
    // 使用累积数据进行分类
    float avgEnergy = [self averageOfHistory:self.energyHistory];
    float avgBass = [self averageOfHistory:self.bassEnergyHistory];
    float avgHigh = [self averageOfHistory:self.highEnergyHistory];
    float avgFlux = [self averageOfHistory:self.spectralFluxHistory];
    float avgBPM = [self averageOfHistory:self.bpmHistory];
    
    // 如果没有足够的历史数据，使用当前值
    if (self.energyHistory.count < 10) {
        avgEnergy = features.energy;
        avgBass = features.bassEnergy;
        avgHigh = features.highEnergy;
        avgFlux = features.spectralFlux;
        avgBPM = features.bpm;
    }
    
    // 计算各风格的概率
    NSMutableDictionary<NSNumber *, NSNumber *> *probabilities = [NSMutableDictionary dictionary];
    
    // Electronic: 高能量 + 强低音 + 快节奏
    float electronicScore = [self scoreForElectronic:avgEnergy bass:avgBass bpm:avgBPM flux:avgFlux];
    probabilities[@(MusicStyleElectronic)] = @(electronicScore);
    
    // Rock: 高能量 + 中等低音 + 高频丰富
    float rockScore = [self scoreForRock:avgEnergy bass:avgBass high:avgHigh flux:avgFlux];
    probabilities[@(MusicStyleRock)] = @(rockScore);
    
    // Metal: 极高能量 + 全频段高
    float metalScore = [self scoreForMetal:avgEnergy bass:avgBass high:avgHigh bpm:avgBPM];
    probabilities[@(MusicStyleMetal)] = @(metalScore);
    
    // Classical: 低能量变化 + 动态范围大 + 无明显节拍
    float classicalScore = [self scoreForClassical:avgEnergy flux:avgFlux bpm:avgBPM];
    probabilities[@(MusicStyleClassical)] = @(classicalScore);
    
    // Jazz: 中等能量 + 复杂节奏
    float jazzScore = [self scoreForJazz:avgEnergy flux:avgFlux bpm:avgBPM];
    probabilities[@(MusicStyleJazz)] = @(jazzScore);
    
    // HipHop: 强低音 + 规律节拍 (80-110 BPM)
    float hiphopScore = [self scoreForHipHop:avgBass bpm:avgBPM flux:avgFlux];
    probabilities[@(MusicStyleHipHop)] = @(hiphopScore);
    
    // Pop: 中等能量 + 中等节奏
    float popScore = [self scoreForPop:avgEnergy bass:avgBass bpm:avgBPM];
    probabilities[@(MusicStylePop)] = @(popScore);
    
    // Ambient: 低能量 + 低变化
    float ambientScore = [self scoreForAmbient:avgEnergy flux:avgFlux];
    probabilities[@(MusicStyleAmbient)] = @(ambientScore);
    
    // Dance: 高能量 + 强节拍 + 快节奏
    float danceScore = [self scoreForDance:avgEnergy bass:avgBass bpm:avgBPM];
    probabilities[@(MusicStyleDance)] = @(danceScore);
    
    // R&B: 中等能量 + 强低音 + 中等节奏
    float rnbScore = [self scoreForRnB:avgEnergy bass:avgBass bpm:avgBPM];
    probabilities[@(MusicStyleRnB)] = @(rnbScore);
    
    // 找出最高分的两个风格
    NSArray *sortedStyles = [probabilities.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *key1, NSNumber *key2) {
        return [probabilities[key2] compare:probabilities[key1]];
    }];
    
    MusicStyleResult *result = [[MusicStyleResult alloc] init];
    result.styleProbabilities = [probabilities copy];
    
    if (sortedStyles.count > 0) {
        result.primaryStyle = [sortedStyles[0] unsignedIntegerValue];
        result.primaryConfidence = [probabilities[sortedStyles[0]] floatValue];
    }
    
    if (sortedStyles.count > 1) {
        result.secondaryStyle = [sortedStyles[1] unsignedIntegerValue];
        result.secondaryConfidence = [probabilities[sortedStyles[1]] floatValue];
    }
    
    self.currentResult = result;
    return result;
}

#pragma mark - Style Scoring

- (float)scoreForElectronic:(float)energy bass:(float)bass bpm:(float)bpm flux:(float)flux {
    float score = 0;
    
    if (energy > 0.5) score += 0.3 * (energy - 0.5) * 2;
    if (bass > 0.6) score += 0.3 * (bass - 0.6) * 2.5;
    if (bpm >= 120 && bpm <= 150) score += 0.2;
    if (flux > 0.3) score += 0.2 * flux;
    
    return MIN(1.0, score);
}

- (float)scoreForRock:(float)energy bass:(float)bass high:(float)high flux:(float)flux {
    float score = 0;
    
    if (energy > 0.5) score += 0.25 * (energy - 0.5) * 2;
    if (bass > 0.4 && bass < 0.7) score += 0.2;
    if (high > 0.5) score += 0.25 * high;
    if (flux > 0.4) score += 0.3 * flux;
    
    return MIN(1.0, score);
}

- (float)scoreForMetal:(float)energy bass:(float)bass high:(float)high bpm:(float)bpm {
    float score = 0;
    
    if (energy > 0.7) score += 0.4 * (energy - 0.7) * 3.3;
    if (bass > 0.6) score += 0.2 * (bass - 0.6) * 2.5;
    if (high > 0.6) score += 0.2 * (high - 0.6) * 2.5;
    if (bpm >= 140) score += 0.2;
    
    return MIN(1.0, score);
}

- (float)scoreForClassical:(float)energy flux:(float)flux bpm:(float)bpm {
    float score = 0;
    
    if (energy < 0.4) score += 0.3 * (0.4 - energy) * 2.5;
    if (flux < 0.3) score += 0.3 * (0.3 - flux) * 3.3;
    if (bpm < 100 || bpm > 150) score += 0.2; // 古典节奏不规律
    
    // 能量变化大加分
    float energyVariance = [self varianceOfHistory:self.energyHistory];
    if (energyVariance > 0.05) score += 0.2;
    
    return MIN(1.0, score);
}

- (float)scoreForJazz:(float)energy flux:(float)flux bpm:(float)bpm {
    float score = 0;
    
    if (energy > 0.3 && energy < 0.6) score += 0.3;
    if (flux > 0.2 && flux < 0.5) score += 0.3;
    if (bpm >= 100 && bpm <= 160) score += 0.2;
    
    // 节奏复杂度
    float bpmVariance = [self varianceOfHistory:self.bpmHistory];
    if (bpmVariance > 10) score += 0.2;
    
    return MIN(1.0, score);
}

- (float)scoreForHipHop:(float)bass bpm:(float)bpm flux:(float)flux {
    float score = 0;
    
    if (bass > 0.6) score += 0.4 * (bass - 0.6) * 2.5;
    if (bpm >= 80 && bpm <= 110) score += 0.3;
    if (flux < 0.4) score += 0.3 * (0.4 - flux) * 2.5; // 节奏规律
    
    return MIN(1.0, score);
}

- (float)scoreForPop:(float)energy bass:(float)bass bpm:(float)bpm {
    float score = 0;
    
    if (energy > 0.3 && energy < 0.7) score += 0.35;
    if (bass > 0.3 && bass < 0.6) score += 0.25;
    if (bpm >= 100 && bpm <= 130) score += 0.4;
    
    return MIN(1.0, score);
}

- (float)scoreForAmbient:(float)energy flux:(float)flux {
    float score = 0;
    
    if (energy < 0.3) score += 0.5 * (0.3 - energy) * 3.3;
    if (flux < 0.2) score += 0.5 * (0.2 - flux) * 5;
    
    return MIN(1.0, score);
}

- (float)scoreForDance:(float)energy bass:(float)bass bpm:(float)bpm {
    float score = 0;
    
    if (energy > 0.6) score += 0.3 * (energy - 0.6) * 2.5;
    if (bass > 0.5) score += 0.3 * (bass - 0.5) * 2;
    if (bpm >= 120 && bpm <= 140) score += 0.4;
    
    return MIN(1.0, score);
}

- (float)scoreForRnB:(float)energy bass:(float)bass bpm:(float)bpm {
    float score = 0;
    
    if (energy > 0.3 && energy < 0.6) score += 0.3;
    if (bass > 0.5) score += 0.3 * bass;
    if (bpm >= 70 && bpm <= 100) score += 0.4;
    
    return MIN(1.0, score);
}

#pragma mark - Preclassify by Name

- (nullable MusicStyleResult *)preclassifyWithSongName:(NSString *)songName artist:(nullable NSString *)artist {
    NSString *searchText = [[NSString stringWithFormat:@"%@ %@", songName, artist ?: @""] lowercaseString];
    
    MusicStyle matchedStyle = MusicStyleUnknown;
    float confidence = 0;
    
    for (NSString *keyword in self.styleKeywords) {
        if ([searchText containsString:keyword]) {
            matchedStyle = [self.styleKeywords[keyword] unsignedIntegerValue];
            confidence = 0.6; // 基于关键词的预分类置信度较低
            break;
        }
    }
    
    if (matchedStyle == MusicStyleUnknown) {
        return nil;
    }
    
    return [MusicStyleResult resultWithStyle:matchedStyle confidence:confidence];
}

#pragma mark - History Management

- (void)updateHistory:(AudioFeatures *)features {
    [self.energyHistory addObject:@(features.energy)];
    [self.bassEnergyHistory addObject:@(features.bassEnergy)];
    [self.highEnergyHistory addObject:@(features.highEnergy)];
    [self.spectralFluxHistory addObject:@(features.spectralFlux)];
    [self.bpmHistory addObject:@(features.bpm)];
    
    if (self.energyHistory.count > kHistorySize) {
        [self.energyHistory removeObjectAtIndex:0];
        [self.bassEnergyHistory removeObjectAtIndex:0];
        [self.highEnergyHistory removeObjectAtIndex:0];
        [self.spectralFluxHistory removeObjectAtIndex:0];
        [self.bpmHistory removeObjectAtIndex:0];
    }
}

- (float)averageOfHistory:(NSArray<NSNumber *> *)history {
    if (history.count == 0) return 0;
    
    float sum = 0;
    for (NSNumber *value in history) {
        sum += value.floatValue;
    }
    return sum / history.count;
}

- (float)varianceOfHistory:(NSArray<NSNumber *> *)history {
    if (history.count < 2) return 0;
    
    float mean = [self averageOfHistory:history];
    float sumSquares = 0;
    
    for (NSNumber *value in history) {
        float diff = value.floatValue - mean;
        sumSquares += diff * diff;
    }
    
    return sumSquares / history.count;
}

#pragma mark - Utility

+ (NSString *)nameForStyle:(MusicStyle)style {
    switch (style) {
        case MusicStyleUnknown: return @"未知";
        case MusicStyleElectronic: return @"电子";
        case MusicStyleRock: return @"摇滚";
        case MusicStyleClassical: return @"古典";
        case MusicStylePop: return @"流行";
        case MusicStyleJazz: return @"爵士";
        case MusicStyleHipHop: return @"嘻哈";
        case MusicStyleAmbient: return @"氛围";
        case MusicStyleMetal: return @"金属";
        case MusicStyleRnB: return @"R&B";
        case MusicStyleCountry: return @"乡村";
        case MusicStyleDance: return @"舞曲";
        case MusicStyleAcoustic: return @"原声";
        default: return @"未知";
    }
}

+ (void)getEnergyRangeForStyle:(MusicStyle)style minEnergy:(float *)minEnergy maxEnergy:(float *)maxEnergy {
    switch (style) {
        case MusicStyleElectronic:
        case MusicStyleDance:
        case MusicStyleMetal:
            *minEnergy = 0.6; *maxEnergy = 1.0;
            break;
        case MusicStyleRock:
            *minEnergy = 0.5; *maxEnergy = 0.9;
            break;
        case MusicStyleHipHop:
        case MusicStylePop:
        case MusicStyleRnB:
            *minEnergy = 0.4; *maxEnergy = 0.7;
            break;
        case MusicStyleJazz:
        case MusicStyleCountry:
        case MusicStyleAcoustic:
            *minEnergy = 0.3; *maxEnergy = 0.6;
            break;
        case MusicStyleClassical:
            *minEnergy = 0.1; *maxEnergy = 0.8;
            break;
        case MusicStyleAmbient:
            *minEnergy = 0.0; *maxEnergy = 0.3;
            break;
        default:
            *minEnergy = 0.0; *maxEnergy = 1.0;
            break;
    }
}

@end
