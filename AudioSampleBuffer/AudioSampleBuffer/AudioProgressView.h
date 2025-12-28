//
//  AudioProgressView.h
//  AudioSampleBuffer
//
//  播放进度条组件 - 支持拖拽跳转播放
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class AudioProgressView;

/// 进度条代理协议
@protocol AudioProgressViewDelegate <NSObject>

@optional
/// 用户拖拽进度条跳转到指定时间
/// @param progressView 进度条视图
/// @param time 目标时间（秒）
- (void)audioProgressView:(AudioProgressView *)progressView didSeekToTime:(NSTimeInterval)time;

/// 用户开始拖拽进度条
/// @param progressView 进度条视图
- (void)audioProgressViewDidBeginSeeking:(AudioProgressView *)progressView;

/// 用户结束拖拽进度条
/// @param progressView 进度条视图
- (void)audioProgressViewDidEndSeeking:(AudioProgressView *)progressView;

@end

/// 播放进度条视图
/// 支持显示当前播放进度、总时长，以及拖拽跳转功能
@interface AudioProgressView : UIView

/// 代理
@property (nonatomic, weak, nullable) id<AudioProgressViewDelegate> delegate;

/// 当前播放时间（秒）
@property (nonatomic, assign) NSTimeInterval currentTime;

/// 总时长（秒）
@property (nonatomic, assign) NSTimeInterval duration;

/// 是否正在播放
@property (nonatomic, assign) BOOL isPlaying;

/// 进度条颜色（默认蓝色）
@property (nonatomic, strong) UIColor *progressColor;

/// 进度条背景颜色（默认深灰色）
@property (nonatomic, strong) UIColor *trackColor;

/// 滑块颜色（默认白色）
@property (nonatomic, strong) UIColor *thumbColor;

/// 时间文字颜色（默认白色）
@property (nonatomic, strong) UIColor *timeTextColor;

/// 是否正在拖拽中
@property (nonatomic, assign, readonly) BOOL isSeeking;

/// 更新当前播放时间
/// @param currentTime 当前时间（秒）
- (void)updateCurrentTime:(NSTimeInterval)currentTime;

/// 更新总时长
/// @param duration 总时长（秒）
- (void)updateDuration:(NSTimeInterval)duration;

/// 重置进度条
- (void)reset;

@end

NS_ASSUME_NONNULL_END

