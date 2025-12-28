//
//  AudioProgressView.m
//  AudioSampleBuffer
//
//  播放进度条组件 - 支持拖拽跳转播放（美化版）
//

#import "AudioProgressView.h"

@interface AudioProgressView ()

/// 进度条背景轨道
@property (nonatomic, strong) UIView *trackView;

/// 进度条填充（渐变效果）
@property (nonatomic, strong) CAGradientLayer *progressGradient;

/// 进度条容器
@property (nonatomic, strong) UIView *progressContainer;

/// 滑块视图
@property (nonatomic, strong) UIView *thumbView;

/// 滑块内部发光效果
@property (nonatomic, strong) UIView *thumbGlowView;

/// 当前时间标签
@property (nonatomic, strong) UILabel *currentTimeLabel;

/// 总时长标签
@property (nonatomic, strong) UILabel *durationLabel;

/// 是否正在拖拽
@property (nonatomic, assign, readwrite) BOOL isSeeking;

/// 拖拽手势
@property (nonatomic, strong) UIPanGestureRecognizer *panGesture;

/// 点击手势
@property (nonatomic, strong) UITapGestureRecognizer *tapGesture;

/// 进度条区域
@property (nonatomic, assign) CGRect progressBarFrame;

/// 波纹动画层
@property (nonatomic, strong) CAShapeLayer *waveLayer;

@end

@implementation AudioProgressView

#pragma mark - 初始化

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupDefaultValues];
        [self setupUI];
        [self setupGestures];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (self) {
        [self setupDefaultValues];
        [self setupUI];
        [self setupGestures];
    }
    return self;
}

- (void)setupDefaultValues {
    _currentTime = 0;
    _duration = 0;
    _isPlaying = NO;
    _isSeeking = NO;
    
    // 默认颜色 - 霓虹风格
    _progressColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    _trackColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    _thumbColor = [UIColor whiteColor];
    _timeTextColor = [UIColor colorWithWhite:0.9 alpha:1.0];
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    
    // 当前时间标签
    self.currentTimeLabel = [[UILabel alloc] init];
    self.currentTimeLabel.text = @"0:00";
    self.currentTimeLabel.textColor = self.timeTextColor;
    self.currentTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightSemibold];
    self.currentTimeLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:self.currentTimeLabel];
    
    // 总时长标签
    self.durationLabel = [[UILabel alloc] init];
    self.durationLabel.text = @"0:00";
    self.durationLabel.textColor = [UIColor colorWithWhite:0.6 alpha:1.0];
    self.durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightMedium];
    self.durationLabel.textAlignment = NSTextAlignmentRight;
    [self addSubview:self.durationLabel];
    
    // 进度条背景轨道
    self.trackView = [[UIView alloc] init];
    self.trackView.backgroundColor = self.trackColor;
    self.trackView.layer.cornerRadius = 4;
    self.trackView.clipsToBounds = YES;
    
    // 添加轨道内阴影效果
    self.trackView.layer.borderWidth = 0.5;
    self.trackView.layer.borderColor = [UIColor colorWithWhite:0.3 alpha:0.5].CGColor;
    [self addSubview:self.trackView];
    
    // 进度条容器（用于放置渐变）
    self.progressContainer = [[UIView alloc] init];
    self.progressContainer.clipsToBounds = YES;
    self.progressContainer.layer.cornerRadius = 4;
    [self.trackView addSubview:self.progressContainer];
    
    // 进度条渐变
    self.progressGradient = [CAGradientLayer layer];
    self.progressGradient.colors = @[
        (id)[UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.0 green:0.9 blue:0.8 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.4 green:1.0 blue:0.6 alpha:1.0].CGColor
    ];
    self.progressGradient.startPoint = CGPointMake(0, 0.5);
    self.progressGradient.endPoint = CGPointMake(1, 0.5);
    self.progressGradient.cornerRadius = 4;
    [self.progressContainer.layer addSublayer:self.progressGradient];
    
    // 滑块发光效果
    self.thumbGlowView = [[UIView alloc] init];
    self.thumbGlowView.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.4];
    self.thumbGlowView.layer.cornerRadius = 12;
    [self addSubview:self.thumbGlowView];
    
    // 滑块
    self.thumbView = [[UIView alloc] init];
    self.thumbView.backgroundColor = self.thumbColor;
    self.thumbView.layer.cornerRadius = 8;
    
    // 滑块阴影
    self.thumbView.layer.shadowColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor;
    self.thumbView.layer.shadowOffset = CGSizeMake(0, 0);
    self.thumbView.layer.shadowOpacity = 0.8;
    self.thumbView.layer.shadowRadius = 6;
    
    // 滑块边框
    self.thumbView.layer.borderWidth = 2;
    self.thumbView.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:0.8].CGColor;
    [self addSubview:self.thumbView];
}

