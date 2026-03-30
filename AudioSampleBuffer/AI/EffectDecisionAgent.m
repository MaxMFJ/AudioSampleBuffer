//
//  EffectDecisionAgent.m
//  AudioSampleBuffer
//
//  Planning + Reflection Agent 实现
//

#import "EffectDecisionAgent.h"
#import "MusicAIAnalyzer.h"
#import "AIColorConfiguration.h"
#import "LLMAPISettings.h"
#import "AgentGoalManager.h"
#import "AgentPlanner.h"
#import "AgentReflectionEngine.h"
#import "AgentMetricsCollector.h"

#pragma mark - Constants

static NSString *const kLLMDecisionCacheFile = @"LLMDecisionCache.plist";
static NSString *const kHistoryRecordsFile = @"DecisionHistory.plist";
static NSString *const kLearnedWeightsFile = @"LearnedWeights.plist";

// 通知
NSString *const kEffectDecisionAgentDidCompleteNotification = @"EffectDecisionAgentDidCompleteNotification";
NSString *const kEffectDecisionAgentDidStartAnalysisNotification = @"EffectDecisionAgentDidStartAnalysisNotification";
NSString *const kEffectDecisionAgentDidLearnNotification = @"EffectDecisionAgentDidLearnNotification";

#pragma mark - DecisionHistoryRecord

@implementation DecisionHistoryRecord

+ (BOOL)supportsSecureCoding {
    return YES;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeObject:self.songName forKey:@"songName"];
    [coder encodeObject:self.artist forKey:@"artist"];
    [coder encodeInteger:self.style forKey:@"style"];
    [coder encodeInteger:self.selectedEffect forKey:@"selectedEffect"];
    [coder encodeInteger:self.source forKey:@"source"];
    [coder encodeFloat:self.initialConfidence forKey:@"initialConfidence"];
    [coder encodeFloat:self.userSatisfaction forKey:@"userSatisfaction"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
    [coder encodeDouble:self.listeningDuration forKey:@"listeningDuration"];
    [coder encodeBool:self.wasSkipped forKey:@"wasSkipped"];
    [coder encodeBool:self.wasManuallyChanged forKey:@"wasManuallyChanged"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _songName = [coder decodeObjectOfClass:[NSString class] forKey:@"songName"];
        _artist = [coder decodeObjectOfClass:[NSString class] forKey:@"artist"];
        _style = [coder decodeIntegerForKey:@"style"];
        _selectedEffect = [coder decodeIntegerForKey:@"selectedEffect"];
        _source = [coder decodeIntegerForKey:@"source"];
        _initialConfidence = [coder decodeFloatForKey:@"initialConfidence"];
        _userSatisfaction = [coder decodeFloatForKey:@"userSatisfaction"];
        _timestamp = [coder decodeObjectOfClass:[NSDate class] forKey:@"timestamp"];
        _listeningDuration = [coder decodeDoubleForKey:@"listeningDuration"];
        _wasSkipped = [coder decodeBoolForKey:@"wasSkipped"];
        _wasManuallyChanged = [coder decodeBoolForKey:@"wasManuallyChanged"];
    }
    return self;
}

@end

#pragma mark - EffectDecision

@implementation EffectDecision

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)decisionWithEffect:(VisualEffectType)effect
                        confidence:(float)confidence
                            source:(DecisionSource)source {
    EffectDecision *decision = [[EffectDecision alloc] init];
    decision.effectType = effect;
    decision.confidence = confidence;
    decision.source = source;
    decision.fallbackEffect = VisualEffectTypeClassicSpectrum;
    decision.retryCount = 0;
    return decision;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.effectType forKey:@"effectType"];
    [coder encodeInteger:self.fallbackEffect forKey:@"fallbackEffect"];
    [coder encodeObject:self.parameters forKey:@"parameters"];
    [coder encodeFloat:self.confidence forKey:@"confidence"];
    [coder encodeInteger:self.source forKey:@"source"];
    [coder encodeObject:self.reasoning forKey:@"reasoning"];
    [coder encodeInteger:self.retryCount forKey:@"retryCount"];
    [coder encodeObject:self.segmentEffects forKey:@"segmentEffects"];
    [coder encodeObject:self.llmRawResponse forKey:@"llmRawResponse"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _effectType = [coder decodeIntegerForKey:@"effectType"];
        _fallbackEffect = [coder decodeIntegerForKey:@"fallbackEffect"];
        _parameters = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"parameters"];
        _confidence = [coder decodeFloatForKey:@"confidence"];
        _source = [coder decodeIntegerForKey:@"source"];
        _reasoning = [coder decodeObjectOfClass:[NSString class] forKey:@"reasoning"];
        _retryCount = [coder decodeIntegerForKey:@"retryCount"];
        _segmentEffects = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"segmentEffects"];
        _llmRawResponse = [coder decodeObjectOfClass:[NSDictionary class] forKey:@"llmRawResponse"];
    }
    return self;
}

- (NSString *)description {
    NSArray *sourceNames = @[@"UserPreference", @"LocalRules", @"LLMCache", @"LLMRealtime", @"Fallback", @"SelfLearning"];
    NSString *sourceName = self.source < sourceNames.count ? sourceNames[self.source] : @"Unknown";
    return [NSString stringWithFormat:@"<EffectDecision: effect=%lu, confidence=%.2f, source=%@, retries=%ld, reason=%@>",
            (unsigned long)self.effectType, self.confidence, sourceName, (long)self.retryCount, self.reasoning ?: @"none"];
}

@end

#pragma mark - AgentConfiguration

@implementation AgentConfiguration

+ (instancetype)defaultConfiguration {
    AgentConfiguration *config = [[AgentConfiguration alloc] init];
    config.localRulesConfidenceThreshold = 0.7;
    config.userPreferenceConfidenceThreshold = 0.6;
    config.selfLearningWeight = 0.3;
    config.maxLLMRetries = 4;           // DeepSeek 响应较慢，多给几次机会
    config.llmTimeout = 35.0;          // 单次请求超时 35 秒（DeepSeek 通常 10-25 秒返回）
    config.enableSelfLearning = YES;
    config.enableDirectLLMCall = YES;
    config.historyRecordLimit = 1000;
    return config;
}

@end

#pragma mark - EffectDecisionAgent

@interface EffectDecisionAgent () <StrategyManagerProtocol>

@property (nonatomic, strong) EffectDecision *currentDecision;
@property (nonatomic, assign) BOOL isDeciding;
@property (nonatomic, assign) BOOL isCallingLLM;

// Planning + Reflection 组件
@property (nonatomic, strong) AgentGoalManager *goalManager;
@property (nonatomic, strong) AgentPlanner *planner;
@property (nonatomic, strong) AgentReflectionEngine *reflectionEngine;
@property (nonatomic, strong) AgentMetricsCollector *metricsCollector;
@property (nonatomic, strong) ExecutionPlan *currentPlan;

// 策略优先级
@property (nonatomic, assign) float llmPriority;
@property (nonatomic, assign) float rulePriority;

// 规则映射表
@property (nonatomic, strong) NSDictionary<NSNumber *, NSArray<NSNumber *> *> *styleEffectMapping;
@property (nonatomic, strong) NSDictionary<NSNumber *, NSDictionary<NSNumber *, NSNumber *> *> *segmentEffectBias;

// 缓存
@property (nonatomic, strong) NSMutableDictionary<NSString *, EffectDecision *> *llmDecisionCache;
@property (nonatomic, strong) NSString *cacheDirectory;

// 历史和学习
@property (nonatomic, strong) NSMutableArray<DecisionHistoryRecord *> *historyRecords;
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSMutableDictionary *> *learnedWeights;
@property (nonatomic, strong) NSString *currentSongName;
@property (nonatomic, copy) NSString *currentArtist;
@property (nonatomic, strong) NSDate *songStartTime;
@property (nonatomic, strong) NSDate *decisionStartTime;

// 当前状态
@property (nonatomic, assign) MusicStyle currentStyle;
@property (nonatomic, assign) MusicSegment currentSegment;

// 统计
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSNumber *> *statistics;

// 网络
@property (nonatomic, strong) NSURLSession *urlSession;

@end

@implementation EffectDecisionAgent

#pragma mark - Singleton

+ (instancetype)sharedAgent {
    static EffectDecisionAgent *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[EffectDecisionAgent alloc] init];
    });
    return instance;
}

#pragma mark - Initialization

- (instancetype)init {
    self = [super init];
    if (self) {
        _autoModeEnabled = YES;
        _configuration = [AgentConfiguration defaultConfiguration];
        _isDeciding = NO;
        _isCallingLLM = NO;
        _currentStyle = MusicStyleUnknown;
        _currentSegment = MusicSegmentUnknown;
        
        // 初始化策略优先级
        _llmPriority = 0.5;
        _rulePriority = 0.5;
        
        _llmDecisionCache = [NSMutableDictionary dictionary];
        _historyRecords = [NSMutableArray array];
        _learnedWeights = [NSMutableDictionary dictionary];
        _statistics = [NSMutableDictionary dictionaryWithDictionary:@{
            @"totalDecisions": @0,
            @"llmCalls": @0,
            @"llmSuccesses": @0,
            @"llmFailures": @0,
            @"cacheHits": @0,
            @"localRulesUsed": @0,
            @"selfLearningUsed": @0
        }];
        
        [self setupCacheDirectory];
        [self setupURLSession];
        [self setupStyleEffectMapping];
        [self setupSegmentEffectBias];
        [self loadAllCaches];
        
        // 初始化 Planning + Reflection 组件
        [self setupPlanningReflectionComponents];
    }
    return self;
}

#pragma mark - Planning + Reflection Setup

- (void)setupPlanningReflectionComponents {
    // 获取各组件单例
    _goalManager = [AgentGoalManager sharedManager];
    _planner = [AgentPlanner sharedPlanner];
    _reflectionEngine = [AgentReflectionEngine sharedEngine];
    _metricsCollector = [AgentMetricsCollector sharedCollector];
    
    // 设置反思引擎的策略管理器
    _reflectionEngine.strategyManager = self;
    
    // 加载保存的策略状态
    [self loadStrategyState];
    
    NSLog(@"🧠 Planning + Reflection Agent 初始化完成");
    NSLog(@"   GoalManager: %@", _goalManager.currentWeights);
    NSLog(@"   Planner: 历史计划 %lu 条", (unsigned long)_planner.planHistory.count);
    NSLog(@"   ReflectionEngine: 决策记录 %lu 条 (紧急模式: %@)", 
          (unsigned long)_reflectionEngine.decisionRecords.count,
          _reflectionEngine.isEmergencyMode ? @"是" : @"否");
    NSLog(@"   策略权重: LLM=%.2f, Rule=%.2f", self.llmPriority, self.rulePriority);
}

#pragma mark - Setup

