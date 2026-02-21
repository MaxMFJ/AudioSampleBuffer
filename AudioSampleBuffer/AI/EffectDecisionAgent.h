//
//  EffectDecisionAgent.h
//  AudioSampleBuffer
//
//  特效决策Agent - 完全自主的AI决策引擎
//  - 自主触发分析和决策
//  - 多轮重试和动态权重
//  - 历史表现学习
//  - 磁盘持久化缓存
//

#import <Foundation/Foundation.h>
#import "AudioFeatureExtractor.h"
#import "MusicStyleClassifier.h"
#import "UserPreferenceEngine.h"
#import "VisualEffectType.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 通知

/// Agent 决策完成通知
extern NSString *const kEffectDecisionAgentDidCompleteNotification;
/// Agent 开始分析通知
extern NSString *const kEffectDecisionAgentDidStartAnalysisNotification;
/// Agent 学习更新通知
extern NSString *const kEffectDecisionAgentDidLearnNotification;

#pragma mark - 决策来源

typedef NS_ENUM(NSUInteger, DecisionSource) {
    DecisionSourceUserPreference,   // 用户偏好
    DecisionSourceLocalRules,       // 本地规则
    DecisionSourceLLMCache,         // LLM缓存
    DecisionSourceLLMRealtime,      // LLM实时调用
    DecisionSourceFallback,         // 降级默认
    DecisionSourceSelfLearning,     // 自学习
};

#pragma mark - 决策历史记录

@interface DecisionHistoryRecord : NSObject <NSSecureCoding>

@property (nonatomic, copy) NSString *songName;
@property (nonatomic, copy, nullable) NSString *artist;
@property (nonatomic, assign) MusicStyle style;
@property (nonatomic, assign) VisualEffectType selectedEffect;
@property (nonatomic, assign) DecisionSource source;
@property (nonatomic, assign) float initialConfidence;
@property (nonatomic, assign) float userSatisfaction;  // 0-1, 基于用户行为推断
@property (nonatomic, strong) NSDate *timestamp;
@property (nonatomic, assign) NSTimeInterval listeningDuration;
@property (nonatomic, assign) BOOL wasSkipped;
@property (nonatomic, assign) BOOL wasManuallyChanged;

@end

#pragma mark - 特效决策结果

@interface EffectDecision : NSObject <NSSecureCoding>

@property (nonatomic, assign) VisualEffectType effectType;
@property (nonatomic, assign) VisualEffectType fallbackEffect;
@property (nonatomic, strong, nullable) NSDictionary *parameters;
@property (nonatomic, assign) float confidence;
@property (nonatomic, assign) DecisionSource source;
@property (nonatomic, copy, nullable) NSString *reasoning;
@property (nonatomic, assign) NSInteger retryCount;  // LLM 重试次数

// 段落特效映射
@property (nonatomic, strong, nullable) NSDictionary<NSNumber *, NSNumber *> *segmentEffects;

// LLM 返回的原始数据
@property (nonatomic, strong, nullable) NSDictionary *llmRawResponse;

+ (instancetype)decisionWithEffect:(VisualEffectType)effect
                        confidence:(float)confidence
                            source:(DecisionSource)source;

@end

#pragma mark - 决策回调

typedef void(^EffectDecisionCompletion)(EffectDecision *decision);
typedef void(^LLMAnalysisCompletion)(NSDictionary * _Nullable response, NSError * _Nullable error);

#pragma mark - Agent 配置

@interface AgentConfiguration : NSObject

@property (nonatomic, assign) float localRulesConfidenceThreshold;
@property (nonatomic, assign) float userPreferenceConfidenceThreshold;
@property (nonatomic, assign) float selfLearningWeight;       // 自学习权重 (0-1)
@property (nonatomic, assign) NSInteger maxLLMRetries;        // 最大重试次数
@property (nonatomic, assign) NSTimeInterval llmTimeout;      // LLM 超时时间
@property (nonatomic, assign) BOOL enableSelfLearning;        // 启用自学习
@property (nonatomic, assign) BOOL enableDirectLLMCall;       // 直接调用 DeepSeek
@property (nonatomic, assign) NSInteger historyRecordLimit;   // 历史记录上限

