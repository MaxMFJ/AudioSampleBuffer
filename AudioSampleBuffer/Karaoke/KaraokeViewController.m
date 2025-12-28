//
//  KaraokeViewController.m
//  AudioSampleBuffer
//
//  Created on 2025/10/14.
//

#import "KaraokeViewController.h"
#import "AudioSpectrumPlayer.h"
#import "LyricsView.h"
#import "LRCParser.h"
#import "LyricsManager.h"
#import "KaraokeAudioEngine.h"
#import "RecordingListViewController.h"
#import "RecordingPlaybackView.h"
#import "AudioMixer.h"
#import "KaraokeRecordingConfig.h"
#import "SegmentSelectorView.h"
#import <AVFoundation/AVFoundation.h>
#import <AudioToolbox/AudioToolbox.h>

// 错误检查宏
static void CheckError(OSStatus error, const char *operation) {
    if (error == noErr) return;
    NSLog(@"❌ Error: %s (%d)", operation, (int)error);
}

@interface KaraokeViewController () <AudioSpectrumPlayerDelegate, AVAudioRecorderDelegate, KaraokeAudioEngineDelegate, LyricsViewDelegate>

// UI 组件
@property (nonatomic, strong) UILabel *songTitleLabel;
@property (nonatomic, strong) UISlider *progressSlider;  // 🆕 可拖动的进度条
@property (nonatomic, strong) UILabel *durationLabel;
@property (nonatomic, strong) UIProgressView *rmsProgressView;
@property (nonatomic, strong) UIProgressView *peakProgressView;
@property (nonatomic, strong) UIButton *startButton;
@property (nonatomic, strong) UILabel *lyricsLabel;

// 🆕 分段录音控制UI
@property (nonatomic, strong) UIButton *pauseButton;      // 暂停/恢复录音按钮
@property (nonatomic, strong) UIButton *rewindButton;     // 回退按钮
@property (nonatomic, strong) UIButton *finishButton;     // 完成录音按钮（改为停止录音）
@property (nonatomic, strong) UILabel *segmentInfoLabel;  // 段落信息标签

// 🆕 预览和试听UI
@property (nonatomic, strong) UIButton *previewButton;    // 试听按钮
@property (nonatomic, strong) UIButton *saveButton;       // 保存按钮
@property (nonatomic, strong) UIView *previewControlView;  // 预览控制面板
@property (nonatomic, assign) BOOL isInPreviewMode;       // 是否处于预览模式

// 耳返控制UI
@property (nonatomic, strong) UISwitch *earReturnSwitch;
@property (nonatomic, strong) UILabel *earReturnLabel;
@property (nonatomic, strong) UISlider *earReturnVolumeSlider;
@property (nonatomic, strong) UILabel *earReturnVolumeLabel;
@property (nonatomic, strong) UISlider *microphoneVolumeSlider;
@property (nonatomic, strong) UILabel *microphoneVolumeLabel;
@property (nonatomic, strong) UISlider *bgmVolumeSlider;  // 新增：BGM音量控制
@property (nonatomic, strong) UILabel *bgmVolumeLabel;
@property (nonatomic, strong) UISlider *bgmPitchSlider;  // 🆕 BGM音高调整控制
@property (nonatomic, strong) UILabel *bgmPitchLabel;

// 音效控制UI
@property (nonatomic, strong) UIButton *voiceEffectButton;
@property (nonatomic, strong) UIView *effectSelectorView;

// 🆕 AGC 控制UI
@property (nonatomic, strong) UIButton *agcButton;
@property (nonatomic, strong) UIView *agcSettingsView;

// 音频系统
@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) AVAudioRecorder *audioRecorder;
@property (nonatomic, strong) AVAudioSession *audioSession;
@property (nonatomic, strong) KaraokeAudioEngine *karaokeAudioEngine;

// 录音相关
@property (nonatomic, strong) NSString *recordingFilePath;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, assign) BOOL isPlaying;
@property (nonatomic, assign) NSTimeInterval recordingStartTime;  // 🆕 记录录音起始时间（用于歌词同步）

// 🎯 片段选择功能
@property (nonatomic, strong) UIButton *segmentSelectorButton;       // 片段选择按钮
@property (nonatomic, strong) SegmentSelectorView *segmentSelectorView;  // 片段选择器视图
@property (nonatomic, strong) KaraokeRecordingConfig *recordingConfig;   // 录音配置

// 回放相关
@property (nonatomic, strong) AVAudioPlayer *playbackPlayer;
@property (nonatomic, strong) NSTimer *playbackUpdateTimer;
@property (nonatomic, strong) RecordingPlaybackView *recordingPlaybackView;

// 定时器
@property (nonatomic, strong) NSTimer *updateTimer;
@property (nonatomic, strong) CADisplayLink *displayLink;

// 歌词
@property (nonatomic, strong) LyricsView *lyricsView;
@property (nonatomic, strong) LRCParser *lyricsParser;

// 🆕 防抖定时器（避免拖动时频繁重新生成）
@property (nonatomic, strong) NSTimer *parameterUpdateDebounceTimer;

// 🆕 试听模式更新定时器
@property (nonatomic, strong) NSTimer *previewUpdateTimer;

@end

@implementation KaraokeViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    NSLog(@"🎬 KaraokeViewController viewDidLoad 开始");
    
    // 🎯 初始化录音配置（默认为全曲模式）
    self.recordingConfig = [[KaraokeRecordingConfig alloc] init];
    
    NSLog(@"📱 Step 1: setupUI");
    [self setupUI];
    
    NSLog(@"📱 Step 2: setupAudioSession");
    [self setupAudioSession];  // 这会异步请求权限
    
    NSLog(@"📱 Step 3: setupPlayer");
    [self setupPlayer];
    
    NSLog(@"📱 Step 4: loadCurrentSong");
    [self loadCurrentSong];
    
    NSLog(@"📱 Step 5: 发送通知");
    // 发送通知，停止外层音频播放
    [[NSNotificationCenter defaultCenter] postNotificationName:@"KaraokeModeDidStart" object:nil];
    NSLog(@"🎤 卡拉OK模式开始，通知主界面停止播放");
    
    NSLog(@"✅ KaraokeViewController viewDidLoad 完成");
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];
    
    // 显示导航栏（从首页进入时需要显示）
    [self.navigationController setNavigationBarHidden:NO animated:animated];
    
    // 🎯 关键修复：重新激活AudioSession（防止被其他页面改变）
    if (self.karaokeAudioEngine) {
        NSError *error = nil;
        AVAudioSession *audioSession = [AVAudioSession sharedInstance];
        
        // 确保AudioSession处于正确状态
        [audioSession setCategory:AVAudioSessionCategoryPlayAndRecord
                      withOptions:AVAudioSessionCategoryOptionDefaultToSpeaker | 
                                  AVAudioSessionCategoryOptionAllowBluetooth
                            error:&error];
        
        if (!error) {
            [audioSession setActive:YES error:&error];
            if (!error) {
                NSLog(@"✅ 卡拉OK页面重新激活AudioSession");
            } else {
                NSLog(@"⚠️ 重新激活AudioSession失败: %@", error.localizedDescription);
            }
        }
    }
    
    [self startUpdateTimer];
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
    [self stopUpdateTimer];
    [self stopRecording];
    
    // 停止卡拉OK音频引擎
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine stop];
        [self.karaokeAudioEngine stopRecording];
    }
    
    // 🎯 关键修复：退出时停用AudioSession，让主界面接管
    NSError *error = nil;
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    [audioSession setActive:NO withOptions:AVAudioSessionSetActiveOptionNotifyOthersOnDeactivation error:&error];
    if (error) {
        NSLog(@"⚠️ 停用AudioSession失败: %@", error.localizedDescription);
    } else {
        NSLog(@"✅ 卡拉OK页面已停用AudioSession");
    }
    
//    // 发送通知，恢复外层音频播放
//    [[NSNotificationCenter defaultCenter] postNotificationName:@"KaraokeModeDidEnd" object:nil];
//    NSLog(@"🎤 卡拉OK模式结束，通知主界面恢复播放");
}

- (void)dealloc {
    [self stopUpdateTimer];
    [self stopRecording];
    
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine stop];
    }
    
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    NSLog(@"🗑️ KaraokeViewController dealloc");
}

#pragma mark - UI Setup

