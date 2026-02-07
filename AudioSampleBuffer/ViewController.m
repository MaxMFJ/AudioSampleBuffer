//
//  ViewController.m
//  AudioSampleBuffer
//
//  Created by gt on 2022/9/7.
//

#import "ViewController.h"
#import "AudioPlayCell.h"
#import "AudioSpectrumPlayer.h"
#import "SpectrumView.h"
#import "TTi.h"
#import "AnimationCoordinator.h"
#import "VisualEffectManager.h"
#import "GalaxyControlPanel.h"
#import "CyberpunkControlPanel.h"
#import "PerformanceControlPanel.h"
#import "LyricsView.h"
#import "LRCParser.h"
#import "LyricsEffectControlPanel.h"
#import "LyricsManager.h"  // 📝 歌词管理器
#import "AudioFileFormats.h"  // 🆕 音频格式工具
#import "KaraokeViewController.h"
#import "MusicLibraryManager.h"  // 🆕 音乐库管理器
#import "ViewController+CloudDownload.h"  // 🆕 云端下载功能
#import "ViewController+PlaybackProgress.h"  // 🆕 播放进度条功能
#import "VinylRecordView.h"  // 🎵 黑胶唱片动画视图
#import "LyricsEditorViewController.h"  // 🎼 歌词打轴编辑器
#import <AVFoundation/AVFoundation.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>  // 用于文件类型识别
#import <MediaPlayer/MediaPlayer.h>  // 🎵 系统媒体控制

@interface ViewController ()<CAAnimationDelegate,UITableViewDelegate, UITableViewDataSource, AudioSpectrumPlayerDelegate, VisualEffectManagerDelegate, GalaxyControlDelegate, CyberpunkControlDelegate, PerformanceControlDelegate, LyricsEffectControlDelegate, UISearchBarDelegate, UIDocumentPickerDelegate, LyricsEditorViewControllerDelegate>
{
    BOOL enterBackground;
    NSInteger index;
    CAShapeLayer *backLayers;
    UIImageView * imageView ;
}
@property (nonatomic, strong) UITableView *tableView;
@property (nonatomic, strong) NSMutableArray *audioArray;  // 保留用于兼容性
@property (nonatomic, strong) AudioSpectrumPlayer *player;
@property (nonatomic, strong) SpectrumView *spectrumView;

// 🆕 音乐库管理器相关
@property (nonatomic, strong) MusicLibraryManager *musicLibrary;
@property (nonatomic, strong) NSArray<MusicItem *> *displayedMusicItems;  // 当前显示的音乐列表
@property (nonatomic, assign) MusicCategory currentCategory;  // 当前分类
@property (nonatomic, strong) NSMutableArray<UIButton *> *categoryButtons;  // 分类按钮数组
@property (nonatomic, strong) UISearchBar *searchBar;  // 搜索栏
@property (nonatomic, strong) UIButton *sortButton;  // 排序按钮
@property (nonatomic, strong) UIButton *reloadButton;  // 刷新音乐库按钮
@property (nonatomic, strong) UIButton *importButton;  // 导入音乐按钮
@property (nonatomic, assign) MusicSortType currentSortType;  // 当前排序方式
@property (nonatomic, assign) BOOL sortAscending;  // 排序方向

// 🎵 播放控制按钮
@property (nonatomic, strong) UIButton *previousButton;  // 上一首按钮
@property (nonatomic, strong) UIButton *playPauseButton;  // 播放/暂停按钮
@property (nonatomic, strong) UIButton *nextButton;  // 下一首按钮
@property (nonatomic, strong) UIButton *loopButton;  // 单曲循环按钮
@property (nonatomic, assign) BOOL isSingleLoopMode;  // 是否单曲循环模式


@property (nonatomic, strong) CAGradientLayer *gradientLayer;
@property (nonatomic, strong) NSTimer *timer;
@property (nonatomic, assign) NSInteger iu;
@property (nonatomic, assign) UIBezierPath *circlePath;
@property(nonatomic,strong)CALayer * xlayer;
@property(nonatomic,strong)CAEmitterLayer *leafEmitter;

// 新的动画系统
@property (nonatomic, strong) AnimationCoordinator *animationCoordinator;

// 高端视觉效果系统
@property (nonatomic, strong) VisualEffectManager *visualEffectManager;
@property (nonatomic, strong) UIButton *effectSelectorButton;
@property (nonatomic, strong) GalaxyControlPanel *galaxyControlPanel;
@property (nonatomic, strong) UIButton *galaxyControlButton;
@property (nonatomic, strong) CyberpunkControlPanel *cyberpunkControlPanel;
@property (nonatomic, strong) UIButton *cyberpunkControlButton;
@property (nonatomic, strong) PerformanceControlPanel *performanceControlPanel;
@property (nonatomic, strong) UIButton *performanceControlButton;

// FPS显示器
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) CADisplayLink *fpsDisplayLink;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) CFTimeInterval lastTimestamp;

// 歌词视图
@property (nonatomic, strong) LyricsView *lyricsView;
@property (nonatomic, strong) UIView *lyricsContainer;

// 卡拉OK按钮
@property (nonatomic, strong) UIButton *karaokeButton;

// 歌词特效控制
@property (nonatomic, strong) LyricsEffectControlPanel *lyricsEffectPanel;
@property (nonatomic, strong) UIButton *lyricsEffectButton;
@property (nonatomic, strong) UIButton *importLyricsButton;  // 📝 导入歌词按钮
@property (nonatomic, strong) UIButton *lyricsTimingButton;  // 🎼 歌词打轴按钮

// UI控制
@property (nonatomic, strong) UIButton *toggleUIButton;  // 一键显示/隐藏UI按钮
@property (nonatomic, assign) BOOL isUIHidden;  // UI是否隐藏
@property (nonatomic, strong) NSMutableArray<UIButton *> *controlButtons;  // 所有控制按钮数组
@property (nonatomic, strong) UIButton *cloudButton;  // 云端按钮

// 🔊 混音控制
@property (nonatomic, strong) UIView *mixAudioControlView;  // 混音控制容器视图
@property (nonatomic, strong) UISwitch *mixAudioSwitch;  // 混音控制开关

// 🎵 系统媒体控制
@property (nonatomic, assign) NSTimeInterval lastNowPlayingUpdateTime;  // 上次更新系统媒体信息的时间

// 🎵 黑胶唱片视图（用于没有封面的歌曲）
@property (nonatomic, strong) VinylRecordView *vinylRecordView;
@property (nonatomic, assign) BOOL isShowingVinylRecord;  // 是否正在显示黑胶唱片

// 🔧 播放状态跟踪（用于防止意外恢复播放）
@property (nonatomic, assign) BOOL wasPlayingBeforeInterruption;  // 中断前是否正在播放
@property (nonatomic, assign) BOOL shouldPreventAutoResume;  // 是否禁止自动恢复播放
@end

@implementation ViewController
- (void)hadEnterBackGround{
    NSLog(@"进入后台");
    enterBackground =  YES;
    [self.animationCoordinator applicationDidEnterBackground];
    
    // 🔋 关键修复：进入后台时完全停止Metal渲染，避免持续发热和耗电
    [self.visualEffectManager pauseRendering];
    
    // 暂停Metal视图的更新
    if (self.visualEffectManager.metalView) {
        self.visualEffectManager.metalView.paused = YES;
        NSLog(@"✅ Metal视图已暂停");
    }
    
    // 停止FPS监控以节省资源
    if (self.fpsDisplayLink) {
        self.fpsDisplayLink.paused = YES;
        NSLog(@"✅ FPS监控已暂停");
    }
    
    // 暂停频谱视图
    if (self.spectrumView) {
        [self.spectrumView pauseRendering];
        NSLog(@"✅ 频谱视图已暂停");
    }
    
    // 🎵 关键：进入后台时确保音频会话保持激活，更新播放信息
    NSLog(@"🎵 检查播放状态: isPlaying=%@", self.player.isPlaying ? @"YES" : @"NO");
    
    if (self.player && self.player.isPlaying) {
        NSLog(@"🎵 后台音乐播放: 保持音频会话激活");
        
        // 🔊 重要：不要在这里直接设置音频会话，避免覆盖混音设置
        // 音频会话由 AudioSpectrumPlayer 管理，已经在播放时正确配置
        
        // 更新播放信息，确保控制中心显示
        [self updateNowPlayingInfo];
        
        // 验证播放信息
        NSDictionary *nowPlaying = [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo;
        NSLog(@"✅ 后台播放信息已更新:");
        NSLog(@"   - 标题: %@", nowPlaying[MPMediaItemPropertyTitle]);
        NSLog(@"   - 播放速率: %@", nowPlaying[MPNowPlayingInfoPropertyPlaybackRate]);
    } else {
        NSLog(@"⚠️ 进入后台时没有音乐在播放");
    }
    
    // 🎵 暂停黑胶唱片动画以节省资源
    if (self.isShowingVinylRecord) {
        [self.vinylRecordView pauseSpinning];
        NSLog(@"✅ 黑胶唱片动画已暂停");
    }
}

- (void)hadEnterForeGround{
    NSLog(@"回到app");
    enterBackground = NO;
    [self.animationCoordinator applicationDidBecomeActive];
    [self.visualEffectManager resumeRendering];
    
    // 恢复Metal视图的更新
    if (self.visualEffectManager.metalView) {
        self.visualEffectManager.metalView.paused = NO;
        NSLog(@"✅ Metal视图已恢复");
    }
    
    // 恢复FPS监控
    if (self.fpsDisplayLink) {
        self.fpsDisplayLink.paused = NO;
        NSLog(@"✅ FPS监控已恢复");
    }
    
    // 恢复频谱视图
    if (self.spectrumView) {
        [self.spectrumView resumeRendering];
        NSLog(@"✅ 频谱视图已恢复");
    }
    
    // 🎵 如果正在播放且显示黑胶唱片，恢复旋转动画
    if (self.isShowingVinylRecord && self.player.isPlaying) {
        [self.vinylRecordView resumeSpinning];
        NSLog(@"✅ 黑胶唱片动画已恢复");
    }
}

- (void)karaokeModeDidStart {
    NSLog(@"🎤 收到卡拉OK模式开始通知，停止主界面音频播放");
    // 停止主界面的音频播放
    [self.player stop];
    // 暂停视觉效果渲染以节省资源
    [self.visualEffectManager pauseRendering];
}

- (void)karaokeModeDidEnd {
    NSLog(@"🎤 收到卡拉OK模式结束通知");
    // 恢复视觉效果渲染
    [self.visualEffectManager resumeRendering];
    
    // 🔧 不再自动恢复播放，由用户手动控制
    // 清除禁止自动恢复标志
    self.shouldPreventAutoResume = NO;
    
    NSLog(@"🎤 卡拉OK模式结束，等待用户手动播放");
}

- (void)ncmDecryptionCompleted:(NSNotification *)notification {
    NSNumber *count = notification.userInfo[@"count"];
    NSLog(@"🎉 收到 NCM 解密完成通知: %@ 个文件", count);
    
    // 显示提示
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ 解密完成" 
                                                                       message:[NSString stringWithFormat:@"成功解密 %@ 个 NCM 文件\n现在可以播放了！", count]
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:nil];
        [alert addAction:okAction];
        
        [self presentViewController:alert animated:YES completion:nil];
    });
}

- (void)setupVisualEffectSystem {
    // 创建视觉效果管理器
    self.visualEffectManager = [[VisualEffectManager alloc] initWithContainerView:self.view];
    self.visualEffectManager.delegate = self;
    
    // 设置默认效果
    [self.visualEffectManager setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];
    
    // 🎨 监听特效配置按钮点击通知
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleEffectSettingsButtonTapped:) 
                                                 name:@"EffectSettingsButtonTapped" 
                                               object:nil];
}

- (void)setupNavigationBar {
    // 🎨 配置导航栏外观，确保标题可见
    if (@available(iOS 13.0, *)) {
        UINavigationBarAppearance *appearance = [[UINavigationBarAppearance alloc] init];
        [appearance configureWithOpaqueBackground];
        appearance.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
        appearance.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:18]
        };
        
        self.navigationController.navigationBar.standardAppearance = appearance;
        self.navigationController.navigationBar.scrollEdgeAppearance = appearance;
        self.navigationController.navigationBar.compactAppearance = appearance;
    } else {
        // iOS 13 以下的版本
        self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
        self.navigationController.navigationBar.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:18]
        };
        self.navigationController.navigationBar.translucent = YES;
    }
    
    // 隐藏导航栏，让视觉效果全屏显示
    self.navigationController.navigationBarHidden = YES;
    
    NSLog(@"✅ 导航栏已隐藏");
}

- (void)setupEffectControls {
    // 初始化控制按钮数组
    self.controlButtons = [NSMutableArray array];
    self.isUIHidden = NO;
    
    // 🔧 修复导航栏遮挡问题：考虑安全区域和导航栏高度
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    
    // 如果有导航栏，从导航栏下方开始布局
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 10; // 额外10px间距
    
    // 👁️ 创建UI切换按钮（放在最左上角）
    [self createToggleUIButton:topOffset];
    
    // 创建性能配置按钮（放在左上角第二个位置）
    self.performanceControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.performanceControlButton setTitle:@"⚙️" forState:UIControlStateNormal];
    [self.performanceControlButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.performanceControlButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.performanceControlButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.2 alpha:0.9];
    self.performanceControlButton.layer.cornerRadius = 25;
    self.performanceControlButton.layer.borderWidth = 2.0;
    self.performanceControlButton.layer.borderColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.3 alpha:1.0].CGColor;
    self.performanceControlButton.frame = CGRectMake(80, topOffset, 50, 50);
    
    // 添加阴影效果
    self.performanceControlButton.layer.shadowColor = [UIColor greenColor].CGColor;
    self.performanceControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.performanceControlButton.layer.shadowOpacity = 0.8;
    self.performanceControlButton.layer.shadowRadius = 4;
    
    [self.performanceControlButton addTarget:self 
                                      action:@selector(performanceControlButtonTapped:) 
                            forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.performanceControlButton];
    [self.controlButtons addObject:self.performanceControlButton];
    
    // 添加FPS监控显示
    [self setupFPSMonitor];
    
    // 创建特效选择按钮（右移为性能按钮腾出空间）
    self.effectSelectorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.effectSelectorButton setTitle:@"🎨 特效" forState:UIControlStateNormal];
    [self.effectSelectorButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.effectSelectorButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.effectSelectorButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:0.9];
    self.effectSelectorButton.layer.cornerRadius = 25;
    self.effectSelectorButton.layer.borderWidth = 1.0;
    self.effectSelectorButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.effectSelectorButton.frame = CGRectMake(140, topOffset, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.effectSelectorButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.effectSelectorButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.effectSelectorButton.layer.shadowOpacity = 0.8;
    self.effectSelectorButton.layer.shadowRadius = 4;
    
    [self.effectSelectorButton addTarget:self 
                                  action:@selector(effectSelectorButtonTapped:) 
                        forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.effectSelectorButton];
    [self.controlButtons addObject:self.effectSelectorButton];
    
    // 添加卡拉OK按钮
    [self createKaraokeButton];
    
    // 添加快捷切换按钮
    // 🔇 已隐藏快捷视觉特效按钮
    // [self createQuickEffectButtons];
    
    // 确保控制按钮在最上层
    [self bringControlButtonsToFront];
}

- (void)createQuickEffectButtons {
    // 🔧 计算顶部偏移量（避免导航栏遮挡）
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70; // 在第一行按钮下方
    
    NSArray *quickEffects = @[
        @{@"title": @"🌈", @"effect": @(VisualEffectTypeNeonGlow)},
        @{@"title": @"🌊", @"effect": @(VisualEffectType3DWaveform)},
        @{@"title": @"💫", @"effect": @(VisualEffectTypeQuantumField)},
        @{@"title": @"🔮", @"effect": @(VisualEffectTypeHolographic)},
        @{@"title": @"⚡", @"effect": @(VisualEffectTypeCyberPunk)},
        @{@"title": @"🌌", @"effect": @(VisualEffectTypeGalaxy)}
    ];
    
    for (NSInteger i = 0; i < quickEffects.count; i++) {
        NSDictionary *effectInfo = quickEffects[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        
        [button setTitle:effectInfo[@"title"] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont systemFontOfSize:20];
        button.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.9];
        button.layer.cornerRadius = 20;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [UIColor whiteColor].CGColor;
        button.tag = [effectInfo[@"effect"] integerValue];
        
        // 添加阴影效果，增强可见性
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.shadowOpacity = 0.8;
        button.layer.shadowRadius = 3;
        
        // 计算位置（右侧垂直排列，从topOffset开始）
        CGFloat buttonSize = 40;
        CGFloat spacing = 10;
        button.frame = CGRectMake(self.view.bounds.size.width - buttonSize - 20, 
                                 topOffset + i * (buttonSize + spacing), 
                                 buttonSize, buttonSize);
        
        [button addTarget:self 
                   action:@selector(quickEffectButtonTapped:) 
         forControlEvents:UIControlEventTouchUpInside];
        
        [self.view addSubview:button];
        [self.controlButtons addObject:button];
    }
    
    // 添加星系控制按钮
    [self createGalaxyControlButton];
    
    // 添加赛博朋克控制按钮
    [self createCyberpunkControlButton];
}

- (void)createGalaxyControlButton {
    // 🔧 计算顶部偏移量
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 10;
    
    self.galaxyControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.galaxyControlButton setTitle:@"🌌⚙️" forState:UIControlStateNormal];
    self.galaxyControlButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.galaxyControlButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.1 blue:0.3 alpha:0.9];
    self.galaxyControlButton.layer.cornerRadius = 25;
    self.galaxyControlButton.layer.borderWidth = 1.0;
    self.galaxyControlButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.galaxyControlButton.frame = CGRectMake(230, topOffset, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.galaxyControlButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.galaxyControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.galaxyControlButton.layer.shadowOpacity = 0.8;
    self.galaxyControlButton.layer.shadowRadius = 4;
    
    [self.galaxyControlButton addTarget:self 
                                 action:@selector(galaxyControlButtonTapped:) 
                       forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.galaxyControlButton];
    [self.controlButtons addObject:self.galaxyControlButton];
}

