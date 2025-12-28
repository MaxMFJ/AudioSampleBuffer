//
//  AudioWaveformView.m
//  AudioSampleBuffer
//
//  音频波形显示视图 - 用于辅助歌词打轴定位
//

#import "AudioWaveformView.h"

@interface AudioWaveformView ()

/// 波形数据（归一化的采样值 0-1）
@property (nonatomic, strong) NSArray<NSNumber *> *waveformData;

/// 波形层
@property (nonatomic, strong) CAShapeLayer *waveformLayer;

/// 已播放波形层
@property (nonatomic, strong) CAShapeLayer *playedWaveformLayer;

/// 播放头指示线
@property (nonatomic, strong) CALayer *playheadLayer;

/// 时间标记层数组
@property (nonatomic, strong) NSMutableArray<CALayer *> *markerLayers;

/// 时间标签
@property (nonatomic, strong) UILabel *currentTimeLabel;

/// 总时长标签
@property (nonatomic, strong) UILabel *durationLabel;

/// 加载指示器
@property (nonatomic, strong) UIActivityIndicatorView *loadingIndicator;

/// 音频时长
@property (nonatomic, assign, readwrite) NSTimeInterval duration;

/// 是否正在加载
@property (nonatomic, assign, readwrite) BOOL isLoading;

/// 缩放比例
@property (nonatomic, assign) CGFloat zoomScale;

@end

@implementation AudioWaveformView

#pragma mark - Initialization

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self commonInit];
    }
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    if (self = [super initWithCoder:coder]) {
        [self commonInit];
    }
    return self;
}

- (void)commonInit {
    self.backgroundColor = [UIColor colorWithWhite:0.1 alpha:1.0];
    self.layer.cornerRadius = 8;
    self.clipsToBounds = YES;
    
    // 默认颜色
    _waveformColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:1.0];
    _playheadColor = [UIColor whiteColor];
    _playedColor = [UIColor colorWithRed:0.2 green:0.8 blue:0.4 alpha:1.0];
    _unplayedColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:0.6];
    _markerColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.2 alpha:1.0];
    
    _zoomScale = 1.0;
    _visibleDuration = 0; // 0 表示显示整个音频
    _autoScrollEnabled = YES;
    _markerLayers = [NSMutableArray array];
    
    [self setupLayers];
    [self setupLabels];
    [self setupGestures];
}

- (void)setupLayers {
    // 波形层（未播放部分）
    _waveformLayer = [CAShapeLayer layer];
    _waveformLayer.fillColor = self.unplayedColor.CGColor;
    _waveformLayer.strokeColor = nil;
    [self.layer addSublayer:_waveformLayer];
    
    // 已播放波形层
    _playedWaveformLayer = [CAShapeLayer layer];
    _playedWaveformLayer.fillColor = self.playedColor.CGColor;
    _playedWaveformLayer.strokeColor = nil;
    [self.layer addSublayer:_playedWaveformLayer];
    
    // 播放头
    _playheadLayer = [CALayer layer];
    _playheadLayer.backgroundColor = self.playheadColor.CGColor;
    _playheadLayer.cornerRadius = 1;
    [self.layer addSublayer:_playheadLayer];
    
    // 加载指示器
    _loadingIndicator = [[UIActivityIndicatorView alloc] initWithActivityIndicatorStyle:UIActivityIndicatorViewStyleMedium];
    _loadingIndicator.color = [UIColor whiteColor];
    _loadingIndicator.hidesWhenStopped = YES;
    _loadingIndicator.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_loadingIndicator];
    
    [NSLayoutConstraint activateConstraints:@[
        [_loadingIndicator.centerXAnchor constraintEqualToAnchor:self.centerXAnchor],
        [_loadingIndicator.centerYAnchor constraintEqualToAnchor:self.centerYAnchor],
    ]];
}

