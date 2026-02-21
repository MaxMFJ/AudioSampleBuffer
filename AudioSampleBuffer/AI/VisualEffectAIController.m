//
//  VisualEffectAIController.m
//  AudioSampleBuffer
//

#import "VisualEffectAIController.h"
#import <QuartzCore/QuartzCore.h>

NSString *const kVisualEffectAIStateDidChangeNotification = @"VisualEffectAIStateDidChangeNotification";
NSString *const kVisualEffectAIDecisionDidCompleteNotification = @"VisualEffectAIDecisionDidCompleteNotification";

@interface VisualEffectAIController ()

// 子模块
@property (nonatomic, strong) AudioFeatureExtractor *featureExtractor;
@property (nonatomic, strong) MusicStyleClassifier *styleClassifier;
@property (nonatomic, strong) EffectDecisionAgent *decisionAgent;
@property (nonatomic, strong) UserPreferenceEngine *preferenceEngine;
@property (nonatomic, strong) RealtimeParameterTuner *parameterTuner;
@property (nonatomic, strong) EffectTransitionController *transitionController;

// 状态
@property (nonatomic, assign) MusicStyle currentStyle;
@property (nonatomic, assign) MusicSegment currentSegment;
@property (nonatomic, strong) EffectDecision *currentDecision;
@property (nonatomic, strong) EffectParameters *currentParameters;
@property (nonatomic, assign) VisualEffectType previousEffect;

// 时间追踪
@property (nonatomic, assign) NSTimeInterval sessionStartTime;
@property (nonatomic, assign) NSTimeInterval lastUpdateTime;
@property (nonatomic, assign) NSInteger frameCount;

// 歌曲信息
@property (nonatomic, copy) NSString *currentSongName;
@property (nonatomic, copy) NSString *currentArtist;

@end

@implementation VisualEffectAIController

+ (instancetype)sharedController {
    static VisualEffectAIController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VisualEffectAIController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        // 初始化子模块（使用单例）
        _featureExtractor = [AudioFeatureExtractor sharedExtractor];
        _styleClassifier = [MusicStyleClassifier sharedClassifier];
        _decisionAgent = [EffectDecisionAgent sharedAgent];
        _preferenceEngine = [UserPreferenceEngine sharedEngine];
        _parameterTuner = [RealtimeParameterTuner sharedTuner];
        _transitionController = [EffectTransitionController sharedController];
        
        // 设置代理
        [_featureExtractor addObserver:self];
        _transitionController.delegate = self;
        
        // 默认启用所有功能
        _autoModeEnabled = YES;
        _segmentSwitchEnabled = YES;
        _realtimeTuningEnabled = YES;
        _beatSyncEnabled = YES;
        
        // 初始状态
        _currentStyle = MusicStyleUnknown;
        _currentSegment = MusicSegmentUnknown;
        _currentParameters = [EffectParameters defaultParameters];
        _previousEffect = VisualEffectTypeClassicSpectrum;
        
        _sessionStartTime = CACurrentMediaTime();
        _lastUpdateTime = 0;
        _frameCount = 0;
        
        NSLog(@"🤖 VisualEffectAIController 初始化完成");
    }
    return self;
}

#pragma mark - Main Interface

- (void)startWithSongName:(NSString *)songName artist:(nullable NSString *)artist {
    if (!self.autoModeEnabled) {
        NSLog(@"🔇 AI自动模式已禁用");
        return;
    }
    
    self.currentSongName = songName;
    self.currentArtist = artist;
    self.sessionStartTime = CACurrentMediaTime();
    self.frameCount = 0;
    
    // 重置子模块
    [self.featureExtractor reset];
    [self.styleClassifier reset];
    [self.parameterTuner reset];
    
    // 更新用户上下文
    [self.preferenceEngine updateCurrentContext];
    [self.preferenceEngine startNewSession];
    
    NSLog(@"🎵 AI控制器开始: %@ - %@", songName, artist ?: @"Unknown");
    
    // 延迟2秒后触发AI决策（等待频谱数据稳定）
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, 2 * NSEC_PER_SEC), dispatch_get_main_queue(), ^{
        [self triggerInitialDecision];
    });
}

- (void)triggerInitialDecision {
    if (!self.autoModeEnabled || !self.currentSongName) return;
    
    AudioFeatures *features = self.featureExtractor.currentFeatures;
    
    // 如果频谱数据不足，使用自主决策模式
    if (!features || features.energy < 0.01) {
        NSLog(@"📊 频谱数据不足，使用自主决策模式");
        [self.decisionAgent autonomousDecisionForSong:self.currentSongName
                                               artist:self.currentArtist
                                           completion:^(EffectDecision *decision) {
            [self handleDecisionResult:decision];
        }];
        return;
    }
    
    UserContext *context = [UserContext currentContext];
    
    [self.decisionAgent decidePrimaryEffectForSong:self.currentSongName
                                            artist:self.currentArtist
                                          features:features
                                           context:context
                                        completion:^(EffectDecision *decision) {
        [self handleDecisionResult:decision];
    }];
}

