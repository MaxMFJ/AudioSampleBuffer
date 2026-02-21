//
//  AgentGoalManager.m
//  AudioSampleBuffer
//
//  目标管理器实现 - 优化版
//

#import "AgentGoalManager.h"

static NSString *const kGoalWeightsFile = @"GoalWeights.plist";
static NSString *const kGoalThresholdsFile = @"GoalThresholds.plist";
static NSString *const kMetricsHistoryFile = @"MetricsHistory.plist";
static const NSInteger kMaxMetricsHistory = 100;
static const NSInteger kBatchSaveThreshold = 10;  // 每 10 条记录触发一次保存

#pragma mark - AgentMetrics

@implementation AgentMetrics

+ (instancetype)metricsWithDefaults {
    AgentMetrics *metrics = [[AgentMetrics alloc] init];
    metrics.userSatisfaction = 0.5;
    metrics.llmCallRate = 0.3;
    metrics.styleDiversity = 0.5;
    metrics.overrideRate = 0.1;
    metrics.decisionLatency = 1.0;
    metrics.cacheHitRate = 0.5;
    metrics.totalDecisions = 0;
    return metrics;
}

- (id)copyWithZone:(NSZone *)zone {
    AgentMetrics *copy = [[AgentMetrics alloc] init];
    copy.userSatisfaction = self.userSatisfaction;
    copy.llmCallRate = self.llmCallRate;
    copy.styleDiversity = self.styleDiversity;
    copy.overrideRate = self.overrideRate;
    copy.decisionLatency = self.decisionLatency;
    copy.cacheHitRate = self.cacheHitRate;
    copy.totalDecisions = self.totalDecisions;
    return copy;
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<AgentMetrics: satisfaction=%.2f, llmRate=%.2f, diversity=%.2f, override=%.2f, latency=%.2fs>",
            self.userSatisfaction, self.llmCallRate, self.styleDiversity, self.overrideRate, self.decisionLatency];
}

@end

#pragma mark - GoalWeights

@implementation GoalWeights

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)defaultWeights {
    GoalWeights *weights = [[GoalWeights alloc] init];
    weights.satisfaction = 0.40;
    weights.cost = 0.20;
    weights.diversity = 0.20;
    weights.stability = 0.10;
    weights.latency = 0.10;
    return weights;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeFloat:self.satisfaction forKey:@"satisfaction"];
    [coder encodeFloat:self.cost forKey:@"cost"];
    [coder encodeFloat:self.diversity forKey:@"diversity"];
    [coder encodeFloat:self.stability forKey:@"stability"];
    [coder encodeFloat:self.latency forKey:@"latency"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _satisfaction = [coder decodeFloatForKey:@"satisfaction"];
        _cost = [coder decodeFloatForKey:@"cost"];
        _diversity = [coder decodeFloatForKey:@"diversity"];
        _stability = [coder decodeFloatForKey:@"stability"];
        _latency = [coder decodeFloatForKey:@"latency"];
    }
    return self;
}

- (id)copyWithZone:(NSZone *)zone {
    GoalWeights *copy = [[GoalWeights alloc] init];
    copy.satisfaction = self.satisfaction;
    copy.cost = self.cost;
    copy.diversity = self.diversity;
    copy.stability = self.stability;
    copy.latency = self.latency;
    return copy;
}

- (float)totalWeight {
    return self.satisfaction + self.cost + self.diversity + self.stability + self.latency;
}

- (void)softNormalize {
    float total = [self totalWeight];
    
    // 只在总和偏离 1.0 超过 10% 时才归一化
    if (total < 0.9 || total > 1.1) {
        // 使用软归一化：保留相对比例变化
        float scale = 1.0 / total;
        self.satisfaction *= scale;
        self.cost *= scale;
        self.diversity *= scale;
        self.stability *= scale;
        self.latency *= scale;
    }
}

- (NSString *)description {
    return [NSString stringWithFormat:@"<GoalWeights: sat=%.2f, cost=%.2f, div=%.2f, stab=%.2f, lat=%.2f (sum=%.2f)>",
            self.satisfaction, self.cost, self.diversity, self.stability, self.latency, [self totalWeight]];
}

@end

#pragma mark - GoalThresholds