- (void)setupCacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *cachesDir = [paths firstObject];
    self.cacheDirectory = [cachesDir stringByAppendingPathComponent:@"EffectDecisionAgent"];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    if (![fm fileExistsAtPath:self.cacheDirectory]) {
        [fm createDirectoryAtPath:self.cacheDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
}

- (void)setupURLSession {
    NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
    NSTimeInterval timeout = MAX(25.0, self.configuration.llmTimeout);  // 至少 25 秒
    config.timeoutIntervalForRequest = timeout;
    config.timeoutIntervalForResource = timeout * 2;  // 整体资源超时
    self.urlSession = [NSURLSession sessionWithConfiguration:config];
    NSLog(@"🌐 LLM 请求超时设置: %.0f 秒", timeout);
}

- (void)setupStyleEffectMapping {
    self.styleEffectMapping = @{
        @(MusicStyleElectronic): @[
            @(VisualEffectTypeWormholeDrive),
            @(VisualEffectTypeNeonGlow),
            @(VisualEffectTypeCyberPunk),
            @(VisualEffectTypeNeonSpringLines),
            @(VisualEffectTypeQuantumField),
            @(VisualEffectTypeHolographic)
        ],
        @(MusicStyleRock): @[
            @(VisualEffectTypeLightning),
            @(VisualEffectType3DWaveform),
            @(VisualEffectTypeParticleFlow),
            @(VisualEffectTypeFireworks),
            @(VisualEffectTypeFluidSimulation)
        ],
        @(MusicStyleMetal): @[
            @(VisualEffectTypeLightning),
            @(VisualEffectTypeQuantumField),
            @(VisualEffectType3DWaveform),
            @(VisualEffectTypeLiquidMetal),
            @(VisualEffectTypeFireworks)
        ],
        @(MusicStyleClassical): @[
            @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeGalaxy),
            @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeCircularWave),
            @(VisualEffectTypeCherryBlossomSnow)
        ],
        @(MusicStyleJazz): @[
            @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeCircularWave),
            @(VisualEffectTypeStarVortex),
            @(VisualEffectTypeGalaxy)
        ],
        @(MusicStyleHipHop): @[
            @(VisualEffectTypeNeonSpringLines),
            @(VisualEffectTypeClassicSpectrum),
            @(VisualEffectTypeCyberPunk),
            @(VisualEffectTypeNeonGlow),
            @(VisualEffectType3DWaveform)
        ],
        @(MusicStylePop): @[
            @(VisualEffectTypeParticleFlow),
            @(VisualEffectTypeNeonGlow),
            @(VisualEffectTypeCircularWave),
            @(VisualEffectTypeCherryBlossomSnow),
            @(VisualEffectTypeHolographic)
        ],
        @(MusicStyleAmbient): @[
            @(VisualEffectTypeWormholeDrive),
            @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeGalaxy),
            @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeCherryBlossomSnow),
            @(VisualEffectTypeCircularWave)
        ],
        @(MusicStyleDance): @[
            @(VisualEffectTypeNeonGlow),
            @(VisualEffectTypeCyberPunk),
            @(VisualEffectTypeWormholeDrive),
            @(VisualEffectTypeQuantumField),
            @(VisualEffectTypeNeonSpringLines),
            @(VisualEffectTypeFireworks)
        ],
        @(MusicStyleRnB): @[
            @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeNeonGlow),
            @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeParticleFlow),
            @(VisualEffectTypeCircularWave)
        ],
        @(MusicStyleCountry): @[
            @(VisualEffectTypeCherryBlossomSnow),
            @(VisualEffectTypeGalaxy),
            @(VisualEffectTypeCircularWave),
            @(VisualEffectTypeStarVortex),
            @(VisualEffectTypeAuroraRipples)
        ],
        @(MusicStyleAcoustic): @[
            @(VisualEffectTypeCircularWave),
            @(VisualEffectTypeCherryBlossomSnow),
            @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeGalaxy)
        ]
    };
}

- (void)setupSegmentEffectBias {
    self.segmentEffectBias = @{
        @(MusicSegmentIntro): @{
            @(VisualEffectTypeNeonGlow): @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeLightning): @(VisualEffectTypeCircularWave),
        },
        @(MusicSegmentChorus): @{
            @(VisualEffectTypeAuroraRipples): @(VisualEffectTypeGalaxy),
            @(VisualEffectTypeCircularWave): @(VisualEffectTypeParticleFlow),
            @(VisualEffectTypeTyndallBeam): @(VisualEffectTypeQuantumField),
            @(VisualEffectTypeNeonGlow): @(VisualEffectTypeCyberPunk),
            @(VisualEffectTypeGalaxy): @(VisualEffectTypeWormholeDrive),
            @(VisualEffectTypeStarVortex): @(VisualEffectTypeWormholeDrive),
        },
        @(MusicSegmentOutro): @{
            @(VisualEffectTypeLightning): @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeCyberPunk): @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeWormholeDrive): @(VisualEffectTypeTyndallBeam),
        }
    };
}

#pragma mark - Configuration Properties

- (float)localRulesConfidenceThreshold {
    return self.configuration.localRulesConfidenceThreshold;
}

- (void)setLocalRulesConfidenceThreshold:(float)threshold {
    self.configuration.localRulesConfidenceThreshold = threshold;
}

- (float)userPreferenceConfidenceThreshold {
    return self.configuration.userPreferenceConfidenceThreshold;
}

- (void)setUserPreferenceConfidenceThreshold:(float)threshold {
    self.configuration.userPreferenceConfidenceThreshold = threshold;
}

- (NSDictionary<NSString *, NSNumber *> *)decisionStatistics {
    return [self.statistics copy];
}

#pragma mark - Planning + Reflection Agent 主流程

- (void)runAgentForSong:(NSString *)songName
                 artist:(nullable NSString *)artist
             completion:(EffectDecisionCompletion)completion {
    
    if (self.isDeciding) {
        NSLog(@"⚠️ Agent 已在决策中，跳过");
        return;
    }
    
    self.isDeciding = YES;
    self.currentSongName = songName;
    self.currentArtist = artist;
    self.songStartTime = [NSDate date];
    self.decisionStartTime = [NSDate date];
    
    NSLog(@"🧠 Planning Agent 开始: %@ - %@", songName, artist ?: @"Unknown");
    
    // 记录决策开始事件
    [self.metricsCollector recordDecisionStartedForSong:songName];
    
    // 1️⃣ 检查成本控制
    if ([self.metricsCollector shouldForceLocalStrategy]) {
        NSLog(@"💰 成本预算已超限，强制使用本地策略");
        EffectDecision *localDecision = [self makeLocalRulesDecisionForSong:songName artist:artist];
        localDecision.reasoning = @"成本控制：今日 LLM 预算已用完";
        [self finalizePlanningDecision:localDecision completion:completion];
        return;
    }
    
    // 2️⃣ 生成执行计划
    PlanContext *context = [PlanContext contextWithSongName:songName artist:artist];
    context.hasCachedDecision = (self.llmDecisionCache[[self cacheKeyForSong:songName artist:artist]] != nil);
    context.hasUserPreference = YES;
    
    // 决定是否需要 LLM：
    // - 紧急模式下强制使用 LLM
    // - LLM 优先级高于规则优先级
    // - 没有缓存且配置允许直接 LLM 调用
    BOOL isEmergencyMode = self.reflectionEngine.isEmergencyMode;
    BOOL llmHasPriority = (self.llmPriority > self.rulePriority);
    BOOL noCacheAndLLMEnabled = !context.hasCachedDecision && self.configuration.enableDirectLLMCall;
    
    context.requiresLLM = isEmergencyMode || llmHasPriority || noCacheAndLLMEnabled;
    context.urgency = isEmergencyMode ? 0.9 : 0.5;
    
    NSLog(@"📊 策略状态: LLM=%.2f, Rule=%.2f, 紧急模式=%@, 需要LLM=%@",
          self.llmPriority, self.rulePriority,
          isEmergencyMode ? @"是" : @"否",
          context.requiresLLM ? @"是" : @"否");
    
    ExecutionPlan *plan = [self.planner generatePlanWithContext:context];
    self.currentPlan = plan;
    
    // 3️⃣ 执行计划
    [self executePlan:plan completion:^(EffectDecision *decision) {
        // 4️⃣ 记录决策完成
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:self.decisionStartTime];
        [self.metricsCollector recordDecisionCompletedWithSource:decision.source
                                                          effect:decision.effectType
                                                      confidence:decision.confidence
                                                        duration:duration];
        
        // 5️⃣ 记录到反思引擎
        ReflectionDecisionRecord *reflectionRecord = [ReflectionDecisionRecord recordWithSource:decision.source
                                                                                     wasCorrect:YES
                                                                                          style:self.currentStyle
                                                                                         effect:decision.effectType];
        reflectionRecord.confidence = decision.confidence;
        reflectionRecord.decisionTime = duration;
        reflectionRecord.songName = songName;
        [self.reflectionEngine recordDecision:reflectionRecord];
        
        // 6️⃣ 评估计划
        NSDictionary *planEval = [self.planner evaluatePlan:plan];
        NSLog(@"📋 计划评估: 成功率=%.1f%%, 耗时=%.2fs",
              [planEval[@"successRate"] floatValue] * 100,
              [planEval[@"totalDuration"] floatValue]);
        
        // 7️⃣ 收集指标并调整目标权重
        AgentMetrics *metrics = [self.metricsCollector collectCurrentMetrics];
        [self.goalManager adjustWeightsWithMetrics:metrics];
        [self.goalManager recordMetrics:metrics];
        
        // 8️⃣ 定期执行反思（每 20 次决策）
        NSInteger totalDecisions = [self.statistics[@"totalDecisions"] integerValue];
        if (totalDecisions > 0 && totalDecisions % 20 == 0) {
            [self performReflectionAndUpdate];
        }
        
        // 完成
        [self finalizePlanningDecision:decision completion:completion];
    }];
}

