//
//  AgentReflectionEngine.m
//  AudioSampleBuffer
//
//  反思引擎实现
//

#import "AgentReflectionEngine.h"

static NSString *const kReflectionRecordsFile = @"ReflectionRecords.plist";
static const NSInteger kMaxRecords = 500;

#pragma mark - ReflectionDecisionRecord

@implementation ReflectionDecisionRecord

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)recordWithSource:(DecisionSource)source
                       wasCorrect:(BOOL)correct
                           style:(MusicStyle)style
                          effect:(VisualEffectType)effect {
    ReflectionDecisionRecord *record = [[ReflectionDecisionRecord alloc] init];
    record.source = source;
    record.wasCorrect = correct;
    record.style = style;
    record.effect = effect;
    record.timestamp = [NSDate date];
    return record;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.source forKey:@"source"];
    [coder encodeBool:self.wasCorrect forKey:@"wasCorrect"];
    [coder encodeInteger:self.style forKey:@"style"];
    [coder encodeInteger:self.effect forKey:@"effect"];
    [coder encodeFloat:self.confidence forKey:@"confidence"];
    [coder encodeDouble:self.decisionTime forKey:@"decisionTime"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
    [coder encodeObject:self.songName forKey:@"songName"];
    [coder encodeBool:self.userOverrode forKey:@"userOverrode"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _source = [coder decodeIntegerForKey:@"source"];
        _wasCorrect = [coder decodeBoolForKey:@"wasCorrect"];
        _style = [coder decodeIntegerForKey:@"style"];
        _effect = [coder decodeIntegerForKey:@"effect"];
        _confidence = [coder decodeFloatForKey:@"confidence"];
        _decisionTime = [coder decodeDoubleForKey:@"decisionTime"];
        _timestamp = [coder decodeObjectOfClass:[NSDate class] forKey:@"timestamp"];
        _songName = [coder decodeObjectOfClass:[NSString class] forKey:@"songName"];
        _userOverrode = [coder decodeBoolForKey:@"userOverrode"];
    }
    return self;
}

- (NSString *)description {
    NSArray *sourceNames = @[@"UserPref", @"LocalRules", @"LLMCache", @"LLMRealtime", @"Fallback", @"SelfLearning"];
    NSString *sourceName = (self.source < sourceNames.count) ? sourceNames[self.source] : @"Unknown";
    return [NSString stringWithFormat:@"<ReflectionRecord: %@ correct=%@ effect=%lu>",
            sourceName, self.wasCorrect ? @"YES" : @"NO", (unsigned long)self.effect];
}

@end

#pragma mark - SourceAccuracyStats

@implementation SourceAccuracyStats

- (instancetype)init {
    self = [super init];
    if (self) {
        _totalCount = 0;
        _correctCount = 0;
        _accuracy = 0.0;
        _averageConfidence = 0.0;
        _averageDecisionTime = 0.0;
    }
    return self;
}

- (void)updateWithCorrect:(BOOL)correct confidence:(float)confidence time:(NSTimeInterval)time {
    float totalConfidence = self.averageConfidence * self.totalCount;
    float totalTime = self.averageDecisionTime * self.totalCount;
    
    self.totalCount++;
    if (correct) {
        self.correctCount++;
    }
    
    self.accuracy = (self.totalCount > 0) ? (float)self.correctCount / (float)self.totalCount : 0;
    self.averageConfidence = (totalConfidence + confidence) / self.totalCount;
    self.averageDecisionTime = (totalTime + time) / self.totalCount;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<Stats: %ld/%ld (%.1f%%) conf=%.2f time=%.2fs>",
            (long)self.correctCount, (long)self.totalCount, self.accuracy * 100,
            self.averageConfidence, self.averageDecisionTime];
}

@end

#pragma mark - ReflectionAnalysisResult

@implementation ReflectionAnalysisResult

- (instancetype)init {
    self = [super init];
    if (self) {
        _sourceStats = [NSDictionary dictionary];
        _insights = [NSArray array];
        _styleProblemRates = [NSDictionary dictionary];
    }
    return self;
}

@end

#pragma mark - ReflectionThresholds