- (void)createCyberpunkControlButton {
    // 🔧 计算顶部偏移量
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 10;
    
    self.cyberpunkControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cyberpunkControlButton setTitle:@"⚡⚙️" forState:UIControlStateNormal];
    self.cyberpunkControlButton.titleLabel.font = [UIFont systemFontOfSize:16];
    self.cyberpunkControlButton.backgroundColor = [UIColor colorWithRed:0.0 green:0.3 blue:0.4 alpha:0.9];
    self.cyberpunkControlButton.layer.cornerRadius = 25;
    self.cyberpunkControlButton.layer.borderWidth = 1.0;
    self.cyberpunkControlButton.layer.borderColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0].CGColor;
    self.cyberpunkControlButton.frame = CGRectMake(320, topOffset, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.cyberpunkControlButton.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.cyberpunkControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.cyberpunkControlButton.layer.shadowOpacity = 0.6;
    self.cyberpunkControlButton.layer.shadowRadius = 4;
    
    [self.cyberpunkControlButton addTarget:self 
                                    action:@selector(cyberpunkControlButtonTapped:) 
                          forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.cyberpunkControlButton];
    [self.controlButtons addObject:self.cyberpunkControlButton];
}

- (void)createKaraokeButton {
    // 🔧 计算顶部偏移量
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70; // 在第一行按钮下方
    
    self.karaokeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.karaokeButton setTitle:@"🎤 卡拉OK" forState:UIControlStateNormal];
    [self.karaokeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.karaokeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.karaokeButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
    self.karaokeButton.layer.cornerRadius = 25;
    self.karaokeButton.layer.borderWidth = 2.0;
    self.karaokeButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0].CGColor;
    self.karaokeButton.frame = CGRectMake(20, topOffset, 120, 50);
    
    // 添加阴影效果
    self.karaokeButton.layer.shadowColor = [UIColor redColor].CGColor;
    self.karaokeButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.karaokeButton.layer.shadowOpacity = 0.8;
    self.karaokeButton.layer.shadowRadius = 4;
    
    [self.karaokeButton addTarget:self 
                           action:@selector(karaokeButtonTapped:) 
                 forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.karaokeButton];
    [self.controlButtons addObject:self.karaokeButton];
    
    // 🎭 添加歌词特效按钮
    [self createLyricsEffectButton];
}

- (void)createLyricsEffectButton {
    // 🔧 计算顶部偏移量
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70; // 在第一行按钮下方
    
    self.lyricsEffectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.lyricsEffectButton setTitle:@"🎭 歌词" forState:UIControlStateNormal];
    [self.lyricsEffectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.lyricsEffectButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.lyricsEffectButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.8 alpha:0.9];
    self.lyricsEffectButton.layer.cornerRadius = 25;
    self.lyricsEffectButton.layer.borderWidth = 2.0;
    self.lyricsEffectButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.4 blue:1.0 alpha:1.0].CGColor;
    self.lyricsEffectButton.frame = CGRectMake(150, topOffset, 100, 50);
    
    // 添加阴影效果
    self.lyricsEffectButton.layer.shadowColor = [UIColor purpleColor].CGColor;
    self.lyricsEffectButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.lyricsEffectButton.layer.shadowOpacity = 0.8;
    self.lyricsEffectButton.layer.shadowRadius = 4;
    
    [self.lyricsEffectButton addTarget:self 
                                action:@selector(lyricsEffectButtonTapped:) 
                      forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.lyricsEffectButton];
    [self.controlButtons addObject:self.lyricsEffectButton];
    
    // 📝 添加导入歌词按钮
    [self createImportLyricsButton];
    
    // 🔊 添加混音控制开关
    [self createMixAudioControl];
}

- (void)createImportLyricsButton {
    // 📝 导入歌词按钮放在歌词特效按钮右侧（同一行）
    // 歌词特效按钮: x=150, width=100, 所以右边界是250
    CGFloat lyricsButtonRightEdge = CGRectGetMaxX(self.lyricsEffectButton.frame);
    CGFloat topOffset = CGRectGetMinY(self.lyricsEffectButton.frame);
    
    self.importLyricsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.importLyricsButton setTitle:@"📝 导入" forState:UIControlStateNormal];
    [self.importLyricsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.importLyricsButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.importLyricsButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.4 alpha:0.9];
    self.importLyricsButton.layer.cornerRadius = 25;
    self.importLyricsButton.layer.borderWidth = 1.5;
    self.importLyricsButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.7 blue:0.6 alpha:1.0].CGColor;
    // 放在歌词按钮右侧，间距5像素
    self.importLyricsButton.frame = CGRectMake(lyricsButtonRightEdge + 5, topOffset, 70, 50);
    
    // 添加阴影效果
    self.importLyricsButton.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.5 alpha:1.0].CGColor;
    self.importLyricsButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.importLyricsButton.layer.shadowOpacity = 0.6;
    self.importLyricsButton.layer.shadowRadius = 3;
    
    [self.importLyricsButton addTarget:self 
                                action:@selector(importLyricsButtonTapped:) 
                      forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.importLyricsButton];
    [self.controlButtons addObject:self.importLyricsButton];
}

- (void)createMixAudioControl {
    // 🔊 混音控制放在导入歌词按钮右侧
    CGFloat importButtonRightEdge = CGRectGetMaxX(self.importLyricsButton.frame);
    CGFloat topOffset = CGRectGetMinY(self.importLyricsButton.frame);
    
    // 创建容器视图（放在导入歌词按钮右侧，间距5像素）
    // 缩小容器尺寸，只保留开关
    self.mixAudioControlView = [[UIView alloc] initWithFrame:CGRectMake(importButtonRightEdge + 5, topOffset, 60, 50)];
    self.mixAudioControlView.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.6 alpha:0.9];
    self.mixAudioControlView.layer.cornerRadius = 25;
    self.mixAudioControlView.layer.borderWidth = 2.0;
    self.mixAudioControlView.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:1.0].CGColor;
    
    // 添加阴影效果
    self.mixAudioControlView.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.mixAudioControlView.layer.shadowOffset = CGSizeMake(0, 2);
    self.mixAudioControlView.layer.shadowOpacity = 0.8;
    self.mixAudioControlView.layer.shadowRadius = 4;
    
    // 创建开关（居中放置）
    self.mixAudioSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(8, 10, 44, 30)];
    self.mixAudioSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);  // 缩小开关
    self.mixAudioSwitch.center = CGPointMake(30, 25);  // 居中
    self.mixAudioSwitch.on = NO;  // 默认关闭（不混音）
    self.mixAudioSwitch.onTintColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0];
    [self.mixAudioSwitch addTarget:self 
                            action:@selector(mixAudioSwitchChanged:) 
                  forControlEvents:UIControlEventValueChanged];
    [self.mixAudioControlView addSubview:self.mixAudioSwitch];
    
    [self.view addSubview:self.mixAudioControlView];
    [self.controlButtons addObject:self.mixAudioControlView];
}

- (void)mixAudioSwitchChanged:(UISwitch *)sender {
    // 更新播放器的混音设置
    self.player.allowMixWithOthers = sender.isOn;
    
    NSLog(@"🔊 混音控制已%@: %@", sender.isOn ? @"开启" : @"关闭", 
          sender.isOn ? @"允许与其他应用同时播放" : @"独占音频播放");
    
    // 验证音频会话配置
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   当前音频会话类别: %@", session.category);
    NSLog(@"   当前音频会话选项: %lu", (unsigned long)session.categoryOptions);
    
    // 显示提示
    NSString *message = sender.isOn ? 
        @"已开启：可与其他应用同时播放\n（如QQ音乐、网易云等）" : 
        @"已关闭：独占音频播放\n（会暂停其他应用的音乐）";
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔊 混音设置"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" 
                                              style:UIAlertActionStyleDefault 
                                            handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createToggleUIButton:(CGFloat)topOffset {
    // 创建UI显示/隐藏切换按钮
    self.toggleUIButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.toggleUIButton setTitle:@"👁️" forState:UIControlStateNormal];
    self.toggleUIButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.toggleUIButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.9];
    self.toggleUIButton.layer.cornerRadius = 25;
    self.toggleUIButton.layer.borderWidth = 2.0;
    self.toggleUIButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.toggleUIButton.frame = CGRectMake(20, topOffset, 50, 50);
    
    // 添加阴影效果
    self.toggleUIButton.layer.shadowColor = [UIColor whiteColor].CGColor;
    self.toggleUIButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.toggleUIButton.layer.shadowOpacity = 0.8;
    self.toggleUIButton.layer.shadowRadius = 4;
    
    [self.toggleUIButton addTarget:self
                            action:@selector(toggleUIButtonTapped:)
                  forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.toggleUIButton];
    // 注意：这个按钮不加入controlButtons数组，因为它本身就是控制按钮
}

- (void)toggleUIButtonTapped:(UIButton *)sender {
    self.isUIHidden = !self.isUIHidden;
    
    NSLog(@"👁️ UI切换: %@", self.isUIHidden ? @"隐藏" : @"显示");
    
    // 切换按钮图标
    [self.toggleUIButton setTitle:self.isUIHidden ? @"🙈" : @"👁️" forState:UIControlStateNormal];
    
    // 切换所有控制按钮的显示/隐藏状态
    [UIView animateWithDuration:0.3 animations:^{
        // 调整隐藏UI按钮自身的透明度
        self.toggleUIButton.alpha = self.isUIHidden ? 0.2 : 1.0;
        
        for (UIButton *button in self.controlButtons) {
            button.alpha = self.isUIHidden ? 0.0 : 1.0;
            button.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 隐藏FPS显示器
        if (self.fpsLabel) {
            self.fpsLabel.alpha = self.isUIHidden ? 0.0 : 1.0;
        }
        
        // 🎵 隐藏歌曲列表相关的UI控件
        // 分类按钮
        for (UIButton *categoryBtn in self.categoryButtons) {
            categoryBtn.alpha = self.isUIHidden ? 0.0 : 1.0;
            categoryBtn.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 排序按钮
        if (self.sortButton) {
            self.sortButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.sortButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 重新扫描按钮
        if (self.reloadButton) {
            self.reloadButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.reloadButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 导入按钮
        if (self.importButton) {
            self.importButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.importButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 📝 导入歌词按钮
        if (self.importLyricsButton) {
            self.importLyricsButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.importLyricsButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 🎵 播放控制按钮
        if (self.previousButton) {
            self.previousButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.previousButton.userInteractionEnabled = !self.isUIHidden;
        }
        if (self.playPauseButton) {
            self.playPauseButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.playPauseButton.userInteractionEnabled = !self.isUIHidden;
        }
        if (self.nextButton) {
            self.nextButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.nextButton.userInteractionEnabled = !self.isUIHidden;
        }
        if (self.loopButton) {
            self.loopButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.loopButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 搜索框
        if (self.searchBar) {
            self.searchBar.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.searchBar.userInteractionEnabled = !self.isUIHidden;
            if (self.isUIHidden) {
                [self.searchBar resignFirstResponder]; // 隐藏键盘
            }
        }
        
        // 云端按钮
        if (self.cloudButton) {
            self.cloudButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.cloudButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 🎼 歌词打轴按钮
        if (self.lyricsTimingButton) {
            self.lyricsTimingButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.lyricsTimingButton.userInteractionEnabled = !self.isUIHidden;
        }
        
        // 🎵 进度条
        [self setProgressViewHidden:self.isUIHidden animated:NO];
    }];
}

- (void)bringControlButtonsToFront {
    // 将UI切换按钮提到最前面（始终可见）
    [self.view bringSubviewToFront:self.toggleUIButton];
    
    // 将所有控制按钮提到最前面
    [self.view bringSubviewToFront:self.performanceControlButton];
    [self.view bringSubviewToFront:self.effectSelectorButton];
    [self.view bringSubviewToFront:self.galaxyControlButton];
    [self.view bringSubviewToFront:self.cyberpunkControlButton];
    [self.view bringSubviewToFront:self.karaokeButton];
    [self.view bringSubviewToFront:self.lyricsEffectButton];
    
    // 将所有快捷按钮也提到前面
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIButton class]] && 
            subview != self.toggleUIButton &&
            subview != self.performanceControlButton &&
            subview != self.effectSelectorButton && 
            subview != self.galaxyControlButton &&
            subview != self.cyberpunkControlButton &&
            subview != self.karaokeButton &&
            subview != self.lyricsEffectButton &&
            subview.tag >= 0 && subview.tag < VisualEffectTypeCount) {
            [self.view bringSubviewToFront:subview];
        }
    }
}
- (void)viewWillAppear:(BOOL)animated
{
    [super viewWillAppear:animated];
    // 首页隐藏导航栏，让视觉效果全屏显示
    [self.navigationController setNavigationBarHidden:YES animated:animated];
    
    // 🔧 清除禁止自动恢复标志（用户返回主界面时）
    self.shouldPreventAutoResume = NO;
    NSLog(@"📱 主界面出现，允许正常的音频操作");
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
    // 🎨 配置导航栏外观
    [self setupNavigationBar];
    
    // 🆕 初始化音乐库管理器（最先初始化）
    [self setupMusicLibrary];
    
    // 初始化动画协调器
    self.animationCoordinator = [[AnimationCoordinator alloc] initWithContainerView:self.view];
    
    // 初始化高端视觉效果系统
    [self setupVisualEffectSystem];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterBackGround) name:UIApplicationDidEnterBackgroundNotification object:nil];
    
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(hadEnterForeGround) name:UIApplicationDidBecomeActiveNotification object:nil];
    
    // 监听卡拉OK模式通知
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(karaokeModeDidStart) name:@"KaraokeModeDidStart" object:nil];
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(karaokeModeDidEnd) name:@"KaraokeModeDidEnd" object:nil];
    
    // 🆕 监听 NCM 解密完成通知
    [[NSNotificationCenter defaultCenter]addObserver:self selector:@selector(ncmDecryptionCompleted:) name:@"NCMDecryptionCompleted" object:nil];
    
    // 🎧 监听音频会话中断通知（耳机拔出/插入、来电等）
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleAudioSessionInterruption:) 
                                                 name:AVAudioSessionInterruptionNotification 
                                               object:[AVAudioSession sharedInstance]];
    
    // 🎧 监听音频路由变化通知（耳机连接/断开）
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(handleAudioSessionRouteChange:) 
                                                 name:AVAudioSessionRouteChangeNotification 
                                               object:[AVAudioSession sharedInstance]];
    
    NSLog(@"✅ 已注册音频会话中断和路由变化监听");
    
    self.view.backgroundColor = [UIColor blackColor];
    
    [self setupBackgroundLayers];
    [self setupImageView];
//    [self setupParticleSystem];
    [self configInit];
    [self createMusic];
    
    // 启动所有动画
    [self.animationCoordinator startAllAnimations];
    
    // 最后创建控制按钮，确保在最上层
    [self setupEffectControls];
    
    // 添加歌词视图
    [self setupLyricsView];
    
    // 🆕 启用云端下载功能（暂时隐藏）
    // [self setupCloudDownloadFeature];
    
    // 🎵 初始化播放器（确保在配置远程控制之前）
    [self player]; // 触发懒加载
    
    // 🎵 配置系统媒体控制（控制中心、锁屏等）
    [self setupRemoteCommandCenter];
    
    // 🎵 设置播放进度条
    [self setupProgressView];
}

- (void)setupBackgroundLayers {
    // 移除音乐封面周围的圆弧，保持界面简洁
    // 原来的圆环代码已被注释掉
    
    /*
    float centerX = self.view.center.x;
    float centerY = self.view.center.y;
    
    // 创建背景圆环 - 已移除
    CAShapeLayer *backLayer = [self createBackgroundRingWithCenter:CGPointMake(centerX, centerY) 
                                                            radius:100 
                                                         lineWidth:10 
                                                        startAngle:0.2*M_PI 
                                                          endAngle:1.5*M_PI];
    
    backLayers = [self createBackgroundRingWithCenter:CGPointMake(centerX, centerY) 
                                               radius:89 
                                            lineWidth:5 
                                           startAngle:0.3*M_PI 
                                             endAngle:1.5*M_PI];
    backLayers.strokeColor = [UIColor colorWithRed:arc4random()%255/255.0 
                                             green:arc4random()%255/255.0 
                                              blue:arc4random()%255/255.0 
                                             alpha:1.0].CGColor;
    
    // 创建渐变色图层
    [self setupGradientLayerWithMask:backLayer];
    
    // 为背景图层添加旋转动画
    [self.animationCoordinator.rotationManager addRotationAnimationToLayer:backLayer 
                                                              withRotations:6.0 
                                                                   duration:25.0 
                                                               rotationType:RotationTypeCounterClockwise];
    
    [self.animationCoordinator.rotationManager addRotationAnimationToLayer:backLayers 
                                                              withRotations:6.0 
                                                                   duration:10.0 
                                                               rotationType:RotationTypeClockwise];
    */
    
    NSLog(@"🎵 音乐封面周围的圆弧已被移除，界面更加简洁");
}

- (CAShapeLayer *)createBackgroundRingWithCenter:(CGPoint)center 
                                           radius:(CGFloat)radius 
                                        lineWidth:(CGFloat)lineWidth 
                                       startAngle:(CGFloat)startAngle 
                                         endAngle:(CGFloat)endAngle {
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center 
                                                        radius:radius 
                                                    startAngle:startAngle 
                                                      endAngle:endAngle 
                                                     clockwise:YES];
    
    CAShapeLayer *layer = [CAShapeLayer layer];
    layer.frame = self.view.bounds;
    layer.fillColor = [[UIColor clearColor] CGColor];
    layer.strokeColor = [UIColor colorWithRed:50.0/255.0f green:50.0/255.0f blue:50.0/255.0f alpha:1].CGColor;
    layer.lineWidth = lineWidth;
    layer.path = [path CGPath];
    layer.strokeEnd = 1;
    layer.lineCap = @"round";
    
    [self.view.layer addSublayer:layer];
    return layer;
}

- (void)setupGradientLayerWithMask:(CAShapeLayer *)maskLayer {
    self.gradientLayer = [CAGradientLayer layer];
    self.gradientLayer.frame = self.view.bounds;
    self.gradientLayer.position = self.view.center;
    self.gradientLayer.cornerRadius = 5;
    [self.gradientLayer setStartPoint:CGPointMake(0.0, 0.5)];
    [self.gradientLayer setEndPoint:CGPointMake(1.0, 0.5)];
    [self.gradientLayer setMask:maskLayer];
    
    [self.view.layer addSublayer:self.gradientLayer];
    
    // 设置渐变动画管理器
    [self.animationCoordinator setupGradientLayer:self.gradientLayer];
    


}

