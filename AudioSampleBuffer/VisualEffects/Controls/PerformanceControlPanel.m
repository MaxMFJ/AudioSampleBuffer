//
//  PerformanceControlPanel.m
//  AudioSampleBuffer
//
//  性能配置控制面板实现
//

#import "PerformanceControlPanel.h"

@interface PerformanceControlPanel ()

@property (nonatomic, strong) UIVisualEffectView *backgroundView;
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;

// 帧率控制
@property (nonatomic, strong) UISegmentedControl *fpsControl;
@property (nonatomic, strong) UILabel *fpsLabel;
@property (nonatomic, strong) UILabel *fpsInfoLabel;

// 抗锯齿控制
@property (nonatomic, strong) UISegmentedControl *msaaControl;
@property (nonatomic, strong) UILabel *msaaLabel;
@property (nonatomic, strong) UILabel *msaaInfoLabel;

// 性能模式
@property (nonatomic, strong) UISegmentedControl *modeControl;
@property (nonatomic, strong) UILabel *modeLabel;
@property (nonatomic, strong) UILabel *modeInfoLabel;

// Shader复杂度
@property (nonatomic, strong) UISegmentedControl *shaderControl;
@property (nonatomic, strong) UILabel *shaderLabel;
@property (nonatomic, strong) UILabel *shaderInfoLabel;

// 按钮
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UIButton *applyButton;

// currentSettings 已在 .h 文件中公开声明，不需要在这里重复

@end

@implementation PerformanceControlPanel

// 显式合成属性，确保 _currentSettings 实例变量可用
@synthesize currentSettings = _currentSettings;

// 懒加载 currentSettings，避免初始化时机问题
- (NSMutableDictionary *)currentSettings {
    if (!_currentSettings) {
        _currentSettings = [[NSMutableDictionary alloc] initWithDictionary:@{
            @"fps": @(30),
            @"msaa": @(1),
            @"mode": @"balanced",
            @"shaderComplexity": @(1.0)
        }];
        NSLog(@"⚙️ 懒加载初始化性能设置: %@", _currentSettings);
    }
    return _currentSettings;
}

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
        // 不再显式调用 setupDefaultSettings，改用懒加载
        // 触发一次懒加载
        [self currentSettings];
    }
    return self;
}

- (void)setupDefaultSettings {
    // 重置为默认值，使用 getter 来确保字典已初始化
    NSMutableDictionary *settings = [self currentSettings];
    [settings removeAllObjects];
    [settings setObject:@(30) forKey:@"fps"];
    [settings setObject:@(1) forKey:@"msaa"];
    [settings setObject:@"balanced" forKey:@"mode"];
    [settings setObject:@(1.0) forKey:@"shaderComplexity"];
    
    NSLog(@"⚙️ 重置性能设置为默认值: %@", settings);
}

