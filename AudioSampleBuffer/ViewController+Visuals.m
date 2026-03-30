#import "ViewController+Private.h"

#import "AgentMetricsCollector.h"
#import "AgentReflectionEngine.h"
#import "AudioFileFormats.h"
#import "EffectDecisionAgent.h"
#import "ViewController+PlaybackProgress.h"

#import <AVFoundation/AVFoundation.h>

@implementation ViewController (Visuals)

#pragma mark - Setup

- (void)setupVisualEffectSystem {
    self.visualEffectManager = [[VisualEffectManager alloc] initWithContainerView:self.view];
    self.visualEffectManager.delegate = self;
    [self.visualEffectManager setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleEffectSettingsButtonTapped:)
                                                 name:@"EffectSettingsButtonTapped"
                                               object:nil];
}

- (void)setupNavigationBar {
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
        self.navigationController.navigationBar.barTintColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
        self.navigationController.navigationBar.titleTextAttributes = @{
            NSForegroundColorAttributeName: [UIColor whiteColor],
            NSFontAttributeName: [UIFont boldSystemFontOfSize:18]
        };
        self.navigationController.navigationBar.translucent = YES;
    }

    self.navigationController.navigationBarHidden = YES;
    NSLog(@"✅ 导航栏已隐藏");
}

- (void)setupEffectControls {
    self.controlButtons = [NSMutableArray array];
    self.isUIHidden = NO;

    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }

    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 10;

    [self createToggleUIButton:topOffset];

    self.performanceControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.performanceControlButton setTitle:@"⚙️" forState:UIControlStateNormal];
    [self.performanceControlButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.performanceControlButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.performanceControlButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.2 alpha:0.9];
    self.performanceControlButton.layer.cornerRadius = 25;
    self.performanceControlButton.layer.borderWidth = 2.0;
    self.performanceControlButton.layer.borderColor = [UIColor colorWithRed:0.5 green:0.9 blue:0.3 alpha:1.0].CGColor;
    self.performanceControlButton.frame = CGRectMake(80, topOffset, 50, 50);
    self.performanceControlButton.layer.shadowColor = [UIColor greenColor].CGColor;
    self.performanceControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.performanceControlButton.layer.shadowOpacity = 0.8;
    self.performanceControlButton.layer.shadowRadius = 4;
    [self.performanceControlButton addTarget:self action:@selector(performanceControlButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.performanceControlButton];
    [self.controlButtons addObject:self.performanceControlButton];

    [self setupFPSMonitor];

    self.effectSelectorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.effectSelectorButton setTitle:@"🎨 特效" forState:UIControlStateNormal];
    [self.effectSelectorButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.effectSelectorButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.effectSelectorButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:0.9];
    self.effectSelectorButton.layer.cornerRadius = 25;
    self.effectSelectorButton.layer.borderWidth = 1.0;
    self.effectSelectorButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.effectSelectorButton.frame = CGRectMake(140, topOffset, 80, 50);
    self.effectSelectorButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.effectSelectorButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.effectSelectorButton.layer.shadowOpacity = 0.8;
    self.effectSelectorButton.layer.shadowRadius = 4;
    [self.effectSelectorButton addTarget:self action:@selector(effectSelectorButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.effectSelectorButton];
    [self.controlButtons addObject:self.effectSelectorButton];

    self.aiModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.aiModeButton setTitle:@"🤖 AI" forState:UIControlStateNormal];
    [self.aiModeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.aiModeButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    self.aiModeButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:0.9];
    self.aiModeButton.layer.cornerRadius = 25;
    self.aiModeButton.layer.borderWidth = 2.0;
    self.aiModeButton.layer.borderColor = [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:1.0].CGColor;
    self.aiModeButton.frame = CGRectMake(230, topOffset, 70, 50);
    self.aiModeButton.layer.shadowColor = [UIColor purpleColor].CGColor;
    self.aiModeButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.aiModeButton.layer.shadowOpacity = 0.8;
    self.aiModeButton.layer.shadowRadius = 4;
    [self.aiModeButton addTarget:self action:@selector(aiModeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.aiModeButton];
    [self.controlButtons addObject:self.aiModeButton];

    [self updateAIModeButtonState];
    [self createKaraokeButton];
    [self bringControlButtonsToFront];
}

- (void)createQuickEffectButtons {
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70;

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
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOffset = CGSizeMake(0, 2);
        button.layer.shadowOpacity = 0.8;
        button.layer.shadowRadius = 3;

        CGFloat buttonSize = 40;
        CGFloat spacing = 10;
        button.frame = CGRectMake(self.view.bounds.size.width - buttonSize - 20,
                                  topOffset + i * (buttonSize + spacing),
                                  buttonSize,
                                  buttonSize);

        [button addTarget:self action:@selector(quickEffectButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.view addSubview:button];
        [self.controlButtons addObject:button];
    }

    [self createGalaxyControlButton];
    [self createCyberpunkControlButton];
}