@implementation ReflectionThresholds

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)defaultThresholds {
    ReflectionThresholds *t = [[ReflectionThresholds alloc] init];
    t.emergencyAccuracyThreshold = 0.5;
    t.highOverrideRateThreshold = 0.7;
    t.lowSourceAccuracyThreshold = 0.4;
    t.highSourceAccuracyThreshold = 0.8;
    t.styleProblemsThreshold = 0.4;
    t.adjustmentStep = 0.1;
    t.minRecordsForAdjustment = 10;
    return t;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeFloat:self.emergencyAccuracyThreshold forKey:@"emergencyAccuracyThreshold"];
    [coder encodeFloat:self.highOverrideRateThreshold forKey:@"highOverrideRateThreshold"];
    [coder encodeFloat:self.lowSourceAccuracyThreshold forKey:@"lowSourceAccuracyThreshold"];
    [coder encodeFloat:self.highSourceAccuracyThreshold forKey:@"highSourceAccuracyThreshold"];
    [coder encodeFloat:self.styleProblemsThreshold forKey:@"styleProblemsThreshold"];
    [coder encodeFloat:self.adjustmentStep forKey:@"adjustmentStep"];
    [coder encodeInteger:self.minRecordsForAdjustment forKey:@"minRecordsForAdjustment"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _emergencyAccuracyThreshold = [coder decodeFloatForKey:@"emergencyAccuracyThreshold"];
        _highOverrideRateThreshold = [coder decodeFloatForKey:@"highOverrideRateThreshold"];
        _lowSourceAccuracyThreshold = [coder decodeFloatForKey:@"lowSourceAccuracyThreshold"];
        _highSourceAccuracyThreshold = [coder decodeFloatForKey:@"highSourceAccuracyThreshold"];
        _styleProblemsThreshold = [coder decodeFloatForKey:@"styleProblemsThreshold"];
        _adjustmentStep = [coder decodeFloatForKey:@"adjustmentStep"];
        _minRecordsForAdjustment = [coder decodeIntegerForKey:@"minRecordsForAdjustment"];
    }
    return self;
}

@end

#pragma mark - StrategyAdjustment

@implementation StrategyAdjustment

+ (instancetype)adjustmentWithType:(StrategyAdjustmentType)type
                          priority:(float)priority
                            reason:(NSString *)reason {
    StrategyAdjustment *adj = [[StrategyAdjustment alloc] init];
    adj.type = type;
    adj.priority = priority;
    adj.reason = reason;
    return adj;
}

- (NSString *)description {
    NSArray *typeNames = @[@"ReduceLLM", @"IncreaseLLM", @"IncreaseRule", @"ReduceRule", @"ExpandCache", 
                           @"EnhanceLearning", @"StyleSpecific", @"Emergency", @"IncreaseUserPref"];
    NSString *typeName = (self.type < typeNames.count) ? typeNames[self.type] : @"Unknown";
    return [NSString stringWithFormat:@"<StrategyAdjustment: %@ priority=%.2f reason=%@>", typeName, self.priority, self.reason];
}

@end

#pragma mark - AgentReflectionEngine

@interface AgentReflectionEngine ()

@property (nonatomic, strong) NSMutableArray<ReflectionDecisionRecord *> *mutableDecisionRecords;
@property (nonatomic, strong) ReflectionAnalysisResult *lastAnalysisResult;
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, assign) BOOL isEmergencyMode;

@end

@implementation AgentReflectionEngine

#pragma mark - Singleton

+ (instancetype)sharedEngine {
    static AgentReflectionEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AgentReflectionEngine alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _mutableDecisionRecords = [NSMutableArray array];
        _thresholds = [self loadThresholds] ?: [ReflectionThresholds defaultThresholds];
        _isEmergencyMode = NO;
        [self setupCacheDirectory];
        [self loadRecords];
    }
    return self;
}