- (void)setupUI {
    self.view.backgroundColor = [UIColor blackColor];
    self.title = @"卡拉OK模式";
    
    // 添加返回按钮
    UIBarButtonItem *backButton = [[UIBarButtonItem alloc] initWithTitle:@"返回" 
                                                                   style:UIBarButtonItemStylePlain 
                                                                  target:self 
                                                                  action:@selector(backButtonTapped)];
    self.navigationItem.leftBarButtonItem = backButton;
    
    // 添加录音列表按钮
    UIBarButtonItem *listButton = [[UIBarButtonItem alloc] initWithTitle:@"📝 录音列表" 
                                                                   style:UIBarButtonItemStylePlain 
                                                                  target:self 
                                                                  action:@selector(showRecordingList)];
    self.navigationItem.rightBarButtonItem = listButton;
    
    // 歌曲标题
    self.songTitleLabel = [[UILabel alloc] init];
    self.songTitleLabel.text = self.currentSongName ?: @"未知歌曲";
    self.songTitleLabel.textColor = [UIColor whiteColor];
    self.songTitleLabel.font = [UIFont boldSystemFontOfSize:20];
    self.songTitleLabel.textAlignment = NSTextAlignmentCenter;
    self.songTitleLabel.frame = CGRectMake(20, 100, self.view.bounds.size.width - 40, 30);
    [self.view addSubview:self.songTitleLabel];
    
    // 🆕 可拖动的进度滑块（替换原来的进度条）
    self.progressSlider = [[UISlider alloc] init];
    self.progressSlider.minimumValue = 0.0;
    self.progressSlider.maximumValue = 1.0;
    self.progressSlider.value = 0.0;
    self.progressSlider.frame = CGRectMake(20, 150, self.view.bounds.size.width - 40, 20);
    self.progressSlider.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.progressSlider.maximumTrackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    [self.progressSlider addTarget:self action:@selector(progressSliderTouchDown:) forControlEvents:UIControlEventTouchDown];
    [self.progressSlider addTarget:self action:@selector(progressSliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self.progressSlider addTarget:self action:@selector(progressSliderTouchUp:) forControlEvents:UIControlEventTouchUpInside | UIControlEventTouchUpOutside];
    [self.view addSubview:self.progressSlider];
    
    // 时间标签
    self.durationLabel = [[UILabel alloc] init];
    self.durationLabel.text = @"0:00 / 0:00";
    self.durationLabel.textColor = [UIColor whiteColor];
    self.durationLabel.font = [UIFont systemFontOfSize:14];
    self.durationLabel.textAlignment = NSTextAlignmentCenter;
    self.durationLabel.frame = CGRectMake(20, 180, self.view.bounds.size.width - 40, 20);
    [self.view addSubview:self.durationLabel];
    
    // VU Meter 标签
    UILabel *vuLabel = [[UILabel alloc] init];
    vuLabel.text = @"麦克风音量";
    vuLabel.textColor = [UIColor whiteColor];
    vuLabel.font = [UIFont systemFontOfSize:16];
    vuLabel.frame = CGRectMake(20, 220, 120, 20);
    [self.view addSubview:vuLabel];
    
    // RMS 进度条
    self.rmsProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.rmsProgressView.progressTintColor = [UIColor greenColor];
    self.rmsProgressView.trackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.rmsProgressView.frame = CGRectMake(20, 250, self.view.bounds.size.width - 40, 10);
    [self.view addSubview:self.rmsProgressView];
    
    // Peak 进度条
    self.peakProgressView = [[UIProgressView alloc] initWithProgressViewStyle:UIProgressViewStyleDefault];
    self.peakProgressView.progressTintColor = [UIColor redColor];
    self.peakProgressView.trackTintColor = [UIColor colorWithWhite:0.3 alpha:1.0];
    self.peakProgressView.frame = CGRectMake(20, 270, self.view.bounds.size.width - 40, 10);
    [self.view addSubview:self.peakProgressView];
    
    // 🆕 分段录音控制按钮组（调整位置避免与耳返控制重叠）
    CGFloat buttonY = 290;  // 向上移动30px
    CGFloat buttonWidth = (self.view.bounds.size.width - 80) / 3;
    CGFloat buttonHeight = 40;  // 稍微缩小
    CGFloat buttonSpacing = 8;
    
    // 开始/停止录音按钮
    self.startButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    [self.startButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.startButton.layer.cornerRadius = 8;
    self.startButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.startButton.frame = CGRectMake(20, buttonY, buttonWidth, buttonHeight);
    [self.startButton addTarget:self action:@selector(startButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.startButton];
    
    // 暂停/恢复按钮
    self.pauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.pauseButton setTitle:@"⏸️ 暂停" forState:UIControlStateNormal];
    [self.pauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.pauseButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.8];
    self.pauseButton.layer.cornerRadius = 8;
    self.pauseButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.pauseButton.frame = CGRectMake(30 + buttonWidth, buttonY, buttonWidth, buttonHeight);
    self.pauseButton.hidden = YES;  // 初始隐藏
    [self.pauseButton addTarget:self action:@selector(pauseButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.pauseButton];
    
    // 完成录音按钮
    self.finishButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.finishButton setTitle:@"✅ 完成" forState:UIControlStateNormal];
    [self.finishButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.finishButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8];
    self.finishButton.layer.cornerRadius = 8;
    self.finishButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.finishButton.frame = CGRectMake(40 + buttonWidth * 2, buttonY, buttonWidth, buttonHeight);
    self.finishButton.hidden = YES;  // 初始隐藏
    [self.finishButton addTarget:self action:@selector(finishButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.finishButton];
    
    // 回退按钮
    self.rewindButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.rewindButton setTitle:@"⏪ 回退10秒" forState:UIControlStateNormal];
    [self.rewindButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.rewindButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.3 alpha:0.8];
    self.rewindButton.layer.cornerRadius = 8;
    self.rewindButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.rewindButton.frame = CGRectMake(20, buttonY + buttonHeight + buttonSpacing, self.view.bounds.size.width - 40, 36);
    self.rewindButton.hidden = YES;  // 初始隐藏
    [self.rewindButton addTarget:self action:@selector(rewindButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.rewindButton];
    
    // 🆕 段落信息标签
    self.segmentInfoLabel = [[UILabel alloc] init];
    self.segmentInfoLabel.text = @"";
    self.segmentInfoLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    self.segmentInfoLabel.font = [UIFont systemFontOfSize:11];
    self.segmentInfoLabel.textAlignment = NSTextAlignmentCenter;
    self.segmentInfoLabel.numberOfLines = 2;
    self.segmentInfoLabel.frame = CGRectMake(20, buttonY + buttonHeight + buttonSpacing + 38, self.view.bounds.size.width - 40, 30);
    [self.view addSubview:self.segmentInfoLabel];
    
    // 耳返控制界面（确保在最上层）
    [self setupEarReturnControls];
    
    // 音效选择按钮
    [self setupVoiceEffectButton];
    
    // 🎯 片段选择按钮
    [self setupSegmentSelectorButton];
    
    // 歌词视图
    [self setupLyricsView];
}

- (void)setupLyricsView {
    CGFloat lyricsY = self.view.bounds.size.height - 150;
    self.lyricsView = [[LyricsView alloc] initWithFrame:CGRectMake(20, lyricsY, self.view.bounds.size.width - 40, 120)];
    self.lyricsView.backgroundColor = [UIColor clearColor];
    self.lyricsView.highlightColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    self.lyricsView.normalColor = [UIColor colorWithWhite:1.0 alpha:0.6];
    self.lyricsView.highlightFont = [UIFont boldSystemFontOfSize:18];
    self.lyricsView.lyricsFont = [UIFont systemFontOfSize:16];
    self.lyricsView.lineSpacing = 20;
    self.lyricsView.autoScroll = YES;
    self.lyricsView.userInteractionEnabled = YES;  // 启用用户交互
    self.lyricsView.delegate = self;  // 🆕 设置代理
    
    [self.view addSubview:self.lyricsView];
}

- (void)setupEarReturnControls {
    CGFloat startY = 380;
    CGFloat spacing = 50;
    
    // 耳返开关
    self.earReturnLabel = [[UILabel alloc] init];
    self.earReturnLabel.text = @"🎧 耳返";
    self.earReturnLabel.textColor = [UIColor whiteColor];
    self.earReturnLabel.font = [UIFont systemFontOfSize:16];
    self.earReturnLabel.frame = CGRectMake(20, startY, 80, 30);
    [self.view addSubview:self.earReturnLabel];
    
    self.earReturnSwitch = [[UISwitch alloc] init];
    self.earReturnSwitch.on = YES; // 默认开启耳返
    self.earReturnSwitch.frame = CGRectMake(110, startY, 0, 0);
    [self.earReturnSwitch addTarget:self action:@selector(earReturnSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.earReturnSwitch];
    
    // 耳返音量滑块
    self.earReturnVolumeLabel = [[UILabel alloc] init];
    self.earReturnVolumeLabel.text = @"耳返音量";
    self.earReturnVolumeLabel.textColor = [UIColor whiteColor];
    self.earReturnVolumeLabel.font = [UIFont systemFontOfSize:14];
    self.earReturnVolumeLabel.frame = CGRectMake(20, startY + spacing, 80, 20);
    [self.view addSubview:self.earReturnVolumeLabel];
    
    self.earReturnVolumeSlider = [[UISlider alloc] init];
    self.earReturnVolumeSlider.minimumValue = 0.0;
    self.earReturnVolumeSlider.maximumValue = 1.0;
    self.earReturnVolumeSlider.value = 0.5; // 默认50%
    self.earReturnVolumeSlider.frame = CGRectMake(110, startY + spacing, self.view.bounds.size.width - 130, 20);
    self.earReturnVolumeSlider.userInteractionEnabled = YES; // 确保可交互
    [self.earReturnVolumeSlider addTarget:self action:@selector(earReturnVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.earReturnVolumeSlider];
    
    // 麦克风音量滑块
    self.microphoneVolumeLabel = [[UILabel alloc] init];
    self.microphoneVolumeLabel.text = @"麦克风音量";
    self.microphoneVolumeLabel.textColor = [UIColor whiteColor];
    self.microphoneVolumeLabel.font = [UIFont systemFontOfSize:14];
    self.microphoneVolumeLabel.frame = CGRectMake(20, startY + spacing * 2, 80, 20);
    [self.view addSubview:self.microphoneVolumeLabel];
    
    self.microphoneVolumeSlider = [[UISlider alloc] init];
    self.microphoneVolumeSlider.minimumValue = 0.0;
    self.microphoneVolumeSlider.maximumValue = 1.0;
    self.microphoneVolumeSlider.value = 1.0; // 默认100%
    self.microphoneVolumeSlider.frame = CGRectMake(110, startY + spacing * 2, self.view.bounds.size.width - 130, 20);
    self.microphoneVolumeSlider.userInteractionEnabled = YES; // 确保可交互
    [self.microphoneVolumeSlider addTarget:self action:@selector(microphoneVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.microphoneVolumeSlider];
    
    // BGM音量滑块
    self.bgmVolumeLabel = [[UILabel alloc] init];
    self.bgmVolumeLabel.text = @"🎵 BGM音量";
    self.bgmVolumeLabel.textColor = [UIColor whiteColor];
    self.bgmVolumeLabel.font = [UIFont systemFontOfSize:14];
    self.bgmVolumeLabel.frame = CGRectMake(20, startY + spacing * 3, 100, 20);
    [self.view addSubview:self.bgmVolumeLabel];
    
    self.bgmVolumeSlider = [[UISlider alloc] init];
    self.bgmVolumeSlider.minimumValue = 0.0;
    self.bgmVolumeSlider.maximumValue = 1.0;
    self.bgmVolumeSlider.value = 0.3; // 默认30% - 避免反馈
    self.bgmVolumeSlider.frame = CGRectMake(110, startY + spacing * 3, self.view.bounds.size.width - 130, 20);
    self.bgmVolumeSlider.userInteractionEnabled = YES; // 确保可交互
    [self.bgmVolumeSlider addTarget:self action:@selector(bgmVolumeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.bgmVolumeSlider];
    
    // 🆕 BGM音高调整控件
    self.bgmPitchLabel = [[UILabel alloc] init];
    self.bgmPitchLabel.text = @"🎵 BGM音高: 0";
    self.bgmPitchLabel.textColor = [UIColor whiteColor];
    self.bgmPitchLabel.font = [UIFont systemFontOfSize:14];
    self.bgmPitchLabel.frame = CGRectMake(20, startY + spacing * 4, 100, 20);
    [self.view addSubview:self.bgmPitchLabel];
    
    self.bgmPitchSlider = [[UISlider alloc] init];
    self.bgmPitchSlider.minimumValue = -12.0;  // -12半音
    self.bgmPitchSlider.maximumValue = 12.0;   // +12半音
    self.bgmPitchSlider.value = 0.0;  // 默认原调
    self.bgmPitchSlider.frame = CGRectMake(110, startY + spacing * 4, self.view.bounds.size.width - 130, 20);
    self.bgmPitchSlider.userInteractionEnabled = YES;
    self.bgmPitchSlider.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    [self.bgmPitchSlider addTarget:self action:@selector(bgmPitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:self.bgmPitchSlider];
    
    // 🆕 智能降噪开关（放在 BGM 音高下方）
    UILabel *noiseReductionLabel = [[UILabel alloc] init];
    noiseReductionLabel.text = @"🔇 智能降噪";
    noiseReductionLabel.textColor = [UIColor whiteColor];
    noiseReductionLabel.font = [UIFont systemFontOfSize:14];
    noiseReductionLabel.frame = CGRectMake(20, startY + spacing * 5, 100, 20);
    [self.view addSubview:noiseReductionLabel];
    
    UISwitch *noiseReductionSwitch = [[UISwitch alloc] init];
    noiseReductionSwitch.on = NO; // 默认关闭
    noiseReductionSwitch.onTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    noiseReductionSwitch.frame = CGRectMake(110, startY + spacing * 5 - 5, 51, 31);
    noiseReductionSwitch.tag = 9001; // 标记为降噪开关
    [noiseReductionSwitch addTarget:self action:@selector(noiseReductionSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.view addSubview:noiseReductionSwitch];
    
//    // 🆕 音高调节（放在降噪开关下方）
//    UILabel *pitchShiftLabel = [[UILabel alloc] init];
//    pitchShiftLabel.text = @"🎵 音高: 0半音";
//    pitchShiftLabel.textColor = [UIColor whiteColor];
//    pitchShiftLabel.font = [UIFont systemFontOfSize:14];
//    pitchShiftLabel.frame = CGRectMake(20, startY + spacing * 5, 100, 20);
//    pitchShiftLabel.tag = 9002; // 标记为音高标签
//    [self.view addSubview:pitchShiftLabel];
//    
//    UISlider *pitchShiftSlider = [[UISlider alloc] init];
//    pitchShiftSlider.minimumValue = -6.0f;
//    pitchShiftSlider.maximumValue = 6.0f;
//    pitchShiftSlider.value = 0.0f;
//    pitchShiftSlider.minimumTrackTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
//    pitchShiftSlider.frame = CGRectMake(110, startY + spacing * 5, self.view.bounds.size.width - 130, 20);
//    pitchShiftSlider.tag = 9003; // 标记为音高滑块
//    pitchShiftSlider.userInteractionEnabled = YES;
//    [pitchShiftSlider addTarget:self action:@selector(pitchShiftSliderChanged:) forControlEvents:UIControlEventValueChanged];
//    [self.view addSubview:pitchShiftSlider];
    
 
}

- (void)setupVoiceEffectButton {
    // 创建音效选择按钮
    CGFloat buttonWidth = 140;
    CGFloat buttonHeight = 44;
    CGFloat buttonX = self.view.bounds.size.width - buttonWidth - 20;
    CGFloat buttonY = 100;
    
    self.voiceEffectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.voiceEffectButton setTitle:@"🎤 音效：原声" forState:UIControlStateNormal];
    [self.voiceEffectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.voiceEffectButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:0.8];
    self.voiceEffectButton.layer.cornerRadius = 22;
    self.voiceEffectButton.layer.borderWidth = 1;
    self.voiceEffectButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0].CGColor;
    self.voiceEffectButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.voiceEffectButton.frame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);
    [self.voiceEffectButton addTarget:self action:@selector(showVoiceEffectSelector) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.voiceEffectButton];
    
    // 🆕 创建AGC控制按钮（紧邻音效按钮下方）
    CGFloat agcButtonY = buttonY + buttonHeight + 10;
    
    self.agcButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.agcButton setTitle:@"🎚️ AGC：关" forState:UIControlStateNormal];
    [self.agcButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.agcButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.7 alpha:0.8];
    self.agcButton.layer.cornerRadius = 22;
    self.agcButton.layer.borderWidth = 1;
    self.agcButton.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0].CGColor;
    self.agcButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.agcButton.frame = CGRectMake(buttonX, agcButtonY, buttonWidth, buttonHeight);
    [self.agcButton addTarget:self action:@selector(showAGCSettings) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.agcButton];
    
    NSLog(@"✅ 音效选择按钮已创建");
    NSLog(@"✅ AGC 控制按钮已创建");
}

#pragma mark - 🎯 片段选择功能

- (void)setupSegmentSelectorButton {
    // 创建片段选择按钮（位于左上角，音效按钮的对侧）
    CGFloat buttonWidth = 120;
    CGFloat buttonHeight = 44;
    CGFloat buttonX = 20;  // 左侧
    CGFloat buttonY = 100;
    
    self.segmentSelectorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.segmentSelectorButton setTitle:@"📍 选片段" forState:UIControlStateNormal];
    [self.segmentSelectorButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.segmentSelectorButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.8];
    self.segmentSelectorButton.layer.cornerRadius = 22;
    self.segmentSelectorButton.layer.borderWidth = 1;
    self.segmentSelectorButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.7 blue:0.2 alpha:1.0].CGColor;
    self.segmentSelectorButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.segmentSelectorButton.frame = CGRectMake(buttonX, buttonY, buttonWidth, buttonHeight);
    [self.segmentSelectorButton addTarget:self action:@selector(showSegmentSelector) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.segmentSelectorButton];
    
    NSLog(@"✅ 片段选择按钮已创建");
}

- (void)showSegmentSelector {
    // 创建片段选择视图
    self.segmentSelectorView = [[SegmentSelectorView alloc] initWithFrame:self.view.bounds];
    
    // 传入歌词解析器和总时长
    self.segmentSelectorView.lyricsParser = self.lyricsParser;
    self.segmentSelectorView.totalDuration = self.karaokeAudioEngine.duration;
    
    // 如果已经选择了片段，传入初始值
    if (self.recordingConfig.mode == KaraokeRecordingModeSegment) {
        self.segmentSelectorView.initialStartTime = self.recordingConfig.segmentStartTime;
        self.segmentSelectorView.initialEndTime = self.recordingConfig.segmentEndTime;
    }
    
    // 设置回调
    __weak typeof(self) weakSelf = self;
    
    // 确认选择片段
    self.segmentSelectorView.onConfirm = ^(NSTimeInterval startTime, NSTimeInterval endTime) {
        [weakSelf onSegmentSelected:startTime endTime:endTime];
    };
    
    // 选择全曲
    self.segmentSelectorView.onSelectFull = ^{
        [weakSelf onFullSongSelected];
    };
    
    // 取消
    self.segmentSelectorView.onCancel = ^{
        weakSelf.segmentSelectorView = nil;
    };
    
    // 显示
    [self.view addSubview:self.segmentSelectorView];
    [self.segmentSelectorView show];
}

- (void)onSegmentSelected:(NSTimeInterval)startTime endTime:(NSTimeInterval)endTime {
    // 更新录音配置为片段模式
    [self.recordingConfig setSegmentModeWithStart:startTime end:endTime];
    
    // 更新按钮显示
    [self.segmentSelectorButton setTitle:@"🔄 重置片段" forState:UIControlStateNormal];
    self.segmentSelectorButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:0.8];
    
    NSLog(@"✅ 已选择片段: %.2f ~ %.2f 秒", startTime, endTime);
    
    // 清理选择器视图
    self.segmentSelectorView = nil;
}

- (void)onFullSongSelected {
    // 重置为全曲模式
    [self.recordingConfig resetToFullMode];
    
    // 恢复按钮显示
    [self.segmentSelectorButton setTitle:@"📍 选片段" forState:UIControlStateNormal];
    self.segmentSelectorButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.8];
    
    NSLog(@"✅ 已重置为全曲模式");
    
    // 清理选择器视图
    self.segmentSelectorView = nil;
}

