//
//  HolographicControlPanel.m
//  AudioSampleBuffer
//
//  全息效果专用控制面板实现
//

#import "HolographicControlPanel.h"

@interface HolographicControlPanel ()
@property (nonatomic, strong) UIView *contentView;
@property (nonatomic, strong) UILabel *titleLabel;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) UIScrollView *scrollView;

// 开关控件
@property (nonatomic, strong) UISwitch *rotationSwitch;
@property (nonatomic, strong) UISwitch *expansionSwitch;
@property (nonatomic, strong) UISwitch *bassResponseSwitch;
@property (nonatomic, strong) UISwitch *midResponseSwitch;
@property (nonatomic, strong) UISwitch *trebleResponseSwitch;
@property (nonatomic, strong) UISwitch *musicIntensitySwitch;

// 滑块控件
@property (nonatomic, strong) UISlider *rotationSpeedSlider;
@property (nonatomic, strong) UISlider *expansionAmountSlider;
@property (nonatomic, strong) UISlider *particleDensitySlider;

// 标签
@property (nonatomic, strong) UILabel *rotationSpeedLabel;
@property (nonatomic, strong) UILabel *expansionAmountLabel;
@property (nonatomic, strong) UILabel *particleDensityLabel;

@end

@implementation HolographicControlPanel

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        [self setupUI];
    }
    return self;
}

- (void)setupUI {
    self.backgroundColor = [UIColor colorWithRed:0.05 green:0.08 blue:0.15 alpha:0.95];
    self.layer.cornerRadius = 20;
    self.clipsToBounds = YES;
    
    // 标题
    _titleLabel = [[UILabel alloc] init];
    _titleLabel.text = @"🌀 全息效果控制";
    _titleLabel.font = [UIFont boldSystemFontOfSize:20];
    _titleLabel.textColor = [UIColor colorWithRed:0.7 green:0.9 blue:1.0 alpha:1.0];
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
    _scrollView.alwaysBounceVertical = YES;
    [self addSubview:_scrollView];
    
    // 内容视图
    _contentView = [[UIView alloc] init];
    [_scrollView addSubview:_contentView];
    
    // 创建控件
    [self createControls];
}

- (void)createControls {
    CGFloat yOffset = 0;
    CGFloat padding = 20;
    
    // ===== 🌀 整体转动和扩散 =====
    UILabel *sectionLabel1 = [self createSectionLabelWithTitle:@"🌀 整体转动和扩散" yOffset:yOffset];
    yOffset += 40;
    
    // 🔄 转动开关
    _rotationSwitch = [self createSwitchRowWithTitle:@"🔄 音乐驱动转动"
                                                  tag:0
                                              yOffset:yOffset];
    yOffset += 50;
    
    // 转动速度滑块
    yOffset = [self createSliderRowWithTitle:@"转动速度"
                                      slider:&_rotationSpeedSlider
                                       label:&_rotationSpeedLabel
                                     minValue:0.0
                                     maxValue:2.0
                                 defaultValue:1.0
                                          tag:100
                                      yOffset:yOffset];
    yOffset += 10;
    
    // 💥 扩散开关
    _expansionSwitch = [self createSwitchRowWithTitle:@"💥 低音扩散效果"
                                                   tag:1
                                               yOffset:yOffset];
    yOffset += 50;
    
    // 扩散幅度滑块
    yOffset = [self createSliderRowWithTitle:@"扩散幅度"
                                      slider:&_expansionAmountSlider
                                       label:&_expansionAmountLabel
                                     minValue:0.0
                                     maxValue:2.0
                                 defaultValue:1.0
                                          tag:101
                                      yOffset:yOffset];
    yOffset += 20;
    
    // 分隔线
    [self addSeparatorAtY:yOffset];
    yOffset += 1;
    
    // ===== 🎵 音乐响应开关 =====
    UILabel *sectionLabel2 = [self createSectionLabelWithTitle:@"🎵 音乐响应开关" yOffset:yOffset];
    yOffset += 40;
    
    // 🔥 高潮检测开关
    _musicIntensitySwitch = [self createSwitchRowWithTitle:@"🔥 高潮检测（多维度）"
                                                        tag:2
                                                    yOffset:yOffset];
    yOffset += 50;
    
    // 🔴 低音响应开关
    _bassResponseSwitch = [self createSwitchRowWithTitle:@"🔴 低音响应增强"
                                                      tag:3
                                                  yOffset:yOffset];
    yOffset += 50;
    
    // 🟢 中音响应开关
    _midResponseSwitch = [self createSwitchRowWithTitle:@"🟢 中音响应增强"
                                                     tag:4
                                                 yOffset:yOffset];
    yOffset += 50;
    
    // 🔵 高音响应开关
    _trebleResponseSwitch = [self createSwitchRowWithTitle:@"🔵 高音响应增强"
                                                        tag:5
                                                    yOffset:yOffset];
    yOffset += 50;
    
    // 分隔线
    [self addSeparatorAtY:yOffset];
    yOffset += 1;
    
    // ===== ⭐ 视觉效果 =====
    UILabel *sectionLabel3 = [self createSectionLabelWithTitle:@"⭐ 视觉效果调整" yOffset:yOffset];
    yOffset += 40;
    
    // 粒子密度滑块
    yOffset = [self createSliderRowWithTitle:@"粒子密度"
                                      slider:&_particleDensitySlider
                                       label:&_particleDensityLabel
                                     minValue:0.0
                                     maxValue:2.0
                                 defaultValue:1.0
                                          tag:102
                                      yOffset:yOffset];
    
    // 设置所有开关默认开启
    _rotationSwitch.on = YES;
    _expansionSwitch.on = YES;
    _bassResponseSwitch.on = YES;
    _midResponseSwitch.on = YES;
    _trebleResponseSwitch.on = YES;
    _musicIntensitySwitch.on = YES;
    
    // 设置内容视图高度
    _contentView.frame = CGRectMake(0, 0, self.bounds.size.width, yOffset + 20);
}