- (void)createGalaxyControlButton {
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
    self.galaxyControlButton.layer.shadowColor = [UIColor blackColor].CGColor;
    self.galaxyControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.galaxyControlButton.layer.shadowOpacity = 0.8;
    self.galaxyControlButton.layer.shadowRadius = 4;
    [self.galaxyControlButton addTarget:self action:@selector(galaxyControlButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.galaxyControlButton];
    [self.controlButtons addObject:self.galaxyControlButton];
}

- (void)createCyberpunkControlButton {
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
    self.cyberpunkControlButton.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.cyberpunkControlButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.cyberpunkControlButton.layer.shadowOpacity = 0.6;
    self.cyberpunkControlButton.layer.shadowRadius = 4;
    [self.cyberpunkControlButton addTarget:self action:@selector(cyberpunkControlButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.cyberpunkControlButton];
    [self.controlButtons addObject:self.cyberpunkControlButton];
}

- (void)createKaraokeButton {
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70;

    self.karaokeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.karaokeButton setTitle:@"🎤 卡拉OK" forState:UIControlStateNormal];
    [self.karaokeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.karaokeButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.karaokeButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.2 blue:0.2 alpha:0.9];
    self.karaokeButton.layer.cornerRadius = 25;
    self.karaokeButton.layer.borderWidth = 2.0;
    self.karaokeButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:1.0].CGColor;
    self.karaokeButton.frame = CGRectMake(20, topOffset, 120, 50);
    self.karaokeButton.layer.shadowColor = [UIColor redColor].CGColor;
    self.karaokeButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.karaokeButton.layer.shadowOpacity = 0.8;
    self.karaokeButton.layer.shadowRadius = 4;
    [self.karaokeButton addTarget:self action:@selector(karaokeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.karaokeButton];
    [self.controlButtons addObject:self.karaokeButton];

    [self createLyricsEffectButton];
}

- (void)createLyricsEffectButton {
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 70;

    self.lyricsEffectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.lyricsEffectButton setTitle:@"🎭 歌词" forState:UIControlStateNormal];
    [self.lyricsEffectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.lyricsEffectButton.titleLabel.font = [UIFont boldSystemFontOfSize:16];
    self.lyricsEffectButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.2 blue:0.8 alpha:0.9];
    self.lyricsEffectButton.layer.cornerRadius = 25;
    self.lyricsEffectButton.layer.borderWidth = 2.0;
    self.lyricsEffectButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.4 blue:1.0 alpha:1.0].CGColor;
    self.lyricsEffectButton.frame = CGRectMake(150, topOffset, 100, 50);
    self.lyricsEffectButton.layer.shadowColor = [UIColor purpleColor].CGColor;
    self.lyricsEffectButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.lyricsEffectButton.layer.shadowOpacity = 0.8;
    self.lyricsEffectButton.layer.shadowRadius = 4;
    [self.lyricsEffectButton addTarget:self action:@selector(lyricsEffectButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.lyricsEffectButton];
    [self.controlButtons addObject:self.lyricsEffectButton];

    [self createImportLyricsButton];
    [self createMixAudioControl];
}

- (void)createImportLyricsButton {
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
    self.importLyricsButton.frame = CGRectMake(lyricsButtonRightEdge + 5, topOffset, 70, 50);
    self.importLyricsButton.layer.shadowColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.5 alpha:1.0].CGColor;
    self.importLyricsButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.importLyricsButton.layer.shadowOpacity = 0.6;
    self.importLyricsButton.layer.shadowRadius = 3;
    [self.importLyricsButton addTarget:self action:@selector(importLyricsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importLyricsButton];
    [self.controlButtons addObject:self.importLyricsButton];
}

