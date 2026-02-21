//
//  EffectDecisionAgent.m
//  AudioSampleBuffer
//
//  完全自主的AI决策引擎实现
//

#import "EffectDecisionAgent.h"
#import "MusicAIAnalyzer.h"
#import "AIColorConfiguration.h"

#pragma mark - Constants

static NSString *const kDeepSeekAPIKey = @"sk-004d32e67f2440c48b3684774d489f12";
static NSString *const kDeepSeekAPIEndpoint = @"https://api.deepseek.com/chat/completions";

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
    config.maxLLMRetries = 3;
    config.llmTimeout = 10.0;
    config.enableSelfLearning = YES;
    config.enableDirectLLMCall = YES;
    config.historyRecordLimit = 1000;
    return config;
}

@end

#pragma mark - EffectDecisionAgent

@interface EffectDecisionAgent ()

@property (nonatomic, strong) EffectDecision *currentDecision;
@property (nonatomic, assign) BOOL isDeciding;
@property (nonatomic, assign) BOOL isCallingLLM;

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
    }
    return self;
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
    config.timeoutIntervalForRequest = self.configuration.llmTimeout;
    config.timeoutIntervalForResource = self.configuration.llmTimeout * 2;
    self.urlSession = [NSURLSession sessionWithConfiguration:config];
}

