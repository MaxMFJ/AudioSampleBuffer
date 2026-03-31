//
//  RecordingPlaybackView.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import "RecordingPlaybackView.h"
#import "PCMAudioPlayer.h"
#import <AVFoundation/AVFoundation.h>

@interface RecordingPlaybackView () <PCMAudioPlayerDelegate>

// UI组件
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIProgressView *progressView;
@property (nonatomic, strong) UILabel *timeLabel;
@property (nonatomic, strong) UIButton *playPauseButton;
@property (nonatomic, strong) UIButton *rewindButton;
@property (nonatomic, strong) UIButton *forwardButton;
@property (nonatomic, strong) UILabel *fileInfoLabel;
@property (nonatomic, strong) UIButton *exportButton;
@property (nonatomic, strong) UIButton *deleteButton;
@property (nonatomic, strong) UIButton *closeButton;

// 播放器
@property (nonatomic, strong) PCMAudioPlayer *pcmPlayer;
@property (nonatomic, strong) NSTimer *updateTimer;

@end

@implementation RecordingPlaybackView

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    // 背景
    self.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    self.layer.cornerRadius = 15;
    self.layer.masksToBounds = YES;
    self.layer.borderWidth = 2;
    self.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor;
    
    // 标题
    self.titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, self.bounds.size.width - 40, 25)];
    self.titleLabel.text = @"录音回放";
    self.titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.titleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:self.titleLabel];
    
    // 关闭按钮
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(self.bounds.size.width - 40, 10, 30, 30);
    UIImage *closeIcon = nil;
    if (@available(iOS 13.0, *)) {
        closeIcon = [UIImage systemImageNamed:@"xmark"];
    }
    [self.closeButton setImage:closeIcon forState:UIControlStateNormal];
    [self.closeButton setTitle:@"" forState:UIControlStateNormal];
    self.closeButton.tintColor = [UIColor whiteColor];
    self.closeButton.titleLabel.font = [UIFont systemFontOfSize:24];
    [self.closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.closeButton];
    
    // 进度条
    self.progressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.progressView.frame = CGRectMake(20, 55, self.bounds.size.width - 40, 10);
    self.progressView.progressTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.progressView.trackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.progressView.progress = 0.0;
    [self addSubview:self.progressView];
    
    // 时间标签
    self.timeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 75, self.bounds.size.width - 40, 20)];
    self.timeLabel.textAlignment = NSTextAlignmentCenter;
    self.timeLabel.font = [UIFont systemFontOfSize:14];
    self.timeLabel.textColor = [UIColor whiteColor];
    self.timeLabel.text = @"00:00 / 00:00";
    [self addSubview:self.timeLabel];
    
    // 播放控制按钮
    CGFloat buttonY = 110;
    CGFloat centerX = self.bounds.size.width / 2;
    
    // 快退按钮
    self.rewindButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.rewindButton.frame = CGRectMake(centerX - 90, buttonY, 50, 50);
    if (@available(iOS 13.0, *)) {
        [self.rewindButton setImage:[UIImage systemImageNamed:@"gobackward"] forState:UIControlStateNormal];
    }
    [self.rewindButton setTitle:@"" forState:UIControlStateNormal];
    self.rewindButton.titleLabel.font = [UIFont systemFontOfSize:30];
    self.rewindButton.tintColor = [UIColor whiteColor];
    [self.rewindButton addTarget:self action:@selector(rewindButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.rewindButton];
    
    // 播放/暂停按钮
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.playPauseButton.frame = CGRectMake(centerX - 25, buttonY, 50, 50);
    if (@available(iOS 13.0, *)) {
        [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    }
    [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
    self.playPauseButton.titleLabel.font = [UIFont systemFontOfSize:35];
    self.playPauseButton.tintColor = [UIColor whiteColor];
    [self.playPauseButton addTarget:self action:@selector(playPauseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.playPauseButton];
    
    // 快进按钮
    self.forwardButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.forwardButton.frame = CGRectMake(centerX + 40, buttonY, 50, 50);
    if (@available(iOS 13.0, *)) {
        [self.forwardButton setImage:[UIImage systemImageNamed:@"goforward"] forState:UIControlStateNormal];
    }
    [self.forwardButton setTitle:@"" forState:UIControlStateNormal];
    self.forwardButton.titleLabel.font = [UIFont systemFontOfSize:30];
    self.forwardButton.tintColor = [UIColor whiteColor];
    [self.forwardButton addTarget:self action:@selector(forwardButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.forwardButton];
    
    // 文件信息标签
    self.fileInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 175, self.bounds.size.width - 40, 40)];
    self.fileInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.fileInfoLabel.font = [UIFont systemFontOfSize:12];
    self.fileInfoLabel.numberOfLines = 2;
    self.fileInfoLabel.textColor = [UIColor grayColor];
    [self addSubview:self.fileInfoLabel];
    
    // 底部按钮
    CGFloat bottomButtonY = 230;
    CGFloat buttonWidth = (self.bounds.size.width - 60) / 2;
    
    // 导出按钮
    self.exportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.exportButton.frame = CGRectMake(20, bottomButtonY, buttonWidth, 40);
    [self.exportButton setTitle:@"导出" forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        [self.exportButton setImage:[UIImage systemImageNamed:@"square.and.arrow.up"] forState:UIControlStateNormal];
    }
    [self.exportButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.exportButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.exportButton.layer.cornerRadius = 8;
    self.exportButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.exportButton addTarget:self action:@selector(exportButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.exportButton];
    
    // 删除按钮
    self.deleteButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.deleteButton.frame = CGRectMake(self.bounds.size.width - 20 - buttonWidth, bottomButtonY, buttonWidth, 40);
    [self.deleteButton setTitle:@"删除" forState:UIControlStateNormal];
    if (@available(iOS 13.0, *)) {
        [self.deleteButton setImage:[UIImage systemImageNamed:@"trash.fill"] forState:UIControlStateNormal];
    }
    [self.deleteButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.deleteButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    self.deleteButton.layer.cornerRadius = 8;
    self.deleteButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.deleteButton addTarget:self action:@selector(deleteButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:self.deleteButton];
}

#pragma mark - Setters

- (void)setFilePath:(NSString *)filePath {
    _filePath = filePath;
    
    if (filePath) {
        [self loadAudioFile];
        [self updateFileInfo];
    }
}

#pragma mark - 音频加载和播放

- (void)loadAudioFile {
    // 加载PCM文件
    NSLog(@"📂 加载PCM文件: %@", self.filePath);
    
    // 检查文件是否存在
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.filePath]) {
        NSLog(@"❌ 文件不存在: %@", self.filePath);
        self.titleLabel.text = @"❌ 文件不存在";
        return;
    }
    
    // 创建PCM播放器
    self.pcmPlayer = [[PCMAudioPlayer alloc] init];
    self.pcmPlayer.delegate = self;
    
    // 🔧 关键修复：从文件名中提取采样率，避免播放速度错误
    double sampleRate = [self extractSampleRateFromFileName:self.filePath];
    
    NSLog(@"🎵 使用采样率加载PCM: %.0f Hz (从文件名提取)", sampleRate);
    
    // 加载PCM文件（使用录音时的参数：提取的采样率, 单声道, 16bit）
    BOOL success = [self.pcmPlayer loadPCMFile:self.filePath
                                    sampleRate:sampleRate
                                      channels:1
                                 bitsPerSample:16];
    
    if (success) {
        NSLog(@"✅ PCM文件加载成功，可以播放");
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
        
        // 更新时间显示
        NSString *durationStr = [self formatTime:self.pcmPlayer.duration];
        self.timeLabel.text = [NSString stringWithFormat:@"00:00 / %@", durationStr];
    } else {
        NSLog(@"❌ PCM文件加载失败");
        self.titleLabel.text = @"❌ 加载失败";
    }
}

// 🔧 从文件名中提取采样率（格式：xxx_44100Hz.pcm 或 xxx_48000Hz.pcm）
- (double)extractSampleRateFromFileName:(NSString *)filePath {
    NSString *fileName = [filePath lastPathComponent];
    
    // 使用正则表达式提取采样率：匹配 "数字+Hz" 模式
    NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"(\\d+)Hz"
                                                                           options:0
                                                                             error:nil];
    NSTextCheckingResult *match = [regex firstMatchInString:fileName
                                                    options:0
                                                      range:NSMakeRange(0, fileName.length)];
    
    if (match && match.numberOfRanges >= 2) {
        NSRange sampleRateRange = [match rangeAtIndex:1];
        NSString *sampleRateStr = [fileName substringWithRange:sampleRateRange];
        double extractedSampleRate = [sampleRateStr doubleValue];
        
        NSLog(@"✅ 从文件名提取到采样率: %.0f Hz", extractedSampleRate);
        return extractedSampleRate;
    }
    
    // 如果文件名中没有采样率信息，使用系统当前采样率（向后兼容旧文件）
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    double systemSampleRate = audioSession.sampleRate;
    
    NSLog(@"⚠️ 文件名中未找到采样率信息，使用系统采样率: %.0f Hz", systemSampleRate);
    return systemSampleRate;
}

- (void)updateFileInfo {
    if (!self.filePath) return;
    
    // 获取文件信息
    NSFileManager *fileManager = [NSFileManager defaultManager];
    NSDictionary *attributes = [fileManager attributesOfItemAtPath:self.filePath error:nil];
    unsigned long long fileSize = [attributes fileSize];
    
    NSString *fileName = [self.filePath lastPathComponent];
    NSString *fileSizeStr = [self formatFileSize:fileSize];
    
    self.fileInfoLabel.text = [NSString stringWithFormat:@"%@\n%@ | PCM 格式", fileName, fileSizeStr];
}

#pragma mark - 按钮动作

- (void)playPauseButtonTapped {
    if (!self.pcmPlayer) {
        [self showAlertWithTitle:@"错误" message:@"播放器未初始化"];
        return;
    }
    
    if (self.pcmPlayer.isPlaying) {
        // 暂停
        [self.pcmPlayer pause];
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
        NSLog(@"⏸️ 暂停播放");
    } else {
        // 播放
        [self.pcmPlayer play];
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"pause.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
        NSLog(@"▶️ 开始播放");
    }
}

- (void)rewindButtonTapped {
    if (self.pcmPlayer) {
        NSTimeInterval newTime = MAX(0, self.pcmPlayer.currentTime - 5.0);
        [self.pcmPlayer seekToTime:newTime];
        NSLog(@"⏪ 快退 5 秒");
    }
}

- (void)forwardButtonTapped {
    if (self.pcmPlayer) {
        NSTimeInterval newTime = MIN(self.pcmPlayer.duration, self.pcmPlayer.currentTime + 5.0);
        [self.pcmPlayer seekToTime:newTime];
        NSLog(@"⏩ 快进 5 秒");
    }
}

- (void)exportButtonTapped {
    if (!self.filePath) return;
    
    NSLog(@"📤 导出文件: %@", self.filePath);
    
    // 获取父视图控制器
    UIViewController *parentVC = [self parentViewController];
    if (parentVC) {
        NSURL *fileURL = [NSURL fileURLWithPath:self.filePath];
        
        UIActivityViewController *activityVC = [[UIActivityViewController alloc] initWithActivityItems:@[fileURL] 
                                                                                 applicationActivities:nil];
        
        // iPad支持
        if ([activityVC respondsToSelector:@selector(popoverPresentationController)]) {
            activityVC.popoverPresentationController.sourceView = self;
            activityVC.popoverPresentationController.sourceRect = self.exportButton.frame;
        }
        
        [parentVC presentViewController:activityVC animated:YES completion:^{
            NSLog(@"📤 导出对话框已显示");
        }];
        
        if (self.onExport) {
            self.onExport(self.filePath);
        }
    }
}

- (void)deleteButtonTapped {
    // 确认删除
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"确认删除" 
                                                                   message:@"确定要删除这个录音吗？此操作无法撤销。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"删除" 
                                                           style:UIAlertActionStyleDestructive 
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self performDelete];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alert addAction:deleteAction];
    [alert addAction:cancelAction];
    
    UIViewController *parentVC = [self parentViewController];
    if (parentVC) {
        [parentVC presentViewController:alert animated:YES completion:nil];
    }
}