- (void)setupImageView {
    [self configInit];
    
    imageView = [[UIImageView alloc]init];
    imageView.frame = CGRectMake(0, 0, 170, 170);
    
    // 🎵 创建黑胶唱片视图（与 imageView 相同大小和位置）
    self.vinylRecordView = [[VinylRecordView alloc] initWithFrame:CGRectMake(0, 0, 170, 170)];
    self.vinylRecordView.center = self.view.center;
    self.vinylRecordView.rotationsPerSecond = 0.5; // 2秒一圈
    self.vinylRecordView.glossIntensity = 0.35;
    self.vinylRecordView.hidden = YES; // 默认隐藏
    [self.view addSubview:self.vinylRecordView];
    
    // 🆕 使用当前显示的音乐项获取封面
    UIImage *coverImage = nil;
    NSString *songName = nil;
    
    if (self.displayedMusicItems.count > 0 && index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        songName = musicItem.displayName ?: musicItem.fileName;
        
        // 🔧 修复：优先使用 filePath（导入的文件），否则从 Bundle 查找
        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
            NSLog(@"🖼️ 使用导入文件封面: %@", musicItem.filePath);
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
            NSLog(@"🖼️ 使用Bundle文件封面: %@", musicItem.fileName);
        }
        
        coverImage = [self musicImageWithMusicURL:fileUrl];
    }
    
    // 🎵 根据是否有封面选择显示 imageView 或 vinylRecordView
    if (coverImage) {
        imageView.image = coverImage;
        imageView.hidden = NO;
        self.vinylRecordView.hidden = YES;
        self.isShowingVinylRecord = NO;
        NSLog(@"🖼️ 显示音乐封面");
    } else {
        // 没有封面，显示黑胶唱片动画
        imageView.hidden = YES;
        self.vinylRecordView.hidden = NO;
        self.isShowingVinylRecord = YES;
        
        // 使用歌曲名称生成一致的随机外观
        if (songName) {
            [self.vinylRecordView regenerateAppearanceWithSongName:songName];
        }
        NSLog(@"🎵 显示黑胶唱片动画（无封面）");
    }
    
    imageView.layer.cornerRadius = imageView.frame.size.height/2.0;
    imageView.clipsToBounds = YES;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.center = self.view.center;
    [self.view addSubview:imageView];
    
    // 使用动画管理器添加旋转动画（只有当显示封面图片时才需要）
    if (!self.isShowingVinylRecord) {
        [self.animationCoordinator addRotationViews:@[imageView] 
                                          rotations:@[@(6.0)] 
                                          durations:@[@(120.0)] 
                                      rotationTypes:@[@(RotationTypeCounterClockwise)]];
    }

    
    [self.view addSubview:[self buildTableHeadView]];
    
    // 确保控制按钮在tableView之上
    [self bringControlButtonsToFront];
}

- (void)setupParticleSystem {
    // 创建粒子容器
    UIView *bvView = [[UIView alloc] init];
    bvView.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    [self.view addSubview:bvView];
    
    self.xlayer = [[CALayer alloc] init];
    self.xlayer.frame = CGRectMake(0, 0, [UIScreen mainScreen].bounds.size.width, [UIScreen mainScreen].bounds.size.height);
    [bvView.layer addSublayer:self.xlayer];
    
    // 设置粒子动画管理器
    [self.animationCoordinator setupParticleContainerLayer:self.xlayer];
    [self.animationCoordinator.particleManager setEmitterPosition:self.view.center];
    [self.animationCoordinator.particleManager setEmitterSize:self.view.bounds.size];
    
    // 🔧 修复：设置当前音频的粒子图像（使用 displayedMusicItems）
    if (self.displayedMusicItems.count > 0 && index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        
        // 优先使用 filePath（导入的文件），否则从 Bundle 查找
        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        }
        
        UIImage *image = [self musicImageWithMusicURL:fileUrl];
        if (image) {
            [self.animationCoordinator updateParticleImage:image];
        }
    }

    
    
}

// 这些方法现在由GradientAnimationManager处理，保留空实现以防其他地方调用
- (void)performAnimation {
    // 已移至GradientAnimationManager
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
    // 已移至GradientAnimationManager
}

- (void)createMusic {
    [self configInit];
    [self buildUI];
}
- (void)configInit {
    self.title = @"播放";
    
    // 如果数组已经有数据，说明已经初始化过了，直接返回
    if (self.audioArray.count > 0) {
        return;
    }
    
    // 🆕 使用统一的音频格式工具类加载所有支持格式的文件
    NSArray *audioFiles = [AudioFileFormats loadAudioFilesFromBundle];
    [self.audioArray addObjectsFromArray:audioFiles];
}

- (void)buildUI {
    // 计算顶部偏移量
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 140;
    
    // 🆕 左侧分类按钮组 - 竖向排列
    CGFloat leftX = 10;
    CGFloat buttonWidth = 70;
    CGFloat buttonHeight = 40;
    CGFloat spacing = 8;
    
    self.categoryButtons = [NSMutableArray array];
    
    NSArray *categories = @[
        @{@"title": @"📁 全部", @"category": @(MusicCategoryAll)},
        @{@"title": @"🕐 最近", @"category": @(MusicCategoryRecent)},
        @{@"title": @"❤️ 最爱", @"category": @(MusicCategoryFavorite)},
        @{@"title": @"🎵 MP3", @"category": @(MusicCategoryMP3)},
        @{@"title": @"🔒 NCM", @"category": @(MusicCategoryNCM)}
    ];
    
    for (NSInteger i = 0; i < categories.count; i++) {
        NSDictionary *catInfo = categories[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:catInfo[@"title"] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:13];
        button.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.85];
        button.layer.cornerRadius = 8;
        button.layer.borderWidth = 1.5;
        button.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.6].CGColor;
        button.tag = [catInfo[@"category"] integerValue];
        
        CGFloat yPos = topOffset + i * (buttonHeight + spacing);
        button.frame = CGRectMake(leftX, yPos, buttonWidth, buttonHeight);
        
        [button addTarget:self action:@selector(categoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
        [self.categoryButtons addObject:button];
        
        // 默认选中"全部"
        if (i == 0) {
            button.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:0.9];
            button.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
        }
    }
    
    // 🆕 排序按钮 - 放在分类按钮下方
    CGFloat sortButtonY = topOffset + categories.count * (buttonHeight + spacing) + 15;
    self.sortButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.sortButton setTitle:@"🔄 排序" forState:UIControlStateNormal];
    [self.sortButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.sortButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.sortButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.3 alpha:0.85];
    self.sortButton.layer.cornerRadius = 8;
    self.sortButton.layer.borderWidth = 1.5;
    self.sortButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:0.8].CGColor;
    self.sortButton.frame = CGRectMake(leftX, sortButtonY, buttonWidth, buttonHeight);
    [self.sortButton addTarget:self action:@selector(sortButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.sortButton];
    
    // 🆕 刷新音乐库按钮 - 放在排序按钮下方
    CGFloat reloadButtonY = sortButtonY + buttonHeight + spacing;
    self.reloadButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.reloadButton setTitle:@"🔄 重新扫描" forState:UIControlStateNormal];
    [self.reloadButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.reloadButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.reloadButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.2 alpha:0.85];
    self.reloadButton.layer.cornerRadius = 8;
    self.reloadButton.layer.borderWidth = 1.5;
    self.reloadButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.5 blue:0.3 alpha:0.8].CGColor;
    self.reloadButton.frame = CGRectMake(leftX, reloadButtonY, buttonWidth, buttonHeight);
    [self.reloadButton addTarget:self action:@selector(reloadMusicLibraryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.reloadButton];
    
    // 🆕 导入音乐按钮 - 放在重新扫描按钮下方
    CGFloat importButtonY = reloadButtonY + buttonHeight + spacing;
    self.importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.importButton setTitle:@"📥 导入" forState:UIControlStateNormal];
    [self.importButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.importButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.importButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.8 alpha:0.85];
    self.importButton.layer.cornerRadius = 8;
    self.importButton.layer.borderWidth = 1.5;
    self.importButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.8].CGColor;
    self.importButton.frame = CGRectMake(leftX, importButtonY, buttonWidth, buttonHeight);
    [self.importButton addTarget:self action:@selector(importMusicButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importButton];
    
    // 🎵 播放控制按钮 - 放在导入按钮下方，纵向排列4个按钮
    CGFloat controlButtonsY = importButtonY + buttonHeight + spacing;
    CGFloat controlButtonWidth = buttonWidth;  // 使用完整宽度
    CGFloat controlButtonHeight = 32;  // 按钮高度
    CGFloat controlSpacing = 4;  // 按钮之间的间距
    
    // 上一首按钮
    self.previousButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.previousButton setTitle:@"⏮️" forState:UIControlStateNormal];
    self.previousButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.previousButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.previousButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:0.85];
    self.previousButton.layer.cornerRadius = 6;
    self.previousButton.layer.borderWidth = 1.0;
    self.previousButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:0.8].CGColor;
    self.previousButton.frame = CGRectMake(leftX, controlButtonsY, controlButtonWidth, controlButtonHeight);
    [self.previousButton addTarget:self action:@selector(previousButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.previousButton];
    
    // 播放/暂停按钮
    CGFloat playButtonY = controlButtonsY + controlButtonHeight + controlSpacing;
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.playPauseButton setTitle:@"▶️" forState:UIControlStateNormal];
    self.playPauseButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.playPauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.85];
    self.playPauseButton.layer.cornerRadius = 6;
    self.playPauseButton.layer.borderWidth = 1.0;
    self.playPauseButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:0.8].CGColor;
    self.playPauseButton.frame = CGRectMake(leftX, playButtonY, controlButtonWidth, controlButtonHeight);
    [self.playPauseButton addTarget:self action:@selector(playPauseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playPauseButton];
    
    // 下一首按钮
    CGFloat nextButtonY = playButtonY + controlButtonHeight + controlSpacing;
    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nextButton setTitle:@"⏭️" forState:UIControlStateNormal];
    self.nextButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.nextButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.nextButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:0.85];
    self.nextButton.layer.cornerRadius = 6;
    self.nextButton.layer.borderWidth = 1.0;
    self.nextButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:0.8].CGColor;
    self.nextButton.frame = CGRectMake(leftX, nextButtonY, controlButtonWidth, controlButtonHeight);
    [self.nextButton addTarget:self action:@selector(nextButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];
    
    // 单曲循环按钮
    CGFloat loopButtonY = nextButtonY + controlButtonHeight + controlSpacing;
    self.loopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.loopButton setTitle:@"🔁" forState:UIControlStateNormal];
    self.loopButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.loopButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.loopButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.7 alpha:0.85];
    self.loopButton.layer.cornerRadius = 6;
    self.loopButton.layer.borderWidth = 1.0;
    self.loopButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.8 alpha:0.8].CGColor;
    self.loopButton.frame = CGRectMake(leftX, loopButtonY, controlButtonWidth, controlButtonHeight);
    [self.loopButton addTarget:self action:@selector(loopButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.loopButton];
    
    // 初始化循环模式
    self.isSingleLoopMode = NO;
    
    // 云端下载按钮
    CGFloat cloudButtonY = loopButtonY + controlButtonHeight + controlSpacing;
    self.cloudButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cloudButton setTitle:@"☁️" forState:UIControlStateNormal];
    self.cloudButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.cloudButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.cloudButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.85];
    self.cloudButton.layer.cornerRadius = 6;
    self.cloudButton.layer.borderWidth = 1.0;
    self.cloudButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.8].CGColor;
    self.cloudButton.frame = CGRectMake(leftX, cloudButtonY, controlButtonWidth, controlButtonHeight);
    [self.cloudButton addTarget:self action:@selector(cloudDownloadButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cloudButton];
    
    // 🎼 歌词打轴按钮 - 放在云端按钮下方
    CGFloat timingButtonY = cloudButtonY + controlButtonHeight + controlSpacing;
    self.lyricsTimingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.lyricsTimingButton setTitle:@"🎼" forState:UIControlStateNormal];
    self.lyricsTimingButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.lyricsTimingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.lyricsTimingButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.5 blue:0.1 alpha:0.85];
    self.lyricsTimingButton.layer.cornerRadius = 6;
    self.lyricsTimingButton.layer.borderWidth = 1.0;
    self.lyricsTimingButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.7 blue:0.3 alpha:0.8].CGColor;
    self.lyricsTimingButton.frame = CGRectMake(leftX, timingButtonY, controlButtonWidth, controlButtonHeight);
    [self.lyricsTimingButton addTarget:self action:@selector(lyricsTimingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.lyricsTimingButton];
    
    // 🆕 添加搜索栏 - 放在右侧
    CGFloat searchBarX = leftX + buttonWidth + 15;
    CGFloat searchBarWidth = self.view.frame.size.width - searchBarX - 10;
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(searchBarX, topOffset, searchBarWidth, 50)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索歌曲、艺术家...";
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.enablesReturnKeyAutomatically = YES;  // 启用返回键
    [self.view addSubview:self.searchBar];
    
    // 🔧 添加点击背景隐藏键盘的手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;  // 不取消其他触摸事件
    [self.view addGestureRecognizer:tapGesture];
    
    // 更新 TableView 位置
    CGFloat tableY = topOffset + 60;
    CGFloat tableX = searchBarX;
    CGFloat tableWidth = searchBarWidth;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(tableX, tableY, tableWidth, self.view.frame.size.height - tableY) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableHeaderView = [[UIView alloc]initWithFrame:CGRectMake(0, 100, tableWidth, self.view.frame.size.height)];
    self.tableView.tableFooterView = [UIView new];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.rowHeight = 60;  // 增加行高以适应新的UI
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;  // 🔧 滚动时自动隐藏键盘
    [self.view addSubview:self.tableView];
    
    // 确保控制按钮在tableView之上
    [self bringControlButtonsToFront];
}

- (UIView *)buildTableHeadView {
    self.spectrumView = [[SpectrumView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    self.spectrumView.backgroundColor = [UIColor clearColor];
    
    // 设置频谱视图到视觉效果管理器，用于在Metal特效时暂停
    [self.visualEffectManager setOriginalSpectrumView:self.spectrumView];
    
    return self.spectrumView;
}

#pragma mark - UITableView
- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    return self.displayedMusicItems.count;
}

- (CGFloat)tableView:(UITableView *)tableView heightForRowAtIndexPath:(NSIndexPath *)indexPath {
    return 60;
}

- (UITableViewCell *)tableView:(UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath {
    AudioPlayCell *cell = [tableView dequeueReusableCellWithIdentifier:@"cellID"];
    if (!cell) {
        cell = [[AudioPlayCell alloc] initWithStyle:UITableViewCellStyleDefault reuseIdentifier:@"cellID"];
    }
    
    // 🆕 使用 MusicItem 配置 cell
    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    [cell configureWithMusicItem:musicItem];
    
    cell.playBtn.hidden = YES;  // 隐藏播放按钮（点击整行即可播放）
    
    // 播放回调
    __weak typeof(self) weakSelf = self;
    cell.playBlock = ^(BOOL isPlaying) {
        if (isPlaying) {
            [weakSelf.player stop];
        } else {
            NSString *playPath = nil;
            
            // 优先使用已解密文件
            if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
                playPath = musicItem.decryptedPath;
            } 
            // 检查是否是NCM文件，需要先解密
            else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
                // 🔧 优先传递完整路径
                NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
                playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];
                
                // 如果解密成功，更新状态
                if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
                    [weakSelf.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
                }
            } else {
                playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
            }
            
            [weakSelf.player playWithFileName:playPath];
        }
    };
    
    // 🆕 收藏回调
    cell.favoriteBlock = ^{
        [weakSelf.musicLibrary toggleFavoriteForMusic:musicItem];
        cell.favoriteButton.selected = musicItem.isFavorite;
        
        // 如果当前在"我的最爱"分类，且取消了收藏，刷新列表
        if (weakSelf.currentCategory == MusicCategoryFavorite && !musicItem.isFavorite) {
            [weakSelf refreshMusicList];
        }
    };
    
    // 🆕 NCM转换回调
    cell.convertBlock = ^{
        [weakSelf convertNCMFile:musicItem atIndexPath:indexPath];
    };
    
    return cell;
}

#pragma mark - UITableView 编辑和删除

// 🆕 使用 iOS 11+ 的左侧滑动 API（避免与右侧收藏、播放按钮重叠）
- (UISwipeActionsConfiguration *)tableView:(UITableView *)tableView leadingSwipeActionsConfigurationForRowAtIndexPath:(NSIndexPath *)indexPath API_AVAILABLE(ios(11.0)) {
    
    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    
    // 检查是否可以删除（Bundle文件不可删除）
    BOOL isBundleFile = ![musicItem.filePath hasPrefix:@"/var/mobile"] && 
                        ![musicItem.filePath hasPrefix:@"/Users"] &&
                        ![musicItem.filePath containsString:@"Documents"];
    
    if (isBundleFile) {
        // Bundle文件：不显示任何侧滑操作
        return nil;
    }
    
    // 创建删除操作（从左侧滑出）
    UIContextualAction *deleteAction = [UIContextualAction contextualActionWithStyle:UIContextualActionStyleDestructive
                                                                               title:@"删除"
                                                                             handler:^(UIContextualAction * _Nonnull action, __kindof UIView * _Nonnull sourceView, void (^ _Nonnull completionHandler)(BOOL)) {
        // 显示确认对话框
        NSString *message = [NSString stringWithFormat:@"确定要删除 \"%@\" 吗？\n\n这将同时删除：\n• 音频文件\n• 歌词文件（如有）\n• 所有播放记录\n\n此操作不可撤销！", musicItem.displayName];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🗑️ 删除歌曲"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        // 确认删除按钮
        UIAlertAction *confirmDelete = [UIAlertAction actionWithTitle:@"删除"
                                                                style:UIAlertActionStyleDestructive
                                                              handler:^(UIAlertAction * _Nonnull action) {
            [self performDeleteMusicItem:musicItem atIndexPath:indexPath];
            completionHandler(YES); // 关闭侧滑
        }];
        
        // 取消按钮
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction * _Nonnull action) {
            completionHandler(NO); // 不删除，关闭侧滑
        }];
        
        [alert addAction:cancelAction];
        [alert addAction:confirmDelete];
        
        [self presentViewController:alert animated:YES completion:nil];
    }];
    
    // 自定义删除按钮样式
    deleteAction.backgroundColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0]; // 鲜红色
    deleteAction.image = [UIImage systemImageNamed:@"trash.fill"]; // iOS 13+ 系统图标
    
    // 返回侧滑配置
    UISwipeActionsConfiguration *configuration = [UISwipeActionsConfiguration configurationWithActions:@[deleteAction]];
    configuration.performsFirstActionWithFullSwipe = NO; // 禁止完全侧滑直接删除（必须点击确认）
    
    return configuration;
}