- (void)showVoiceEffectSelector {
    // 如果已经显示，则隐藏
    if (self.effectSelectorView) {
        [self hideVoiceEffectSelector];
        return;
    }
    
    // 创建半透明背景
    UIView *backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    backgroundView.tag = 999;
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideVoiceEffectSelector)];
    [backgroundView addGestureRecognizer:tapGesture];
    [self.view addSubview:backgroundView];
    
    // 创建音效选择面板
    CGFloat panelWidth = 320;
    CGFloat panelHeight = 630;  // 适应12个音效（新增了自动修音、升调、降调）
    CGFloat panelX = (self.view.bounds.size.width - panelWidth) / 2;
    CGFloat panelY = (self.view.bounds.size.height - panelHeight) / 2;
    
    self.effectSelectorView = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelWidth, panelHeight)];
    self.effectSelectorView.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.95];
    self.effectSelectorView.layer.cornerRadius = 16;
    self.effectSelectorView.layer.borderWidth = 2;
    self.effectSelectorView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:1.0 alpha:1.0].CGColor;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 20, panelWidth, 30)];
    titleLabel.text = @"🎤 选择音效";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.effectSelectorView addSubview:titleLabel];
    
    // 音效列表
    NSArray *effects = @[
        @[@(VoiceEffectTypeNone), @"原声", @"💬"],
        @[@(VoiceEffectTypeStudio), @"录音棚", @"🎙️"],
        @[@(VoiceEffectTypeConcertHall), @"音乐厅", @"🎭"],
        @[@(VoiceEffectTypeSuperReverb), @"超级混响", @"🌊"],
        @[@(VoiceEffectTypeSinger), @"唱将", @"🎵"],
        @[@(VoiceEffectTypeGodOfSong), @"歌神", @"👑"],
        @[@(VoiceEffectTypeEthereal), @"空灵", @"✨"],
        @[@(VoiceEffectTypeMagnetic), @"磁性", @"🔥"],
        @[@(VoiceEffectTypeBright), @"明亮", @"💎"],
    ];
    
    CGFloat buttonStartY = 70;
    CGFloat buttonSpacing = 45;
    CGFloat buttonHeight = 40;
    
    for (int i = 0; i < effects.count; i++) {
        NSArray *effect = effects[i];
        VoiceEffectType effectType = [effect[0] integerValue];
        NSString *name = effect[1];
        NSString *emoji = effect[2];
        
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.tag = effectType;
        button.frame = CGRectMake(20, buttonStartY + i * buttonSpacing, panelWidth - 40, buttonHeight);
        
        NSString *buttonTitle = [NSString stringWithFormat:@"%@ %@", emoji, name];
        [button setTitle:buttonTitle forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.backgroundColor = [UIColor colorWithRed:0.25 green:0.45 blue:0.85 alpha:0.6];
        button.layer.cornerRadius = 8;
        button.titleLabel.font = [UIFont boldSystemFontOfSize:16];
        button.contentHorizontalAlignment = UIControlContentHorizontalAlignmentLeft;
        button.contentEdgeInsets = UIEdgeInsetsMake(0, 15, 0, 0);
        
        // 如果是当前选中的音效，高亮显示
        if (self.karaokeAudioEngine.voiceEffectProcessor.effectType == effectType) {
            button.backgroundColor = [UIColor colorWithRed:0.0 green:0.7 blue:1.0 alpha:0.8];
            button.layer.borderWidth = 2;
            button.layer.borderColor = [UIColor colorWithRed:0.0 green:0.9 blue:1.0 alpha:1.0].CGColor;
        }
        
        [button addTarget:self action:@selector(selectVoiceEffect:) forControlEvents:UIControlEventTouchUpInside];
        [self.effectSelectorView addSubview:button];
    }
    
    // 添加到视图
    [self.view addSubview:self.effectSelectorView];
    
    // 动画效果
    self.effectSelectorView.alpha = 0;
    self.effectSelectorView.transform = CGAffineTransformMakeScale(0.8, 0.8);
    [UIView animateWithDuration:0.3 delay:0 usingSpringWithDamping:0.8 initialSpringVelocity:0 options:0 animations:^{
        self.effectSelectorView.alpha = 1;
        self.effectSelectorView.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    NSLog(@"📱 显示音效选择面板");
}

- (void)hideVoiceEffectSelector {
    UIView *backgroundView = [self.view viewWithTag:999];
    
    [UIView animateWithDuration:0.2 animations:^{
        self.effectSelectorView.alpha = 0;
        self.effectSelectorView.transform = CGAffineTransformMakeScale(0.8, 0.8);
        backgroundView.alpha = 0;
    } completion:^(BOOL finished) {
        [self.effectSelectorView removeFromSuperview];
        [backgroundView removeFromSuperview];
        self.effectSelectorView = nil;
    }];
}

#pragma mark - 🆕 AGC 控制方法

- (void)showAGCSettings {
    // 如果已经显示，则隐藏
    if (self.agcSettingsView) {
        [self hideAGCSettings];
        return;
    }
    
    // 创建半透明背景
    UIView *backgroundView = [[UIView alloc] initWithFrame:self.view.bounds];
    backgroundView.backgroundColor = [UIColor colorWithWhite:0 alpha:0.7];
    backgroundView.tag = 998;  // 使用不同的tag
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(hideAGCSettings)];
    [backgroundView addGestureRecognizer:tapGesture];
    [self.view addSubview:backgroundView];
    
    // 创建AGC设置面板
    CGFloat panelWidth = 340;
    CGFloat panelHeight = 420;
    CGFloat panelX = (self.view.bounds.size.width - panelWidth) / 2;
    CGFloat panelY = (self.view.bounds.size.height - panelHeight) / 2;
    
    self.agcSettingsView = [[UIView alloc] initWithFrame:CGRectMake(panelX, panelY, panelWidth, panelHeight)];
    self.agcSettingsView.backgroundColor = [UIColor colorWithWhite:0.12 alpha:0.97];
    self.agcSettingsView.layer.cornerRadius = 20;
    self.agcSettingsView.layer.borderWidth = 2;
    self.agcSettingsView.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0].CGColor;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(0, 25, panelWidth, 35)];
    titleLabel.text = @"🎚️ 自动增益控制 (AGC)";
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.font = [UIFont boldSystemFontOfSize:22];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.agcSettingsView addSubview:titleLabel];
    
    // 说明文字
    UILabel *descLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 70, panelWidth - 40, 50)];
    descLabel.text = @"自动调整麦克风音量，让录音保持稳定的响度，无需手动调节。";
    descLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    descLabel.font = [UIFont systemFontOfSize:13];
    descLabel.numberOfLines = 0;
    descLabel.textAlignment = NSTextAlignmentCenter;
    [self.agcSettingsView addSubview:descLabel];
    
    CGFloat currentY = 140;
    
    // ======== AGC 开关 ========
    UILabel *switchLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, currentY, 120, 30)];
    switchLabel.text = @"启用 AGC";
    switchLabel.textColor = [UIColor whiteColor];
    switchLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.agcSettingsView addSubview:switchLabel];
    
    UISwitch *agcSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(panelWidth - 80, currentY, 51, 31)];
    agcSwitch.on = self.karaokeAudioEngine.voiceEffectProcessor.enableAGC;
    agcSwitch.onTintColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0];
    agcSwitch.tag = 8001;
    [agcSwitch addTarget:self action:@selector(agcSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.agcSettingsView addSubview:agcSwitch];
    
    currentY += 60;
    
    // ======== AGC 强度调节 ========
    UILabel *strengthTitleLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, currentY, 200, 25)];
    strengthTitleLabel.text = @"AGC 强度";
    strengthTitleLabel.textColor = [UIColor whiteColor];
    strengthTitleLabel.font = [UIFont boldSystemFontOfSize:16];
    [self.agcSettingsView addSubview:strengthTitleLabel];
    
    UILabel *strengthValueLabel = [[UILabel alloc] initWithFrame:CGRectMake(panelWidth - 100, currentY, 70, 25)];
    strengthValueLabel.tag = 8002;
    strengthValueLabel.textColor = [UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0];
    strengthValueLabel.font = [UIFont boldSystemFontOfSize:15];
    strengthValueLabel.textAlignment = NSTextAlignmentRight;
    [self.agcSettingsView addSubview:strengthValueLabel];
    
    currentY += 35;
    
    UISlider *strengthSlider = [[UISlider alloc] initWithFrame:CGRectMake(30, currentY, panelWidth - 60, 30)];
    strengthSlider.minimumValue = 0.0f;
    strengthSlider.maximumValue = 1.0f;
    strengthSlider.value = self.karaokeAudioEngine.voiceEffectProcessor.agcStrength;
    strengthSlider.minimumTrackTintColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0];
    strengthSlider.tag = 8003;
    [strengthSlider addTarget:self action:@selector(agcStrengthSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.agcSettingsView addSubview:strengthSlider];
    
    // 更新强度标签
    [self updateAGCStrengthLabel:strengthValueLabel forStrength:strengthSlider.value];
    
    currentY += 40;
    
    // 强度说明
    UILabel *strengthHintLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, currentY, panelWidth - 60, 15)];
    strengthHintLabel.text = @"弱                           中                           强";
    strengthHintLabel.textColor = [UIColor colorWithWhite:0.5 alpha:1.0];
    strengthHintLabel.font = [UIFont systemFontOfSize:11];
    strengthHintLabel.textAlignment = NSTextAlignmentCenter;
    [self.agcSettingsView addSubview:strengthHintLabel];
    
    currentY += 35;
    
    // ======== 实时增益显示 ========
    UILabel *gainDisplayLabel = [[UILabel alloc] initWithFrame:CGRectMake(30, currentY, panelWidth - 60, 25)];
    gainDisplayLabel.text = @"当前增益：1.0x";
    gainDisplayLabel.textColor = [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:1.0];
    gainDisplayLabel.font = [UIFont monospacedDigitSystemFontOfSize:14 weight:UIFontWeightMedium];
    gainDisplayLabel.textAlignment = NSTextAlignmentCenter;
    gainDisplayLabel.tag = 8004;
    [self.agcSettingsView addSubview:gainDisplayLabel];
    
    // 启动定时器更新增益显示（只在AGC开启时）
    if (agcSwitch.on) {
        [self startAGCGainUpdateTimer];
    }
    
    currentY += 40;
    
    // ======== 快捷设置按钮 ========
    CGFloat presetButtonWidth = 85;
    CGFloat presetButtonHeight = 36;
    CGFloat presetButtonSpacing = 10;
    CGFloat totalPresetWidth = presetButtonWidth * 3 + presetButtonSpacing * 2;
    CGFloat presetStartX = (panelWidth - totalPresetWidth) / 2;
    
    NSArray *presets = @[
        @{@"title": @"弱", @"value": @(0.16f)},
        @{@"title": @"中", @"value": @(0.50f)},
        @{@"title": @"强", @"value": @(1.0f)}
    ];
    
    for (int i = 0; i < presets.count; i++) {
        NSDictionary *preset = presets[i];
        
        UIButton *presetButton = [UIButton buttonWithType:UIButtonTypeSystem];
        presetButton.frame = CGRectMake(presetStartX + i * (presetButtonWidth + presetButtonSpacing), 
                                       currentY, 
                                       presetButtonWidth, 
                                       presetButtonHeight);
        [presetButton setTitle:preset[@"title"] forState:UIControlStateNormal];
        [presetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        presetButton.backgroundColor = [UIColor colorWithRed:0.4 green:0.25 blue:0.6 alpha:0.7];
        presetButton.layer.cornerRadius = 8;
        presetButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
        presetButton.tag = 8100 + i;
        [presetButton addTarget:self action:@selector(agcPresetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.agcSettingsView addSubview:presetButton];
    }
    
    // 添加到视图
    [self.view addSubview:self.agcSettingsView];
    
    // 动画效果
    self.agcSettingsView.alpha = 0;
    self.agcSettingsView.transform = CGAffineTransformMakeScale(0.85, 0.85);
    [UIView animateWithDuration:0.35 delay:0 usingSpringWithDamping:0.75 initialSpringVelocity:0 options:0 animations:^{
        self.agcSettingsView.alpha = 1;
        self.agcSettingsView.transform = CGAffineTransformIdentity;
    } completion:nil];
    
    NSLog(@"📱 显示 AGC 设置面板");
}

- (void)hideAGCSettings {
    UIView *backgroundView = [self.view viewWithTag:998];
    
    // 停止增益更新定时器
    [self stopAGCGainUpdateTimer];
    
    [UIView animateWithDuration:0.25 animations:^{
        self.agcSettingsView.alpha = 0;
        self.agcSettingsView.transform = CGAffineTransformMakeScale(0.85, 0.85);
        backgroundView.alpha = 0;
    } completion:^(BOOL finished) {
        [self.agcSettingsView removeFromSuperview];
        [backgroundView removeFromSuperview];
        self.agcSettingsView = nil;
    }];
}

- (void)agcSwitchChanged:(UISwitch *)sender {
    BOOL enabled = sender.on;
    float currentStrength = self.karaokeAudioEngine.voiceEffectProcessor.agcStrength;
    
    // 应用AGC设置
    [self.karaokeAudioEngine.voiceEffectProcessor setAGCEnabled:enabled strength:currentStrength];
    
    // 更新按钮显示
    [self updateAGCButtonTitle];
    
    // 控制增益显示更新
    if (enabled) {
        [self startAGCGainUpdateTimer];
    } else {
        [self stopAGCGainUpdateTimer];
    }
    
    NSLog(@"🎚️ AGC %@", enabled ? @"已启用" : @"已关闭");
}

- (void)agcStrengthSliderChanged:(UISlider *)sender {
    float strength = sender.value;
    BOOL enabled = self.karaokeAudioEngine.voiceEffectProcessor.enableAGC;
    
    // 应用AGC设置
    [self.karaokeAudioEngine.voiceEffectProcessor setAGCEnabled:enabled strength:strength];
    
    // 更新强度标签
    UILabel *strengthLabel = (UILabel *)[self.agcSettingsView viewWithTag:8002];
    [self updateAGCStrengthLabel:strengthLabel forStrength:strength];
    
    NSLog(@"🎚️ AGC 强度调整为: %.2f", strength);
}

- (void)agcPresetButtonTapped:(UIButton *)sender {
    NSArray *presetValues = @[@(0.16f), @(0.50f), @(1.0f)];
    int presetIndex = (int)(sender.tag - 8100);
    
    if (presetIndex >= 0 && presetIndex < presetValues.count) {
        float strength = [presetValues[presetIndex] floatValue];
        
        // 更新滑块
        UISlider *strengthSlider = (UISlider *)[self.agcSettingsView viewWithTag:8003];
        strengthSlider.value = strength;
        
        // 应用设置
        BOOL enabled = self.karaokeAudioEngine.voiceEffectProcessor.enableAGC;
        [self.karaokeAudioEngine.voiceEffectProcessor setAGCEnabled:enabled strength:strength];
        
        // 更新强度标签
        UILabel *strengthLabel = (UILabel *)[self.agcSettingsView viewWithTag:8002];
        [self updateAGCStrengthLabel:strengthLabel forStrength:strength];
        
        NSLog(@"🎚️ 选择预设强度: %.2f", strength);
    }
}

- (void)updateAGCStrengthLabel:(UILabel *)label forStrength:(float)strength {
    NSString *levelText;
    if (strength < 0.34f) {
        levelText = @"弱";
    } else if (strength < 0.67f) {
        levelText = @"中";
    } else {
        levelText = @"强";
    }
    label.text = [NSString stringWithFormat:@"%@ (%.0f%%)", levelText, strength * 100];
}

- (void)updateAGCButtonTitle {
    BOOL enabled = self.karaokeAudioEngine.voiceEffectProcessor.enableAGC;
    NSString *title = enabled ? @"🎚️ AGC：开" : @"🎚️ AGC：关";
    [self.agcButton setTitle:title forState:UIControlStateNormal];
    
    // 改变按钮颜色以反映状态
    if (enabled) {
        self.agcButton.backgroundColor = [UIColor colorWithRed:0.4 green:0.7 blue:0.3 alpha:0.9];
        self.agcButton.layer.borderColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.4 alpha:1.0].CGColor;
    } else {
        self.agcButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.7 alpha:0.8];
        self.agcButton.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0].CGColor;
    }
}