- (UILabel *)createSectionLabelWithTitle:(NSString *)title yOffset:(CGFloat)yOffset {
    CGFloat padding = 20;
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, self.bounds.size.width - 2 * padding, 30)];
    label.text = title;
    label.font = [UIFont boldSystemFontOfSize:16];
    label.textColor = [UIColor colorWithRed:0.5 green:0.8 blue:1.0 alpha:1.0];
    label.textAlignment = NSTextAlignmentLeft;
    [_contentView addSubview:label];
    return label;
}

- (UISwitch *)createSwitchRowWithTitle:(NSString *)title
                                   tag:(NSInteger)tag
                               yOffset:(CGFloat)yOffset {
    CGFloat padding = 20;
    
    // 标题标签
    UILabel *label = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset + 10, self.bounds.size.width - 100, 30)];
    label.text = title;
    label.font = [UIFont systemFontOfSize:15];
    label.textColor = [UIColor whiteColor];
    [_contentView addSubview:label];
    
    // 开关
    UISwitch *switchControl = [[UISwitch alloc] init];
    switchControl.frame = CGRectMake(self.bounds.size.width - 70, yOffset + 10, 51, 31);
    switchControl.onTintColor = [UIColor colorWithRed:0.3 green:0.75 blue:0.95 alpha:1.0];
    switchControl.tag = tag;
    [switchControl addTarget:self action:@selector(switchValueChanged:) forControlEvents:UIControlEventValueChanged];
    [_contentView addSubview:switchControl];
    
    return switchControl;
}

- (CGFloat)createSliderRowWithTitle:(NSString *)title
                             slider:(UISlider **)slider
                              label:(UILabel **)label
                           minValue:(float)minValue
                           maxValue:(float)maxValue
                       defaultValue:(float)defaultValue
                                tag:(NSInteger)tag
                            yOffset:(CGFloat)yOffset {
    CGFloat padding = 20;
    
    // 标题标签
    UILabel *titleLabel = [[UILabel alloc] initWithFrame:CGRectMake(padding, yOffset, 150, 20)];
    titleLabel.text = title;
    titleLabel.font = [UIFont systemFontOfSize:13];
    titleLabel.textColor = [UIColor colorWithWhite:0.8 alpha:1.0];
    [_contentView addSubview:titleLabel];
    
    // 数值标签
    UILabel *valueLabel = [[UILabel alloc] initWithFrame:CGRectMake(self.bounds.size.width - 80, yOffset, 60, 20)];
    valueLabel.text = [NSString stringWithFormat:@"%.1f", defaultValue];
    valueLabel.font = [UIFont systemFontOfSize:13];
    valueLabel.textColor = [UIColor colorWithRed:0.7 green:0.9 blue:1.0 alpha:1.0];
    valueLabel.textAlignment = NSTextAlignmentRight;
    valueLabel.tag = tag + 1000; // 用于后续查找
    [_contentView addSubview:valueLabel];
    *label = valueLabel;
    
    // 滑块
    UISlider *sliderControl = [[UISlider alloc] initWithFrame:CGRectMake(padding, yOffset + 25, self.bounds.size.width - 2 * padding, 30)];
    sliderControl.minimumValue = minValue;
    sliderControl.maximumValue = maxValue;
    sliderControl.value = defaultValue;
    sliderControl.minimumTrackTintColor = [UIColor colorWithRed:0.3 green:0.75 blue:0.95 alpha:1.0];
    sliderControl.tag = tag;
    [sliderControl addTarget:self action:@selector(sliderValueChanged:) forControlEvents:UIControlEventValueChanged];
    [_contentView addSubview:sliderControl];
    *slider = sliderControl;
    
    return yOffset + 60;
}