- (void)handleDecisionResult:(EffectDecision *)decision {
    self.currentDecision = decision;
    self.previousEffect = decision.effectType;
    
    // 设置参数调谐器的基础参数
    if (decision.parameters) {
        [self.parameterTuner setBaseParametersFromDictionary:decision.parameters];
    }
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(aiController:didSelectEffect:withDecision:)]) {
        [self.delegate aiController:self didSelectEffect:decision.effectType withDecision:decision];
    }
    
    // 发送通知
    [[NSNotificationCenter defaultCenter] postNotificationName:kVisualEffectAIDecisionDidCompleteNotification
                                                        object:self
                                                      userInfo:@{@"decision": decision}];
    
    NSString *effectName = [[VisualEffectRegistry sharedRegistry] effectInfoForType:decision.effectType].name ?: @"Unknown";
    NSString *sourceName = [self sourceNameForDecision:decision];
    NSLog(@"✅ AI初始决策完成: 特效=%@ (ID:%lu), 置信度=%.2f, 来源=%@",
          effectName, (unsigned long)decision.effectType, decision.confidence, sourceName);
    NSLog(@"   决策原因: %@", decision.reasoning ?: @"无");
    
    // 显示重试信息
    if (decision.retryCount > 0) {
        NSLog(@"   LLM重试次数: %ld", (long)decision.retryCount);
    }
}

- (NSString *)sourceNameForDecision:(EffectDecision *)decision {
    switch (decision.source) {
        case DecisionSourceUserPreference: return @"用户偏好";
        case DecisionSourceLocalRules: return @"本地规则";
        case DecisionSourceLLMCache: return @"LLM缓存";
        case DecisionSourceLLMRealtime: return @"LLM实时";
        case DecisionSourceFallback: return @"降级回退";
        case DecisionSourceSelfLearning: return @"自学习";
        default: return @"未知";
    }
}

- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrumData {
    if (spectrumData.count == 0) return;
    
    self.frameCount++;
    NSTimeInterval currentTime = CACurrentMediaTime();
    NSTimeInterval deltaTime = currentTime - self.lastUpdateTime;
    self.lastUpdateTime = currentTime;
    
    // 1. 更新音频特征
    [self.featureExtractor processSpectrumData:spectrumData];
    AudioFeatures *features = self.featureExtractor.currentFeatures;
    
    // 2. 更新音乐风格分类（每30帧更新一次）
    if (self.frameCount % 30 == 0) {
        MusicStyleResult *styleResult = [self.styleClassifier classifyWithFeatures:features];
        if (styleResult.primaryStyle != self.currentStyle && styleResult.primaryConfidence > 0.6) {
            self.currentStyle = styleResult.primaryStyle;
            
            if ([self.delegate respondsToSelector:@selector(aiController:didClassifyStyle:confidence:)]) {
                [self.delegate aiController:self
                          didClassifyStyle:styleResult.primaryStyle
                                confidence:styleResult.primaryConfidence];
            }
        }
    }
    
    // 3. 实时参数调谐
    if (self.realtimeTuningEnabled) {
        self.currentParameters = [self.parameterTuner tuneParametersWithFeatures:features];
        
        if ([self.delegate respondsToSelector:@selector(aiController:didTuneParameters:)]) {
            [self.delegate aiController:self didTuneParameters:self.currentParameters];
        }
    }
    
    // 4. 更新过渡
    if (self.transitionController.isTransitioning) {
        [self.transitionController updateWithDeltaTime:deltaTime];
    }
    
    // 5. 检测节拍
    if (self.beatSyncEnabled && features.beatDetected) {
        [self.transitionController notifyBeatDetected];
        
        if ([self.delegate respondsToSelector:@selector(aiController:didDetectBeatWithIntensity:)]) {
            [self.delegate aiController:self didDetectBeatWithIntensity:features.bassEnergy];
        }
    }
}

- (void)stop {
    self.currentSongName = nil;
    self.currentArtist = nil;
    
    [self.transitionController cancelTransition];
    
    NSLog(@"🛑 AI控制器停止");
}

- (void)reset {
    [self stop];
    
    [self.featureExtractor reset];
    [self.styleClassifier reset];
    [self.parameterTuner reset];
    
    self.currentStyle = MusicStyleUnknown;
    self.currentSegment = MusicSegmentUnknown;
    self.currentDecision = nil;
    self.currentParameters = [EffectParameters defaultParameters];
    self.frameCount = 0;
    
    NSLog(@"🔄 AI控制器重置");
}

#pragma mark - User Interaction Feedback

