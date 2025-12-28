//
//  AudioWaveformView.h
//  AudioSampleBuffer
//
//  音频波形显示视图 - 用于辅助歌词打轴定位
//

#import <UIKit/UIKit.h>
#import <AVFoundation/AVFoundation.h>

NS_ASSUME_NONNULL_BEGIN

@class AudioWaveformView;

/// 波形视图代理
@protocol AudioWaveformViewDelegate <NSObject>

@optional
/// 用户点击了波形的某个位置，返回对应的时间
- (void)waveformView:(AudioWaveformView *)view didTapAtTime:(NSTimeInterval)time;

/// 用户拖动了波形位置
- (void)waveformView:(AudioWaveformView *)view didDragToTime:(NSTimeInterval)time;

@end

/// 音频波形显示视图
@interface AudioWaveformView : UIView

/// 代理
@property (nonatomic, weak, nullable) id<AudioWaveformViewDelegate> delegate;

/// 波形颜色
@property (nonatomic, strong) UIColor *waveformColor;

/// 播放位置指示线颜色
@property (nonatomic, strong) UIColor *playheadColor;

/// 已播放部分颜色
@property (nonatomic, strong) UIColor *playedColor;

/// 未播放部分颜色
@property (nonatomic, strong) UIColor *unplayedColor;

/// 时间戳标记颜色
@property (nonatomic, strong) UIColor *markerColor;

/// 音频总时长
@property (nonatomic, assign, readonly) NSTimeInterval duration;

/// 当前播放位置
@property (nonatomic, assign) NSTimeInterval currentTime;

/// 是否正在加载波形
@property (nonatomic, assign, readonly) BOOL isLoading;

/// 时间戳标记数组（用于显示已打轴的位置）
@property (nonatomic, strong) NSArray<NSNumber *> *timeMarkers;

/// 显示的时间范围（秒），默认显示整个音频
@property (nonatomic, assign) NSTimeInterval visibleDuration;

/// 波形偏移时间（用于滚动显示）
@property (nonatomic, assign) NSTimeInterval timeOffset;

/// 是否跟随播放位置自动滚动
@property (nonatomic, assign) BOOL autoScrollEnabled;

#pragma mark - 加载波形

/// 从音频文件路径加载波形
/// @param filePath 音频文件路径
- (void)loadWaveformFromFile:(NSString *)filePath;

/// 从音频 URL 加载波形
/// @param url 音频文件 URL
- (void)loadWaveformFromURL:(NSURL *)url;

/// 从 AVAsset 加载波形
/// @param asset 音频资源
- (void)loadWaveformFromAsset:(AVAsset *)asset;

/// 清除波形数据
- (void)clearWaveform;

#pragma mark - 交互

/// 设置当前播放位置（带动画）
/// @param time 当前时间
/// @param animated 是否动画
- (void)setCurrentTime:(NSTimeInterval)time animated:(BOOL)animated;

/// 滚动到指定时间位置
/// @param time 目标时间
/// @param animated 是否动画
- (void)scrollToTime:(NSTimeInterval)time animated:(BOOL)animated;

/// 放大/缩小波形显示
/// @param scale 缩放比例（1.0 = 正常，2.0 = 放大2倍）
- (void)setZoomScale:(CGFloat)scale;

@end

NS_ASSUME_NONNULL_END

