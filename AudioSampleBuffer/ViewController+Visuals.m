#import "ViewController+Private.h"

#import "AgentMetricsCollector.h"
#import "AgentReflectionEngine.h"
#import "AudioFileFormats.h"
#import "EffectDecisionAgent.h"
#import "ViewController+PlaybackProgress.h"

#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>

static NSString * const kSpectrumLayoutStyleDefaultsKey = @"SpectrumLayoutStyle";
static NSString * const kSpectrumColorModeDefaultsKey = @"SpectrumColorMode";
static NSString * const kSpectrumAutoColorDefaultsKey = @"SpectrumAutoColorEnabled";
static NSString * const kSpectrumHueDefaultsKey = @"SpectrumHueShift";
static NSString * const kSpectrumBrightnessDefaultsKey = @"SpectrumBrightness";
static NSString * const kSpectrumOpacityDefaultsKey = @"SpectrumOpacity";
static NSString * const kSpectrumPositionXDefaultsKey = @"SpectrumLayoutOffsetX";
static NSString * const kSpectrumPositionYDefaultsKey = @"SpectrumLayoutOffsetY";
static NSString * const kSpectrumScaleDefaultsKey     = @"SpectrumLayoutScale";

@implementation ViewController (Visuals)

#pragma mark - Setup

- (void)setupVisualEffectSystem {
    self.visualEffectManager = [[VisualEffectManager alloc] initWithContainerView:self.view];
    self.visualEffectManager.delegate = self;
    [self.visualEffectManager setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];
    [self updateBackgroundMediaEffectStateForEffect:VisualEffectTypeNeonGlow];
    [self refreshVisualLyricsOverlayVisibility];

    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleEffectSettingsButtonTapped:)
                                                 name:@"EffectSettingsButtonTapped"
                                               object:nil];
}