- (void)setupUI {
    self.backgroundColor = [UIColor clearColor];
    self.hidden = YES;
    
    // 背景模糊效果
    UIBlurEffect *blurEffect = [UIBlurEffect effectWithStyle:UIBlurEffectStyleDark];
    self.backgroundView = [[UIVisualEffectView alloc] initWithEffect:blurEffect];
    self.backgroundView.frame = self.bounds;
    self.backgroundView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self addSubview:self.backgroundView];
    
    // 滚动视图
    self.scrollView = [[UIScrollView alloc] initWithFrame:CGRectMake(20, 20, 
                                                                     self.bounds.size.width - 40, 
                                                                     self.bounds.size.height - 40)];
    self.scrollView.backgroundColor = [UIColor colorWithWhite:0.1 alpha:0.95];
    self.scrollView.layer.cornerRadius = 15;
    self.scrollView.layer.borderWidth = 2;
    self.scrollView.layer.borderColor = [UIColor colorWithRed:0.3 green:0.6 blue:1.0 alpha:1.0].CGColor;
    [self.backgroundView.contentView addSubview:self.scrollView];
    
    // 内容视图
    self.contentView = [[UIView alloc] initWithFrame:CGRectMake(0, 0, 
                                                                self.scrollView.bounds.size.width, 
                                                                800)];
    [self.scrollView addSubview:self.contentView];
    self.scrollView.contentSize = self.contentView.bounds.size;
    
    CGFloat yOffset = 20;
    
    // 标题
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, yOffset, 
                                                                    self.contentView.bounds.size.width - 40, 30)];
    titleLabel.text = @"⚙️ 性能配置";
    titleLabel.font = [UIFont boldSystemFontOfSize:24];
    titleLabel.textColor = [UIColor whiteColor];
    titleLabel.textAlignment = NSTextAlignmentCenter;
    [self.contentView addSubview:titleLabel];
    yOffset += 50;
    
    // 性能模式
    yOffset = [self addModeControlAtY:yOffset];
    yOffset += 30;
    
    // 帧率控制
    yOffset = [self addFPSControlAtY:yOffset];
    yOffset += 30;
    
    // 抗锯齿控制
    yOffset = [self addMSAAControlAtY:yOffset];
    yOffset += 30;
    
    // Shader复杂度
    yOffset = [self addShaderControlAtY:yOffset];
    yOffset += 40;
    
    // 性能说明
    [self addPerformanceInfoAtY:yOffset];
    yOffset += 180;
    
    // 按钮
    [self addButtonsAtY:yOffset];
    
    // 更新内容高度
    self.contentView.frame = CGRectMake(0, 0, self.scrollView.bounds.size.width, yOffset + 80);
    self.scrollView.contentSize = self.contentView.bounds.size;
}

- (CGFloat)addModeControlAtY:(CGFloat)y {
    // 标签
    self.modeLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                               self.contentView.bounds.size.width - 40, 25)];
    self.modeLabel.text = @"性能模式";
    self.modeLabel.font = [UIFont boldSystemFontOfSize:18];
    self.modeLabel.textColor = [UIColor whiteColor];
    [self.contentView addSubview:self.modeLabel];
    y += 30;
    
    // 分段控制
    self.modeControl = [[UISegmentedControl alloc] initWithItems:@[@"省电", @"平衡", @"性能"]];
    self.modeControl.frame = CGRectMake(20, y, self.contentView.bounds.size.width - 40, 35);
    self.modeControl.selectedSegmentIndex = 1; // 默认平衡
    [self.modeControl addTarget:self action:@selector(modeChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.modeControl];
    y += 40;
    
    // 说明
    self.modeInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                                   self.contentView.bounds.size.width - 40, 40)];
    self.modeInfoLabel.text = @"平衡：30fps + 关闭MSAA\n省电续航，视觉效果保持95%";
    self.modeInfoLabel.numberOfLines = 0;
    self.modeInfoLabel.font = [UIFont systemFontOfSize:13];
    self.modeInfoLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    [self.contentView addSubview:self.modeInfoLabel];
    
    return y + 45;
}

- (CGFloat)addFPSControlAtY:(CGFloat)y {
    // 标签
    self.fpsLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                              self.contentView.bounds.size.width - 40, 25)];
    self.fpsLabel.text = @"帧率 (FPS)";
    self.fpsLabel.font = [UIFont boldSystemFontOfSize:18];
    self.fpsLabel.textColor = [UIColor whiteColor];
    [self.contentView addSubview:self.fpsLabel];
    y += 30;
    
    // 分段控制
    self.fpsControl = [[UISegmentedControl alloc] initWithItems:@[@"20", @"30", @"60"]];
    self.fpsControl.frame = CGRectMake(20, y, self.contentView.bounds.size.width - 40, 35);
    self.fpsControl.selectedSegmentIndex = 1; // 默认30fps
    [self.fpsControl addTarget:self action:@selector(fpsChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.fpsControl];
    y += 40;
    
    // 说明
    self.fpsInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                                  self.contentView.bounds.size.width - 40, 40)];
    self.fpsInfoLabel.text = @"30fps：推荐设置，流畅省电\nGPU负载：中";
    self.fpsInfoLabel.numberOfLines = 0;
    self.fpsInfoLabel.font = [UIFont systemFontOfSize:13];
    self.fpsInfoLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    [self.contentView addSubview:self.fpsInfoLabel];
    
    return y + 45;
}