- (void)userDidManuallySelectEffect:(VisualEffectType)effect {
    VisualEffectType oldEffect = self.previousEffect;
    self.previousEffect = effect;
    
    // 更新偏好引擎
    [self.preferenceEngine recordUserManuallyChangedEffect:effect fromEffect:oldEffect];
    
    // 更新决策Agent学习
    if (self.currentSongName) {
        [self.decisionAgent userDidManuallyChangeEffect:effect 
                                            forSongName:self.currentSongName 
                                                 artist:self.currentArtist];
    }
    
    NSLog(@"👆 用户手动选择特效: %lu (原: %lu)", (unsigned long)effect, (unsigned long)oldEffect);
}

- (void)userDidSkipSong {
    [self.preferenceEngine recordUserSkippedSong];
    
    // 更新决策Agent学习
    if (self.currentSongName) {
        [self.decisionAgent userDidSkipSong:self.currentSongName artist:self.currentArtist];
    }
    
    NSLog(@"⏭️ 用户跳过歌曲");
}

- (void)userDidFinishListening {
    [self.preferenceEngine recordUserListenedFull];
    
    // 更新决策Agent学习
    if (self.currentSongName && self.sessionStartTime > 0) {
        NSTimeInterval duration = CACurrentMediaTime() - self.sessionStartTime;
        [self.decisionAgent userDidFinishListening:self.currentSongName 
                                            artist:self.currentArtist 
                                          duration:duration];
    }
    
    NSLog(@"✅ 用户完整听完歌曲");
}

#pragma mark - AudioFeatureObserver

- (void)audioFeatureExtractor:(id)extractor didDetectBeatAtTime:(NSTimeInterval)time {
    // 节拍检测已在 processSpectrumData 中处理
}

- (void)audioFeatureExtractor:(id)extractor didChangeSegmentFrom:(MusicSegment)oldSegment to:(MusicSegment)newSegment {
    self.currentSegment = newSegment;
    
    if (!self.segmentSwitchEnabled || !self.currentDecision) return;
    
    // 检查段落特效映射
    NSNumber *suggestedEffectNum = self.currentDecision.segmentEffects[@(newSegment)];
    VisualEffectType suggestedEffect = suggestedEffectNum ? [suggestedEffectNum unsignedIntegerValue] : self.previousEffect;
    
    if (suggestedEffect != self.previousEffect) {
        // 使用节拍同步过渡
        [self.transitionController transitionFromEffect:self.previousEffect
                                               toEffect:suggestedEffect
                                         transitionType:TransitionTypeBeatSync
                                               duration:0.5];
        
        if ([self.delegate respondsToSelector:@selector(aiController:didDetectSegmentChange:suggestedEffect:)]) {
            [self.delegate aiController:self didDetectSegmentChange:newSegment suggestedEffect:suggestedEffect];
        }
        
        NSLog(@"🎭 段落变化: %@ -> 建议特效 %lu",
              [self segmentName:newSegment], (unsigned long)suggestedEffect);
    }
}

#pragma mark - EffectTransitionDelegate

- (void)transitionController:(EffectTransitionController *)controller
      didCompleteTransitionToEffect:(VisualEffectType)effect {
    self.previousEffect = effect;
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(aiController:didSelectEffect:withDecision:)]) {
        EffectDecision *decision = [EffectDecision decisionWithEffect:effect
                                                           confidence:0.8
                                                               source:DecisionSourceLocalRules];
        [self.delegate aiController:self didSelectEffect:effect withDecision:decision];
    }
}

#pragma mark - Transition Control

- (float)transitionBlendFactor {
    return [self.transitionController easedProgress];
}

- (BOOL)isTransitioning {
    return self.transitionController.isTransitioning;
}

- (void)completeTransitionImmediately {
    [self.transitionController completeImmediately];
}

#pragma mark - Helpers

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

#pragma mark - Debug

- (NSDictionary *)debugInfo {
    return @{
        @"autoModeEnabled": @(self.autoModeEnabled),
        @"currentStyle": [MusicStyleClassifier nameForStyle:self.currentStyle],
        @"currentSegment": [self segmentName:self.currentSegment],
        @"currentEffect": @(self.previousEffect),
        @"isTransitioning": @(self.isTransitioning),
        @"frameCount": @(self.frameCount),
        @"sessionDuration": @(CACurrentMediaTime() - self.sessionStartTime),
        @"features": @{
            @"bpm": @(self.featureExtractor.currentFeatures.bpm),
            @"energy": @(self.featureExtractor.currentFeatures.energy),
            @"bassEnergy": @(self.featureExtractor.currentFeatures.bassEnergy),
        },
        @"parameters": [self.currentParameters toDictionary],
        @"preferences": [self.preferenceEngine exportPreferences],
    };
}

@end