- (void)executePlan:(ExecutionPlan *)plan completion:(void(^)(EffectDecision *))completion {
    __block EffectDecision *finalDecision = nil;
    
    // 获取下一个待执行步骤
    PlanStep *nextStep = [plan nextPendingStep];
    
    if (!nextStep) {
        // 所有步骤完成，使用本地规则作为 fallback
        finalDecision = [self makeLocalRulesDecisionForSong:self.currentSongName artist:self.currentArtist];
        completion(finalDecision);
        return;
    }
    
    [self.planner markStepInProgress:nextStep.stepId inPlan:plan];
    
    switch (nextStep.type) {
        case PlanStepTypeCacheLookup: {
            // 缓存查找
            NSString *cacheKey = [self cacheKeyForSong:self.currentSongName artist:self.currentArtist];
            EffectDecision *cached = self.llmDecisionCache[cacheKey];
            
            if (cached) {
                [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{@"hit": @YES}];
                [self.metricsCollector recordCacheHit];
                cached.source = DecisionSourceLLMCache;
                completion(cached);
                return;
            } else {
                [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{@"hit": @NO}];
            }
            break;
        }
        case PlanStepTypeClassifyStyle: {
            // 风格分类
            MusicStyleClassifier *classifier = [MusicStyleClassifier sharedClassifier];
            MusicStyleResult *result = [classifier preclassifyWithSongName:self.currentSongName artist:self.currentArtist];
            
            if (result) {
                self.currentStyle = result.primaryStyle;
                [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{
                    @"style": @(result.primaryStyle),
                    @"confidence": @(result.primaryConfidence)
                }];
            } else {
                self.currentStyle = MusicStylePop;
                [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{@"style": @(MusicStylePop)}];
            }
            break;
        }
        case PlanStepTypeApplyUserPreferences: {
            // 用户偏好
            UserPreferenceEngine *prefEngine = [UserPreferenceEngine sharedEngine];
            UserContext *context = [UserContext currentContext];
            PreferenceQueryResult *prefResult = [prefEngine preferredEffectForStyle:self.currentStyle context:context];
            
            if (prefResult.confidence >= self.configuration.userPreferenceConfidenceThreshold && prefResult.sampleCount >= 3) {
                [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{
                    @"effect": @(prefResult.preferredEffect),
                    @"confidence": @(prefResult.confidence)
                }];
                
                finalDecision = [EffectDecision decisionWithEffect:prefResult.preferredEffect
                                                        confidence:prefResult.confidence
                                                            source:DecisionSourceUserPreference];
                finalDecision.reasoning = @"基于用户历史偏好";
                completion(finalDecision);
                return;
            } else {
                [self.planner skipStep:nextStep.stepId inPlan:plan reason:@"偏好数据不足"];
            }
            break;
        }
        case PlanStepTypeAssignEffects: {
            // 分配特效
            finalDecision = [self makeLocalRulesDecisionForSong:self.currentSongName artist:self.currentArtist];
            [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{
                @"effect": @(finalDecision.effectType),
                @"confidence": @(finalDecision.confidence)
            }];
            
            // 如果置信度够高，直接返回
            if (finalDecision.confidence >= self.configuration.localRulesConfidenceThreshold) {
                [self incrementStatistic:@"localRulesUsed"];
                completion(finalDecision);
                return;
            }
            break;
        }
        case PlanStepTypeLLMQuery: {
            // LLM 查询
            [self callDeepSeekWithRetry:self.currentSongName artist:self.currentArtist retryCount:0 completion:^(EffectDecision *llmDecision) {
                if (llmDecision) {
                    [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{
                        @"effect": @(llmDecision.effectType),
                        @"confidence": @(llmDecision.confidence)
                    }];
                    
                    // 缓存 LLM 决策
                    NSString *cacheKey = [self cacheKeyForSong:self.currentSongName artist:self.currentArtist];
                    self.llmDecisionCache[cacheKey] = llmDecision;
                    [self saveLLMCacheToDisk];
                    
                    completion(llmDecision);
                } else {
                    [self.planner markStepFailed:nextStep.stepId inPlan:plan withError:[NSError errorWithDomain:@"LLM" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"LLM 调用失败"}]];
                    
                    // 继续执行下一步
                    [self executePlan:plan completion:completion];
                }
            }];
            return;  // 异步返回
        }
        case PlanStepTypeValidateTransitions:
        case PlanStepTypeOptimizeParameters: {
            // 验证/优化步骤 - 简单标记完成
            [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{@"validated": @YES}];
            break;
        }
        case PlanStepTypeFallbackDecision: {
            // 降级决策
            finalDecision = [self makeLocalRulesDecisionForSong:self.currentSongName artist:self.currentArtist];
            finalDecision.source = DecisionSourceFallback;
            finalDecision.reasoning = @"降级到本地规则";
            [self.planner markStepDone:nextStep.stepId inPlan:plan withOutput:@{@"fallback": @YES}];
            completion(finalDecision);
            return;
        }
        default:
            [self.planner skipStep:nextStep.stepId inPlan:plan reason:@"未知步骤类型"];
            break;
    }
    
    // 递归执行下一步
    [self executePlan:plan completion:completion];
}

- (void)runQuickAgentForSong:(NSString *)songName
                      artist:(nullable NSString *)artist
                  completion:(EffectDecisionCompletion)completion {
    
    if (self.isDeciding) {
        NSLog(@"⚠️ Agent 已在决策中，跳过");
        return;
    }
    
    self.isDeciding = YES;
    self.currentSongName = songName;
    self.currentArtist = artist;
    self.decisionStartTime = [NSDate date];
    
    NSLog(@"⚡ Quick Agent 开始: %@ - %@", songName, artist ?: @"Unknown");
    
    // 1. 检查缓存
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    EffectDecision *cached = self.llmDecisionCache[cacheKey];
    
    if (cached) {
        [self.metricsCollector recordCacheHit];
        cached.source = DecisionSourceLLMCache;
        [self finalizePlanningDecision:cached completion:completion];
        return;
    }
    
    // 2. 快速本地规则
    EffectDecision *decision = [self makeLocalRulesDecisionForSong:songName artist:artist];
    [self incrementStatistic:@"localRulesUsed"];
    [self finalizePlanningDecision:decision completion:completion];
}

- (void)finalizePlanningDecision:(EffectDecision *)decision completion:(EffectDecisionCompletion)completion {
    self.currentDecision = decision;
    self.isDeciding = NO;
    
    // 记录用于学习
    if (self.currentSongName) {
        [self recordDecision:decision forSongName:self.currentSongName artist:self.currentArtist style:self.currentStyle];
    }
    
    NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:self.decisionStartTime];
    NSLog(@"✅ Agent 决策完成: %@ (来源=%ld, 耗时=%.2fs)",
          [[VisualEffectRegistry sharedRegistry] effectInfoForType:decision.effectType].name ?: @"Unknown",
          (long)decision.source, duration);
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kEffectDecisionAgentDidCompleteNotification
                                                            object:self
                                                          userInfo:@{@"decision": decision}];
        
        if (completion) {
            completion(decision);
        }
    });
}

- (void)performReflectionAndUpdate {
    NSLog(@"🔍 开始执行反思与策略更新...");
    [self.reflectionEngine reflectAndUpdatePolicy];
    
    // 输出策略建议
    AgentMetrics *metrics = [self.metricsCollector collectCurrentMetrics];
    NSArray *recommendations = [self.goalManager getStrategyRecommendations:metrics];
    
    for (NSString *rec in recommendations) {
        NSLog(@"💡 策略建议: %@", rec);
    }
}

- (AgentMetrics *)getCurrentMetrics {
    return [self.metricsCollector collectCurrentMetrics];
}

- (NSArray<NSString *> *)getStrategyRecommendations {
    AgentMetrics *metrics = [self.metricsCollector collectCurrentMetrics];
    return [self.goalManager getStrategyRecommendations:metrics];
}

#pragma mark - StrategyManagerProtocol

- (void)reduceLLMPriority:(float)amount {
    self.llmPriority = MAX(0.1, self.llmPriority - amount);
    self.rulePriority = MIN(0.9, self.rulePriority + amount);
    NSLog(@"🔧 策略调整: LLM 优先级 -> %.2f, 规则优先级 -> %.2f", self.llmPriority, self.rulePriority);
}

- (void)increaseLLMPriority:(float)amount {
    self.llmPriority = MIN(0.9, self.llmPriority + amount);
    self.rulePriority = MAX(0.1, self.rulePriority - amount);
    NSLog(@"🔧 策略调整: LLM 优先级 -> %.2f, 规则优先级 -> %.2f", self.llmPriority, self.rulePriority);
}

- (void)increaseRulePriority:(float)amount {
    self.rulePriority = MIN(0.9, self.rulePriority + amount);
    self.llmPriority = MAX(0.1, self.llmPriority - amount);
    NSLog(@"🔧 策略调整: 规则优先级 -> %.2f, LLM 优先级 -> %.2f", self.rulePriority, self.llmPriority);
}

- (void)setLLMCallEnabled:(BOOL)enabled {
    self.configuration.enableDirectLLMCall = enabled;
    NSLog(@"🔧 LLM 调用: %@", enabled ? @"启用" : @"禁用");
}

- (float)currentLLMPriority {
    return self.llmPriority;
}

- (float)currentRulePriority {
    return self.rulePriority;
}

- (void)reduceRulePriority:(float)amount {
    self.rulePriority = MAX(0.1, self.rulePriority - amount);
    NSLog(@"🔧 策略调整: 规则优先级 -> %.2f", self.rulePriority);
}

- (void)increaseUserPreferenceWeight:(float)amount {
    UserPreferenceEngine *prefEngine = [UserPreferenceEngine sharedEngine];
    [prefEngine boostUserPreferenceWeight:amount];
    NSLog(@"🔧 策略调整: 用户偏好权重 +%.2f", amount);
}

- (void)enterEmergencyMode {
    NSLog(@"🚨 进入紧急模式: 最大化 LLM 和用户偏好权重");
    self.llmPriority = 0.8;
    self.rulePriority = 0.3;
    UserPreferenceEngine *prefEngine = [UserPreferenceEngine sharedEngine];
    [prefEngine boostUserPreferenceWeight:0.3];
}

- (void)exitEmergencyMode {
    NSLog(@"✅ 退出紧急模式: 恢复默认策略权重");
    self.llmPriority = 0.5;
    self.rulePriority = 0.5;
}

- (void)saveStrategyState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setFloat:self.llmPriority forKey:@"EffectDecisionAgent_LLMPriority"];
    [defaults setFloat:self.rulePriority forKey:@"EffectDecisionAgent_RulePriority"];
    [defaults synchronize];
    NSLog(@"💾 策略状态已保存: LLM=%.2f, Rule=%.2f", self.llmPriority, self.rulePriority);
}

- (void)loadStrategyState {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:@"EffectDecisionAgent_LLMPriority"]) {
        self.llmPriority = [defaults floatForKey:@"EffectDecisionAgent_LLMPriority"];
        self.rulePriority = [defaults floatForKey:@"EffectDecisionAgent_RulePriority"];
        NSLog(@"📂 策略状态已加载: LLM=%.2f, Rule=%.2f", self.llmPriority, self.rulePriority);
    }
}