- (void)setupCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    self.cacheDirectory = [cachesDir stringByAppendingPathComponent:@"AgentReflection"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectory]) {
        [fm createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (NSArray<ReflectionDecisionRecord *> *)decisionRecords {
    return [self.mutableDecisionRecords copy];
}

#pragma mark - Record Decisions

- (void)recordDecision:(ReflectionDecisionRecord *)record {
    [self.mutableDecisionRecords addObject:record];
    
    while (self.mutableDecisionRecords.count > kMaxRecords) {
        [self.mutableDecisionRecords removeObjectAtIndex:0];
    }
    
    [self saveRecords];
    
    NSLog(@"🔍 Reflection: 记录决策 %@", record);
}

- (void)recordDecisionOutcome:(NSString *)songName
                  userOverrode:(BOOL)overrode
                    newEffect:(VisualEffectType)newEffect {
    // 找到最近的该歌曲的决策记录并更新
    for (NSInteger i = self.mutableDecisionRecords.count - 1; i >= 0; i--) {
        ReflectionDecisionRecord *record = self.mutableDecisionRecords[i];
        if ([record.songName isEqualToString:songName]) {
            record.userOverrode = overrode;
            record.wasCorrect = !overrode;
            [self saveRecords];
            
            NSLog(@"🔍 Reflection: 更新决策结果 %@ -> %@", songName, overrode ? @"用户覆盖" : @"保持");
            break;
        }
    }
}

- (void)recordDecisions:(NSArray<ReflectionDecisionRecord *> *)records {
    [self.mutableDecisionRecords addObjectsFromArray:records];
    
    while (self.mutableDecisionRecords.count > kMaxRecords) {
        [self.mutableDecisionRecords removeObjectAtIndex:0];
    }
    
    [self saveRecords];
}

#pragma mark - Analysis

- (ReflectionAnalysisResult *)analyzeAllRecords {
    return [self analyzeRecords:self.mutableDecisionRecords];
}

- (ReflectionAnalysisResult *)analyzeRecordsFromDate:(NSDate *)fromDate toDate:(NSDate *)toDate {
    NSMutableArray *filteredRecords = [NSMutableArray array];
    
    for (ReflectionDecisionRecord *record in self.mutableDecisionRecords) {
        if ([record.timestamp compare:fromDate] != NSOrderedAscending &&
            [record.timestamp compare:toDate] != NSOrderedDescending) {
            [filteredRecords addObject:record];
        }
    }
    
    return [self analyzeRecords:filteredRecords];
}

- (ReflectionAnalysisResult *)analyzeRecordsForStyle:(MusicStyle)style {
    NSMutableArray *filteredRecords = [NSMutableArray array];
    
    for (ReflectionDecisionRecord *record in self.mutableDecisionRecords) {
        if (record.style == style) {
            [filteredRecords addObject:record];
        }
    }
    
    return [self analyzeRecords:filteredRecords];
}

- (ReflectionAnalysisResult *)analyzeRecords:(NSArray<ReflectionDecisionRecord *> *)records {
    ReflectionAnalysisResult *result = [[ReflectionAnalysisResult alloc] init];
    
    if (records.count == 0) {
        return result;
    }
    
    // 按来源分组统计
    NSMutableDictionary<NSNumber *, SourceAccuracyStats *> *sourceStats = [NSMutableDictionary dictionary];
    
    // 初始化各来源统计
    for (NSInteger i = 0; i <= DecisionSourceSelfLearning; i++) {
        sourceStats[@(i)] = [[SourceAccuracyStats alloc] init];
    }
    
    // 按风格统计问题率
    NSMutableDictionary<NSNumber *, NSNumber *> *styleProblems = [NSMutableDictionary dictionary];
    NSMutableDictionary<NSNumber *, NSNumber *> *styleTotals = [NSMutableDictionary dictionary];
    
    NSInteger totalCorrect = 0;
    
    for (ReflectionDecisionRecord *record in records) {
        // 更新来源统计
        SourceAccuracyStats *stats = sourceStats[@(record.source)];
        [stats updateWithCorrect:record.wasCorrect confidence:record.confidence time:record.decisionTime];
        
        if (record.wasCorrect) {
            totalCorrect++;
        }
        
        // 更新风格问题统计
        NSNumber *styleKey = @(record.style);
        NSInteger problems = [styleProblems[styleKey] integerValue];
        NSInteger total = [styleTotals[styleKey] integerValue];
        
        if (!record.wasCorrect) {
            problems++;
        }
        total++;
        
        styleProblems[styleKey] = @(problems);
        styleTotals[styleKey] = @(total);
    }
    
    result.sourceStats = sourceStats;
    result.totalRecords = records.count;
    result.overallAccuracy = (float)totalCorrect / (float)records.count;
    result.overrideRate = 1.0 - result.overallAccuracy;  // 覆盖率 = 1 - 准确率
    
    // 提取各来源准确率
    SourceAccuracyStats *llmStats = sourceStats[@(DecisionSourceLLMRealtime)];
    SourceAccuracyStats *llmCacheStats = sourceStats[@(DecisionSourceLLMCache)];
    SourceAccuracyStats *ruleStats = sourceStats[@(DecisionSourceLocalRules)];
    SourceAccuracyStats *learningStats = sourceStats[@(DecisionSourceSelfLearning)];
    SourceAccuracyStats *userPrefStats = sourceStats[@(DecisionSourceUserPreference)];
    
    result.llmAccuracy = llmStats.accuracy;
    result.cacheAccuracy = llmCacheStats.accuracy;
    result.ruleAccuracy = ruleStats.accuracy;
    result.learningAccuracy = learningStats.accuracy;
    result.userPrefAccuracy = userPrefStats.accuracy;
    
    // 计算风格问题率
    NSMutableDictionary<NSNumber *, NSNumber *> *problemRates = [NSMutableDictionary dictionary];
    for (NSNumber *style in styleTotals) {
        NSInteger total = [styleTotals[style] integerValue];
        NSInteger problems = [styleProblems[style] integerValue];
        if (total > 0) {
            problemRates[style] = @((float)problems / (float)total);
        }
    }
    result.styleProblemRates = problemRates;
    
    // 生成洞察（基于可配置阈值）
    NSMutableArray *insights = [NSMutableArray array];
    
    // 紧急模式检测
    if (result.overallAccuracy < self.thresholds.emergencyAccuracyThreshold) {
        [insights addObject:[NSString stringWithFormat:@"⚠️ 整体准确率 %.0f%% 低于 %.0f%%，建议进入紧急模式",
                             result.overallAccuracy * 100, self.thresholds.emergencyAccuracyThreshold * 100]];
    }
    
    // 高覆盖率警告
    if (result.overrideRate > self.thresholds.highOverrideRateThreshold) {
        [insights addObject:[NSString stringWithFormat:@"🔴 用户覆盖率 %.0f%% 过高，应增加 LLM 或用户偏好权重",
                             result.overrideRate * 100]];
    }
    
    // LLM 相关洞察
    if (llmStats.totalCount >= 3) {
        if (result.llmAccuracy < self.thresholds.lowSourceAccuracyThreshold) {
            [insights addObject:[NSString stringWithFormat:@"LLM 准确率 %.0f%% 过低，应降低优先级或优化 prompt",
                                 result.llmAccuracy * 100]];
        } else if (result.llmAccuracy > self.thresholds.highSourceAccuracyThreshold) {
            [insights addObject:[NSString stringWithFormat:@"LLM 准确率 %.0f%% 良好，可增加依赖",
                                 result.llmAccuracy * 100]];
        }
    }
    
    // 规则相关洞察
    if (ruleStats.totalCount >= 3) {
        if (result.ruleAccuracy < self.thresholds.lowSourceAccuracyThreshold) {
            [insights addObject:[NSString stringWithFormat:@"规则准确率 %.0f%% 过低，应降低优先级或改进规则",
                                 result.ruleAccuracy * 100]];
        } else if (result.ruleAccuracy > self.thresholds.highSourceAccuracyThreshold) {
            [insights addObject:@"本地规则准确率高，可以增加规则优先级"];
        }
    }
    
    // 缓存相关洞察
    if (llmCacheStats.totalCount >= 3) {
        if (result.cacheAccuracy < self.thresholds.lowSourceAccuracyThreshold) {
            [insights addObject:@"缓存命中但准确率低，建议清理或减少缓存依赖"];
        } else if (result.cacheAccuracy > self.thresholds.highSourceAccuracyThreshold) {
            [insights addObject:@"缓存效果良好，可扩大缓存范围"];
        }
    }
    
    // 自学习相关洞察
    if (learningStats.totalCount >= 3) {
        if (result.learningAccuracy < self.thresholds.lowSourceAccuracyThreshold) {
            [insights addObject:@"自学习准确率低，需要更多正向样本或调整学习参数"];
        } else if (result.learningAccuracy > 0.75) {
            [insights addObject:@"自学习效果良好，建议增加学习权重"];
        }
    }
    
    // 风格特定问题
    for (NSNumber *style in problemRates) {
        float rate = [problemRates[style] floatValue];
        if (rate > self.thresholds.styleProblemsThreshold) {
            NSString *styleName = [MusicStyleClassifier nameForStyle:[style unsignedIntegerValue]];
            [insights addObject:[NSString stringWithFormat:@"💡 %@ 风格问题率高 (%.0f%%)，需要生成专用规则", styleName, rate * 100]];
        }
    }
    
    result.insights = insights;
    
    self.lastAnalysisResult = result;
    
    NSLog(@"🔍 Reflection: 分析完成 - 整体准确率 %.1f%%, LLM %.1f%%, 规则 %.1f%%",
          result.overallAccuracy * 100, result.llmAccuracy * 100, result.ruleAccuracy * 100);
    
    return result;
}

- (SourceAccuracyStats *)analyzeSource:(DecisionSource)source {
    SourceAccuracyStats *stats = [[SourceAccuracyStats alloc] init];
    
    for (ReflectionDecisionRecord *record in self.mutableDecisionRecords) {
        if (record.source == source) {
            [stats updateWithCorrect:record.wasCorrect confidence:record.confidence time:record.decisionTime];
        }
    }
    
    return stats;
}

#pragma mark - Strategy Updates

- (NSArray<StrategyAdjustment *> *)generateAdjustments:(ReflectionAnalysisResult *)result {
    NSMutableArray *adjustments = [NSMutableArray array];
    float step = self.thresholds.adjustmentStep;
    
    // ==========================================
    // 1️⃣ 紧急模式：整体准确率 < 50%
    // ==========================================
    if (result.overallAccuracy < self.thresholds.emergencyAccuracyThreshold &&
        result.totalRecords >= self.thresholds.minRecordsForAdjustment) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentEmergencyMode
                                                                priority:1.0
                                                                  reason:[NSString stringWithFormat:@"🚨 整体准确率 %.0f%% 过低，触发紧急模式",
                                                                          result.overallAccuracy * 100]];
        adj.parameters = @{@"increaseLLM": @(step * 2), @"increaseUserPref": @(step * 2)};
        [adjustments addObject:adj];
    }
    
    // ==========================================
    // 2️⃣ 高覆盖率：覆盖率 > 70%
    // ==========================================
    if (result.overrideRate > self.thresholds.highOverrideRateThreshold &&
        result.totalRecords >= self.thresholds.minRecordsForAdjustment) {
        // 强制增加 LLM 或用户偏好权重
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentIncreaseUserPreference
                                                                priority:0.95
                                                                  reason:[NSString stringWithFormat:@"用户覆盖率 %.0f%% 过高，增加用户偏好权重",
                                                                          result.overrideRate * 100]];
        adj.parameters = @{@"increase": @(step)};
        [adjustments addObject:adj];
        
        // 同时考虑增加 LLM（如果 LLM 准确率不是太差）
        if (result.llmAccuracy >= self.thresholds.lowSourceAccuracyThreshold) {
            StrategyAdjustment *llmAdj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentIncreaseLLMPriority
                                                                       priority:0.9
                                                                         reason:@"覆盖率高但 LLM 可用，增加 LLM 权重"];
            llmAdj.parameters = @{@"increase": @(step)};
            [adjustments addObject:llmAdj];
        }
    }
    
    // ==========================================
    // 3️⃣ 来源准确率 < 40% - 降低该来源优先级
    // ==========================================
    SourceAccuracyStats *llmStats = result.sourceStats[@(DecisionSourceLLMRealtime)];
    SourceAccuracyStats *ruleStats = result.sourceStats[@(DecisionSourceLocalRules)];
    SourceAccuracyStats *cacheStats = result.sourceStats[@(DecisionSourceLLMCache)];
    SourceAccuracyStats *learningStats = result.sourceStats[@(DecisionSourceSelfLearning)];
    
    // LLM 准确率低 -> 降低优先级
    if (result.llmAccuracy < self.thresholds.lowSourceAccuracyThreshold && llmStats.totalCount >= 3) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentReduceLLMPriority
                                                                priority:0.85
                                                                  reason:[NSString stringWithFormat:@"LLM 准确率 %.0f%% 低于 %.0f%%",
                                                                          result.llmAccuracy * 100,
                                                                          self.thresholds.lowSourceAccuracyThreshold * 100]];
        adj.parameters = @{@"reduction": @(step)};
        [adjustments addObject:adj];
    }
    
    // 规则准确率低 -> 降低优先级
    if (result.ruleAccuracy < self.thresholds.lowSourceAccuracyThreshold && ruleStats.totalCount >= 3) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentReduceRulePriority
                                                                priority:0.8
                                                                  reason:[NSString stringWithFormat:@"规则准确率 %.0f%% 低于 %.0f%%",
                                                                          result.ruleAccuracy * 100,
                                                                          self.thresholds.lowSourceAccuracyThreshold * 100]];
        adj.parameters = @{@"reduction": @(step)};
        [adjustments addObject:adj];
    }
    
    // ==========================================
    // 4️⃣ 来源准确率高 -> 增加优先级（正向反馈）
    // ==========================================
    // LLM 准确率高 -> 增加优先级
    if (result.llmAccuracy > self.thresholds.highSourceAccuracyThreshold && llmStats.totalCount >= 3) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentIncreaseLLMPriority
                                                                priority:0.7
                                                                  reason:[NSString stringWithFormat:@"LLM 准确率 %.0f%% 优秀",
                                                                          result.llmAccuracy * 100]];
        adj.parameters = @{@"increase": @(step)};
        [adjustments addObject:adj];
    }
    
    // 规则准确率高 -> 增加优先级
    if (result.ruleAccuracy > self.thresholds.highSourceAccuracyThreshold && ruleStats.totalCount >= 3) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentIncreaseRulePriority
                                                                priority:0.7
                                                                  reason:[NSString stringWithFormat:@"规则准确率 %.0f%% 优秀",
                                                                          result.ruleAccuracy * 100]];
        adj.parameters = @{@"increase": @(step), @"newThreshold": @0.65};
        [adjustments addObject:adj];
    }
    
    // 缓存准确率高 -> 扩大缓存
    if (result.cacheAccuracy > self.thresholds.highSourceAccuracyThreshold && cacheStats.totalCount >= 3) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentExpandCache
                                                                priority:0.5
                                                                  reason:@"缓存准确率高"];
        [adjustments addObject:adj];
    }
    
    // 自学习效果好 -> 增强学习
    if (result.learningAccuracy > 0.75 && learningStats.totalCount >= 3) {
        StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentEnhanceLearning
                                                                priority:0.6
                                                                  reason:@"自学习效果良好"];
        adj.parameters = @{@"weightIncrease": @(step / 2)};
        [adjustments addObject:adj];
    }
    
    // ==========================================
    // 5️⃣ 风格特定规则自动生成
    // ==========================================
    for (NSNumber *style in result.styleProblemRates) {
        float rate = [result.styleProblemRates[style] floatValue];
        if (rate > self.thresholds.styleProblemsThreshold) {
            NSString *styleName = [MusicStyleClassifier nameForStyle:[style unsignedIntegerValue]];
            StrategyAdjustment *adj = [StrategyAdjustment adjustmentWithType:StrategyAdjustmentStyleSpecificRule
                                                                    priority:0.65
                                                                      reason:[NSString stringWithFormat:@"%@ 风格问题率 %.0f%%，需生成专用规则",
                                                                              styleName, rate * 100]];
            adj.parameters = @{@"style": style, @"problemRate": @(rate)};
            [adjustments addObject:adj];
        }
    }
    
    // 按优先级排序
    [adjustments sortUsingComparator:^NSComparisonResult(StrategyAdjustment *a, StrategyAdjustment *b) {
        return [@(b.priority) compare:@(a.priority)];
    }];
    
    NSLog(@"📋 Reflection: 生成 %lu 项策略调整", (unsigned long)adjustments.count);
    for (StrategyAdjustment *adj in adjustments) {
        NSLog(@"   - %@", adj.reason);
    }
    
    return adjustments;
}