- (void)setupLabels {
    // 当前时间标签
    _currentTimeLabel = [[UILabel alloc] init];
    _currentTimeLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
    _currentTimeLabel.textColor = [UIColor whiteColor];
    _currentTimeLabel.text = @"00:00";
    _currentTimeLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_currentTimeLabel];
    
    // 总时长标签
    _durationLabel = [[UILabel alloc] init];
    _durationLabel.font = [UIFont monospacedDigitSystemFontOfSize:10 weight:UIFontWeightMedium];
    _durationLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    _durationLabel.textAlignment = NSTextAlignmentRight;
    _durationLabel.text = @"00:00";
    _durationLabel.translatesAutoresizingMaskIntoConstraints = NO;
    [self addSubview:_durationLabel];
    
    [NSLayoutConstraint activateConstraints:@[
        [_currentTimeLabel.leadingAnchor constraintEqualToAnchor:self.leadingAnchor constant:8],
        [_currentTimeLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
        
        [_durationLabel.trailingAnchor constraintEqualToAnchor:self.trailingAnchor constant:-8],
        [_durationLabel.bottomAnchor constraintEqualToAnchor:self.bottomAnchor constant:-4],
    ]];
}

- (void)setupGestures {
    // 点击手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(handleTap:)];
    [self addGestureRecognizer:tapGesture];
    
    // 拖动手势
    UIPanGestureRecognizer *panGesture = [[UIPanGestureRecognizer alloc] initWithTarget:self action:@selector(handlePan:)];
    [self addGestureRecognizer:panGesture];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    
    _waveformLayer.frame = self.bounds;
    _playedWaveformLayer.frame = self.bounds;
    
    [self updateWaveformPath];
    [self updatePlayhead];
    [self updateMarkers];
}

#pragma mark - Loading

- (void)loadWaveformFromFile:(NSString *)filePath {
    NSURL *url = [NSURL fileURLWithPath:filePath];
    [self loadWaveformFromURL:url];
}

- (void)loadWaveformFromURL:(NSURL *)url {
    AVAsset *asset = [AVAsset assetWithURL:url];
    [self loadWaveformFromAsset:asset];
}

- (void)loadWaveformFromAsset:(AVAsset *)asset {
    self.isLoading = YES;
    [self.loadingIndicator startAnimating];
    
    __weak typeof(self) weakSelf = self;
    
    [asset loadValuesAsynchronouslyForKeys:@[@"duration", @"tracks"] completionHandler:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            __strong typeof(weakSelf) strongSelf = weakSelf;
            if (!strongSelf) return;
            
            NSError *error = nil;
            AVKeyValueStatus status = [asset statusOfValueForKey:@"duration" error:&error];
            
            if (status == AVKeyValueStatusLoaded) {
                strongSelf.duration = CMTimeGetSeconds(asset.duration);
                strongSelf.durationLabel.text = [strongSelf formatTime:strongSelf.duration];
                
                // 提取波形数据
                [strongSelf extractWaveformFromAsset:asset];
            } else {
                strongSelf.isLoading = NO;
                [strongSelf.loadingIndicator stopAnimating];
                NSLog(@"加载音频失败: %@", error);
            }
        });
    }];
}