- (void)setupBackgroundMediaPanel {
    if (self.backgroundMediaPanelView) {
        return;
    }

    CGFloat panelWidth = MIN(320.0, self.view.bounds.size.width - 96.0);
    CGFloat safeTop = 0.0;
    CGFloat safeBottom = 0.0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
        safeBottom = self.view.safeAreaInsets.bottom;
    }
    CGFloat topOffset = MAX(safeTop, 44.0) + 8.0;
    CGFloat panelHeight = self.view.bounds.size.height - topOffset - safeBottom - 120.0;
    CGFloat originX = self.view.bounds.size.width - panelWidth - 68.0;

    UIView *panel = [[UIView alloc] initWithFrame:CGRectMake(originX, topOffset + 52.0, panelWidth, MAX(260.0, panelHeight))];
    panel.backgroundColor = [UIColor colorWithWhite:0.08 alpha:0.96];
    panel.layer.cornerRadius = 18.0;
    panel.layer.borderWidth = 1.0;
    panel.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    panel.hidden = YES;
    panel.alpha = 0.0;
    self.backgroundMediaPanelView = panel;

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(16, 14, panelWidth - 200, 24)];
    titleLabel.text = @"背景媒体列表";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textColor = [UIColor whiteColor];
    [panel addSubview:titleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(panelWidth - 40, 12, 28, 28);
    closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    closeButton.layer.cornerRadius = 14.0;
    [closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.92] forState:UIControlStateNormal];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:16 weight:UIFontWeightBold];
    [closeButton addTarget:self action:@selector(backgroundMediaCloseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:closeButton];

    CGFloat headerBtnH = 30.0;
    CGFloat headerBtnSpacing = 8.0;
    CGFloat headerRightEdge = CGRectGetMinX(closeButton.frame) - headerBtnSpacing;

    UIButton *enableButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat enableW = 66.0;
    enableButton.frame = CGRectMake(headerRightEdge - enableW, 12, enableW, headerBtnH);
    enableButton.layer.cornerRadius = 15.0;
    enableButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [enableButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    [enableButton addTarget:self action:@selector(backgroundMediaEnableButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:enableButton];
    self.backgroundMediaEnableButton = enableButton;

    UIButton *rhythmButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat rhythmW = 66.0;
    CGFloat rhythmX = CGRectGetMinX(enableButton.frame) - headerBtnSpacing - rhythmW;
    rhythmButton.frame = CGRectMake(MAX(16.0, rhythmX), 12, rhythmW, headerBtnH);
    rhythmButton.layer.cornerRadius = 15.0;
    rhythmButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [rhythmButton setTitle:@"律动" forState:UIControlStateNormal];
    [rhythmButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    rhythmButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.10];
    [rhythmButton addTarget:self action:@selector(backgroundMediaRhythmButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:rhythmButton];
    self.backgroundMediaRhythmButton = rhythmButton;

    UIButton *importButton = [UIButton buttonWithType:UIButtonTypeSystem];
    CGFloat importW = 72.0;
    CGFloat importX = CGRectGetMinX(rhythmButton.frame) - headerBtnSpacing - importW;
    importButton.frame = CGRectMake(MAX(16.0, importX), 12, importW, headerBtnH);
    importButton.backgroundColor = [UIColor colorWithRed:0.18 green:0.45 blue:0.82 alpha:1.0];
    importButton.layer.cornerRadius = 15.0;
    [importButton setTitle:@"导入" forState:UIControlStateNormal];
    [importButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    importButton.titleLabel.font = [UIFont boldSystemFontOfSize:13];
    [importButton addTarget:self action:@selector(importBackgroundMediaButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [panel addSubview:importButton];
    self.importBackgroundMediaButton = importButton;

    CGFloat headerHeight = 52.0;
    // 三行 slider：每行 32pt
    CGFloat rowH = 32.0;
    CGFloat controlsHeight = rowH * 3 + 12.0;

    UIView *controlsView = [[UIView alloc] initWithFrame:CGRectMake(12, headerHeight, panelWidth - 24, controlsHeight)];
    controlsView.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.06];
    controlsView.layer.cornerRadius = 14.0;
    controlsView.layer.borderWidth = 1.0;
    controlsView.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.10].CGColor;
    [panel addSubview:controlsView];
    self.backgroundMediaRhythmControlsView = controlsView;

    CGFloat sliderX = 62.0;
    CGFloat sliderW = controlsView.bounds.size.width - sliderX - 12.0;
    CGFloat labelX = 12.0;
    CGFloat labelW = 46.0;

    // 第 1 行：震颤（rate slider，控制 scale 脉冲 + beat 上 seek-forward 跳跃量）
    UILabel *rateLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, 8, labelW, 18)];
    rateLabel.text = @"震颤";
    rateLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    rateLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [controlsView addSubview:rateLabel];

    UISlider *rateSlider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, 4, sliderW, 26)];
    rateSlider.minimumValue = 0.0;
    rateSlider.maximumValue = 1.0;
    rateSlider.value = 0.55;
    rateSlider.minimumTrackTintColor = [UIColor colorWithRed:0.20 green:0.75 blue:0.45 alpha:1.0];
    rateSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [rateSlider addTarget:self action:@selector(backgroundMediaRhythmRateSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [controlsView addSubview:rateSlider];
    self.backgroundMediaRhythmRateSlider = rateSlider;

    // 第 2 行：色散（RGB 分离 + 调色幅度）
    UILabel *shakeLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, 8 + rowH, labelW, 18)];
    shakeLabel.text = @"色散";
    shakeLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    shakeLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [controlsView addSubview:shakeLabel];

    UISlider *shakeSlider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, 4 + rowH, sliderW, 26)];
    shakeSlider.minimumValue = 0.0;
    shakeSlider.maximumValue = 1.0;
    shakeSlider.value = 0.45;
    shakeSlider.minimumTrackTintColor = [UIColor colorWithRed:0.95 green:0.65 blue:0.20 alpha:1.0];
    shakeSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [shakeSlider addTarget:self action:@selector(backgroundMediaRhythmShakeSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [controlsView addSubview:shakeSlider];
    self.backgroundMediaRhythmShakeSlider = shakeSlider;

    // 第 3 行：闪屏（beat 上的白闪叠加层 alpha 上限）
    UILabel *flashLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, 8 + 2*rowH, labelW, 18)];
    flashLabel.text = @"闪屏";
    flashLabel.font = [UIFont systemFontOfSize:12 weight:UIFontWeightSemibold];
    flashLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [controlsView addSubview:flashLabel];

    UISlider *flashSlider = [[UISlider alloc] initWithFrame:CGRectMake(sliderX, 4 + 2*rowH, sliderW, 26)];
    flashSlider.minimumValue = 0.0;
    flashSlider.maximumValue = 1.0;
    flashSlider.value = 0.0;
    flashSlider.minimumTrackTintColor = [UIColor colorWithRed:0.92 green:0.92 blue:0.40 alpha:1.0];
    flashSlider.maximumTrackTintColor = [UIColor colorWithWhite:1.0 alpha:0.15];
    [flashSlider addTarget:self action:@selector(backgroundMediaRhythmFlashSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [controlsView addSubview:flashSlider];
    self.backgroundMediaRhythmFlashSlider = flashSlider;

    CGFloat tableY = headerHeight + controlsHeight + 10.0;
    UITableView *mediaTableView = [[UITableView alloc] initWithFrame:CGRectMake(0, tableY, panelWidth, panel.bounds.size.height - tableY) style:UITableViewStylePlain];
    mediaTableView.delegate = self;
    mediaTableView.dataSource = self;
    mediaTableView.backgroundColor = [UIColor clearColor];
    mediaTableView.separatorColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    mediaTableView.rowHeight = 62.0;
    mediaTableView.tableFooterView = [UIView new];
    [panel addSubview:mediaTableView];
    self.backgroundMediaTableView = mediaTableView;

    UILabel *emptyLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, tableY + 48, panelWidth - 40, 120)];
    emptyLabel.text = @"还没有背景媒体\n导入视频或 Live Photo 后，可在此选择循环背景。";
    emptyLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.65];
    emptyLabel.font = [UIFont systemFontOfSize:15 weight:UIFontWeightMedium];
    emptyLabel.numberOfLines = 0;
    emptyLabel.textAlignment = NSTextAlignmentCenter;
    [panel addSubview:emptyLabel];
    self.backgroundMediaEmptyLabel = emptyLabel;

    [self.view addSubview:panel];
    [self reloadBackgroundMediaLibrary];
    [self refreshBackgroundMediaButtonState];
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
    CGFloat topOffset = MAX(safeTop, 44.0) + 8;

    // 隐藏UI 切换按钮 - 左上角
    [self createToggleUIButton:topOffset];

    [self setupFPSMonitor];

    // 右侧功能按钮区域 - 统一 44x44 圆形图标按钮，竖向排列
    CGFloat btnSize = 44;
    CGFloat btnSpacing = 10;
    CGFloat rightX = self.view.bounds.size.width - btnSize - 12;
    CGFloat rightY = topOffset;

    // 特效按钮
    self.effectSelectorButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *effectImage = nil;
    if (@available(iOS 13.0, *)) {
        effectImage = [UIImage systemImageNamed:@"paintpalette.fill"];
    }
    [self.effectSelectorButton setImage:effectImage forState:UIControlStateNormal];
    [self.effectSelectorButton setTitle:@"" forState:UIControlStateNormal];
    self.effectSelectorButton.tintColor = [UIColor whiteColor];
    self.effectSelectorButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.25 alpha:0.85];
    self.effectSelectorButton.layer.cornerRadius = btnSize / 2;
    self.effectSelectorButton.layer.borderWidth = 1.0;
    self.effectSelectorButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
    self.effectSelectorButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
    [self.effectSelectorButton addTarget:self action:@selector(effectSelectorButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.effectSelectorButton];
    [self.controlButtons addObject:self.effectSelectorButton];
    rightY += btnSize + btnSpacing;

    // 频谱样式按钮
    self.spectrumStyleButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *spectrumImage = nil;
    if (@available(iOS 13.0, *)) {
        spectrumImage = [UIImage systemImageNamed:@"waveform.path.ecg"];
    }
    [self.spectrumStyleButton setImage:spectrumImage forState:UIControlStateNormal];
    [self.spectrumStyleButton setTitle:@"" forState:UIControlStateNormal];
    self.spectrumStyleButton.tintColor = [UIColor whiteColor];
    self.spectrumStyleButton.backgroundColor = [UIColor colorWithRed:0.16 green:0.24 blue:0.42 alpha:0.88];
    self.spectrumStyleButton.layer.cornerRadius = btnSize / 2;
    self.spectrumStyleButton.layer.borderWidth = 1.0;
    self.spectrumStyleButton.layer.borderColor = [UIColor colorWithRed:0.45 green:0.72 blue:1.0 alpha:0.45].CGColor;
    self.spectrumStyleButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
    [self.spectrumStyleButton addTarget:self action:@selector(spectrumStyleButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.spectrumStyleButton];
    [self.controlButtons addObject:self.spectrumStyleButton];
    rightY += btnSize + btnSpacing;

    // AI模式按钮
    self.aiModeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *aiImage = nil;
    if (@available(iOS 13.0, *)) {
        aiImage = [UIImage systemImageNamed:@"brain.head.profile.fill"];
    }
    [self.aiModeButton setImage:aiImage forState:UIControlStateNormal];
    [self.aiModeButton setTitle:@"" forState:UIControlStateNormal];
    self.aiModeButton.tintColor = [UIColor whiteColor];
    self.aiModeButton.backgroundColor = [UIColor colorWithRed:0.4 green:0.15 blue:0.6 alpha:0.85];
    self.aiModeButton.layer.cornerRadius = btnSize / 2;
    self.aiModeButton.layer.borderWidth = 1.0;
    self.aiModeButton.layer.borderColor = [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:0.5].CGColor;
    self.aiModeButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
    [self.aiModeButton addTarget:self action:@selector(aiModeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.aiModeButton];
    [self.controlButtons addObject:self.aiModeButton];
    rightY += btnSize + btnSpacing;

    // 性能设置按钮
    self.performanceControlButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *perfImage = nil;
    if (@available(iOS 13.0, *)) {
        perfImage = [UIImage systemImageNamed:@"gearshape.fill"];
    }
    [self.performanceControlButton setImage:perfImage forState:UIControlStateNormal];
    [self.performanceControlButton setTitle:@"" forState:UIControlStateNormal];
    self.performanceControlButton.tintColor = [UIColor whiteColor];
    self.performanceControlButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.35 blue:0.15 alpha:0.85];
    self.performanceControlButton.layer.cornerRadius = btnSize / 2;
    self.performanceControlButton.layer.borderWidth = 1.0;
    self.performanceControlButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.3 alpha:0.5].CGColor;
    self.performanceControlButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
    [self.performanceControlButton addTarget:self action:@selector(performanceControlButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.performanceControlButton];
    [self.controlButtons addObject:self.performanceControlButton];

    [self updateAIModeButtonState];
    [self createKaraokeButton];
    [self bringControlButtonsToFront];
}

- (void)createQuickEffectButtons {
    // 快速特效按钮现已整合到 effectSelectorButton 弹出面板中，此处不再创建独立按钮
    [self createGalaxyControlButton];
    [self createCyberpunkControlButton];
}

- (void)createGalaxyControlButton {
    // 银河控制按钮现已通过特效选择器面板访问，不再独立显示
}

- (void)createCyberpunkControlButton {
    // 赛博朋克控制按钮现已通过特效选择器面板访问，不再独立显示
}

- (void)createKaraokeButton {
    // 卡拉OK 按钮 - 接续右侧竖排（在 performanceControlButton 下方继续）
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat topOffset = MAX(safeTop, 44.0) + 8;

    CGFloat btnSize = 44;
    CGFloat btnSpacing = 10;
    CGFloat rightX = self.view.bounds.size.width - btnSize - 12;
    // 跳过前4个按钮(特效+频谱+AI+性能)的位置
    CGFloat rightY = topOffset + (btnSize + btnSpacing) * 4;

    self.karaokeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *micImage = nil;
    if (@available(iOS 13.0, *)) {
        micImage = [UIImage systemImageNamed:@"mic.fill"];
    }
    [self.karaokeButton setImage:micImage forState:UIControlStateNormal];
    [self.karaokeButton setTitle:@"" forState:UIControlStateNormal];
    self.karaokeButton.tintColor = [UIColor whiteColor];
    self.karaokeButton.backgroundColor = [UIColor colorWithRed:0.55 green:0.1 blue:0.1 alpha:0.85];
    self.karaokeButton.layer.cornerRadius = btnSize / 2;
    self.karaokeButton.layer.borderWidth = 1.0;
    self.karaokeButton.layer.borderColor = [UIColor colorWithRed:1.0 green:0.3 blue:0.3 alpha:0.5].CGColor;
    self.karaokeButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
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
    CGFloat topOffset = MAX(safeTop, 44.0) + 8;

    CGFloat btnSize = 44;
    CGFloat btnSpacing = 10;
    CGFloat rightX = self.view.bounds.size.width - btnSize - 12;
    // 跳过前5个按钮(特效+频谱+AI+性能+卡拉OK)的位置
    CGFloat rightY = topOffset + (btnSize + btnSpacing) * 5;

    // 歌词特效按钮
    self.lyricsEffectButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *lyricsImage = nil;
    if (@available(iOS 13.0, *)) {
        lyricsImage = [UIImage systemImageNamed:@"music.note.list"];
    }
    [self.lyricsEffectButton setImage:lyricsImage forState:UIControlStateNormal];
    [self.lyricsEffectButton setTitle:@"" forState:UIControlStateNormal];
    self.lyricsEffectButton.tintColor = [UIColor whiteColor];
    self.lyricsEffectButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.12 blue:0.5 alpha:0.85];
    self.lyricsEffectButton.layer.cornerRadius = btnSize / 2;
    self.lyricsEffectButton.layer.borderWidth = 1.0;
    self.lyricsEffectButton.layer.borderColor = [UIColor colorWithRed:0.7 green:0.4 blue:1.0 alpha:0.5].CGColor;
    self.lyricsEffectButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
    [self.lyricsEffectButton addTarget:self action:@selector(lyricsEffectButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.lyricsEffectButton];
    [self.controlButtons addObject:self.lyricsEffectButton];
    rightY += btnSize + btnSpacing;

    // 导入歌词按钮
    self.importLyricsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *importLyricsImage = nil;
    if (@available(iOS 13.0, *)) {
        importLyricsImage = [UIImage systemImageNamed:@"doc.badge.plus"];
    }
    [self.importLyricsButton setImage:importLyricsImage forState:UIControlStateNormal];
    [self.importLyricsButton setTitle:@"" forState:UIControlStateNormal];
    self.importLyricsButton.tintColor = [UIColor whiteColor];
    self.importLyricsButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.3 blue:0.25 alpha:0.85];
    self.importLyricsButton.layer.cornerRadius = btnSize / 2;
    self.importLyricsButton.layer.borderWidth = 1.0;
    self.importLyricsButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.7 blue:0.6 alpha:0.5].CGColor;
    self.importLyricsButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
    [self.importLyricsButton addTarget:self action:@selector(importLyricsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.importLyricsButton];
    [self.controlButtons addObject:self.importLyricsButton];

    [self createMixAudioControl];
}

