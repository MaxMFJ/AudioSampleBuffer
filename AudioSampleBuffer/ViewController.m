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
#import "AudioFileFormats.h"  // 🆕 音频格式工具
#import "KaraokeViewController.h"
#import "MusicLibraryManager.h"  // 🆕 音乐库管理器
#import "ViewController+CloudDownload.h"  // 🆕 云端下载功能
#import <AVFoundation/AVFoundation.h>

@interface ViewController ()<CAAnimationDelegate,UITableViewDelegate, UITableViewDataSource, AudioSpectrumPlayerDelegate, VisualEffectManagerDelegate, GalaxyControlDelegate, CyberpunkControlDelegate, PerformanceControlDelegate, LyricsEffectControlDelegate, UISearchBarDelegate>
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
@property (nonatomic, assign) MusicSortType currentSortType;  // 当前排序方式
@property (nonatomic, assign) BOOL sortAscending;  // 排序方向


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
@end

@implementation ViewController
- (void)hadEnterBackGround{
    NSLog(@"进入后台");
    enterBackground =  YES;
    [self.animationCoordinator applicationDidEnterBackground];
    
    // 🔋 关键修复：进入后台时立即暂停Metal渲染，避免持续发热和耗电
    [self.visualEffectManager pauseRendering];
}

- (void)hadEnterForeGround{
    NSLog(@"回到app");
    enterBackground = NO;
    [self.animationCoordinator applicationDidBecomeActive];
    [self.visualEffectManager resumeRendering];
}

- (void)karaokeModeDidStart {
    NSLog(@"🎤 收到卡拉OK模式开始通知，停止主界面音频播放");
    // 停止主界面的音频播放
    [self.player stop];
    // 暂停视觉效果渲染以节省资源
    [self.visualEffectManager pauseRendering];
}

- (void)karaokeModeDidEnd {
    NSLog(@"🎤 收到卡拉OK模式结束通知，恢复主界面音频播放");
    // 恢复视觉效果渲染
    [self.visualEffectManager resumeRendering];
    // 可以选择恢复播放当前选中的歌曲
    if (self.displayedMusicItems.count > 0 && index < self.displayedMusicItems.count) {
        // 🆕 自动处理 NCM 文件解密
        MusicItem *musicItem = self.displayedMusicItems[index];
        NSString *fileName = musicItem.fileName;
        NSString *playableFileName = [AudioFileFormats prepareAudioFileForPlayback:fileName];
        [self.player playWithFileName:playableFileName];
    }
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
}