- (void)extractWaveformFromAsset:(AVAsset *)asset {
    // 获取音频轨道
    NSArray *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    
    if (audioTracks.count == 0) {
        self.isLoading = NO;
        [self.loadingIndicator stopAnimating];
        NSLog(@"没有找到音频轨道");
        return;
    }
    
    AVAssetTrack *audioTrack = audioTracks.firstObject;
    
    // 配置读取器
    NSError *error = nil;
    AVAssetReader *reader = [[AVAssetReader alloc] initWithAsset:asset error:&error];
    
    if (error) {
        self.isLoading = NO;
        [self.loadingIndicator stopAnimating];
        NSLog(@"创建 AVAssetReader 失败: %@", error);
        return;
    }
    
    // 配置输出格式（单声道 PCM）
    NSDictionary *outputSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
        AVNumberOfChannelsKey: @1,
        AVSampleRateKey: @44100
    };
    
    AVAssetReaderTrackOutput *output = [[AVAssetReaderTrackOutput alloc] initWithTrack:audioTrack
                                                                        outputSettings:outputSettings];
    
    // 🔧 检查是否可以添加 output
    if (![reader canAddOutput:output]) {
        self.isLoading = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
        });
        NSLog(@"无法添加 AVAssetReaderTrackOutput");
        return;
    }
    
    [reader addOutput:output];
    
    // 开始读取
    if (![reader startReading]) {
        self.isLoading = NO;
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.loadingIndicator stopAnimating];
        });
        NSLog(@"开始读取失败: %@", reader.error);
        return;
    }
    
    // 在后台线程处理波形数据
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSMutableArray<NSNumber *> *samples = [NSMutableArray array];
        
        // 目标采样数（波形视图宽度相关）
        NSInteger targetSampleCount = 200;
        NSMutableArray<NSNumber *> *tempSamples = [NSMutableArray array];
        
        // 🔧 确保 reader 状态正确
        if (reader.status != AVAssetReaderStatusReading) {
            NSLog(@"AVAssetReader 状态异常: %ld", (long)reader.status);
            dispatch_async(dispatch_get_main_queue(), ^{
                self.isLoading = NO;
                [self.loadingIndicator stopAnimating];
            });
            return;
        }
        
        // 读取所有采样
        CMSampleBufferRef sampleBuffer;
        while (reader.status == AVAssetReaderStatusReading && 
               (sampleBuffer = [output copyNextSampleBuffer])) {
            CMBlockBufferRef blockBuffer = CMSampleBufferGetDataBuffer(sampleBuffer);
            
            size_t length;
            char *data;
            CMBlockBufferGetDataPointer(blockBuffer, 0, NULL, &length, &data);
            
            // 处理 16-bit PCM 数据
            int16_t *samples16 = (int16_t *)data;
            NSInteger sampleCount = length / sizeof(int16_t);
            
            for (NSInteger i = 0; i < sampleCount; i += 100) { // 降采样
                float sample = fabsf((float)samples16[i] / 32768.0f);
                [tempSamples addObject:@(sample)];
            }
            
            CFRelease(sampleBuffer);
        }
        
        // 降采样到目标数量
        if (tempSamples.count > 0) {
            NSInteger step = MAX(1, tempSamples.count / targetSampleCount);
            
            for (NSInteger i = 0; i < tempSamples.count; i += step) {
                // 取区间内的最大值
                float maxSample = 0;
                for (NSInteger j = i; j < MIN(i + step, tempSamples.count); j++) {
                    float sample = [tempSamples[j] floatValue];
                    if (sample > maxSample) {
                        maxSample = sample;
                    }
                }
                [samples addObject:@(maxSample)];
            }
        }
        
        dispatch_async(dispatch_get_main_queue(), ^{
            self.waveformData = samples;
            self.isLoading = NO;
            [self.loadingIndicator stopAnimating];
            [self updateWaveformPath];
        });
    });
}

- (void)clearWaveform {
    self.waveformData = nil;
    self.duration = 0;
    self.currentTime = 0;
    _waveformLayer.path = nil;
    _playedWaveformLayer.path = nil;
}

#pragma mark - Drawing

- (void)updateWaveformPath {
    if (!self.waveformData || self.waveformData.count == 0) {
        return;
    }
    
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height - 20; // 留空间给时间标签
    CGFloat midY = height / 2 + 5;
    
    CGFloat barWidth = width / self.waveformData.count;
    CGFloat barSpacing = 1.0;
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    for (NSInteger i = 0; i < self.waveformData.count; i++) {
        CGFloat sample = [self.waveformData[i] floatValue];
        CGFloat barHeight = sample * (height * 0.8);
        
        CGFloat x = i * barWidth;
        CGFloat y = midY - barHeight / 2;
        
        CGRect barRect = CGRectMake(x + barSpacing / 2, y, MAX(1, barWidth - barSpacing), barHeight);
        UIBezierPath *barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:barWidth / 4];
        [path appendPath:barPath];
    }
    
    _waveformLayer.path = path.CGPath;
    
    // 更新已播放部分
    [self updatePlayedWaveform];
}