- (void)createMixAudioControl {
    CGFloat importButtonRightEdge = CGRectGetMaxX(self.importLyricsButton.frame);
    CGFloat topOffset = CGRectGetMinY(self.importLyricsButton.frame);

    self.mixAudioControlView = [[UIView alloc] initWithFrame:CGRectMake(importButtonRightEdge + 5, topOffset, 60, 50)];
    self.mixAudioControlView.backgroundColor = [UIColor colorWithRed:0.2 green:0.4 blue:0.6 alpha:0.9];
    self.mixAudioControlView.layer.cornerRadius = 25;
    self.mixAudioControlView.layer.borderWidth = 2.0;
    self.mixAudioControlView.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:1.0].CGColor;
    self.mixAudioControlView.layer.shadowColor = [UIColor cyanColor].CGColor;
    self.mixAudioControlView.layer.shadowOffset = CGSizeMake(0, 2);
    self.mixAudioControlView.layer.shadowOpacity = 0.8;
    self.mixAudioControlView.layer.shadowRadius = 4;

    self.mixAudioSwitch = [[UISwitch alloc] initWithFrame:CGRectMake(8, 10, 44, 30)];
    self.mixAudioSwitch.transform = CGAffineTransformMakeScale(0.75, 0.75);
    self.mixAudioSwitch.center = CGPointMake(30, 25);
    self.mixAudioSwitch.on = NO;
    self.mixAudioSwitch.onTintColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.5 alpha:1.0];
    [self.mixAudioSwitch addTarget:self action:@selector(mixAudioSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [self.mixAudioControlView addSubview:self.mixAudioSwitch];

    [self.view addSubview:self.mixAudioControlView];
    [self.controlButtons addObject:self.mixAudioControlView];
}

- (void)mixAudioSwitchChanged:(UISwitch *)sender {
    self.player.allowMixWithOthers = sender.isOn;

    NSLog(@"🔊 混音控制已%@: %@", sender.isOn ? @"开启" : @"关闭",
          sender.isOn ? @"允许与其他应用同时播放" : @"独占音频播放");

    AVAudioSession *session = [AVAudioSession sharedInstance];
    NSLog(@"   当前音频会话类别: %@", session.category);
    NSLog(@"   当前音频会话选项: %lu", (unsigned long)session.categoryOptions);

    NSString *message = sender.isOn ?
        @"已开启：可与其他应用同时播放\n（如QQ音乐、网易云等）" :
        @"已关闭：独占音频播放\n（会暂停其他应用的音乐）";

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔊 混音设置"
                                                                   message:message
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

- (void)createToggleUIButton:(CGFloat)topOffset {
    self.toggleUIButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.toggleUIButton setTitle:@"👁️" forState:UIControlStateNormal];
    self.toggleUIButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.toggleUIButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.2 alpha:0.9];
    self.toggleUIButton.layer.cornerRadius = 25;
    self.toggleUIButton.layer.borderWidth = 2.0;
    self.toggleUIButton.layer.borderColor = [UIColor whiteColor].CGColor;
    self.toggleUIButton.frame = CGRectMake(20, topOffset, 50, 50);
    self.toggleUIButton.layer.shadowColor = [UIColor whiteColor].CGColor;
    self.toggleUIButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.toggleUIButton.layer.shadowOpacity = 0.8;
    self.toggleUIButton.layer.shadowRadius = 4;
    [self.toggleUIButton addTarget:self action:@selector(toggleUIButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.toggleUIButton];
}

- (void)toggleUIButtonTapped:(UIButton *)sender {
    self.isUIHidden = !self.isUIHidden;

    NSLog(@"👁️ UI切换: %@", self.isUIHidden ? @"隐藏" : @"显示");
    [self.toggleUIButton setTitle:self.isUIHidden ? @"🙈" : @"👁️" forState:UIControlStateNormal];

    [UIView animateWithDuration:0.3 animations:^{
        self.toggleUIButton.alpha = self.isUIHidden ? 0.2 : 1.0;

        for (UIView *controlView in self.controlButtons) {
            controlView.alpha = self.isUIHidden ? 0.0 : 1.0;
            controlView.userInteractionEnabled = !self.isUIHidden;
        }

        if (self.fpsLabel) {
            self.fpsLabel.alpha = self.isUIHidden ? 0.0 : 1.0;
        }

        if (self.leftFunctionScrollView) {
            self.leftFunctionScrollView.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.leftFunctionScrollView.userInteractionEnabled = !self.isUIHidden;
        }

        if (self.importLyricsButton) {
            self.importLyricsButton.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.importLyricsButton.userInteractionEnabled = !self.isUIHidden;
        }

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

        if (self.searchBar) {
            self.searchBar.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.searchBar.userInteractionEnabled = !self.isUIHidden;
            if (self.isUIHidden) {
                [self.searchBar resignFirstResponder];
            }
        }

        [self setProgressViewHidden:self.isUIHidden animated:NO];
    }];
}

- (void)bringControlButtonsToFront {
    [self.view bringSubviewToFront:self.toggleUIButton];
    [self.view bringSubviewToFront:self.leftFunctionScrollView];
    [self.view bringSubviewToFront:self.previousButton];
    [self.view bringSubviewToFront:self.playPauseButton];
    [self.view bringSubviewToFront:self.nextButton];

    for (UIView *controlView in self.controlButtons) {
        [self.view bringSubviewToFront:controlView];
    }

    for (UIView *subview in self.view.subviews) {
        if ([subview isKindOfClass:[UIButton class]] &&
            subview != self.toggleUIButton &&
            subview != self.previousButton &&
            subview != self.playPauseButton &&
            subview != self.nextButton &&
            subview.tag >= 0 &&
            subview.tag < VisualEffectTypeCount) {
            [self.view bringSubviewToFront:subview];
        }
    }
}

- (void)setupBackgroundLayers {
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
    layer.fillColor = [UIColor clearColor].CGColor;
    layer.strokeColor = [UIColor colorWithRed:50.0 / 255.0f green:50.0 / 255.0f blue:50.0 / 255.0f alpha:1].CGColor;
    layer.lineWidth = lineWidth;
    layer.path = path.CGPath;
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

    [self.animationCoordinator setupGradientLayer:self.gradientLayer];
}

- (void)setupImageView {
    [self configInit];

    self.coverImageView = [[UIImageView alloc] init];
    self.coverImageView.frame = CGRectMake(0, 0, 170, 170);

    self.vinylRecordView = [[VinylRecordView alloc] initWithFrame:CGRectMake(0, 0, 170, 170)];
    self.vinylRecordView.center = self.view.center;
    self.vinylRecordView.rotationsPerSecond = 0.5;
    self.vinylRecordView.glossIntensity = 0.35;
    self.vinylRecordView.hidden = YES;
    [self.view addSubview:self.vinylRecordView];

    UIImage *coverImage = nil;
    NSString *songName = nil;

    if (self.displayedMusicItems.count > 0 && self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
        songName = musicItem.displayName ?: musicItem.fileName;

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

    if (coverImage) {
        self.coverImageView.image = coverImage;
        self.coverImageView.hidden = NO;
        self.vinylRecordView.hidden = YES;
        self.isShowingVinylRecord = NO;
        NSLog(@"🖼️ 显示音乐封面");
    } else {
        self.coverImageView.hidden = YES;
        self.vinylRecordView.hidden = NO;
        self.isShowingVinylRecord = YES;

        if (songName) {
            [self.vinylRecordView regenerateAppearanceWithSongName:songName];
        }
        NSLog(@"🎵 显示黑胶唱片动画（无封面）");
    }

    self.coverImageView.layer.cornerRadius = self.coverImageView.frame.size.height / 2.0;
    self.coverImageView.clipsToBounds = YES;
    self.coverImageView.contentMode = UIViewContentModeScaleAspectFill;
    self.coverImageView.center = self.view.center;
    [self.view addSubview:self.coverImageView];

    if (!self.isShowingVinylRecord) {
        [self.animationCoordinator addRotationViews:@[self.coverImageView]
                                          rotations:@[@(6.0)]
                                          durations:@[@(120.0)]
                                      rotationTypes:@[@(RotationTypeCounterClockwise)]];
    }

    [self.view addSubview:[self buildTableHeadView]];
    [self bringControlButtonsToFront];
}

- (void)setupParticleSystem {
    UIView *containerView = [[UIView alloc] init];
    containerView.frame = CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
    [self.view addSubview:containerView];

    self.xlayer = [[CALayer alloc] init];
    self.xlayer.frame = CGRectMake(0, 0, UIScreen.mainScreen.bounds.size.width, UIScreen.mainScreen.bounds.size.height);
    [containerView.layer addSublayer:self.xlayer];

    [self.animationCoordinator setupParticleContainerLayer:self.xlayer];
    [self.animationCoordinator.particleManager setEmitterPosition:self.view.center];
    [self.animationCoordinator.particleManager setEmitterSize:self.view.bounds.size];

    if (self.displayedMusicItems.count > 0 && self.currentIndex < self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];

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

- (void)performAnimation {
}

- (void)animationDidStop:(CAAnimation *)animation finished:(BOOL)flag {
}

- (void)createMusic {
    [self configInit];
    [self buildUI];
}

- (void)configInit {
    self.title = @"播放";

    if (self.audioArray.count > 0) {
        return;
    }

    NSArray *audioFiles = [AudioFileFormats loadAudioFilesFromBundle];
    [self.audioArray addObjectsFromArray:audioFiles];
}

- (void)buildUI {
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat navigationBarHeight = self.navigationController.navigationBar.frame.size.height;
    CGFloat statusBarHeight = [[UIApplication sharedApplication] statusBarFrame].size.height;
    CGFloat topOffset = MAX(safeTop, statusBarHeight + navigationBarHeight) + 140;

    CGFloat leftX = 10;
    CGFloat buttonWidth = 70;
    CGFloat buttonHeight = 40;
    CGFloat spacing = 8;
    CGFloat scrollViewWidth = buttonWidth + 20;
    CGFloat scrollViewHeight = self.view.frame.size.height - topOffset - 20;

    self.leftFunctionScrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, topOffset, scrollViewWidth, scrollViewHeight)];
    self.leftFunctionScrollView.showsVerticalScrollIndicator = YES;
    self.leftFunctionScrollView.showsHorizontalScrollIndicator = NO;
    self.leftFunctionScrollView.bounces = YES;
    self.leftFunctionScrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.leftFunctionScrollView];

    CGFloat contentY = 0;
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

        CGFloat yPos = contentY + i * (buttonHeight + spacing);
        button.frame = CGRectMake(leftX, yPos, buttonWidth, buttonHeight);

        [button addTarget:self action:@selector(categoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.leftFunctionScrollView addSubview:button];
        [self.categoryButtons addObject:button];

        if (i == 0) {
            button.backgroundColor = [UIColor colorWithRed:0.2 green:0.5 blue:0.8 alpha:0.9];
            button.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
        }
    }

    CGFloat sortButtonY = contentY + categories.count * (buttonHeight + spacing) + 15;
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
    [self.leftFunctionScrollView addSubview:self.sortButton];

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
    [self.leftFunctionScrollView addSubview:self.reloadButton];

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
    [self.leftFunctionScrollView addSubview:self.importButton];

    CGFloat clearAICacheButtonY = importButtonY + buttonHeight + spacing;
    self.clearAICacheButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.clearAICacheButton setTitle:@"🗑️ 清除 AI" forState:UIControlStateNormal];
    [self.clearAICacheButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.clearAICacheButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.clearAICacheButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.3 blue:0.3 alpha:0.85];
    self.clearAICacheButton.layer.cornerRadius = 8;
    self.clearAICacheButton.layer.borderWidth = 1.5;
    self.clearAICacheButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.4 blue:0.4 alpha:0.8].CGColor;
    self.clearAICacheButton.frame = CGRectMake(leftX, clearAICacheButtonY, buttonWidth, buttonHeight);
    [self.clearAICacheButton addTarget:self action:@selector(clearAICacheButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftFunctionScrollView addSubview:self.clearAICacheButton];

    CGFloat aiSettingsButtonY = clearAICacheButtonY + buttonHeight + spacing;
    self.aiSettingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.aiSettingsButton setTitle:@"🤖 AI设置" forState:UIControlStateNormal];
    [self.aiSettingsButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.aiSettingsButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    self.aiSettingsButton.titleLabel.numberOfLines = 2;
    self.aiSettingsButton.titleLabel.textAlignment = NSTextAlignmentCenter;
    self.aiSettingsButton.backgroundColor = [UIColor colorWithRed:0.32 green:0.45 blue:0.85 alpha:0.85];
    self.aiSettingsButton.layer.cornerRadius = 8;
    self.aiSettingsButton.layer.borderWidth = 1.5;
    self.aiSettingsButton.layer.borderColor = [UIColor colorWithRed:0.45 green:0.58 blue:1.0 alpha:0.8].CGColor;
    self.aiSettingsButton.frame = CGRectMake(leftX, aiSettingsButtonY, buttonWidth, buttonHeight);
    [self.aiSettingsButton addTarget:self action:@selector(aiSettingsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftFunctionScrollView addSubview:self.aiSettingsButton];

    CGFloat controlButtonHeight = 32;
    CGFloat controlSpacing = 4;

    CGFloat loopButtonY = aiSettingsButtonY + buttonHeight + spacing + 10;
    self.loopButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.loopButton setTitle:@"🔁" forState:UIControlStateNormal];
    self.loopButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.loopButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.loopButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.7 alpha:0.85];
    self.loopButton.layer.cornerRadius = 6;
    self.loopButton.layer.borderWidth = 1.0;
    self.loopButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.5 blue:0.8 alpha:0.8].CGColor;
    self.loopButton.frame = CGRectMake(leftX, loopButtonY, buttonWidth, controlButtonHeight);
    [self.loopButton addTarget:self action:@selector(loopButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftFunctionScrollView addSubview:self.loopButton];
    self.isSingleLoopMode = NO;

    CGFloat cloudButtonY = loopButtonY + controlButtonHeight + controlSpacing;
    self.cloudButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.cloudButton setTitle:@"☁️" forState:UIControlStateNormal];
    self.cloudButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.cloudButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.cloudButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.85];
    self.cloudButton.layer.cornerRadius = 6;
    self.cloudButton.layer.borderWidth = 1.0;
    self.cloudButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:0.8].CGColor;
    self.cloudButton.frame = CGRectMake(leftX, cloudButtonY, buttonWidth, controlButtonHeight);
    [self.cloudButton addTarget:self action:@selector(cloudDownloadButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftFunctionScrollView addSubview:self.cloudButton];

    CGFloat timingButtonY = cloudButtonY + controlButtonHeight + controlSpacing;
    self.lyricsTimingButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.lyricsTimingButton setTitle:@"🎼" forState:UIControlStateNormal];
    self.lyricsTimingButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.lyricsTimingButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.lyricsTimingButton.backgroundColor = [UIColor colorWithRed:0.9 green:0.5 blue:0.1 alpha:0.85];
    self.lyricsTimingButton.layer.cornerRadius = 6;
    self.lyricsTimingButton.layer.borderWidth = 1.0;
    self.lyricsTimingButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.7 blue:0.3 alpha:0.8].CGColor;
    self.lyricsTimingButton.frame = CGRectMake(leftX, timingButtonY, buttonWidth, controlButtonHeight);
    [self.lyricsTimingButton addTarget:self action:@selector(lyricsTimingButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.leftFunctionScrollView addSubview:self.lyricsTimingButton];

    CGFloat totalContentHeight = timingButtonY + controlButtonHeight + 20;
    self.leftFunctionScrollView.contentSize = CGSizeMake(scrollViewWidth, totalContentHeight);

    CGFloat screenWidth = self.view.frame.size.width;
    CGFloat playControlWidth = 50;
    CGFloat playControlHeight = 40;
    CGFloat playControlSpacing = 8;
    CGFloat totalPlayControlWidth = playControlWidth * 3 + playControlSpacing * 2;
    CGFloat playControlX = screenWidth - totalPlayControlWidth - 15;
    CGFloat playControlY = topOffset;

    self.previousButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.previousButton setTitle:@"⏮️" forState:UIControlStateNormal];
    self.previousButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.previousButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.previousButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:0.85];
    self.previousButton.layer.cornerRadius = 6;
    self.previousButton.layer.borderWidth = 1.0;
    self.previousButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:0.8].CGColor;
    self.previousButton.frame = CGRectMake(playControlX, playControlY, playControlWidth, playControlHeight);
    [self.previousButton addTarget:self action:@selector(previousButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.previousButton];

    CGFloat playButtonX = playControlX + playControlWidth + playControlSpacing;
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.playPauseButton setTitle:@"▶️" forState:UIControlStateNormal];
    self.playPauseButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.playPauseButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.7 blue:0.3 alpha:0.85];
    self.playPauseButton.layer.cornerRadius = 6;
    self.playPauseButton.layer.borderWidth = 1.0;
    self.playPauseButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.8 blue:0.4 alpha:0.8].CGColor;
    self.playPauseButton.frame = CGRectMake(playButtonX, playControlY, playControlWidth, playControlHeight);
    [self.playPauseButton addTarget:self action:@selector(playPauseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.playPauseButton];

    CGFloat nextButtonX = playButtonX + playControlWidth + playControlSpacing;
    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.nextButton setTitle:@"⏭️" forState:UIControlStateNormal];
    self.nextButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [self.nextButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.nextButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:0.85];
    self.nextButton.layer.cornerRadius = 6;
    self.nextButton.layer.borderWidth = 1.0;
    self.nextButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.8 alpha:0.8].CGColor;
    self.nextButton.frame = CGRectMake(nextButtonX, playControlY, playControlWidth, playControlHeight);
    [self.nextButton addTarget:self action:@selector(nextButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.nextButton];

    CGFloat searchBarX = scrollViewWidth + 5;
    CGFloat searchBarWidth = playControlX - searchBarX - 10;
    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(searchBarX, topOffset, searchBarWidth, 50)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索歌曲、艺术家...";
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.enablesReturnKeyAutomatically = YES;
    [self.view addSubview:self.searchBar];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];

    CGFloat tableY = topOffset + 60;
    CGFloat tableX = searchBarX;
    CGFloat tableWidth = self.view.frame.size.width - searchBarX - 10;
    self.tableView = [[UITableView alloc] initWithFrame:CGRectMake(tableX, tableY, tableWidth, self.view.frame.size.height - tableY) style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 100, tableWidth, self.view.frame.size.height)];
    self.tableView.tableFooterView = [UIView new];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.rowHeight = 60;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];

    [self bringControlButtonsToFront];
}