// ⚠️ 启用侧滑编辑功能（必须返回 YES 才能触发侧滑）
- (BOOL)tableView:(UITableView *)tableView canEditRowAtIndexPath:(NSIndexPath *)indexPath {
    // 检查是否可以删除（Bundle文件不可删除）
    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    BOOL isBundleFile = ![musicItem.filePath hasPrefix:@"/var/mobile"] &&
                        ![musicItem.filePath hasPrefix:@"/Users"] &&
                        ![musicItem.filePath containsString:@"Documents"];
    return !isBundleFile;
}

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath {
    // iOS 10 及以下的删除处理
    if (editingStyle == UITableViewCellEditingStyleDelete) {
        MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
        
        NSString *message = [NSString stringWithFormat:@"确定要删除 \"%@\" 吗？\n\n此操作不可撤销！", musicItem.displayName];
        
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🗑️ 删除歌曲"
                                                                       message:message
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *deleteAction = [UIAlertAction actionWithTitle:@"删除"
                                                               style:UIAlertActionStyleDestructive
                                                             handler:^(UIAlertAction * _Nonnull action) {
            [self performDeleteMusicItem:musicItem atIndexPath:indexPath];
        }];
        
        UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消"
                                                               style:UIAlertActionStyleCancel
                                                             handler:^(UIAlertAction * _Nonnull action) {
            [tableView setEditing:NO animated:YES];
        }];
        
        [alert addAction:cancelAction];
        [alert addAction:deleteAction];
        
        [self presentViewController:alert animated:YES completion:nil];
    }
}

// 执行删除操作
- (void)performDeleteMusicItem:(MusicItem *)musicItem atIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🗑️ 开始删除歌曲: %@", musicItem.displayName);
    
    // 在后台线程执行删除操作
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSError *error = nil;
        BOOL success = [self.musicLibrary deleteMusicItem:musicItem error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            if (success) {
                // 刷新显示列表
                [self refreshMusicList];
                
                // 显示成功提示（轻量级toast）
                [self showToast:[NSString stringWithFormat:@"✅ 已删除 \"%@\"", musicItem.displayName]];
                
                NSLog(@"✅ 删除成功: %@", musicItem.displayName);
            } else {
                // 显示错误提示
                NSString *errorMessage = error ? error.localizedDescription : @"未知错误";
                UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"❌ 删除失败" 
                                                                                    message:[NSString stringWithFormat:@"删除失败：%@", errorMessage] 
                                                                             preferredStyle:UIAlertControllerStyleAlert];
                [errorAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:errorAlert animated:YES completion:nil];
                
                NSLog(@"❌ 删除失败: %@ - %@", musicItem.displayName, errorMessage);
            }
        });
    });
}

// 显示轻量级Toast提示
- (void)showToast:(NSString *)message {
    UILabel *toastLabel = [[UILabel alloc] init];
    toastLabel.text = message;
    toastLabel.font = [UIFont systemFontOfSize:14];
    toastLabel.textColor = [UIColor whiteColor];
    toastLabel.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.9];
    toastLabel.textAlignment = NSTextAlignmentCenter;
    toastLabel.numberOfLines = 0;
    toastLabel.layer.cornerRadius = 10;
    toastLabel.clipsToBounds = YES;
    
    // 计算尺寸
    CGSize textSize = [message boundingRectWithSize:CGSizeMake(self.view.bounds.size.width - 80, CGFLOAT_MAX)
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: toastLabel.font}
                                            context:nil].size;
    
    CGFloat width = textSize.width + 40;
    CGFloat height = textSize.height + 20;
    
    toastLabel.frame = CGRectMake((self.view.bounds.size.width - width) / 2,
                                  self.view.bounds.size.height - 150,
                                  width,
                                  height);
    toastLabel.alpha = 0;
    
    [self.view addSubview:toastLabel];
    
    // 显示动画
    [UIView animateWithDuration:0.3 animations:^{
        toastLabel.alpha = 1.0;
    } completion:^(BOOL finished) {
        // 1.5秒后自动消失
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [UIView animateWithDuration:0.3 animations:^{
                toastLabel.alpha = 0;
            } completion:^(BOOL finished) {
                [toastLabel removeFromSuperview];
            }];
        });
    }];
}

-(void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath
{
    // 🔧 点击列表项时隐藏键盘
    [self.searchBar resignFirstResponder];
    
    index = indexPath.row;
    
    // 🆕 获取选中的音乐项
    MusicItem *musicItem = self.displayedMusicItems[indexPath.row];
    
    // 🆕 记录播放
    [self.musicLibrary recordPlayForMusic:musicItem];
    
    [self updateAudioSelection];
    
    // 🔧 优先使用完整路径，支持云下载的文件和已解密的 NCM 文件
    NSString *playPath = nil;
    
    NSLog(@"🎵 准备播放: fileName=%@, filePath=%@, decryptedPath=%@", musicItem.fileName, musicItem.filePath, musicItem.decryptedPath);
    
    // 🆕 优先检查是否已有解密后的文件（NCM 转 MP3）
    if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
        playPath = musicItem.decryptedPath;
        NSLog(@"✅ 使用已解密文件播放: %@", playPath);
    }
    // 🔧 检查是否是NCM文件，如果是则需要先解密
    else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
        NSLog(@"🔓 检测到NCM文件，开始自动解密...");
        
        // 🔧 优先传递完整路径（如果有的话）
        NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
        playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];
        
        // 如果解密成功，更新 MusicItem 的解密路径
        if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
            NSLog(@"✅ 自动解密成功: %@", playPath);
        }
    }
    // 检查是否有完整路径（云下载的文件）
    else if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
        // 使用完整路径（云下载文件或已存在的文件）
        playPath = musicItem.filePath;
        
        // 验证文件是否存在
        if ([[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            NSLog(@"✅ 使用完整路径播放: %@", playPath);
        } else {
            NSLog(@"❌ 文件不存在: %@，尝试从 Bundle 查找", playPath);
            // 文件不存在，尝试从 Bundle 查找
            playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
        }
    } else {
        // 使用文件名（Bundle 中的文件）
        playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
        NSLog(@"🎵 从 Bundle 播放: %@", playPath);
    }
    
    // 🎵 先设置基本的播放信息（立即设置，让控制中心显示）
    [self updateNowPlayingInfoImmediate];
    
    [self.player playWithFileName:playPath];
    
    // 🎵 注意：完整的播放信息将在 playerDidStartPlaying 回调中更新
}

// 🆕 转换NCM文件
- (void)convertNCMFile:(MusicItem *)musicItem atIndexPath:(NSIndexPath *)indexPath {
    NSLog(@"🔄 开始转换 NCM 文件: %@", musicItem.fileName);
    
    // 显示加载提示
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"⏳ 转换中" 
                                                                          message:@"正在转换 NCM 文件，请稍候..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 在后台线程执行转换
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 🔧 获取NCM文件路径 - 优先使用完整路径（导入的文件）
        NSURL *fileURL = nil;
        NSString *sourcePath = nil;
        
        // 1. 优先使用 filePath（导入的文件或云下载的文件）
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            sourcePath = musicItem.filePath;
            if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
                fileURL = [NSURL fileURLWithPath:sourcePath];
                NSLog(@"✅ 找到导入的NCM文件: %@", sourcePath);
            }
        }
        
        // 2. 如果没有找到，尝试从 Bundle 查找
        if (!fileURL) {
            fileURL = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
            if (fileURL) {
                sourcePath = fileURL.path;
                NSLog(@"✅ 找到Bundle中的NCM文件: %@", sourcePath);
            }
        }
        
        // 3. 尝试从 Audio 目录查找
        if (!fileURL) {
            NSString *audioPath = [[NSBundle mainBundle] pathForResource:@"Audio" ofType:nil];
            if (audioPath) {
                sourcePath = [audioPath stringByAppendingPathComponent:musicItem.fileName];
                if ([[NSFileManager defaultManager] fileExistsAtPath:sourcePath]) {
                    fileURL = [NSURL fileURLWithPath:sourcePath];
                    NSLog(@"✅ 找到Audio目录中的NCM文件: %@", sourcePath);
                }
            }
        }
        
        // 4. 如果都没找到，报错
        if (!fileURL || !sourcePath) {
            NSLog(@"❌ 找不到NCM文件: fileName=%@, filePath=%@", musicItem.fileName, musicItem.filePath);
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingAlert dismissViewControllerAnimated:YES completion:^{
                    [self showAlert:@"❌ 错误" message:[NSString stringWithFormat:@"找不到文件: %@", musicItem.fileName]];
                }];
            });
            return;
        }
        
        // 生成输出路径（在 Documents 目录）
        NSString *documentsPath = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
        NSString *outputFilename = [[musicItem.fileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"mp3"];
        NSString *outputPath = [documentsPath stringByAppendingPathComponent:outputFilename];
        
        // 执行解密
        NSError *error = nil;
        NSString *result = [NCMDecryptor decryptNCMFile:fileURL.path
                                             outputPath:outputPath
                                                  error:&error];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                if (result) {
                    NSLog(@"✅ NCM 转换成功: %@", result);
                    
                    // 更新 MusicItem 状态
                    [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:result];
                    
                    // 刷新 cell
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
                    
                    // 🆕 自动播放解密后的文件
                    NSLog(@"🎵 开始播放解密后的文件: %@", result);
                    [self.player playWithFileName:result];
                    
                    // 显示成功提示
                    [self showAlert:@"✅ 转换成功" message:[NSString stringWithFormat:@"已成功转换并开始播放: %@", musicItem.displayName ?: musicItem.fileName]];
                } else {
                    NSLog(@"❌ NCM 转换失败: %@", error.localizedDescription);
                    
                    // 显示失败提示
                    [self showAlert:@"❌ 转换失败" message:error.localizedDescription ?: @"未知错误"];
                    
                    // 刷新 cell 以重置按钮状态
                    [self.tableView reloadRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationNone];
                }
            }];
        });
    });
}

// 辅助方法：显示提示框
- (void)showAlert:(NSString *)title message:(NSString *)message {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:title 
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"好的" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)updateAudioSelection {
    // 更新背景圆环颜色
    if (backLayers) {
        backLayers.strokeColor = [UIColor colorWithRed:arc4random()%255/255.0 
                                                 green:arc4random()%255/255.0 
                                                  blue:arc4random()%255/255.0 
                                                 alpha:1.0].CGColor;
    }
    
    // 🆕 使用当前显示的音乐项
    if (index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        NSString *songName = musicItem.displayName ?: musicItem.fileName;
        
        // 🔧 修复：优先使用 filePath（导入的文件），否则从 Bundle 查找
        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
            NSLog(@"🖼️ 更新导入文件封面: %@", musicItem.filePath);
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
            NSLog(@"🖼️ 更新Bundle文件封面: %@", musicItem.fileName);
        }
        
        UIImage *image = [self musicImageWithMusicURL:fileUrl];
        
        // 🎵 根据是否有封面切换显示 imageView 或 vinylRecordView
        if (image) {
            // 有封面，显示 imageView
            imageView.image = image;
            imageView.hidden = NO;
            self.vinylRecordView.hidden = YES;
            
            // 如果之前在显示黑胶唱片，需要停止动画并重新设置旋转
            if (self.isShowingVinylRecord) {
                [self.vinylRecordView stopSpinning];
                self.isShowingVinylRecord = NO;
                
                // 重新添加 imageView 的旋转动画
                [self.animationCoordinator addRotationViews:@[imageView] 
                                                  rotations:@[@(6.0)] 
                                                  durations:@[@(120.0)] 
                                              rotationTypes:@[@(RotationTypeCounterClockwise)]];
            }
            
            // 更新粒子图像
            [self.animationCoordinator updateParticleImage:image];
            NSLog(@"🖼️ 显示音乐封面");
        } else {
            // 没有封面，显示黑胶唱片动画
            imageView.hidden = YES;
            self.vinylRecordView.hidden = NO;
            self.isShowingVinylRecord = YES;
            
            // 使用歌曲名称生成一致的随机外观
            [self.vinylRecordView regenerateAppearanceWithSongName:songName];
            
            // 如果正在播放，启动黑胶唱片旋转
            if (self.player.isPlaying) {
                [self.vinylRecordView startSpinning];
            }
            
            NSLog(@"🎵 显示黑胶唱片动画（无封面）: %@", songName);
        }
    }
}
#pragma mark - AudioSpectrumPlayerDelegate
- (void)playerDidGenerateSpectrum:(nonnull NSArray *)spectrums {
    dispatch_async(dispatch_get_main_queue(), ^{
        UIApplicationState state = [UIApplication sharedApplication].applicationState;
        if (state == UIApplicationStateBackground){
            return;
        }
        
        // 更新频谱视图
        [self.spectrumView updateSpectra:spectrums withStype:ADSpectraStyleRound];
        
        // 更新频谱动画（如果需要的话）
        if (self.animationCoordinator.spectrumManager) {
            [self.animationCoordinator updateSpectrumAnimations:spectrums];
        }
        
        // 更新高端视觉效果
        if (spectrums.count > 0) {
            NSArray *firstChannelData = spectrums.firstObject;
            [self.visualEffectManager updateSpectrumData:firstChannelData];
        }
    });
}
-(void)didFinishPlay
{
    // 🔧 检查是否禁止自动播放（用户在其他页面时）
    if (self.shouldPreventAutoResume) {
        NSLog(@"⏹️ 播放结束，但用户在其他页面，不自动播放下一首");
        return;
    }
    
    // 🔂 单曲循环模式：重新播放当前歌曲
    if (self.isSingleLoopMode) {
        NSLog(@"🔂 单曲循环：重新播放当前歌曲");
        [self playCurrentTrack];
        return;
    }
    
    // 🔁 列表循环模式：播放下一首
    index++;
    if (index >= self.displayedMusicItems.count)
    {
        index = 0;
    }
    
    // 🆕 记录播放
    if (index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        [self.musicLibrary recordPlayForMusic:musicItem];
    }
    
    [self updateAudioSelection];
    
    // 使用统一的播放方法
    [self playCurrentTrack];
}

#pragma mark - 歌词代理方法

- (void)playerDidLoadLyrics:(LRCParser *)parser {
    dispatch_async(dispatch_get_main_queue(), ^{
        if (parser) {
            NSLog(@"✅ 歌词加载成功: %@ - %@", parser.artist ?: @"未知", parser.title ?: @"未知");
            NSLog(@"   歌词行数: %lu", (unsigned long)parser.lyrics.count);
            
            // 显示歌词容器
            self.lyricsContainer.hidden = NO;
            
            // 更新歌词视图
            self.lyricsView.parser = parser;
        } else {
            NSLog(@"⚠️ 未找到歌词");
            // 显示歌词容器（显示"暂无lrc文件歌词"提示）
            self.lyricsContainer.hidden = NO;
            
            // 清空歌词视图，触发显示"暂无lrc文件歌词"消息
            self.lyricsView.parser = nil;
        }
    });
}

- (void)playerDidStartPlaying {
    // 🎵 关键：播放真正开始后才设置完整的播放信息
    NSLog(@"🎵 播放器已开始播放，更新系统媒体信息");
    
    // 🎵 更新播放/暂停按钮状态
    dispatch_async(dispatch_get_main_queue(), ^{
        [self.playPauseButton setTitle:@"⏸️" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.2 alpha:0.85];
    });
    
    // 延迟一点让播放器获取完整的时长信息
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.3 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        [self updateNowPlayingInfo];
        NSLog(@"✅ 播放开始后已更新完整媒体信息");
        
        // 🎵 更新进度条时长
        [self updateProgressWithDuration:self.player.duration];
        
        // 🔍 运行诊断测试（已禁用，不需要覆盖真实歌曲信息）
        // [self forceUpdateNowPlayingInfo];
    });
}

- (void)playerDidUpdateTime:(NSTimeInterval)currentTime {
    // 更新歌词显示
    [self.lyricsView updateWithTime:currentTime];
    
    // 🎵 更新进度条当前时间
    [self updateProgressWithCurrentTime:currentTime];
    
    // 🎵 定期更新系统播放进度（每5秒更新一次，避免频繁更新）
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    if (now - self.lastNowPlayingUpdateTime >= 5.0) {
        self.lastNowPlayingUpdateTime = now;
        
        // 更新当前播放时间
        NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
        if (nowPlayingInfo) {
            nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(currentTime);
            nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.player.isPlaying ? 1.0 : 0.0);
            [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
        }
    }
}
- (NSMutableArray *)audioArray {
    if (!_audioArray) {
        _audioArray = [NSMutableArray new];
    }
    return _audioArray;
}

- (AudioSpectrumPlayer *)player {
    if (!_player) {
        _player = [[AudioSpectrumPlayer alloc] init];
        _player.delegate = self;
    }
    return _player;
}
#pragma mark- 文件处理
- (UIImage*)musicImageWithMusicURL:(NSURL*)url {
    
    // 🔧 添加nil检查
    if (!url) {
        NSLog(@"⚠️ 无法获取封面：URL为空");
        return nil;
    }
    
    // 🔧 如果是NCM文件，尝试从解密后的MP3文件读取封面
    if ([url isFileURL] && [[url.path.pathExtension lowercaseString] isEqualToString:@"ncm"]) {
        NSString *ncmPath = url.path;
        NSString *baseName = [ncmPath stringByDeletingPathExtension];
        NSString *directory = [ncmPath stringByDeletingLastPathComponent];
        
        // 检查Documents目录中是否有解密后的文件
        NSArray *paths = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES);
        NSString *documentsDirectory = paths.firstObject;
        NSString *fileName = [ncmPath lastPathComponent];
        NSString *baseFileName = [fileName stringByDeletingPathExtension];
        
        // 尝试常见的音频格式
        NSArray *extensions = @[@"mp3", @"flac", @"m4a"];
        for (NSString *ext in extensions) {
            NSString *decryptedPath = [[documentsDirectory stringByAppendingPathComponent:baseFileName] stringByAppendingPathExtension:ext];
            if ([[NSFileManager defaultManager] fileExistsAtPath:decryptedPath]) {
                NSLog(@"🔄 NCM文件，从解密文件读取封面: %@", [decryptedPath lastPathComponent]);
                url = [NSURL fileURLWithPath:decryptedPath];
                break;
            }
        }
    }
    
    // 检查文件是否存在
    if ([url isFileURL]) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        if (![fileManager fileExistsAtPath:url.path]) {
            NSLog(@"⚠️ 无法获取封面：文件不存在: %@", url.path);
            return nil;
        }
        
        // 🆕 优先尝试从同目录加载独立的封面图片文件（云端下载的封面和NCM封面）
        UIImage *externalCover = [self loadExternalCoverForMusicFile:url.path];
        if (externalCover) {
            NSLog(@"✅ 使用外部封面文件: %@", url.path.lastPathComponent);
            return externalCover;
        }
    }
    
    NSData*data =nil;
    
    // 初始化媒体文件
    AVURLAsset*mp3Asset = [AVURLAsset URLAssetWithURL:url options:nil];
    
    NSLog(@"🔍 [封面读取] 文件: %@", url.path.lastPathComponent);
    NSLog(@"   可用格式数: %lu", (unsigned long)[mp3Asset availableMetadataFormats].count);

    // 读取文件中的数据
    for(NSString*format in [mp3Asset availableMetadataFormats]) {
        NSLog(@"   扫描格式: %@", format);
        
        for(AVMetadataItem*metadataItem in[mp3Asset metadataForFormat:format]) {
            //artwork这个key对应的value里面存的就是封面缩略图，其它key可以取出其它摘要信息，例如title - 标题
            
            if([metadataItem.commonKey isEqualToString:@"artwork"]) {
                data = [metadataItem.value copyWithZone:nil];
                NSLog(@"   ✅ 找到封面 metadata (格式: %@)", format);
                break;
            }
        }
        
        if (data) {
            break; // 已找到封面，退出外层循环
        }
    }
    
    if(!data) {
        // 如果音乐没有图片，就返回默认图片
        NSLog(@"⚠️ 无法获取封面：文件中没有封面数据: %@", url.path.lastPathComponent);
        return nil;//[UIImage imageNamed:@"default"];
        
    }
    
    NSLog(@"✅ 成功提取封面数据 (%.0f KB): %@", (CGFloat)data.length / 1024.0, url.path.lastPathComponent);
    
    UIImage *image = [UIImage imageWithData:data];
    if (!image) {
        NSLog(@"⚠️ 警告：封面数据无法转换为UIImage");
        return nil;
    }
    
    NSLog(@"✅ 封面图片创建成功 (%.0fx%.0f)", image.size.width, image.size.height);
    return image;
    
}

