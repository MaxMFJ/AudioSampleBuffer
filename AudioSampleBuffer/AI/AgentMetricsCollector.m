//
//  AgentMetricsCollector.m
//  AudioSampleBuffer
//
//  指标采集器实现
//

#import "AgentMetricsCollector.h"

static NSString *const kMetricsEventsFile = @"MetricsEvents.plist";
static NSString *const kMetricsSnapshotsFile = @"MetricsSnapshots.plist";
static NSString *const kCostControlFile = @"CostControl.plist";
static const NSInteger kMaxEvents = 1000;
static const NSInteger kMaxSnapshots = 100;

#pragma mark - DecisionEvent

@implementation DecisionEvent

+ (instancetype)eventWithType:(DecisionEventType)type {
    DecisionEvent *event = [[DecisionEvent alloc] init];
    event.type = type;
    event.timestamp = [NSDate date];
    return event;
}

- (NSString *)description {
    NSArray *typeNames = @[@"Started", @"Completed", @"UserOverride", @"LLMCalled",
                           @"LLMSuccess", @"LLMFailed", @"CacheHit", @"RuleUsed",
                           @"LearningUsed", @"Fallback"];
    NSString *typeName = (self.type < typeNames.count) ? typeNames[self.type] : @"Unknown";
    return [NSString stringWithFormat:@"<DecisionEvent: %@ at %@>", typeName, self.timestamp];
}

@end

#pragma mark - MetricsSnapshot

@implementation MetricsSnapshot

@end

#pragma mark - CostControlConfig

@implementation CostControlConfig

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)defaultConfig {
    CostControlConfig *config = [[CostControlConfig alloc] init];
    config.dailyLLMBudget = 100;        // 每日最多 100 次 LLM 调用
    config.currentLLMCalls = 0;
    config.budgetResetDate = [self startOfDay:[NSDate date]];
    config.forceLocalOnBudgetExceeded = YES;
    return config;
}

+ (NSDate *)startOfDay:(NSDate *)date {
    NSCalendar *calendar = [NSCalendar currentCalendar];
    return [calendar startOfDayForDate:date];
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.dailyLLMBudget forKey:@"dailyLLMBudget"];
    [coder encodeInteger:self.currentLLMCalls forKey:@"currentLLMCalls"];
    [coder encodeObject:self.budgetResetDate forKey:@"budgetResetDate"];
    [coder encodeBool:self.forceLocalOnBudgetExceeded forKey:@"forceLocalOnBudgetExceeded"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _dailyLLMBudget = [coder decodeIntegerForKey:@"dailyLLMBudget"];
        _currentLLMCalls = [coder decodeIntegerForKey:@"currentLLMCalls"];
        _budgetResetDate = [coder decodeObjectOfClass:[NSDate class] forKey:@"budgetResetDate"];
        _forceLocalOnBudgetExceeded = [coder decodeBoolForKey:@"forceLocalOnBudgetExceeded"];
    }
    return self;
}

- (BOOL)isBudgetExceeded {
    [self resetIfNeeded];
    return self.currentLLMCalls >= self.dailyLLMBudget;
}

- (void)incrementLLMCalls {
    [self resetIfNeeded];
    self.currentLLMCalls++;
}

- (void)resetIfNeeded {
    NSDate *todayStart = [CostControlConfig startOfDay:[NSDate date]];
    if ([self.budgetResetDate compare:todayStart] == NSOrderedAscending) {
        self.currentLLMCalls = 0;
        self.budgetResetDate = todayStart;
        NSLog(@"💰 CostControl: 每日预算已重置");
    }
}

@end

#pragma mark - AgentMetricsCollector

@interface AgentMetricsCollector ()

@property (nonatomic, strong) NSMutableArray<DecisionEvent *> *events;
@property (nonatomic, strong) NSMutableArray<MetricsSnapshot *> *snapshots;
@property (nonatomic, strong) NSString *cacheDirectory;
@property (nonatomic, strong, nullable) NSTimer *collectionTimer;