- (NSString *)exportStrategyReport {
    NSMutableString *report = [NSMutableString string];
    
    [report appendString:@"======================================\n"];
    [report appendString:@"   Agent 策略状态报告\n"];
    [report appendFormat:@"   生成时间: %@\n", [NSDate date]];
    [report appendString:@"======================================\n\n"];
    
    // 策略权重
    [report appendString:@"--- 当前策略权重 ---\n"];
    [report appendFormat:@"  LLM 优先级: %.2f\n", self.llmPriority];
    [report appendFormat:@"  规则优先级: %.2f\n", self.rulePriority];
    [report appendFormat:@"  用户偏好权重: %.2f\n", [UserPreferenceEngine sharedEngine].preferenceWeight];
    [report appendFormat:@"  紧急模式: %@\n\n", self.reflectionEngine.isEmergencyMode ? @"是" : @"否"];
    
    // 成本控制
    [report appendString:@"--- 成本控制 ---\n"];
    [report appendFormat:@"  今日 LLM 调用: %ld / %ld\n",
     (long)self.metricsCollector.costControl.currentLLMCalls,
     (long)self.metricsCollector.costControl.dailyLLMBudget];
    [report appendFormat:@"  剩余预算: %ld\n", (long)[self.metricsCollector remainingLLMBudgetToday]];
    [report appendFormat:@"  超限强制本地: %@\n\n", self.metricsCollector.costControl.forceLocalOnBudgetExceeded ? @"是" : @"否"];
    
    // 决策统计
    [report appendString:@"--- 决策统计 ---\n"];
    [report appendFormat:@"  总决策数: %@\n", self.statistics[@"totalDecisions"]];
    [report appendFormat:@"  LLM 调用: %@\n", self.statistics[@"llmCalls"]];
    [report appendFormat:@"  LLM 成功: %@\n", self.statistics[@"llmSuccesses"]];
    [report appendFormat:@"  LLM 失败: %@\n", self.statistics[@"llmFailures"]];
    [report appendFormat:@"  缓存命中: %@\n", self.statistics[@"cacheHits"]];
    [report appendFormat:@"  本地规则: %@\n", self.statistics[@"localRulesUsed"]];
    [report appendFormat:@"  自学习: %@\n\n", self.statistics[@"selfLearningUsed"]];
    
    // 反思阈值
    ReflectionThresholds *thresholds = self.reflectionEngine.thresholds;
    [report appendString:@"--- 反思阈值配置 ---\n"];
    [report appendFormat:@"  紧急模式触发: <%.0f%%\n", thresholds.emergencyAccuracyThreshold * 100];
    [report appendFormat:@"  高覆盖率阈值: >%.0f%%\n", thresholds.highOverrideRateThreshold * 100];
    [report appendFormat:@"  低来源准确率: <%.0f%%\n", thresholds.lowSourceAccuracyThreshold * 100];
    [report appendFormat:@"  调整步长: %.2f\n\n", thresholds.adjustmentStep];
    
    // LLM 是否会被调用
    BOOL llmEnabled = self.configuration.enableDirectLLMCall;
    BOOL llmHasPriority = (self.llmPriority > self.rulePriority);
    BOOL budgetOK = ![self.metricsCollector shouldForceLocalStrategy];
    [report appendString:@"--- LLM 调用条件 ---\n"];
    [report appendFormat:@"  配置启用: %@\n", llmEnabled ? @"✅" : @"❌"];
    [report appendFormat:@"  优先级高于规则: %@\n", llmHasPriority ? @"✅" : @"❌"];
    [report appendFormat:@"  预算充足: %@\n", budgetOK ? @"✅" : @"❌"];
    [report appendFormat:@"  紧急模式: %@\n", self.reflectionEngine.isEmergencyMode ? @"✅ (强制 LLM)" : @"否"];
    
    BOOL willUseLLM = self.reflectionEngine.isEmergencyMode || (llmEnabled && llmHasPriority && budgetOK);
    [report appendFormat:@"\n  ➡️ LLM 将被调用: %@\n", willUseLLM ? @"是" : @"否"];
    
    [report appendString:@"\n======================================\n"];
    
    return report;
}

#pragma mark - Autonomous Decision (兼容旧 API)

- (void)autonomousDecisionForSong:(NSString *)songName
                           artist:(nullable NSString *)artist
                       completion:(EffectDecisionCompletion)completion {
    
    // 使用新的 Planning Agent 流程
    [self runAgentForSong:songName artist:artist completion:completion];
}

#pragma mark - Primary Effect Decision

- (void)decidePrimaryEffectForSong:(NSString *)songName
                            artist:(nullable NSString *)artist
                          features:(AudioFeatures *)features
                           context:(UserContext *)context
                        completion:(EffectDecisionCompletion)completion {
    
    if (self.isDeciding) {
        NSLog(@"⚠️ 已在决策中，跳过");
        return;
    }
    
    self.isDeciding = YES;
    self.currentSongName = songName;
    self.currentArtist = artist;
    self.songStartTime = [NSDate date];
    [self incrementStatistic:@"totalDecisions"];
    
    NSLog(@"🧠 开始特效决策: %@ - %@", songName, artist ?: @"Unknown");
    
    // Step 1: 分类音乐风格
    MusicStyleClassifier *classifier = [MusicStyleClassifier sharedClassifier];
    MusicStyleResult *styleResult = [classifier classifyWithFeatures:features];
    
    MusicStyleResult *nameResult = [classifier preclassifyWithSongName:songName artist:artist];
    if (nameResult && nameResult.primaryConfidence > styleResult.primaryConfidence) {
        styleResult = nameResult;
    }
    
    self.currentStyle = styleResult.primaryStyle;
    NSLog(@"🎵 音乐风格: %@ (置信度: %.2f)",
          [MusicStyleClassifier nameForStyle:styleResult.primaryStyle],
          styleResult.primaryConfidence);
    
    // Step 2: 检查用户偏好
    UserPreferenceEngine *prefEngine = [UserPreferenceEngine sharedEngine];
    PreferenceQueryResult *prefResult = [prefEngine preferredEffectForStyle:styleResult.primaryStyle context:context];
    
    if (prefResult.confidence >= self.configuration.userPreferenceConfidenceThreshold && prefResult.sampleCount >= 3) {
        EffectDecision *decision = [EffectDecision decisionWithEffect:prefResult.preferredEffect
                                                           confidence:prefResult.confidence
                                                               source:DecisionSourceUserPreference];
        decision.reasoning = [NSString stringWithFormat:@"用户在%@风格下偏好此特效（基于%ld次记录）",
                              [MusicStyleClassifier nameForStyle:styleResult.primaryStyle],
                              (long)prefResult.sampleCount];
        [self finalizeDecision:decision completion:completion];
        return;
    }
    
    // Step 3: 检查自学习
    if (self.configuration.enableSelfLearning) {
        EffectDecision *learnedDecision = [self decisionFromSelfLearningForStyle:styleResult.primaryStyle];
        if (learnedDecision && learnedDecision.confidence >= 0.7) {
            [self incrementStatistic:@"selfLearningUsed"];
            [self finalizeDecision:learnedDecision completion:completion];
            return;
        }
    }
    
    // Step 4: 本地规则匹配
    EffectDecision *localDecision = [self makeLocalRulesDecision:styleResult features:features context:context];
    
    if (localDecision.confidence >= self.configuration.localRulesConfidenceThreshold) {
        [self incrementStatistic:@"localRulesUsed"];
        [self finalizeDecision:localDecision completion:completion];
        return;
    }
    
    // Step 5: 检查 LLM 缓存
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    EffectDecision *cachedDecision = self.llmDecisionCache[cacheKey];
    
    if (cachedDecision) {
        [self incrementStatistic:@"cacheHits"];
        cachedDecision.source = DecisionSourceLLMCache;
        NSLog(@"📦 使用LLM缓存决策");
        [self finalizeDecision:cachedDecision completion:completion];
        return;
    }
    
    // Step 6: 调用 LLM（带重试）
    NSLog(@"🔄 本地规则置信度 %.2f < 阈值 %.2f，尝试调用LLM",
          localDecision.confidence, self.configuration.localRulesConfidenceThreshold);
    
    [self callLLMForDecision:songName artist:artist style:styleResult localDecision:localDecision completion:^(EffectDecision *llmDecision) {
        if (llmDecision) {
            self.llmDecisionCache[cacheKey] = llmDecision;
            [self saveLLMCacheToDisk];
            NSLog(@"✅ LLM决策成功");
            [self finalizeDecision:llmDecision completion:completion];
        } else {
            localDecision.source = DecisionSourceFallback;
            localDecision.reasoning = @"LLM调用失败，使用本地规则降级";
            NSLog(@"⚠️ LLM决策失败，降级到本地规则");
            [self finalizeDecision:localDecision completion:completion];
        }
    }];
}

#pragma mark - Direct LLM API Call

- (void)callDeepSeekDirectly:(NSString *)songName
                      artist:(nullable NSString *)artist
           additionalContext:(nullable NSDictionary *)additionalContext
                  completion:(LLMAnalysisCompletion)completion {
    
    NSLog(@"🔗 直接调用 LLM API: %@ - %@（单次超时 %.0f 秒，请耐心等待）", 
          songName, artist ?: @"Unknown", self.configuration.llmTimeout);
    
    self.isCallingLLM = YES;
    [self incrementStatistic:@"llmCalls"];
    
    NSString *prompt = [self buildPromptForSong:songName artist:artist additionalContext:additionalContext];
    LLMAPISettings *settings = [LLMAPISettings sharedSettings];
    if (settings.apiKey.length == 0) {
        self.isCallingLLM = NO;
        NSError *configError = [NSError errorWithDomain:@"LLMConfiguration"
                                                   code:-1001
                                               userInfo:@{NSLocalizedDescriptionKey: @"请先在 AI 设置中填写 API Key"}];
        [self incrementStatistic:@"llmFailures"];
        completion(nil, configError);
        return;
    }
    
    NSURL *serviceURL = settings.serviceURL;
    if (!serviceURL) {
        self.isCallingLLM = NO;
        NSError *configError = [NSError errorWithDomain:@"LLMConfiguration"
                                                   code:-1002
                                               userInfo:@{NSLocalizedDescriptionKey: @"AI 设置中的 Base URL 无效，请重新填写"}];
        [self incrementStatistic:@"llmFailures"];
        completion(nil, configError);
        return;
    }
    
    NSDictionary *requestBody = @{
        @"model": settings.model,
        @"messages": @[
            @{@"role": @"system", @"content": @"你是一个专业的音乐视觉效果分析师。根据歌曲信息，推荐最合适的视觉特效。返回JSON格式。"},
            @{@"role": @"user", @"content": prompt}
        ],
        @"temperature": @0.7,
        @"max_tokens": @1000
    };
    
    NSError *jsonError;
    NSData *bodyData = [NSJSONSerialization dataWithJSONObject:requestBody options:0 error:&jsonError];
    if (jsonError) {
        self.isCallingLLM = NO;
        completion(nil, jsonError);
        return;
    }
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:serviceURL];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", settings.apiKey] forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        self.isCallingLLM = NO;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"❌ LLM API 错误: %@", error.localizedDescription);
                [self incrementStatistic:@"llmFailures"];
                completion(nil, error);
                return;
            }
            
            // 先检查 HTTP 状态码
            NSHTTPURLResponse *httpResponse = (NSHTTPURLResponse *)response;
            NSInteger statusCode = httpResponse.statusCode;
            NSLog(@"📡 LLM HTTP 状态码: %ld", (long)statusCode);
            
            // 打印原始响应（调试用）
            if (data) {
                NSString *rawResponse = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
                if (rawResponse.length > 500) {
                    NSLog(@"📥 LLM 原始响应 (前500字符): %@...", [rawResponse substringToIndex:500]);
                } else {
                    NSLog(@"📥 LLM 原始响应: %@", rawResponse);
                }
            } else {
                NSLog(@"❌ LLM 响应数据为空");
                completion(nil, [NSError errorWithDomain:@"LLMAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"No data received"}]);
                return;
            }
            
            NSError *parseError;
            NSDictionary *responseDict = [NSJSONSerialization JSONObjectWithData:data options:0 error:&parseError];
            if (parseError || !responseDict) {
                NSLog(@"❌ JSON 解析错误: %@", parseError.localizedDescription);
                [self incrementStatistic:@"llmFailures"];
                completion(nil, parseError);
                return;
            }
            
            // 检查是否有 API 错误信息
            if (responseDict[@"error"]) {
                NSDictionary *errorInfo = responseDict[@"error"];
                NSString *errorMsg = errorInfo[@"message"] ?: @"Unknown API error";
                NSString *errorType = errorInfo[@"type"] ?: @"unknown";
                NSLog(@"❌ LLM API 返回错误: [%@] %@", errorType, errorMsg);
                [self incrementStatistic:@"llmFailures"];
                completion(nil, [NSError errorWithDomain:@"LLMAPI" code:statusCode userInfo:@{NSLocalizedDescriptionKey: errorMsg}]);
                return;
            }
            
            // 提取内容
            NSArray *choices = responseDict[@"choices"];
            if (choices.count > 0) {
                NSDictionary *message = choices[0][@"message"];
                NSString *content = message[@"content"];
                
                // 尝试解析 JSON 内容
                NSDictionary *parsedContent = [self parseJSONFromContent:content];
                if (parsedContent) {
                    NSLog(@"✅ LLM 分析成功");
                    [self incrementStatistic:@"llmSuccesses"];
                    completion(parsedContent, nil);
                } else {
                    NSLog(@"⚠️ 无法解析 LLM 响应内容，使用原始内容");
                    completion(@{@"raw_content": content ?: @""}, nil);
                }
            } else {
                NSLog(@"❌ LLM 响应中没有 choices 数组");
                NSLog(@"📋 完整响应字典: %@", responseDict);
                completion(nil, [NSError errorWithDomain:@"LLMAPI" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Empty choices in response"}]);
            }
        });
    }];
    
    [task resume];
}