/// 🆕 从音乐文件所在目录加载外部封面文件（用于云端下载的封面和NCM封面）
- (UIImage *)loadExternalCoverForMusicFile:(NSString *)musicFilePath {
    if (!musicFilePath || musicFilePath.length == 0) {
        return nil;
    }
    
    // 获取音乐文件名（不含扩展名）
    NSString *baseFileName = [[musicFilePath lastPathComponent] stringByDeletingPathExtension];
    NSString *directory = [musicFilePath stringByDeletingLastPathComponent];
    
    // 支持的图片扩展名
    NSArray *imageExtensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    
    // 🔧 修复：尝试两种命名方式
    // 1. NCM解密生成的封面：歌曲名_cover.jpg
    // 2. 云端下载的封面：歌曲名.jpg
    NSArray *namingPatterns = @[@"%@_cover", @"%@"];
    
    for (NSString *pattern in namingPatterns) {
        NSString *fileName = [NSString stringWithFormat:pattern, baseFileName];
        for (NSString *ext in imageExtensions) {
            NSString *coverPath = [[directory stringByAppendingPathComponent:fileName] stringByAppendingPathExtension:ext];
            if ([[NSFileManager defaultManager] fileExistsAtPath:coverPath]) {
                UIImage *image = [UIImage imageWithContentsOfFile:coverPath];
                if (image) {
                    NSLog(@"🖼️ 找到外部封面: %@", [coverPath lastPathComponent]);
                    return image;
                }
            }
        }
    }
    
    return nil;
}

-(void)setImageAudio
{
    NSMutableArray *array = [NSMutableArray array];//CAEmitterCell数组，存放不同的CAEmitterCell，我这里准备了四张不同形态的叶子图片。
    for (int i = 1; i<9; i++) {
        //            NSString *imageName = [NSString stringWithFormat:@"WechatIMG3－%d",i];
        
        CAEmitterCell *leafCell = [CAEmitterCell emitterCell];
        leafCell.birthRate = 0.5;//粒子产生速度
        leafCell.lifetime =10;//粒子存活时间r
        
        leafCell.velocity = 1;//初始速度
        leafCell.velocityRange = 5;//初始速度的差值区间，所以初始速度为5~15，后面属性range算法相同
        
        leafCell.yAcceleration = 20;//y轴方向的加速度，落叶下飘只需要y轴正向加速度。
        leafCell.zAcceleration = 20;//y轴方向的加速度，落叶下飘只需要y轴正向加速度。
        
        leafCell.spin = 0.25;//粒子旋转速度
        leafCell.spinRange = 5;//粒子旋转速度范围
        
        leafCell.emissionRange = M_PI;//粒子发射角度范围
        
        //        leafCell.contents = (id)[[UIImage imageNamed:imageName] CGImage];//粒子图片
        // 🔧 修复：使用 displayedMusicItems 并支持导入的文件
        NSURL *fileUrl = nil;
        if (index < self.displayedMusicItems.count) {
            MusicItem *musicItem = self.displayedMusicItems[index];
            if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
                fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
            } else {
                fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
            }
        }
        leafCell.contents = (id)[[self musicImageWithMusicURL:fileUrl] CGImage];//粒子图片
        leafCell.color = [UIColor whiteColor].CGColor;
        leafCell.scale = 0.03;//缩放比例
        leafCell.scaleRange = 0.03;//缩放比例
        
        leafCell.alphaSpeed = -0.22;
        leafCell.alphaRange = -0.8;
        
        [array addObject:leafCell];
    }
    
    self.leafEmitter.emitterCells = array;//设置粒子组
}

#pragma mark - 特效控制按钮事件

- (void)effectSelectorButtonTapped:(UIButton *)sender {
    [self.visualEffectManager showEffectSelector];
}

- (void)galaxyControlButtonTapped:(UIButton *)sender {
    if (!self.galaxyControlPanel) {
        self.galaxyControlPanel = [[GalaxyControlPanel alloc] initWithFrame:CGRectMake(20, 100, 
                                                                                       self.view.bounds.size.width - 40, 
                                                                                       self.view.bounds.size.height - 200)];
        self.galaxyControlPanel.delegate = self;
        [self.view addSubview:self.galaxyControlPanel];
    }
    
    [self.galaxyControlPanel showAnimated:YES];
}

- (void)cyberpunkControlButtonTapped:(UIButton *)sender {
    if (!self.cyberpunkControlPanel) {
        // 增加高度以容纳新增的网格和背景控制
        self.cyberpunkControlPanel = [[CyberpunkControlPanel alloc] initWithFrame:CGRectMake(20, 100, 
                                                                                             self.view.bounds.size.width - 40, 
                                                                                             550)];
        self.cyberpunkControlPanel.delegate = self;
        [self.view addSubview:self.cyberpunkControlPanel];
        
        // 设置默认值（全部开启，包含新增的网格和背景控制）
        NSDictionary *defaultSettings = @{
            @"enableClimaxEffect": @(1.0),
            @"enableBassEffect": @(1.0),
            @"enableMidEffect": @(1.0),
            @"enableTrebleEffect": @(1.0),
            @"showDebugBars": @(0.0),  // 调试条默认关闭
            @"enableGrid": @(1.0),     // 网格默认开启
            @"backgroundMode": @(0.0), // 默认网格背景模式
            @"solidColorR": @(0.15),
            @"solidColorG": @(0.1),
            @"solidColorB": @(0.25),
            @"backgroundIntensity": @(0.8)
        };
        [self.cyberpunkControlPanel setCurrentSettings:defaultSettings];
        
        // 🔋 优化：减少日志输出
        [self.visualEffectManager setRenderParameters:defaultSettings];
    }
    
    [self.cyberpunkControlPanel showAnimated:YES];
    [self.view bringSubviewToFront:self.cyberpunkControlPanel];
}

// 🎨 处理特效配置按钮点击（从特效选择器中）
- (void)handleEffectSettingsButtonTapped:(NSNotification *)notification {
    VisualEffectType effectType = [notification.userInfo[@"effectType"] integerValue];
    
    NSLog(@"🎨 收到特效配置请求: %ld", (long)effectType);
    
    // 根据特效类型打开对应的配置面板
    if (effectType == VisualEffectTypeGalaxy) {
        [self galaxyControlButtonTapped:nil];
    } else if (effectType == VisualEffectTypeCyberPunk) {
        [self cyberpunkControlButtonTapped:nil];
    }
}

- (void)quickEffectButtonTapped:(UIButton *)sender {
    VisualEffectType effectType = (VisualEffectType)sender.tag;
    
    // 检查设备是否支持该特效
    if ([self.visualEffectManager isEffectSupported:effectType]) {
        [self.visualEffectManager setCurrentEffect:effectType animated:YES];
        
        // 视觉反馈
        [UIView animateWithDuration:0.2 animations:^{
            sender.transform = CGAffineTransformMakeScale(1.2, 1.2);
            sender.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.5 alpha:0.9];
        } completion:^(BOOL finished) {
            [UIView animateWithDuration:0.2 animations:^{
                sender.transform = CGAffineTransformIdentity;
                sender.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.7];
            }];
        }];
    } else {
        // 不支持的特效，显示提示
        [self showUnsupportedEffectAlert];
    }
}

- (void)showUnsupportedEffectAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"特效不支持" 
                                                                   message:@"该特效需要更高性能的设备支持" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                       style:UIAlertActionStyleDefault 
                                                     handler:nil];
    [alert addAction:okAction];
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - VisualEffectManagerDelegate

- (void)visualEffectManager:(VisualEffectManager *)manager didChangeEffect:(VisualEffectType)effectType {
    // 🔋 优化：减少日志输出
    // NSLog(@"🎨 特效切换完成");
    
    // 开始渲染新特效
    [manager startRendering];
    
    // 更新UI状态
    [self updateEffectButtonStates:effectType];
}

- (void)visualEffectManager:(VisualEffectManager *)manager didUpdatePerformance:(NSDictionary *)stats {
    NSNumber *fps = stats[@"fps"];
    if (fps && [fps doubleValue] < 20.0) {
        NSLog(@"⚠️ 性能警告: FPS过低 (%.1f)", [fps doubleValue]);
    }
}

- (void)visualEffectManager:(VisualEffectManager *)manager didEncounterError:(NSError *)error {
    NSLog(@"❌ 视觉效果错误: %@", error.localizedDescription);
}

- (void)updateEffectButtonStates:(VisualEffectType)currentEffect {
    // 更新快捷按钮的选中状态
    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIButton class]] && subview.tag >= 0 && subview.tag < VisualEffectTypeCount) {
            UIButton *button = (UIButton *)subview;
            if (button.tag == currentEffect) {
                button.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.8];
            } else {
                button.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.2 alpha:0.7];
            }
        }
    }
}

#pragma mark - GalaxyControlDelegate

- (void)galaxyControlDidUpdateSettings:(NSDictionary *)settings {
    // 🔋 优化：减少参数更新日志
    // 应用新的星系设置
    [self.visualEffectManager setRenderParameters:settings];
    
    // 如果当前不是星系效果，自动切换到星系效果
    if (self.visualEffectManager.currentEffectType != VisualEffectTypeGalaxy) {
        [self.visualEffectManager setCurrentEffect:VisualEffectTypeGalaxy animated:YES];
        [self updateEffectButtonStates:VisualEffectTypeGalaxy];
    }
}

#pragma mark - CyberpunkControlDelegate

- (void)cyberpunkControlDidUpdateSettings:(NSDictionary *)settings {
    // 🔋 优化：减少参数更新日志
    // 应用新的赛博朋克设置
    [self.visualEffectManager setRenderParameters:settings];
    
    // 如果当前不是赛博朋克效果，自动切换到赛博朋克效果
    if (self.visualEffectManager.currentEffectType != VisualEffectTypeCyberPunk) {
        [self.visualEffectManager setCurrentEffect:VisualEffectTypeCyberPunk animated:YES];
        [self updateEffectButtonStates:VisualEffectTypeCyberPunk];
    }
}

#pragma mark - PerformanceControlDelegate

- (void)performanceControlDidUpdateSettings:(NSDictionary *)settings {
    NSLog(@"📥 ViewController收到性能设置: %@", settings);
    NSLog(@"   设置类型: %@", [settings class]);
    NSLog(@"   设置数量: %lu", (unsigned long)[settings count]);
    
    if (settings && [settings count] > 0) {
        NSLog(@"   fps=%@, msaa=%@, shader=%@, mode=%@",
              settings[@"fps"], settings[@"msaa"], settings[@"shaderComplexity"], settings[@"mode"]);
    }
    
    // 应用性能设置到视觉效果管理器
    [self.visualEffectManager applyPerformanceSettings:settings];
}

#pragma mark - 性能控制按钮

- (void)performanceControlButtonTapped:(UIButton *)sender {
    if (!self.performanceControlPanel) {
        self.performanceControlPanel = [[PerformanceControlPanel alloc] initWithFrame:CGRectMake(20, 100, 
                                                                                                 self.view.bounds.size.width - 40, 
                                                                                                 self.view.bounds.size.height - 200)];
        self.performanceControlPanel.delegate = self;
        [self.view addSubview:self.performanceControlPanel];
        
        // 设置当前性能参数
        NSDictionary *currentSettings = @{
            @"fps": @(30),
            @"msaa": @(1),
            @"mode": @"balanced",
            @"shaderComplexity": @(1.0)
        };
        [self.performanceControlPanel setCurrentSettings:currentSettings];
    }
    
    [self.performanceControlPanel showAnimated:YES];
    [self.view bringSubviewToFront:self.performanceControlPanel];
}

- (void)karaokeButtonTapped:(UIButton *)sender {
    // 检查是否有选中的歌曲
    if (self.displayedMusicItems.count == 0 || index >= self.displayedMusicItems.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                       message:@"请先选择一首歌曲" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:nil];
        [alert addAction:okAction];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    // 🔧 标记禁止自动恢复播放（进入其他页面时不应自动恢复）
    self.shouldPreventAutoResume = YES;
    
    // 创建卡拉OK视图控制器
    KaraokeViewController *karaokeVC = [[KaraokeViewController alloc] init];
    MusicItem *musicItem = self.displayedMusicItems[index];
    karaokeVC.currentSongName = musicItem.fileName;
    
    // 🔧 获取可播放的文件路径（自动处理 ncm 解密）
    NSString *playablePath = [musicItem playableFilePath];
    karaokeVC.currentSongPath = playablePath;
    
    NSLog(@"🎤 进入卡拉OK模式: %@ -> %@", musicItem.fileName, playablePath);
    
    // 推送到卡拉OK页面（现在有NavigationController了）
    [self.navigationController pushViewController:karaokeVC animated:YES];
}

- (void)lyricsEffectButtonTapped:(UIButton *)sender {
    if (!self.lyricsEffectPanel) {
        self.lyricsEffectPanel = [[LyricsEffectControlPanel alloc] initWithFrame:self.view.bounds];
        self.lyricsEffectPanel.delegate = self;
        [self.view addSubview:self.lyricsEffectPanel];
        
        // 设置当前特效
        if (self.lyricsView) {
            self.lyricsEffectPanel.currentEffect = self.lyricsView.currentEffect;
        }
    }
    
    // 同步歌词可见性状态
    self.lyricsEffectPanel.lyricsVisible = (self.lyricsContainer.alpha > 0.5);
    
    [self.lyricsEffectPanel showAnimated:YES];
    [self.view bringSubviewToFront:self.lyricsEffectPanel];
    
    NSLog(@"🎭 打开歌词特效面板");
}

#pragma mark - 📝 导入歌词

- (void)importLyricsButtonTapped:(UIButton *)sender {
    // 🔧 隐藏键盘
    [self.searchBar resignFirstResponder];
    
    // 检查是否有选中的歌曲
    if (self.displayedMusicItems.count == 0 || index < 0 || index >= self.displayedMusicItems.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                       message:@"请先选择要关联歌词的歌曲" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:nil];
        [alert addAction:okAction];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    MusicItem *currentMusicItem = self.displayedMusicItems[index];
    NSLog(@"📝 为歌曲导入歌词: %@", currentMusicItem.fileName);
    
    // 显示选择面板：导入新歌词 or 自动匹配
    UIAlertController *actionSheet = [UIAlertController alertControllerWithTitle:@"导入歌词" 
                                                                         message:[NSString stringWithFormat:@"为「%@」导入歌词", currentMusicItem.fileName]
                                                                  preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 选择 LRC 文件
    UIAlertAction *importAction = [UIAlertAction actionWithTitle:@"📂 从文件选择 LRC" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:^(UIAlertAction * _Nonnull action) {
        [self openLRCFilePicker];
    }];
    [actionSheet addAction:importAction];
    
    // 批量导入歌词
    UIAlertAction *batchImportAction = [UIAlertAction actionWithTitle:@"📁 批量导入歌词文件" 
                                                                style:UIAlertActionStyleDefault 
                                                              handler:^(UIAlertAction * _Nonnull action) {
        [self openBatchLRCFilePicker];
    }];
    [actionSheet addAction:batchImportAction];
    
    // 取消
    UIAlertAction *cancelAction = [UIAlertAction actionWithTitle:@"取消" 
                                                           style:UIAlertActionStyleCancel 
                                                         handler:nil];
    [actionSheet addAction:cancelAction];
    
    // iPad 需要设置 popover
    if (UI_USER_INTERFACE_IDIOM() == UIUserInterfaceIdiomPad) {
        actionSheet.popoverPresentationController.sourceView = sender;
        actionSheet.popoverPresentationController.sourceRect = sender.bounds;
    }
    
    [self presentViewController:actionSheet animated:YES completion:nil];
}

- (void)openLRCFilePicker {
    NSLog(@"📂 打开 LRC 文件选择器...");
    
    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        // iOS 14+ 使用 UTType
        UTType *lrcType = [UTType typeWithFilenameExtension:@"lrc"];
        UTType *txtType = UTTypeText;
        
        NSMutableArray *contentTypes = [NSMutableArray array];
        if (lrcType) {
            [contentTypes addObject:lrcType];
        }
        [contentTypes addObject:txtType];
        
        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    } else {
        // iOS 13 及以下版本
        NSArray *lrcTypes = @[
            @"public.text",
            @"public.plain-text",
            @"public.data"
        ];
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:lrcTypes inMode:UIDocumentPickerModeImport];
    }
    
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = NO;  // 单选模式（关联当前歌曲）
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // 使用 accessibilityHint 标记这是歌词导入
    documentPicker.view.accessibilityHint = @"lyrics_import_single";
    
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark - 🎼 歌词打轴

- (void)lyricsTimingButtonTapped:(UIButton *)sender {
    // 🔧 隐藏键盘
    [self.searchBar resignFirstResponder];
    
    // 检查是否有选中的歌曲
    if (self.displayedMusicItems.count == 0 || index < 0 || index >= self.displayedMusicItems.count) {
        UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"提示" 
                                                                       message:@"请先选择要打轴的歌曲" 
                                                                preferredStyle:UIAlertControllerStyleAlert];
        
        UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" 
                                                           style:UIAlertActionStyleDefault 
                                                         handler:nil];
        [alert addAction:okAction];
        
        [self presentViewController:alert animated:YES completion:nil];
        return;
    }
    
    MusicItem *currentMusicItem = self.displayedMusicItems[index];
    NSLog(@"🎼 进入歌词打轴: %@", currentMusicItem.fileName);
    
    // 停止当前播放
    [self.player stop];
    
    // 🔧 标记禁止自动恢复播放（进入其他页面时不应自动恢复）
    self.shouldPreventAutoResume = YES;
    
    // 创建歌词编辑器
    LyricsEditorViewController *editor = [[LyricsEditorViewController alloc] initWithAudioFilePath:[currentMusicItem playableFilePath]];
    
    // 设置歌曲信息
    editor.songTitle = currentMusicItem.displayName ?: currentMusicItem.fileName;
    editor.artistName = currentMusicItem.artist;
    editor.albumName = currentMusicItem.album;
    
    // 设置代理
    editor.delegate = (id<LyricsEditorViewControllerDelegate>)self;
    
    // 🔧 改为 push 操作（而非模态展示）
    [self.navigationController pushViewController:editor animated:YES];
}