- (UIView *)buildTableHeadView {
    self.spectrumView = [[SpectrumView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    self.spectrumView.backgroundColor = [UIColor clearColor];
    [self.visualEffectManager setOriginalSpectrumView:self.spectrumView];
    return self.spectrumView;
}

#pragma mark - Effect Controls

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
        self.cyberpunkControlPanel = [[CyberpunkControlPanel alloc] initWithFrame:CGRectMake(20, 100,
                                                                                             self.view.bounds.size.width - 40,
                                                                                             550)];
        self.cyberpunkControlPanel.delegate = self;
        [self.view addSubview:self.cyberpunkControlPanel];

        NSDictionary *defaultSettings = @{
            @"enableClimaxEffect": @(1.0),
            @"enableBassEffect": @(1.0),
            @"enableMidEffect": @(1.0),
            @"enableTrebleEffect": @(1.0),
            @"showDebugBars": @(0.0),
            @"enableGrid": @(1.0),
            @"backgroundMode": @(0.0),
            @"solidColorR": @(0.15),
            @"solidColorG": @(0.1),
            @"solidColorB": @(0.25),
            @"backgroundIntensity": @(0.8)
        };
        [self.cyberpunkControlPanel setCurrentSettings:defaultSettings];
        [self.visualEffectManager setRenderParameters:defaultSettings];
    }

    [self.cyberpunkControlPanel showAnimated:YES];
    [self.view bringSubviewToFront:self.cyberpunkControlPanel];
}