- (void)createImportLyricsButton {
    // 导入歌词按钮已移至 createLyricsEffectButton 中统一创建，此方法保留为空兼容调用
}

- (void)createMixAudioControl {
    // 混音控制放在右侧竖排末尾（导入歌词按钮下方）
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat topOffset = MAX(safeTop, 44.0) + 8;
    CGFloat btnSize = 44;
    CGFloat btnSpacing = 10;
    CGFloat rightX = self.view.bounds.size.width - btnSize - 12;
    // 跳过前7个按钮的位置(特效+频谱+AI+性能+卡拉OK+歌词+导入歌词)
    CGFloat rightY = topOffset + (btnSize + btnSpacing) * 7;

    self.mixAudioControlView = [[UIView alloc] initWithFrame:CGRectMake(rightX, rightY, btnSize, btnSize)];
    self.mixAudioControlView.backgroundColor = [UIColor colorWithRed:0.1 green:0.25 blue:0.4 alpha:0.85];
    self.mixAudioControlView.layer.cornerRadius = btnSize / 2;
    self.mixAudioControlView.layer.borderWidth = 1.0;
    self.mixAudioControlView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:0.9 alpha:0.5].CGColor;

    self.mixAudioSwitch = [[UISwitch alloc] init];
    self.mixAudioSwitch.transform = CGAffineTransformMakeScale(0.65, 0.65);
    self.mixAudioSwitch.center = CGPointMake(btnSize / 2, btnSize / 2);
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
    CGFloat btnSize = 36;
    self.toggleUIButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *eyeImage = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
        eyeImage = [UIImage systemImageNamed:@"eye.fill" withConfiguration:config];
    }
    [self.toggleUIButton setImage:eyeImage forState:UIControlStateNormal];
    [self.toggleUIButton setTitle:@"" forState:UIControlStateNormal];
    self.toggleUIButton.tintColor = [UIColor colorWithWhite:1.0 alpha:0.8];
    self.toggleUIButton.backgroundColor = [UIColor colorWithWhite:0.15 alpha:0.75];
    self.toggleUIButton.layer.cornerRadius = btnSize / 2;
    self.toggleUIButton.layer.borderWidth = 1.0;
    self.toggleUIButton.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    self.toggleUIButton.frame = CGRectMake(12, topOffset + 4, btnSize, btnSize);
    [self.toggleUIButton addTarget:self action:@selector(toggleUIButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:self.toggleUIButton];
}

