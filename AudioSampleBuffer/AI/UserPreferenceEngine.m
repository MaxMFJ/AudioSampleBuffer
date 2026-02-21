//
//  UserPreferenceEngine.m
//  AudioSampleBuffer
//

#import "UserPreferenceEngine.h"

static NSString *const kPreferenceRecordsKey = @"MusicAI_PreferenceRecords";
static NSString *const kStyleEffectScoresKey = @"MusicAI_StyleEffectScores";
static NSString *const kSceneEffectScoresKey = @"MusicAI_SceneEffectScores";
static NSString *const kEffectGlobalScoresKey = @"MusicAI_EffectGlobalScores";
static const NSInteger kMaxRecords = 1000;

#pragma mark - PreferenceRecord

@implementation PreferenceRecord

+ (BOOL)supportsSecureCoding {
    return YES;
}

+ (instancetype)recordWithStyle:(MusicStyle)style
                         effect:(VisualEffectType)effect
                        context:(UserContext *)context
                          score:(float)score {
    PreferenceRecord *record = [[PreferenceRecord alloc] init];
    record.style = style;
    record.effect = effect;
    record.context = context;
    record.engagementScore = score;
    record.timestamp = [NSDate date];
    return record;
}

- (void)encodeWithCoder:(NSCoder *)coder {
    [coder encodeInteger:self.style forKey:@"style"];
    [coder encodeInteger:self.effect forKey:@"effect"];
    [coder encodeObject:self.context forKey:@"context"];
    [coder encodeFloat:self.engagementScore forKey:@"engagementScore"];
    [coder encodeObject:self.timestamp forKey:@"timestamp"];
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super init];
    if (self) {
        _style = [coder decodeIntegerForKey:@"style"];
        _effect = [coder decodeIntegerForKey:@"effect"];
        _context = [coder decodeObjectOfClass:[UserContext class] forKey:@"context"];
        _engagementScore = [coder decodeFloatForKey:@"engagementScore"];
        _timestamp = [coder decodeObjectOfClass:[NSDate class] forKey:@"timestamp"];
    }
    return self;
}

@end

#pragma mark - PreferenceQueryResult

@implementation PreferenceQueryResult

@end

#pragma mark - UserPreferenceEngine

@interface UserPreferenceEngine ()

@property (nonatomic, strong) UserContext *currentContext;
@property (nonatomic, strong) NSDate *sessionStartTime;

// 当前状态
@property (nonatomic, assign) VisualEffectType currentEffect;
@property (nonatomic, assign) MusicStyle currentStyle;
@property (nonatomic, strong) NSDate *effectStartTime;
@property (nonatomic, assign) NSTimeInterval currentSongDuration;

// 累积分数（风格 -> 特效 -> 分数）
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSNumber *> *> *styleEffectScores;

// 场景偏好分数（场景 -> 特效 -> 分数）
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSNumber *> *> *sceneEffectScores;

// 全局特效分数
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSNumber *> *effectGlobalScores;

// 采样计数
@property (nonatomic, strong) NSMutableDictionary<NSNumber *, NSMutableDictionary<NSNumber *, NSNumber *> *> *styleEffectCounts;

@end

@implementation UserPreferenceEngine

+ (instancetype)sharedEngine {
    static UserPreferenceEngine *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[UserPreferenceEngine alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _currentContext = [UserContext currentContext];
        _sessionStartTime = [NSDate date];
        _currentEffect = VisualEffectTypeClassicSpectrum;
        _currentStyle = MusicStyleUnknown;
        _effectStartTime = [NSDate date];
        _preferenceWeight = 0.5;  // 默认权重
        
        [self loadPreferences];
        [self loadPreferenceWeight];
    }
    return self;
}

#pragma mark - Persistence

- (void)loadPreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    // 加载风格-特效分数
    NSDictionary *styleEffectDict = [defaults objectForKey:kStyleEffectScoresKey];
    if (styleEffectDict) {
        self.styleEffectScores = [self mutableDictionaryFromPersisted:styleEffectDict];
    } else {
        self.styleEffectScores = [NSMutableDictionary dictionary];
    }
    
    // 加载场景-特效分数
    NSDictionary *sceneEffectDict = [defaults objectForKey:kSceneEffectScoresKey];
    if (sceneEffectDict) {
        self.sceneEffectScores = [self mutableDictionaryFromPersisted:sceneEffectDict];
    } else {
        self.sceneEffectScores = [NSMutableDictionary dictionary];
    }
    
    // 加载全局特效分数
    NSDictionary *globalDict = [defaults objectForKey:kEffectGlobalScoresKey];
    if (globalDict) {
        self.effectGlobalScores = [self mutableFlatDictionaryFromPersisted:globalDict];
    } else {
        self.effectGlobalScores = [NSMutableDictionary dictionary];
    }
    
    self.styleEffectCounts = [NSMutableDictionary dictionary];
    
    NSLog(@"📊 UserPreferenceEngine: 加载了 %lu 个风格的偏好数据", (unsigned long)self.styleEffectScores.count);
}