- (void)callDeepSeekWithRetry:(NSString *)songName
                       artist:(nullable NSString *)artist
                   retryCount:(NSInteger)retryCount
                   completion:(void(^)(EffectDecision * _Nullable))completion {
    
    if (retryCount >= self.configuration.maxLLMRetries) {
        NSLog(@"❌ LLM 重试次数已达上限 (%ld)", (long)self.configuration.maxLLMRetries);
        // 记录失败的 LLM 调用
        [self.metricsCollector recordLLMCall:NO duration:0];
        completion(nil);
        return;
    }
    
    NSLog(@"🔄 LLM 调用 (尝试 %ld/%ld)", (long)(retryCount + 1), (long)self.configuration.maxLLMRetries);
    NSDate *callStartTime = [NSDate date];
    
    [self callDeepSeekDirectly:songName artist:artist additionalContext:nil completion:^(NSDictionary *response, NSError *error) {
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:callStartTime];
        
        if (error) {
            // 指数退避：3s, 6s, 12s, 24s（给 DeepSeek 足够时间）
            NSTimeInterval delay = pow(2, retryCount) * 3.0;
            NSLog(@"❌ LLM 本次失败: %@", error.localizedDescription);
            NSLog(@"⏳ %.0f 秒后重试 (第 %ld 次重试)...", delay, (long)(retryCount + 1));
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self callDeepSeekWithRetry:songName artist:artist retryCount:retryCount + 1 completion:completion];
            });
            return;
        }
        
        // 记录成功的 LLM 调用
        [self.metricsCollector recordLLMCall:YES duration:duration];
        NSLog(@"💰 成本控制: LLM 调用已记录 (耗时 %.2fs, 剩余预算 %ld)",
              duration, (long)[self.metricsCollector remainingLLMBudgetToday]);
        
        // 解析响应并创建决策
        EffectDecision *decision = [self createDecisionFromLLMResponse:response songName:songName artist:artist];
        decision.retryCount = retryCount;
        completion(decision);
    }];
}

- (NSString *)buildPromptForSong:(NSString *)songName
                          artist:(nullable NSString *)artist
               additionalContext:(nullable NSDictionary *)context {
    
    NSMutableString *prompt = [NSMutableString string];
    [prompt appendFormat:@"分析歌曲《%@》", songName];
    if (artist) {
        [prompt appendFormat:@"（%@）", artist];
    }
    [prompt appendString:@"\n\n请返回JSON格式，包含：\n"];
    [prompt appendString:@"{\n"];
    [prompt appendString:@"  \"style\": \"音乐风格(electronic/rock/pop/ambient/classical/jazz/hiphop/rnb)\",\n"];
    [prompt appendString:@"  \"emotion\": \"情感(calm/happy/sad/energetic/intense)\",\n"];
    [prompt appendString:@"  \"energy\": 0.0-1.0,\n"];
    [prompt appendString:@"  \"bpm\": 估计BPM,\n"];
    [prompt appendString:@"  \"recommended_effect\": 推荐特效ID(0-20的数字),\n"];
    [prompt appendString:@"  \"effect_name\": \"特效名称\",\n"];
    [prompt appendString:@"  \"animation_speed\": 0.5-2.0,\n"];
    [prompt appendString:@"  \"brightness\": 0.5-1.5,\n"];
    [prompt appendString:@"  \"color_scheme\": \"warm/cool/neutral/vibrant\",\n"];
    
    // 新增：特效颜色配置参数
    [prompt appendString:@"  \"effect_color\": {\n"];
    [prompt appendString:@"    \"color_mode\": 0-3 (0=彩虹渐变, 1=单色渐变, 2=双色渐变, 3=自定义主题),\n"];
    [prompt appendString:@"    \"primary_color\": [R,G,B] (0-1范围，如[1.0,0.5,0.2]代表橙色),\n"];
    [prompt appendString:@"    \"secondary_color\": [R,G,B] (用于双色渐变和自定义主题),\n"];
    [prompt appendString:@"    \"saturation\": 0.0-1.0 (颜色饱和度),\n"];
    [prompt appendString:@"    \"brightness_mult\": 0.5-2.0 (亮度倍数),\n"];
    [prompt appendString:@"    \"hue_shift\": 0.0-1.0 (彩虹模式的色相偏移)\n"];
    [prompt appendString:@"  },\n"];
    
    [prompt appendString:@"  \"reasoning\": \"选择原因\"\n"];
    [prompt appendString:@"}\n\n"];
    [prompt appendString:@"可用特效ID与名称（请直接返回数字ID）：\n"];
    [prompt appendString:@"0-经典频谱(支持颜色配置), 1-环形波浪, 2-粒子流, 3-霓虹发光, 4-3D波形, 5-流体模拟, "];
    [prompt appendString:@"6-量子场, 7-全息效果, 8-赛博朋克, 9-音频响应3D, 10-星系银河, 11-闪电, "];
    [prompt appendString:@"12-漂浮光点, 13-液态金属, 14-几何变形, 15-分形图案, 16-极光波纹, "];
    [prompt appendString:@"17-恒星涡旋, 18-霓虹弹簧线, 19-樱花飘雪, 20-丁达尔光束(支持颜色配置)"];
    
    // 颜色配置建议
    [prompt appendString:@"\n\n颜色配置建议：\n"];
    [prompt appendString:@"- 欢快/流行歌曲: 彩虹模式(0)或暖色单色渐变，高饱和度(0.9-1.0)\n"];
    [prompt appendString:@"- 抒情/慢歌: 单色渐变(1)，柔和暖色如[1.0,0.6,0.3]或[0.8,0.5,0.7]\n"];
    [prompt appendString:@"- 电子/舞曲: 彩虹模式(0)或自定义主题(3)，冷色如青蓝[0,0.8,1.0]\n"];
    [prompt appendString:@"- 摇滚/金属: 双色渐变(2)，红黑或橙紫配色，高亮度(1.2-1.5)\n"];
    [prompt appendString:@"- 古典/氛围: 单色渐变(1)，低饱和度(0.5-0.7)，金色或紫色\n"];
    [prompt appendString:@"- 嘻哈/R&B: 自定义主题(3)，紫金或粉蓝配色"];
    
    if (context) {
        [prompt appendFormat:@"\n\n额外上下文: %@", context];
    }
    
    return prompt;
}

- (NSDictionary *)parseJSONFromContent:(NSString *)content {
    if (!content) return nil;
    
    // 尝试提取 JSON 块
    NSRange jsonStart = [content rangeOfString:@"{"];
    NSRange jsonEnd = [content rangeOfString:@"}" options:NSBackwardsSearch];
    
    if (jsonStart.location != NSNotFound && jsonEnd.location != NSNotFound) {
        NSRange jsonRange = NSMakeRange(jsonStart.location, jsonEnd.location - jsonStart.location + 1);
        NSString *jsonString = [content substringWithRange:jsonRange];
        
        NSData *jsonData = [jsonString dataUsingEncoding:NSUTF8StringEncoding];
        NSError *error;
        NSDictionary *result = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&error];
        if (!error && result) {
            return result;
        }
    }
    
    return nil;
}

// 辅助方法：安全解析整数值（兼容字符串和数字）
- (NSInteger)parseIntegerValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value integerValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        return [value integerValue];
    }
    return 0;
}

// 辅助方法：安全解析浮点值（兼容字符串和数字）
- (CGFloat)parseFloatValue:(id)value {
    if ([value isKindOfClass:[NSNumber class]]) {
        return [value floatValue];
    } else if ([value isKindOfClass:[NSString class]]) {
        return [value floatValue];
    }
    return 0.0;
}