@implementation GoalThresholds

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)defaultThresholds {
    GoalThresholds *t = [[GoalThresholds alloc] init];
    t.overrideRateHigh = 0.4;
    t.llmCallRateHigh = 0.6;
    t.satisfactionLow = 0.5;
    t.diversityLow = 0.3;
    t.latencyHigh = 3.0;
    t.majorAdjustStep = 0.05;
    t.minorAdjustStep = 0.03;
    t.minWeight = 0.05;
    t.maxWeight = 0.60;
    t.cacheHitRateLow = 0.3;
    t.costWeightHigh = 0.3;
    return t;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeFloat:self.overrideRateHigh forKey:@"overrideRateHigh"];
    [coder encodeFloat:self.llmCallRateHigh forKey:@"llmCallRateHigh"];
    [coder encodeFloat:self.satisfactionLow forKey:@"satisfactionLow"];
    [coder encodeFloat:self.diversityLow forKey:@"diversityLow"];
    [coder encodeFloat:self.latencyHigh forKey:@"latencyHigh"];
    [coder encodeFloat:self.majorAdjustStep forKey:@"majorAdjustStep"];
    [coder encodeFloat:self.minorAdjustStep forKey:@"minorAdjustStep"];
    [coder encodeFloat:self.minWeight forKey:@"minWeight"];
    [coder encodeFloat:self.maxWeight forKey:@"maxWeight"];
    [coder encodeFloat:self.cacheHitRateLow forKey:@"cacheHitRateLow"];
    [coder encodeFloat:self.costWeightHigh forKey:@"costWeightHigh"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _overrideRateHigh = [coder decodeFloatForKey:@"overrideRateHigh"];
        _llmCallRateHigh = [coder decodeFloatForKey:@"llmCallRateHigh"];
        _satisfactionLow = [coder decodeFloatForKey:@"satisfactionLow"];
        _diversityLow = [coder decodeFloatForKey:@"diversityLow"];
        _latencyHigh = [coder decodeFloatForKey:@"latencyHigh"];
        _majorAdjustStep = [coder decodeFloatForKey:@"majorAdjustStep"];
        _minorAdjustStep = [coder decodeFloatForKey:@"minorAdjustStep"];
        _minWeight = [coder decodeFloatForKey:@"minWeight"];
        _maxWeight = [coder decodeFloatForKey:@"maxWeight"];
        _cacheHitRateLow = [coder decodeFloatForKey:@"cacheHitRateLow"];
        _costWeightHigh = [coder decodeFloatForKey:@"costWeightHigh"];
    }
    return self;
}

@end

#pragma mark - GoalEvaluationResult

@implementation GoalEvaluationResult

- (NSString *)description {
    return [NSString stringWithFormat:@"<GoalEvaluationResult: total=%.1f, %@>", self.totalScore, self.interpretation];
}

@end

#pragma mark - AgentGoalManager

@interface AgentGoalManager ()

@property (nonatomic, strong) GoalWeights *currentWeights;
@property (nonatomic, strong) NSMutableArray<AgentMetrics *> *mutableMetricsHistory;
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, assign) NSInteger unsavedMetricsCount;
@property (nonatomic, strong) NSTimer *autoSaveTimer;
@property (nonatomic, strong) dispatch_queue_t saveQueue;

@end

@implementation AgentGoalManager

#pragma mark - Singleton

+ (instancetype)sharedManager {
    static AgentGoalManager *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AgentGoalManager alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentWeights = [GoalWeights defaultWeights];
        _thresholds = [GoalThresholds defaultThresholds];
        _mutableMetricsHistory = [NSMutableArray array];
        _unsavedMetricsCount = 0;
        _autoSaveEnabled = YES;
        _autoSaveInterval = 60.0;
        
        // 创建后台保存队列
        _saveQueue = dispatch_queue_create("com.audiosamplebuffer.goalsave", DISPATCH_QUEUE_SERIAL);
        
        [self setupCacheDirectory];
        [self loadWeights];
        [self loadThresholds];
        [self loadMetricsHistory];
        [self startAutoSaveTimer];
    }
    return self;
}

- (void)dealloc {
    [self.autoSaveTimer invalidate];
    [self flushToDisk];
}

