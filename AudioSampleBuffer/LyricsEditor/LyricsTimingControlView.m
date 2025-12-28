//
//  LyricsTimingControlView.m
//  AudioSampleBuffer
//
//  歌词打轴控制面板 - 播放控制、打轴按钮、进度显示、波形显示
//

#import "LyricsTimingControlView.h"
#import "AudioWaveformView.h"

@interface LyricsTimingControlView () <AudioWaveformViewDelegate>

/// 波形视图
@property (nonatomic, strong) AudioWaveformView *waveformView;

/// 当前歌词预览标签
@property (nonatomic, strong) UILabel *lyricsPreviewLabel;

/// 进度条
@property (nonatomic, strong) UISlider *progressSlider;

/// 当前时间标签
@property (nonatomic, strong) UILabel *currentTimeLabel;

/// 总时长标签
@property (nonatomic, strong) UILabel *durationLabel;

/// 打轴进度标签
@property (nonatomic, strong) UILabel *stampProgressLabel;

/// 播放/暂停按钮
@property (nonatomic, strong) UIButton *playPauseButton;

/// 快退按钮
@property (nonatomic, strong) UIButton *rewindButton;

/// 快进按钮
@property (nonatomic, strong) UIButton *forwardButton;

/// 回退上一行按钮
@property (nonatomic, strong) UIButton *goBackButton;

/// 跳过按钮
@property (nonatomic, strong) UIButton *skipButton;

/// 打轴按钮（核心）
@property (nonatomic, strong) UIButton *stampButton;

/// 进度条是否正在拖动
@property (nonatomic, assign) BOOL isSliderTracking;

/// 音频时长（缓存用于波形更新）
@property (nonatomic, assign) NSTimeInterval audioDuration;

@end