- (CGFloat)addMSAAControlAtY:(CGFloat)y {
    // 标签
    self.msaaLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                               self.contentView.bounds.size.width - 40, 25)];
    self.msaaLabel.text = @"抗锯齿 (MSAA)";
    self.msaaLabel.font = [UIFont boldSystemFontOfSize:18];
    self.msaaLabel.textColor = [UIColor whiteColor];
    [self.contentView addSubview:self.msaaLabel];
    y += 30;
    
    // 分段控制
    self.msaaControl = [[UISegmentedControl alloc] initWithItems:@[@"关闭", @"2x", @"4x"]];
    self.msaaControl.frame = CGRectMake(20, y, self.contentView.bounds.size.width - 40, 35);
    self.msaaControl.selectedSegmentIndex = 0; // 默认关闭
    [self.msaaControl addTarget:self action:@selector(msaaChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.msaaControl];
    y += 40;
    
    // 说明
    self.msaaInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                                   self.contentView.bounds.size.width - 40, 40)];
    self.msaaInfoLabel.text = @"关闭：推荐设置，高分屏差异小\nGPU开销：无";
    self.msaaInfoLabel.numberOfLines = 0;
    self.msaaInfoLabel.font = [UIFont systemFontOfSize:13];
    self.msaaInfoLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    [self.contentView addSubview:self.msaaInfoLabel];
    
    return y + 45;
}

- (CGFloat)addShaderControlAtY:(CGFloat)y {
    // 标签
    self.shaderLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                                 self.contentView.bounds.size.width - 40, 25)];
    self.shaderLabel.text = @"特效复杂度";
    self.shaderLabel.font = [UIFont boldSystemFontOfSize:18];
    self.shaderLabel.textColor = [UIColor whiteColor];
    [self.contentView addSubview:self.shaderLabel];
    y += 30;
    
    // 分段控制
    self.shaderControl = [[UISegmentedControl alloc] initWithItems:@[@"简化", @"标准", @"完整"]];
    self.shaderControl.frame = CGRectMake(20, y, self.contentView.bounds.size.width - 40, 35);
    self.shaderControl.selectedSegmentIndex = 1; // 默认标准（已优化）
    [self.shaderControl addTarget:self action:@selector(shaderChanged:) forControlEvents:UIControlEventValueChanged];
    [self.contentView addSubview:self.shaderControl];
    y += 40;
    
    // 说明
    self.shaderInfoLabel = [[UILabel alloc] initWithFrame:CGRectMake(20, y, 
                                                                     self.contentView.bounds.size.width - 40, 40)];
    self.shaderInfoLabel.text = @"标准：当前优化版本，效果好\nGPU计算：中等";
    self.shaderInfoLabel.numberOfLines = 0;
    self.shaderInfoLabel.font = [UIFont systemFontOfSize:13];
    self.shaderInfoLabel.textColor = [UIColor colorWithWhite:0.7 alpha:1.0];
    [self.contentView addSubview:self.shaderInfoLabel];
    
    return y + 45;
}

- (void)addPerformanceInfoAtY:(CGFloat)y {
    UIView *infoBox = [[UIView alloc] initWithFrame:CGRectMake(20, y, 
                                                               self.contentView.bounds.size.width - 40, 140)];
    infoBox.backgroundColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.4 alpha:0.5];
    infoBox.layer.cornerRadius = 10;
    infoBox.layer.borderWidth = 1;
    infoBox.layer.borderColor = [UIColor colorWithRed:0.3 green:0.5 blue:0.7 alpha:0.8].CGColor;
    [self.contentView addSubview:infoBox];
    
    UILabel *infoTitle = [[UILabel alloc] initWithFrame:CGRectMake(15, 10, infoBox.bounds.size.width - 30, 25)];
    infoTitle.text = @"💡 推荐设置";
    infoTitle.font = [UIFont boldSystemFontOfSize:16];
    infoTitle.textColor = [UIColor colorWithRed:0.5 green:0.8 blue:1.0 alpha:1.0];
    [infoBox addSubview:infoTitle];
    
    UILabel *infoText = [[UILabel alloc] initWithFrame:CGRectMake(15, 35, infoBox.bounds.size.width - 30, 95)];
    infoText.text = @"• 日常使用：平衡模式（30fps）\n• 长时间播放：省电模式（20fps）\n• 演示展示：性能模式（60fps，需充电）\n• 抗锯齿：关闭（高分屏差异小）\n• 特效：标准（已优化，效果好）";
    infoText.numberOfLines = 0;
    infoText.font = [UIFont systemFontOfSize:13];
    infoText.textColor = [UIColor colorWithWhite:0.9 alpha:1.0];
    [infoBox addSubview:infoText];
}