- (void)setupCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    self.cacheDirectory = [cachesDir stringByAppendingPathComponent:@"AgentGoalManager"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectory]) {
        [fm createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)startAutoSaveTimer {
    if (!self.autoSaveEnabled) return;
    
    [self.autoSaveTimer invalidate];
    self.autoSaveTimer = [NSTimer scheduledTimerWithTimeInterval:self.autoSaveInterval
                                                          target:self
                                                        selector:@selector(autoSaveTimerFired)
                                                        userInfo:nil
                                                         repeats:YES];
}

- (void)autoSaveTimerFired {
    if (self.unsavedMetricsCount > 0) {
        [self flushToDisk];
    }
}

- (NSArray<AgentMetrics *> *)metricsHistory {
    return [self.mutableMetricsHistory copy];
}

#pragma mark - Evaluation (优化版：全正向评分)

- (GoalEvaluationResult *)evaluateMetricsWithResult:(AgentMetrics *)metrics {
    GoalEvaluationResult *result = [[GoalEvaluationResult alloc] init];
    
    // 计算各维度得分（0-100）
    // 满意度：直接映射
    result.satisfactionScore = metrics.userSatisfaction * 100;
    
    // 效率：LLM 调用率越低越好（成本越低越高效）
    // 转换为正向：效率 = (1 - llmCallRate) * 权重系数 + cacheHitRate * 权重系数
    float costEfficiency = (1.0 - metrics.llmCallRate) * 0.6 + metrics.cacheHitRate * 0.4;
    result.efficiencyScore = costEfficiency * 100;
    
    // 多样性：直接映射
    result.diversityScore = metrics.styleDiversity * 100;
    
    // 稳定性：覆盖率越低越稳定
    result.stabilityScore = (1.0 - metrics.overrideRate) * 100;
    
    // 响应速度：延迟越低越好，使用 sigmoid 转换
    // 延迟 0s -> 100分, 延迟 2s -> 50分, 延迟 5s -> ~10分
    float latencyScore = 100.0 / (1.0 + expf((metrics.decisionLatency - 2.0) * 1.5));
    result.responsivenessScore = latencyScore;
    
    // 加权计算总分
    float totalWeight = [self.currentWeights totalWeight];
    if (totalWeight <= 0) totalWeight = 1.0;
    
    result.totalScore = (
        result.satisfactionScore * self.currentWeights.satisfaction +
        result.efficiencyScore * self.currentWeights.cost +
        result.diversityScore * self.currentWeights.diversity +
        result.stabilityScore * self.currentWeights.stability +
        result.responsivenessScore * self.currentWeights.latency
    ) / totalWeight;
    
    // 生成解释
    result.interpretation = [self interpretScore:result.totalScore];
    
    return result;
}

- (NSString *)interpretScore:(float)score {
    if (score >= 85) {
        return @"🟢 优秀：Agent 表现非常好";
    } else if (score >= 70) {
        return @"🟡 良好：Agent 表现正常，有提升空间";
    } else if (score >= 55) {
        return @"🟠 一般：建议关注策略建议进行优化";
    } else if (score >= 40) {
        return @"🔴 较差：需要调整策略或配置";
    } else {
        return @"⚫ 很差：请检查系统配置和规则";
    }
}

- (float)evaluateMetrics:(AgentMetrics *)metrics {
    return [self evaluateMetricsWithResult:metrics].totalScore;
}

- (NSDictionary<NSString *, NSNumber *> *)evaluateMetricsDetailed:(AgentMetrics *)metrics {
    GoalEvaluationResult *result = [self evaluateMetricsWithResult:metrics];
    return @{
        @"satisfaction": @(result.satisfactionScore),
        @"efficiency": @(result.efficiencyScore),
        @"diversity": @(result.diversityScore),
        @"stability": @(result.stabilityScore),
        @"responsiveness": @(result.responsivenessScore),
        @"total": @(result.totalScore)
    };
}

#pragma mark - Weight Adjustment (优化版：避免稀释)

- (void)adjustWeightsWithMetrics:(AgentMetrics *)metrics {
    GoalWeights *newWeights = [self.currentWeights copy];
    GoalThresholds *t = self.thresholds;
    
    BOOL adjusted = NO;
    NSMutableArray *adjustments = [NSMutableArray array];
    
    // 计算需要调整的维度
    BOOL needStabilityUp = metrics.overrideRate > t.overrideRateHigh;
    BOOL needCostUp = metrics.llmCallRate > t.llmCallRateHigh;
    BOOL needSatisfactionUp = metrics.userSatisfaction < t.satisfactionLow;
    BOOL needDiversityUp = metrics.styleDiversity < t.diversityLow;
    BOOL needLatencyUp = metrics.decisionLatency > t.latencyHigh;
    
    // 统计需要增加的维度数量
    NSInteger upCount = (needStabilityUp ? 1 : 0) + (needCostUp ? 1 : 0) +
                        (needSatisfactionUp ? 1 : 0) + (needDiversityUp ? 1 : 0) +
                        (needLatencyUp ? 1 : 0);
    
    if (upCount == 0) {
        // 无需调整
        return;
    }
    
    // 优化：根据需要调整的维度数量分配步长，避免稀释
    // 使用"预算"模式：总调整量固定，按优先级分配
    float totalBudget = t.majorAdjustStep * 2;  // 总调整预算
    float stepPerDimension = totalBudget / upCount;
    
    // 找出表现最好的维度，用于"借用"权重
    NSMutableArray<NSDictionary *> *dimensionPerformance = [NSMutableArray array];
    
    if (!needSatisfactionUp) {
        [dimensionPerformance addObject:@{@"name": @"satisfaction", @"value": @(newWeights.satisfaction)}];
    }
    if (!needCostUp) {
        [dimensionPerformance addObject:@{@"name": @"cost", @"value": @(newWeights.cost)}];
    }
    if (!needDiversityUp) {
        [dimensionPerformance addObject:@{@"name": @"diversity", @"value": @(newWeights.diversity)}];
    }
    if (!needStabilityUp) {
        [dimensionPerformance addObject:@{@"name": @"stability", @"value": @(newWeights.stability)}];
    }
    if (!needLatencyUp) {
        [dimensionPerformance addObject:@{@"name": @"latency", @"value": @(newWeights.latency)}];
    }
    
    // 按权重降序排列（优先从高权重的"好"维度借用）
    [dimensionPerformance sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        return [b[@"value"] compare:a[@"value"]];
    }];
    
    // 计算需要借用的总量
    float totalIncrease = stepPerDimension * upCount;
    float remainingDecrease = totalIncrease;
    
    // 从表现好的维度借用权重
    for (NSDictionary *dim in dimensionPerformance) {
        if (remainingDecrease <= 0) break;
        
        NSString *name = dim[@"name"];
        float currentVal = [dim[@"value"] floatValue];
        float canDecrease = MAX(0, currentVal - t.minWeight);
        float decrease = MIN(canDecrease, remainingDecrease / dimensionPerformance.count);
        
        if (decrease > 0.001) {
            if ([name isEqualToString:@"satisfaction"]) newWeights.satisfaction -= decrease;
            else if ([name isEqualToString:@"cost"]) newWeights.cost -= decrease;
            else if ([name isEqualToString:@"diversity"]) newWeights.diversity -= decrease;
            else if ([name isEqualToString:@"stability"]) newWeights.stability -= decrease;
            else if ([name isEqualToString:@"latency"]) newWeights.latency -= decrease;
            
            remainingDecrease -= decrease;
        }
    }
    
    // 增加需要提升的维度权重
    if (needStabilityUp) {
        float increase = MIN(stepPerDimension, t.maxWeight - newWeights.stability);
        newWeights.stability += increase;
        [adjustments addObject:[NSString stringWithFormat:@"稳定性 +%.2f (覆盖率 %.0f%%)", increase, metrics.overrideRate * 100]];
        adjusted = YES;
    }
    
    if (needCostUp) {
        float increase = MIN(stepPerDimension, t.maxWeight - newWeights.cost);
        newWeights.cost += increase;
        [adjustments addObject:[NSString stringWithFormat:@"成本 +%.2f (LLM率 %.0f%%)", increase, metrics.llmCallRate * 100]];
        adjusted = YES;
    }
    
    if (needSatisfactionUp) {
        float increase = MIN(stepPerDimension, t.maxWeight - newWeights.satisfaction);
        newWeights.satisfaction += increase;
        [adjustments addObject:[NSString stringWithFormat:@"满意度 +%.2f (当前 %.0f%%)", increase, metrics.userSatisfaction * 100]];
        adjusted = YES;
    }
    
    if (needDiversityUp) {
        float increase = MIN(stepPerDimension, t.maxWeight - newWeights.diversity);
        newWeights.diversity += increase;
        [adjustments addObject:[NSString stringWithFormat:@"多样性 +%.2f (当前 %.0f%%)", increase, metrics.styleDiversity * 100]];
        adjusted = YES;
    }
    
    if (needLatencyUp) {
        float increase = MIN(stepPerDimension, t.maxWeight - newWeights.latency);
        newWeights.latency += increase;
        [adjustments addObject:[NSString stringWithFormat:@"延迟 +%.2f (当前 %.1fs)", increase, metrics.decisionLatency]];
        adjusted = YES;
    }
    
    if (adjusted) {
        // 使用软归一化，避免过度稀释
        [newWeights softNormalize];
        
        self.currentWeights = newWeights;
        [self saveWeights];
        
        NSLog(@"🎯 GoalManager: 权重调整 (%lu 项)", (unsigned long)adjustments.count);
        for (NSString *adj in adjustments) {
            NSLog(@"   %@", adj);
        }
        NSLog(@"   新权重: %@", newWeights);
    }
}