- (void)applyAdjustments:(NSArray<StrategyAdjustment *> *)adjustments {
    if (!self.strategyManager) {
        NSLog(@"⚠️ Reflection: 未设置策略管理器，无法应用调整");
        return;
    }
    
    NSLog(@"🔧 Reflection: 开始应用 %lu 项策略调整...", (unsigned long)adjustments.count);
    
    for (StrategyAdjustment *adj in adjustments) {
        switch (adj.type) {
            case StrategyAdjustmentReduceLLMPriority: {
                float reduction = [adj.parameters[@"reduction"] floatValue] ?: 0.1;
                [self.strategyManager reduceLLMPriority:reduction];
                NSLog(@"   ⬇️ 降低 LLM 优先级 %.2f - %@", reduction, adj.reason);
                break;
            }
            case StrategyAdjustmentIncreaseLLMPriority: {
                float increase = [adj.parameters[@"increase"] floatValue] ?: 0.1;
                [self.strategyManager increaseLLMPriority:increase];
                NSLog(@"   ⬆️ 提高 LLM 优先级 %.2f - %@", increase, adj.reason);
                break;
            }
            case StrategyAdjustmentIncreaseRulePriority: {
                float increase = [adj.parameters[@"increase"] floatValue] ?: 0.1;
                float newThreshold = [adj.parameters[@"newThreshold"] floatValue] ?: 0.65;
                [self.strategyManager increaseRulePriority:increase];
                [self.strategyManager setLocalRulesConfidenceThreshold:newThreshold];
                NSLog(@"   ⬆️ 提高规则优先级 %.2f, 阈值 %.2f - %@", increase, newThreshold, adj.reason);
                break;
            }
            case StrategyAdjustmentReduceRulePriority: {
                float reduction = [adj.parameters[@"reduction"] floatValue] ?: 0.1;
                [self.strategyManager reduceRulePriority:reduction];
                NSLog(@"   ⬇️ 降低规则优先级 %.2f - %@", reduction, adj.reason);
                break;
            }
            case StrategyAdjustmentExpandCache:
                NSLog(@"   📦 建议扩大缓存 - %@", adj.reason);
                break;
            case StrategyAdjustmentEnhanceLearning:
                NSLog(@"   🧠 建议增强学习 - %@", adj.reason);
                break;
            case StrategyAdjustmentStyleSpecificRule: {
                NSNumber *style = adj.parameters[@"style"];
                float problemRate = [adj.parameters[@"problemRate"] floatValue];
                NSLog(@"   🎵 生成风格 %@ 专用规则 (问题率 %.0f%%) - %@", style, problemRate * 100, adj.reason);
                break;
            }
            case StrategyAdjustmentEmergencyMode: {
                float llmIncrease = [adj.parameters[@"increaseLLM"] floatValue] ?: 0.2;
                float userPrefIncrease = [adj.parameters[@"increaseUserPref"] floatValue] ?: 0.2;
                [self.strategyManager enterEmergencyMode];
                [self.strategyManager increaseLLMPriority:llmIncrease];
                [self.strategyManager increaseUserPreferenceWeight:userPrefIncrease];
                self.isEmergencyMode = YES;
                NSLog(@"   🚨 进入紧急模式! LLM +%.2f, 用户偏好 +%.2f - %@", llmIncrease, userPrefIncrease, adj.reason);
                break;
            }
            case StrategyAdjustmentIncreaseUserPreference: {
                float increase = [adj.parameters[@"increase"] floatValue] ?: 0.1;
                [self.strategyManager increaseUserPreferenceWeight:increase];
                NSLog(@"   👤 增加用户偏好权重 %.2f - %@", increase, adj.reason);
                break;
            }
        }
    }
    
    // 保存策略状态
    [self.strategyManager saveStrategyState];
    [self saveThresholds];
    
    NSLog(@"✅ Reflection: 策略调整完成并已保存");
}