- (void)handleEffectSettingsButtonTapped:(NSNotification *)notification {
    VisualEffectType effectType = [notification.userInfo[@"effectType"] integerValue];
    NSLog(@"🎨 收到特效配置请求: %ld", (long)effectType);

    if (effectType == VisualEffectTypeGalaxy) {
        [self galaxyControlButtonTapped:nil];
    } else if (effectType == VisualEffectTypeCyberPunk) {
        [self cyberpunkControlButtonTapped:nil];
    }
}

- (void)quickEffectButtonTapped:(UIButton *)sender {
    VisualEffectType effectType = (VisualEffectType)sender.tag;

    if ([self.visualEffectManager isEffectSupported:effectType]) {
        [self.visualEffectManager setCurrentEffect:effectType animated:YES];
        [self recordUserManualEffectChange:effectType];

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
        [self showUnsupportedEffectAlert];
    }
}

- (void)recordUserManualEffectChange:(VisualEffectType)newEffect {
    EffectDecisionAgent *agent = [EffectDecisionAgent sharedAgent];

    NSString *songName = @"Unknown";
    NSString *artist = nil;
    if (self.currentIndex >= 0 && self.currentIndex < (NSInteger)self.displayedMusicItems.count) {
        MusicItem *musicItem = self.displayedMusicItems[self.currentIndex];
        songName = musicItem.displayName ?: musicItem.fileName ?: @"Unknown";
        artist = musicItem.artist;
    }

    [agent userDidManuallyChangeEffect:newEffect forSongName:songName artist:artist];
}