- (EffectDecision *)createDecisionFromLLMResponse:(NSDictionary *)response
                                         songName:(NSString *)songName
                                           artist:(NSString *)artist {
    
    EffectDecision *decision = [[EffectDecision alloc] init];
    decision.source = DecisionSourceLLMRealtime;
    decision.llmRawResponse = response;
    
    // 解析推荐特效（可能是字符串 "4" 或数字 4）
    id effectValue = response[@"recommended_effect"];
    if (effectValue) {
        if ([effectValue isKindOfClass:[NSString class]]) {
            decision.effectType = (VisualEffectType)[effectValue integerValue];
        } else if ([effectValue isKindOfClass:[NSNumber class]]) {
            decision.effectType = [effectValue unsignedIntegerValue];
        } else {
            decision.effectType = VisualEffectTypeTyndallBeam;
        }
    } else {
        decision.effectType = VisualEffectTypeTyndallBeam;  // 默认
    }
    
    // 解析参数（同样处理字符串/数字兼容）
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    
    id animSpeed = response[@"animation_speed"];
    if (animSpeed) {
        if ([animSpeed isKindOfClass:[NSString class]]) {
            params[@"animationSpeed"] = @([animSpeed floatValue]);
        } else {
            params[@"animationSpeed"] = animSpeed;
        }
    }
    
    id brightness = response[@"brightness"];
    if (brightness) {
        if ([brightness isKindOfClass:[NSString class]]) {
            params[@"brightness"] = @([brightness floatValue]);
        } else {
            params[@"brightness"] = brightness;
        }
    }
    
    // === 解析颜色配置 ===
    NSDictionary *effectColor = response[@"effect_color"];
    if (effectColor && [effectColor isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *colorConfig = [NSMutableDictionary dictionary];
        
        // 颜色模式 (0=彩虹, 1=单色渐变, 2=双色渐变, 3=自定义主题)
        id colorMode = effectColor[@"color_mode"];
        if (colorMode) {
            NSInteger mode = [self parseIntegerValue:colorMode];
            colorConfig[@"colorMode"] = @(MIN(3, MAX(0, mode)));
        }
        
        // 主色 RGB 数组
        id primaryColor = effectColor[@"primary_color"];
        if (primaryColor && [primaryColor isKindOfClass:[NSArray class]]) {
            NSArray *rgb = primaryColor;
            if (rgb.count >= 3) {
                colorConfig[@"primaryColor"] = @[
                    @([self parseFloatValue:rgb[0]]),
                    @([self parseFloatValue:rgb[1]]),
                    @([self parseFloatValue:rgb[2]])
                ];
            }
        }
        
        // 副色 RGB 数组
        id secondaryColor = effectColor[@"secondary_color"];
        if (secondaryColor && [secondaryColor isKindOfClass:[NSArray class]]) {
            NSArray *rgb = secondaryColor;
            if (rgb.count >= 3) {
                colorConfig[@"secondaryColor"] = @[
                    @([self parseFloatValue:rgb[0]]),
                    @([self parseFloatValue:rgb[1]]),
                    @([self parseFloatValue:rgb[2]])
                ];
            }
        }
        
        // 饱和度
        id saturation = effectColor[@"saturation"];
        if (saturation) {
            CGFloat sat = [self parseFloatValue:saturation];
            colorConfig[@"colorSaturation"] = @(MIN(1.0, MAX(0.0, sat)));
        }
        
        // 亮度倍数
        id brightnessMult = effectColor[@"brightness_mult"];
        if (brightnessMult) {
            CGFloat bm = [self parseFloatValue:brightnessMult];
            colorConfig[@"colorBrightness"] = @(MIN(2.0, MAX(0.5, bm)));
        }
        
        // 色相偏移
        id hueShift = effectColor[@"hue_shift"];
        if (hueShift) {
            CGFloat hs = [self parseFloatValue:hueShift];
            colorConfig[@"hueShift"] = @(fmod(hs, 1.0));
        }
        
        if (colorConfig.count > 0) {
            params[@"effectColor"] = colorConfig;
            NSLog(@"🎨 解析到颜色配置: 模式=%@, 主色=%@",
                  colorConfig[@"colorMode"], colorConfig[@"primaryColor"]);
        }
    }
    
    decision.parameters = params;
    
    // 置信度
    decision.confidence = 0.85;
    
    // 原因
    decision.reasoning = response[@"reasoning"] ?: [NSString stringWithFormat:@"DeepSeek 推荐特效: %@", response[@"effect_name"] ?: @"Unknown"];
    
    NSString *effectName = [[VisualEffectRegistry sharedRegistry] effectInfoForType:decision.effectType].name ?: @"Unknown";
    NSLog(@"🎯 LLM 推荐特效: %@ (ID:%lu), 参数包含颜色配置: %@",
          effectName, (unsigned long)decision.effectType,
          decision.parameters[@"effectColor"] ? @"是" : @"否");
    
    return decision;
}

#pragma mark - LLM Integration (via MusicAIAnalyzer)

- (void)callLLMForDecision:(NSString *)songName
                    artist:(nullable NSString *)artist
                     style:(MusicStyleResult *)styleResult
             localDecision:(EffectDecision *)localDecision
                completion:(void(^)(EffectDecision * _Nullable))completion {
    
    NSLog(@"🤖 调用LLM进行决策: %@ - %@", songName, artist ?: @"Unknown");
    [self incrementStatistic:@"llmCalls"];
    
    MusicAIAnalyzer *analyzer = [MusicAIAnalyzer sharedAnalyzer];
    
    // 检查缓存
    AIColorConfiguration *cachedConfig = [analyzer getCachedConfigurationForSong:songName artist:artist];
    NSLog(@"🔍 检查AI配置缓存: %@", cachedConfig ? @"有缓存" : @"无缓存");
    
    if (cachedConfig) {
        NSLog(@"📦 使用已缓存的AI配置进行决策 (BPM=%ld, 情感=%ld)",
              (long)cachedConfig.bpm, (long)cachedConfig.emotion);
        [self incrementStatistic:@"cacheHits"];
        [self processAIConfig:cachedConfig style:styleResult completion:completion];
        return;
    }
    
    NSLog(@"🔍 MusicAIAnalyzer状态: isAnalyzing=%@", analyzer.isAnalyzing ? @"YES" : @"NO");
    
    // 如果正在分析中，等待通知
    if (analyzer.isAnalyzing) {
        NSLog(@"⏳ MusicAIAnalyzer正在分析中，等待完成...");
        
        __block BOOL handled = NO;
        __block id observer = nil;
        
        observer = [[NSNotificationCenter defaultCenter] addObserverForName:kAIConfigurationDidChangeNotification
                                                                     object:nil
                                                                      queue:[NSOperationQueue mainQueue]
                                                                 usingBlock:^(NSNotification *notification) {
            if (handled) return;
            handled = YES;
            
            if (observer) {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                observer = nil;
            }
            
            AIColorConfiguration *config = notification.userInfo[kAIConfigurationKey];
            if (config) {
                NSLog(@"📬 收到AI分析完成通知，继续决策");
                [self incrementStatistic:@"llmSuccesses"];
                [self processAIConfig:config style:styleResult completion:completion];
            } else {
                NSLog(@"⚠️ AI分析完成但配置为空");
                [self incrementStatistic:@"llmFailures"];
                completion(nil);
            }
        }];
        
        // 超时
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(self.configuration.llmTimeout * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            if (handled) return;
            handled = YES;
            
            if (observer) {
                [[NSNotificationCenter defaultCenter] removeObserver:observer];
                observer = nil;
            }
            
            NSLog(@"⏰ 等待AI分析超时");
            [self incrementStatistic:@"llmFailures"];
            completion(nil);
        });
        return;
    }
    
    // 正常调用
    NSDate *llmStartTime = [NSDate date];
    [analyzer analyzeSong:songName artist:artist completion:^(AIColorConfiguration *config, NSError *error) {
        NSTimeInterval duration = [[NSDate date] timeIntervalSinceDate:llmStartTime];
        
        if (error || !config) {
            NSLog(@"❌ LLM调用失败: %@", error.localizedDescription);
            [self incrementStatistic:@"llmFailures"];
            [self.metricsCollector recordLLMCall:NO duration:duration];
            completion(nil);
            return;
        }
        
        [self incrementStatistic:@"llmSuccesses"];
        [self.metricsCollector recordLLMCall:YES duration:duration];
        NSLog(@"💰 成本控制: LLM 调用已记录 (耗时 %.2fs, 剩余预算 %ld)",
              duration, (long)[self.metricsCollector remainingLLMBudgetToday]);
        [self processAIConfig:config style:styleResult completion:completion];
    }];
}

- (void)processAIConfig:(AIColorConfiguration *)config
                  style:(MusicStyleResult *)styleResult
             completion:(void(^)(EffectDecision * _Nullable))completion {
    
    NSLog(@"📊 处理AI配置: BPM=%ld, 情感=%ld, 能量=%.2f, 风格=%ld",
          (long)config.bpm, (long)config.emotion, config.energy, (long)styleResult.primaryStyle);
    
    VisualEffectType effect = [self effectForEmotion:config.emotion
                                              energy:config.energy
                                               style:styleResult.primaryStyle];
    
    NSString *effectName = [[VisualEffectRegistry sharedRegistry] effectInfoForType:effect].name ?: @"Unknown";
    NSLog(@"🎯 基于情感/能量选择特效: %@ (ID:%lu)", effectName, (unsigned long)effect);
    
    EffectDecision *decision = [EffectDecision decisionWithEffect:effect
                                                       confidence:0.85
                                                           source:DecisionSourceLLMRealtime];
    
    decision.reasoning = [NSString stringWithFormat:@"LLM分析: BPM=%ld, 情感=%ld, 能量=%.2f → 选择%@",
                          (long)config.bpm, (long)config.emotion, config.energy, effectName];
    
    decision.parameters = @{
        @"animationSpeed": @(config.animationSpeed),
        @"brightness": @(config.brightnessMultiplier),
    };
    
    decision.segmentEffects = @{
        @(MusicSegmentIntro): @(VisualEffectTypeAuroraRipples),
        @(MusicSegmentVerse): @(effect),
        @(MusicSegmentChorus): @([self intensifiedEffect:effect]),
        @(MusicSegmentBridge): @(effect),
        @(MusicSegmentOutro): @(VisualEffectTypeCherryBlossomSnow),
    };
    
    NSLog(@"✅ LLM决策完成: 特效=%@", effectName);
    completion(decision);
}

#pragma mark - Local Rules Decision

- (EffectDecision *)makeLocalRulesDecisionForSong:(NSString *)songName artist:(NSString *)artist {
    MusicStyleClassifier *classifier = [MusicStyleClassifier sharedClassifier];
    MusicStyleResult *styleResult = [classifier preclassifyWithSongName:songName artist:artist];
    
    if (!styleResult || styleResult.primaryConfidence < 0.3) {
        styleResult = [[MusicStyleResult alloc] init];
        styleResult.primaryStyle = MusicStylePop;
        styleResult.primaryConfidence = 0.5;
    }
    
    AudioFeatures *features = [AudioFeatures emptyFeatures];
    UserContext *context = [UserContext currentContext];
    
    return [self makeLocalRulesDecision:styleResult features:features context:context];
}