+ (instancetype)defaultConfiguration;

@end

#pragma mark - 特效决策Agent

@interface EffectDecisionAgent : NSObject

/// 单例
+ (instancetype)sharedAgent;

/// 当前决策
@property (nonatomic, strong, readonly, nullable) EffectDecision *currentDecision;

/// Agent 配置
@property (nonatomic, strong) AgentConfiguration *configuration;

/// 自动模式是否启用
@property (nonatomic, assign) BOOL autoModeEnabled;

/// 是否正在决策中
@property (nonatomic, assign, readonly) BOOL isDeciding;

/// 是否正在调用 LLM
@property (nonatomic, assign, readonly) BOOL isCallingLLM;

/// 决策统计
@property (nonatomic, readonly) NSDictionary<NSString *, NSNumber *> *decisionStatistics;

#pragma mark - 主要决策接口

/// 完全自主的特效决策（Agent 自己触发分析）
/// @param songName 歌曲名
/// @param artist 艺术家
/// @param completion 决策完成回调
- (void)autonomousDecisionForSong:(NSString *)songName
                           artist:(nullable NSString *)artist
                       completion:(EffectDecisionCompletion)completion;

/// 歌曲开始时的主特效决策
- (void)decidePrimaryEffectForSong:(NSString *)songName
                            artist:(nullable NSString *)artist
                          features:(AudioFeatures *)features
                           context:(UserContext *)context
                        completion:(EffectDecisionCompletion)completion;

/// 段落变化时的特效调整
- (EffectDecision *)adjustEffectForSegmentChange:(MusicSegment)newSegment
                                   currentEffect:(VisualEffectType)currentEffect;

/// 实时特征变化时的微调决策
- (nullable EffectDecision *)evaluateEffectChangeWithFeatures:(AudioFeatures *)features;

#pragma mark - 直接 LLM 调用

/// 直接调用 DeepSeek 进行分析
/// @param songName 歌曲名
/// @param artist 艺术家
/// @param additionalContext 额外上下文信息
/// @param completion 完成回调
- (void)callDeepSeekDirectly:(NSString *)songName
                      artist:(nullable NSString *)artist
           additionalContext:(nullable NSDictionary *)additionalContext
                  completion:(LLMAnalysisCompletion)completion;

#pragma mark - 自学习接口

/// 记录决策结果用于学习
/// @param decision 决策
/// @param songName 歌曲名
/// @param artist 艺术家
/// @param style 音乐风格
- (void)recordDecision:(EffectDecision *)decision
           forSongName:(NSString *)songName
                artist:(nullable NSString *)artist
                 style:(MusicStyle)style;

/// 用户跳过歌曲时更新学习
- (void)userDidSkipSong:(NSString *)songName artist:(nullable NSString *)artist;

/// 用户手动切换特效时更新学习
- (void)userDidManuallyChangeEffect:(VisualEffectType)newEffect
                        forSongName:(NSString *)songName
                             artist:(nullable NSString *)artist;

/// 用户完整听完歌曲时更新学习
- (void)userDidFinishListening:(NSString *)songName
                        artist:(nullable NSString *)artist
                      duration:(NSTimeInterval)duration;

/// 获取学习到的特效偏好
- (NSDictionary<NSNumber *, NSNumber *> *)learnedPreferencesForStyle:(MusicStyle)style;

/// 重置学习数据
- (void)resetLearningData;

#pragma mark - 缓存管理

/// 清除所有缓存
- (void)clearAllCache;

/// 清除特定歌曲缓存
- (void)clearCacheForSong:(NSString *)songName artist:(nullable NSString *)artist;

/// 获取缓存状态
- (NSDictionary *)cacheStatus;

/// 强制保存缓存到磁盘
- (void)forceSaveCache;

#pragma mark - 本地规则

+ (NSArray<NSNumber *> *)recommendedEffectsForStyle:(MusicStyle)style;
+ (NSDictionary *)defaultParametersForEffect:(VisualEffectType)effect style:(MusicStyle)style;

#pragma mark - 便捷配置属性

@property (nonatomic, assign) float localRulesConfidenceThreshold;
@property (nonatomic, assign) float userPreferenceConfidenceThreshold;

@end

NS_ASSUME_NONNULL_END