- (void)setWeights:(GoalWeights *)weights {
    self.currentWeights = [weights copy];
    [self.currentWeights softNormalize];
    [self saveWeights];
}

- (void)resetWeights {
    self.currentWeights = [GoalWeights defaultWeights];
    [self saveWeights];
    NSLog(@"🎯 GoalManager: 权重已重置为默认值");
}

#pragma mark - Strategy Recommendations

- (NSArray<NSString *> *)getStrategyRecommendations:(AgentMetrics *)metrics {
    NSMutableArray *recommendations = [NSMutableArray array];
    GoalThresholds *t = self.thresholds;
    
    if (metrics.userSatisfaction < t.satisfactionLow) {
        [recommendations addObject:@"建议：增加 LLM 调用以提高推荐质量"];
    }
    
    if (metrics.overrideRate > t.overrideRateHigh) {
        [recommendations addObject:@"建议：优化本地规则，减少用户手动覆盖"];
    }
    
    if (metrics.llmCallRate > t.llmCallRateHigh && metrics.cacheHitRate < t.cacheHitRateLow) {
        [recommendations addObject:@"建议：扩大缓存策略，减少重复 LLM 调用"];
    }
    
    if (metrics.styleDiversity < t.diversityLow) {
        [recommendations addObject:@"建议：增加随机探索，提高特效多样性"];
    }
    
    if (metrics.decisionLatency > t.latencyHigh) {
        [recommendations addObject:@"建议：优先使用本地规则和缓存，降低延迟"];
    }
    
    return recommendations;
}