// 累计统计
@property (nonatomic, assign) NSInteger totalDecisions;
@property (nonatomic, assign) NSInteger totalLLMCalls;
@property (nonatomic, assign) NSInteger totalLLMSuccesses;
@property (nonatomic, assign) NSInteger totalCacheHits;
@property (nonatomic, assign) NSInteger totalUserOverrides;
@property (nonatomic, assign) NSTimeInterval totalDecisionTime;

@end

@implementation AgentMetricsCollector

#pragma mark - Singleton

+ (instancetype)sharedCollector {
    static AgentMetricsCollector *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[AgentMetricsCollector alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _events = [NSMutableArray array];
        _snapshots = [NSMutableArray array];
        _costControl = [CostControlConfig defaultConfig];
        _autoCollectionEnabled = YES;
        _collectionInterval = 300.0;  // 5 分钟
        
        _totalDecisions = 0;
        _totalLLMCalls = 0;
        _totalLLMSuccesses = 0;
        _totalCacheHits = 0;
        _totalUserOverrides = 0;
        _totalDecisionTime = 0;
        
        [self setupCacheDirectory];
        [self loadMetrics];
        [self startAutoCollection];
    }
    return self;
}

- (void)setupCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    self.cacheDirectory = [cachesDir stringByAppendingPathComponent:@"AgentMetrics"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectory]) {
        [fm createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)startAutoCollection {
    if (!self.autoCollectionEnabled) return;
    
    [self.collectionTimer invalidate];
    self.collectionTimer = [NSTimer scheduledTimerWithTimeInterval:self.collectionInterval
                                                            target:self
                                                          selector:@selector(autoCollectMetrics)
                                                          userInfo:nil
                                                           repeats:YES];
}

- (void)autoCollectMetrics {
    AgentMetrics *metrics = [self collectCurrentMetrics];
    
    MetricsSnapshot *snapshot = [[MetricsSnapshot alloc] init];
    snapshot.timestamp = [NSDate date];
    snapshot.metrics = metrics;
    snapshot.timeWindow = MetricsTimeWindowHour;
    
    [self.snapshots addObject:snapshot];
    while (self.snapshots.count > kMaxSnapshots) {
        [self.snapshots removeObjectAtIndex:0];
    }
    
    [self saveMetrics];
    
    NSLog(@"📊 Metrics: 自动采集 - 满意度=%.1f%%, LLM率=%.1f%%",
          metrics.userSatisfaction * 100, metrics.llmCallRate * 100);
}

#pragma mark - Event Recording

- (void)recordEvent:(DecisionEvent *)event {
    [self.events addObject:event];
    
    while (self.events.count > kMaxEvents) {
        [self.events removeObjectAtIndex:0];
    }
}

- (void)recordDecisionStartedForSong:(NSString *)songName {
    DecisionEvent *event = [DecisionEvent eventWithType:DecisionEventTypeStarted];
    event.songName = songName;
    [self recordEvent:event];
}

- (void)recordDecisionCompletedWithSource:(DecisionSource)source
                                   effect:(VisualEffectType)effect
                               confidence:(float)confidence
                                 duration:(NSTimeInterval)duration {
    DecisionEvent *event = [DecisionEvent eventWithType:DecisionEventTypeCompleted];
    event.source = source;
    event.effect = effect;
    event.confidence = confidence;
    event.duration = duration;
    [self recordEvent:event];
    
    self.totalDecisions++;
    self.totalDecisionTime += duration;
    
    // 记录来源类型
    switch (source) {
        case DecisionSourceLLMRealtime:
        case DecisionSourceLLMCache:
            // LLM 相关统计在 recordLLMCall 中处理
            break;
        case DecisionSourceLocalRules:
            // 规则使用
            break;
        case DecisionSourceSelfLearning:
            // 学习使用
            break;
        default:
            break;
    }
}

- (void)recordUserOverrideFromEffect:(VisualEffectType)oldEffect
                            toEffect:(VisualEffectType)newEffect {
    DecisionEvent *event = [DecisionEvent eventWithType:DecisionEventTypeUserOverride];
    event.metadata = @{
        @"oldEffect": @(oldEffect),
        @"newEffect": @(newEffect)
    };
    [self recordEvent:event];
    
    self.totalUserOverrides++;
    
    NSLog(@"📊 Metrics: 记录用户覆盖 %lu -> %lu", (unsigned long)oldEffect, (unsigned long)newEffect);
}

- (void)recordLLMCall:(BOOL)success duration:(NSTimeInterval)duration {
    DecisionEvent *event = [DecisionEvent eventWithType:success ? DecisionEventTypeLLMSuccess : DecisionEventTypeLLMFailed];
    event.duration = duration;
    [self recordEvent:event];
    
    self.totalLLMCalls++;
    if (success) {
        self.totalLLMSuccesses++;
    }
    
    // 更新成本控制
    [self.costControl incrementLLMCalls];
}

- (void)recordCacheHit {
    DecisionEvent *event = [DecisionEvent eventWithType:DecisionEventTypeCacheHit];
    [self recordEvent:event];
    
    self.totalCacheHits++;
}

#pragma mark - Metrics Calculation

- (AgentMetrics *)collectCurrentMetrics {
    return [self collectMetricsForTimeWindow:MetricsTimeWindowAll];
}

- (AgentMetrics *)collectMetricsForTimeWindow:(MetricsTimeWindow)window {
    AgentMetrics *metrics = [AgentMetrics metricsWithDefaults];
    
    NSArray<DecisionEvent *> *filteredEvents = [self eventsInTimeWindow:window];
    
    if (filteredEvents.count == 0) {
        return metrics;
    }
    
    NSInteger decisions = 0;
    NSInteger overrides = 0;
    NSInteger llmCalls = 0;
    NSInteger cacheHits = 0;
    NSTimeInterval totalLatency = 0;
    NSMutableSet *usedEffects = [NSMutableSet set];
    
    for (DecisionEvent *event in filteredEvents) {
        switch (event.type) {
            case DecisionEventTypeCompleted:
                decisions++;
                totalLatency += event.duration;
                [usedEffects addObject:@(event.effect)];
                break;
            case DecisionEventTypeUserOverride:
                overrides++;
                break;
            case DecisionEventTypeLLMCalled:
            case DecisionEventTypeLLMSuccess:
            case DecisionEventTypeLLMFailed:
                llmCalls++;
                break;
            case DecisionEventTypeCacheHit:
                cacheHits++;
                break;
            default:
                break;
        }
    }
    
    metrics.totalDecisions = decisions;
    metrics.userSatisfaction = [self calculateUserSatisfactionFromEvents:filteredEvents];
    metrics.llmCallRate = (decisions > 0) ? (float)llmCalls / (float)decisions : 0;
    metrics.overrideRate = (decisions > 0) ? (float)overrides / (float)decisions : 0;
    metrics.cacheHitRate = (llmCalls + cacheHits > 0) ? (float)cacheHits / (float)(llmCalls + cacheHits) : 0;
    metrics.decisionLatency = (decisions > 0) ? totalLatency / decisions : 0;
    
    // 多样性 = 使用的特效种类数 / 最大可能种类数 (假设 20 种)
    metrics.styleDiversity = MIN(1.0, (float)usedEffects.count / 20.0);
    
    return metrics;
}

- (AgentMetrics *)collectMetricsForStyle:(MusicStyle)style {
    AgentMetrics *metrics = [AgentMetrics metricsWithDefaults];
    
    NSMutableArray *filteredEvents = [NSMutableArray array];
    for (DecisionEvent *event in self.events) {
        if (event.style == style) {
            [filteredEvents addObject:event];
        }
    }
    
    if (filteredEvents.count == 0) {
        return metrics;
    }
    
    // 计算该风格的指标...（与上面类似）
    
    return metrics;
}

- (NSArray<DecisionEvent *> *)eventsInTimeWindow:(MetricsTimeWindow)window {
    if (window == MetricsTimeWindowAll) {
        return [self.events copy];
    }
    
    NSDate *cutoffDate;
    NSDate *now = [NSDate date];
    
    switch (window) {
        case MetricsTimeWindowHour:
            cutoffDate = [now dateByAddingTimeInterval:-3600];
            break;
        case MetricsTimeWindowDay:
            cutoffDate = [now dateByAddingTimeInterval:-86400];
            break;
        case MetricsTimeWindowWeek:
            cutoffDate = [now dateByAddingTimeInterval:-604800];
            break;
        case MetricsTimeWindowMonth:
            cutoffDate = [now dateByAddingTimeInterval:-2592000];
            break;
        default:
            return [self.events copy];
    }
    
    NSMutableArray *filtered = [NSMutableArray array];
    for (DecisionEvent *event in self.events) {
        if ([event.timestamp compare:cutoffDate] != NSOrderedAscending) {
            [filtered addObject:event];
        }
    }
    
    return filtered;
}

#pragma mark - Satisfaction Calculation

- (float)calculateUserSatisfaction {
    return [self calculateUserSatisfactionFromEvents:self.events];
}

- (float)calculateUserSatisfactionFromEvents:(NSArray<DecisionEvent *> *)events {
    if (events.count == 0) return 0.5;
    
    NSInteger decisions = 0;
    NSInteger overrides = 0;
    NSInteger highConfidence = 0;
    
    for (DecisionEvent *event in events) {
        if (event.type == DecisionEventTypeCompleted) {
            decisions++;
            if (event.confidence > 0.7) {
                highConfidence++;
            }
        } else if (event.type == DecisionEventTypeUserOverride) {
            overrides++;
        }
    }
    
    if (decisions == 0) return 0.5;
    
    // 满意度 = (1 - 覆盖率) * 0.6 + 高置信度比例 * 0.4
    float overrideRate = (float)overrides / (float)decisions;
    float highConfidenceRate = (float)highConfidence / (float)decisions;
    
    return (1.0 - overrideRate) * 0.6 + highConfidenceRate * 0.4;
}

- (float)calculateStyleDiversity {
    NSMutableSet *usedEffects = [NSMutableSet set];
    NSInteger recentCount = 0;
    
    for (NSInteger i = self.events.count - 1; i >= 0 && recentCount < 50; i--) {
        DecisionEvent *event = self.events[i];
        if (event.type == DecisionEventTypeCompleted) {
            [usedEffects addObject:@(event.effect)];
            recentCount++;
        }
    }
    
    return MIN(1.0, (float)usedEffects.count / 15.0);
}

- (float)calculateLLMCallRate {
    if (self.totalDecisions == 0) return 0;
    return (float)self.totalLLMCalls / (float)self.totalDecisions;
}

- (float)calculateOverrideRate {
    if (self.totalDecisions == 0) return 0;
    return (float)self.totalUserOverrides / (float)self.totalDecisions;
}

- (float)calculateCacheHitRate {
    NSInteger total = self.totalLLMCalls + self.totalCacheHits;
    if (total == 0) return 0;
    return (float)self.totalCacheHits / (float)total;
}

- (NSTimeInterval)calculateAverageDecisionLatency {
    if (self.totalDecisions == 0) return 0;
    return self.totalDecisionTime / self.totalDecisions;
}

#pragma mark - Trend Analysis

- (NSDictionary<NSString *, NSNumber *> *)getMetricsTrend:(MetricsTimeWindow)current
                                               compareTo:(MetricsTimeWindow)previous {
    AgentMetrics *currentMetrics = [self collectMetricsForTimeWindow:current];
    AgentMetrics *previousMetrics = [self collectMetricsForTimeWindow:previous];
    
    return @{
        @"satisfaction": @(currentMetrics.userSatisfaction - previousMetrics.userSatisfaction),
        @"llmRate": @(currentMetrics.llmCallRate - previousMetrics.llmCallRate),
        @"diversity": @(currentMetrics.styleDiversity - previousMetrics.styleDiversity),
        @"overrideRate": @(currentMetrics.overrideRate - previousMetrics.overrideRate),
        @"latency": @(currentMetrics.decisionLatency - previousMetrics.decisionLatency)
    };
}

- (NSArray<MetricsSnapshot *> *)getMetricsHistory:(NSInteger)count {
    NSInteger start = MAX(0, (NSInteger)self.snapshots.count - count);
    return [self.snapshots subarrayWithRange:NSMakeRange(start, self.snapshots.count - start)];
}

#pragma mark - Cost Control

- (BOOL)shouldForceLocalStrategy {
    return self.costControl.forceLocalOnBudgetExceeded && [self.costControl isBudgetExceeded];
}

- (NSInteger)remainingLLMBudgetToday {
    [self.costControl resetIfNeeded];
    return MAX(0, self.costControl.dailyLLMBudget - self.costControl.currentLLMCalls);
}

- (void)resetDailyBudget {
    self.costControl.currentLLMCalls = 0;
    self.costControl.budgetResetDate = [NSDate date];
    [self saveCostControl];
}

#pragma mark - Reports

- (NSString *)generateSummaryReport {
    AgentMetrics *metrics = [self collectCurrentMetrics];
    
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"======================================\n"];
    [report appendString:@"   Agent 指标摘要报告\n"];
    [report appendFormat:@"   生成时间: %@\n", [NSDate date]];
    [report appendString:@"======================================\n\n"];
    
    [report appendFormat:@"📊 总决策数: %ld\n", (long)self.totalDecisions];
    [report appendFormat:@"📈 用户满意度: %.1f%%\n", metrics.userSatisfaction * 100];
    [report appendFormat:@"🤖 LLM 调用率: %.1f%%\n", metrics.llmCallRate * 100];
    [report appendFormat:@"📦 缓存命中率: %.1f%%\n", metrics.cacheHitRate * 100];
    [report appendFormat:@"🔄 用户覆盖率: %.1f%%\n", metrics.overrideRate * 100];
    [report appendFormat:@"🎨 风格多样性: %.1f%%\n", metrics.styleDiversity * 100];
    [report appendFormat:@"⏱️ 平均延迟: %.2f秒\n\n", metrics.decisionLatency];
    
    [report appendString:@"--- 成本控制 ---\n"];
    [report appendFormat:@"  今日 LLM 调用: %ld / %ld\n",
     (long)self.costControl.currentLLMCalls, (long)self.costControl.dailyLLMBudget];
    [report appendFormat:@"  剩余预算: %ld\n", (long)[self remainingLLMBudgetToday]];
    
    [report appendString:@"\n======================================\n"];
    
    return report;
}