- (void)reflectAndUpdatePolicy {
    NSLog(@"🔍 Reflection: 开始自动反思...");
    
    ReflectionAnalysisResult *result = [self analyzeAllRecords];
    
    if (self.mutableDecisionRecords.count < self.thresholds.minRecordsForAdjustment) {
        NSLog(@"🔍 Reflection: 决策记录 %lu 条，不足 %ld 条，跳过策略更新", 
              (unsigned long)self.mutableDecisionRecords.count,
              (long)self.thresholds.minRecordsForAdjustment);
        return;
    }
    
    // 检查是否应该退出紧急模式
    if (self.isEmergencyMode && result.overallAccuracy >= self.thresholds.emergencyAccuracyThreshold + 0.1) {
        NSLog(@"✅ Reflection: 准确率恢复至 %.0f%%，退出紧急模式", result.overallAccuracy * 100);
        [self.strategyManager exitEmergencyMode];
        self.isEmergencyMode = NO;
    }
    
    NSArray *adjustments = [self generateAdjustments:result];
    
    if (adjustments.count > 0) {
        NSLog(@"🔍 Reflection: 生成 %lu 条策略调整建议", (unsigned long)adjustments.count);
        [self applyAdjustments:adjustments];
    } else {
        NSLog(@"🔍 Reflection: 当前策略表现良好，无需调整");
    }
    
    // 输出洞察
    NSLog(@"💡 洞察建议 (%lu 条):", (unsigned long)result.insights.count);
    for (NSString *insight in result.insights) {
        NSLog(@"   %@", insight);
    }
}