- (void)savePreferences {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    
    [defaults setObject:[self persistableDictionary:self.styleEffectScores] forKey:kStyleEffectScoresKey];
    [defaults setObject:[self persistableDictionary:self.sceneEffectScores] forKey:kSceneEffectScoresKey];
    [defaults setObject:[self persistableFlatDictionary:self.effectGlobalScores] forKey:kEffectGlobalScoresKey];
    
    [defaults synchronize];
}

- (NSDictionary *)persistableDictionary:(NSDictionary *)dict {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id key in dict) {
        // 将键转换为字符串
        NSString *stringKey = [key isKindOfClass:[NSNumber class]] ? [key stringValue] : key;
        id value = dict[key];
        
        // 递归处理嵌套字典
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *innerResult = [NSMutableDictionary dictionary];
            for (id innerKey in value) {
                NSString *innerStringKey = [innerKey isKindOfClass:[NSNumber class]] ? [innerKey stringValue] : innerKey;
                innerResult[innerStringKey] = value[innerKey];
            }
            result[stringKey] = innerResult;
        } else {
            result[stringKey] = value;
        }
    }
    return result;
}

- (NSDictionary *)persistableFlatDictionary:(NSDictionary *)dict {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (id key in dict) {
        NSString *stringKey = [key isKindOfClass:[NSNumber class]] ? [key stringValue] : key;
        result[stringKey] = dict[key];
    }
    return result;
}

- (NSMutableDictionary *)mutableFlatDictionaryFromPersisted:(NSDictionary *)dict {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in dict) {
        NSNumber *numKey = @([key integerValue]);
        result[numKey] = dict[key];
    }
    return result;
}

- (NSMutableDictionary *)mutableDictionaryFromPersisted:(NSDictionary *)dict {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in dict) {
        NSNumber *numKey = @([key integerValue]);
        id value = dict[key];
        if ([value isKindOfClass:[NSDictionary class]]) {
            NSMutableDictionary *innerDict = [NSMutableDictionary dictionary];
            for (NSString *innerKey in value) {
                innerDict[@([innerKey integerValue])] = value[innerKey];
            }
            result[numKey] = innerDict;
        } else {
            result[numKey] = value;
        }
    }
    return result;
}

#pragma mark - Record User Behavior

- (void)recordEffectShown:(VisualEffectType)effect
                 forStyle:(MusicStyle)style
                  context:(UserContext *)context {
    self.currentEffect = effect;
    self.currentStyle = style;
    self.effectStartTime = [NSDate date];
    self.currentContext = context;
    
    // 增加采样计数
    [self incrementCountForStyle:style effect:effect];
    
    NSLog(@"📝 记录特效展示: %@ for style %@",
          @(effect), [MusicStyleClassifier nameForStyle:style]);
}

- (void)recordUserSkippedSong {
    // 跳过歌曲 = 当前特效负反馈
    [self addScore:-0.3 forStyle:self.currentStyle effect:self.currentEffect];
    [self addGlobalScore:-0.2 forEffect:self.currentEffect];
    
    NSLog(@"⏭️ 用户跳过歌曲，特效 %@ 减分", @(self.currentEffect));
    [self savePreferences];
}

- (void)recordUserManuallyChangedEffect:(VisualEffectType)newEffect
                             fromEffect:(VisualEffectType)oldEffect {
    // 手动切换 = 原特效负反馈，新特效正反馈
    [self addScore:-0.5 forStyle:self.currentStyle effect:oldEffect];
    [self addScore:0.8 forStyle:self.currentStyle effect:newEffect];
    
    [self addGlobalScore:-0.3 forEffect:oldEffect];
    [self addGlobalScore:0.5 forEffect:newEffect];
    
    // 场景偏好
    [self addScore:0.6 forScene:self.currentContext.usageScene effect:newEffect];
    
    // 更新上下文
    self.currentContext.lastManualEffectChoice = @(newEffect).stringValue;
    
    self.currentEffect = newEffect;
    self.effectStartTime = [NSDate date];
    
    NSLog(@"🔄 用户手动切换: %@ -> %@", @(oldEffect), @(newEffect));
    [self savePreferences];
}