- (NSDictionary *)getRealTimeStats {
    AgentMetrics *metrics = [self collectCurrentMetrics];
    
    return @{
        @"totalDecisions": @(self.totalDecisions),
        @"userSatisfaction": @(metrics.userSatisfaction),
        @"llmCallRate": @(metrics.llmCallRate),
        @"cacheHitRate": @(metrics.cacheHitRate),
        @"overrideRate": @(metrics.overrideRate),
        @"styleDiversity": @(metrics.styleDiversity),
        @"avgLatency": @(metrics.decisionLatency),
        @"todayLLMCalls": @(self.costControl.currentLLMCalls),
        @"llmBudget": @(self.costControl.dailyLLMBudget),
        @"budgetExceeded": @([self.costControl isBudgetExceeded])
    };
}

#pragma mark - Persistence

- (void)saveMetrics {
    [self saveEvents];
    [self saveSnapshots];
    [self saveCostControl];
    [self saveCounters];
}

- (void)loadMetrics {
    [self loadEvents];
    [self loadSnapshots];
    [self loadCostControl];
    [self loadCounters];
}

- (void)saveEvents {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kMetricsEventsFile];
    
    @try {
        NSMutableArray *eventDicts = [NSMutableArray array];
        for (DecisionEvent *event in self.events) {
            [eventDicts addObject:@{
                @"type": @(event.type),
                @"timestamp": event.timestamp ?: [NSDate date],
                @"songName": event.songName ?: @"",
                @"style": @(event.style),
                @"effect": @(event.effect),
                @"source": @(event.source),
                @"confidence": @(event.confidence),
                @"duration": @(event.duration)
            }];
        }
        [eventDicts writeToFile:path atomically:YES];
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Metrics: 保存事件失败: %@", exception.reason);
    }
}

