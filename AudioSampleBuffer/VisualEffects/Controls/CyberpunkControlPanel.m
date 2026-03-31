//
//  CyberpunkControlPanel.m
//  AudioSampleBuffer
//
//  赛博朋克效果专用控制面板实现
//

#import "CyberpunkControlPanel.h"

@interface CyberpunkControlPanel ()
@property (nonatomic, strong) UIScrollView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;

// 开关控件
@property (nonatomic, strong) UISwitch *climaxEffectSwitch;
@property (nonatomic, strong) UISwitch *bassEffectSwitch;
@property (nonatomic, strong) UISwitch *midEffectSwitch;
@property (nonatomic, strong) UISwitch *trebleEffectSwitch;
@property (nonatomic, strong) UISwitch *debugBarsSwitch;
@property (nonatomic, strong) UISwitch *gridSwitch;

// 背景模式选择器
@property (nonatomic, strong) UISegmentedControl *backgroundModeControl;

@end

@implementation CyberpunkControlPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];
    self.layer.cornerRadius = 20;
    self.clipsToBounds = YES;
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"⚡ 赛博朋克控制";
    _titleLabel.font = [UIFont boldSystemFontOfSize:20];
    _titleLabel.textColor = [UIColor whiteColor];
    _titleLabel.textAlignment = NSTextAlignmentCenter;
    [self addSubview:_titleLabel];
    
    // 关闭按钮
    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_closeButton setTitle:@"✕" forState:UIControlStateNormal];
    [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont systemFontOfSize:18];
    [_closeButton addTarget:self action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_closeButton];
    
    // 内容视图（使用UIScrollView以支持滚动）
    _contentView = [[UIScrollView alloc] init];
    _contentView.showsVerticalScrollIndicator = YES;
    _contentView.alwaysBounceVertical = YES;
    [self addSubview:_contentView];
    
    // 创建开关控件
    [self createSwitchControls];
}

- (void)createSwitchControls {
    CGFloat yOffset = 0;
    CGFloat padding = 20;
    
    // 🟨 黄色高能效果开关
    _climaxEffectSwitch = [self createSwitchRowWithTitle:@"🟨 高能效果（黄色）"
                                                      tag:0
                                                  yOffset:yOffset];
    yOffset += 50;
    
    // 分隔线
    [self addSeparatorAtY:yOffset];
    yOffset += 1;
    
    // 频段特效标题
    UILabel *sectionLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.bounds.size.width - 2 * padding, 30)];
    sectionLabel.text = @"频段特效开关";
    sectionLabel.font = [UIFont boldSystemFontOfSize:14];
    sectionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    sectionLabel.textAlignment = NSTextAlignmentCenter;
    [_contentView addSubview:sectionLabel];
    yOffset += 30;
    
    // 🔴 红色低音效果开关
    _bassEffectSwitch = [self createSwitchRowWithTitle:@"🔴 低音效果（红色）"
                                                    tag:1
                                                yOffset:yOffset];
    yOffset += 50;
    
    // 🟢 绿色中音效果开关
    _midEffectSwitch = [self createSwitchRowWithTitle:@"🟢 中音效果（绿色）"
                                                   tag:2
                                               yOffset:yOffset];
    yOffset += 50;
    
    // 🔵 蓝色高音效果开关
    _trebleEffectSwitch = [self createSwitchRowWithTitle:@"🔵 高音效果（蓝色）"
                                                      tag:3
                                                  yOffset:yOffset];
    yOffset += 50;
    
    // 分隔线
    [self addSeparatorAtY:yOffset];
    yOffset += 1;
    
    // 📊 调试条显示开关
    _debugBarsSwitch = [self createSwitchRowWithTitle:@"📊 显示调试强度条"
                                                   tag:4
                                               yOffset:yOffset];
    yOffset += 50;
    
    // 分隔线
    [self addSeparatorAtY:yOffset];
    yOffset += 1;
    
    // 背景效果标题
    UILabel *backgroundSectionLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.bounds.size.width - 2 * padding, 30)];
    backgroundSectionLabel.text = @"背景效果控制";
    backgroundSectionLabel.font = [UIFont boldSystemFontOfSize:14];
    backgroundSectionLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    backgroundSectionLabel.textAlignment = NSTextAlignmentCenter;
    [_contentView addSubview:backgroundSectionLabel];
    yOffset += 30;
    
    // 🔲 网格背景开关
    _gridSwitch = [self createSwitchRowWithTitle:@"🔲 显示网格背景"
                                             tag:5
                                         yOffset:yOffset];
    yOffset += 50;
    
    // 背景模式选择器标签
    UILabel *bgModeLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset + 10, 120, 30)];
    bgModeLabel.text = @"🎨 背景模式";
    bgModeLabel.font = [UIFont systemFontOfSize:16];
    bgModeLabel.textColor = [UIColor whiteColor];
    [_contentView addSubview:bgModeLabel];
    
    // 背景模式分段控制器
    _backgroundModeControl = [[UISegmentedControl alloc] initWithItems:@[@"网格", @"纯色", @"粒子", @"渐变", @"无"]];
    _backgroundModeControl.frame = CGRectMake(padding + 130, yOffset + 5, self.bounds.size.width - 180, 40);
    _backgroundModeControl.selectedSegmentIndex = 0;
    _backgroundModeControl.backgroundColor = [UIColor colorWithWhite:0.2 alpha:1.0];
    
    // iOS 13+ 支持selectedSegmentTintColor
    if (@available(iOS 13.0, *)) {
        _backgroundModeControl.selectedSegmentTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    } else {
        _backgroundModeControl.tintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    }
    
    [_backgroundModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor whiteColor]} 
                                          forState:UIControlStateNormal];
    [_backgroundModeControl setTitleTextAttributes:@{NSForegroundColorAttributeName: [UIColor blackColor]} 
                                          forState:UIControlStateSelected];
    [_backgroundModeControl addTarget:self action:@selector(backgroundModeChanged:) forControlEvents:UIControlEventValueChanged];
    [_contentView addSubview:_backgroundModeControl];
    
    // 设置所有开关默认开启
    _climaxEffectSwitch.on = YES;
    _bassEffectSwitch.on = YES;
    _midEffectSwitch.on = YES;
    _trebleEffectSwitch.on = YES;
    _debugBarsSwitch.on = YES;
    _gridSwitch.on = YES; // 网格默认开启
}