- (void)setupStyleEffectMapping {
    self.styleEffectMapping = @{
        @(MusicStyleElectronic): @[
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
            @(VisualEffectTypeTyndallBeam),
            @(VisualEffectTypeGalaxy),
            @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeCherryBlossomSnow),
            @(VisualEffectTypeCircularWave)
        ],
        @(MusicStyleDance): @[
            @(VisualEffectTypeNeonGlow),
            @(VisualEffectTypeCyberPunk),
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
        },
        @(MusicSegmentOutro): @{
            @(VisualEffectTypeLightning): @(VisualEffectTypeAuroraRipples),
            @(VisualEffectTypeCyberPunk): @(VisualEffectTypeTyndallBeam),
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

#pragma mark - Autonomous Decision

- (void)autonomousDecisionForSong:(NSString *)songName
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
    
    NSLog(@"🤖 Agent 开始自主决策: %@ - %@", songName, artist ?: @"Unknown");
    
    [[NSNotificationCenter defaultCenter] postNotificationName:kEffectDecisionAgentDidStartAnalysisNotification
                                                        object:self
                                                      userInfo:@{@"songName": songName}];
    
    // Step 1: 检查缓存
    NSString *cacheKey = [self cacheKeyForSong:songName artist:artist];
    EffectDecision *cachedDecision = self.llmDecisionCache[cacheKey];
    
    if (cachedDecision) {
        [self incrementStatistic:@"cacheHits"];
        cachedDecision.source = DecisionSourceLLMCache;
        NSLog(@"📦 使用缓存决策: %@", [[VisualEffectRegistry sharedRegistry] effectInfoForType:cachedDecision.effectType].name);
        [self finalizeDecision:cachedDecision completion:completion];
        return;
    }
    
    // Step 2: 检查自学习结果
    if (self.configuration.enableSelfLearning) {
        EffectDecision *learnedDecision = [self decisionFromSelfLearning:songName artist:artist];
        if (learnedDecision && learnedDecision.confidence >= 0.75) {
            [self incrementStatistic:@"selfLearningUsed"];
            NSLog(@"🧠 使用自学习决策: %@", [[VisualEffectRegistry sharedRegistry] effectInfoForType:learnedDecision.effectType].name);
            [self finalizeDecision:learnedDecision completion:completion];
            return;
        }
    }
    
    // Step 3: 直接调用 DeepSeek 进行分析
    if (self.configuration.enableDirectLLMCall) {
        [self callDeepSeekWithRetry:songName artist:artist retryCount:0 completion:^(EffectDecision *decision) {
            if (decision) {
                // 缓存成功的决策
                self.llmDecisionCache[cacheKey] = decision;
                [self saveLLMCacheToDisk];
                [self finalizeDecision:decision completion:completion];
            } else {
                // 降级到本地规则
                EffectDecision *fallback = [self makeLocalRulesDecisionForSong:songName artist:artist];
                fallback.source = DecisionSourceFallback;
                fallback.reasoning = @"LLM 调用失败，使用本地规则";
                [self finalizeDecision:fallback completion:completion];
            }
        }];
    } else {
        // 直接使用本地规则
        EffectDecision *localDecision = [self makeLocalRulesDecisionForSong:songName artist:artist];
        [self finalizeDecision:localDecision completion:completion];
    }
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

#pragma mark - Direct DeepSeek API Call

- (void)callDeepSeekDirectly:(NSString *)songName
                      artist:(nullable NSString *)artist
           additionalContext:(nullable NSDictionary *)additionalContext
                  completion:(LLMAnalysisCompletion)completion {
    
    NSLog(@"🔗 直接调用 DeepSeek API: %@ - %@", songName, artist ?: @"Unknown");
    
    self.isCallingLLM = YES;
    [self incrementStatistic:@"llmCalls"];
    
    NSString *prompt = [self buildPromptForSong:songName artist:artist additionalContext:additionalContext];
    
    NSDictionary *requestBody = @{
        @"model": @"deepseek-chat",
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
    
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:kDeepSeekAPIEndpoint]];
    request.HTTPMethod = @"POST";
    request.HTTPBody = bodyData;
    [request setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    [request setValue:[NSString stringWithFormat:@"Bearer %@", kDeepSeekAPIKey] forHTTPHeaderField:@"Authorization"];
    
    NSURLSessionDataTask *task = [self.urlSession dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        self.isCallingLLM = NO;
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (error) {
                NSLog(@"❌ DeepSeek API 错误: %@", error.localizedDescription);
                [self incrementStatistic:@"llmFailures"];
                completion(nil, error);
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
            
            // 提取内容
            NSArray *choices = responseDict[@"choices"];
            if (choices.count > 0) {
                NSDictionary *message = choices[0][@"message"];
                NSString *content = message[@"content"];
                
                // 尝试解析 JSON 内容
                NSDictionary *parsedContent = [self parseJSONFromContent:content];
                if (parsedContent) {
                    NSLog(@"✅ DeepSeek 分析成功");
                    [self incrementStatistic:@"llmSuccesses"];
                    completion(parsedContent, nil);
                } else {
                    NSLog(@"⚠️ 无法解析 DeepSeek 响应内容");
                    completion(@{@"raw_content": content ?: @""}, nil);
                }
            } else {
                completion(nil, [NSError errorWithDomain:@"DeepSeek" code:-1 userInfo:@{NSLocalizedDescriptionKey: @"Empty response"}]);
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
        completion(nil);
        return;
    }
    
    NSLog(@"🔄 LLM 调用 (尝试 %ld/%ld)", (long)(retryCount + 1), (long)self.configuration.maxLLMRetries);
    
    [self callDeepSeekDirectly:songName artist:artist additionalContext:nil completion:^(NSDictionary *response, NSError *error) {
        if (error) {
            // 延迟后重试
            NSTimeInterval delay = pow(2, retryCount) * 0.5;  // 指数退避: 0.5s, 1s, 2s...
            NSLog(@"⏳ %.1f秒后重试...", delay);
            
            dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                [self callDeepSeekWithRetry:songName artist:artist retryCount:retryCount + 1 completion:completion];
            });
            return;
        }
        
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
    [prompt appendString:@"  \"recommended_effect\": \"推荐特效ID(0-20)\",\n"];
    [prompt appendString:@"  \"effect_name\": \"特效名称\",\n"];
    [prompt appendString:@"  \"animation_speed\": 0.5-2.0,\n"];
    [prompt appendString:@"  \"brightness\": 0.5-1.5,\n"];
    [prompt appendString:@"  \"color_scheme\": \"warm/cool/neutral/vibrant\",\n"];
    [prompt appendString:@"  \"reasoning\": \"选择原因\"\n"];
    [prompt appendString:@"}\n\n"];
    [prompt appendString:@"可用特效：0-经典频谱,1-霓虹,2-流体,3-粒子,4-极光,5-银河,6-闪电,7-3D波形,"];
    [prompt appendString:@"8-圆环波,9-樱花,10-星漩,11-量子场,12-赛博朋克,13-烟花,14-全息,15-丁达尔,"];
    [prompt appendString:@"16-弹簧线,17-液态金属,18-流星雨,19-频谱波,20-迷幻渐变"];
    
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

- (EffectDecision *)createDecisionFromLLMResponse:(NSDictionary *)response
                                         songName:(NSString *)songName
                                           artist:(NSString *)artist {
    
    EffectDecision *decision = [[EffectDecision alloc] init];
    decision.source = DecisionSourceLLMRealtime;
    decision.llmRawResponse = response;
    
    // 解析推荐特效
    NSNumber *effectNum = response[@"recommended_effect"];
    if (effectNum) {
        decision.effectType = [effectNum unsignedIntegerValue];
    } else {
        decision.effectType = VisualEffectTypeTyndallBeam;  // 默认
    }
    
    // 解析参数
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (response[@"animation_speed"]) {
        params[@"animationSpeed"] = response[@"animation_speed"];
    }
    if (response[@"brightness"]) {
        params[@"brightness"] = response[@"brightness"];
    }
    decision.parameters = params;
    
    // 置信度
    decision.confidence = 0.85;
    
    // 原因
    decision.reasoning = response[@"reasoning"] ?: [NSString stringWithFormat:@"DeepSeek 推荐特效: %@", response[@"effect_name"] ?: @"Unknown"];
    
    NSString *effectName = [[VisualEffectRegistry sharedRegistry] effectInfoForType:decision.effectType].name ?: @"Unknown";
    NSLog(@"🎯 LLM 推荐特效: %@ (ID:%lu)", effectName, (unsigned long)decision.effectType);
    
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
    [analyzer analyzeSong:songName artist:artist completion:^(AIColorConfiguration *config, NSError *error) {
        if (error || !config) {
            NSLog(@"❌ LLM调用失败: %@", error.localizedDescription);
            [self incrementStatistic:@"llmFailures"];
            completion(nil);
            return;
        }
        
        [self incrementStatistic:@"llmSuccesses"];
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
    
    DecisionHistoryRecord *record = [self findRecentRecord:songName artist:artist];
    if (record) {
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
        
        NSLog(@"📊 学习: 用户手动切换到特效 %lu", (unsigned long)newEffect);
    }
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