- (void)updatePlayedWaveform {
    if (!self.waveformData || self.waveformData.count == 0 || self.duration == 0) {
        _playedWaveformLayer.path = nil;
        return;
    }
    
    CGFloat progress = self.currentTime / self.duration;
    CGFloat width = self.bounds.size.width;
    CGFloat height = self.bounds.size.height - 20;
    CGFloat midY = height / 2 + 5;
    
    CGFloat barWidth = width / self.waveformData.count;
    CGFloat barSpacing = 1.0;
    NSInteger playedCount = progress * self.waveformData.count;
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    for (NSInteger i = 0; i < playedCount && i < self.waveformData.count; i++) {
        CGFloat sample = [self.waveformData[i] floatValue];
        CGFloat barHeight = sample * (height * 0.8);
        
        CGFloat x = i * barWidth;
        CGFloat y = midY - barHeight / 2;
        
        CGRect barRect = CGRectMake(x + barSpacing / 2, y, MAX(1, barWidth - barSpacing), barHeight);
        UIBezierPath *barPath = [UIBezierPath bezierPathWithRoundedRect:barRect cornerRadius:barWidth / 4];
        [path appendPath:barPath];
    }
    
    _playedWaveformLayer.path = path.CGPath;
}

- (void)updatePlayhead {
    if (self.duration == 0) {
        _playheadLayer.hidden = YES;
        return;
    }
    
    _playheadLayer.hidden = NO;
    
    CGFloat progress = self.currentTime / self.duration;
    CGFloat x = progress * self.bounds.size.width;
    
    _playheadLayer.frame = CGRectMake(x - 1, 5, 2, self.bounds.size.height - 25);
    
    // 更新时间标签
    _currentTimeLabel.text = [self formatTime:self.currentTime];
}

- (void)updateMarkers {
    // 清除旧标记
    for (CALayer *layer in _markerLayers) {
        [layer removeFromSuperlayer];
    }
    [_markerLayers removeAllObjects];
    
    if (!self.timeMarkers || self.duration == 0) {
        return;
    }
    
    for (NSNumber *timeNum in self.timeMarkers) {
        NSTimeInterval time = [timeNum doubleValue];
        CGFloat progress = time / self.duration;
        CGFloat x = progress * self.bounds.size.width;
        
        CALayer *markerLayer = [CALayer layer];
        markerLayer.backgroundColor = self.markerColor.CGColor;
        markerLayer.frame = CGRectMake(x - 1, 0, 2, self.bounds.size.height - 15);
        markerLayer.opacity = 0.7;
        
        [self.layer insertSublayer:markerLayer below:_playheadLayer];
        [_markerLayers addObject:markerLayer];
    }
}

#pragma mark - Public Methods

- (void)setCurrentTime:(NSTimeInterval)currentTime {
    _currentTime = currentTime;
    [self updatePlayhead];
    [self updatePlayedWaveform];
}

- (void)setCurrentTime:(NSTimeInterval)time animated:(BOOL)animated {
    if (animated) {
        [CATransaction begin];
        [CATransaction setAnimationDuration:0.1];
        self.currentTime = time;
        [CATransaction commit];
    } else {
        self.currentTime = time;
    }
}

- (void)scrollToTime:(NSTimeInterval)time animated:(BOOL)animated {
    // 对于简化版本，整个波形始终显示，无需滚动
    // 可以在需要时扩展为滚动显示
}

- (void)setZoomScale:(CGFloat)scale {
    _zoomScale = MAX(0.5, MIN(4.0, scale));
    [self setNeedsLayout];
}

- (void)setTimeMarkers:(NSArray<NSNumber *> *)timeMarkers {
    _timeMarkers = [timeMarkers copy];
    [self updateMarkers];
}

#pragma mark - Gestures

- (void)handleTap:(UITapGestureRecognizer *)gesture {
    if (self.duration == 0) return;
    
    CGPoint location = [gesture locationInView:self];
    CGFloat progress = location.x / self.bounds.size.width;
    NSTimeInterval time = progress * self.duration;
    
    if ([self.delegate respondsToSelector:@selector(waveformView:didTapAtTime:)]) {
        [self.delegate waveformView:self didTapAtTime:time];
    }
}

- (void)handlePan:(UIPanGestureRecognizer *)gesture {
    if (self.duration == 0) return;
    
    CGPoint location = [gesture locationInView:self];
    CGFloat progress = MAX(0, MIN(1, location.x / self.bounds.size.width));
    NSTimeInterval time = progress * self.duration;
    
    if ([self.delegate respondsToSelector:@selector(waveformView:didDragToTime:)]) {
        [self.delegate waveformView:self didDragToTime:time];
    }
}

#pragma mark - Helpers

- (NSString *)formatTime:(NSTimeInterval)time {
    int minutes = (int)(time / 60);
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%02d:%02d", minutes, seconds];
}

@end