- (void)setupEffectControls {
    // 🔧 修复导航栏遮挡问题：考虑安全区域和导航栏高度
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    
    // 如果有导航栏，从导航栏下方开始布局
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 10; // 额外10px间距
    
    // 创建性能配置按钮（放在左上角第一个位置）
    self.performanceControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.performanceControlButton setTitle:@"⚙️" forState:UIControlStateNormal];
    [self.performanceControlButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.performanceControlButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.performanceControlButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.2 alpha:0.9];
    self.performanceControlButton.layer.cornerRadius = 25;
    self.performanceControlButton.layer.borderWidth = 2.0;
    self.performanceControlButton.layer.borderColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.3 alpha:1.0].CGColor;
    self.performanceControlButton.frame = CGRectMake(20, topOffset, 50, 50);
    
    // 添加阴影效果
    self.performanceControlButton.layer.shadowColor = [UIColor greenColor].CGColor;
    self.performanceControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.performanceControlButton.layer.shadowOpacity = 0.8;
    self.performanceControlButton.layer.shadowRadius = 4;
    
    [self.performanceControlButton addTarget:self 
                                      action:@selector(performanceControlButtonTapped:) 
                            forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.performanceControlButton];
    
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
    self.effectSelectorButton.frame = CGRectMake(80, topOffset, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.effectSelectorButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.effectSelectorButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.effectSelectorButton.layer.shadowOpacity = 0.8;
    self.effectSelectorButton.layer.shadowRadius = 4;
    
    [self.effectSelectorButton addTarget:self 
                                  action:@selector(effectSelectorButtonTapped:) 
                        forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.effectSelectorButton];
    
    // 添加卡拉OK按钮
    [self createKaraokeButton];
    
    // 添加快捷切换按钮
    [self createQuickEffectButtons];
    
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
    self.galaxyControlButton.frame = CGRectMake(170, topOffset, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.galaxyControlButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.galaxyControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.galaxyControlButton.layer.shadowOpacity = 0.8;
    self.galaxyControlButton.layer.shadowRadius = 4;
    
    [self.galaxyControlButton addTarget:self 
                                 action:@selector(galaxyControlButtonTapped:) 
                       forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.galaxyControlButton];
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
    self.cyberpunkControlButton.frame = CGRectMake(260, topOffset, 80, 50);
    
    // 添加阴影效果，增强可见性
    self.cyberpunkControlButton.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.cyberpunkControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.cyberpunkControlButton.layer.shadowOpacity = 0.6;
    self.cyberpunkControlButton.layer.shadowRadius = 4;
    
    [self.cyberpunkControlButton addTarget:self 
                                    action:@selector(cyberpunkControlButtonTapped:) 
                          forControlEvents:UIControlEventTouchUpInside];
    
    [self.view addSubview:self.cyberpunkControlButton];
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
}

- (void)bringControlButtonsToFront {
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
    [super viewWillAppear:YES];
}
- (void)viewDidLoad {
    [super viewDidLoad];
    
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
    
    // 🆕 启用云端下载功能
    [self setupCloudDownloadFeature];
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
    
    // 🆕 使用当前显示的音乐项获取封面
    if (self.displayedMusicItems.count > 0 && index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        imageView.image = [self musicImageWithMusicURL:fileUrl];
    }
    
    imageView.layer.cornerRadius = imageView.frame.size.height/2.0;
    imageView.clipsToBounds = YES;
    imageView.contentMode = UIViewContentModeScaleAspectFill;
    imageView.center = self.view.center;
    [self.view addSubview:imageView];
    
    // 使用动画管理器添加旋转动画
    [self.animationCoordinator addRotationViews:@[imageView] 
                                      rotations:@[@(6.0)] 
                                      durations:@[@(120.0)] 
                                  rotationTypes:@[@(RotationTypeCounterClockwise)]];

    
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
    
    // 设置当前音频的粒子图像
    if (self.audioArray.count > 0) {
        NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
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
    self.spectrumView = [[SpectrumView alloc] initWithFrame:CGRectMake(0, 25, self.view.frame.size.width, self.view.frame.size.height)];
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
            NSString *fileName = musicItem.fileName;
            NSString *playableFileName = [AudioFileFormats prepareAudioFileForPlayback:fileName];
            [weakSelf.player playWithFileName:playableFileName];
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
    
    // 🔧 优先使用完整路径，支持云下载的文件
    NSString *playPath = nil;
    
    NSLog(@"🎵 准备播放: fileName=%@, filePath=%@", musicItem.fileName, musicItem.filePath);
    
    // 检查是否有完整路径（云下载的文件或已解密的 NCM 文件）
    if (musicItem.filePath && [musicItem.filePath hasPrefix:@"/"]) {
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
        NSString *fileName = musicItem.fileName;
        playPath = [AudioFileFormats prepareAudioFileForPlayback:fileName];
        NSLog(@"🎵 从 Bundle 播放: %@", playPath);
    }
    
    [self.player playWithFileName:playPath];
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
        // 获取NCM文件路径
        NSURL *fileURL = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        if (!fileURL) {
            NSString *audioPath = [[NSBundle mainBundle] pathForResource:@"Audio" ofType:nil];
            NSString *fullPath = [audioPath stringByAppendingPathComponent:musicItem.fileName];
            fileURL = [NSURL fileURLWithPath:fullPath];
        }
        
        if (!fileURL) {
            dispatch_async(dispatch_get_main_queue(), ^{
                [loadingAlert dismissViewControllerAnimated:YES completion:^{
                    [self showAlert:@"❌ 错误" message:@"找不到文件"];
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
                    
                    // 显示成功提示
                    [self showAlert:@"✅ 转换成功" message:[NSString stringWithFormat:@"已成功转换: %@\n现在可以播放了！", musicItem.displayName ?: musicItem.fileName]];
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
        
        // 更新封面图像
        NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:musicItem.fileName withExtension:nil];
        UIImage *image = [self musicImageWithMusicURL:fileUrl];
        if (image) {
            imageView.image = image;
            // 更新粒子图像
            [self.animationCoordinator updateParticleImage:image];
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
    
    // 🆕 自动处理 NCM 文件解密
    if (index < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[index];
        NSString *fileName = musicItem.fileName;
        NSString *playableFileName = [AudioFileFormats prepareAudioFileForPlayback:fileName];
        
        [self.player playWithFileName:playableFileName];
    }
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

- (void)playerDidUpdateTime:(NSTimeInterval)currentTime {
    // 更新歌词显示
    [self.lyricsView updateWithTime:currentTime];
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
    
    NSData*data =nil;
    
    // 初始化媒体文件
    
    AVURLAsset*mp3Asset = [AVURLAsset URLAssetWithURL:url options:nil];

    // 读取文件中的数据
    
    for(NSString*format in [mp3Asset availableMetadataFormats]) {
        
        for(AVMetadataItem*metadataItem in[mp3Asset metadataForFormat:format]) {
            //artwork这个key对应的value里面存的就是封面缩略图，其它key可以取出其它摘要信息，例如title - 标题
            
            if([metadataItem.commonKey isEqualToString:@"artwork"]) {
                
                data = [metadataItem.value copyWithZone:nil];
                
                break;
            }
        }
    }
    if(!data) {
        // 如果音乐没有图片，就返回默认图片
        return nil;//[UIImage imageNamed:@"default"];
        
    }
    
    return[UIImage imageWithData:data];
    
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
        NSURL *fileUrl = [[NSBundle mainBundle] URLForResource:self.audioArray[index] withExtension:nil];
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
    
    [self.lyricsEffectPanel showAnimated:YES];
    [self.view bringSubviewToFront:self.lyricsEffectPanel];
    
    NSLog(@"🎭 打开歌词特效面板");
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

@end