#pragma mark - ReAct Loop

- (void)runReActLoopWithState:(NSDictionary *)currentState
                   completion:(void(^)(NSDictionary *newState, NSString *action, NSString *observation))completion {
    
    // Thought: 分析当前状态
    ReflectionAnalysisResult *analysis = self.lastAnalysisResult ?: [self analyzeAllRecords];
    
    NSMutableDictionary *newState = [currentState mutableCopy] ?: [NSMutableDictionary dictionary];
    NSString *action = @"OBSERVE";
    NSString *observation = @"";
    
    // 根据分析结果决定行动
    if (analysis.overallAccuracy < 0.5) {
        action = @"IMPROVE_RULES";
        observation = [NSString stringWithFormat:@"整体准确率低 (%.1f%%)，需要改进规则", analysis.overallAccuracy * 100];
        newState[@"needsImprovement"] = @YES;
    } else if (analysis.llmAccuracy < 0.6 && analysis.ruleAccuracy > 0.7) {
        action = @"SHIFT_TO_RULES";
        observation = @"LLM 效果不佳，本地规则更可靠";
        newState[@"preferRules"] = @YES;
    } else if (analysis.overallAccuracy > 0.8) {
        action = @"MAINTAIN";
        observation = @"策略表现良好，保持当前配置";
        newState[@"stable"] = @YES;
    } else {
        action = @"EXPLORE";
        observation = @"尝试更多策略组合";
        newState[@"exploring"] = @YES;
    }
    
    newState[@"lastAction"] = action;
    newState[@"lastObservation"] = observation;
    newState[@"timestamp"] = [NSDate date];
    
    NSLog(@"🔄 ReAct: Action=%@ | Observation=%@", action, observation);
    
    if (completion) {
        completion(newState, action, observation);
    }
}