- (void)addButtonsAtY:(CGFloat)y {
    // 关闭按钮
    self.closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.closeButton.frame = CGRectMake(20, y, 80, 40);
    [self.closeButton setTitle:@"关闭" forState:UIControlStateNormal];
    [self.closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.closeButton.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.8];
    self.closeButton.layer.cornerRadius = 10;
    [self.closeButton addTarget:self action:@selector(closeButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.closeButton];
    
    // 重置按钮
    self.resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.resetButton.frame = CGRectMake((self.contentView.bounds.size.width - 100) / 2, y, 100, 40);
    [self.resetButton setTitle:@"恢复默认" forState:UIControlStateNormal];
    [self.resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.resetButton.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.2 alpha:0.8];
    self.resetButton.layer.cornerRadius = 10;
    [self.resetButton addTarget:self action:@selector(resetButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.resetButton];
    
    // 应用按钮
    self.applyButton = [UIButton buttonWithType:UIButtonTypeSystem];
    self.applyButton.frame = CGRectMake(self.contentView.bounds.size.width - 100, y, 80, 40);
    [self.applyButton setTitle:@"应用" forState:UIControlStateNormal];
    [self.applyButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    self.applyButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.6 blue:0.9 alpha:0.9];
    self.applyButton.layer.cornerRadius = 10;
    [self.applyButton addTarget:self action:@selector(applyButtonTapped) forControlEvents:UIControlEventTouchUpInside];
    [self.contentView addSubview:self.applyButton];
}

#pragma mark - 控制变化

- (void)modeChanged:(UISegmentedControl *)sender {
    NSString *mode;
    NSInteger fps, msaa;
    float complexity;
    
    switch (sender.selectedSegmentIndex) {
        case 0: // 省电
            mode = @"power_saving";
            fps = 20;
            msaa = 1;
            complexity = 0.6;
            self.fpsControl.selectedSegmentIndex = 0;
            self.msaaControl.selectedSegmentIndex = 0;
            self.shaderControl.selectedSegmentIndex = 0;
            self.modeInfoLabel.text = @"省电：20fps + 关闭MSAA + 简化特效\n最低功耗，续航优先";
            break;
        case 1: // 平衡
            mode = @"balanced";
            fps = 30;
            msaa = 1;
            complexity = 1.0;
            self.fpsControl.selectedSegmentIndex = 1;
            self.msaaControl.selectedSegmentIndex = 0;
            self.shaderControl.selectedSegmentIndex = 1;
            self.modeInfoLabel.text = @"平衡：30fps + 关闭MSAA + 标准特效\n省电续航，视觉效果保持95%";
            break;
        case 2: // 性能
            mode = @"performance";
            fps = 60;
            msaa = 4;
            complexity = 1.5;
            self.fpsControl.selectedSegmentIndex = 2;
            self.msaaControl.selectedSegmentIndex = 2;
            self.shaderControl.selectedSegmentIndex = 2;
            self.modeInfoLabel.text = @"性能：60fps + 4x MSAA + 完整特效\n最佳效果，建议充电时使用";
            break;
        default:
            mode = @"balanced";
            fps = 30;
            msaa = 1;
            complexity = 1.0;
    }
    
    // 使用 getter 确保字典已初始化
    NSMutableDictionary *settings = [self currentSettings];
    [settings setObject:mode forKey:@"mode"];
    [settings setObject:@(fps) forKey:@"fps"];
    [settings setObject:@(msaa) forKey:@"msaa"];
    [settings setObject:@(complexity) forKey:@"shaderComplexity"];
    
    NSLog(@"🔄 模式切换: %@ (fps=%ld, msaa=%ld, shader=%.1f)", mode, (long)fps, (long)msaa, complexity);
    
    [self updateInfoLabels];
}

- (void)fpsChanged:(UISegmentedControl *)sender {
    NSInteger fps;
    switch (sender.selectedSegmentIndex) {
        case 0: fps = 20; break;
        case 1: fps = 30; break;
        case 2: fps = 60; break;
        default: fps = 30;
    }
    
    [[self currentSettings] setObject:@(fps) forKey:@"fps"];
    [self updateFPSInfo:fps];
}

- (void)msaaChanged:(UISegmentedControl *)sender {
    NSInteger msaa;
    switch (sender.selectedSegmentIndex) {
        case 0: msaa = 1; break;
        case 1: msaa = 2; break;
        case 2: msaa = 4; break;
        default: msaa = 1;
    }
    
    [[self currentSettings] setObject:@(msaa) forKey:@"msaa"];
    [self updateMSAAInfo:msaa];
}

- (void)shaderChanged:(UISegmentedControl *)sender {
    float complexity;
    switch (sender.selectedSegmentIndex) {
        case 0: complexity = 0.6; break;  // 简化
        case 1: complexity = 1.0; break;  // 标准（当前优化版本）
        case 2: complexity = 1.5; break;  // 完整（优化前版本）
        default: complexity = 1.0;
    }
    
    [[self currentSettings] setObject:@(complexity) forKey:@"shaderComplexity"];
    [self updateShaderInfo:complexity];
}

#pragma mark - 更新信息标签

- (void)updateInfoLabels {
    NSInteger fps = [self.currentSettings[@"fps"] integerValue];
    NSInteger msaa = [self.currentSettings[@"msaa"] integerValue];
    float complexity = [self.currentSettings[@"shaderComplexity"] floatValue];
    
    [self updateFPSInfo:fps];
    [self updateMSAAInfo:msaa];
    [self updateShaderInfo:complexity];
}

- (void)updateFPSInfo:(NSInteger)fps {
    NSString *load = fps == 20 ? @"低" : (fps == 30 ? @"中" : @"高");
    NSString *desc = fps == 20 ? @"最省电" : (fps == 30 ? @"流畅省电" : @"最流畅");
    self.fpsInfoLabel.text = [NSString stringWithFormat:@"%ldfps：%@\nGPU负载：%@", (long)fps, desc, load];
}

- (void)updateMSAAInfo:(NSInteger)msaa {
    NSString *load = msaa == 1 ? @"无" : (msaa == 2 ? @"中" : @"高");
    NSString *desc = msaa == 1 ? @"推荐设置，高分屏差异小" : (msaa == 2 ? @"轻微平滑" : @"最平滑");
    NSString *text = msaa == 1 ? @"关闭" : [NSString stringWithFormat:@"%ldx", (long)msaa];
    self.msaaInfoLabel.text = [NSString stringWithFormat:@"%@：%@\nGPU开销：%@", text, desc, load];
}

- (void)updateShaderInfo:(float)complexity {
    NSString *load = complexity < 0.8 ? @"低" : (complexity <= 1.0 ? @"中等" : @"高");
    NSString *desc = complexity < 0.8 ? @"简化版，基础效果" : (complexity <= 1.0 ? @"当前优化版本，效果好" : @"完整版，最佳效果");
    NSString *text = complexity < 0.8 ? @"简化" : (complexity <= 1.0 ? @"标准" : @"完整");
    self.shaderInfoLabel.text = [NSString stringWithFormat:@"%@：%@\nGPU计算：%@", text, desc, load];
}

#pragma mark - 按钮事件

- (void)closeButtonTapped {
    [self hideAnimated:YES];
}

- (void)resetButtonTapped {
    [self setupDefaultSettings];
    self.modeControl.selectedSegmentIndex = 1;
    self.fpsControl.selectedSegmentIndex = 1;
    self.msaaControl.selectedSegmentIndex = 0;
    self.shaderControl.selectedSegmentIndex = 1;
    [self updateInfoLabels];
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"已重置" 
                                                                   message:@"已恢复为推荐的默认设置\n点击\"应用\"生效" 
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
    [[self findViewController] presentViewController:alert animated:YES completion:nil];
}

- (void)applyButtonTapped {
    // 确保currentSettings不为空
    if (!self.currentSettings || [self.currentSettings count] == 0) {
        NSLog(@"❌ currentSettings为空，重新初始化");
        [self setupDefaultSettings];
    }
    
    NSInteger fps = [self.currentSettings[@"fps"] integerValue];
    NSInteger msaa = [self.currentSettings[@"msaa"] integerValue];
    float shader = [self.currentSettings[@"shaderComplexity"] floatValue];
    NSString *mode = self.currentSettings[@"mode"];
    
    NSLog(@"🎯 准备应用设置: fps=%ld, msaa=%ld, shader=%.1f, mode=%@", 
          (long)fps, (long)msaa, shader, mode);
    
    // 调用代理方法
    if ([self.delegate respondsToSelector:@selector(performanceControlDidUpdateSettings:)]) {
        // 创建一个新的字典副本传递，避免引用问题
        NSDictionary *settingsCopy = [self.currentSettings copy];
        NSLog(@"📤 传递设置字典: %@", settingsCopy);
        [self.delegate performanceControlDidUpdateSettings:settingsCopy];
    }
    
    // 显示确认对话框
    NSString *modeText = [mode isEqualToString:@"power_saving"] ? @"省电" : 
                         ([mode isEqualToString:@"balanced"] ? @"平衡" : @"性能");
    
    UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"✅ 设置已应用" 
                                                                   message:[NSString stringWithFormat:@"模式: %@\n帧率: %ldfps\n抗锯齿: %ldx\nShader: %.1f\n\n帧率和Shader已立即生效\nMSAA需要切换特效后生效", modeText, (long)fps, (long)msaa, shader]
                                                            preferredStyle:UIAlertControllerStyleAlert];
    [alert addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:^(UIAlertAction * _Nonnull action) {
        [self hideAnimated:YES];
    }]];
    [[self findViewController] presentViewController:alert animated:YES completion:nil];
}