- (EffectDecision *)makeLocalRulesDecision:(MusicStyleResult *)styleResult
                                  features:(AudioFeatures *)features
                                   context:(UserContext *)context {
    
    MusicStyle style = styleResult.primaryStyle;
    NSArray<NSNumber *> *recommendedEffects = self.styleEffectMapping[@(style)];
    
    if (!recommendedEffects || recommendedEffects.count == 0) {
        recommendedEffects = @[@(VisualEffectTypeClassicSpectrum)];
    }
    
    VisualEffectType selectedEffect = [recommendedEffects[0] unsignedIntegerValue];
    float confidence = styleResult.primaryConfidence * 0.8;
    
    // 应用自学习权重调整
    if (self.configuration.enableSelfLearning) {
        NSDictionary *learnedPrefs = [self learnedPreferencesForStyle:style];
        if (learnedPrefs.count > 0) {
            NSNumber *topEffect = [self topEffectFromPreferences:learnedPrefs];
            if (topEffect) {
                // 混合自学习结果
                float learnedConfidence = [learnedPrefs[topEffect] floatValue];
                if (learnedConfidence > confidence * (1 - self.configuration.selfLearningWeight)) {
                    selectedEffect = [topEffect unsignedIntegerValue];
                    confidence = confidence * (1 - self.configuration.selfLearningWeight) + learnedConfidence * self.configuration.selfLearningWeight;
                }
            }
        }
    }
    
    // 场景调整
    if (context.usageScene == UsageSceneLateNight || context.usageScene == UsageSceneNight) {
        for (NSNumber *effectNum in recommendedEffects) {
            VisualEffectType effect = [effectNum unsignedIntegerValue];
            if (effect == VisualEffectTypeAuroraRipples ||
                effect == VisualEffectTypeGalaxy ||
                effect == VisualEffectTypeCherryBlossomSnow ||
                effect == VisualEffectTypeTyndallBeam ||
                effect == VisualEffectTypeCircularWave) {
                selectedEffect = effect;
                break;
            }
        }
    }
    
    // 能量调整
    if (features.energy > 0.7 && recommendedEffects.count > 1) {
        NSInteger index = MIN(recommendedEffects.count - 1, 2);
        selectedEffect = [recommendedEffects[index] unsignedIntegerValue];
    }
    
    EffectDecision *decision = [EffectDecision decisionWithEffect:selectedEffect
                                                       confidence:confidence
                                                           source:DecisionSourceLocalRules];
    
    decision.reasoning = [NSString stringWithFormat:@"本地规则: %@风格 + %@场景",
                          [MusicStyleClassifier nameForStyle:style],
                          [UserContext nameForScene:context.usageScene]];
    
    if (recommendedEffects.count > 1) {
        decision.fallbackEffect = [recommendedEffects[1] unsignedIntegerValue];
    }
    
    VisualEffectType chorusEffect = (decision.fallbackEffect != 0) ? decision.fallbackEffect : selectedEffect;
    decision.segmentEffects = @{
        @(MusicSegmentIntro): @(selectedEffect),
        @(MusicSegmentVerse): @(selectedEffect),
        @(MusicSegmentChorus): @(chorusEffect),
        @(MusicSegmentBridge): @(selectedEffect),
        @(MusicSegmentOutro): @(VisualEffectTypeAuroraRipples),
    };
    
    [self incrementStatistic:@"localRulesUsed"];
    return decision;
}

#pragma mark - Segment and Feature Adjustments

- (EffectDecision *)adjustEffectForSegmentChange:(MusicSegment)newSegment
                                   currentEffect:(VisualEffectType)currentEffect {
    self.currentSegment = newSegment;
    
    NSDictionary *segmentBias = self.segmentEffectBias[@(newSegment)];
    NSNumber *suggestedEffect = segmentBias[@(currentEffect)];
    
    if (suggestedEffect) {
        EffectDecision *decision = [EffectDecision decisionWithEffect:[suggestedEffect unsignedIntegerValue]
                                                           confidence:0.6
                                                               source:DecisionSourceLocalRules];
        decision.reasoning = [NSString stringWithFormat:@"段落变化到%@，调整特效",
                              [self segmentName:newSegment]];
        decision.fallbackEffect = currentEffect;
        
        NSLog(@"🔄 段落变化: %@ -> 建议切换特效 %lu",
              [self segmentName:newSegment], (unsigned long)decision.effectType);
        
        return decision;
    }
    
    return [EffectDecision decisionWithEffect:currentEffect confidence:0.5 source:DecisionSourceLocalRules];
}

- (nullable EffectDecision *)evaluateEffectChangeWithFeatures:(AudioFeatures *)features {
    if (!self.autoModeEnabled || !self.currentDecision) {
        return nil;
    }
    
    if (features.energy > 0.8 && self.currentDecision.effectType == VisualEffectTypeAuroraRipples) {
        NSArray *highEnergyEffects = @[@(VisualEffectTypeNeonGlow), @(VisualEffectTypeLightning), @(VisualEffectTypeCyberPunk)];
        NSNumber *randomEffect = highEnergyEffects[arc4random_uniform((uint32_t)highEnergyEffects.count)];
        
        EffectDecision *decision = [EffectDecision decisionWithEffect:[randomEffect unsignedIntegerValue]
                                                           confidence:0.55
                                                               source:DecisionSourceLocalRules];
        decision.reasoning = @"能量剧增，切换到高能量特效";
        return decision;
    }
    
    if (features.energy < 0.2 && self.currentDecision.effectType == VisualEffectTypeLightning) {
        EffectDecision *decision = [EffectDecision decisionWithEffect:VisualEffectTypeAuroraRipples
                                                           confidence:0.55
                                                               source:DecisionSourceLocalRules];
        decision.reasoning = @"能量降低，切换到柔和特效";
        return decision;
    }
    
    return nil;
}

#pragma mark - Self Learning

- (void)recordDecision:(EffectDecision *)decision
           forSongName:(NSString *)songName
                artist:(nullable NSString *)artist
                 style:(MusicStyle)style {
    
    if (!self.configuration.enableSelfLearning) return;
    
    DecisionHistoryRecord *record = [[DecisionHistoryRecord alloc] init];
    record.songName = songName;
    record.artist = artist;
    record.style = style;
    record.selectedEffect = decision.effectType;
    record.source = decision.source;
    record.initialConfidence = decision.confidence;
    record.userSatisfaction = 0.5;  // 初始中立
    record.timestamp = [NSDate date];
    record.listeningDuration = 0;
    record.wasSkipped = NO;
    record.wasManuallyChanged = NO;
    
    [self.historyRecords addObject:record];
    
    // 限制历史记录数量
    while (self.historyRecords.count > self.configuration.historyRecordLimit) {
        [self.historyRecords removeObjectAtIndex:0];
    }
    
    [self saveHistoryToDisk];
}

- (void)userDidSkipSong:(NSString *)songName artist:(nullable NSString *)artist {
    DecisionHistoryRecord *record = [self findRecentRecord:songName artist:artist];
    if (record) {
        record.wasSkipped = YES;
        record.userSatisfaction = 0.2;  // 跳过表示不满意
        [self updateLearnedWeightsFromRecord:record negative:YES];
        [self saveHistoryToDisk];
        NSLog(@"📉 学习: 用户跳过歌曲，降低特效 %lu 权重", (unsigned long)record.selectedEffect);
    }
}

- (void)userDidManuallyChangeEffect:(VisualEffectType)newEffect
                        forSongName:(NSString *)songName
                             artist:(nullable NSString *)artist {
    
    // 确定旧特效：优先从历史记录获取，否则从当前决策获取
    VisualEffectType oldEffect = 0;  // 默认值，仅用于指标记录
    DecisionHistoryRecord *record = [self findRecentRecord:songName artist:artist];
    
    if (record) {
        oldEffect = record.selectedEffect;
        
        // 更新学习记录
        record.wasManuallyChanged = YES;
        record.userSatisfaction = 0.3;  // 手动更改表示不太满意
        [self updateLearnedWeightsFromRecord:record negative:YES];
        
        // 为新特效创建正向学习
        DecisionHistoryRecord *newRecord = [[DecisionHistoryRecord alloc] init];
        newRecord.songName = songName;
        newRecord.artist = artist;
        newRecord.style = record.style;
        newRecord.selectedEffect = newEffect;
        newRecord.source = DecisionSourceUserPreference;
        newRecord.initialConfidence = 1.0;
        newRecord.userSatisfaction = 0.9;  // 用户选择的表示满意
        newRecord.timestamp = [NSDate date];
        
        [self.historyRecords addObject:newRecord];
        [self updateLearnedWeightsFromRecord:newRecord negative:NO];
        [self saveHistoryToDisk];
        
        NSLog(@"📊 学习: 用户手动切换到特效 %lu (来自历史记录)", (unsigned long)newEffect);
    } else if (self.currentDecision) {
        // 没有历史记录但有当前决策
        oldEffect = self.currentDecision.effectType;
        NSLog(@"📊 用户手动切换到特效 %lu (来自当前决策)", (unsigned long)newEffect);
    } else {
        NSLog(@"📊 用户手动切换到特效 %lu (无法确定旧特效)", (unsigned long)newEffect);
    }
    
    // 📊 无论是否找到记录，都要记录到指标采集器（独立于学习系统）
    [self.metricsCollector recordUserOverrideFromEffect:oldEffect toEffect:newEffect];
    
    // 🔍 无论是否找到记录，都要更新反思引擎
    [self.reflectionEngine recordDecisionOutcome:songName userOverrode:YES newEffect:newEffect];
}

- (void)userDidFinishListening:(NSString *)songName
                        artist:(nullable NSString *)artist
                      duration:(NSTimeInterval)duration {
    
    DecisionHistoryRecord *record = [self findRecentRecord:songName artist:artist];
    if (record) {
        record.listeningDuration = duration;
        
        // 听完超过2分钟表示满意
        if (duration > 120) {
            record.userSatisfaction = 0.9;
            [self updateLearnedWeightsFromRecord:record negative:NO];
            NSLog(@"📈 学习: 用户完整听完，增加特效 %lu 权重", (unsigned long)record.selectedEffect);
        } else if (duration > 60) {
            record.userSatisfaction = 0.6;
        }
        
        [self saveHistoryToDisk];
    }
}

- (DecisionHistoryRecord *)findRecentRecord:(NSString *)songName artist:(NSString *)artist {
    for (NSInteger i = self.historyRecords.count - 1; i >= 0; i--) {
        DecisionHistoryRecord *record = self.historyRecords[i];
        if ([record.songName isEqualToString:songName]) {
            if (!artist || [record.artist isEqualToString:artist]) {
                return record;
            }
        }
    }
    return nil;
}

- (void)updateLearnedWeightsFromRecord:(DecisionHistoryRecord *)record negative:(BOOL)negative {
    NSString *styleKey = [NSString stringWithFormat:@"style_%ld", (long)record.style];
    
    if (!self.learnedWeights[styleKey]) {
        self.learnedWeights[styleKey] = [NSMutableDictionary dictionary];
    }
    
    NSString *effectKey = [NSString stringWithFormat:@"%lu", (unsigned long)record.selectedEffect];
    float currentWeight = [self.learnedWeights[styleKey][effectKey] floatValue];
    
    float adjustment = negative ? -0.1 : 0.15;
    float newWeight = MAX(0, MIN(1, currentWeight + adjustment * record.userSatisfaction));
    
    self.learnedWeights[styleKey][effectKey] = @(newWeight);
    [self saveLearnedWeightsToDisk];
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kEffectDecisionAgentDidLearnNotification
                                                        object:self
                                                      userInfo:@{@"style": @(record.style), @"effect": @(record.selectedEffect)}];
}