// ======== 增益显示更新定时器 ========
- (void)startAGCGainUpdateTimer {
    [self stopAGCGainUpdateTimer];  // 确保没有重复的定时器
    
    // 每0.1秒更新一次增益显示
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1
                                                        target:self
                                                      selector:@selector(updateAGCGainDisplay)
                                                      userInfo:nil
                                                       repeats:YES];
}

- (void)stopAGCGainUpdateTimer {
    if (self.updateTimer) {
        [self.updateTimer invalidate];
        self.updateTimer = nil;
    }
}

- (void)updateAGCGainDisplay {
    if (!self.agcSettingsView) return;
    
    UILabel *gainLabel = (UILabel *)[self.agcSettingsView viewWithTag:8004];
    if (gainLabel) {
        float currentGain = [self.karaokeAudioEngine.voiceEffectProcessor getCurrentAGCGain];
        gainLabel.text = [NSString stringWithFormat:@"当前增益：%.2fx", currentGain];
        
        // 根据增益大小改变颜色（视觉反馈）
        if (currentGain > 3.0f) {
            gainLabel.textColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0];  // 红色 - 高增益
        } else if (currentGain > 1.5f) {
            gainLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.2 alpha:1.0];  // 黄色 - 中增益
        } else {
            gainLabel.textColor = [UIColor colorWithRed:0.5 green:1.0 blue:0.5 alpha:1.0];  // 绿色 - 正常
        }
    }
}

- (void)selectVoiceEffect:(UIButton *)sender {
    VoiceEffectType effectType = (VoiceEffectType)sender.tag;
    
    // 应用音效
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine setVoiceEffect:effectType];
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
    
    // 更新按钮标题
    NSString *effectName = [VoiceEffectProcessor nameForEffectType:effectType];
    [self.voiceEffectButton setTitle:[NSString stringWithFormat:@"🎤 音效：%@", effectName] forState:UIControlStateNormal];
    
    NSLog(@"🎵 选择音效: %@", effectName);
    
    // 关闭面板
    [self hideVoiceEffectSelector];
}

// 🆕 降噪开关改变
- (void)noiseReductionSwitchChanged:(UISwitch *)sender {
    BOOL enabled = sender.isOn;
    
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.voiceEffectProcessor) {
        [self.karaokeAudioEngine.voiceEffectProcessor setNoiseReductionEnabled:enabled];
        NSLog(@"🔇 智能降噪: %@", enabled ? @"开启" : @"关闭");
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
}

// 🆕 音高滑块改变
//- (void)pitchShiftSliderChanged:(UISlider *)sender {
//    float pitchShift = roundf(sender.value); // 四舍五入到整数半音
//    sender.value = pitchShift; // 捕捉到整数值
//    
//    // 更新标签
//    UILabel *pitchLabel = (UILabel *)[self.view viewWithTag:9002];
//    if (pitchLabel) {
//        if (pitchShift > 0) {
//            pitchLabel.text = [NSString stringWithFormat:@"🎵 音高: +%.0f半音", pitchShift];
//        } else if (pitchShift < 0) {
//            pitchLabel.text = [NSString stringWithFormat:@"🎵 音高: %.0f半音", pitchShift];
//        } else {
//            pitchLabel.text = @"🎵 音高: 0半音";
//        }
//    }
//    
//    // 应用音高变化
//    if (self.karaokeAudioEngine && self.karaokeAudioEngine.voiceEffectProcessor) {
//        [self.karaokeAudioEngine.voiceEffectProcessor setPitchShiftSemitones:pitchShift];
//        NSLog(@"🎵 音高调节: %.0f 半音", pitchShift);
//        
//        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
//        if (self.isInPreviewMode) {
//            [self scheduleParameterUpdateWithDelay];
//        }
//    }
//}

#pragma mark - Audio Setup

- (void)setupAudioSession {
    // 注意：音频会话由KaraokeAudioEngine管理，这里只做权限检查
    self.audioSession = [AVAudioSession sharedInstance];
    
    // 请求麦克风权限
    [self.audioSession requestRecordPermission:^(BOOL granted) {
        dispatch_async(dispatch_get_main_queue(), ^{
            if (granted) {
                NSLog(@"✅ 麦克风权限已授权");
            } else {
                NSLog(@"❌ 麦克风权限被拒绝");
                [self showMicrophonePermissionAlert];
            }
        });
    }];
    
    NSLog(@"✅ 音频会话由KaraokeAudioEngine统一管理");
}


- (void)showMicrophonePermissionAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"需要麦克风权限" 
                                                                   message:@"卡拉OK功能需要访问麦克风来录制您的声音。请在设置中允许麦克风权限。" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *settingsAction = [UIAlertAction actionWithTitle:@"去设置" 
                                                             style:UIAlertActionStyleDefault 
                                                           handler:^(UIAlertAction * _Nonnull action) {
        [[UIApplication sharedApplication] openURL:[NSURL URLWithString:UIApplicationOpenSettingsURLString] 
                                           options:@{} 
                                 completionHandler:nil];
    }];
    
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    
    [alert addAction:settingsAction];
    [alert addAction:cancelAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)setupAudioRecorder {
    // 设置录音文件路径
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_recording_%@.m4a", 
                         [[NSDate date] description]];
    self.recordingFilePath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    // 确保目录存在
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:documentsDirectory]) {
        [fileManager createDirectoryAtPath:documentsDirectory withIntermediateDirectories:YES attributes:nil error:nil];
    }
    
    // 录音设置 - 使用更兼容的设置
    NSDictionary *recordSettings = @{
        AVFormatIDKey: @(kAudioFormatMPEG4AAC),
        AVSampleRateKey: @44100.0,
        AVNumberOfChannelsKey: @1,  // 改为单声道，更稳定
        AVEncoderAudioQualityKey: @(AVAudioQualityMedium),  // 降低质量要求
        AVEncoderBitRateKey: @128000
    };
    
    NSError *error;
    self.audioRecorder = [[AVAudioRecorder alloc] initWithURL:[NSURL fileURLWithPath:self.recordingFilePath]
                                                     settings:recordSettings
                                                        error:&error];
    
    if (error) {
        NSLog(@"❌ 创建录音器失败: %@", error.localizedDescription);
        NSLog(@"   错误详情: %@", error.userInfo);
    } else {
        NSLog(@"✅ 录音器创建成功: %@", self.recordingFilePath);
        self.audioRecorder.delegate = self;
        self.audioRecorder.meteringEnabled = YES;
        
        // 准备录音
        BOOL prepared = [self.audioRecorder prepareToRecord];
        if (prepared) {
            NSLog(@"✅ 录音器准备成功");
        } else {
            NSLog(@"❌ 录音器准备失败");
        }
    }
}