- (void)showUnsupportedEffectAlert {
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"特效不支持"
                                                                   message:@"该特效需要更高性能的设备支持"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    UIAlertAction *okAction = [UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil];
    [alert addAction:okAction];
    [self presentViewController:alert animated:YES completion:nil];
}

#pragma mark - VisualEffectManagerDelegate

- (void)visualEffectManager:(VisualEffectManager *)manager didChangeEffect:(VisualEffectType)effectType {
    [manager startRendering];
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

#pragma mark - Control Delegates

- (void)galaxyControlDidUpdateSettings:(NSDictionary *)settings {
    [self.visualEffectManager setRenderParameters:settings];

    if (self.visualEffectManager.currentEffectType != VisualEffectTypeGalaxy) {
        [self.visualEffectManager setCurrentEffect:VisualEffectTypeGalaxy animated:YES];
        [self updateEffectButtonStates:VisualEffectTypeGalaxy];
    }
}

- (void)cyberpunkControlDidUpdateSettings:(NSDictionary *)settings {
    [self.visualEffectManager setRenderParameters:settings];

    if (self.visualEffectManager.currentEffectType != VisualEffectTypeCyberPunk) {
        [self.visualEffectManager setCurrentEffect:VisualEffectTypeCyberPunk animated:YES];
        [self updateEffectButtonStates:VisualEffectTypeCyberPunk];
    }
}

- (void)performanceControlDidUpdateSettings:(NSDictionary *)settings {
    NSLog(@"📥 ViewController收到性能设置: %@", settings);
    NSLog(@"   设置类型: %@", [settings class]);
    NSLog(@"   设置数量: %lu", (unsigned long)[settings count]);

    if (settings && [settings count] > 0) {
        NSLog(@"   fps=%@, msaa=%@, shader=%@, mode=%@",
              settings[@"fps"], settings[@"msaa"], settings[@"shaderComplexity"], settings[@"mode"]);
    }

    [self.visualEffectManager applyPerformanceSettings:settings];
}

- (void)performanceControlButtonTapped:(UIButton *)sender {
    if (!self.performanceControlPanel) {
        self.performanceControlPanel = [[PerformanceControlPanel alloc] initWithFrame:CGRectMake(20, 100,
                                                                                                 self.view.bounds.size.width - 40,
                                                                                                 self.view.bounds.size.height - 200)];
        self.performanceControlPanel.delegate = self;
        [self.view addSubview:self.performanceControlPanel];

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

- (void)aiModeButtonTapped:(UIButton *)sender {
    BOOL newState = !self.visualEffectManager.aiAutoModeEnabled;
    self.visualEffectManager.aiAutoModeEnabled = newState;
    [self updateAIModeButtonState];

    NSString *message = newState ? @"AI自动模式已开启\n将自动匹配最佳特效" : @"AI自动模式已关闭\n手动选择特效";
    [self showToastMessage:message];

    NSLog(@"🤖 AI自动模式: %@", newState ? @"开启" : @"关闭");
}

- (void)updateAIModeButtonState {
    BOOL isEnabled = self.visualEffectManager.aiAutoModeEnabled;

    if (isEnabled) {
        [self.aiModeButton setTitle:@"🤖 AI" forState:UIControlStateNormal];
        self.aiModeButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:0.9];
        self.aiModeButton.layer.borderColor = [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:1.0].CGColor;
    } else {
        [self.aiModeButton setTitle:@"🔇 AI" forState:UIControlStateNormal];
        self.aiModeButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.3 alpha:0.9];
        self.aiModeButton.layer.borderColor = [UIColor grayColor].CGColor;
    }
}

- (void)showToastMessage:(NSString *)message {
    UILabel *toast = [[UILabel alloc] init];
    toast.text = message;
    toast.textColor = [UIColor whiteColor];
    toast.backgroundColor = [UIColor colorWithRed:0 green:0 blue:0 alpha:0.8];
    toast.textAlignment = NSTextAlignmentCenter;
    toast.font = [UIFont systemFontOfSize:14];
    toast.numberOfLines = 0;
    toast.layer.cornerRadius = 10;
    toast.clipsToBounds = YES;

    CGSize maxSize = CGSizeMake(self.view.bounds.size.width - 80, 100);
    CGSize textSize = [message boundingRectWithSize:maxSize
                                            options:NSStringDrawingUsesLineFragmentOrigin
                                         attributes:@{NSFontAttributeName: toast.font}
                                            context:nil].size;

    CGFloat padding = 20;
    toast.frame = CGRectMake((self.view.bounds.size.width - textSize.width - padding * 2) / 2,
                             self.view.bounds.size.height - 150,
                             textSize.width + padding * 2,
                             textSize.height + padding);

    [self.view addSubview:toast];

    [UIView animateWithDuration:0.3 delay:1.5 options:UIViewAnimationOptionCurveEaseOut animations:^{
        toast.alpha = 0;
    } completion:^(BOOL finished) {
        [toast removeFromSuperview];
    }];
}

#pragma mark - FPS

- (void)setupFPSMonitor {
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

    self.fpsDisplayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(updateFPS:)];
    [self.fpsDisplayLink addToRunLoop:[NSRunLoop mainRunLoop] forMode:NSRunLoopCommonModes];

    self.frameCount = 0;
    self.lastTimestamp = 0;

    NSLog(@"✅ FPS监视器已启动");
}