- (UISwitch *)createSwitchRowWithTitle:(NSString *)title
                                   tag:(NSInteger)tag
                               yOffset:(CGFloat)yOffset {
    CGFloat padding = 20;
    
    // 标题标签
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset + 10, 200, 30)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:16];
    label.textColor = [UIColor whiteColor];
    [_contentView addSubview:label];
    
    // 开关
    UISwitch *switchControl = [[UISwitch alloc] init];
    switchControl.frame = CGRectMake(self.bounds.size.width - 70, yOffset + 10, 51, 31);
    switchControl.onTintColor = [UIColor colorWithRed:0.0 green:0.8 blue:1.0 alpha:1.0];
    switchControl.tag = tag;
    [switchControl addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
    [_contentView addSubview:switchControl];
    
    return switchControl;
}

- (void)addSeparatorAtY:(CGFloat)y {
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.bounds.size.width - 40, 1)];
    separator.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [_contentView addSubview:separator];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    // 标题
    _titleLabel.frame = CGRectMake(0, 15, self.bounds.size.width, 30);
    
    // 关闭按钮
    _closeButton.frame = CGRectMake(self.bounds.size.width - 50, 15, 30, 30);
    
    // 内容视图（ScrollView）
    _contentView.frame = CGRectMake(0, 60, self.bounds.size.width, self.bounds.size.height - 60);
    
    // 设置ScrollView的contentSize
    // 计算所有控件的总高度：
    // 1个高能效果开关(50) + 分隔线(1) + 标题(30)
    // 3个频段开关(50×3) + 分隔线(1) + 调试条(50)
    // 分隔线(1) + 背景标题(30) + 网格开关(50) + 背景模式(50) + 底部间距(20)
    CGFloat contentHeight = 50 + 1 + 30 + 150 + 1 + 50 + 1 + 30 + 50 + 50 + 20;
    _contentView.contentSize = CGSizeMake(self.bounds.size.width, contentHeight);
}