- (BOOL)shouldPreferLocalRules:(AgentMetrics *)metrics {
    GoalThresholds *t = self.thresholds;
    return (self.currentWeights.cost > t.costWeightHigh) ||
           (metrics.decisionLatency > 2.0) ||
           (metrics.llmCallRate > 0.5 && metrics.userSatisfaction > 0.6);
}

- (BOOL)shouldIncreaseLLMUsage:(AgentMetrics *)metrics {
    GoalThresholds *t = self.thresholds;
    return (metrics.userSatisfaction < t.satisfactionLow) &&
           (metrics.llmCallRate < 0.5) &&
           (self.currentWeights.satisfaction > self.currentWeights.cost);
}

#pragma mark - Persistence (优化版：延迟批量保存)

- (void)saveWeights {
    dispatch_async(self.saveQueue, ^{
        NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kGoalWeightsFile];
        
        @try {
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.currentWeights requiringSecureCoding:YES error:nil];
            [data writeToFile:path atomically:YES];
        } @catch (NSException *exception) {
            NSLog(@"⚠️ GoalManager: 保存权重失败: %@", exception.reason);
        }
    });
}

- (void)loadWeights {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kGoalWeightsFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[GoalWeights class], nil];
            GoalWeights *weights = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (weights) {
                self.currentWeights = weights;
                NSLog(@"📂 GoalManager: 加载权重成功 -> %@", weights);
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ GoalManager: 加载权重失败: %@", exception.reason);
        }
    }
}