#pragma mark - LyricsEditorViewControllerDelegate

- (void)lyricsEditor:(LyricsEditorViewController *)editor didFinishWithLRCContent:(NSString *)lrcContent {
    NSLog(@"🎼 歌词打轴完成，LRC 内容长度: %lu", (unsigned long)lrcContent.length);
}

- (void)lyricsEditor:(LyricsEditorViewController *)editor didSaveLRCToPath:(NSString *)path {
    NSLog(@"🎼 歌词已保存到: %@", path);
    
    // 可选：刷新当前歌曲的歌词显示
    if (index >= 0 && index < self.displayedMusicItems.count) {
        MusicItem *currentMusicItem = self.displayedMusicItems[index];
        [[LyricsManager sharedManager] clearLyricsCacheForAudioFile:currentMusicItem.filePath];
        // 重新加载歌词
        [self.player loadLyricsForCurrentTrack];
    }
}

- (void)lyricsEditorDidCancel:(LyricsEditorViewController *)editor {
    NSLog(@"🎼 歌词打轴已取消");
}

- (void)openBatchLRCFilePicker {
    NSLog(@"📁 打开批量 LRC 文件选择器...");
    
    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        UTType *lrcType = [UTType typeWithFilenameExtension:@"lrc"];
        UTType *txtType = UTTypeText;
        
        NSMutableArray *contentTypes = [NSMutableArray array];
        if (lrcType) {
            [contentTypes addObject:lrcType];
        }
        [contentTypes addObject:txtType];
        
        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    } else {
        NSArray *lrcTypes = @[
            @"public.text",
            @"public.plain-text",
            @"public.data"
        ];
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:lrcTypes inMode:UIDocumentPickerModeImport];
    }
    
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;  // 多选模式
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    
    // 使用 accessibilityHint 标记这是批量歌词导入
    documentPicker.view.accessibilityHint = @"lyrics_import_batch";
    
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark - 歌词视图设置

- (void)setupLyricsView {
    // 创建歌词容器（缩小高度）
    CGFloat containerWidth = self.view.bounds.size.width - 40;
    CGFloat containerHeight = 180; // 从 300 缩小到 180
    CGFloat containerY = self.view.bounds.size.height - containerHeight - 120; // 在底部但不遮挡列表
    
    self.lyricsContainer = [[UIView alloc] initWithFrame:CGRectMake(20, 
                                                                     containerY, 
                                                                     containerWidth, 
                                                                     containerHeight)];
    self.lyricsContainer.backgroundColor = [UIColor clearColor];
    self.lyricsContainer.layer.cornerRadius = 15;
    self.lyricsContainer.clipsToBounds = YES;
    
    // 将歌词容器添加到歌单view的下面（层级调整）
    if (self.tableView) {
        [self.view insertSubview:self.lyricsContainer belowSubview:self.tableView];
    } else {
        [self.view addSubview:self.lyricsContainer];
    }
    
    // 创建歌词视图
    self.lyricsView = [[LyricsView alloc] initWithFrame:self.lyricsContainer.bounds];
    self.lyricsView.backgroundColor = [UIColor clearColor];
    
    // 自定义歌词样式 - 缩小字体
    self.lyricsView.highlightColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];  // 青色高亮
    self.lyricsView.normalColor = [UIColor colorWithWhite:1.0 alpha:0.5];
    self.lyricsView.highlightFont = [UIFont boldSystemFontOfSize:16]; // 从 18 缩小到 16
    self.lyricsView.lyricsFont = [UIFont systemFontOfSize:13];        // 从 15 缩小到 13
    self.lyricsView.lineSpacing = 18; // 从 25 缩小到 18
    self.lyricsView.autoScroll = YES;
    
    [self.lyricsContainer addSubview:self.lyricsView];
    
    // 🎨 添加上下渐变遮罩层（模糊边缘效果）
    [self addGradientMaskToLyricsContainer];
    
    // 默认隐藏，等歌词加载后再显示
    self.lyricsContainer.hidden = YES;
    
    // 添加点击手势 - 点击歌词容器可以切换显示/隐藏
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self 
                                                                                 action:@selector(toggleLyricsView:)];
    tapGesture.numberOfTapsRequired = 2; // 双击切换
    [self.lyricsContainer addGestureRecognizer:tapGesture];
    
    NSLog(@"🎵 歌词视图已创建（优化版：缩小尺寸 + 渐变边缘）");
}

// 添加渐变遮罩，实现上下模糊边缘效果
- (void)addGradientMaskToLyricsContainer {
    // 创建渐变图层作为遮罩
    CAGradientLayer *gradientMask = [CAGradientLayer layer];
    gradientMask.frame = self.lyricsContainer.bounds;
    
    // 设置渐变颜色：从透明到不透明再到透明
    gradientMask.colors = @[
        (id)[UIColor clearColor].CGColor,              // 顶部完全透明
        (id)[UIColor colorWithWhite:1.0 alpha:0.3].CGColor,  // 顶部渐变
        (id)[UIColor whiteColor].CGColor,              // 中间不透明
        (id)[UIColor whiteColor].CGColor,              // 中间不透明
        (id)[UIColor colorWithWhite:1.0 alpha:0.3].CGColor,  // 底部渐变
        (id)[UIColor clearColor].CGColor               // 底部完全透明
    ];
    
    // 设置渐变位置：上下各 20% 渐变区域
    gradientMask.locations = @[@0.0, @0.15, @0.25, @0.75, @0.85, @1.0];
    
    // 设置为垂直渐变
    gradientMask.startPoint = CGPointMake(0.5, 0);
    gradientMask.endPoint = CGPointMake(0.5, 1);
    
    // 应用遮罩
    self.lyricsContainer.layer.mask = gradientMask;
}

- (void)toggleLyricsView:(UITapGestureRecognizer *)gesture {
    // 双击切换歌词容器的显示状态
    [UIView animateWithDuration:0.3 animations:^{
        self.lyricsContainer.alpha = self.lyricsContainer.alpha > 0.5 ? 0.3 : 1.0;
    }];
}

#pragma mark - FPS监控

- (void)setupFPSMonitor {
    // 创建FPS标签
    self.fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.view.bounds.size.width - 100, 40, 90, 70)];
    self.fpsLabel.backgroundColor = [[UIColor blackColor] colorWithAlphaComponent:0.7];
    self.fpsLabel.textColor = [UIColor greenColor];
    self.fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:13 weight:UIFontWeightBold];
    self.fpsLabel.textAlignment = NSTextAlignmentCenter;
    self.fpsLabel.numberOfLines = 4;
    self.fpsLabel.layer.cornerRadius = 8;
    self.fpsLabel.layer.masksToBounds = YES;
    self.fpsLabel.layer.borderWidth = 1;
    self.fpsLabel.layer.borderColor = [UIColor greenColor].CGColor;
    self.fpsLabel.text = @"FPS: --\n目标: --\nMetal: --\n负载: --";
    [self.view addSubview:self.fpsLabel];
    [self.view bringSubviewToFront:self.fpsLabel];
    
    // 创建DisplayLink来监控FPS
    self.fpsDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFPS:)];
    [self.fpsDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];
    
    self.frameCount = 0;
    self.lastTimestamp = 0;
    
    NSLog(@"✅ FPS监视器已启动");
}

- (void)updateFPS:(CADisplayLink *)displayLink {
    // 获取Metal视图的目标FPS设置
    NSInteger targetFPS = 30;  // 默认值
    BOOL isPaused = YES;
    
    if (self.visualEffectManager && self.visualEffectManager.metalView) {
        targetFPS = self.visualEffectManager.metalView.preferredFramesPerSecond;
        isPaused = self.visualEffectManager.metalView.isPaused;
    }
    
    // 🔧 关键修复：直接使用目标FPS，而不是计算屏幕刷新率
    // CADisplayLink 总是以屏幕刷新率运行（60Hz），不能用来测量Metal的实际FPS
    CGFloat displayFPS = targetFPS;
    
    // 如果暂停，FPS为0
    if (isPaused) {
        displayFPS = 0;
    }
    
    // 根据FPS设置颜色
    UIColor *fpsColor;
    NSString *statusEmoji;
    if (displayFPS >= 55) {
        fpsColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.3 alpha:1.0]; // 亮绿
        statusEmoji = @"🟢";
    } else if (displayFPS >= 25) {
        fpsColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0]; // 橙黄色
        statusEmoji = @"🟡";
    } else if (displayFPS > 0) {
        fpsColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0]; // 红色
        statusEmoji = @"🔴";
    } else {
        fpsColor = [UIColor grayColor];
        statusEmoji = @"⚫️";
    }
    
    // 更新标签（每次刷新都更新，确保实时显示）
    self.fpsLabel.textColor = fpsColor;
    self.fpsLabel.layer.borderColor = fpsColor.CGColor;
    
    NSString *statusText = isPaused ? @"⏸暂停" : @"▶️运行";
    NSString *loadText = isPaused ? @"0%" : @"100%";
    
    self.fpsLabel.text = [NSString stringWithFormat:@"%@ %.0f FPS\n目标: %ld\n%@\n负载: %@", 
                          statusEmoji,
                          displayFPS, 
                          (long)targetFPS,
                          statusText,
                          loadText];
}

#pragma mark - 音乐库管理器方法

- (void)setupMusicLibrary {
    // 初始化音乐库管理器
    self.musicLibrary = [MusicLibraryManager sharedManager];
    
    // 设置初始分类和排序
    self.currentCategory = MusicCategoryAll;
    self.currentSortType = MusicSortByName;
    self.sortAscending = YES;
    
    // 加载音乐列表
    [self refreshMusicList];
    
    NSLog(@"🎵 音乐库初始化完成: %ld 首歌曲", (long)self.musicLibrary.totalMusicCount);
}

- (void)refreshMusicList {
    // 获取当前分类的音乐
    NSArray<MusicItem *> *musicList = [self.musicLibrary musicForCategory:self.currentCategory];
    
    // 应用搜索过滤（如果有搜索词）
    if (self.searchBar.text.length > 0) {
        musicList = [self.musicLibrary searchMusic:self.searchBar.text inCategory:self.currentCategory];
    }
    
    // 应用排序
    self.displayedMusicItems = [self.musicLibrary sortMusic:musicList 
                                                      byType:self.currentSortType 
                                                   ascending:self.sortAscending];
    
    // 刷新表格
    [self.tableView reloadData];
    
    NSLog(@"🔄 音乐列表已刷新: %ld 首", (long)self.displayedMusicItems.count);
}

#pragma mark - UI 事件处理

- (void)categoryButtonTapped:(UIButton *)sender {
    // 🔧 隐藏键盘
    [self.searchBar resignFirstResponder];
    
    // 获取选中的分类
    MusicCategory selectedCategory = (MusicCategory)sender.tag;
    self.currentCategory = selectedCategory;
    
    // 更新所有分类按钮的样式
    for (UIButton *btn in self.categoryButtons) {
        if (btn.tag == selectedCategory) {
            // 选中状态 - 蓝色高亮
            btn.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:0.9];
            btn.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
            btn.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } else {
            // 未选中状态 - 灰色
            btn.backgroundColor = [UIColor colorWithWhite:0.2 alpha:0.85];
            btn.layer.borderColor = [UIColor colorWithWhite:0.4 alpha:0.6].CGColor;
            btn.transform = CGAffineTransformIdentity;
        }
    }
    
    // 刷新音乐列表
    [self refreshMusicList];
    
    NSLog(@"📂 切换分类: %@ (%ld 首)", [MusicLibraryManager nameForCategory:self.currentCategory], (long)self.displayedMusicItems.count);
}

- (void)reloadMusicLibraryButtonTapped:(UIButton *)sender {
    // 🔧 隐藏键盘
    [self.searchBar resignFirstResponder];
    
    NSLog(@"🔄 开始重新扫描音乐库...");
    
    // 显示加载提示
    UIAlertController *loadingAlert = [UIAlertController alertControllerWithTitle:@"正在扫描"
                                                                          message:@"正在重新扫描音频文件..."
                                                                   preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:loadingAlert animated:YES completion:nil];
    
    // 异步执行重新加载
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        // 重新加载音乐库（会重新扫描文件）
        [self.musicLibrary reloadMusicLibrary];
        
        dispatch_async(dispatch_get_main_queue(), ^{
            // 刷新列表
            [self refreshMusicList];
            
            // 关闭加载提示
            [loadingAlert dismissViewControllerAnimated:YES completion:^{
                // 显示完成提示
                NSString *message = [NSString stringWithFormat:@"发现 %ld 首歌曲", (long)self.musicLibrary.totalMusicCount];
                UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 扫描完成"
                                                                                      message:message
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [successAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:successAlert animated:YES completion:nil];
                
                NSLog(@"✅ 音乐库重新加载完成: %ld 首歌曲", (long)self.musicLibrary.totalMusicCount);
            }];
        });
    });
}

- (void)importMusicButtonTapped:(UIButton *)sender {
    // 🔧 隐藏键盘
    [self.searchBar resignFirstResponder];
    
    NSLog(@"📥 打开文件选择器导入音乐...");
    
    UIDocumentPickerViewController *documentPicker;
    if (@available(iOS 14.0, *)) {
        // iOS 14+ 使用 UTType
        NSMutableArray *contentTypes = [NSMutableArray array];
        
        // 添加常见音频格式
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"mp3"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"m4a"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"flac"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"wav"]];
        [contentTypes addObject:[UTType typeWithFilenameExtension:@"aac"]];
        
        // 🔧 添加 NCM 格式支持
        UTType *ncmType = [UTType typeWithFilenameExtension:@"ncm"];
        if (ncmType) {
            [contentTypes addObject:ncmType];
        }
        
        documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:contentTypes];
    } else {
        // iOS 13 及以下版本 - 使用通用的文档类型，可以选择任何文件
        NSArray *audioTypes = @[
            @"public.audio",           // 通用音频
            @"public.mp3",             // MP3
            @"public.mpeg-4-audio",    // M4A
            @"public.data",            // 通用数据（包括 NCM）
            @"public.item"             // 通用项目（兜底）
        ];
        documentPicker = [[UIDocumentPickerViewController alloc] initWithDocumentTypes:audioTypes inMode:UIDocumentPickerModeImport];
    }
    
    documentPicker.delegate = self;
    documentPicker.allowsMultipleSelection = YES;  // 允许多选
    documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
    
    [self presentViewController:documentPicker animated:YES completion:nil];
}

#pragma mark - 🎵 播放控制按钮事件处理

/// 上一首按钮点击
- (void)previousButtonTapped:(UIButton *)sender {
    NSLog(@"⏮️ 点击上一首按钮");
    [self playPrevious];
}

/// 下一首按钮点击
- (void)nextButtonTapped:(UIButton *)sender {
    NSLog(@"⏭️ 点击下一首按钮");
    [self playNext];
}

/// 播放/暂停按钮点击
- (void)playPauseButtonTapped:(UIButton *)sender {
    if (self.player.isPlaying) {
        NSLog(@"⏸️ 暂停播放");
        [self stopPlayback];
        [self.playPauseButton setTitle:@"▶️" forState:UIControlStateNormal];
        self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.85];
    } else {
        NSLog(@"▶️ 开始播放");
        if (self.displayedMusicItems.count > 0) {
            // 如果有选中的歌曲，播放当前选中的歌曲
            [self playCurrentTrack];
            [self.playPauseButton setTitle:@"⏸️" forState:UIControlStateNormal];
            self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.3 blue:0.2 alpha:0.85];
        } else {
            NSLog(@"⚠️ 播放列表为空");
        }
    }
}

/// 单曲循环按钮点击
- (void)loopButtonTapped:(UIButton *)sender {
    self.isSingleLoopMode = !self.isSingleLoopMode;
    
    if (self.isSingleLoopMode) {
        NSLog(@"🔂 切换为单曲循环模式");
        [self.loopButton setTitle:@"🔂" forState:UIControlStateNormal];
        self.loopButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.5 alpha:0.85];
        self.loopButton.layer.borderColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.6 alpha:0.8].CGColor;
    } else {
        NSLog(@"🔁 切换为列表循环模式");
        [self.loopButton setTitle:@"🔁" forState:UIControlStateNormal];
        self.loopButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.7 alpha:0.85];
        self.loopButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.8 alpha:0.8].CGColor;
    }
}

