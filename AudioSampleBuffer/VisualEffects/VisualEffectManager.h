//
//  VisualEffectManager.h
//  AudioSampleBuffer
//
//  视觉效果统一管理器
//

#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>
#import <MetalKit/MetalKit.h>
#import "VisualEffectType.h"
#import "MetalRenderer.h"
#import "EffectSelectorView.h"

NS_ASSUME_NONNULL_BEGIN

@class SpectrumView;  // 前向声明
@class VisualEffectAIController;  // AI控制器前向声明
@class EffectDecision;  // AI决策前向声明
@class EffectParameters;  // 特效参数前向声明

@protocol VisualEffectManagerDelegate <NSObject>
@optional
- (void)visualEffectManager:(id)manager didChangeEffect:(VisualEffectType)effectType;
- (void)visualEffectManager:(id)manager didUpdatePerformance:(NSDictionary *)stats;
- (void)visualEffectManager:(id)manager didEncounterError:(NSError *)error;
/// AI自动选择了特效
- (void)visualEffectManager:(id)manager aiDidSelectEffect:(VisualEffectType)effectType withDecision:(EffectDecision *)decision;
/// AI调整了特效参数
- (void)visualEffectManager:(id)manager aiDidTuneParameters:(EffectParameters *)parameters;
@end

/**
 * 视觉效果管理器
 * 统一管理所有视觉效果的显示、切换和配置
 */
@interface VisualEffectManager : NSObject <EffectSelectorDelegate>

@property (nonatomic, weak) id<VisualEffectManagerDelegate> delegate;
@property (nonatomic, assign, readonly) VisualEffectType currentEffectType;
@property (nonatomic, assign, readonly) BOOL isEffectActive;
@property (nonatomic, strong, readonly) UIView *effectContainerView;
@property (nonatomic, strong, readonly) MTKView *metalView;  // Metal视图，用于FPS监控
@property (nonatomic, assign, readonly) CGFloat actualFPS;  // 实际渲染FPS

/**
 * 初始化管理器
 * @param containerView 效果显示容器
 */
- (instancetype)initWithContainerView:(UIView *)containerView;

/**
 * 设置原有的频谱视图引用（用于在Metal特效时暂停）
 * @param spectrumView 频谱视图
 */
- (void)setOriginalSpectrumView:(SpectrumView *)spectrumView;

/**
 * 显示特效选择界面
 */
- (void)showEffectSelector;

/**
 * 隐藏特效选择界面
 */
- (void)hideEffectSelector;

/**
 * 设置当前特效
 * @param effectType 特效类型
 * @param animated 是否使用动画
 */
- (void)setCurrentEffect:(VisualEffectType)effectType animated:(BOOL)animated;

/**
 * 更新频谱数据
 * @param spectrumData 频谱数据数组
 */
- (void)updateSpectrumData:(NSArray<NSNumber *> *)spectrumData;

/**
 * 开始渲染
 */
- (void)startRendering;

/**
 * 停止渲染
 */
- (void)stopRendering;

/**
 * 暂停渲染
 */
- (void)pauseRendering;

/**
 * 恢复渲染
 */
- (void)resumeRendering;

/**
 * 设置渲染参数
 * @param parameters 参数字典
 */
- (void)setRenderParameters:(NSDictionary *)parameters;

/**
 * 获取当前性能统计
 */
- (NSDictionary *)performanceStatistics;

/**
 * 检查特效是否受支持
 */
- (BOOL)isEffectSupported:(VisualEffectType)effectType;

/**
 * 获取推荐的特效设置
 */
- (NSDictionary *)recommendedSettingsForCurrentDevice;

/**
 * 应用性能设置（帧率、MSAA、Shader复杂度）
 * @param settings 性能设置字典
 */
- (void)applyPerformanceSettings:(NSDictionary *)settings;

#pragma mark - AI 自动模式

/**
 * AI自动模式是否启用
 */
@property (nonatomic, assign) BOOL aiAutoModeEnabled;

/**
 * AI控制器
 */
@property (nonatomic, strong, readonly, nullable) VisualEffectAIController *aiController;

/**
 * 开始AI自动模式（播放新歌曲时调用）
 * @param songName 歌曲名
 * @param artist 艺术家
 */
- (void)startAIModeWithSongName:(NSString *)songName artist:(nullable NSString *)artist;

/**
 * 停止AI自动模式
 */
- (void)stopAIMode;

/**
 * 用户手动切换特效（通知AI学习偏好）
 */
- (void)userDidManuallySelectEffect:(VisualEffectType)effectType;

/**
 * 用户跳过歌曲（通知AI）
 */
- (void)userDidSkipSong;

/**
 * 用户完整听完歌曲（通知AI）
 */
- (void)userDidFinishListening;

@end

NS_ASSUME_NONNULL_END