- (void)recordUserListenedFull {
    // 完整听完 = 当前特效正反馈
    [self addScore:1.0 forStyle:self.currentStyle effect:self.currentEffect];
    [self addGlobalScore:0.5 forEffect:self.currentEffect];
    [self addScore:0.4 forScene:self.currentContext.usageScene effect:self.currentEffect];
    
    NSLog(@"✅ 用户听完整首歌，特效 %@ 加分", @(self.currentEffect));
    [self savePreferences];
}

- (void)recordUserStayedOnEffect:(VisualEffectType)effect
                        duration:(NSTimeInterval)duration {
    // 停留时间越长，加分越多（上限60秒）
    float bonus = MIN(1.0, duration / 60.0) * 0.5;
    [self addScore:bonus forStyle:self.currentStyle effect:effect];
    [self addGlobalScore:bonus * 0.5 forEffect:effect];
    
    NSLog(@"⏱️ 用户停留 %.1fs 在特效 %@", duration, @(effect));
}

#pragma mark - Score Management

- (void)addScore:(float)score forStyle:(MusicStyle)style effect:(VisualEffectType)effect {
    NSMutableDictionary *effectScores = self.styleEffectScores[@(style)];
    if (!effectScores) {
        effectScores = [NSMutableDictionary dictionary];
        self.styleEffectScores[@(style)] = effectScores;
    }
    
    float currentScore = [effectScores[@(effect)] floatValue];
    float newScore = currentScore + score;
    // 限制范围 [-10, 10]
    newScore = MAX(-10.0, MIN(10.0, newScore));
    effectScores[@(effect)] = @(newScore);
}

- (void)addScore:(float)score forScene:(UsageScene)scene effect:(VisualEffectType)effect {
    NSMutableDictionary *effectScores = self.sceneEffectScores[@(scene)];
    if (!effectScores) {
        effectScores = [NSMutableDictionary dictionary];
        self.sceneEffectScores[@(scene)] = effectScores;
    }
    
    float currentScore = [effectScores[@(effect)] floatValue];
    float newScore = currentScore + score;
    newScore = MAX(-10.0, MIN(10.0, newScore));
    effectScores[@(effect)] = @(newScore);
}

- (void)addGlobalScore:(float)score forEffect:(VisualEffectType)effect {
    float currentScore = [self.effectGlobalScores[@(effect)] floatValue];
    float newScore = currentScore + score;
    newScore = MAX(-10.0, MIN(10.0, newScore));
    self.effectGlobalScores[@(effect)] = @(newScore);
}

- (void)incrementCountForStyle:(MusicStyle)style effect:(VisualEffectType)effect {
    NSMutableDictionary *effectCounts = self.styleEffectCounts[@(style)];
    if (!effectCounts) {
        effectCounts = [NSMutableDictionary dictionary];
        self.styleEffectCounts[@(style)] = effectCounts;
    }
    
    NSInteger count = [effectCounts[@(effect)] integerValue];
    effectCounts[@(effect)] = @(count + 1);
}

#pragma mark - Query Preferences

- (PreferenceQueryResult *)preferredEffectForStyle:(MusicStyle)style
                                           context:(UserContext *)context {
    PreferenceQueryResult *result = [[PreferenceQueryResult alloc] init];
    
    NSDictionary *effectScores = self.styleEffectScores[@(style)];
    NSDictionary *sceneScores = self.sceneEffectScores[@(context.usageScene)];
    
    if (!effectScores && !sceneScores) {
        // 没有偏好数据
        result.preferredEffect = VisualEffectTypeClassicSpectrum;
        result.confidence = 0;
        result.sampleCount = 0;
        return result;
    }
    
    // 综合风格偏好和场景偏好
    NSMutableDictionary<NSNumber *, NSNumber *> *combinedScores = [NSMutableDictionary dictionary];
    
    // 风格偏好权重 0.6
    for (NSNumber *effectKey in effectScores) {
        float score = [effectScores[effectKey] floatValue] * 0.6;
        combinedScores[effectKey] = @(score);
    }
    
    // 场景偏好权重 0.4
    for (NSNumber *effectKey in sceneScores) {
        float existingScore = [combinedScores[effectKey] floatValue];
        float sceneScore = [sceneScores[effectKey] floatValue] * 0.4;
        combinedScores[effectKey] = @(existingScore + sceneScore);
    }
    
    // 找出最高分
    NSNumber *bestEffect = nil;
    float bestScore = -INFINITY;
    
    for (NSNumber *effectKey in combinedScores) {
        float score = [combinedScores[effectKey] floatValue];
        if (score > bestScore) {
            bestScore = score;
            bestEffect = effectKey;
        }
    }
    
    if (bestEffect) {
        result.preferredEffect = [bestEffect unsignedIntegerValue];
        // 将分数转换为置信度 [0, 1]
        result.confidence = MIN(1.0, MAX(0, (bestScore + 5.0) / 10.0));
        result.sampleCount = [self.styleEffectCounts[@(style)][bestEffect] integerValue];
    } else {
        result.preferredEffect = VisualEffectTypeClassicSpectrum;
        result.confidence = 0;
        result.sampleCount = 0;
    }
    
    return result;
}