- (void)saveThresholds {
    dispatch_async(self.saveQueue, ^{
        NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kGoalThresholdsFile];
        
        @try {
            NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.thresholds requiringSecureCoding:YES error:nil];
            [data writeToFile:path atomically:YES];
        } @catch (NSException *exception) {
            NSLog(@"⚠️ GoalManager: 保存阈值失败: %@", exception.reason);
        }
    });
}

- (void)loadThresholds {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kGoalThresholdsFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[GoalThresholds class], nil];
            GoalThresholds *thresholds = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (thresholds) {
                self.thresholds = thresholds;
                NSLog(@"📂 GoalManager: 加载阈值成功");
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ GoalManager: 加载阈值失败: %@", exception.reason);
        }
    }
}

- (void)recordMetrics:(AgentMetrics *)metrics {
    @synchronized (self.mutableMetricsHistory) {
        [self.mutableMetricsHistory addObject:[metrics copy]];
        
        // 使用环形缓冲区方式管理，避免频繁数组操作
        if (self.mutableMetricsHistory.count > kMaxMetricsHistory) {
            [self.mutableMetricsHistory removeObjectsInRange:NSMakeRange(0, self.mutableMetricsHistory.count - kMaxMetricsHistory)];
        }
        
        self.unsavedMetricsCount++;
    }
    
    // 达到批量阈值时保存
    if (self.unsavedMetricsCount >= kBatchSaveThreshold) {
        [self saveMetricsHistoryAsync];
    }
}

- (void)saveMetricsHistoryAsync {
    // 复制数据以避免线程问题
    NSArray *historySnapshot;
    @synchronized (self.mutableMetricsHistory) {
        historySnapshot = [self.mutableMetricsHistory copy];
        self.unsavedMetricsCount = 0;
    }
    
    dispatch_async(self.saveQueue, ^{
        NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kMetricsHistoryFile];
        
        @try {
            NSMutableArray *dictArray = [NSMutableArray arrayWithCapacity:historySnapshot.count];
            for (AgentMetrics *m in historySnapshot) {
                [dictArray addObject:@{
                    @"userSatisfaction": @(m.userSatisfaction),
                    @"llmCallRate": @(m.llmCallRate),
                    @"styleDiversity": @(m.styleDiversity),
                    @"overrideRate": @(m.overrideRate),
                    @"decisionLatency": @(m.decisionLatency),
                    @"cacheHitRate": @(m.cacheHitRate),
                    @"totalDecisions": @(m.totalDecisions)
                }];
            }
            [dictArray writeToFile:path atomically:YES];
            NSLog(@"💾 GoalManager: 异步保存指标历史 %lu 条", (unsigned long)dictArray.count);
        } @catch (NSException *exception) {
            NSLog(@"⚠️ GoalManager: 保存指标历史失败: %@", exception.reason);
        }
    });
}

- (void)loadMetricsHistory {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kMetricsHistoryFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSArray *dictArray = [NSArray arrayWithContentsOfFile:path];
            
            // 预分配容量
            NSMutableArray *history = [NSMutableArray arrayWithCapacity:dictArray.count];
            
            for (NSDictionary *dict in dictArray) {
                AgentMetrics *m = [[AgentMetrics alloc] init];
                m.userSatisfaction = [dict[@"userSatisfaction"] floatValue];
                m.llmCallRate = [dict[@"llmCallRate"] floatValue];
                m.styleDiversity = [dict[@"styleDiversity"] floatValue];
                m.overrideRate = [dict[@"overrideRate"] floatValue];
                m.decisionLatency = [dict[@"decisionLatency"] floatValue];
                m.cacheHitRate = [dict[@"cacheHitRate"] floatValue];
                m.totalDecisions = [dict[@"totalDecisions"] integerValue];
                [history addObject:m];
            }
            
            @synchronized (self.mutableMetricsHistory) {
                self.mutableMetricsHistory = history;
            }
            
            NSLog(@"📂 GoalManager: 加载指标历史 %lu 条", (unsigned long)history.count);
        } @catch (NSException *exception) {
            NSLog(@"⚠️ GoalManager: 加载指标历史失败: %@", exception.reason);
        }
    }
}

- (void)flushToDisk {
    [self saveWeights];
    [self saveThresholds];
    [self saveMetricsHistoryAsync];
    NSLog(@"💾 GoalManager: 强制刷新到磁盘");
}

@end