- (void)setupGestures {
    // 拖拽手势 - 添加到整个视图以增大触摸区域
    self.panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePanGesture:)];
    [self addGestureRecognizer:self.panGesture];
    
    // 点击手势
    self.tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTapGesture:)];
    [self addGestureRecognizer:self.tapGesture];
    
    self.userInteractionEnabled = YES;
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height;
    
    CGFloat padding = 16;
    CGFloat timeLabelWidth = 50;
    CGFloat trackHeight = 8;
    CGFloat thumbSize = 16;
    CGFloat glowSize = 24;
    
    // 时间标签布局 - 放在进度条上方
    CGFloat labelY = 4;
    self.currentTimeLabel.frame = CGRectMake(padding, labelY, timeLabelWidth, 18);
    self.durationLabel.frame = CGRectMake(width - padding - timeLabelWidth, labelY, timeLabelWidth, 18);
    
    // 进度条轨道布局 - 放在时间标签下方
    CGFloat trackY = labelY + 22;
    CGFloat trackWidth = width - 2 * padding;
    self.trackView.frame = CGRectMake(padding, trackY, trackWidth, trackHeight);
    self.progressBarFrame = self.trackView.frame;
    
    // 进度条容器
    self.progressContainer.frame = CGRectMake(0, 0, 0, trackHeight);
    
    // 渐变层 - 设置为轨道的完整宽度
    self.progressGradient.frame = CGRectMake(0, 0, trackWidth, trackHeight);
    
    // 更新进度条和滑块位置
    [self updateProgressUI];
}

- (void)updateProgressUI {
    CGFloat progress = 0;
    if (self.duration > 0) {
        progress = self.currentTime / self.duration;
        progress = fmin(fmax(progress, 0), 1);  // 限制在 0-1 之间
    }
    
    CGFloat trackWidth = self.trackView.bounds.size.width;
    CGFloat trackHeight = self.trackView.bounds.size.height;
    
    // 更新进度条容器宽度（渐变通过 mask 效果显示）
    self.progressContainer.frame = CGRectMake(0, 0, trackWidth * progress, trackHeight);
    
    // 更新滑块位置
    CGFloat thumbSize = 16;
    CGFloat glowSize = 24;
    CGFloat thumbX = self.trackView.frame.origin.x + trackWidth * progress - thumbSize / 2;
    CGFloat thumbY = self.trackView.frame.origin.y + (trackHeight - thumbSize) / 2;
    self.thumbView.frame = CGRectMake(thumbX, thumbY, thumbSize, thumbSize);
    
    // 更新发光效果位置
    CGFloat glowX = thumbX - (glowSize - thumbSize) / 2;
    CGFloat glowY = thumbY - (glowSize - thumbSize) / 2;
    self.thumbGlowView.frame = CGRectMake(glowX, glowY, glowSize, glowSize);
}

#pragma mark - 公开方法

- (void)updateCurrentTime:(NSTimeInterval)currentTime {
    // 如果正在拖拽，不更新时间
    if (self.isSeeking) {
        return;
    }
    
    self.currentTime = currentTime;
    self.currentTimeLabel.text = [self formatTime:currentTime];
    [self updateProgressUI];
}

- (void)updateDuration:(NSTimeInterval)duration {
    self.duration = duration;
    self.durationLabel.text = [self formatTime:duration];
    [self updateProgressUI];
}

- (void)reset {
    self.currentTime = 0;
    self.duration = 0;
    self.isPlaying = NO;
    self.isSeeking = NO;
    self.currentTimeLabel.text = @"0:00";
    self.durationLabel.text = @"0:00";
    [self updateProgressUI];
}

#pragma mark - Setter

- (void)setProgressColor:(UIColor *)progressColor {
    _progressColor = progressColor;
    // 更新渐变颜色
    CGFloat r, g, b, a;
    [progressColor getRed:&r green:&g blue:&b alpha:&a];
    self.progressGradient.colors = @[
        (id)[UIColor colorWithRed:r*0.7 green:g*0.7 blue:b alpha:1.0].CGColor,
        (id)progressColor.CGColor,
        (id)[UIColor colorWithRed:r green:g*1.2 blue:b*0.8 alpha:1.0].CGColor
    ];
}

- (void)setTrackColor:(UIColor *)trackColor {
    _trackColor = trackColor;
    self.trackView.backgroundColor = trackColor;
}

- (void)setThumbColor:(UIColor *)thumbColor {
    _thumbColor = thumbColor;
    self.thumbView.backgroundColor = thumbColor;
}