- (float)preferenceScoreForEffect:(VisualEffectType)effect
                          inStyle:(MusicStyle)style {
    NSDictionary *effectScores = self.styleEffectScores[@(style)];
    return [effectScores[@(effect)] floatValue];
}

- (float)preferenceScoreForEffect:(VisualEffectType)effect
                          inScene:(UsageScene)scene {
    NSDictionary *effectScores = self.sceneEffectScores[@(scene)];
    return [effectScores[@(effect)] floatValue];
}

- (NSArray<NSNumber *> *)topPreferredEffects:(NSInteger)count {
    // 按全局分数排序
    NSArray *sortedEffects = [self.effectGlobalScores.allKeys sortedArrayUsingComparator:^NSComparisonResult(NSNumber *key1, NSNumber *key2) {
        return [self.effectGlobalScores[key2] compare:self.effectGlobalScores[key1]];
    }];
    
    if (sortedEffects.count <= count) {
        return sortedEffects;
    }
    
    return [sortedEffects subarrayWithRange:NSMakeRange(0, count)];
}

#pragma mark - Context & Session

- (void)updateCurrentContext {
    self.currentContext = [UserContext currentContext];
    self.currentContext.sessionDuration = [[NSDate date] timeIntervalSinceDate:self.sessionStartTime];
    self.currentContext.lastManualEffectChoice = @(self.currentEffect).stringValue;
}

- (void)startNewSession {
    self.sessionStartTime = [NSDate date];
    self.currentContext = [UserContext currentContext];
    self.currentContext.todayPlayCount = 0;
    
    NSLog(@"🎬 开始新会话");
}

#pragma mark - Data Management

- (void)clearAllPreferences {
    [self.styleEffectScores removeAllObjects];
    [self.sceneEffectScores removeAllObjects];
    [self.effectGlobalScores removeAllObjects];
    [self.styleEffectCounts removeAllObjects];
    
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults removeObjectForKey:kStyleEffectScoresKey];
    [defaults removeObjectForKey:kSceneEffectScoresKey];
    [defaults removeObjectForKey:kEffectGlobalScoresKey];
    [defaults synchronize];
    
    NSLog(@"🗑️ 已清除所有偏好数据");
}

- (NSDictionary *)exportPreferences {
    return @{
        @"styleEffectScores": self.styleEffectScores ?: @{},
        @"sceneEffectScores": self.sceneEffectScores ?: @{},
        @"effectGlobalScores": self.effectGlobalScores ?: @{},
        @"currentContext": @{
            @"hourOfDay": @(self.currentContext.hourOfDay),
            @"isWeekend": @(self.currentContext.isWeekend),
            @"usageScene": [UserContext nameForScene:self.currentContext.usageScene],
        }
    };
}

#pragma mark - 策略调整

static NSString * const kPreferenceWeightKey = @"UserPreferenceEngine_Weight";

- (void)boostUserPreferenceWeight:(float)amount {
    self.preferenceWeight = MIN(1.0, self.preferenceWeight + amount);
    [self savePreferenceWeight];
    NSLog(@"👤 用户偏好权重提升至 %.2f", self.preferenceWeight);
}

- (void)savePreferenceWeight {
    [[NSUserDefaults standardUserDefaults] setFloat:self.preferenceWeight forKey:kPreferenceWeightKey];
}

- (void)loadPreferenceWeight {
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if ([defaults objectForKey:kPreferenceWeightKey]) {
        self.preferenceWeight = [defaults floatForKey:kPreferenceWeightKey];
    } else {
        self.preferenceWeight = 0.5;  // 默认权重
    }
}

@end
