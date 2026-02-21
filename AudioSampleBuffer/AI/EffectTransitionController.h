//
//  EffectTransitionController.h
//  AudioSampleBuffer
//
//  特效过渡控制器 - 实现平滑的特效切换
//

#import <Foundation/Foundation.h>
#import "VisualEffectType.h"
#import "AudioFeatureExtractor.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 过渡类型

typedef NS_ENUM(NSUInteger, TransitionType) {
    TransitionTypeCrossfade,      // 交叉淡入淡出
    TransitionTypeWipe,           // 擦除过渡
    TransitionTypeBeatSync,       // 等待下一个节拍切换
    TransitionTypeInstant,        // 立即切换
    TransitionTypeDissolve,       // 溶解过渡
    TransitionTypeZoom,           // 缩放过渡
};

#pragma mark - 过渡状态

typedef NS_ENUM(NSUInteger, TransitionState) {
    TransitionStateIdle,          // 空闲
    TransitionStateWaitingBeat,   // 等待节拍
    TransitionStateTransitioning, // 正在过渡
    TransitionStateCompleted,     // 完成
};

#pragma mark - 过渡进度回调

@class EffectTransitionController;

@protocol EffectTransitionDelegate <NSObject>
@optional
/// 过渡进度更新
- (void)transitionController:(EffectTransitionController *)controller
         didUpdateProgress:(float)progress
                fromEffect:(VisualEffectType)fromEffect
                  toEffect:(VisualEffectType)toEffect;

/// 过渡完成
- (void)transitionController:(EffectTransitionController *)controller
      didCompleteTransitionToEffect:(VisualEffectType)effect;

/// 准备开始过渡
- (void)transitionController:(EffectTransitionController *)controller
       willStartTransitionFromEffect:(VisualEffectType)fromEffect
                            toEffect:(VisualEffectType)toEffect;
@end

#pragma mark - 过渡配置

@interface TransitionConfiguration : NSObject

@property (nonatomic, assign) TransitionType type;
@property (nonatomic, assign) NSTimeInterval duration;        // 过渡持续时间
@property (nonatomic, assign) float easeInFactor;             // 缓入因子 [0-1]
@property (nonatomic, assign) float easeOutFactor;            // 缓出因子 [0-1]
@property (nonatomic, assign) BOOL waitForBeat;               // 是否等待节拍开始

+ (instancetype)defaultConfiguration;
+ (instancetype)configurationWithType:(TransitionType)type duration:(NSTimeInterval)duration;

@end

#pragma mark - 特效过渡控制器

@interface EffectTransitionController : NSObject

/// 单例
+ (instancetype)sharedController;

/// 代理
@property (nonatomic, weak, nullable) id<EffectTransitionDelegate> delegate;

/// 当前状态
@property (nonatomic, assign, readonly) TransitionState state;

/// 当前过渡进度 [0-1]
@property (nonatomic, assign, readonly) float progress;

/// 源特效
@property (nonatomic, assign, readonly) VisualEffectType fromEffect;

/// 目标特效
@property (nonatomic, assign, readonly) VisualEffectType toEffect;

/// 是否正在过渡
@property (nonatomic, assign, readonly) BOOL isTransitioning;

#pragma mark - 过渡控制

/// 开始过渡
- (void)transitionFromEffect:(VisualEffectType)from
                    toEffect:(VisualEffectType)to
              transitionType:(TransitionType)type
                    duration:(NSTimeInterval)duration;

/// 使用配置开始过渡
- (void)transitionFromEffect:(VisualEffectType)from
                    toEffect:(VisualEffectType)to
               configuration:(TransitionConfiguration *)config;

/// 更新过渡（每帧调用）
/// @param deltaTime 帧间隔时间
/// @return 当前混合因子 [0=源特效, 1=目标特效]
- (float)updateWithDeltaTime:(NSTimeInterval)deltaTime;

/// 通知节拍发生（用于 BeatSync 模式）
- (void)notifyBeatDetected;

/// 取消当前过渡
- (void)cancelTransition;

/// 立即完成过渡
- (void)completeImmediately;

#pragma mark - 混合计算

/// 获取当前特效混合权重
/// @param effectA A特效的混合权重（输出）
/// @param effectB B特效的混合权重（输出）
- (void)getBlendWeightsForEffectA:(float *)effectA effectB:(float *)effectB;

/// 获取适用于当前过渡进度的缓动值
- (float)easedProgress;

@end

NS_ASSUME_NONNULL_END