- (void)setupPlayer {
    // 创建卡拉OK音频引擎（用于BGM播放、耳返和录音）
    self.karaokeAudioEngine = [[KaraokeAudioEngine alloc] init];
    self.karaokeAudioEngine.delegate = self;
    
    // 🔧 同步 UI 滑块的初始值到音频引擎
    if (self.karaokeAudioEngine) {
        // 耳返开关
        BOOL earReturnEnabled = self.earReturnSwitch ? self.earReturnSwitch.isOn : YES;
        [self.karaokeAudioEngine setEarReturnEnabled:earReturnEnabled];
        
        // 耳返音量（从滑块读取，如果滑块还未创建则使用默认值）
        float earReturnVolume = self.earReturnVolumeSlider ? self.earReturnVolumeSlider.value : 0.5;
        [self.karaokeAudioEngine setEarReturnVolume:earReturnVolume];
        
        // 麦克风音量（从滑块读取，如果滑块还未创建则使用默认值）
        float microphoneVolume = self.microphoneVolumeSlider ? self.microphoneVolumeSlider.value : 1.0;
        [self.karaokeAudioEngine setMicrophoneVolume:microphoneVolume];
        
        // 🎵 BGM 音量（从滑块读取，如果滑块还未创建则使用默认值）
        float bgmVolume = self.bgmVolumeSlider ? self.bgmVolumeSlider.value : 0.3;
        if (self.karaokeAudioEngine) {
            self.karaokeAudioEngine.bgmVolume = bgmVolume;
        }
        
        NSLog(@"✅ 卡拉OK音频引擎初始音量已设置:");
        NSLog(@"   耳返: %@ (音量 %.0f%%)", earReturnEnabled ? @"开" : @"关", earReturnVolume * 100);
        NSLog(@"   麦克风音量: %.0f%%", microphoneVolume * 100);
        NSLog(@"   BGM音量: %.0f%%", bgmVolume * 100);
    }
}

- (void)loadCurrentSong {
    if (self.currentSongName) {
        // 🔧 优先使用完整路径，支持 ncm 解密后的文件
        NSString *filePath = self.currentSongPath;
        
        // 如果没有完整路径，尝试从 Bundle 查找
        if (!filePath || ![[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            filePath = [[NSBundle mainBundle] pathForResource:self.currentSongName ofType:nil];
        }
        
        if (filePath && [[NSFileManager defaultManager] fileExistsAtPath:filePath]) {
            NSLog(@"🎵 加载音频文件: %@", filePath);
            [self.karaokeAudioEngine loadAudioFile:filePath];
            
            // 🔧 加载完成后，同步 UI 的 BGM 音量到音频引擎
            if (self.bgmVolumeSlider && self.karaokeAudioEngine) {
                float bgmVolume = self.bgmVolumeSlider.value;
                self.karaokeAudioEngine.bgmVolume = bgmVolume;
                NSLog(@"🎵 已同步 UI BGM 音量到引擎: %.0f%%", bgmVolume * 100);
            }
            
            NSLog(@"✅ 音频文件已加载，等待用户点击开始录音按钮");
        } else {
            NSLog(@"❌ 未找到音频文件: %@ (path: %@)", self.currentSongName, filePath);
        }
        
        // 加载歌词
        [self loadLyricsForSong:self.currentSongName];
    }
}

- (void)loadLyricsForSong:(NSString *)songName {
    // 🆕 使用 LyricsManager 统一管理歌词加载（支持从Bundle和沙盒加载）
    
    // 构建音频文件的完整路径（用于LyricsManager查找对应的歌词）
    NSString *audioPath = [[NSBundle mainBundle] pathForResource:songName ofType:nil];
    
    if (!audioPath) {
        NSLog(@"⚠️ 未找到音频文件: %@", songName);
        self.lyricsView.parser = nil;
        return;
    }
    
    NSLog(@"🔍 [K歌模式] 正在加载歌词: %@", songName);
    
    // 使用 LyricsManager 获取歌词（自动处理Bundle、沙盒、ID3标签、在线API等多种来源）
    [[LyricsManager sharedManager] fetchLyricsForAudioFile:audioPath completion:^(LRCParser * _Nullable parser, NSError * _Nullable error) {
        if (parser && parser.lyrics.count > 0) {
            self.lyricsParser = parser;
            self.lyricsView.parser = parser;
            NSLog(@"✅ [K歌模式] 歌词加载成功: %@ (%lu行)", songName, (unsigned long)parser.lyrics.count);
        } else {
            NSLog(@"⚠️ [K歌模式] 未找到歌词: %@ (error: %@)", songName, error.localizedDescription);
            self.lyricsView.parser = nil;
        }
    }];
}

#pragma mark - Timer Management

- (void)startUpdateTimer {
    self.updateTimer = [NSTimer scheduledTimerWithTimeInterval:0.1 
                                                        target:self 
                                                      selector:@selector(updateUI) 
                                                      userInfo:nil 
                                                       repeats:YES];
    
    self.displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateVUMeter)];
    [self.displayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
}

- (void)stopUpdateTimer {
    [self.updateTimer invalidate];
    self.updateTimer = nil;
    
    [self.displayLink invalidate];
    self.displayLink = nil;
}

#pragma mark - UI Updates

- (void)updateUI {
    // 🔧 Bug修复：预览模式下由previewUpdateTimer更新，避免冲突
    if (self.isInPreviewMode) {
        return;  // 预览模式下不更新，避免和previewUpdateTimer冲突
    }
    
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.duration > 0) {
        // 更新进度滑块 - 使用基于 BGM 读取位置的时间
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        NSTimeInterval duration = self.karaokeAudioEngine.duration;
        float progress = duration > 0 ? (float)(currentTime / duration) : 0.0f;
        
        // 🆕 只有在用户未拖动时才更新滑块
        if (!self.progressSlider.isTracking) {
            self.progressSlider.value = progress;
        }
        
        // 更新时间标签
        NSString *currentTimeStr = [self formatTime:currentTime];
        NSString *durationStr = [self formatTime:duration];
        self.durationLabel.text = [NSString stringWithFormat:@"%@ / %@", currentTimeStr, durationStr];
        
        // 🆕 只有在播放时才更新歌词（停止/暂停时不更新）
        if (self.karaokeAudioEngine.isPlaying) {
        [self.lyricsView updateWithTime:currentTime];
        }
        
        // 🎯 片段模式自动停止检测
        if (self.isRecording && self.recordingConfig.mode == KaraokeRecordingModeSegment) {
            if (currentTime >= self.recordingConfig.segmentEndTime) {
                NSLog(@"🎯 已到达片段终点，自动停止录音");
                [self autoStopSegmentRecording];
            }
        }
    }
}

- (void)updateVUMeter {
    // VU表现在由KaraokeAudioEngine的回调实时更新
    // 这个方法保留用于其他可能的更新逻辑
    // 不再需要从AVAudioRecorder获取数据
}

- (NSString *)formatTime:(NSTimeInterval)time {
    // 🔧 修复：处理负数时间和异常值
    if (time < 0 || isnan(time) || isinf(time)) {
        return @"0:00";
    }
    
    int minutes = (int)time / 60;
    int seconds = (int)time % 60;
    return [NSString stringWithFormat:@"%d:%02d", minutes, seconds];
}

#pragma mark - Button Actions

// 🆕 进度滑块事件处理
- (void)progressSliderTouchDown:(UISlider *)sender {
    // 用户开始拖动，暂时停止自动更新
    NSLog(@"📍 用户开始拖动进度条");
}

- (void)progressSliderValueChanged:(UISlider *)sender {
    // 🔧 Bug修复：预览模式下禁止拖动进度条
    if (self.isInPreviewMode) {
        return;  // 预览模式下不响应拖动
    }
    
    // 实时更新预览时间和歌词
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.duration > 0) {
        NSTimeInterval duration = self.karaokeAudioEngine.duration;
        NSTimeInterval targetTime = duration * sender.value;
        
        // 更新时间显示
        NSString *targetTimeStr = [self formatTime:targetTime];
        NSString *durationStr = [self formatTime:duration];
        self.durationLabel.text = [NSString stringWithFormat:@"%@ / %@", targetTimeStr, durationStr];
        
        // 更新歌词预览
        [self.lyricsView updateWithTime:targetTime];
    }
}

- (void)progressSliderTouchUp:(UISlider *)sender {
    // 🔧 Bug修复：预览模式下禁止拖动进度条（避免干扰预览播放）
    if (self.isInPreviewMode) {
        NSLog(@"⚠️ 预览模式下不支持拖动进度条");
        // 恢复到当前实际播放位置
        if ([self.karaokeAudioEngine isPlayingPreview]) {
            NSTimeInterval currentTime = [self.karaokeAudioEngine currentPreviewTime];
            NSTimeInterval duration = [self.karaokeAudioEngine previewDuration];
            if (duration > 0) {
                self.progressSlider.value = currentTime / duration;
            }
        }
        return;
    }
    
    if (!self.karaokeAudioEngine || self.karaokeAudioEngine.duration <= 0) {
        return;
    }
    
    NSTimeInterval duration = self.karaokeAudioEngine.duration;
    NSTimeInterval targetTime = duration * sender.value;
    
    NSLog(@"📍 用户松开进度条，跳转到 %.2f 秒", targetTime);
    
    // 如果正在录音，使用jump或rewind
    if (self.karaokeAudioEngine.isRecording) {
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        
        if (targetTime > currentTime) {
            // 向后跳转（跳过部分）
            [self confirmJumpToTime:targetTime];
        } else {
            // 向前回退
            [self confirmRewindToTime:targetTime];
        }
    } else {
        // 未录音，直接跳转播放位置
        [self.karaokeAudioEngine playFromTime:targetTime];
    }
}


