//
//  GalaxyControlPanel.m
//  AudioSampleBuffer
//
//  星系效果专用控制面板实现
//

#import "GalaxyControlPanel.h"

@interface GalaxyControlPanel ()
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSMutableArray<GalaxySlider *> *sliders;
@property (nonatomic, strong) UIButton *resetButton;
@property (nonatomic, strong) UIButton *randomButton;
@property (nonatomic, strong) UIView *themeContainer;
@property (nonatomic, strong) UILabel *themeLabel;
@property (nonatomic, assign) NSInteger selectedTheme;
@end

@implementation GalaxyControlPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
        [self createSliders];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];
    self.layer.cornerRadius = 20;
    self.clipsToBounds = YES;
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"🌌 星系效果控制";
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
    
    // 滚动视图
    _scrollView = [[UIScrollView alloc] init];
    _scrollView.showsVerticalScrollIndicator = YES;
    _scrollView.bounces = YES;
    [self addSubview:_scrollView];
    
    // 内容视图
    _contentView = [[UIView alloc] init];
    [_scrollView addSubview:_contentView];
    
    // 重置按钮
    _resetButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_resetButton setTitle:@"🔄 重置默认" forState:UIControlStateNormal];
    [_resetButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _resetButton.backgroundColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.5 alpha:0.8];
    _resetButton.layer.cornerRadius = 20;
    [_resetButton addTarget:self action:@selector(resetButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_resetButton];
    
    // 随机按钮
    _randomButton = [UIButton buttonWithType:UIButtonTypeSystem];
    [_randomButton setTitle:@"🎲 随机效果" forState:UIControlStateNormal];
    [_randomButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _randomButton.backgroundColor = [UIColor colorWithRed:0.5 green:0.3 blue:0.5 alpha:0.8];
    _randomButton.layer.cornerRadius = 20;
    [_randomButton addTarget:self action:@selector(randomButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [_contentView addSubview:_randomButton];
    
    _sliders = [NSMutableArray array];
}

- (void)createSliders {
    NSArray *sliderConfigs = @[
        @{@"title": @"🌟 核心亮度", @"key": @"coreIntensity", @"min": @(0.5), @"max": @(5.0), @"default": @(2.0)},
        @{@"title": @"✨ 边缘亮度", @"key": @"edgeIntensity", @"min": @(0.1), @"max": @(3.0), @"default": @(1.0)},
        @{@"title": @"🔄 旋转速度", @"key": @"rotationSpeed", @"min": @(0.1), @"max": @(2.0), @"default": @(0.5)},
        @{@"title": @"💫 光晕半径", @"key": @"glowRadius", @"min": @(0.1), @"max": @(0.8), @"default": @(0.3)},
        @{@"title": @"🎨 颜色变化", @"key": @"colorShiftSpeed", @"min": @(0.0), @"max": @(3.0), @"default": @(1.0)},
        @{@"title": @"☁️ 星云强度", @"key": @"nebulaIntensity", @"min": @(0.0), @"max": @(1.0), @"default": @(0.3)},
        @{@"title": @"💓 脉冲强度", @"key": @"pulseStrength", @"min": @(0.0), @"max": @(0.5), @"default": @(0.1)},
        @{@"title": @"🎵 音频敏感度", @"key": @"audioSensitivity", @"min": @(0.5), @"max": @(3.0), @"default": @(1.5)},
        @{@"title": @"⭐ 星星密度", @"key": @"starDensity", @"min": @(0.1), @"max": @(2.0), @"default": @(0.7)},
        @{@"title": @"🌀 螺旋臂数量", @"key": @"spiralArms", @"min": @(1.0), @"max": @(6.0), @"default": @(2.0)}
    ];
    
    for (NSDictionary *config in sliderConfigs) {
        GalaxySlider *slider = [[GalaxySlider alloc] initWithTitle:config[@"title"]
                                                      minimumValue:[config[@"min"] floatValue]
                                                      maximumValue:[config[@"max"] floatValue]
                                                      currentValue:[config[@"default"] floatValue]];
        
        __weak typeof(self) weakSelf = self;
        slider.valueChangedBlock = ^(float value) {
            [weakSelf sliderValueChanged:config[@"key"] value:value];
        };
        
        [_sliders addObject:slider];
        [_contentView addSubview:slider];
    }
    
    // 创建颜色主题选择器
    [self createColorThemeSelector];
}

- (void)createColorThemeSelector {
    // 颜色主题标题
    UILabel *themeLabel = [[UILabel alloc] init];
    themeLabel.text = @"🎨 星云颜色主题";
    themeLabel.textColor = [UIColor whiteColor];
    themeLabel.font = [UIFont boldSystemFontOfSize:16];
    themeLabel.textAlignment = NSTextAlignmentCenter;
    [_contentView addSubview:themeLabel];
    
    // 颜色主题按钮
    NSArray *themes = @[
        @{@"title": @"🌈 彩虹", @"tag": @(0)},
        @{@"title": @"🔥 火焰", @"tag": @(1)},
        @{@"title": @"❄️ 冰霜", @"tag": @(2)},
        @{@"title": @"🌸 樱花", @"tag": @(3)},
        @{@"title": @"🌿 翠绿", @"tag": @(4)},
        @{@"title": @"🌅 日落", @"tag": @(5)},
        @{@"title": @"🌌 深空", @"tag": @(6)},
        @{@"title": @"✨ 梦幻", @"tag": @(7)}
    ];
    
    // 创建主题按钮容器
    UIView *themeContainer = [[UIView alloc] init];
    [_contentView addSubview:themeContainer];
    
    CGFloat buttonWidth = 80;
    CGFloat buttonHeight = 35;
    CGFloat spacing = 10;
    NSInteger buttonsPerRow = 2;
    
    for (NSInteger i = 0; i < themes.count; i++) {
        NSDictionary *theme = themes[i];
        UIButton *themeButton = [UIButton buttonWithType:UIButtonTypeSystem];
        
        [themeButton setTitle:theme[@"title"] forState:UIControlStateNormal];
        [themeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
        themeButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.6 alpha:0.7];
        themeButton.layer.cornerRadius = 15;
        themeButton.layer.borderWidth = 1;
        themeButton.layer.borderColor = [UIColor colorWithRed:0.4 green:0.5 blue:0.8 alpha:0.8].CGColor;
        themeButton.titleLabel.font = [UIFont systemFontOfSize:12];
        themeButton.tag = [theme[@"tag"] integerValue];
        
        [themeButton addTarget:self action:@selector(colorThemeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        
        NSInteger row = i / buttonsPerRow;
        NSInteger col = i % buttonsPerRow;
        
        CGFloat x = col * (buttonWidth + spacing);
        CGFloat y = row * (buttonHeight + spacing);
        
        themeButton.frame = CGRectMake(x, y, buttonWidth, buttonHeight);
        [themeContainer addSubview:themeButton];
    }
    
    // 保存主题容器引用
    _themeContainer = themeContainer;
    _themeLabel = themeLabel;
    
    // 计算主题容器大小
    NSInteger rows = (themes.count + buttonsPerRow - 1) / buttonsPerRow;
    CGFloat containerHeight = rows * (buttonHeight + spacing) - spacing;
    themeContainer.frame = CGRectMake(0, 0, buttonsPerRow * (buttonWidth + spacing) - spacing, containerHeight);
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    CGFloat padding = 20;
    
    // 标题和关闭按钮
    _titleLabel.frame = CGRectMake(padding, padding, bounds.size.width - 2 * padding, 30);
    _closeButton.frame = CGRectMake(bounds.size.width - 50, padding, 30, 30);
    
    // 滚动视图
    _scrollView.frame = CGRectMake(0, 70, bounds.size.width, bounds.size.height - 70);
    
    // 内容视图布局
    CGFloat contentHeight = [self layoutContentView];
    _contentView.frame = CGRectMake(0, 0, bounds.size.width, contentHeight);
    _scrollView.contentSize = CGSizeMake(bounds.size.width, contentHeight);
}

- (CGFloat)layoutContentView {
    CGFloat padding = 20;
    CGFloat sliderHeight = 80;
    CGFloat buttonHeight = 40;
    CGFloat spacing = 15;
    CGFloat y = padding;
    
    // 滑块布局
    for (GalaxySlider *slider in _sliders) {
        slider.frame = CGRectMake(padding, y, self.bounds.size.width - 2 * padding, sliderHeight);
        y += sliderHeight + spacing;
    }
    
    // 颜色主题选择器布局
    if (_themeLabel && _themeContainer) {
        _themeLabel.frame = CGRectMake(padding, y, self.bounds.size.width - 2 * padding, 30);
        y += 40;
        
        CGFloat containerWidth = _themeContainer.frame.size.width;
        CGFloat containerX = (self.bounds.size.width - containerWidth) / 2;
        _themeContainer.frame = CGRectMake(containerX, y, containerWidth, _themeContainer.frame.size.height);
        y += _themeContainer.frame.size.height + spacing;
    }
    
    // 按钮布局
    CGFloat buttonWidth = (self.bounds.size.width - 3 * padding) / 2;
    _resetButton.frame = CGRectMake(padding, y, buttonWidth, buttonHeight);
    _randomButton.frame = CGRectMake(padding * 2 + buttonWidth, y, buttonWidth, buttonHeight);
    y += buttonHeight + padding;
    
    return y;
}

#pragma mark - Actions

- (void)closeButtonTapped:(UIButton *)sender {
    [self hideAnimated:YES];
}

- (void)resetButtonTapped:(UIButton *)sender {
    // 重置所有滑块到默认值
    for (GalaxySlider *slider in _sliders) {
        if ([slider.title containsString:@"核心亮度"]) slider.value = 2.0;
        else if ([slider.title containsString:@"边缘亮度"]) slider.value = 1.0;
        else if ([slider.title containsString:@"旋转速度"]) slider.value = 0.5;
        else if ([slider.title containsString:@"光晕半径"]) slider.value = 0.3;
        else if ([slider.title containsString:@"颜色变化"]) slider.value = 1.0;
        else if ([slider.title containsString:@"星云强度"]) slider.value = 0.3;
        else if ([slider.title containsString:@"脉冲强度"]) slider.value = 0.1;
        else if ([slider.title containsString:@"音频敏感度"]) slider.value = 1.5;
        else if ([slider.title containsString:@"星星密度"]) slider.value = 0.7;
        else if ([slider.title containsString:@"螺旋臂数量"]) slider.value = 2.0;
    }
    
    [self notifySettingsChanged];
}

- (void)randomButtonTapped:(UIButton *)sender {
    // 随机化所有参数
    for (GalaxySlider *slider in _sliders) {
        float randomValue = slider.minimumValue + 
                           (slider.maximumValue - slider.minimumValue) * ((float)arc4random() / UINT32_MAX);
        slider.value = randomValue;
    }
    
    // 随机选择颜色主题
    _selectedTheme = arc4random() % 8;
    [self updateThemeButtons];
    
    [self notifySettingsChanged];
}

- (void)colorThemeButtonTapped:(UIButton *)sender {
    _selectedTheme = sender.tag;
    [self updateThemeButtons];
    
    // 通知代理颜色主题变化
    [self notifySettingsChanged];
}

- (void)updateThemeButtons {
    // 更新主题按钮的选中状态
    for (UIView *subview in _themeContainer.subviews) {
        if ([subview isKindOfClass:[UIButton class]]) {
            UIButton *button = (UIButton *)subview;
            if (button.tag == _selectedTheme) {
                button.backgroundColor = [UIColor colorWithRed:0.4 green:0.6 blue:0.9 alpha:0.9];
                button.layer.borderColor = [UIColor colorWithRed:0.6 green:0.8 blue:1.0 alpha:1.0].CGColor;
                button.layer.borderWidth = 2;
            } else {
                button.backgroundColor = [UIColor colorWithRed:0.2 green:0.3 blue:0.6 alpha:0.7];
                button.layer.borderColor = [UIColor colorWithRed:0.4 green:0.5 blue:0.8 alpha:0.8].CGColor;
                button.layer.borderWidth = 1;
            }
        }
    }
}

- (void)sliderValueChanged:(NSString *)key value:(float)value {
    [self notifySettingsChanged];
}

- (void)notifySettingsChanged {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    
    for (GalaxySlider *slider in _sliders) {
        NSString *key = [self keyForSliderTitle:slider.title];
        if (key) {
            settings[key] = @(slider.value);
        }
    }
    
    // 添加颜色主题信息
    settings[@"colorTheme"] = @(_selectedTheme);
    
    if ([_delegate respondsToSelector:@selector(galaxyControlDidUpdateSettings:)]) {
        [_delegate galaxyControlDidUpdateSettings:settings];
    }
}

- (NSString *)keyForSliderTitle:(NSString *)title {
    if ([title containsString:@"核心亮度"]) return @"coreIntensity";
    if ([title containsString:@"边缘亮度"]) return @"edgeIntensity";
    if ([title containsString:@"旋转速度"]) return @"rotationSpeed";
    if ([title containsString:@"光晕半径"]) return @"glowRadius";
    if ([title containsString:@"颜色变化"]) return @"colorShiftSpeed";
    if ([title containsString:@"星云强度"]) return @"nebulaIntensity";
    if ([title containsString:@"脉冲强度"]) return @"pulseStrength";
    if ([title containsString:@"音频敏感度"]) return @"audioSensitivity";
    if ([title containsString:@"星星密度"]) return @"starDensity";
    if ([title containsString:@"螺旋臂数量"]) return @"spiralArms";
    return nil;
}

- (void)reloadColorThemes {
    // 重新加载颜色主题选择器
    [self updateThemeButtons];
}

#pragma mark - Public Methods

- (void)showAnimated:(BOOL)animated {
    self.alpha = 0;
    self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    
    void (^showBlock)(void) = ^{
        self.alpha = 1.0;
        self.transform = CGAffineTransformIdentity;
    };
    
    if (animated) {
        [UIView animateWithDuration:0.5 
                              delay:0 
             usingSpringWithDamping:0.8 
              initialSpringVelocity:0.5 
                            options:UIViewAnimationOptionCurveEaseOut 
                         animations:showBlock 
                         completion:nil];
    } else {
        showBlock();
    }
}

- (void)hideAnimated:(BOOL)animated {
    void (^hideBlock)(void) = ^{
        self.alpha = 0;
        self.transform = CGAffineTransformMakeScale(0.8, 0.8);
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:hideBlock completion:^(BOOL finished) {
            [self removeFromSuperview];
        }];
    } else {
        hideBlock();
        [self removeFromSuperview];
    }
}

- (void)setCurrentSettings:(NSDictionary *)settings {
    for (GalaxySlider *slider in _sliders) {
        NSString *key = [self keyForSliderTitle:slider.title];
        if (key && settings[key]) {
            slider.value = [settings[key] floatValue];
        }
    }
}

@end

#pragma mark - GalaxySlider Implementation

@interface GalaxySlider ()
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UILabel *valueLabel;
@property (nonatomic, strong) UISlider *slider;
@property (nonatomic, strong) UIView *backgroundView;
@end

@implementation GalaxySlider

- (instancetype)initWithTitle:(NSString *)title
                 minimumValue:(float)min
                 maximumValue:(float)max
                 currentValue:(float)current {
    if (self = [super init]) {
        _title = title;
        _minimumValue = min;
        _maximumValue = max;
        _value = current;
        [self setupSlider];
    }
    return self;
}

- (void)setupSlider {
    // 背景
    _backgroundView = [[UIView alloc] init];
    _backgroundView.backgroundColor = [UIColor colorWithRed:0.15 green:0.15 blue:0.25 alpha:0.8];
    _backgroundView.layer.cornerRadius = 12;
    [self addSubview:_backgroundView];
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = _title;
    _titleLabel.font = [UIFont boldSystemFontOfSize:16];
    _titleLabel.textColor = [UIColor whiteColor];
    [self addSubview:_titleLabel];
    
    // 数值标签
    _valueLabel = [[UILabel alloc] init];
    _valueLabel.font = [UIFont systemFontOfSize:14];
    _valueLabel.textColor = [UIColor colorWithRed:0.8 green:0.9 blue:1.0 alpha:1.0];
    _valueLabel.textAlignment = NSTextAlignmentRight;
    [self updateValueLabel];
    [self addSubview:_valueLabel];
    
    // 滑块
    _slider = [[UISlider alloc] init];
    _slider.minimumValue = _minimumValue;
    _slider.maximumValue = _maximumValue;
    _slider.value = _value;
    _slider.tintColor = [UIColor colorWithRed:0.3 green:0.7 blue:1.0 alpha:1.0];
    [_slider addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [self addSubview:_slider];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    CGFloat padding = 12;
    
    _backgroundView.frame = bounds;
    
    _titleLabel.frame = CGRectMake(padding, padding, bounds.size.width * 0.6, 20);
    _valueLabel.frame = CGRectMake(bounds.size.width * 0.6, padding, bounds.size.width * 0.4 - padding, 20);
    _slider.frame = CGRectMake(padding, padding + 30, bounds.size.width - 2 * padding, 30);
}

- (void)sliderValueChanged:(UISlider *)slider {
    _value = slider.value;
    [self updateValueLabel];
    
    if (_valueChangedBlock) {
        _valueChangedBlock(_value);
    }
}

- (void)updateValueLabel {
    _valueLabel.text = [NSString stringWithFormat:@"%.2f", _value];
}

- (void)setValue:(float)value {
    _value = value;
    _slider.value = value;
    [self updateValueLabel];
}

@end