#pragma mark - Persistence

- (void)saveRecords {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kReflectionRecordsFile];
    
    @try {
        NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [ReflectionDecisionRecord class], nil];
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.mutableDecisionRecords requiringSecureCoding:YES error:nil];
        [data writeToFile:path atomically:YES];
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Reflection: 保存记录失败: %@", exception.reason);
    }
}

- (void)loadRecords {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kReflectionRecordsFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [ReflectionDecisionRecord class], [NSString class], [NSDate class], nil];
            NSMutableArray *records = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (records) {
                self.mutableDecisionRecords = records;
                NSLog(@"📂 Reflection: 加载记录 %lu 条", (unsigned long)records.count);
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ Reflection: 加载记录失败: %@", exception.reason);
        }
    }
}

- (void)clearRecords {
    [self.mutableDecisionRecords removeAllObjects];
    self.lastAnalysisResult = nil;
    self.isEmergencyMode = NO;
    [self saveRecords];
    NSLog(@"🔍 Reflection: 记录已清除");
}

#pragma mark - Thresholds Persistence

static NSString * const kReflectionThresholdsKey = @"AgentReflectionThresholds";

- (void)saveThresholds {
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.thresholds requiringSecureCoding:YES error:nil];
        [[NSUserDefaults standardUserDefaults] setObject:data forKey:kReflectionThresholdsKey];
        NSLog(@"💾 Reflection: 阈值配置已保存");
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Reflection: 保存阈值失败: %@", exception.reason);
    }
}