- (void)startButtonTapped:(UIButton *)sender {
    if (self.isRecording) {
        // 🔧 停止录音：保存当前段落、停止录音状态、暂停BGM
        NSLog(@"🛑 用户点击停止录音");
        
        // 1. 停止录音引擎（保存当前段落）
        [self.karaokeAudioEngine stopRecording];
        
        // 2. 暂停BGM播放
        if (self.karaokeAudioEngine.isPlaying) {
            [self.karaokeAudioEngine pause];
            NSLog(@"⏸️ BGM已暂停");
        }
        
        // 3. 停止AUGraph（停止录音回调）
        Boolean isRunning = false;
        AUGraphIsRunning(self.karaokeAudioEngine.auGraph, &isRunning);
        if (isRunning) {
            CheckError(AUGraphStop(self.karaokeAudioEngine.auGraph), "AUGraphStop on stop button");
            NSLog(@"🛑 AUGraph已停止");
        }
        
        // 4. 更新状态
        self.isRecording = NO;
        
        // 5. 更新UI
        [self.startButton setTitle:@"继续录音" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
        
        // 显示完成按钮
        self.finishButton.hidden = NO;
        self.pauseButton.hidden = YES;
        self.rewindButton.hidden = NO;
        
        NSLog(@"✅ 录音已停止，可继续录音或完成");
    } else {
        // 开始/继续录音
        if (self.karaokeAudioEngine.recordingSegments.count == 0) {
            // 第一次录音，重置状态
        [self resetAudioEngineForNewRecording];
        }
        
        // 🎯 根据录音配置决定起始时间
        NSTimeInterval startTime;
        if (self.recordingConfig.mode == KaraokeRecordingModeSegment) {
            // 片段模式：从片段起点开始
            startTime = self.recordingConfig.segmentStartTime;
            NSLog(@"🎯 片段模式录音：%.2f ~ %.2f 秒", startTime, self.recordingConfig.segmentEndTime);
        } else {
            // 全曲模式：从当前滑块位置开始
            startTime = self.progressSlider.value * self.karaokeAudioEngine.duration;
            NSLog(@"🎵 全曲模式录音：从 %.2f 秒开始", startTime);
        }
        
        [self.karaokeAudioEngine playFromTime:startTime];
        [self.karaokeAudioEngine startRecordingFromTime:startTime];
        
        self.isRecording = YES;
        [self.startButton setTitle:@"停止录音" forState:UIControlStateNormal];
        self.startButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        
        // 显示控制按钮
        self.pauseButton.hidden = NO;
        self.finishButton.hidden = NO;
        self.rewindButton.hidden = NO;
        
        NSLog(@"🎤 开始录音（从 %.2f 秒）", startTime);
    }
}

// 🆕 暂停/恢复按钮
- (void)pauseButtonTapped {
    if (self.karaokeAudioEngine.isRecordingPaused) {
        // 恢复录音
        [self.karaokeAudioEngine resumeRecording];
        [self.pauseButton setTitle:@"⏸️ 暂停" forState:UIControlStateNormal];
        NSLog(@"▶️ 录音已恢复");
    } else {
        // 暂停录音
        [self.karaokeAudioEngine pauseRecording];
        [self.pauseButton setTitle:@"▶️ 恢复" forState:UIControlStateNormal];
        NSLog(@"⏸️ 录音已暂停");
    }
}

// 🆕 完成录音按钮（改为停止并进入预览模式）
- (void)finishButtonTapped {
    NSLog(@"✅ 停止录音，进入预览模式");
    
    // 如果正在录音，先停止
    if (self.karaokeAudioEngine.isRecording) {
        [self.karaokeAudioEngine stopRecording];
    }
    
    // 停止BGM
    if (self.karaokeAudioEngine.isPlaying) {
        [self.karaokeAudioEngine pause];
    }
    
    // 停止AUGraph
    Boolean isRunning = false;
    AUGraphIsRunning(self.karaokeAudioEngine.auGraph, &isRunning);
    if (isRunning) {
        CheckError(AUGraphStop(self.karaokeAudioEngine.auGraph), "AUGraphStop on finish");
    }
    
    // 进入预览模式
    [self enterPreviewMode];
}

// 🎯 片段模式自动停止录音
- (void)autoStopSegmentRecording {
    NSLog(@"🎯 片段录音自动停止");
    
    // 1. 停止录音引擎
    [self.karaokeAudioEngine stopRecording];
    
    // 2. 暂停BGM播放
    if (self.karaokeAudioEngine.isPlaying) {
        [self.karaokeAudioEngine pause];
        NSLog(@"⏸️ BGM已暂停");
    }
    
    // 3. 停止AUGraph
    Boolean isRunning = false;
    AUGraphIsRunning(self.karaokeAudioEngine.auGraph, &isRunning);
    if (isRunning) {
        CheckError(AUGraphStop(self.karaokeAudioEngine.auGraph), "AUGraphStop on auto stop");
        NSLog(@"🛑 AUGraph已停止");
    }
    
    // 4. 更新状态
    self.isRecording = NO;
    
    // 5. 更新UI
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.pauseButton.hidden = YES;
    self.finishButton.hidden = NO;
    self.rewindButton.hidden = YES;
    
    // 6. 提示用户
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ 片段录制完成"
                                                                   message:[NSString stringWithFormat:@"已录制片段：%.1f ~ %.1f 秒\n可以预览试听或重新录制", 
                                                                           self.recordingConfig.segmentStartTime,
                                                                           self.recordingConfig.segmentEndTime]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
    
    NSLog(@"✅ 片段录音已自动停止");
}

#pragma mark - 🆕 预览模式

// 进入预览模式
- (void)enterPreviewMode {
    NSLog(@"🎬 进入预览模式");
    
    self.isInPreviewMode = YES;
    
    // 隐藏录音控制按钮
    self.startButton.hidden = YES;
    self.pauseButton.hidden = YES;
    self.rewindButton.hidden = YES;
    self.finishButton.hidden = YES;
    
    // 显示预览控制面板
    [self showPreviewControlPanel];
}

// 显示预览控制面板
- (void)showPreviewControlPanel {
    if (self.previewControlView) {
        self.previewControlView.hidden = NO;
        return;
    }
    
    // 🆕 创建预览控制面板（紧凑型，放在录音按钮位置）
    CGFloat panelY = 290;
    CGFloat panelWidth = self.view.bounds.size.width - 40;
    CGFloat panelHeight = 120;  // 缩小高度
    
    self.previewControlView = [[UIView alloc] initWithFrame:CGRectMake(20, panelY, panelWidth, panelHeight)];
    self.previewControlView.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.95];
    self.previewControlView.layer.cornerRadius = 12;
    [self.view addSubview:self.previewControlView];
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] init];
    titleLabel.text = @"🎬 预览模式 - 可调整参数后试听";
    titleLabel.textColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    titleLabel.font = [UIFont boldSystemFontOfSize:16];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    titleLabel.frame = CGRectMake(0, 8, panelWidth, 22);
    [self.previewControlView addSubview:titleLabel];
    
    // 段落信息（显示合成总时长和实际录音时长）
    NSInteger segmentCount = self.karaokeAudioEngine.recordingSegments.count;
    NSTimeInterval totalDuration = [self.karaokeAudioEngine getTotalRecordedDuration];  // 合成后总时长
    NSTimeInterval vocalDuration = [self.karaokeAudioEngine getActualVocalDuration];  // 实际录音时长
    
    UILabel *infoLabel = [[UILabel alloc] init];
    // 如果有跳转（总时长 > 实际录音时长），显示两个时长
    if (totalDuration > vocalDuration + 0.5) {
        infoLabel.text = [NSString stringWithFormat:@"%ld个段落 | 合成%.1f秒 (录音%.1f秒)", 
                         (long)segmentCount, totalDuration, vocalDuration];
    } else {
        infoLabel.text = [NSString stringWithFormat:@"%ld个段落 | 录制%.1f秒", 
                         (long)segmentCount, totalDuration];
    }
    infoLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    infoLabel.font = [UIFont systemFontOfSize:12];
    infoLabel.textAlignment = NSTextAlignmentCenter;
    infoLabel.frame = CGRectMake(0, 32, panelWidth, 18);
    [self.previewControlView addSubview:infoLabel];
    
    // 🆕 提示文字
    UILabel *hintLabel = [[UILabel alloc] init];
    hintLabel.text = @"⬇️ 下方可调整BGM/麦克风/音效参数";
    hintLabel.textColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    hintLabel.font = [UIFont systemFontOfSize:11];
    hintLabel.textAlignment = NSTextAlignmentCenter;
    hintLabel.frame = CGRectMake(0, 52, panelWidth, 16);
    [self.previewControlView addSubview:hintLabel];
    
    // 按钮布局（紧凑排列）
    CGFloat buttonY = 72;
    CGFloat buttonWidth = (panelWidth - 60) / 3;
    CGFloat buttonHeight = 40;
    
    // 试听按钮
    self.previewButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
    [self.previewButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.previewButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.previewButton.layer.cornerRadius = 8;
    self.previewButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.previewButton.frame = CGRectMake(20, buttonY, buttonWidth, buttonHeight);
    [self.previewButton addTarget:self action:@selector(previewButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewControlView addSubview:self.previewButton];
    
    // 重新录制按钮
    UIButton *reRecordButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [reRecordButton setTitle:@"🔄 重录" forState:UIControlStateNormal];
    [reRecordButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reRecordButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:1.0];
    reRecordButton.layer.cornerRadius = 8;
    reRecordButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    reRecordButton.frame = CGRectMake(30 + buttonWidth, buttonY, buttonWidth, buttonHeight);
    [reRecordButton addTarget:self action:@selector(reRecordButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewControlView addSubview:reRecordButton];
    
    // 保存按钮
    self.saveButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.saveButton setTitle:@"✅ 保存" forState:UIControlStateNormal];
    [self.saveButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.saveButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.8 blue:0.4 alpha:1.0];
    self.saveButton.layer.cornerRadius = 8;
    self.saveButton.titleLabel.font = [UIFont boldSystemFontOfSize:15];
    self.saveButton.frame = CGRectMake(40 + buttonWidth * 2, buttonY, buttonWidth, buttonHeight);
    [self.saveButton addTarget:self action:@selector(saveButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.previewControlView addSubview:self.saveButton];
    
    NSLog(@"✅ 预览控制面板已显示（紧凑型，不遮挡参数控制）");
}

// 试听按钮
- (void)previewButtonTapped {
    if ([self.karaokeAudioEngine isPlayingPreview]) {
        // 正在播放，停止
        [self.karaokeAudioEngine stopPreview];
        [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
        
        // 🆕 停止UI更新定时器
        [self stopPreviewUpdateTimer];
        
        NSLog(@"🛑 停止预览");
    } else {
        // 🆕 使用当前参数重新生成预览
        NSLog(@"🎧 开始播放预览（当前参数）");
        [self.previewButton setTitle:@"⏸️ 停止" forState:UIControlStateNormal];
        
        // 🆕 启动UI更新定时器
        [self startPreviewUpdateTimer];
        
        [self.karaokeAudioEngine playPreview:^(NSError *error) {
            dispatch_async(dispatch_get_main_queue(), ^{
                // 播放完成或出错
                [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
                
                // 🆕 停止UI更新定时器
                [self stopPreviewUpdateTimer];
                
                if (error) {
                    NSLog(@"❌ 预览播放出错: %@", error);
                    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"播放失败"
                                                                                   message:error.localizedDescription
                                                                            preferredStyle:UIAlertControllerStyleAlert];
                    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:alert animated:YES completion:nil];
                } else {
                    NSLog(@"✅ 预览播放完成");
                }
            });
        }];
    }
}

// 重新录制按钮
- (void)reRecordButtonTapped {
    NSLog(@"🔄 重新录制");
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"重新录制"
                                                                   message:@"确定要清空当前录音并重新开始吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"重新录制" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        // 停止预览
        if ([self.karaokeAudioEngine isPlayingPreview]) {
            [self.karaokeAudioEngine stopPreview];
        }
        
        // 退出预览模式（会自动清空缓存）
        [self exitPreviewMode];
        
        // 重置引擎
        [self resetAudioEngineForNewRecording];
        
        // 重置UI
        [self resetToInitialState];
        
        NSLog(@"✅ 已重置，可以重新录音");
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 保存按钮
- (void)saveButtonTapped {
    NSLog(@"💾 保存录音文件");
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"保存录音"
                                                                   message:@"确定要保存这个录音吗？"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"保存" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        // 显示保存中
        UIAlertController *savingAlert = [UIAlertController alertControllerWithTitle:@"保存中..."
                                                                               message:@"正在生成文件，请稍候"
                                                                        preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:savingAlert animated:YES completion:nil];
        
        // 异步保存
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            [self.karaokeAudioEngine savePreviewToFile:^(NSString *filePath, NSError *error) {
                dispatch_async(dispatch_get_main_queue(), ^{
                    [savingAlert dismissViewControllerAnimated:YES completion:^{
                        if (error) {
                            NSLog(@"❌ 保存失败: %@", error);
                            UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"保存失败"
                                                                                               message:error.localizedDescription
                                                                                        preferredStyle:UIAlertControllerStyleAlert];
                            [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                            [self presentViewController:errorAlert animated:YES completion:nil];
                        } else {
                            NSLog(@"✅ 保存成功: %@", filePath);
                            
                            // 1. 🆕 保存文件路径（重要：在reset之前保存，因为reset会清空recordingFilePath）
                            NSString *savedRecordingPath = filePath;
                            
                            // 2. 退出预览模式（会自动清空缓存和重置UI参数）
                            [self exitPreviewMode];
                            
                            // 3. 🆕 重置音频引擎（重要：清空录音段落、重置BGM位置等）
                            [self resetAudioEngineForNewRecording];
                            
                            // 4. 重置UI状态（重要：必须在显示对话框之前，确保进度条等都归零）
                            [self resetToInitialState];
                            
                            // 5. 最后显示回放对话框（使用保存的文件路径）
                            if (savedRecordingPath && [[NSFileManager defaultManager] fileExistsAtPath:savedRecordingPath]) {
                                [self showPlaybackViewForFile:savedRecordingPath];
                            } else {
                                NSLog(@"⚠️ 录音文件路径无效，跳过回放");
                            }
                        }
                    }];
                });
            }];
        });
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 退出预览模式
- (void)exitPreviewMode {
    NSLog(@"🚪 退出预览模式");
    
    self.isInPreviewMode = NO;
    
    // 🆕 停止预览UI更新定时器
    [self stopPreviewUpdateTimer];
    
    // 🆕 停止防抖定时器
    [self.parameterUpdateDebounceTimer invalidate];
    self.parameterUpdateDebounceTimer = nil;
    
    // 停止预览播放
    if ([self.karaokeAudioEngine isPlayingPreview]) {
        [self.karaokeAudioEngine stopPreview];
    }
    
    // 🆕 清空预览缓存
    [self.karaokeAudioEngine invalidatePreviewCache];
    NSLog(@"🗑️ 预览缓存已清空");
    
    // 🆕 重置预览按钮状态
    if (self.previewButton) {
        [self.previewButton setTitle:@"🎧 试听" forState:UIControlStateNormal];
    }
    
    // 隐藏预览控制面板
    if (self.previewControlView) {
        self.previewControlView.hidden = YES;
    }
    
    // 显示录音控制按钮
    self.startButton.hidden = NO;
    
    // 🆕 重置参数控制面板到默认值
    [self resetParameterControls];
}

// 🆕 重置参数控制面板到默认值
- (void)resetParameterControls {
    NSLog(@"🔄 重置参数控制面板到默认值");
    
    // 1. 重置耳返开关和音量
    if (self.earReturnSwitch) {
        self.earReturnSwitch.on = NO;
        [self.karaokeAudioEngine setEarReturnEnabled:NO];
    }
    if (self.earReturnVolumeSlider) {
        self.earReturnVolumeSlider.value = 0.5;
        [self.karaokeAudioEngine setEarReturnVolume:0.5];
        self.earReturnVolumeLabel.text = @"耳返音量: 50%";
    }
    
    // 2. 重置麦克风音量
    if (self.microphoneVolumeSlider) {
        self.microphoneVolumeSlider.value = 1.0;
        [self.karaokeAudioEngine setMicrophoneVolume:1.0];
        self.microphoneVolumeLabel.text = @"麦克风音量: 100%";
    }
    
    // 3. 重置BGM音量
    if (self.bgmVolumeSlider) {
        self.bgmVolumeSlider.value = 0.3;
        if (self.karaokeAudioEngine) {
            self.karaokeAudioEngine.bgmVolume = 0.3;
        }
        self.bgmVolumeLabel.text = @"🎵 BGM音量: 30%";
    }
    
    // 4. 重置音效为原声
    if (self.karaokeAudioEngine.voiceEffectProcessor) {
        [self.karaokeAudioEngine.voiceEffectProcessor setPresetEffect:VoiceEffectTypeNone];
        [self.voiceEffectButton setTitle:@"🎤 音效：原声" forState:UIControlStateNormal];
    }
    
    // 5. 关闭音效选择器（如果打开）
    if (self.effectSelectorView && !self.effectSelectorView.hidden) {
        self.effectSelectorView.hidden = YES;
    }
    
    // 6. 关闭AGC设置面板（如果打开）
    if (self.agcSettingsView && !self.agcSettingsView.hidden) {
        self.agcSettingsView.hidden = YES;
    }
    
    NSLog(@"✅ 参数控制面板已重置到默认值");
}

// 🆕 重置到初始状态
- (void)resetToInitialState {
    NSLog(@"🔄 重置所有状态到初始状态");
    
    // 1. 重置录音状态
    self.isRecording = NO;
    
    // 2. 重置UI按钮
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    self.pauseButton.hidden = YES;
    self.finishButton.hidden = YES;
    self.rewindButton.hidden = YES;
    
    // 🎯 重置片段选择配置
    [self.recordingConfig resetToFullMode];
    [self.segmentSelectorButton setTitle:@"📍 选片段" forState:UIControlStateNormal];
    self.segmentSelectorButton.backgroundColor = [UIColor colorWithRed:1.0 green:0.6 blue:0.0 alpha:0.8];
    
    // 3. 重置段落信息
    self.segmentInfoLabel.text = @"";
    
    // 4. 重置进度条到开头
    self.progressSlider.value = 0.0;
    
    // 5. 重置时间显示
    if (self.karaokeAudioEngine && self.karaokeAudioEngine.duration > 0) {
        NSTimeInterval duration = self.karaokeAudioEngine.duration;
        self.durationLabel.text = [NSString stringWithFormat:@"0:00 / %@", [self formatTime:duration]];
    }
    
    // 6. 重置歌词到开头
    if (self.lyricsView) {
        [self.lyricsView updateWithTime:0.0];
        [self.lyricsView reset];
    }
    
    // 7. 重置VU表
    self.rmsProgressView.progress = 0.0;
    self.peakProgressView.progress = 0.0;
    
    // 8. 🆕 重置参数控制面板（防御性编程，确保参数被重置）
    [self resetParameterControls];
    
    NSLog(@"✅ 状态重置完成");
}

// 🆕 回退按钮
- (void)rewindButtonTapped {
    if (!self.karaokeAudioEngine || self.karaokeAudioEngine.duration <= 0) {
        return;
    }
    
    NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
    NSTimeInterval targetTime = MAX(0, currentTime - 10.0);
    
    [self confirmRewindToTime:targetTime];
}

// 🆕 确认跳转
- (void)confirmJumpToTime:(NSTimeInterval)targetTime {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"跳转确认"
                                                                   message:[NSString stringWithFormat:@"跳转到 %@？\n跳过的部分将填充纯BGM", [self formatTime:targetTime]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"跳转" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self.karaokeAudioEngine jumpToTime:targetTime];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

// 🆕 确认回退
- (void)confirmRewindToTime:(NSTimeInterval)targetTime {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"回退确认"
                                                                   message:[NSString stringWithFormat:@"回退到 %@？\n之后的录音将被删除", [self formatTime:targetTime]]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" style:UIAlertActionStyleCancel handler:nil]];
    [alert addAction:[UIAlertAction actionWithTitle:@"回退" style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [self.karaokeAudioEngine rewindToTime:targetTime];
    }]];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)resetAudioEngineForNewRecording {
    if (!self.karaokeAudioEngine) {
        return;
    }
    
    NSLog(@"🔄 重置音频引擎，准备新的录音...");
    
    // 1. 确保之前的录音已停止
    if (self.karaokeAudioEngine.isRecording) {
        [self.karaokeAudioEngine stopRecording];
    }
    
    // 2. 确保播放已停止
    if (self.karaokeAudioEngine.isPlaying) {
        [self.karaokeAudioEngine stop];
    }
    
    // 3. 调用reset方法重置状态（会重置BGM位置、AUGraph等）
    [self.karaokeAudioEngine reset];
    
    NSLog(@"✅ 音频引擎已重置");
}

- (void)startKaraokeSession {
    // 使用新的音频引擎开始播放和录音
    if (self.karaokeAudioEngine) {
        [self.karaokeAudioEngine play];
        [self.karaokeAudioEngine startRecording];
        self.isRecording = YES;
        NSLog(@"🎤 卡拉OK会话开始 - 播放和录音同时进行");
    } else {
        // 回退到原来的录音方式
        [self startRecording];
    }
}

- (void)backButtonTapped {
    [self.navigationController popViewControllerAnimated:YES];
}

- (void)showRecordingList {
    NSLog(@"📝 打开录音列表");
    RecordingListViewController *listVC = [[RecordingListViewController alloc] init];
    [self.navigationController pushViewController:listVC animated:YES];
}

#pragma mark - Recording

- (void)startRecording {
    NSLog(@"🎤 尝试开始录音...");
    
    // 检查麦克风权限
    AVAudioSessionRecordPermission permission = [self.audioSession recordPermission];
    NSLog(@"   麦克风权限状态: %ld", (long)permission);
    
    // 权限状态值：0=未决定, 1=拒绝, 2=授权
    if (permission == AVAudioSessionRecordPermissionDenied) {
        NSLog(@"❌ 麦克风权限被拒绝");
        [self showMicrophonePermissionAlert];
        return;
    } else if (permission == AVAudioSessionRecordPermissionUndetermined) {
        NSLog(@"❌ 麦克风权限未决定，重新请求");
        [self.audioSession requestRecordPermission:^(BOOL granted) {
            dispatch_async(dispatch_get_main_queue(), ^{
                if (granted) {
                    [self startRecording];
                } else {
                    [self showMicrophonePermissionAlert];
                }
            });
        }];
        return;
    } else if (permission != AVAudioSessionRecordPermissionGranted) {
        NSLog(@"❌ 麦克风权限状态异常: %ld", (long)permission);
        [self showMicrophonePermissionAlert];
        return;
    }
    
    // 检查录音器是否已创建
    if (!self.audioRecorder) {
        NSLog(@"❌ 录音器未创建");
        [self showRecordingErrorAlert:@"录音器未初始化，请重新进入页面"];
        return;
    }
    
    // 检查录音器是否准备就绪
    if (![self.audioRecorder prepareToRecord]) {
        NSLog(@"❌ 录音器准备失败");
        [self showRecordingErrorAlert:@"录音器准备失败，请检查设备状态"];
        return;
    }
    
    // 开始录音
    BOOL success = [self.audioRecorder record];
    if (success) {
        self.isRecording = YES;
        NSLog(@"✅ 录音开始成功: %@", self.recordingFilePath);
    } else {
        NSLog(@"❌ 录音启动失败");
        [self showRecordingErrorAlert:@"无法开始录音，请检查麦克风权限和设备状态"];
    }
}

- (void)showRecordingErrorAlert:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"录音失败" 
                                                                   message:message 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)stopRecording {
    if (self.isRecording) {
        if (self.karaokeAudioEngine) {
            [self.karaokeAudioEngine stop];
            [self.karaokeAudioEngine stopRecording];
            self.recordingFilePath = [self.karaokeAudioEngine getRecordingFilePath];
        } else {
            [self.audioRecorder stop];
        }
        self.isRecording = NO;
        NSLog(@"🛑 录音停止: %@", self.recordingFilePath);
    }
}

- (void)showRecordingPlaybackDialog {
    // 获取录音文件路径
    NSString *recordingPath = [self.karaokeAudioEngine getRecordingFilePath];
    if (!recordingPath || ![[NSFileManager defaultManager] fileExistsAtPath:recordingPath]) {
        [self showAlertWithTitle:@"错误" message:@"录音文件不存在"];
        return;
    }
    
    NSLog(@"📂 录音文件路径: %@", recordingPath);
    
    // 移除旧的回放视图（如果存在）
    if (self.recordingPlaybackView) {
        [self.recordingPlaybackView removeFromSuperview];
        self.recordingPlaybackView = nil;
    }
    
    // 创建RecordingPlaybackView
    CGFloat viewHeight = 300;
    CGFloat viewY = (self.view.bounds.size.height - viewHeight) / 2;
    
    self.recordingPlaybackView = [[RecordingPlaybackView alloc] initWithFrame:CGRectMake(20, viewY, 
                                                                                          self.view.bounds.size.width - 40, 
                                                                                          viewHeight)];
    self.recordingPlaybackView.filePath = recordingPath;
    
    // 设置回调
    __weak typeof(self) weakSelf = self;
    self.recordingPlaybackView.onClose = ^{
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
    };
    
    self.recordingPlaybackView.onDelete = ^(NSString *path) {
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
        [weakSelf showAlertWithTitle:@"删除成功" message:@"录音已删除"];
    };
    
    self.recordingPlaybackView.onExport = ^(NSString *path) {
        NSLog(@"📤 导出录音: %@", path);
    };
    
    [self.view addSubview:self.recordingPlaybackView];
    
    NSLog(@"✅ 录音回放视图已显示");
}

#pragma mark - 混音处理

- (void)mixRecordingWithBGM {
    // 获取录音文件路径
    NSString *vocalPath = [self.karaokeAudioEngine getRecordingFilePath];
    if (!vocalPath || ![[NSFileManager defaultManager] fileExistsAtPath:vocalPath]) {
        [self showAlertWithTitle:@"错误" message:@"录音文件不存在"];
        return;
    }
    
    // 🔧 获取BGM文件路径（优先使用完整路径）
    NSString *bgmPath = self.currentSongPath;
    
    // 如果没有完整路径，尝试从 Bundle 查找
    if (!bgmPath || ![[NSFileManager defaultManager] fileExistsAtPath:bgmPath]) {
        bgmPath = [[NSBundle mainBundle] pathForResource:self.currentSongName ofType:nil];
    }
    
    if (!bgmPath || ![[NSFileManager defaultManager] fileExistsAtPath:bgmPath]) {
        NSLog(@"⚠️ 未找到BGM文件，只保存纯人声");
        [self showRecordingPlaybackDialog];
        return;
    }
    
    NSLog(@"🎵 BGM文件路径: %@", bgmPath);
    
    // 显示处理提示
    UIAlertController *processingAlert = [UIAlertController alertControllerWithTitle:@"🎵 正在处理"
                                                                             message:@"正在混合人声和背景音乐，请稍候..."
                                                                      preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:processingAlert animated:YES completion:nil];
    
    // 生成混音输出文件名
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
    NSString *documentsDirectory = [paths objectAtIndex:0];
    NSString *fileName = [NSString stringWithFormat:@"karaoke_mixed_%ld.pcm", (long)[[NSDate date] timeIntervalSince1970]];
    NSString *mixedPath = [documentsDirectory stringByAppendingPathComponent:fileName];
    
    NSLog(@"🎵 开始混音:");
    NSLog(@"   人声: %@", vocalPath);
    NSLog(@"   BGM: %@", bgmPath);
    NSLog(@"   输出: %@", mixedPath);
    
    // 执行混音
    [AudioMixer mixVocalFile:vocalPath
                 withBGMFile:bgmPath
                outputToFile:mixedPath
                 vocalVolume:1.0  // 人声100%
                   bgmVolume:0.3  // BGM 30% (与播放时一致)
                  completion:^(BOOL success, NSError * _Nullable error) {
        // 关闭处理提示
        [processingAlert dismissViewControllerAnimated:YES completion:^{
            if (success) {
                NSLog(@"✅ 混音成功: %@", mixedPath);
                
                // 可选：删除原始人声文件（只保留混音文件）
                // [[NSFileManager defaultManager] removeItemAtPath:vocalPath error:nil];
                
                // 显示混音后的文件
                [self showPlaybackViewForFile:mixedPath];
            } else {
                NSLog(@"❌ 混音失败: %@", error.localizedDescription);
                [self showAlertWithTitle:@"混音失败"
                                 message:[NSString stringWithFormat:@"%@\n将显示纯人声录音", error.localizedDescription]];
                
                // 失败时显示原始人声录音
                [self showRecordingPlaybackDialog];
            }
        }];
    }];
}

- (void)showPlaybackViewForFile:(NSString *)filePath {
    // 移除旧的回放视图（如果存在）
    if (self.recordingPlaybackView) {
        [self.recordingPlaybackView removeFromSuperview];
        self.recordingPlaybackView = nil;
    }
    
    // 创建RecordingPlaybackView
    CGFloat viewHeight = 300;
    CGFloat viewY = (self.view.bounds.size.height - viewHeight) / 2;
    
    self.recordingPlaybackView = [[RecordingPlaybackView alloc] initWithFrame:CGRectMake(20, viewY,
                                                                                          self.view.bounds.size.width - 40,
                                                                                          viewHeight)];
    self.recordingPlaybackView.filePath = filePath;
    
    // 设置回调
    __weak typeof(self) weakSelf = self;
    self.recordingPlaybackView.onClose = ^{
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
    };
    
    self.recordingPlaybackView.onDelete = ^(NSString *path) {
        [weakSelf.recordingPlaybackView removeFromSuperview];
        weakSelf.recordingPlaybackView = nil;
        [weakSelf showAlertWithTitle:@"删除成功" message:@"录音已删除"];
    };
    
    self.recordingPlaybackView.onExport = ^(NSString *path) {
        NSLog(@"📤 导出录音: %@", path);
    };
    
    [self.view addSubview:self.recordingPlaybackView];
    
    NSLog(@"✅ 录音回放视图已显示");
}

- (void)showAlertWithTitle:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)showRecordingCompleteAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"录音完成" 
                                                                   message:[NSString stringWithFormat:@"录音文件已保存到:\n%@", self.recordingFilePath]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AudioSpectrumPlayerDelegate