- (void)toggleUIButtonTapped:(UIButton *)sender {
    self.isUIHidden = !self.isUIHidden;

    NSLog(@"👁️ UI切换: %@", self.isUIHidden ? @"隐藏" : @"显示");
    UIImage *eyeImage = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *config = [UIImageSymbolConfiguration configurationWithPointSize:16 weight:UIImageSymbolWeightMedium];
        eyeImage = [UIImage systemImageNamed:self.isUIHidden ? @"eye.slash.fill" : @"eye.fill" withConfiguration:config];
    }
    [self.toggleUIButton setImage:eyeImage forState:UIControlStateNormal];

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

        if (self.playControlBarView) {
            self.playControlBarView.alpha = self.isUIHidden ? 0.0 : 1.0;
            self.playControlBarView.userInteractionEnabled = !self.isUIHidden;
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
    if (self.toggleUIButton) [self.view bringSubviewToFront:self.toggleUIButton];
    if (self.fpsLabel) [self.view bringSubviewToFront:self.fpsLabel];
    if (self.leftFunctionScrollView) [self.view bringSubviewToFront:self.leftFunctionScrollView];
    if (self.backgroundMediaPanelView && self.backgroundMediaPanelView.superview) {
        [self.view bringSubviewToFront:self.backgroundMediaPanelView];
    }
    if (self.spectrumStylePanelView && self.spectrumStylePanelView.superview) {
        [self.view bringSubviewToFront:self.spectrumStylePanelView];
    }

    for (UIView *controlView in self.controlButtons) {
        if (controlView && controlView.superview) {
            [self.view bringSubviewToFront:controlView];
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
        self.coverImageView.hidden = self.isBackgroundMediaEffectActive;
        self.vinylRecordView.hidden = YES;
        self.isShowingVinylRecord = NO;
        NSLog(@"🖼️ 显示音乐封面");
    } else {
        self.coverImageView.hidden = YES;
        self.vinylRecordView.hidden = self.isBackgroundMediaEffectActive;
        self.isShowingVinylRecord = !self.isBackgroundMediaEffectActive;

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
    CGFloat screenWidth  = self.view.frame.size.width;
    CGFloat screenHeight = self.view.frame.size.height;

    CGFloat safeTop = 0, safeBottom = 0;
    if (@available(iOS 11.0, *)) {
        safeTop    = self.view.safeAreaInsets.top;
        safeBottom = self.view.safeAreaInsets.bottom;
    }
    CGFloat topOffset = MAX(safeTop, 44.0) + 8;

    // ── 右侧功能按钮区宽度 ──
    CGFloat rightBtnSize  = 44;
    CGFloat rightBtnRight = rightBtnSize + 12 + 8; // 按钮宽+右边距+间隙

    // ── 底部播放控制区高度 ──
    CGFloat playAreaHeight = 100;
    CGFloat bottomAreaTop  = screenHeight - safeBottom - playAreaHeight;

    // ══════════════════════════════════════════
    // 左侧分类滚动视图
    // ══════════════════════════════════════════
    CGFloat leftScrollX     = 0;
    CGFloat leftScrollWidth = 80;
    CGFloat leftScrollTop   = topOffset + 52; // 给 toggleUIButton 留空间
    CGFloat leftScrollH     = bottomAreaTop - leftScrollTop - 8;

    self.leftFunctionScrollView = [[UIScrollView alloc] initWithFrame:
        CGRectMake(leftScrollX, leftScrollTop, leftScrollWidth, leftScrollH)];
    self.leftFunctionScrollView.showsVerticalScrollIndicator = NO;
    self.leftFunctionScrollView.showsHorizontalScrollIndicator = NO;
    self.leftFunctionScrollView.bounces = YES;
    self.leftFunctionScrollView.backgroundColor = [UIColor clearColor];
    [self.view addSubview:self.leftFunctionScrollView];

    CGFloat btnW = 58, btnH = 34, btnSpacing = 6, btnX = 11;
    CGFloat contentY = 8;
    self.categoryButtons = [NSMutableArray array];

    NSArray *categories = @[
        @{@"title": @"全部",  @"category": @(MusicCategoryAll)},
        @{@"title": @"最近",  @"category": @(MusicCategoryRecent)},
        @{@"title": @"最爱",  @"category": @(MusicCategoryFavorite)},
        @{@"title": @"MP3",  @"category": @(MusicCategoryMP3)},
        @{@"title": @"NCM",  @"category": @(MusicCategoryNCM)}
    ];

    for (NSInteger i = 0; i < (NSInteger)categories.count; i++) {
        NSDictionary *catInfo = categories[i];
        UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
        [button setTitle:catInfo[@"title"] forState:UIControlStateNormal];
        [button setTitleColor:[UIColor colorWithWhite:0.9 alpha:1.0] forState:UIControlStateNormal];
        button.titleLabel.font = [UIFont boldSystemFontOfSize:12];
        button.backgroundColor = [UIColor colorWithWhite:0.18 alpha:0.80];
        button.layer.cornerRadius = 8;
        button.layer.borderWidth = 1.0;
        button.layer.borderColor = [UIColor colorWithWhite:0.35 alpha:0.5].CGColor;
        button.tag = [catInfo[@"category"] integerValue];
        button.frame = CGRectMake(btnX, contentY + i * (btnH + btnSpacing), btnW, btnH);
        [button addTarget:self action:@selector(categoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [self.leftFunctionScrollView addSubview:button];
        [self.categoryButtons addObject:button];
        if (i == 0) {
            button.backgroundColor = [UIColor colorWithRed:0.15 green:0.45 blue:0.85 alpha:0.9];
            button.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:0.7].CGColor;
        }
    }

    CGFloat utilY = contentY + categories.count * (btnH + btnSpacing) + 12;

    // 工具按钮辅助 block（仅用图标，无文字，统一风格）
    NSArray *utilButtons = @[
        @{@"icon": @"arrow.up.arrow.down",    @"color": @[@0.2, @0.5, @0.25],  @"sel": @"sortButtonTapped:"},
        @{@"icon": @"arrow.clockwise",         @"color": @[@0.5, @0.28, @0.12], @"sel": @"reloadMusicLibraryButtonTapped:"},
        @{@"icon": @"tray.and.arrow.down",     @"color": @[@0.12, @0.42, @0.6], @"sel": @"importMusicButtonTapped:"},
        @{@"icon": @"photo.on.rectangle.angled", @"color": @[@0.18, @0.32, @0.62], @"sel": @"backgroundMediaButtonTapped:"},
        @{@"icon": @"trash.fill",              @"color": @[@0.6, @0.18, @0.18], @"sel": @"clearAICacheButtonTapped:"},
        @{@"icon": @"cpu.fill",                @"color": @[@0.22, @0.32, @0.7], @"sel": @"aiSettingsButtonTapped:"},
        @{@"icon": @"repeat",                  @"color": @[@0.4, @0.28, @0.5],  @"sel": @"loopButtonTapped:"},
        @{@"icon": @"icloud.and.arrow.down",   @"color": @[@0.12, @0.42, @0.68],@"sel": @"cloudDownloadButtonTapped:"},
        @{@"icon": @"waveform",                @"color": @[@0.6, @0.33, @0.06], @"sel": @"lyricsTimingButtonTapped:"}
    ];

    UIButton *sortBtn = nil, *reloadBtn = nil, *importBtn = nil, *mediaBtn = nil, *clearAIBtn = nil;
    UIButton *aiSettingsBtn = nil, *loopBtn = nil, *cloudBtn = nil, *timingBtn = nil;
    NSArray *btnRefs = @[
        [NSNull null], [NSNull null], [NSNull null], [NSNull null], [NSNull null],
        [NSNull null], [NSNull null], [NSNull null], [NSNull null]
    ];
    (void)btnRefs;

    for (NSInteger i = 0; i < (NSInteger)utilButtons.count; i++) {
        NSDictionary *info = utilButtons[i];
        NSArray *rgb = info[@"color"];
        UIButton *btn = [UIButton buttonWithType:UIButtonTypeSystem];
        if (@available(iOS 13.0, *)) {
            UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:14 weight:UIImageSymbolWeightMedium];
            [btn setImage:[UIImage systemImageNamed:info[@"icon"] withConfiguration:cfg] forState:UIControlStateNormal];
        }
        [btn setTitle:@"" forState:UIControlStateNormal];
        btn.tintColor = [UIColor whiteColor];
        btn.backgroundColor = [UIColor colorWithRed:[rgb[0] floatValue]
                                              green:[rgb[1] floatValue]
                                               blue:[rgb[2] floatValue]
                                              alpha:0.85];
        btn.layer.cornerRadius = 8;
        btn.layer.borderWidth = 1.0;
        btn.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.2].CGColor;
        btn.frame = CGRectMake(btnX, utilY + i * (btnH + btnSpacing), btnW, btnH);
        SEL action = NSSelectorFromString(info[@"sel"]);
        [btn addTarget:self action:action forControlEvents:UIControlEventTouchUpInside];
        [self.leftFunctionScrollView addSubview:btn];

        if (i == 0) sortBtn = btn;
        else if (i == 1) reloadBtn = btn;
        else if (i == 2) importBtn = btn;
        else if (i == 3) mediaBtn = btn;
        else if (i == 4) clearAIBtn = btn;
        else if (i == 5) aiSettingsBtn = btn;
        else if (i == 6) loopBtn = btn;
        else if (i == 7) cloudBtn = btn;
        else if (i == 8) timingBtn = btn;
    }

    self.sortButton          = sortBtn;
    self.reloadButton        = reloadBtn;
    self.importButton        = importBtn;
    self.backgroundMediaButton = mediaBtn;
    self.clearAICacheButton  = clearAIBtn;
    self.aiSettingsButton    = aiSettingsBtn;
    self.loopButton          = loopBtn;
    self.cloudButton         = cloudBtn;
    self.lyricsTimingButton  = timingBtn;
    self.isSingleLoopMode    = NO;

    CGFloat totalContentH = utilY + utilButtons.count * (btnH + btnSpacing) + 16;
    self.leftFunctionScrollView.contentSize = CGSizeMake(leftScrollWidth, totalContentH);

    // ══════════════════════════════════════════
    // 搜索栏 & 歌曲列表
    // ══════════════════════════════════════════
    CGFloat listLeft  = leftScrollX + leftScrollWidth + 4;
    CGFloat listRight = screenWidth - rightBtnRight - 4;
    CGFloat listW     = listRight - listLeft;

    self.searchBar = [[UISearchBar alloc] initWithFrame:CGRectMake(listLeft, topOffset, listW, 44)];
    self.searchBar.delegate = self;
    self.searchBar.placeholder = @"搜索歌曲、艺术家...";
    self.searchBar.barStyle = UIBarStyleBlack;
    self.searchBar.searchBarStyle = UISearchBarStyleMinimal;
    self.searchBar.enablesReturnKeyAutomatically = YES;
    [self.view addSubview:self.searchBar];

    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(dismissKeyboard)];
    tapGesture.cancelsTouchesInView = NO;
    [self.view addGestureRecognizer:tapGesture];

    CGFloat tableTop = topOffset + 48;
    self.tableView = [[UITableView alloc] initWithFrame:
        CGRectMake(listLeft, tableTop, listW, bottomAreaTop - tableTop - 4)
        style:UITableViewStylePlain];
    self.tableView.delegate = self;
    self.tableView.dataSource = self;
    self.tableView.tableHeaderView = [[UIView alloc] initWithFrame:CGRectMake(0, 100, listW, screenHeight)];
    self.tableView.tableFooterView = [UIView new];
    self.tableView.backgroundColor = [UIColor clearColor];
    self.tableView.rowHeight = 56;
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeOnDrag;
    [self.view addSubview:self.tableView];
    [self setupBackgroundMediaPanel];

    // ══════════════════════════════════════════
    // 底部播放控制区
    // ══════════════════════════════════════════
    // 背景毛玻璃条
    UIView *playBar = [[UIView alloc] initWithFrame:CGRectMake(0, bottomAreaTop, screenWidth, playAreaHeight + safeBottom)];
    playBar.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    // 上边框线
    CALayer *topLine = [CALayer layer];
    topLine.frame = CGRectMake(0, 0, screenWidth, 0.5);
    topLine.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    [playBar.layer addSublayer:topLine];
    [self.view addSubview:playBar];
    self.playControlBarView = playBar;

    // 三个播放按钮居中
    CGFloat prevW = 52, playW = 64, nextW = 52;
    CGFloat playH = 52;
    CGFloat gap = 20;
    CGFloat totalW = prevW + playW + nextW + gap * 2;
    CGFloat startX = (screenWidth - totalW) / 2;
    CGFloat btnCenterY = playAreaHeight / 2 - 4; // 在 playBar 内部的 Y

    // 上一首
    self.previousButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
        [self.previousButton setImage:[UIImage systemImageNamed:@"backward.end.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    }
    [self.previousButton setTitle:@"" forState:UIControlStateNormal];
    self.previousButton.tintColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    self.previousButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.previousButton.layer.cornerRadius = prevW / 2;
    self.previousButton.frame = CGRectMake(startX, btnCenterY - playH / 2, prevW, playH);
    [self.previousButton addTarget:self action:@selector(previousButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [playBar addSubview:self.previousButton];

    // 播放/暂停（更大更突出）
    self.playPauseButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:28 weight:UIImageSymbolWeightBold];
        [self.playPauseButton setImage:[UIImage systemImageNamed:@"play.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    }
    [self.playPauseButton setTitle:@"" forState:UIControlStateNormal];
    self.playPauseButton.tintColor = [UIColor whiteColor];
    self.playPauseButton.backgroundColor = [UIColor colorWithRed:0.15 green:0.6 blue:0.3 alpha:0.9];
    self.playPauseButton.layer.cornerRadius = playW / 2;
    self.playPauseButton.layer.borderWidth = 1.5;
    self.playPauseButton.layer.borderColor = [UIColor colorWithRed:0.3 green:0.85 blue:0.5 alpha:0.6].CGColor;
    self.playPauseButton.frame = CGRectMake(startX + prevW + gap, btnCenterY - playW / 2, playW, playW);
    [self.playPauseButton addTarget:self action:@selector(playPauseButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [playBar addSubview:self.playPauseButton];

    // 下一首
    self.nextButton = [UIButton buttonWithType:UIButtonTypeSystem];
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:22 weight:UIImageSymbolWeightMedium];
        [self.nextButton setImage:[UIImage systemImageNamed:@"forward.end.fill" withConfiguration:cfg] forState:UIControlStateNormal];
    }
    [self.nextButton setTitle:@"" forState:UIControlStateNormal];
    self.nextButton.tintColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    self.nextButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    self.nextButton.layer.cornerRadius = nextW / 2;
    self.nextButton.frame = CGRectMake(startX + prevW + gap + playW + gap, btnCenterY - playH / 2, nextW, playH);
    [self.nextButton addTarget:self action:@selector(nextButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [playBar addSubview:self.nextButton];

    [self bringControlButtonsToFront];
}

- (UIView *)buildTableHeadView {
    self.spectrumView = [[SpectrumView alloc] initWithFrame:CGRectMake(0, 0, self.view.frame.size.width, self.view.frame.size.height)];
    self.spectrumView.backgroundColor = [UIColor clearColor];
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    self.spectrumView.layoutStyle = (ADSpectrumLayoutStyle)[defaults integerForKey:kSpectrumLayoutStyleDefaultsKey];
    self.spectrumView.colorMode = (ADSpectrumColorMode)[defaults integerForKey:kSpectrumColorModeDefaultsKey];
    self.spectrumView.hueShift = [defaults objectForKey:kSpectrumHueDefaultsKey] ? [defaults floatForKey:kSpectrumHueDefaultsKey] : 0.0;
    self.spectrumView.colorBrightness = [defaults objectForKey:kSpectrumBrightnessDefaultsKey] ? [defaults floatForKey:kSpectrumBrightnessDefaultsKey] : 1.0;
    self.spectrumView.opacity = [defaults objectForKey:kSpectrumOpacityDefaultsKey] ? [defaults floatForKey:kSpectrumOpacityDefaultsKey] : 1.0;
    self.spectrumView.layoutOffset = CGPointMake([defaults floatForKey:kSpectrumPositionXDefaultsKey],
                                                 [defaults floatForKey:kSpectrumPositionYDefaultsKey]);
    {
        CGFloat scale = [defaults objectForKey:kSpectrumScaleDefaultsKey] ? [defaults floatForKey:kSpectrumScaleDefaultsKey] : 1.0;
        self.spectrumView.layoutScale = scale;
    }
    [self.visualEffectManager setOriginalSpectrumView:self.spectrumView];
    if ([defaults objectForKey:kSpectrumAutoColorDefaultsKey] && ![defaults boolForKey:kSpectrumAutoColorDefaultsKey]) {
        [self applyManualSpectrumPaletteIfNeeded];
    }
    [self refreshSpectrumStyleButtonState];
    return self.spectrumView;
}

#pragma mark - Effect Controls

- (void)effectSelectorButtonTapped:(UIButton *)sender {
    [self.visualEffectManager showEffectSelector];
}

- (void)spectrumStyleButtonTapped:(UIButton *)sender {
    [self.searchBar resignFirstResponder];
    [self showSpectrumStylePanel];
}

- (void)showSpectrumStylePanel {
    if (self.spectrumStylePanelView.superview) {
        [self dismissSpectrumStylePanel];
        return;
    }

    UIView *overlay = [[UIView alloc] initWithFrame:self.view.bounds];
    overlay.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.38];
    overlay.alpha = 0.0;

    UIButton *dismissButton = [UIButton buttonWithType:UIButtonTypeCustom];
    dismissButton.frame = overlay.bounds;
    [dismissButton addTarget:self action:@selector(dismissSpectrumStylePanel) forControlEvents:UIControlEventTouchUpInside];
    [overlay addSubview:dismissButton];

    CGFloat cardWidth = MIN(360.0, self.view.bounds.size.width - 36.0);
    CGFloat maxCardHeight = MIN(self.view.bounds.size.height - 72.0, 560.0);
    UIView *card = [[UIView alloc] initWithFrame:CGRectMake((self.view.bounds.size.width - cardWidth) * 0.5,
                                                            MAX(48.0, (self.view.bounds.size.height - maxCardHeight) * 0.5),
                                                            cardWidth,
                                                            maxCardHeight)];
    card.backgroundColor = [UIColor colorWithRed:0.08 green:0.10 blue:0.15 alpha:0.98];
    card.layer.cornerRadius = 18.0;
    card.layer.borderWidth = 1.0;
    card.layer.borderColor = [UIColor colorWithWhite:1.0 alpha:0.12].CGColor;
    [overlay addSubview:card];

    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(18, 16, cardWidth - 80, 28)];
    titleLabel.text = @"频谱样式";
    titleLabel.font = [UIFont boldSystemFontOfSize:20];
    titleLabel.textColor = [UIColor whiteColor];
    [card addSubview:titleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(cardWidth - 46, 14, 30, 30);
    [closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [closeButton setTitleColor:[UIColor colorWithWhite:1.0 alpha:0.92] forState:UIControlStateNormal];
    closeButton.backgroundColor = [UIColor colorWithWhite:1.0 alpha:0.08];
    closeButton.layer.cornerRadius = 15.0;
    [closeButton addTarget:self action:@selector(dismissSpectrumStylePanel) forControlEvents:UIControlEventTouchUpInside];
    [card addSubview:closeButton];

    UIScrollView *scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(0, 52.0, cardWidth, maxCardHeight - 52.0)];
    scrollView.showsVerticalScrollIndicator = YES;
    scrollView.alwaysBounceVertical = YES;
    [card addSubview:scrollView];
    self.spectrumStyleScrollView = scrollView;

    UIView *contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, cardWidth, 520.0)];
    [scrollView addSubview:contentView];

    CGFloat labelX = 18.0;
    CGFloat controlX = 18.0;
    CGFloat controlW = cardWidth - 36.0;
    CGFloat y = 12.0;

    UILabel *layoutLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    layoutLabel.text = @"形态";
    layoutLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    layoutLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:layoutLabel];
    y += 22.0;

    self.spectrumLayoutSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"圆环", @"竖柱", @"双向"]];
    self.spectrumLayoutSegmentedControl.frame = CGRectMake(controlX, y, controlW, 32);
    self.spectrumLayoutSegmentedControl.selectedSegmentIndex = self.spectrumView ? self.spectrumView.layoutStyle : 0;
    [self.spectrumLayoutSegmentedControl addTarget:self action:@selector(spectrumLayoutChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumLayoutSegmentedControl];
    y += 46.0;

    UILabel *colorLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    colorLabel.text = @"颜色";
    colorLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    colorLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:colorLabel];
    y += 22.0;

    self.spectrumColorModeSegmentedControl = [[UISegmentedControl alloc] initWithItems:@[@"彩虹", @"单色", @"双色", @"主题"]];
    self.spectrumColorModeSegmentedControl.frame = CGRectMake(controlX, y, controlW, 32);
    self.spectrumColorModeSegmentedControl.selectedSegmentIndex = self.spectrumView ? self.spectrumView.colorMode : 0;
    [self.spectrumColorModeSegmentedControl addTarget:self action:@selector(spectrumColorModeChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumColorModeSegmentedControl];
    y += 46.0;

    UILabel *autoLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y + 4, 200, 18)];
    autoLabel.text = @"自动适配 Live 背景";
    autoLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    autoLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:autoLabel];

    self.spectrumAutoColorSwitch = [[UISwitch alloc] initWithFrame:CGRectZero];
    self.spectrumAutoColorSwitch.onTintColor = [UIColor colorWithRed:0.28 green:0.76 blue:0.54 alpha:1.0];
    self.spectrumAutoColorSwitch.on = [[NSUserDefaults standardUserDefaults] objectForKey:kSpectrumAutoColorDefaultsKey] ? [[NSUserDefaults standardUserDefaults] boolForKey:kSpectrumAutoColorDefaultsKey] : YES;
    self.spectrumAutoColorSwitch.center = CGPointMake(cardWidth - 42.0, y + 14.0);
    [self.spectrumAutoColorSwitch addTarget:self action:@selector(spectrumAutoColorSwitchChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumAutoColorSwitch];
    y += 40.0;

    UILabel *hueLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    hueLabel.text = @"色相偏移";
    hueLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    hueLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:hueLabel];
    y += 20.0;

    self.spectrumHueSlider = [[UISlider alloc] initWithFrame:CGRectMake(controlX, y, controlW, 28)];
    self.spectrumHueSlider.minimumValue = 0.0;
    self.spectrumHueSlider.maximumValue = 1.0;
    self.spectrumHueSlider.value = self.spectrumView ? self.spectrumView.hueShift : 0.0;
    [self.spectrumHueSlider addTarget:self action:@selector(spectrumHueSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumHueSlider];
    y += 36.0;

    UILabel *brightnessLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    brightnessLabel.text = @"亮度";
    brightnessLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    brightnessLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:brightnessLabel];
    y += 20.0;

    self.spectrumBrightnessSlider = [[UISlider alloc] initWithFrame:CGRectMake(controlX, y, controlW, 28)];
    self.spectrumBrightnessSlider.minimumValue = 0.55;
    self.spectrumBrightnessSlider.maximumValue = 1.65;
    self.spectrumBrightnessSlider.value = self.spectrumView ? self.spectrumView.colorBrightness : 1.0;
    [self.spectrumBrightnessSlider addTarget:self action:@selector(spectrumBrightnessSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumBrightnessSlider];
    y += 36.0;

    UILabel *opacityLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    opacityLabel.text = @"透明度";
    opacityLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    opacityLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:opacityLabel];
    y += 20.0;

    self.spectrumOpacitySlider = [[UISlider alloc] initWithFrame:CGRectMake(controlX, y, controlW, 28)];
    self.spectrumOpacitySlider.minimumValue = 0.1;
    self.spectrumOpacitySlider.maximumValue = 1.0;
    self.spectrumOpacitySlider.value = self.spectrumView ? self.spectrumView.opacity : 1.0;
    self.spectrumOpacitySlider.minimumTrackTintColor = [UIColor colorWithRed:0.88 green:0.72 blue:0.96 alpha:1.0];
    [self.spectrumOpacitySlider addTarget:self action:@selector(spectrumOpacitySliderChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumOpacitySlider];
    y += 36.0;

    UILabel *positionLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    positionLabel.text = @"音柱位置";
    positionLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    positionLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:positionLabel];
    y += 22.0;

    self.spectrumPositionHintLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 16)];
    self.spectrumPositionHintLabel.font = [UIFont systemFontOfSize:11 weight:UIFontWeightMedium];
    self.spectrumPositionHintLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.56];
    [contentView addSubview:self.spectrumPositionHintLabel];
    y += 18.0;

    self.spectrumPositionXSlider = [[UISlider alloc] initWithFrame:CGRectMake(controlX, y, controlW, 24)];
    self.spectrumPositionXSlider.minimumValue = -0.32;
    self.spectrumPositionXSlider.maximumValue = 0.32;
    self.spectrumPositionXSlider.value = self.spectrumView ? self.spectrumView.layoutOffset.x : 0.0;
    [self.spectrumPositionXSlider addTarget:self action:@selector(spectrumPositionSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumPositionXSlider];
    y += 28.0;

    self.spectrumPositionYSlider = [[UISlider alloc] initWithFrame:CGRectMake(controlX, y, controlW, 24)];
    self.spectrumPositionYSlider.minimumValue = -0.28;
    self.spectrumPositionYSlider.maximumValue = 0.28;
    self.spectrumPositionYSlider.value = self.spectrumView ? self.spectrumView.layoutOffset.y : 0.0;
    [self.spectrumPositionYSlider addTarget:self action:@selector(spectrumPositionSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumPositionYSlider];
    y += 32.0;

    UILabel *scaleLabel = [[UILabel alloc] initWithFrame:CGRectMake(labelX, y, controlW, 18)];
    scaleLabel.text = @"频谱大小";
    scaleLabel.font = [UIFont systemFontOfSize:13 weight:UIFontWeightSemibold];
    scaleLabel.textColor = [UIColor colorWithWhite:1.0 alpha:0.82];
    [contentView addSubview:scaleLabel];
    y += 22.0;

    self.spectrumScaleSlider = [[UISlider alloc] initWithFrame:CGRectMake(controlX, y, controlW, 24)];
    self.spectrumScaleSlider.minimumValue = 0.5;
    self.spectrumScaleSlider.maximumValue = 1.8;
    self.spectrumScaleSlider.value = self.spectrumView ? self.spectrumView.layoutScale : 1.0;
    self.spectrumScaleSlider.minimumTrackTintColor = [UIColor colorWithRed:0.35 green:0.78 blue:0.95 alpha:1.0];
    [self.spectrumScaleSlider addTarget:self action:@selector(spectrumScaleSliderChanged:) forControlEvents:UIControlEventValueChanged];
    [contentView addSubview:self.spectrumScaleSlider];
    y += 38.0;

    contentView.frame = CGRectMake(0, 0, cardWidth, y + 18.0);
    scrollView.contentSize = CGSizeMake(cardWidth, CGRectGetMaxY(contentView.frame));

    self.spectrumStylePanelView = overlay;
    self.spectrumStyleCardView = card;
    [self.view addSubview:overlay];
    [self updateSpectrumLiveEditingAvailability];

    [UIView animateWithDuration:0.22 animations:^{
        overlay.alpha = 1.0;
    }];
}

- (void)dismissSpectrumStylePanel {
    if (!self.spectrumStylePanelView.superview) {
        return;
    }
    UIView *overlay = self.spectrumStylePanelView;
    [UIView animateWithDuration:0.18 animations:^{
        overlay.alpha = 0.0;
    } completion:^(BOOL finished) {
        [overlay removeFromSuperview];
        self.spectrumStylePanelView = nil;
        self.spectrumStyleCardView = nil;
        self.spectrumLayoutSegmentedControl = nil;
        self.spectrumColorModeSegmentedControl = nil;
        self.spectrumAutoColorSwitch = nil;
        self.spectrumStyleScrollView = nil;
        self.spectrumHueSlider = nil;
        self.spectrumBrightnessSlider = nil;
        self.spectrumOpacitySlider = nil;
        self.spectrumPositionXSlider = nil;
        self.spectrumPositionYSlider = nil;
        self.spectrumScaleSlider = nil;
        self.spectrumPositionHintLabel = nil;
    }];
}

- (void)spectrumScaleSliderChanged:(UISlider *)sender {
    if (!self.spectrumView) return;
    CGFloat v = MAX(0.5, MIN(sender.value, 1.8));
    self.spectrumView.layoutScale = v;
    [[NSUserDefaults standardUserDefaults] setFloat:(float)v forKey:kSpectrumScaleDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)spectrumOpacitySliderChanged:(UISlider *)sender {
    if (!self.spectrumView) return;
    CGFloat value = MAX(0.1, MIN(sender.value, 1.0));
    self.spectrumView.opacity = value;
    [[NSUserDefaults standardUserDefaults] setFloat:(float)value forKey:kSpectrumOpacityDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
}

- (void)spectrumLayoutChanged:(UISegmentedControl *)sender {
    self.spectrumView.layoutStyle = (ADSpectrumLayoutStyle)sender.selectedSegmentIndex;
    if (self.spectrumView.layoutStyle == ADSpectrumLayoutStyleRing) {
        [self.spectrumView resetLayoutOffset];
        self.spectrumPositionXSlider.value = 0.0;
        self.spectrumPositionYSlider.value = 0.0;
    }
    [self persistSpectrumSettings];
    [self refreshSpectrumStyleButtonState];
    [self updateSpectrumLiveEditingAvailability];
}

- (void)spectrumColorModeChanged:(UISegmentedControl *)sender {
    self.spectrumView.colorMode = (ADSpectrumColorMode)sender.selectedSegmentIndex;
    [self applyManualSpectrumPaletteIfNeeded];
    [self persistSpectrumSettings];
}

- (void)spectrumAutoColorSwitchChanged:(UISwitch *)sender {
    [[NSUserDefaults standardUserDefaults] setBool:sender.isOn forKey:kSpectrumAutoColorDefaultsKey];
    [[NSUserDefaults standardUserDefaults] synchronize];
    self.spectrumHueSlider.enabled = !sender.isOn;
    self.spectrumBrightnessSlider.enabled = YES;
    if (sender.isOn) {
        [self refreshSpectrumAdaptiveThemeIfNeeded];
    } else {
        [self applyManualSpectrumPaletteIfNeeded];
    }
}

- (void)spectrumHueSliderChanged:(UISlider *)sender {
    self.spectrumView.hueShift = sender.value;
    [self applyManualSpectrumPaletteIfNeeded];
    [self persistSpectrumSettings];
}

- (void)spectrumBrightnessSliderChanged:(UISlider *)sender {
    self.spectrumView.colorBrightness = sender.value;
    if (self.spectrumAutoColorSwitch.isOn) {
        [self refreshSpectrumAdaptiveThemeIfNeeded];
    } else {
        [self applyManualSpectrumPaletteIfNeeded];
    }
    [self persistSpectrumSettings];
}

- (void)spectrumPositionSliderChanged:(UISlider *)sender {
    if (!self.spectrumView) return;
    // Ring 样式不需要单独位置（圆环已居中），其它任何样式都允许调整，无需 live 模式
    if (self.spectrumView.layoutStyle == ADSpectrumLayoutStyleRing) {
        sender.value = 0.0;
        return;
    }
    self.spectrumView.layoutOffset = CGPointMake(self.spectrumPositionXSlider.value,
                                                 self.spectrumPositionYSlider.value);
    [self persistSpectrumSettings];
}

- (void)persistSpectrumSettings {
    if (!self.spectrumView) {
        return;
    }
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    [defaults setInteger:self.spectrumView.layoutStyle forKey:kSpectrumLayoutStyleDefaultsKey];
    [defaults setInteger:self.spectrumView.colorMode forKey:kSpectrumColorModeDefaultsKey];
    [defaults setFloat:self.spectrumView.hueShift forKey:kSpectrumHueDefaultsKey];
    [defaults setFloat:self.spectrumView.colorBrightness forKey:kSpectrumBrightnessDefaultsKey];
    [defaults setFloat:self.spectrumView.opacity forKey:kSpectrumOpacityDefaultsKey];
    [defaults setFloat:self.spectrumView.layoutOffset.x forKey:kSpectrumPositionXDefaultsKey];
    [defaults setFloat:self.spectrumView.layoutOffset.y forKey:kSpectrumPositionYDefaultsKey];
    [defaults synchronize];
}

- (void)applyManualSpectrumPaletteIfNeeded {
    if (!self.spectrumView || self.spectrumAutoColorSwitch.isOn) {
        return;
    }

    CGFloat hue = self.spectrumHueSlider ? self.spectrumHueSlider.value : self.spectrumView.hueShift;
    CGFloat brightness = self.spectrumBrightnessSlider ? self.spectrumBrightnessSlider.value : self.spectrumView.colorBrightness;
    self.spectrumView.hueShift = hue;
    self.spectrumView.colorBrightness = brightness;

    UIColor *primary = [UIColor colorWithHue:hue saturation:0.86 brightness:MIN(1.0, 0.92 * brightness) alpha:1.0];
    UIColor *secondary = [UIColor colorWithHue:fmod(hue + 0.18, 1.0) saturation:0.78 brightness:MIN(1.0, 0.98 * brightness) alpha:1.0];
    self.spectrumView.primaryColor = primary;
    self.spectrumView.secondaryColor = secondary;
}

- (void)refreshSpectrumStyleButtonState {
    if (!self.spectrumStyleButton || !self.spectrumView) {
        return;
    }

    UIColor *borderColor = [UIColor colorWithWhite:1.0 alpha:0.22];
    UIColor *fillColor = [UIColor colorWithRed:0.16 green:0.24 blue:0.42 alpha:0.88];
    if (self.spectrumView.layoutStyle == ADSpectrumLayoutStyleVerticalBars) {
        fillColor = [UIColor colorWithRed:0.18 green:0.40 blue:0.58 alpha:0.9];
        borderColor = [UIColor colorWithRed:0.45 green:0.82 blue:1.0 alpha:0.5];
    } else if (self.spectrumView.layoutStyle == ADSpectrumLayoutStyleMirroredVerticalBars) {
        fillColor = [UIColor colorWithRed:0.28 green:0.22 blue:0.56 alpha:0.9];
        borderColor = [UIColor colorWithRed:0.72 green:0.55 blue:1.0 alpha:0.5];
    }
    self.spectrumStyleButton.backgroundColor = fillColor;
    self.spectrumStyleButton.layer.borderColor = borderColor.CGColor;
}

- (void)updateSpectrumLiveEditingAvailability {
    BOOL nonRingLayout = self.spectrumView.layoutStyle != ADSpectrumLayoutStyleRing;
    self.spectrumPositionXSlider.enabled = nonRingLayout;
    self.spectrumPositionYSlider.enabled = nonRingLayout;
    if (!nonRingLayout) {
        self.spectrumPositionHintLabel.text = @"圆环样式不需要单独调整音柱位置";
    } else {
        self.spectrumPositionHintLabel.text = @"拖动滑块调整音柱位置和大小";
    }
    self.spectrumHueSlider.enabled = !(self.spectrumAutoColorSwitch && self.spectrumAutoColorSwitch.isOn);
}

- (void)refreshSpectrumAdaptiveThemeIfNeeded {
    BOOL autoEnabled = [[NSUserDefaults standardUserDefaults] objectForKey:kSpectrumAutoColorDefaultsKey] ? [[NSUserDefaults standardUserDefaults] boolForKey:kSpectrumAutoColorDefaultsKey] : YES;
    if (!autoEnabled || !self.spectrumView) {
        return;
    }

    UIColor *coverColor = self.coverImageView.image ? [self averageColorFromImage:self.coverImageView.image] : nil;
    UIColor *baseColor = self.backgroundMediaPreviewColor ?: coverColor;
    if (!baseColor) {
        baseColor = [UIColor colorWithRed:0.10 green:0.14 blue:0.22 alpha:1.0];
    }

    CGFloat hue = 0.0, saturation = 0.0, brightness = 0.0, alpha = 0.0;
    [baseColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];

    CGFloat accentHue = fmod(hue + 0.46, 1.0);
    CGFloat altHue = fmod(accentHue + 0.12, 1.0);
    CGFloat accentBrightness = brightness < 0.45 ? 0.98 : 0.72;
    CGFloat accentSaturation = MAX(0.52, MIN(0.95, 0.88 - saturation * 0.18));
    UIColor *primary = [UIColor colorWithHue:accentHue saturation:accentSaturation brightness:accentBrightness alpha:1.0];
    UIColor *secondary = [UIColor colorWithHue:altHue saturation:MIN(1.0, accentSaturation + 0.08) brightness:MIN(1.0, accentBrightness + 0.08) alpha:1.0];

    self.spectrumView.primaryColor = primary;
    self.spectrumView.secondaryColor = secondary;
    self.spectrumView.colorBrightness = self.spectrumBrightnessSlider ? self.spectrumBrightnessSlider.value : self.spectrumView.colorBrightness;
    self.spectrumView.hueShift = accentHue;

    if (self.spectrumHueSlider) {
        self.spectrumHueSlider.value = accentHue;
    }
}

- (UIColor *)averageColorFromImage:(UIImage *)image {
    if (!image.CGImage) {
        return [UIColor whiteColor];
    }

    CIImage *inputImage = [[CIImage alloc] initWithCGImage:image.CGImage];
    CIVector *extent = [CIVector vectorWithX:CGRectGetMidX(inputImage.extent)
                                           Y:CGRectGetMidY(inputImage.extent)
                                           Z:CGRectGetWidth(inputImage.extent)
                                           W:CGRectGetHeight(inputImage.extent)];
    CIFilter *filter = [CIFilter filterWithName:@"CIAreaAverage"];
    [filter setValue:inputImage forKey:kCIInputImageKey];
    [filter setValue:extent forKey:kCIInputExtentKey];

    CIContext *context = [CIContext contextWithOptions:@{kCIContextWorkingColorSpace: [NSNull null]}];
    unsigned char bitmap[4] = {0};
    CIImage *outputImage = filter.outputImage;
    if (!outputImage) {
        return [UIColor whiteColor];
    }

    [context render:outputImage
           toBitmap:bitmap
           rowBytes:4
             bounds:CGRectMake(0, 0, 1, 1)
             format:kCIFormatRGBA8
         colorSpace:nil];

    return [UIColor colorWithRed:bitmap[0] / 255.0
                           green:bitmap[1] / 255.0
                            blue:bitmap[2] / 255.0
                           alpha:1.0];
}

- (nullable UIColor *)dominantColorForBackgroundMediaItem:(BackgroundMediaItem *)item {
    if (!item.filePath.length || ![[NSFileManager defaultManager] fileExistsAtPath:item.filePath]) {
        return nil;
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:item.filePath] options:nil];
    AVAssetImageGenerator *generator = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    generator.appliesPreferredTrackTransform = YES;
    generator.maximumSize = CGSizeMake(240.0, 240.0);
    NSError *error = nil;
    CGImageRef imageRef = [generator copyCGImageAtTime:CMTimeMakeWithSeconds(0.15, 600) actualTime:nil error:&error];
    if (!imageRef) {
        NSLog(@"⚠️ 背景媒体取色失败: %@", error.localizedDescription ?: @"未知错误");
        return nil;
    }

    UIImage *image = [UIImage imageWithCGImage:imageRef];
    CGImageRelease(imageRef);
    return [self averageColorFromImage:image];
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
    [self updateBackgroundMediaEffectStateForEffect:effectType];
    [self refreshVisualLyricsOverlayVisibility];
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
        [self.aiModeButton setTitle:@"AI" forState:UIControlStateNormal];
        self.aiModeButton.backgroundColor = [UIColor colorWithRed:0.6 green:0.2 blue:0.8 alpha:0.9];
        self.aiModeButton.layer.borderColor = [UIColor colorWithRed:0.8 green:0.4 blue:1.0 alpha:1.0].CGColor;
    } else {
        [self.aiModeButton setTitle:@"AI" forState:UIControlStateNormal];
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
    // 小型 FPS 指示器放在左上角 toggle 按钮右侧
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat fpsTop = MAX(safeTop, 44.0) + 12;

    self.fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(54, fpsTop, 70, 26)];
    self.fpsLabel.backgroundColor = [UIColor colorWithWhite:0.0 alpha:0.55];
    self.fpsLabel.textColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:1.0];
    self.fpsLabel.font = [UIFont monospacedDigitSystemFontOfSize:11 weight:UIFontWeightMedium];
    self.fpsLabel.textAlignment = NSTextAlignmentCenter;
    self.fpsLabel.numberOfLines = 1;
    self.fpsLabel.layer.cornerRadius = 6;
    self.fpsLabel.layer.masksToBounds = YES;
    self.fpsLabel.layer.borderWidth = 0.5;
    self.fpsLabel.layer.borderColor = [UIColor colorWithRed:0.2 green:1.0 blue:0.4 alpha:0.4].CGColor;
    self.fpsLabel.text = @"-- FPS";
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
    if (displayFPS >= 55) {
        fpsColor = [UIColor colorWithRed:0.0 green:1.0 blue:0.3 alpha:1.0];
    } else if (displayFPS >= 25) {
        fpsColor = [UIColor colorWithRed:1.0 green:0.8 blue:0.0 alpha:1.0];
    } else if (displayFPS > 0) {
        fpsColor = [UIColor colorWithRed:1.0 green:0.2 blue:0.2 alpha:1.0];
    } else {
        fpsColor = [UIColor grayColor];
    }

    self.fpsLabel.textColor = fpsColor;
    self.fpsLabel.layer.borderColor = fpsColor.CGColor;

    self.fpsLabel.text = [NSString stringWithFormat:@"%.0f/%ld FPS",
                          displayFPS,
                          (long)targetFPS];
}