- (void)sortButtonTapped:(UIButton *)sender {
    // 🔧 隐藏键盘
    [self.searchBar resignFirstResponder];
    
    // 创建排序选项菜单
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"排序方式" 
                                                                   message:@"选择排序方式" 
                                                            preferredStyle:UIAlertControllerStyleActionSheet];
    
    // 按名称排序
    [alert addAction:[UIAlertAction actionWithTitle:@"按名称 A-Z" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByName;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];
    
    // 按艺术家排序
    [alert addAction:[UIAlertAction actionWithTitle:@"按艺术家 A-Z" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByArtist;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];
    
    // 按播放次数排序
    [alert addAction:[UIAlertAction actionWithTitle:@"按播放次数（最多）" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByPlayCount;
        self.sortAscending = NO;
        [self refreshMusicList];
    }]];
    
    // 按添加日期排序
    [alert addAction:[UIAlertAction actionWithTitle:@"按添加日期（最新）" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByDate;
        self.sortAscending = NO;
        [self refreshMusicList];
    }]];
    
    // 按时长排序
    [alert addAction:[UIAlertAction actionWithTitle:@"按时长（短到长）" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByDuration;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];
    
    // 按文件大小排序
    [alert addAction:[UIAlertAction actionWithTitle:@"按文件大小（小到大）" 
                                              style:UIAlertActionStyleDefault 
                                            handler:^(UIAlertAction *action) {
        self.currentSortType = MusicSortByFileSize;
        self.sortAscending = YES;
        [self refreshMusicList];
    }]];
    
    // 取消按钮
    [alert addAction:[UIAlertAction actionWithTitle:@"取消" 
                                              style:UIAlertActionStyleCancel 
                                            handler:nil]];
    
    // 对于 iPad，设置 popover 的源
    if (alert.popoverPresentationController) {
        alert.popoverPresentationController.sourceView = sender;
        alert.popoverPresentationController.sourceRect = sender.bounds;
    }
    
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - UISearchBarDelegate

- (void)searchBar:(UISearchBar *)searchBar textDidChange:(NSString *)searchText {
    [self refreshMusicList];
}

- (void)searchBarSearchButtonClicked:(UISearchBar *)searchBar {
    [searchBar resignFirstResponder];
    [self refreshMusicList];
}

- (void)searchBarCancelButtonClicked:(UISearchBar *)searchBar {
    searchBar.text = @"";
    [searchBar resignFirstResponder];
    [self refreshMusicList];
}

// 🔧 点击背景隐藏键盘
- (void)dismissKeyboard {
    [self.searchBar resignFirstResponder];
}

#pragma mark - UIScrollViewDelegate

// 🔧 开始拖动时隐藏键盘
- (void)scrollViewWillBeginDragging:(UIScrollView *)scrollView {
    if (scrollView == self.tableView) {
        [self.searchBar resignFirstResponder];
    }
}

- (void)dealloc {
    // 清理FPS监视器
    [self.fpsDisplayLink invalidate];
    self.fpsDisplayLink = nil;
    
    // 清理通知观察者
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - LyricsEffectControlDelegate

- (void)lyricsEffectDidChange:(LyricsEffectType)effectType {
    NSLog(@"🎭 歌词特效已切换: %@", [LyricsEffectManager nameForEffect:effectType]);
    
    if (self.lyricsView) {
        [self.lyricsView setLyricsEffect:effectType];
    }
    
    // 添加触觉反馈
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

- (void)lyricsVisibilityDidChange:(BOOL)isVisible {
    NSLog(@"👁️ 歌词可见性已切换: %@", isVisible ? @"显示" : @"隐藏");
    
    // 使用动画切换歌词容器的可见性
    [UIView animateWithDuration:0.3 animations:^{
        self.lyricsContainer.alpha = isVisible ? 1.0 : 0.0;
    }];
    
    // 添加触觉反馈
    UIImpactFeedbackGenerator *feedback = [[UIImpactFeedbackGenerator alloc] initWithStyle:UIImpactFeedbackStyleLight];
    [feedback impactOccurred];
}

#pragma mark - UIDocumentPickerDelegate

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSLog(@"📥 用户选择了 %ld 个文件", (long)urls.count);
    
    if (urls.count == 0) {
        return;
    }
    
    // 📝 检查是否是 LRC 歌词文件导入
    NSURL *firstURL = urls.firstObject;
    NSString *fileExtension = [firstURL.pathExtension lowercaseString];
    
    if ([fileExtension isEqualToString:@"lrc"]) {
        // 是歌词文件，走歌词导入流程
        if (urls.count == 1) {
            // 单个文件 - 关联到当前歌曲
            [self handleSingleLRCImport:firstURL];
        } else {
            // 多个文件 - 批量导入
            [self handleBatchLRCImport:urls];
        }
        return;
    }
    
    // 显示导入进度提示
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"正在导入"
                                                                            message:@"正在复制文件到音乐库..."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    // 在后台线程执行文件复制
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        NSFileManager *fileManager = [NSFileManager defaultManager];
        
        // 获取目标目录（使用与云下载相同的目录）
        NSString *targetDirectory = [MusicLibraryManager cloudDownloadDirectory];
        
        // 确保目标目录存在
        if (![fileManager fileExistsAtPath:targetDirectory]) {
            NSError *createError = nil;
            [fileManager createDirectoryAtPath:targetDirectory 
                   withIntermediateDirectories:YES 
                                    attributes:nil 
                                         error:&createError];
            if (createError) {
                NSLog(@"❌ 创建目标目录失败: %@", createError.localizedDescription);
            }
        }
        
        NSInteger successCount = 0;
        NSInteger failureCount = 0;
        NSMutableArray *importedFiles = [NSMutableArray array];
        
        for (NSURL *sourceURL in urls) {
            // 开始访问安全范围资源
            BOOL didStartAccessing = [sourceURL startAccessingSecurityScopedResource];
            
            @try {
                NSString *fileName = sourceURL.lastPathComponent;
                NSString *targetPath = [targetDirectory stringByAppendingPathComponent:fileName];
                
                // 如果文件已存在，添加时间戳避免覆盖
                if ([fileManager fileExistsAtPath:targetPath]) {
                    NSString *baseName = [fileName stringByDeletingPathExtension];
                    NSString *extension = [fileName pathExtension];
                    NSTimeInterval timestamp = [[NSDate date] timeIntervalSince1970];
                    fileName = [NSString stringWithFormat:@"%@_%ld.%@", baseName, (long)timestamp, extension];
                    targetPath = [targetDirectory stringByAppendingPathComponent:fileName];
                }
                
                // 复制文件
                NSError *copyError = nil;
                BOOL success = [fileManager copyItemAtURL:sourceURL toURL:[NSURL fileURLWithPath:targetPath] error:&copyError];
                
                if (success) {
                    successCount++;
                    [importedFiles addObject:fileName];
                    NSLog(@"✅ 成功导入: %@", fileName);
                } else {
                    failureCount++;
                    NSLog(@"❌ 导入失败: %@ - %@", fileName, copyError.localizedDescription);
                }
            }
            @finally {
                // 停止访问安全范围资源
                if (didStartAccessing) {
                    [sourceURL stopAccessingSecurityScopedResource];
                }
            }
        }
        
        // 回到主线程更新UI
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (successCount > 0) {
                    // 导入成功，在后台线程重新加载音乐库（避免主线程阻塞）
                    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
                        [self.musicLibrary reloadMusicLibrary];
                        
                        // 回到主线程刷新UI
                        dispatch_async(dispatch_get_main_queue(), ^{
                            [self refreshMusicList];
                            
                            // 显示成功提示
                            NSString *message;
                            if (failureCount > 0) {
                                message = [NSString stringWithFormat:@"成功导入 %ld 首\n失败 %ld 首", (long)successCount, (long)failureCount];
                            } else {
                                message = [NSString stringWithFormat:@"成功导入 %ld 首音乐文件", (long)successCount];
                            }
                            
                            UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 导入完成"
                                                                                                  message:message
                                                                                           preferredStyle:UIAlertControllerStyleAlert];
                            [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                            [self presentViewController:successAlert animated:YES completion:nil];
                            
                            NSLog(@"✅ 导入完成: 成功 %ld 首, 失败 %ld 首", (long)successCount, (long)failureCount);
                        });
                    });
                } else {
                    // 全部失败
                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"❌ 导入失败"
                                                                                         message:@"所有文件导入失败，请检查文件格式"
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:errorAlert animated:YES completion:nil];
                    
                    NSLog(@"❌ 导入失败: 所有文件导入失败");
                }
            }];
        });
    });
}

- (void)documentPickerWasCancelled:(UIDocumentPickerViewController *)controller {
    NSLog(@"📥 用户取消了文件选择");
}

#pragma mark - 📝 歌词导入处理

- (void)handleSingleLRCImport:(NSURL *)lrcURL {
    // 检查是否有当前选中的歌曲
    if (index < 0 || index >= self.displayedMusicItems.count) {
        // 没有选中歌曲，按文件名自动匹配
        [self handleBatchLRCImport:@[lrcURL]];
        return;
    }
    
    MusicItem *currentMusicItem = self.displayedMusicItems[index];
    NSString *audioPath = [currentMusicItem playableFilePath];
    
    NSLog(@"📝 导入歌词关联到: %@", currentMusicItem.fileName);
    
    // 显示导入进度
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"正在导入歌词"
                                                                            message:@"请稍候..."
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    // 使用 LyricsManager 导入
    [[LyricsManager sharedManager] importLRCFile:lrcURL
                                    forAudioFile:audioPath
                                      completion:^(LRCParser *parser, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                if (parser) {
                    // 导入成功
                    NSString *message = [NSString stringWithFormat:@"已为「%@」导入歌词\n共 %lu 行歌词",
                                       currentMusicItem.fileName,
                                       (unsigned long)parser.lyrics.count];
                    
                    UIAlertController *successAlert = [UIAlertController alertControllerWithTitle:@"✅ 歌词导入成功"
                                                                                          message:message
                                                                                   preferredStyle:UIAlertControllerStyleAlert];
                    [successAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:successAlert animated:YES completion:nil];
                    
                    // 如果当前正在播放这首歌，立即更新歌词显示
                    if (self.player.isPlaying) {
                        self.lyricsView.parser = parser;
                        self.lyricsContainer.hidden = NO;
                    }
                    
                    NSLog(@"✅ 歌词导入成功: %@ (%lu 行)", currentMusicItem.fileName, (unsigned long)parser.lyrics.count);
                } else {
                    // 导入失败
                    UIAlertController *errorAlert = [UIAlertController alertControllerWithTitle:@"❌ 歌词导入失败"
                                                                                         message:error.localizedDescription ?: @"无法解析歌词文件"
                                                                                  preferredStyle:UIAlertControllerStyleAlert];
                    [errorAlert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
                    [self presentViewController:errorAlert animated:YES completion:nil];
                    
                    NSLog(@"❌ 歌词导入失败: %@", error.localizedDescription);
                }
            }];
        });
    }];
}

- (void)handleBatchLRCImport:(NSArray<NSURL *> *)lrcURLs {
    NSLog(@"📁 批量导入 %ld 个歌词文件", (long)lrcURLs.count);
    
    // 显示导入进度
    UIAlertController *progressAlert = [UIAlertController alertControllerWithTitle:@"正在批量导入歌词"
                                                                            message:[NSString stringWithFormat:@"共 %ld 个文件...", (long)lrcURLs.count]
                                                                     preferredStyle:UIAlertControllerStyleAlert];
    [self presentViewController:progressAlert animated:YES completion:nil];
    
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        __block NSInteger successCount = 0;
        __block NSInteger failureCount = 0;
        dispatch_group_t group = dispatch_group_create();
        
        for (NSURL *lrcURL in lrcURLs) {
            dispatch_group_enter(group);
            
            [[LyricsManager sharedManager] importLRCFile:lrcURL
                                              completion:^(LRCParser *parser, NSError *error) {
                if (parser) {
                    successCount++;
                } else {
                    failureCount++;
                }
                dispatch_group_leave(group);
            }];
        }
        
        // 等待所有导入完成
        dispatch_group_wait(group, DISPATCH_TIME_FOREVER);
        
        // 回到主线程显示结果
        dispatch_async(dispatch_get_main_queue(), ^{
            [progressAlert dismissViewControllerAnimated:YES completion:^{
                NSString *message;
                NSString *title;
                
                if (successCount > 0 && failureCount == 0) {
                    title = @"✅ 批量导入完成";
                    message = [NSString stringWithFormat:@"成功导入 %ld 个歌词文件", (long)successCount];
                } else if (successCount > 0) {
                    title = @"⚠️ 部分导入成功";
                    message = [NSString stringWithFormat:@"成功: %ld 个\n失败: %ld 个", (long)successCount, (long)failureCount];
                } else {
                    title = @"❌ 导入失败";
                    message = @"所有歌词文件导入失败";
                }
                
                UIAlertController *resultAlert = [UIAlertController alertControllerWithTitle:title
                                                                                      message:message
                                                                               preferredStyle:UIAlertControllerStyleAlert];
                [resultAlert addAction:[UIAlertAction actionWithTitle:@"好的" style:UIAlertActionStyleDefault handler:nil]];
                [self presentViewController:resultAlert animated:YES completion:nil];
                
                NSLog(@"📁 批量歌词导入完成: 成功 %ld, 失败 %ld", (long)successCount, (long)failureCount);
            }];
        });
    });
}

#pragma mark - 🎵 系统媒体控制（控制中心、锁屏等）