- (void)playerDidGenerateSpectrum:(NSArray *)spectrums {
    // 性能优化：录音时不显示频谱特效，避免性能占用
    // dispatch_async(dispatch_get_main_queue(), ^{
    //     [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];
    // });
}

- (void)didFinishPlay {
    // 歌曲播放完成
    [self stopRecording];
    [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
    self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"歌曲播放完成" 
                                                                   message:@"录音已自动停止" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - AVAudioRecorderDelegate

- (void)audioRecorderDidFinishRecording:(AVAudioRecorder *)recorder successfully:(BOOL)flag {
    if (flag) {
        NSLog(@"✅ 录音成功完成");
    } else {
        NSLog(@"❌ 录音失败");
    }
}

- (void)audioRecorderEncodeErrorDidOccur:(AVAudioRecorder *)recorder error:(NSError *)error {
    NSLog(@"❌ 录音编码错误: %@", error.localizedDescription);
}

#pragma mark - 耳返控制事件

- (void)earReturnSwitchChanged:(UISwitch *)sender {
    NSLog(@"🎧 耳返开关改变: %@", sender.on ? @"开启" : @"关闭");
    if (self.karaokeAudioEngine) {
        @try {
            [self.karaokeAudioEngine setEarReturnEnabled:sender.on];
        } @catch (NSException *exception) {
            NSLog(@"❌ 设置耳返开关异常: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ 卡拉OK音频引擎未初始化");
    }
}

- (void)earReturnVolumeChanged:(UISlider *)sender {
    NSLog(@"🎧 耳返音量滑块改变: %.0f%%", sender.value * 100);
    if (self.karaokeAudioEngine) {
        @try {
            [self.karaokeAudioEngine setEarReturnVolume:sender.value];
        } @catch (NSException *exception) {
            NSLog(@"❌ 设置耳返音量异常: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ 卡拉OK音频引擎未初始化");
    }
}

- (void)microphoneVolumeChanged:(UISlider *)sender {
    NSLog(@"🎤 麦克风音量滑块改变: %.0f%%", sender.value * 100);
    if (self.karaokeAudioEngine) {
        @try {
            [self.karaokeAudioEngine setMicrophoneVolume:sender.value];
            
            // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
            if (self.isInPreviewMode) {
                [self scheduleParameterUpdateWithDelay];
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ 设置麦克风音量异常: %@", exception.reason);
        }
    } else {
        NSLog(@"⚠️ 卡拉OK音频引擎未初始化");
    }
}

- (void)bgmVolumeChanged:(UISlider *)sender {
    NSLog(@"🎵 BGM音量滑块改变: %.0f%%", sender.value * 100);
    if (self.karaokeAudioEngine) {
        self.karaokeAudioEngine.bgmVolume = sender.value;
        NSLog(@"✅ BGM音量已设置为: %.0f%%", sender.value * 100);
        
        // 更新标签
        self.bgmVolumeLabel.text = [NSString stringWithFormat:@"🎵 BGM音量: %.0f%%", sender.value * 100];
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
}

// 🆕 BGM音高调整
- (void)bgmPitchChanged:(UISlider *)sender {
    float pitchValue = roundf(sender.value);  // 四舍五入到整数半音
    sender.value = pitchValue;  // 更新滑块到整数位置
    
    NSLog(@"🎵 BGM音高滑块改变: %.0f 半音", pitchValue);
    if (self.karaokeAudioEngine) {
        self.karaokeAudioEngine.bgmPitchShift = pitchValue;
        NSLog(@"✅ BGM音高已设置为: %.0f 半音", pitchValue);
        
        // 更新标签
        NSString *pitchText;
        if (pitchValue > 0) {
            pitchText = [NSString stringWithFormat:@"🎵 BGM音高: +%.0f", pitchValue];
        } else if (pitchValue < 0) {
            pitchText = [NSString stringWithFormat:@"🎵 BGM音高: %.0f", pitchValue];
        } else {
            pitchText = @"🎵 BGM音高: 0";
        }
        self.bgmPitchLabel.text = pitchText;
        
        // 🆕 如果在预览模式且正在播放，使用防抖延迟更新
        if (self.isInPreviewMode) {
            [self scheduleParameterUpdateWithDelay];
        }
    }
}

#pragma mark - 🆕 防抖和预览更新

// 防抖：延迟触发参数更新（避免拖动时频繁重新生成）
- (void)scheduleParameterUpdateWithDelay {
    // 取消之前的定时器
    [self.parameterUpdateDebounceTimer invalidate];
    
    // 创建新的定时器：500ms后触发
    self.parameterUpdateDebounceTimer = [NSTimer scheduledTimerWithTimeInterval:0.5
                                                                         repeats:NO
                                                                           block:^(NSTimer *timer) {
        NSLog(@"⏱️ 防抖定时器触发，开始更新参数...");
        if (self.isInPreviewMode) {
            [self.karaokeAudioEngine updatePreviewParametersIfPlaying];
        }
    }];
    
    NSLog(@"⏱️ 已安排防抖更新（500ms后执行）");
}

// 启动预览模式的UI更新定时器
- (void)startPreviewUpdateTimer {
    // 停止之前的定时器
    [self stopPreviewUpdateTimer];
    
    // 创建新定时器：30fps更新
    self.previewUpdateTimer = [NSTimer scheduledTimerWithTimeInterval:1.0/30.0
                                                               repeats:YES
                                                                 block:^(NSTimer *timer) {
        [self updatePreviewUI];
    }];
    
    NSLog(@"⏱️ 预览模式UI更新定时器已启动");
}

// 停止预览模式的UI更新定时器
- (void)stopPreviewUpdateTimer {
    if (self.previewUpdateTimer) {
        [self.previewUpdateTimer invalidate];
        self.previewUpdateTimer = nil;
        NSLog(@"⏱️ 预览模式UI更新定时器已停止");
    }
}

// 更新预览模式的UI（进度条、歌词）
- (void)updatePreviewUI {
    if (![self.karaokeAudioEngine isPlayingPreview]) {
        return;
    }
    
    // 获取预览播放器的当前时间
    NSTimeInterval currentTime = [self.karaokeAudioEngine currentPreviewTime];
    NSTimeInterval duration = [self.karaokeAudioEngine previewDuration];
    
    // 更新进度条
    if (duration > 0) {
        self.progressSlider.value = currentTime / duration;
    }
    
    // 更新歌词
    [self.lyricsView updateWithTime:currentTime];
}

#pragma mark - LyricsViewDelegate

// 🆕 歌词点击代理方法
- (void)lyricsView:(LyricsView *)lyricsView didTapLyricAtTime:(NSTimeInterval)time text:(NSString *)text index:(NSInteger)index {
    NSLog(@"🎵 用户点击歌词: 索引=%ld, 时间=%.2f秒, 文本=%@", (long)index, time, text);
    
    if (!self.karaokeAudioEngine || self.karaokeAudioEngine.duration <= 0) {
        NSLog(@"⚠️ BGM未加载，无法跳转");
        return;
    }
    
    // 如果正在录音，需要确认跳转/回退
    if (self.karaokeAudioEngine.isRecording) {
        NSTimeInterval currentTime = self.karaokeAudioEngine.currentPlaybackTime;
        
        if (time > currentTime) {
            // 向后跳转（跳过部分）
            [self confirmJumpToTime:time];
        } else {
            // 向前回退
            [self confirmRewindToTime:time];
        }
    } else {
        // 未录音，直接跳转播放位置
        [self.karaokeAudioEngine playFromTime:time];
        
        // 更新进度条
        if (self.karaokeAudioEngine.duration > 0) {
            self.progressSlider.value = time / self.karaokeAudioEngine.duration;
        }
        
        // 立即更新歌词显示
        [self.lyricsView updateWithTime:time];
        
        NSLog(@"✅ 已跳转到 %.2f 秒", time);
    }
}

#pragma mark - KaraokeAudioEngineDelegate

- (void)audioEngineDidUpdateMicrophoneLevel:(float)level {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.rmsProgressView.progress = level;
    });
}

- (void)audioEngineDidUpdatePeakLevel:(float)peak {
    dispatch_async(dispatch_get_main_queue(), ^{
        self.peakProgressView.progress = peak;
    });
}

// 🆕 录音段落更新回调
- (void)audioEngineDidUpdateRecordingSegments:(NSArray<RecordingSegment *> *)segments {
    dispatch_async(dispatch_get_main_queue(), ^{
        // 更新段落信息显示
        if (segments.count == 0) {
            self.segmentInfoLabel.text = @"";
        } else {
            NSInteger recordedSegments = 0;
            NSTimeInterval totalDuration = 0;
            
            for (RecordingSegment *segment in segments) {
                if (segment.isRecorded) {
                    recordedSegments++;
                }
                totalDuration += segment.duration;
            }
            
            self.segmentInfoLabel.text = [NSString stringWithFormat:@"已录制 %ld 段落 | 总时长 %@",
                                          (long)recordedSegments,
                                          [self formatTime:totalDuration]];
        }
        
        NSLog(@"📊 段落更新: %lu 个段落", (unsigned long)segments.count);
    });
}

- (void)audioEngineDidFinishPlaying {
    dispatch_async(dispatch_get_main_queue(), ^{
        NSLog(@"🎵 收到BGM播放完成通知，自动结束录音会话");
        
        if (self.isRecording) {
            self.isRecording = NO;
            
            // 更新UI
            [self.startButton setTitle:@"开始录音" forState:UIControlStateNormal];
            self.startButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.6 blue:1.0 alpha:1.0];
            self.pauseButton.hidden = YES;
            self.finishButton.hidden = NO;
            self.rewindButton.hidden = NO;
            
            NSLog(@"💡 提示：可以点击按钮合成最终录音");
        }
    });
}

- (void)audioEngineDidEncounterError:(NSError *)error {
    NSLog(@"❌ 卡拉OK音频引擎错误: %@", error.localizedDescription);
}

@end