@implementation LyricsTimingControlView

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 🔧 使用纯色背景，去掉模糊效果
    self.backgroundColor = [UIColor systemBackgroundColor];
    
    // 当前歌词预览
    _lyricsPreviewLabel = [[UILabel alloc] init];
    _lyricsPreviewLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _lyricsPreviewLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightSemibold];
    _lyricsPreviewLabel.textColor = [UIColor labelColor];
    _lyricsPreviewLabel.textAlignment = NSTextAlignmentCenter;
    _lyricsPreviewLabel.numberOfLines = 2;
    _lyricsPreviewLabel.text = @"等待开始打轴...";
    [self addSubview:_lyricsPreviewLabel];
    
    // 打轴进度
    _stampProgressLabel = [[UILabel alloc] init];
    _stampProgressLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _stampProgressLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _stampProgressLabel.textColor = [UIColor secondaryLabelColor];
    _stampProgressLabel.textAlignment = NSTextAlignmentCenter;
    _stampProgressLabel.text = @"0 / 0";
    [self addSubview:_stampProgressLabel];
    
    // 波形视图
    _waveformView = [[AudioWaveformView alloc] init];
    _waveformView.translatesAutoresizingMaskIntoConstraints = NO;
    _waveformView.delegate = self;
    [self addSubview:_waveformView];
    
    // 进度条
    _progressSlider = [[UISlider alloc] init];
    _progressSlider.translatesAutoresizingMaskIntoConstraints = NO;
    _progressSlider.minimumTrackTintColor = [UIColor systemBlueColor];
    _progressSlider.maximumTrackTintColor = [UIColor tertiarySystemFillColor];
    [_progressSlider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [_progressSlider addTarget:self action:@selector(sliderTouchDown) forControlEvents:UIControlEventTouchDown];
    [_progressSlider addTarget:self action:@selector(sliderTouchUp) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self addSubview:_progressSlider];
    
    // 时间标签
    _currentTimeLabel = [[UILabel alloc] init];
    _currentTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _currentTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _currentTimeLabel.textColor = [UIColor secondaryLabelColor];
    _currentTimeLabel.text = @"00:00";
    [self addSubview:_currentTimeLabel];
    
    _durationLabel = [[UILabel alloc] init];
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightMedium];
    _durationLabel.textColor = [UIColor secondaryLabelColor];
    _durationLabel.textAlignment = NSTextAlignmentRight;
    _durationLabel.text = @"00:00";
    [self addSubview:_durationLabel];
    
    // 控制按钮行
    [self setupControlButtons];
    
    // 打轴按钮（大按钮）
    _stampButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _stampButton.translatesAutoresizingMaskIntoConstraints = NO;
    _stampButton.backgroundColor = [UIColor systemBlueColor];
    _stampButton.layer.cornerRadius = 32;
    [_stampButton setTitle:@"打轴 ⏎" forState:UIControlStateNormal];
    [_stampButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _stampButton.titleLabel.font = [UIFont systemFontOfSize:18 weight:UIFontWeightBold];
    [_stampButton addTarget:self action:@selector(stampButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    
    // 添加阴影
    _stampButton.layer.shadowColor = [UIColor systemBlueColor].CGColor;
    _stampButton.layer.shadowOffset = CGSizeMake(0, 4);
    _stampButton.layer.shadowRadius = 8;
    _stampButton.layer.shadowOpacity = 0.3;
    [self addSubview:_stampButton];
    
    // 布局
    [self setupConstraints];
}

- (void)setupControlButtons {
    // 快退 5 秒
    _rewindButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _rewindButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_rewindButton setImage:[UIImage systemImageNamed:@"gobackward.5"] forState:UIControlStateNormal];
    _rewindButton.tintColor = [UIColor labelColor];
    [_rewindButton addTarget:self action:@selector(rewindButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_rewindButton];
    
    // 回退上一行
    _goBackButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _goBackButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_goBackButton setImage:[UIImage systemImageNamed:@"arrow.uturn.backward"] forState:UIControlStateNormal];
    _goBackButton.tintColor = [UIColor systemOrangeColor];
    [_goBackButton addTarget:self action:@selector(goBackButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_goBackButton];
    
    // 播放/暂停
    _playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _playPauseButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    _playPauseButton.tintColor = [UIColor labelColor];
    [_playPauseButton addTarget:self action:@selector(playPauseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_playPauseButton];
    
    // 跳过当前行
    _skipButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _skipButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_skipButton setImage:[UIImage systemImageNamed:@"forward.end"] forState:UIControlStateNormal];
    _skipButton.tintColor = [UIColor tertiaryLabelColor];
    [_skipButton addTarget:self action:@selector(skipButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_skipButton];
    
    // 快进 5 秒
    _forwardButton = [UIButton buttonWithType:UIButtonTypeSystem];
    _forwardButton.translatesAutoresizingMaskIntoConstraints = NO;
    [_forwardButton setImage:[UIImage systemImageNamed:@"goforward.5"] forState:UIControlStateNormal];
    _forwardButton.tintColor = [UIColor labelColor];
    [_forwardButton addTarget:self action:@selector(forwardButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_forwardButton];
}

- (void)setupConstraints {
    [NSLayoutConstraint activateConstraints:@[
        // 歌词预览
        [_lyricsPreviewLabel.topAnchor constraintEqualToAnchor:self.topAnchor constant:16],
        [_lyricsPreviewLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_lyricsPreviewLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        
        // 打轴进度
        [_stampProgressLabel.topAnchor constraintEqualToAnchor:_lyricsPreviewLabel.bottomAnchor constant:6],
        [_stampProgressLabel.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        
        // 波形视图
        [_waveformView.topAnchor constraintEqualToAnchor:_stampProgressLabel.bottomAnchor constant:8],
        [_waveformView.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_waveformView.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_waveformView.heightAnchor constraintEqualToConstant:50],
        
        // 进度条（隐藏，用波形代替）
        [_progressSlider.topAnchor constraintEqualToAnchor:_waveformView.bottomAnchor constant:8],
        [_progressSlider.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:16],
        [_progressSlider.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-16],
        [_progressSlider.heightAnchor constraintEqualToConstant:0], // 隐藏进度条
        
        // 时间标签
        [_currentTimeLabel.topAnchor constraintEqualToAnchor:_progressSlider.bottomAnchor constant:4],
        [_currentTimeLabel.leadingAnchor constraintEqualToAnchor:_progressSlider.leadingAnchor],
        
        [_durationLabel.topAnchor constraintEqualToAnchor:_progressSlider.bottomAnchor constant:4],
        [_durationLabel.trailingAnchor constraintEqualToAnchor:_progressSlider.trailingAnchor],
        
        // 控制按钮
        [_playPauseButton.topAnchor constraintEqualToAnchor:_currentTimeLabel.bottomAnchor constant:16],
        [_playPauseButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_playPauseButton.widthAnchor constraintEqualToConstant:44],
        [_playPauseButton.heightAnchor constraintEqualToConstant:44],
        
        [_goBackButton.centerYAnchor constraintEqualToAnchor:_playPauseButton.centerYAnchor],
        [_goBackButton.trailingAnchor constraintEqualToAnchor:_playPauseButton.leadingAnchor constant:-24],
        [_goBackButton.widthAnchor constraintEqualToConstant:44],
        [_goBackButton.heightAnchor constraintEqualToConstant:44],
        
        [_rewindButton.centerYAnchor constraintEqualToAnchor:_playPauseButton.centerYAnchor],
        [_rewindButton.trailingAnchor constraintEqualToAnchor:_goBackButton.leadingAnchor constant:-16],
        [_rewindButton.widthAnchor constraintEqualToConstant:44],
        [_rewindButton.heightAnchor constraintEqualToConstant:44],
        
        [_skipButton.centerYAnchor constraintEqualToAnchor:_playPauseButton.centerYAnchor],
        [_skipButton.leadingAnchor constraintEqualToAnchor:_playPauseButton.trailingAnchor constant:24],
        [_skipButton.widthAnchor constraintEqualToConstant:44],
        [_skipButton.heightAnchor constraintEqualToConstant:44],
        
        [_forwardButton.centerYAnchor constraintEqualToAnchor:_playPauseButton.centerYAnchor],
        [_forwardButton.leadingAnchor constraintEqualToAnchor:_skipButton.trailingAnchor constant:16],
        [_forwardButton.widthAnchor constraintEqualToConstant:44],
        [_forwardButton.heightAnchor constraintEqualToConstant:44],
        
        // 打轴按钮
        [_stampButton.topAnchor constraintEqualToAnchor:_playPauseButton.bottomAnchor constant:20],
        [_stampButton.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_stampButton.widthAnchor constraintEqualToConstant:160],
        [_stampButton.heightAnchor constraintEqualToConstant:64],
        [_stampButton.bottomAnchor constraintLessThanOrEqualToAnchor:self.bottomAnchor constant:-16],
    ]];
}

#pragma mark - Public Methods

- (void)setIsPlaying:(BOOL)isPlaying {
    _isPlaying = isPlaying;
    
    NSString *imageName = isPlaying ? @"pause.fill" : @"play.fill";
    [_playPauseButton setImage:[UIImage systemImageNamed:imageName] forState:UIControlStateNormal];
}

- (void)updateTimeDisplay:(NSTimeInterval)currentTime duration:(NSTimeInterval)duration {
    self.currentTimeLabel.text = [self formatTime:currentTime];
    self.durationLabel.text = [self formatTime:duration];
    self.audioDuration = duration;
    
    if (!self.isSliderTracking && duration > 0) {
        self.progressSlider.value = currentTime / duration;
    }
    
    // 更新波形视图
    [self.waveformView setCurrentTime:currentTime animated:NO];
}

- (void)updateProgress:(float)progress {
    if (!self.isSliderTracking) {
        self.progressSlider.value = progress;
    }
}

- (void)updateStampProgress:(NSInteger)current total:(NSInteger)total {
    self.stampProgressLabel.text = [NSString stringWithFormat:@"%ld / %ld", (long)current, (long)total];
    
    // 完成时的特殊样式
    if (current == total && total > 0) {
        self.stampProgressLabel.textColor = [UIColor systemGreenColor];
    } else {
        self.stampProgressLabel.textColor = [UIColor secondaryLabelColor];
    }
}

- (void)setCurrentLyricPreview:(NSString *)text {
    self.lyricsPreviewLabel.text = text ?: @"等待开始打轴...";
}

- (void)setStampButtonEnabled:(BOOL)enabled {
    self.stampButton.enabled = enabled;
    self.stampButton.alpha = enabled ? 1.0 : 0.5;
}

- (void)playStampSuccessAnimation {
    // 按钮缩放动画
    [UIView animateWithDuration:0.1 animations:^{
        self.stampButton.transform = CGAffineTransformMakeScale(0.9, 0.9);
        self.stampButton.backgroundColor = [UIColor systemGreenColor];
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.2 animations:^{
            self.stampButton.transform = CGAffineTransformIdentity;
            self.stampButton.backgroundColor = [UIColor systemBlueColor];
        }];
    }];
}

#pragma mark - Actions

- (void)playPauseButtonTapped {
    if ([self.delegate respondsToSelector:@selector(timingControlViewDidTapPlayPause:)]) {
        [self.delegate timingControlViewDidTapPlayPause:self];
    }
}

- (void)stampButtonTapped {
    if ([self.delegate respondsToSelector:@selector(timingControlViewDidTapStamp:)]) {
        [self.delegate timingControlViewDidTapStamp:self];
    }
}

- (void)goBackButtonTapped {
    if ([self.delegate respondsToSelector:@selector(timingControlViewDidTapGoBack:)]) {
        [self.delegate timingControlViewDidTapGoBack:self];
    }
}

- (void)skipButtonTapped {
    if ([self.delegate respondsToSelector:@selector(timingControlViewDidTapSkip:)]) {
        [self.delegate timingControlViewDidTapSkip:self];
    }
}

- (void)rewindButtonTapped {
    if ([self.delegate respondsToSelector:@selector(timingControlView:didSeekBySeconds:)]) {
        [self.delegate timingControlView:self didSeekBySeconds:-5.0];
    }
}

- (void)forwardButtonTapped {
    if ([self.delegate respondsToSelector:@selector(timingControlView:didSeekBySeconds:)]) {
        [self.delegate timingControlView:self didSeekBySeconds:5.0];
    }
}

- (void)sliderTouchDown {
    self.isSliderTracking = YES;
}

- (void)sliderTouchUp {
    self.isSliderTracking = NO;
    
    if ([self.delegate respondsToSelector:@selector(timingControlView:didSeekToProgress:)]) {
        [self.delegate timingControlView:self didSeekToProgress:self.progressSlider.value];
    }
}

- (void)sliderValueChanged:(UISlider *)slider {
    // 拖动时实时更新时间显示（但不发送代理）
    // 实际 seek 在 touchUp 时执行
}

#pragma mark - Waveform

- (void)loadWaveformFromFile:(NSString *)filePath {
    [self.waveformView loadWaveformFromFile:filePath];
}

- (void)updateWaveformMarkers:(NSArray<NSNumber *> *)timestamps {
    self.waveformView.timeMarkers = timestamps;
}

#pragma mark - AudioWaveformViewDelegate

- (void)waveformView:(AudioWaveformView *)view didTapAtTime:(NSTimeInterval)time {
    if ([self.delegate respondsToSelector:@selector(timingControlView:didSeekToTime:)]) {
        [self.delegate timingControlView:self didSeekToTime:time];
    }
}

- (void)waveformView:(AudioWaveformView *)view didDragToTime:(NSTimeInterval)time {
    if ([self.delegate respondsToSelector:@selector(timingControlView:didSeekToTime:)]) {
        [self.delegate timingControlView:self didSeekToTime:time];
    }
}

#pragma mark - Helpers

- (NSString *)formatTime:(NSTimeInterval)time {
    int minutes = (int)(time / 60);
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
}

@end