/// 配置远程控制命令中心（iOS 16+ 优化版）
- (void)setupRemoteCommandCenter {
    NSLog(@"🎵 开始配置系统媒体控制（iOS 16+ 优化）...");
    
    // ========== 步骤 1：音频会话由 AudioSpectrumPlayer 管理 ==========
    // 注意：音频会话的配置已由 AudioSpectrumPlayer 管理，包括混音选项
    // 这里不再重复配置，避免覆盖用户的混音设置
    AVAudioSession *audioSession = [AVAudioSession sharedInstance];
    NSLog(@"✅ Step 1: 音频会话由 AudioSpectrumPlayer 管理");
    NSLog(@"   当前类别: %@", audioSession.category);
    NSLog(@"   混音模式: %@", self.player.allowMixWithOthers ? @"开启" : @"关闭");
    
    // ========== 步骤 2：启用远程控制事件接收 ==========
    [[UIApplication sharedApplication] beginReceivingRemoteControlEvents];
    [self becomeFirstResponder];
    NSLog(@"✅ Step 2: 已启用远程控制事件接收");
    
    // ========== 步骤 3：注册远程命令（在激活之后）==========
    MPRemoteCommandCenter *commandCenter = [MPRemoteCommandCenter sharedCommandCenter];
    
    // 3.1 先移除所有旧的 target（避免重复注册）
    [commandCenter.playCommand removeTarget:nil];
    [commandCenter.pauseCommand removeTarget:nil];
    [commandCenter.nextTrackCommand removeTarget:nil];
    [commandCenter.previousTrackCommand removeTarget:nil];
    [commandCenter.togglePlayPauseCommand removeTarget:nil]; // iOS 16+: 禁用这个
    
    // 3.2 禁用 togglePlayPauseCommand（iOS 16+ 建议使用单独的 play/pause）
    commandCenter.togglePlayPauseCommand.enabled = NO;
    
    // 3.3 注册播放命令
    [commandCenter.playCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 播放");
        dispatch_async(dispatch_get_main_queue(), ^{
            // 🔧 检查是否禁止自动恢复播放（用户在其他页面时）
            if (self.shouldPreventAutoResume) {
                NSLog(@"   ⚠️ 已禁止播放（用户在其他页面）");
                return;
            }
            if (!self.player.isPlaying) {
                [self playCurrentTrack];
            }
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // 3.4 注册暂停命令
    [commandCenter.pauseCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 暂停");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self stopPlayback];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // 3.5 注册下一首命令
    [commandCenter.nextTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 下一首");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playNext];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // 3.6 注册上一首命令
    [commandCenter.previousTrackCommand addTargetWithHandler:^MPRemoteCommandHandlerStatus(MPRemoteCommandEvent * _Nonnull event) {
        NSLog(@"🎵 系统控制: 上一首");
        dispatch_async(dispatch_get_main_queue(), ^{
            [self playPrevious];
        });
        return MPRemoteCommandHandlerStatusSuccess;
    }];
    
    // 3.7 显式启用所需命令
    commandCenter.playCommand.enabled = YES;
    commandCenter.pauseCommand.enabled = YES;
    commandCenter.nextTrackCommand.enabled = YES;
    commandCenter.previousTrackCommand.enabled = YES;
    
    NSLog(@"✅ Step 3: 远程命令已注册并启用");
    
    // ========== 验证配置 ==========
    NSLog(@"📋 最终配置状态:");
    NSLog(@"   • 音频会话类别: %@", audioSession.category);
    NSLog(@"   • 音频会话模式: %@", audioSession.mode);
    NSLog(@"   • 混音模式: %@", self.player.allowMixWithOthers ? @"✅ 允许混音" : @"❌ 独占播放");
    NSLog(@"   • 播放命令: %@", commandCenter.playCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 暂停命令: %@", commandCenter.pauseCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 下一首命令: %@", commandCenter.nextTrackCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 上一首命令: %@", commandCenter.previousTrackCommand.isEnabled ? @"✅" : @"❌");
    NSLog(@"   • 切换播放命令: %@ (应该禁用)", commandCenter.togglePlayPauseCommand.isEnabled ? @"❌ 启用了" : @"✅ 已禁用");
    
    NSLog(@"✅ 系统媒体控制配置完成（iOS 16+ 优化）");
}

// 支持成为第一响应者以接收远程控制事件
- (BOOL)canBecomeFirstResponder {
    return YES;
}

/// 🔍 诊断：测试强制设置播放信息（临时测试方法）
- (void)forceUpdateNowPlayingInfo {
    NSLog(@"🔍 强制设置播放信息测试...");
    
    // 强制设置最简单的播放信息
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[MPMediaItemPropertyTitle] = @"测试歌曲";
    info[MPMediaItemPropertyArtist] = @"测试艺术家";
    info[MPMediaItemPropertyPlaybackDuration] = @(180.0); // 3分钟
    info[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(0.0);
    info[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
    
    // 🎵 iOS 16+ 关键：添加封面图
    UIImage *testArtwork = [self createDefaultArtworkImage];
    if (testArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:testArtwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return testArtwork;
        }];
        info[MPMediaItemPropertyArtwork] = artwork;
    }
    
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = info;
    
    NSLog(@"✅ 强制设置完成");
    NSLog(@"   当前播放信息: %@", [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo);
    
    // 验证音频会话
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   音频会话类别: %@", session.category);
    NSLog(@"   音频会话选项: %lu", (unsigned long)session.categoryOptions);
    NSLog(@"   其他音频播放中: %@", @([session isOtherAudioPlaying]));
    NSLog(@"   音频会话激活: ✅ (已设置)");
    
    // 验证远程控制
    MPRemoteCommandCenter *cc = [MPRemoteCommandCenter sharedCommandCenter];
    NSLog(@"   播放命令启用: %@", @(cc.playCommand.isEnabled));
    NSLog(@"   暂停命令启用: %@", @(cc.pauseCommand.isEnabled));
}

/// 立即更新基本播放信息（在播放开始前调用，确保控制中心立即显示）
- (void)updateNowPlayingInfoImmediate {
    if (index >= self.displayedMusicItems.count) {
        NSLog(@"⚠️ 无法更新播放信息: 索引超出范围");
        return;
    }
    
    MusicItem *musicItem = self.displayedMusicItems[index];
    
    // 🎵 关键：创建新字典，不要修改现有字典
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    
    // 歌曲标题（必须）
    NSString *title = @"正在播放";
    if (musicItem.displayName) {
        title = musicItem.displayName;
    } else if (musicItem.fileName) {
        title = [musicItem.fileName stringByDeletingPathExtension];
    }
    nowPlayingInfo[MPMediaItemPropertyTitle] = title;
    
    // 艺术家（必须）
    nowPlayingInfo[MPMediaItemPropertyArtist] = @"AudioSampleBuffer";
    
    // 专辑
    nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = @"本地音乐";
    
    // 🎵 iOS 16+ 关键：必须设置封面图片！否则控制中心不显示
    UIImage *defaultArtwork = [self createDefaultArtworkImage];
    if (defaultArtwork) {
        MPMediaItemArtwork *artwork = [[MPMediaItemArtwork alloc] initWithBoundsSize:defaultArtwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return defaultArtwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artwork;
        NSLog(@"   - 封面图片: ✅ 已设置 (%.0fx%.0f)", defaultArtwork.size.width, defaultArtwork.size.height);
    }
    
    // 🎵 关键：播放速率必须大于0才会显示播放状态
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(1.0);
    
    // 当前时间（初始为0）
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(0.0);
    
    // 🎵 关键：立即更新到系统
    MPNowPlayingInfoCenter *center = [MPNowPlayingInfoCenter defaultCenter];
    center.nowPlayingInfo = nowPlayingInfo;
    
    NSLog(@"✅ 立即设置播放信息成功:");
    NSLog(@"   - 标题: %@", title);
    NSLog(@"   - 艺术家: %@", nowPlayingInfo[MPMediaItemPropertyArtist]);
    NSLog(@"   - 播放速率: %@", nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate]);
    
    // 验证音频会话状态
    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   - 音频会话类别: %@", session.category);
    NSLog(@"   - 音频会话选项: %lu (0=独占, 1=混音)", (unsigned long)session.categoryOptions);
    NSLog(@"   - 其他音频播放中: %@", @(session.isOtherAudioPlaying));
    
    // 🎵 强制触发系统更新
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
        // 再次设置确保系统接收
        center.nowPlayingInfo = nowPlayingInfo;
        NSLog(@"🔄 二次确认播放信息已设置");
    });
}

/// 创建默认封面图片（iOS 16+ 必须）
- (UIImage *)createDefaultArtworkImage {
    // 🆕 优先尝试获取当前播放音乐的真实封面
    if (index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        
        // 获取音乐文件URL
        NSURL *fileUrl = nil;
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            fileUrl = [NSURL fileURLWithPath:musicItem.filePath];
        } else {
            fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        }
        
        if (fileUrl) {
            UIImage *musicCover = [self musicImageWithMusicURL:fileUrl];
            if (musicCover) {
                NSLog(@"✅ 使用音乐真实封面 (%.0fx%.0f): %@", musicCover.size.width, musicCover.size.height, musicItem.fileName);
                return musicCover;
            }
        }
    }
    
    // 🎵 如果没有真实封面，使用 App Icon 作为默认封面
    UIImage *appIcon = [UIImage imageNamed:@"none_image"];
    if (appIcon) {
        NSLog(@"✅ 使用 App Icon 作为默认封面 (%.0fx%.0f)", appIcon.size.width, appIcon.size.height);
        return appIcon;
    }
    
    // 🎵 如果无法获取 App Icon，尝试使用项目中的 none_image 图片
    UIImage *noneImage = [UIImage imageNamed:@"none_image"];
    if (noneImage) {
        NSLog(@"✅ 使用默认封面图片: none_image (%.0fx%.0f)", noneImage.size.width, noneImage.size.height);
        return noneImage;
    }
    
    NSLog(@"⚠️ none_image 图片未找到，使用程序生成的默认封面");
    
    // 如果 none_image 不存在，创建一个简单的渐变色封面
    CGSize size = CGSizeMake(512, 512);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0.0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // 渐变背景
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    NSArray *colors = @[
        (id)[UIColor colorWithRed:0.2 green:0.4 blue:0.8 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:1.0].CGColor
    ];
    CGGradientRef gradient = CGGradientCreateWithColors(colorSpace, (__bridge CFArrayRef)colors, NULL);
    CGContextDrawLinearGradient(context, gradient, CGPointMake(0, 0), CGPointMake(size.width, size.height), 0);
    
    // 添加音乐图标
    UIBezierPath *musicNote = [UIBezierPath bezierPath];
    CGFloat centerX = size.width / 2;
    CGFloat centerY = size.height / 2;
    [musicNote moveToPoint:CGPointMake(centerX - 30, centerY + 40)];
    [musicNote addLineToPoint:CGPointMake(centerX - 30, centerY - 40)];
    [musicNote addLineToPoint:CGPointMake(centerX + 30, centerY - 50)];
    [musicNote addLineToPoint:CGPointMake(centerX + 30, centerY + 30)];
    [[UIColor whiteColor] setStroke];
    musicNote.lineWidth = 8;
    [musicNote stroke];
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
    
    return image;
}

/// 更新正在播放的信息（显示在控制中心和锁屏界面）
- (void)updateNowPlayingInfo {
    if (index >= self.displayedMusicItems.count) {
        return;
    }
    
    MusicItem *musicItem = self.displayedMusicItems[index];
    
    NSMutableDictionary *nowPlayingInfo = [NSMutableDictionary dictionary];
    
    // 歌曲标题
    if (musicItem.displayName) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = musicItem.displayName;
    } else if (musicItem.fileName) {
        nowPlayingInfo[MPMediaItemPropertyTitle] = [musicItem.fileName stringByDeletingPathExtension];
    }
    
    // 艺术家（从歌词解析器获取，如果有的话）
    if (self.player.lyricsParser && self.player.lyricsParser.artist) {
        nowPlayingInfo[MPMediaItemPropertyArtist] = self.player.lyricsParser.artist;
    } else {
        nowPlayingInfo[MPMediaItemPropertyArtist] = @"未知艺术家";
    }
    
    // 专辑（从歌词解析器获取，如果有的话）
    if (self.player.lyricsParser && self.player.lyricsParser.album) {
        nowPlayingInfo[MPMediaItemPropertyAlbumTitle] = self.player.lyricsParser.album;
    }
    
    // 🎵 iOS 16+ 关键：封面图片（必须）
    UIImage *artwork = [self createDefaultArtworkImage];
    if (artwork) {
        MPMediaItemArtwork *artworkItem = [[MPMediaItemArtwork alloc] initWithBoundsSize:artwork.size requestHandler:^UIImage * _Nonnull(CGSize size) {
            return artwork;
        }];
        nowPlayingInfo[MPMediaItemPropertyArtwork] = artworkItem;
    }
    
    // 播放时长
    nowPlayingInfo[MPMediaItemPropertyPlaybackDuration] = @(self.player.duration);
    
    // 当前播放时间
    nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
    
    // 播放速率（1.0 = 正常播放）
    nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(self.player.isPlaying ? 1.0 : 0.0);
    
    // 更新到系统
    [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
    
    NSLog(@"🎵 已更新系统播放信息: %@", nowPlayingInfo[MPMediaItemPropertyTitle]);
}

#pragma mark - 🎮 外部播放控制接口

/// 停止当前播放
- (void)stopPlayback {
    NSLog(@"⏹️ 外部控制: 停止播放");
    [self.player stop];
    
    // 🎵 如果正在显示黑胶唱片，停止旋转动画
    if (self.isShowingVinylRecord) {
        [self.vinylRecordView stopSpinning];
    }
    
    // 🎵 iOS 16+: 更新播放状态为暂停（不清除信息）
    NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
    if (nowPlayingInfo) {
        // 关键：将播放速率设置为 0.0 表示暂停状态
        nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(0.0);
        // 保持当前播放时间
        nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
        [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
        NSLog(@"✅ 播放状态已更新为暂停 (playbackRate = 0.0)");
    }
}

/// 播放下一首
- (void)playNext {
    NSLog(@"⏭️ 外部控制: 播放下一首");
    
    if (self.displayedMusicItems.count == 0) {
        NSLog(@"⚠️ 播放列表为空");
        return;
    }
    
    index++;
    if (index >= self.displayedMusicItems.count) {
        index = 0; // 循环播放
    }
    
    // 记录播放
    MusicItem *musicItem = self.displayedMusicItems[index];
    [self.musicLibrary recordPlayForMusic:musicItem];
    
    [self updateAudioSelection];
    
    // 播放音频
    [self playCurrentTrack];
}

/// 播放上一首
- (void)playPrevious {
    NSLog(@"⏮️ 外部控制: 播放上一首");
    
    if (self.displayedMusicItems.count == 0) {
        NSLog(@"⚠️ 播放列表为空");
        return;
    }
    
    index--;
    if (index < 0) {
        index = self.displayedMusicItems.count - 1; // 循环到最后一首
    }
    
    // 记录播放
    MusicItem *musicItem = self.displayedMusicItems[index];
    [self.musicLibrary recordPlayForMusic:musicItem];
    
    [self updateAudioSelection];
    
    // 播放音频
    [self playCurrentTrack];
}

/// 播放当前曲目（复用播放逻辑）
- (void)playCurrentTrack {
    NSLog(@"🎵 [playCurrentTrack] 开始...");
    NSLog(@"   当前索引: %ld", (long)index);
    NSLog(@"   列表总数: %lu", (unsigned long)self.displayedMusicItems.count);
    
    if (index >= self.displayedMusicItems.count) {
        NSLog(@"⚠️ 索引超出范围: %ld / %lu", (long)index, (unsigned long)self.displayedMusicItems.count);
        return;
    }
    
    MusicItem *musicItem = self.displayedMusicItems[index];
    NSLog(@"   歌曲: %@", musicItem.fileName);
    NSLog(@"   路径: %@", musicItem.filePath);
    
    NSString *playPath = nil;
    
    // 优先使用已解密文件
    if (musicItem.decryptedPath && [[NSFileManager defaultManager] fileExistsAtPath:musicItem.decryptedPath]) {
        playPath = musicItem.decryptedPath;
        NSLog(@"🎵 播放已解密文件: %@", playPath);
    }
    // 检查是否是NCM文件，需要先解密
    else if ([AudioFileFormats needsDecryption:musicItem.fileName]) {
        NSLog(@"🔓 解密NCM文件: %@", musicItem.fileName);
        
        // 优先传递完整路径
        NSString *fileToDecrypt = (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) ? musicItem.filePath : musicItem.fileName;
        playPath = [AudioFileFormats prepareAudioFileForPlayback:fileToDecrypt];
        
        // 如果解密成功，更新状态
        if (playPath && [playPath hasPrefix:@"/"] && [[NSFileManager defaultManager] fileExistsAtPath:playPath]) {
            [self.musicLibrary updateNCMDecryptionStatus:musicItem decryptedPath:playPath];
            NSLog(@"✅ 解密成功: %@", playPath);
        }
    } else {
        // 🔧 优先使用完整路径（云下载的文件）
        if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
            playPath = musicItem.filePath;
            NSLog(@"🎵 播放云下载文件（完整路径）: %@", playPath);
        } else {
            playPath = [AudioFileFormats prepareAudioFileForPlayback:musicItem.fileName];
            NSLog(@"🎵 播放Bundle文件: %@", playPath);
        }
    }
    
    // 🔧 最终验证 playPath
    if (!playPath || playPath.length == 0) {
        NSLog(@"❌ [playCurrentTrack] playPath 为空！");
        return;
    }
    
    NSLog(@"🎵 [playCurrentTrack] 最终播放路径: %@", playPath);
    
    // 🎵 先设置基本的播放信息（立即设置，让控制中心显示）
    [self updateNowPlayingInfoImmediate];
    
    [self.player playWithFileName:playPath];
    
    // 🎵 如果正在显示黑胶唱片，开始旋转动画
    if (self.isShowingVinylRecord) {
        [self.vinylRecordView startSpinning];
    }
    
    // 🎵 注意：完整的播放信息将在 playerDidStartPlaying 回调中更新
}

#pragma mark - 🎧 音频会话中断和路由变化处理

/// 处理音频会话中断（来电、闹钟、Siri等）
- (void)handleAudioSessionInterruption:(NSNotification *)notification {
    AVAudioSessionInterruptionType interruptionType = [notification.userInfo[AVAudioSessionInterruptionTypeKey] unsignedIntegerValue];
    
    if (interruptionType == AVAudioSessionInterruptionTypeBegan) {
        // 中断开始（来电、闹钟等）
        NSLog(@"🎧 音频会话中断开始");
        
        // 🔧 记录中断前是否正在播放（用于决定是否恢复）
        self.wasPlayingBeforeInterruption = self.player.isPlaying;
        NSLog(@"   中断前播放状态: %@", self.wasPlayingBeforeInterruption ? @"播放中" : @"已暂停");
        
        // 系统会自动暂停音频，我们只需要更新UI状态
        if (self.player.isPlaying) {
            // 更新播放/暂停按钮状态
            dispatch_async(dispatch_get_main_queue(), ^{
                [self.playPauseButton setTitle:@"▶️" forState:UIControlStateNormal];
                self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.85];
            });
            
            // 更新系统媒体信息为暂停状态
            NSMutableDictionary *nowPlayingInfo = [[MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo mutableCopy];
            if (nowPlayingInfo) {
                nowPlayingInfo[MPNowPlayingInfoPropertyPlaybackRate] = @(0.0);
                nowPlayingInfo[MPNowPlayingInfoPropertyElapsedPlaybackTime] = @(self.player.currentTime);
                [MPNowPlayingInfoCenter defaultCenter].nowPlayingInfo = nowPlayingInfo;
            }
        }
        
    } else if (interruptionType == AVAudioSessionInterruptionTypeEnded) {
        // 中断结束
        NSLog(@"🎧 音频会话中断结束");
        
        // 🔧 检查是否禁止自动恢复播放（用户进入其他页面时设置）
        if (self.shouldPreventAutoResume) {
            NSLog(@"   ⚠️ 已禁止自动恢复播放（用户可能在其他页面）");
            return;
        }
        
        // 🔧 检查中断前是否正在播放
        if (!self.wasPlayingBeforeInterruption) {
            NSLog(@"   ⚠️ 中断前未播放，不恢复播放");
            return;
        }
        
        // 检查是否应该恢复播放
        AVAudioSessionInterruptionOptions options = [notification.userInfo[AVAudioSessionInterruptionOptionKey] unsignedIntegerValue];
        BOOL shouldResume = (options & AVAudioSessionInterruptionOptionShouldResume) != 0;
        
        NSLog(@"   是否应该恢复播放: %@", shouldResume ? @"是" : @"否");
        
        if (shouldResume) {
            // 重新激活音频会话
            NSError *error = nil;
            [[AVAudioSession sharedInstance] setActive:YES error:&error];
            if (error) {
                NSLog(@"❌ 重新激活音频会话失败: %@", error);
            } else {
                NSLog(@"✅ 音频会话已重新激活");
                
                // 恢复播放
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    [self playCurrentTrack];
                    NSLog(@"✅ 已恢复播放");
                    // 清除标志
                    self.wasPlayingBeforeInterruption = NO;
                });
            }
        }
    }
}

/// 处理音频路由变化（耳机插拔、蓝牙连接/断开）
- (void)handleAudioSessionRouteChange:(NSNotification *)notification {
    AVAudioSessionRouteChangeReason reason = [notification.userInfo[AVAudioSessionRouteChangeReasonKey] unsignedIntegerValue];
    
    NSLog(@"🎧 音频路由变化，原因: %lu", (unsigned long)reason);
    
    switch (reason) {
        case AVAudioSessionRouteChangeReasonNewDeviceAvailable: {
            // 新设备连接（耳机插入、蓝牙连接）
            NSLog(@"🎧 新音频设备连接");
            
            AVAudioSession *session = [AVAudioSession sharedInstance];
            AVAudioSessionRouteDescription *currentRoute = session.currentRoute;
            
            for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
                NSLog(@"   输出设备: %@ (%@)", output.portName, output.portType);
                
                // 检测是否是耳机或蓝牙设备
                if ([output.portType isEqualToString:AVAudioSessionPortHeadphones] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
                    
                    NSLog(@"✅ 检测到耳机/蓝牙设备连接");
                    
                    // 耳机连接时，如果之前在播放，继续播放
                    // 注意：这里不自动播放，因为用户可能只是插入耳机准备听
                    // 如果需要自动播放，可以取消下面的注释
                    /*
                    if (!self.player.isPlaying && index < self.displayedMusicItems.count) {
                        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                            [self playCurrentTrack];
                            NSLog(@"✅ 耳机连接，自动恢复播放");
                        });
                    }
                    */
                }
            }
            break;
        }
            
        case AVAudioSessionRouteChangeReasonOldDeviceUnavailable: {
            // 设备断开（耳机拔出、蓝牙断开）
            NSLog(@"🎧 音频设备断开");
            
            AVAudioSessionRouteDescription *previousRoute = notification.userInfo[AVAudioSessionRouteChangePreviousRouteKey];
            
            for (AVAudioSessionPortDescription *output in previousRoute.outputs) {
                NSLog(@"   断开的设备: %@ (%@)", output.portName, output.portType);
                
                // 检测是否是耳机或蓝牙设备
                if ([output.portType isEqualToString:AVAudioSessionPortHeadphones] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothA2DP] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothLE] ||
                    [output.portType isEqualToString:AVAudioSessionPortBluetoothHFP]) {
                    
                    NSLog(@"⚠️ 耳机/蓝牙设备已断开，暂停播放");
                    
                    // 耳机拔出时自动暂停播放
                    if (self.player.isPlaying) {
                        [self stopPlayback];
                        NSLog(@"✅ 已自动暂停播放");
                    }
                }
            }
            break;
        }
            
        case AVAudioSessionRouteChangeReasonCategoryChange: {
            // 音频类别变化
            NSLog(@"🎧 音频类别变化");
            
            AVAudioSession *session = [AVAudioSession sharedInstance];
            NSLog(@"   新类别: %@", session.category);
            NSLog(@"   新模式: %@", session.mode);
            
            // 如果类别变化导致播放停止，需要重新配置
            if (self.player.isPlaying) {
                dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.1 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
                    // 重新配置音频会话
                    [self.player configureAudioSession];
                    NSLog(@"✅ 已重新配置音频会话");
                });
            }
            break;
        }
            
        case AVAudioSessionRouteChangeReasonOverride:
            NSLog(@"🎧 音频路由被覆盖");
            break;
            
        case AVAudioSessionRouteChangeReasonWakeFromSleep:
            NSLog(@"🎧 从睡眠中唤醒");
            break;
            
        case AVAudioSessionRouteChangeReasonNoSuitableRouteForCategory:
            NSLog(@"⚠️ 当前类别没有合适的音频路由");
            break;
            
        case AVAudioSessionRouteChangeReasonRouteConfigurationChange:
            NSLog(@"🎧 音频路由配置变化");
            break;
            
        default:
            NSLog(@"🎧 其他路由变化原因: %lu", (unsigned long)reason);
            break;
    }
    
    // 打印当前音频路由信息
    AVAudioSession *session = [AVAudioSession sharedInstance];
    AVAudioSessionRouteDescription *currentRoute = session.currentRoute;
    NSLog(@"📋 当前音频路由:");
    for (AVAudioSessionPortDescription *output in currentRoute.outputs) {
        NSLog(@"   输出: %@ (%@)", output.portName, output.portType);
    }
    for (AVAudioSessionPortDescription *input in currentRoute.inputs) {
        NSLog(@"   输入: %@ (%@)", input.portName, input.portType);
    }
}

@end