- (void)addSeparatorAtY:(CGFloat)y {
    UIView *separator = [[UIView alloc] initWithFrame:CGRectMake(20, y, self.bounds.size.width - 40, 1)];
    separator.backgroundColor = [UIColor colorWithWhite:0.3 alpha:0.5];
    [_contentView addSubview:separator];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat padding = 20;
    
    // 标题
    _titleLabel.frame = CGRectMake(0, 15, self.bounds.size.width, 30);
    
    // 关闭按钮
    _closeButton.frame = CGRectMake(self.bounds.size.width - 50, 15, 30, 30);
    
    // 滚动视图
    _scrollView.frame = CGRectMake(0, 60, self.bounds.size.width, self.bounds.size.height - 60);
    _scrollView.contentSize = CGSizeMake(self.bounds.size.width, _contentView.frame.size.height);
}

- (void)switchValueChanged:(UISwitch *)sender {
    [self notifyDelegate];
}

- (void)sliderValueChanged:(UISlider *)sender {
    // 更新对应的数值标签
    UILabel *valueLabel = [_contentView viewWithTag:sender.tag + 1000];
    if (valueLabel) {
        valueLabel.text = [NSString stringWithFormat:@"%.1f", sender.value];
    }
    [self notifyDelegate];
}

- (void)notifyDelegate {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    
    // 开关状态
    settings[@"enableRotation"] = @(_rotationSwitch.on ? 1.0 : 0.0);
    settings[@"enableExpansion"] = @(_expansionSwitch.on ? 1.0 : 0.0);
    settings[@"enableMusicIntensity"] = @(_musicIntensitySwitch.on ? 1.0 : 0.0);
    settings[@"enableBassResponse"] = @(_bassResponseSwitch.on ? 1.0 : 0.0);
    settings[@"enableMidResponse"] = @(_midResponseSwitch.on ? 1.0 : 0.0);
    settings[@"enableTrebleResponse"] = @(_trebleResponseSwitch.on ? 1.0 : 0.0);
    
    // 滑块数值
    settings[@"rotationSpeed"] = @(_rotationSpeedSlider.value);
    settings[@"expansionAmount"] = @(_expansionAmountSlider.value);
    settings[@"particleDensity"] = @(_particleDensitySlider.value);
    
    if ([self.delegate respondsToSelector:@selector(holographicControlDidUpdateSettings:)]) {
        [self.delegate holographicControlDidUpdateSettings:settings];
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
    } completion:nil];
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
    if (settings[@"enableRotation"]) {
        _rotationSwitch.on = [settings[@"enableRotation"] floatValue] > 0.5;
    }
    if (settings[@"enableExpansion"]) {
        _expansionSwitch.on = [settings[@"enableExpansion"] floatValue] > 0.5;
    }
    if (settings[@"enableMusicIntensity"]) {
        _musicIntensitySwitch.on = [settings[@"enableMusicIntensity"] floatValue] > 0.5;
    }
    if (settings[@"enableBassResponse"]) {
        _bassResponseSwitch.on = [settings[@"enableBassResponse"] floatValue] > 0.5;
    }
    if (settings[@"enableMidResponse"]) {
        _midResponseSwitch.on = [settings[@"enableMidResponse"] floatValue] > 0.5;
    }
    if (settings[@"enableTrebleResponse"]) {
        _trebleResponseSwitch.on = [settings[@"enableTrebleResponse"] floatValue] > 0.5;
    }
    
    if (settings[@"rotationSpeed"]) {
        _rotationSpeedSlider.value = [settings[@"rotationSpeed"] floatValue];
        _rotationSpeedLabel.text = [NSString stringWithFormat:@"%.1f", _rotationSpeedSlider.value];
    }
    if (settings[@"expansionAmount"]) {
        _expansionAmountSlider.value = [settings[@"expansionAmount"] floatValue];
        _expansionAmountLabel.text = [NSString stringWithFormat:@"%.1f", _expansionAmountSlider.value];
    }
    if (settings[@"particleDensity"]) {
        _particleDensitySlider.value = [settings[@"particleDensity"] floatValue];
        _particleDensityLabel.text = [NSString stringWithFormat:@"%.1f", _particleDensitySlider.value];
    }
}

@end

