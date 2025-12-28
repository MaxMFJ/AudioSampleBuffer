//
//  ViewController+PlaybackProgress.h
//  AudioSampleBuffer
//
//  播放进度条扩展 - 为 ViewController 添加进度条功能
//

#import "ViewController.h"
#import "AudioProgressView.h"

NS_ASSUME_NONNULL_BEGIN

@interface ViewController (PlaybackProgress) <AudioProgressViewDelegate>

/// 进度条视图
@property (nonatomic, strong, readonly) AudioProgressView *progressView;

/// 设置进度条（在 viewDidLoad 中调用）
- (void)setupProgressView;

/// 更新进度条当前时间
/// @param currentTime 当前播放时间（秒）
- (void)updateProgressWithCurrentTime:(NSTimeInterval)currentTime;

/// 更新进度条总时长
/// @param duration 总时长（秒）
- (void)updateProgressWithDuration:(NSTimeInterval)duration;

/// 重置进度条
- (void)resetProgress;

/// 显示/隐藏进度条
/// @param hidden 是否隐藏
/// @param animated 是否动画
- (void)setProgressViewHidden:(BOOL)hidden animated:(BOOL)animated;

@end

NS_ASSUME_NONNULL_END