- (void)updateFPS:(CADisplayLink *)displayLink {
    NSInteger targetFPS = 30;
    BOOL isPaused = YES;

    if (self.visualEffectManager && self.visualEffectManager.metalView) {
        targetFPS = self.visualEffectManager.metalView.preferredFramesPerSecond;
        isPaused = self.visualEffectManager.metalView.isPaused;
    }

    CGFloat displayFPS = isPaused ? 0 : targetFPS;

    UIColor *fpsColor = nil;
    NSString *statusEmoji = nil;
    if (displayFPS >= 55) {
        fpsColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.3 alpha:1.0];
        statusEmoji = @"🟢";
    } else if (displayFPS >= 25) {
        fpsColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
        statusEmoji = @"🟡";
    } else if (displayFPS > 0) {
        fpsColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
        statusEmoji = @"🔴";
    } else {
        fpsColor = [UIColor grayColor];
        statusEmoji = @"⚫️";
    }

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

#pragma mark - Agent Panel

- (void)setupAgentStatusPanel {
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat topOffset = MAX(safeTop, 44) + 10;

    self.agentStatusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [self.agentStatusButton setTitle:@"🧠" forState:UIControlStateNormal];
    [self.agentStatusButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.agentStatusButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
    self.agentStatusButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.2 blue:0.5 alpha:0.9];
    self.agentStatusButton.layer.cornerRadius = 25;
    self.agentStatusButton.layer.borderWidth = 2.0;
    self.agentStatusButton.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:1.0].CGColor;
    self.agentStatusButton.frame = CGRectMake(self.view.bounds.size.width - 60, topOffset + 80, 50, 50);
    self.agentStatusButton.layer.shadowColor = [UIColor purpleColor].CGColor;
    self.agentStatusButton.layer.shadowOffset = CGSizeMake(0, 2);
    self.agentStatusButton.layer.shadowOpacity = 0.8;
    self.agentStatusButton.layer.shadowRadius = 4;
    [self.agentStatusButton addTarget:self action:@selector(agentStatusButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.agentStatusButton];
    [self.controlButtons addObject:self.agentStatusButton];

    CGFloat panelWidth = 320;
    CGFloat panelHeight = 400;
    self.agentStatusPanel = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - panelWidth) / 2,
                                                                     (self.view.bounds.size.height - panelHeight) / 2,
                                                                     panelWidth,
                                                                     panelHeight)];
    self.agentStatusPanel.backgroundColor = [UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:0.95];
    self.agentStatusPanel.layer.cornerRadius = 20;
    self.agentStatusPanel.layer.borderWidth = 2;
    self.agentStatusPanel.layer.borderColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.8 alpha:1.0].CGColor;
    self.agentStatusPanel.hidden = YES;
    self.agentStatusPanel.layer.shadowColor = [UIColor blackColor].CGColor;
    self.agentStatusPanel.layer.shadowOffset = CGSizeMake(0, 5);
    self.agentStatusPanel.layer.shadowOpacity = 0.5;
    self.agentStatusPanel.layer.shadowRadius = 10;
    [self.view addSubview:self.agentStatusPanel];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 15, panelWidth - 40, 30)];
    titleLabel.text = @"🧠 Agent 状态面板";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.agentStatusPanel addSubview:titleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(panelWidth - 40, 10, 30, 30);
    [closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [closeButton addTarget:self action:@selector(closeAgentStatusPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.agentStatusPanel addSubview:closeButton];

    UILabel *metricsTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, panelWidth - 40, 20)];
    metricsTitle.text = @"📊 运行指标";
    metricsTitle.font = [UIFont boldSystemFontOfSize:14];
    metricsTitle.textColor = [UIColor cyanColor];
    [self.agentStatusPanel addSubview:metricsTitle];

    self.agentMetricsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 75, panelWidth - 40, 80)];
    self.agentMetricsLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.agentMetricsLabel.textColor = [UIColor lightGrayColor];
    self.agentMetricsLabel.numberOfLines = 0;
    self.agentMetricsLabel.text = @"加载中...";
    [self.agentStatusPanel addSubview:self.agentMetricsLabel];

    UILabel *recTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 160, panelWidth - 40, 20)];
    recTitle.text = @"💡 策略建议";
    recTitle.font = [UIFont boldSystemFontOfSize:14];
    recTitle.textColor = [UIColor yellowColor];
    [self.agentStatusPanel addSubview:recTitle];

    self.agentRecommendationsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 185, panelWidth - 40, 80)];
    self.agentRecommendationsLabel.font = [UIFont systemFontOfSize:12];
    self.agentRecommendationsLabel.textColor = [UIColor lightGrayColor];
    self.agentRecommendationsLabel.numberOfLines = 0;
    self.agentRecommendationsLabel.text = @"加载中...";
    [self.agentStatusPanel addSubview:self.agentRecommendationsLabel];

    UILabel *costTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 270, panelWidth - 40, 20)];
    costTitle.text = @"💰 成本控制";
    costTitle.font = [UIFont boldSystemFontOfSize:14];
    costTitle.textColor = [UIColor greenColor];
    [self.agentStatusPanel addSubview:costTitle];

    self.agentCostLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, 295, panelWidth - 40, 40)];
    self.agentCostLabel.font = [UIFont monospacedDigitSystemFontOfSize:12 weight:UIFontWeightRegular];
    self.agentCostLabel.textColor = [UIColor lightGrayColor];
    self.agentCostLabel.numberOfLines = 0;
    self.agentCostLabel.text = @"加载中...";
    [self.agentStatusPanel addSubview:self.agentCostLabel];

    UIButton *reflectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    reflectButton.frame = CGRectMake(20, 345, (panelWidth - 50) / 2, 40);
    [reflectButton setTitle:@"🔄 执行反思" forState:UIControlStateNormal];
    [reflectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reflectButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.8 alpha:1.0];
    reflectButton.layer.cornerRadius = 8;
    reflectButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [reflectButton addTarget:self action:@selector(performAgentReflection) forControlEvents:UIControlEventTouchUpInside];
    [self.agentStatusPanel addSubview:reflectButton];

    UIButton *reportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    reportButton.frame = CGRectMake(panelWidth / 2 + 5, 345, (panelWidth - 50) / 2, 40);
    [reportButton setTitle:@"📋 导出报告" forState:UIControlStateNormal];
    [reportButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reportButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.6 alpha:1.0];
    reportButton.layer.cornerRadius = 8;
    reportButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [reportButton addTarget:self action:@selector(exportAgentReport) forControlEvents:UIControlEventTouchUpInside];
    [self.agentStatusPanel addSubview:reportButton];

    NSLog(@"🧠 Agent 状态面板已初始化");
}