- (ReflectionThresholds *)loadThresholds {
    @try {
        NSData *data = [[NSUserDefaults standardUserDefaults] objectForKey:kReflectionThresholdsKey];
        if (data) {
            NSSet *classes = [NSSet setWithObject:[ReflectionThresholds class]];
            ReflectionThresholds *t = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (t) {
                NSLog(@"📂 Reflection: 阈值配置已加载");
                return t;
            }
        }
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Reflection: 加载阈值失败: %@", exception.reason);
    }
    return nil;
}

- (NSString *)exportAnalysisReport {
    ReflectionAnalysisResult *result = self.lastAnalysisResult ?: [self analyzeAllRecords];
    
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"======================================\n"];
    [report appendString:@"   Agent 反思分析报告\n"];
    [report appendFormat:@"   生成时间: %@\n", [NSDate date]];
    [report appendString:@"======================================\n\n"];
    
    [report appendFormat:@"📊 总记录数: %lu\n", (unsigned long)self.mutableDecisionRecords.count];
    [report appendFormat:@"📈 整体准确率: %.1f%%\n", result.overallAccuracy * 100];
    [report appendFormat:@"🔄 用户覆盖率: %.1f%%\n", result.overrideRate * 100];
    [report appendFormat:@"🚨 紧急模式: %@\n\n", self.isEmergencyMode ? @"是" : @"否"];
    
    [report appendString:@"--- 各来源准确率 ---\n"];
    [report appendFormat:@"  LLM 实时: %.1f%%\n", result.llmAccuracy * 100];
    [report appendFormat:@"  LLM 缓存: %.1f%%\n", result.cacheAccuracy * 100];
    [report appendFormat:@"  本地规则: %.1f%%\n", result.ruleAccuracy * 100];
    [report appendFormat:@"  自学习: %.1f%%\n", result.learningAccuracy * 100];
    [report appendFormat:@"  用户偏好: %.1f%%\n\n", result.userPrefAccuracy * 100];
    
    [report appendString:@"--- 当前阈值配置 ---\n"];
    [report appendFormat:@"  紧急模式触发: <%.0f%%\n", self.thresholds.emergencyAccuracyThreshold * 100];
    [report appendFormat:@"  高覆盖率阈值: >%.0f%%\n", self.thresholds.highOverrideRateThreshold * 100];
    [report appendFormat:@"  低来源准确率: <%.0f%%\n", self.thresholds.lowSourceAccuracyThreshold * 100];
    [report appendFormat:@"  高来源准确率: >%.0f%%\n", self.thresholds.highSourceAccuracyThreshold * 100];
    [report appendFormat:@"  调整步长: %.1f\n\n", self.thresholds.adjustmentStep];
    
    [report appendString:@"--- 洞察建议 ---\n"];
    for (NSString *insight in result.insights) {
        [report appendFormat:@"  %@\n", insight];
    }
    
    // 生成策略调整预览
    NSArray *adjustments = [self generateAdjustments:result];
    if (adjustments.count > 0) {
        [report appendString:@"\n--- 待执行策略调整 ---\n"];
        for (StrategyAdjustment *adj in adjustments) {
            [report appendFormat:@"  [优先级 %.1f] %@\n", adj.priority, adj.reason];
        }
    } else {
        [report appendString:@"\n✅ 当前策略表现良好，无需调整\n"];
    }
    
    [report appendString:@"\n======================================\n"];
    
    return report;
}

@end