- (void)switchValueChanged:(UISwitch *)sender {
    [self updateSettings];
}

- (void)backgroundModeChanged:(UISegmentedControl *)sender {
    [self updateSettings];
}

- (void)updateSettings {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    
    // 特效开关
    settings[@"enableClimaxEffect"] = @(_climaxEffectSwitch.on ? 1.0 : 0.0);
    settings[@"enableBassEffect"] = @(_bassEffectSwitch.on ? 1.0 : 0.0);
    settings[@"enableMidEffect"] = @(_midEffectSwitch.on ? 1.0 : 0.0);
    settings[@"enableTrebleEffect"] = @(_trebleEffectSwitch.on ? 1.0 : 0.0);
    settings[@"showDebugBars"] = @(_debugBarsSwitch.on ? 1.0 : 0.0);
    
    // 网格和背景控制
    settings[@"enableGrid"] = @(_gridSwitch.on ? 1.0 : 0.0);
    settings[@"backgroundMode"] = @((float)_backgroundModeControl.selectedSegmentIndex);
    
    // 背景参数（为纯色模式设置默认颜色）
    settings[@"solidColorR"] = @(0.15);  // 默认深蓝紫色
    settings[@"solidColorG"] = @(0.1);
    settings[@"solidColorB"] = @(0.25);
    settings[@"backgroundIntensity"] = @(0.8);
    
    NSLog(@"🎛️ 控制面板发送设置: grid=%@, bgMode=%@, 完整设置=%@", 
          settings[@"enableGrid"], settings[@"backgroundMode"], settings);
    
    if ([self.delegate respondsToSelector:@selector(cyberpunkControlDidUpdateSettings:)]) {
        [self.delegate cyberpunkControlDidUpdateSettings:settings];
    } else {
        NSLog(@"⚠️ delegate未设置或不响应cyberpunkControlDidUpdateSettings方法！");
    }
}

- (void)closeButtonTapped:(id)sender {
    [self hideAnimated:YES];
}

- (void)showAnimated:(BOOL)animated {
    self.hidden = NO;
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    
    [UIView animateWithDuration:animated ? 0.3 : 0.0
                          delay:0
         usingSpringWithDamping:0.7
          initialSpringVelocity:0.5
                        options:UIViewAnimationOptionCurveEaseOut
                     animations:^{
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    } completion:^(BOOL finished) {
        // 面板显示完成后，立即应用一次当前设置，确保shader接收到参数
        [self updateSettings];
        NSLog(@"⚡ 赛博朋克控制面板显示完成，已应用初始设置");
    }];
}

- (void)hideAnimated:(BOOL)animated {
    [UIView animateWithDuration:animated ? 0.25 : 0.0
                     animations:^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.9, 0.9);
    } completion:^(BOOL finished) {
        self.hidden = YES;
        self.transform = CGAffineTransformIdentity;
    }];
}

- (void)setCurrentSettings:(NSDictionary *)settings {
    if (settings[@"enableClimaxEffect"]) {
        _climaxEffectSwitch.on = [settings[@"enableClimaxEffect"] floatValue] > 0.5;
    }
    if (settings[@"enableBassEffect"]) {
        _bassEffectSwitch.on = [settings[@"enableBassEffect"] floatValue] > 0.5;
    }
    if (settings[@"enableMidEffect"]) {
        _midEffectSwitch.on = [settings[@"enableMidEffect"] floatValue] > 0.5;
    }
    if (settings[@"enableTrebleEffect"]) {
        _trebleEffectSwitch.on = [settings[@"enableTrebleEffect"] floatValue] > 0.5;
    }
    if (settings[@"showDebugBars"]) {
        _debugBarsSwitch.on = [settings[@"showDebugBars"] floatValue] > 0.5;
    }
    if (settings[@"enableGrid"]) {
        _gridSwitch.on = [settings[@"enableGrid"] floatValue] > 0.5;
    }
    if (settings[@"backgroundMode"]) {
        NSInteger mode = (NSInteger)[settings[@"backgroundMode"] floatValue];
        if (mode >= 0 && mode < 5) {
            _backgroundModeControl.selectedSegmentIndex = mode;
        }
    }
}

@end