- (void)agentStatusButtonTapped:(UIButton *)sender {
    self.agentStatusPanel.hidden = NO;
    [self.view bringSubviewToFront:self.agentStatusPanel];
    [self updateAgentStatusDisplay];

    [self.agentStatusTimer invalidate];
    self.agentStatusTimer = [NSTimer scheduledTimerWithTimeInterval:2.0
                                                             target:self
                                                           selector:@selector(updateAgentStatusDisplay)
                                                           userInfo:nil
                                                            repeats:YES];
}

- (void)closeAgentStatusPanel {
    self.agentStatusPanel.hidden = YES;
    [self.agentStatusTimer invalidate];
    self.agentStatusTimer = nil;
}

- (void)updateAgentStatusDisplay {
    AgentMetrics *metrics = [[EffectDecisionAgent sharedAgent] getCurrentMetrics];

    NSString *metricsText = [NSString stringWithFormat:
        @"用户满意度: %.1f%%\n"
        @"LLM 调用率: %.1f%%\n"
        @"缓存命中率: %.1f%%\n"
        @"覆盖率: %.1f%%\n"
        @"风格多样性: %.1f%%",
        metrics.userSatisfaction * 100,
        metrics.llmCallRate * 100,
        metrics.cacheHitRate * 100,
        metrics.overrideRate * 100,
        metrics.styleDiversity * 100];
    self.agentMetricsLabel.text = metricsText;

    NSArray<NSString *> *recommendations = [[EffectDecisionAgent sharedAgent] getStrategyRecommendations];
    if (recommendations.count > 0) {
        NSMutableString *recText = [NSMutableString string];
        for (NSString *rec in recommendations) {
            [recText appendFormat:@"• %@\n", rec];
        }
        self.agentRecommendationsLabel.text = recText;
    } else {
        self.agentRecommendationsLabel.text = @"当前策略表现良好，无需调整 ✓";
        self.agentRecommendationsLabel.textColor = [UIColor greenColor];
    }

    AgentMetricsCollector *collector = [AgentMetricsCollector sharedCollector];
    NSDictionary *stats = [collector getRealTimeStats];

    NSInteger todayCalls = [stats[@"todayLLMCalls"] integerValue];
    NSInteger budget = [stats[@"llmBudget"] integerValue];
    BOOL exceeded = [stats[@"budgetExceeded"] boolValue];

    NSString *costText = [NSString stringWithFormat:@"今日 LLM 调用: %ld / %ld\n状态: %@",
                          (long)todayCalls,
                          (long)budget,
                          exceeded ? @"🔴 已超预算（强制本地）" : @"🟢 正常"];
    self.agentCostLabel.text = costText;
    self.agentCostLabel.textColor = exceeded ? [UIColor redColor] : [UIColor greenColor];
}

- (void)performAgentReflection {
    NSLog(@"🔄 手动触发 Agent 反思...");
    [[EffectDecisionAgent sharedAgent] performReflectionAndUpdate];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"🔍 反思完成"
                                                                   message:@"Agent 已完成决策复盘，策略已更新。"
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];

    [self updateAgentStatusDisplay];
}

- (void)exportAgentReport {
    NSString *reflectionReport = [[AgentReflectionEngine sharedEngine] exportAnalysisReport];
    NSString *metricsReport = [[AgentMetricsCollector sharedCollector] generateSummaryReport];
    NSString *fullReport = [NSString stringWithFormat:@"%@\n\n%@", metricsReport, reflectionReport];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"📋 Agent 分析报告"
                                                                   message:fullReport
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"复制" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
        [UIPasteboard generalPasteboard].string = fullReport;
        NSLog(@"📋 报告已复制到剪贴板");
    }]];
    [alert addAction:[UIAlertAction actionWithTitle:@"关闭" style:UIAlertActionStyleCancel handler:nil]];
    [self presentViewController:alert animated:YES completion:nil];
}

@end