#pragma mark - 显示/隐藏

- (void)showAnimated:(BOOL)animated {
    self.hidden = NO;
    self.alpha = 0;
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 1.0;
        }];
    } else {
        self.alpha = 1.0;
    }
}

- (void)hideAnimated:(BOOL)animated {
    if (animated) {
        [UIView animateWithDuration:0.3 animations:^{
            self.alpha = 0;
        } completion:^(BOOL finished) {
            self.hidden = YES;
        }];
    } else {
        self.hidden = YES;
    }
}

- (void)setCurrentSettings:(NSDictionary *)settings {
    // 使用 getter 确保字典已初始化
    NSMutableDictionary *current = [self currentSettings];
    
    // 清空并重新设置所有值
    [current removeAllObjects];
    if (settings && [settings count] > 0) {
        [current addEntriesFromDictionary:settings];
    }
    
    NSLog(@"🔧 setCurrentSettings被调用: %@", current);
    
    // 更新UI
    NSInteger fps = [settings[@"fps"] integerValue];
    if (fps == 20) self.fpsControl.selectedSegmentIndex = 0;
    else if (fps == 30) self.fpsControl.selectedSegmentIndex = 1;
    else if (fps == 60) self.fpsControl.selectedSegmentIndex = 2;
    
    NSInteger msaa = [settings[@"msaa"] integerValue];
    if (msaa == 1) self.msaaControl.selectedSegmentIndex = 0;
    else if (msaa == 2) self.msaaControl.selectedSegmentIndex = 1;
    else if (msaa == 4) self.msaaControl.selectedSegmentIndex = 2;
    
    [self updateInfoLabels];
}

- (UIViewController *)findViewController {
    UIResponder *responder = self;
    while (responder) {
        if ([responder isKindOfClass:[UIViewController class]]) {
            return (UIViewController *)responder;
        }
        responder = [responder nextResponder];
    }
    return nil;
}

@end