- (EffectDecision *)decisionFromSelfLearning:(NSString *)songName artist:(NSString *)artist {
    MusicStyleClassifier *classifier = [MusicStyleClassifier sharedClassifier];
    MusicStyleResult *styleResult = [classifier preclassifyWithSongName:songName artist:artist];
    
    if (!styleResult) return nil;
    
    return [self decisionFromSelfLearningForStyle:styleResult.primaryStyle];
}

- (EffectDecision *)decisionFromSelfLearningForStyle:(MusicStyle)style {
    NSDictionary *prefs = [self learnedPreferencesForStyle:style];
    NSNumber *topEffect = [self topEffectFromPreferences:prefs];
    
    if (topEffect && [prefs[topEffect] floatValue] >= 0.6) {
        EffectDecision *decision = [EffectDecision decisionWithEffect:[topEffect unsignedIntegerValue]
                                                           confidence:[prefs[topEffect] floatValue]
                                                               source:DecisionSourceSelfLearning];
        decision.reasoning = @"基于历史表现学习";
        return decision;
    }
    
    return nil;
}

- (NSDictionary<NSNumber *, NSNumber *> *)learnedPreferencesForStyle:(MusicStyle)style {
    NSString *styleKey = [NSString stringWithFormat:@"style_%ld", (long)style];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    
    NSDictionary *weights = self.learnedWeights[styleKey];
    for (NSString *effectKey in weights) {
        NSNumber *effectNum = @([effectKey integerValue]);
        result[effectNum] = weights[effectKey];
    }
    
    return result;
}

- (NSNumber *)topEffectFromPreferences:(NSDictionary *)prefs {
    NSNumber *topEffect = nil;
    float topWeight = 0;
    
    for (NSNumber *effect in prefs) {
        float weight = [prefs[effect] floatValue];
        if (weight > topWeight) {
            topWeight = weight;
            topEffect = effect;
        }
    }
    
    return topEffect;
}

- (void)resetLearningData {
    [self.historyRecords removeAllObjects];
    [self.learnedWeights removeAllObjects];
    [self saveHistoryToDisk];
    [self saveLearnedWeightsToDisk];
    NSLog(@"🔄 学习数据已重置");
}

#pragma mark - Effect Mapping

- (VisualEffectType)effectForEmotion:(MusicEmotion)emotion
                              energy:(float)energy
                               style:(MusicStyle)style {
    switch (emotion) {
        case MusicEmotionCalm:
            return VisualEffectTypeAuroraRipples;
            
        case MusicEmotionSad:
            return VisualEffectTypeGalaxy;
            
        case MusicEmotionHappy:
            if (energy > 0.6) {
                return VisualEffectTypeParticleFlow;
            }
            return VisualEffectTypeCherryBlossomSnow;
            
        case MusicEmotionEnergetic:
            if (style == MusicStyleElectronic || style == MusicStyleDance) {
                return VisualEffectTypeCyberPunk;
            }
            return VisualEffectTypeNeonGlow;
            
        case MusicEmotionIntense:
            return VisualEffectTypeLightning;
            
        default:
            return VisualEffectTypeTyndallBeam;
    }
}

- (VisualEffectType)intensifiedEffect:(VisualEffectType)effect {
    switch (effect) {
        case VisualEffectTypeAuroraRipples:
            return VisualEffectTypeGalaxy;
        case VisualEffectTypeCircularWave:
            return VisualEffectTypeParticleFlow;
        case VisualEffectTypeNeonGlow:
            return VisualEffectTypeCyberPunk;
        case VisualEffectTypeTyndallBeam:
            return VisualEffectTypeQuantumField;
        case VisualEffectTypeCherryBlossomSnow:
            return VisualEffectTypeStarVortex;
        default:
            return effect;
    }
}

#pragma mark - Finalization

- (void)finalizeDecision:(EffectDecision *)decision completion:(EffectDecisionCompletion)completion {
    self.currentDecision = decision;
    self.isDeciding = NO;
    
    // 记录用于学习
    if (self.currentSongName) {
        [self recordDecision:decision forSongName:self.currentSongName artist:self.currentArtist style:self.currentStyle];
    }
    
    dispatch_async(dispatch_get_main_queue(), ^{
        [[NSNotificationCenter defaultCenter] postNotificationName:kEffectDecisionAgentDidCompleteNotification
                                                            object:self
                                                          userInfo:@{@"decision": decision}];
        
        if (completion) {
            completion(decision);
        }
    });
}

#pragma mark - Cache Management

- (void)loadAllCaches {
    [self loadLLMCacheFromDisk];
    [self loadHistoryFromDisk];
    [self loadLearnedWeightsFromDisk];
}

- (void)loadLLMCacheFromDisk {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kLLMDecisionCacheFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[NSMutableDictionary class], [EffectDecision class], [NSString class], nil];
            NSMutableDictionary *cache = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (cache) {
                self.llmDecisionCache = cache;
                NSLog(@"📂 加载 LLM 缓存: %lu 条记录", (unsigned long)cache.count);
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ 加载 LLM 缓存失败: %@", exception.reason);
        }
    }
}

- (void)saveLLMCacheToDisk {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kLLMDecisionCacheFile];
    
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.llmDecisionCache requiringSecureCoding:YES error:nil];
        [data writeToFile:path atomically:YES];
        NSLog(@"💾 保存 LLM 缓存: %lu 条记录", (unsigned long)self.llmDecisionCache.count);
    } @catch (NSException *exception) {
        NSLog(@"⚠️ 保存 LLM 缓存失败: %@", exception.reason);
    }
}

- (void)loadHistoryFromDisk {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kHistoryRecordsFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[NSMutableArray class], [DecisionHistoryRecord class], [NSString class], [NSDate class], nil];
            NSMutableArray *history = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (history) {
                self.historyRecords = history;
                NSLog(@"📂 加载历史记录: %lu 条", (unsigned long)history.count);
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ 加载历史记录失败: %@", exception.reason);
        }
    }
}

- (void)saveHistoryToDisk {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kHistoryRecordsFile];
    
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.historyRecords requiringSecureCoding:YES error:nil];
        [data writeToFile:path atomically:YES];
    } @catch (NSException *exception) {
        NSLog(@"⚠️ 保存历史记录失败: %@", exception.reason);
    }
}

- (void)loadLearnedWeightsFromDisk {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kLearnedWeightsFile];
    
    if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
        @try {
            NSData *data = [NSData dataWithContentsOfFile:path];
            NSSet *classes = [NSSet setWithObjects:[NSMutableDictionary class], [NSString class], [NSNumber class], nil];
            NSMutableDictionary *weights = [NSKeyedUnarchiver unarchivedObjectOfClasses:classes fromData:data error:nil];
            if (weights) {
                self.learnedWeights = weights;
                NSLog(@"📂 加载学习权重: %lu 个风格", (unsigned long)weights.count);
            }
        } @catch (NSException *exception) {
            NSLog(@"⚠️ 加载学习权重失败: %@", exception.reason);
        }
    }
}

- (void)saveLearnedWeightsToDisk {
    NSString *path = [self.cacheDirectory stringByAppendingPathComponent:kLearnedWeightsFile];
    
    @try {
        NSData *data = [NSKeyedArchiver archivedDataWithRootObject:self.learnedWeights requiringSecureCoding:YES error:nil];
        [data writeToFile:path atomically:YES];
    } @catch (NSException *exception) {
        NSLog(@"⚠️ 保存学习权重失败: %@", exception.reason);
    }
}

- (void)clearAllCache {
    [self.llmDecisionCache removeAllObjects];
    [self saveLLMCacheToDisk];
    NSLog(@"🗑️ 已清除所有缓存");
}

- (void)clearCacheForSong:(NSString *)songName artist:(nullable NSString *)artist {
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    [self.llmDecisionCache removeObjectForKey:cacheKey];
    [self saveLLMCacheToDisk];
}

- (NSDictionary *)cacheStatus {
    return @{
        @"llmCacheCount": @(self.llmDecisionCache.count),
        @"historyCount": @(self.historyRecords.count),
        @"learnedStyleCount": @(self.learnedWeights.count),
        @"cacheDirectory": self.cacheDirectory ?: @""
    };
}

- (void)forceSaveCache {
    [self saveLLMCacheToDisk];
    [self saveHistoryToDisk];
    [self saveLearnedWeightsToDisk];
    NSLog(@"💾 强制保存所有缓存完成");
}

#pragma mark - Statistics

- (void)incrementStatistic:(NSString *)key {
    NSInteger current = [self.statistics[key] integerValue];
    self.statistics[key] = @(current + 1);
}

#pragma mark - Utilities

- (NSString *)cacheKeyForSong:(NSString *)songName artist:(NSString *)artist {
    if (artist) {
        return [NSString stringWithFormat:@"%@_%@", songName, artist];
    }
    return songName;
}

- (NSString *)segmentName:(MusicSegment)segment {
    switch (segment) {
        case MusicSegmentIntro: return @"前奏";
        case MusicSegmentVerse: return @"主歌";
        case MusicSegmentChorus: return @"副歌";
        case MusicSegmentBridge: return @"过渡";
        case MusicSegmentOutro: return @"尾奏";
        default: return @"未知";
    }
}

#pragma mark - Class Methods

+ (NSArray<NSNumber *> *)recommendedEffectsForStyle:(MusicStyle)style {
    return [[EffectDecisionAgent sharedAgent].styleEffectMapping[@(style)] copy] ?: @[@(VisualEffectTypeClassicSpectrum)];
}

+ (NSDictionary *)defaultParametersForEffect:(VisualEffectType)effect style:(MusicStyle)style {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    
    switch (style) {
        case MusicStyleElectronic:
        case MusicStyleDance:
            params[@"animationSpeed"] = @1.2;
            params[@"brightness"] = @1.1;
            params[@"beatReactivity"] = @0.9;
            break;
            
        case MusicStyleRock:
        case MusicStyleMetal:
            params[@"animationSpeed"] = @1.0;
            params[@"brightness"] = @1.2;
            params[@"beatReactivity"] = @0.8;
            break;
            
        case MusicStyleClassical:
        case MusicStyleAmbient:
            params[@"animationSpeed"] = @0.6;
            params[@"brightness"] = @0.8;
            params[@"beatReactivity"] = @0.3;
            break;
            
        case MusicStyleJazz:
            params[@"animationSpeed"] = @0.8;
            params[@"brightness"] = @0.9;
            params[@"beatReactivity"] = @0.5;
            break;
            
        default:
            params[@"animationSpeed"] = @1.0;
            params[@"brightness"] = @1.0;
            params[@"beatReactivity"] = @0.6;
            break;
    }
    
    return params;
}

@end
