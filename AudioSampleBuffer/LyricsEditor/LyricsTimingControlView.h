//
//  LyricsTimingControlView.h
//  AudioSampleBuffer
//
//  歌词打轴控制面板 - 播放控制、打轴按钮、进度显示、波形显示
//

#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

@class LyricsTimingControlView;

/// 打轴控制面板代理
@protocol LyricsTimingControlViewDelegate <NSObject>

/// 播放/暂停按钮点击
- (void)timingControlViewDidTapPlayPause:(LyricsTimingControlView *)view;

/// 打轴按钮点击（核心：记录当前时间）
- (void)timingControlViewDidTapStamp:(LyricsTimingControlView *)view;

/// 回退上一行
- (void)timingControlViewDidTapGoBack:(LyricsTimingControlView *)view;

/// 跳过当前行
- (void)timingControlViewDidTapSkip:(LyricsTimingControlView *)view;

/// 进度条拖动
- (void)timingControlView:(LyricsTimingControlView *)view didSeekToProgress:(float)progress;

/// 快进/快退
- (void)timingControlView:(LyricsTimingControlView *)view didSeekBySeconds:(NSTimeInterval)seconds;

/// 点击波形跳转到指定时间
- (void)timingControlView:(LyricsTimingControlView *)view didSeekToTime:(NSTimeInterval)time;

@end

/// 打轴控制面板
@interface LyricsTimingControlView : UIView

/// 代理
@property (nonatomic, weak, nullable) id<LyricsTimingControlViewDelegate> delegate;

/// 是否正在播放
@property (nonatomic, assign) BOOL isPlaying;

/// 更新播放时间显示
/// @param currentTime 当前时间（秒）
/// @param duration 总时长（秒）
- (void)updateTimeDisplay:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration;

/// 更新进度条
/// @param progress 进度（0-1）
- (void)updateProgress:(float)progress;

/// 更新打轴进度显示
/// @param current 已打轴行数
/// @param total 总行数
- (void)updateStampProgress:(NSInteger)current total:(NSInteger)total;

/// 设置当前歌词行预览
/// @param text 当前歌词文本
- (void)setCurrentLyricPreview:(NSString *)text;

/// 启用/禁用打轴按钮
/// @param enabled 是否启用
- (void)setStampButtonEnabled:(BOOL)enabled;

/// 播放打轴成功动画
- (void)playStampSuccessAnimation;

/// 加载音频波形
/// @param filePath 音频文件路径
- (void)loadWaveformFromFile:(NSString *)filePath;

/// 更新波形上的时间标记
/// @param timestamps 已打轴的时间戳数组
- (void)updateWaveformMarkers:(NSArray<NSNumber *> *)timestamps;

@end

NS_ASSUME_NONNULL_END