- (void)performDelete {
    if (!self.filePath) return;
    
    NSError *error;
    [[NSFileManager defaultManager] removeItemAtPath:self.filePath error:&error];
    
    if (error) {
        [self showAlertWithTitle:@"删除失败" message:error.localizedDescription];
    } else {
        NSLog(@"🗑️ 已删除: %@", self.filePath);
        
        if (self.onDelete) {
            self.onDelete(self.filePath);
        }
    }
}

- (void)closeButtonTapped {
    [self stopPlayback];
    
    if (self.onClose) {
        self.onClose();
    }
}

#pragma mark - 播放控制

- (void)stopPlayback {
    if (self.pcmPlayer) {
        [self.pcmPlayer stop];
        if (@available(iOS 13.0, *)) {
            [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
        }
        [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
    }
}

#pragma mark - PCMAudioPlayerDelegate

- (void)audioPlayerDidFinishPlaying {
    NSLog(@"✅ 播放完成");
    if (@available(iOS 13.0, *)) {
        [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill"] forState:UIControlStateNormal];
    }
    [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
    self.progressView.progress = 0.0;
    
    NSString *durationStr = [self formatTime:self.pcmPlayer.duration];
    self.timeLabel.text = [NSString stringWithFormat:@"00:00 / %@", durationStr];
}

- (void)audioPlayerDidUpdateProgress:(float)progress currentTime:(NSTimeInterval)currentTime {
    self.progressView.progress = progress;
    
    NSString *currentTimeStr = [self formatTime:currentTime];
    NSString *durationStr = [self formatTime:self.pcmPlayer.duration];
    self.timeLabel.text = [NSString stringWithFormat:@"%@ / %@", currentTimeStr, durationStr];
}

#pragma mark - Helper Methods

- (NSString *)formatTime:(NSTimeInterval)time {
    int minutes = (int)time / 60;
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

- (NSString *)formatFileSize:(unsigned long long)size {
    if (size < 1024) {
        return [NSString stringWithFormat:@"%llu B", size];
    } else if (size < 1024 * 1024) {
        return [NSString stringWithFormat:@"%.2f KB", size / 1024.0];
    } else {
        return [NSString stringWithFormat:@"%.2f MB", size / (1024.0 * 1024.0)];
    }
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    
    UIViewController *parentVC = [self parentViewController];
    if (parentVC) {
        [parentVC presentViewController:alert animated:YES completion:nil];
    }
}

- (UIViewController *)parentViewController {
    UIResponder *responder = self.nextResponder;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = responder.nextResponder;
    }
    return nil;
}

- (void)dealloc {
    [self stopPlayback];
    NSLog(@"🗑️ RecordingPlaybackView dealloc");
}

@end