#pragma mark - Agent Panel

- (void)setupAgentStatusPanel {
    CGFloat safeTop = 0;
    if (@available(iOS 11.0, *)) {
        safeTop = self.view.safeAreaInsets.top;
    }
    CGFloat topOffset = MAX(safeTop, 44) + 10;

    // agentStatusButton 放在右侧竖排（混音控件 mixAudioControlView 下方）
    CGFloat btnSize = 44;
    CGFloat btnSpacing = 10;
    CGFloat rightX = self.view.bounds.size.width - btnSize - 12;
    CGFloat rightY = topOffset + (btnSize + btnSpacing) * 7;

    self.agentStatusButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *agentIcon = nil;
    if (@available(iOS 13.0, *)) {
        UIImageSymbolConfiguration *cfg = [UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightMedium];
        agentIcon = [UIImage systemImageNamed:@"brain.head.profile.fill" withConfiguration:cfg];
    }
    [self.agentStatusButton setImage:agentIcon forState:UIControlStateNormal];
    [self.agentStatusButton setTitle:@"" forState:UIControlStateNormal];
    self.agentStatusButton.tintColor = [UIColor whiteColor];
    self.agentStatusButton.backgroundColor = [UIColor colorWithRed:0.22 green:0.12 blue:0.38 alpha:0.85];
    self.agentStatusButton.layer.cornerRadius = btnSize / 2;
    self.agentStatusButton.layer.borderWidth = 1.0;
    self.agentStatusButton.layer.borderColor = [UIColor colorWithRed:0.6 green:0.4 blue:0.9 alpha:0.5].CGColor;
    self.agentStatusButton.frame = CGRectMake(rightX, rightY, btnSize, btnSize);
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
    titleLabel.text = @"Agent 状态面板";
    titleLabel.font = [UIFont boldSystemFontOfSize:18];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.agentStatusPanel addSubview:titleLabel];

    UIButton *closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    closeButton.frame = CGRectMake(panelWidth - 40, 10, 30, 30);
    UIImage *closeIcon = nil;
    if (@available(iOS 13.0, *)) {
        closeIcon = [UIImage systemImageNamed:@"xmark"];
    }
    [closeButton setImage:closeIcon forState:UIControlStateNormal];
    [closeButton setTitle:@"" forState:UIControlStateNormal];
    closeButton.tintColor = [UIColor whiteColor];
    closeButton.titleLabel.font = [UIFont systemFontOfSize:20];
    [closeButton addTarget:self action:@selector(closeAgentStatusPanel) forControlEvents:UIControlEventTouchUpInside];
    [self.agentStatusPanel addSubview:closeButton];

    UILabel *metricsTitle = [[UILabel alloc] initWithFrame:CGRectMake(20, 50, panelWidth - 40, 20)];
    metricsTitle.text = @"运行指标";
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
    recTitle.text = @"策略建议";
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
    costTitle.text = @"成本控制";
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
    [reflectButton setTitle:@"执行反思" forState:UIControlStateNormal];
    [reflectButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    reflectButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.8 alpha:1.0];
    reflectButton.layer.cornerRadius = 8;
    reflectButton.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [reflectButton addTarget:self action:@selector(performAgentReflection) forControlEvents:UIControlEventTouchUpInside];
    [self.agentStatusPanel addSubview:reflectButton];

    UIButton *reportButton = [UIButton buttonWithType:UIButtonTypeSystem];
    reportButton.frame = CGRectMake(panelWidth / 2 + 5, 345, (panelWidth - 50) / 2, 40);
    [reportButton setTitle:@"导出报告" forState:UIControlStateNormal];
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
                          exceeded ? @"已超预算（强制本地）" : @"正常"];
    self.agentCostLabel.text = costText;
    self.agentCostLabel.textColor = exceeded ? [UIColor redColor] : [UIColor greenColor];
}

- (void)performAgentReflection {
    NSLog(@"🔄 手动触发 Agent 反思...");
    [[EffectDecisionAgent sharedAgent] performReflectionAndUpdate];

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"反思完成"
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

    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Agent 分析报告"
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