- (void)loadEvents {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kMetricsEventsFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSArray *eventDicts = [NSArray arrayWithContentsOfFile:path];
            for (NSDictionary *dict in eventDicts) {
                DecisionEvent *event = [[DecisionEvent alloc] init];
                event.type = [dict[@"type"] unsignedIntegerValue];
                event.timestamp = dict[@"timestamp"];
                event.songName = dict[@"songName"];
                event.style = [dict[@"style"] unsignedIntegerValue];
                event.effect = [dict[@"effect"] unsignedIntegerValue];
                event.source = [dict[@"source"] unsignedIntegerValue];
                event.confidence = [dict[@"confidence"] floatValue];
                event.duration = [dict[@"duration"] doubleValue];
                [self.events addObject:event];
            }
            NSLog(@"📂 Metrics: 加载事件 %lu 条", (unsigned long)self.events.count);
        } @catch (NSException *exception) {
            NSLog(@"⚠️ Metrics: 加载事件失败: %@", exception.reason);
        }
    }
}

- (void)saveSnapshots {
    // 快照保存逻辑（简化版）
}

- (void)loadSnapshots {
    // 快照加载逻辑（简化版）
}

- (void)saveCostControl {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kCostControlFile];
    
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.costControl requiringSecureCoding:YES error:nil];
        [data writeToFile:path atomically:YES];
    } @catch (NSException *exception) {
        NSLog(@"⚠️ Metrics: 保存成本控制失败: %@", exception.reason);
    }
}

