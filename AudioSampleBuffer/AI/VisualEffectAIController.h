//
//  VisualEffectAIController.h
//  AudioSampleBuffer
//
//  视觉效果AI控制器 - 整合所有AI模块的统一接口
//

#import <Foundation/Foundation.h>
#import "AudioFeatureExtractor.h"
#import "MusicStyleClassifier.h"
#import "EffectDecisionAgent.h"
#import "UserPreferenceEngine.h"
#import "RealtimeParameterTuner.h"
#import "EffectTransitionController.h"
#import "VisualEffectType.h"

NS_ASSUME_NONNULL_BEGIN

/// AI控制器状态更新通知
extern NSString *const kVisualEffectAIStateDidChangeNotification;
/// AI决策完成通知
extern NSString *const kVisualEffectAIDecisionDidCompleteNotification;

#pragma mark - AI控制器代理

@protocol VisualEffectAIControllerDelegate <NSObject>
@optional
/// AI选择了新特效
- (void)aiController:(id)controller didSelectEffect:(VisualEffectType)effect withDecision:(EffectDecision *)decision;

/// AI调整了特效参数
- (void)aiController:(id)controller didTuneParameters:(EffectParameters *)parameters;

/// AI检测到段落变化
- (void)aiController:(id)controller didDetectSegmentChange:(MusicSegment)segment suggestedEffect:(VisualEffectType)effect;

/// AI检测到节拍
- (void)aiController:(id)controller didDetectBeatWithIntensity:(float)intensity;

/// 音乐风格已识别
- (void)aiController:(id)controller didClassifyStyle:(MusicStyle)style confidence:(float)confidence;
@end

#pragma mark - 视觉效果AI控制器

@interface VisualEffectAIController : NSObject <AudioFeatureObserver, EffectTransitionDelegate>

/// 单例
+ (instancetype)sharedController;

/// 代理
@property (nonatomic, weak, nullable) id<VisualEffectAIControllerDelegate> delegate;

#pragma mark - 模式控制

/// AI自动模式是否启用
@property (nonatomic, assign) BOOL autoModeEnabled;

/// 段落自动切换是否启用
@property (nonatomic, assign) BOOL segmentSwitchEnabled;

/// 实时参数调谐是否启用
@property (nonatomic, assign) BOOL realtimeTuningEnabled;

/// 节拍同步是否启用
@property (nonatomic, assign) BOOL beatSyncEnabled;

#pragma mark - 状态

/// 当前音乐风格
@property (nonatomic, assign, readonly) MusicStyle currentStyle;

/// 当前音乐段落
@property (nonatomic, assign, readonly) MusicSegment currentSegment;

/// 当前AI决策
@property (nonatomic, strong, readonly, nullable) EffectDecision *currentDecision;

/// 当前特效参数
@property (nonatomic, strong, readonly) EffectParameters *currentParameters;

/// 是否正在过渡
@property (nonatomic, assign, readonly) BOOL isTransitioning;

#pragma mark - 主要接口

/// 开始播放新歌曲时调用
/// @param songName 歌曲名
/// @param artist 艺术家
- (void)startWithSongName:(NSString *)songName artist:(nullable NSString *)artist;

/// 处理频谱数据（每帧调用）
/// @param spectrumData 频谱数组
- (void)processSpectrumData:(NSArray<NSNumber *> *)spectrumData;

/// 停止AI分析
- (void)stop;

/// 重置状态
- (void)reset;

#pragma mark - 用户交互反馈

/// 用户手动切换特效
- (void)userDidManuallySelectEffect:(VisualEffectType)effect;

/// 用户跳过歌曲
- (void)userDidSkipSong;

/// 用户完整听完歌曲
- (void)userDidFinishListening;

#pragma mark - 过渡控制

/// 获取当前过渡混合因子
- (float)transitionBlendFactor;

/// 强制完成过渡
- (void)completeTransitionImmediately;

#pragma mark - 调试

/// 导出当前状态（调试用）
- (NSDictionary *)debugInfo;

@end

NS_ASSUME_NONNULL_END