- (void)setTimeTextColor:(UIColor *)timeTextColor {
    _timeTextColor = timeTextColor;
    self.currentTimeLabel.textColor = timeTextColor;
    self.durationLabel.textColor = [timeTextColor colorWithAlphaComponent:0.6];
}

#pragma mark - 手势处理

- (void)handlePanGesture:(UIPanGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    
    switch (gesture.state) {
        case UIGestureRecognizerStateBegan: {
            self.isSeeking = YES;
            
            // 放大滑块，提供视觉反馈
            [UIView animateWithDuration:0.15 animations:^{
                self.thumbView.transform = CGAffineTransformMakeScale(1.4, 1.4);
                self.thumbGlowView.transform = CGAffineTransformMakeScale(1.5, 1.5);
                self.thumbGlowView.alpha = 1.0;
                self.thumbView.layer.shadowOpacity = 1.0;
                self.thumbView.layer.shadowRadius = 10;
            }];
            
            if ([self.delegate respondsToSelector:@selector(audioProgressViewDidBeginSeeking:)]) {
                [self.delegate audioProgressViewDidBeginSeeking:self];
            }
            break;
        }
            
        case UIGestureRecognizerStateChanged: {
            [self seekToLocationX:location.x];
            break;
        }
            
        case UIGestureRecognizerStateEnded:
        case UIGestureRecognizerStateCancelled: {
            // 恢复滑块大小
            [UIView animateWithDuration:0.2 animations:^{
                self.thumbView.transform = CGAffineTransformIdentity;
                self.thumbGlowView.transform = CGAffineTransformIdentity;
                self.thumbGlowView.alpha = 0.4;
                self.thumbView.layer.shadowOpacity = 0.8;
                self.thumbView.layer.shadowRadius = 6;
            }];
            
            // 计算最终的跳转时间
            NSTimeInterval seekTime = [self timeForLocationX:location.x];
            
            self.isSeeking = NO;
            
            if ([self.delegate respondsToSelector:@selector(audioProgressView:didSeekToTime:)]) {
                [self.delegate audioProgressView:self didSeekToTime:seekTime];
            }
            
            if ([self.delegate respondsToSelector:@selector(audioProgressViewDidEndSeeking:)]) {
                [self.delegate audioProgressViewDidEndSeeking:self];
            }
            
            break;
        }
            
        default:
            break;
    }
}

- (void)handleTapGesture:(UITapGestureRecognizer *)gesture {
    CGPoint location = [gesture locationInView:self];
    NSTimeInterval seekTime = [self timeForLocationX:location.x];
    
    // 点击动画反馈
    [UIView animateWithDuration:0.1 animations:^{
        self.thumbView.transform = CGAffineTransformMakeScale(1.3, 1.3);
        self.thumbGlowView.alpha = 1.0;
    } completion:^(BOOL finished) {
        [UIView animateWithDuration:0.15 animations:^{
            self.thumbView.transform = CGAffineTransformIdentity;
            self.thumbGlowView.alpha = 0.4;
        }];
    }];
    
    // 更新UI
    self.currentTime = seekTime;
    self.currentTimeLabel.text = [self formatTime:seekTime];
    [self updateProgressUI];
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(audioProgressView:didSeekToTime:)]) {
        [self.delegate audioProgressView:self didSeekToTime:seekTime];
    }
}

- (void)seekToLocationX:(CGFloat)locationX {
    CGFloat trackMinX = self.progressBarFrame.origin.x;
    CGFloat trackMaxX = trackMinX + self.progressBarFrame.size.width;
    
    // 限制在轨道范围内
    locationX = fmax(trackMinX, fmin(locationX, trackMaxX));
    
    // 计算进度
    CGFloat progress = (locationX - trackMinX) / self.progressBarFrame.size.width;
    progress = fmax(0, fmin(1, progress));
    
    // 更新时间
    NSTimeInterval time = progress * self.duration;
    self.currentTime = time;
    self.currentTimeLabel.text = [self formatTime:time];
    
    // 更新进度条
    [self updateProgressUI];
}

- (NSTimeInterval)timeForLocationX:(CGFloat)locationX {
    CGFloat trackMinX = self.progressBarFrame.origin.x;
    CGFloat trackWidth = self.progressBarFrame.size.width;
    
    // 计算进度
    CGFloat progress = (locationX - trackMinX) / trackWidth;
    progress = fmax(0, fmin(1, progress));
    
    return progress * self.duration;
}

#pragma mark - 辅助方法

- (NSString *)formatTime:(NSTimeInterval)time {
    if (isnan(time) || time < 0) {
        time = 0;
    }
    
    int totalSeconds = (int)time;
    int minutes = totalSeconds / 60;
    int seconds = totalSeconds % 60;
    
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

@end