- (void)loadCostControl {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kCostControlFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[CostControlConfig class], [NSDate class], nil];
            CostControlConfig *config = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (config) {
                self.costControl = config;
                [self.costControl resetIfNeeded];
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ Metrics: 加载成本控制失败: %@", exception.reason);
        }
    }
}

- (void)saveCounters {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:@"Counters.plist"];
    
    NSDictionary *counters = @{
        @"totalDecisions": @(self.totalDecisions),
        @"totalLLMCalls": @(self.totalLLMCalls),
        @"totalLLMSuccesses": @(self.totalLLMSuccesses),
        @"totalCacheHits": @(self.totalCacheHits),
        @"totalUserOverrides": @(self.totalUserOverrides),
        @"totalDecisionTime": @(self.totalDecisionTime)
    };
    
    [counters writeToFile:path atomically:YES];
}

- (void)loadCounters {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:@"Counters.plist"];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        NSDictionary *counters = [NSDictionary dictionaryWithContentsOfFile:path];
        self.totalDecisions = [counters[@"totalDecisions"] integerValue];
        self.totalLLMCalls = [counters[@"totalLLMCalls"] integerValue];
        self.totalLLMSuccesses = [counters[@"totalLLMSuccesses"] integerValue];
        self.totalCacheHits = [counters[@"totalCacheHits"] integerValue];
        self.totalUserOverrides = [counters[@"totalUserOverrides"] integerValue];
        self.totalDecisionTime = [counters[@"totalDecisionTime"] doubleValue];
        
        NSLog(@"📂 Metrics: 加载计数器 - 总决策数 %ld", (long)self.totalDecisions);
    }
}

- (void)clearHistory {
    [self.events removeAllObjects];
    [self.snapshots removeAllObjects];
    self.totalDecisions = 0;
    self.totalLLMCalls = 0;
    self.totalLLMSuccesses = 0;
    self.totalCacheHits = 0;
    self.totalUserOverrides = 0;
    self.totalDecisionTime = 0;
    
    [self saveMetrics];
    NSLog(@"📊 Metrics: 历史数据已清除");
}

@end
