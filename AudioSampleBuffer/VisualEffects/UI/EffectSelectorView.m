//
//  EffectSelectorView.m
//  AudioSampleBuffer
//
//  特效选择界面实现
//

#import "EffectSelectorView.h"

#pragma mark - EffectCardView

@interface EffectCardView ()
@property (nonatomic, strong) UIImageView *previewImageView;
@property (nonatomic, strong) UILabel *nameLabel;
@property (nonatomic, strong) UILabel *descriptionLabel;
@property (nonatomic, strong) UIView *categoryBadge;
@property (nonatomic, strong) UILabel *categoryLabel;
@property (nonatomic, strong) UIView *performanceIndicator;
@property (nonatomic, strong) UIView *selectionOverlay;
@property (nonatomic, strong) CAGradientLayer *backgroundGradient;
@property (nonatomic, strong) CAShapeLayer *borderLayer;
@property (nonatomic, strong) UIButton *configButton;  // 🎨 特效配置按钮
@end

@implementation EffectCardView

- (instancetype)initWithEffectInfo:(VisualEffectInfo *)effectInfo {
    if (self = [super init]) {
        _effectInfo = effectInfo;
        _effectType = effectInfo.type;
        [self setupViews];
        [self updateContent];
    }
    return self;
}

- (void)setupViews {
    self.layer.cornerRadius = 16;
    self.clipsToBounds = YES;
    
    // 背景渐变
    _backgroundGradient = [CAGradientLayer layer];
    _backgroundGradient.colors = @[
        (id)[UIColor colorWithRed:0.1 green:0.1 blue:0.15 alpha:1.0].CGColor,
        (id)[UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:1.0].CGColor
    ];
    _backgroundGradient.startPoint = CGPointMake(0, 0);
    _backgroundGradient.endPoint = CGPointMake(1, 1);
    [self.layer addSublayer:_backgroundGradient];
    
    // 边框
    _borderLayer = [CAShapeLayer layer];
    _borderLayer.fillColor = [UIColor clearColor].CGColor;
    _borderLayer.strokeColor = [UIColor colorWithRed:0.3 green:0.3 blue:0.4 alpha:0.5].CGColor;
    _borderLayer.lineWidth = 1.0;
    [self.layer addSublayer:_borderLayer];
    
    // 预览图
    _previewImageView = [[UIImageView alloc] init];
    _previewImageView.contentMode = UIViewContentModeScaleAspectFill;
    _previewImageView.clipsToBounds = YES;
    _previewImageView.layer.cornerRadius = 8;
    _previewImageView.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:1.0];
    [self addSubview:_previewImageView];
    
    // 名称标签
    _nameLabel = [[UILabel alloc] init];
    _nameLabel.font = [UIFont boldSystemFontOfSize:16];
    _nameLabel.textColor = [UIColor whiteColor];
    _nameLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:_nameLabel];
    
    // 描述标签
    _descriptionLabel = [[UILabel alloc] init];
    _descriptionLabel.font = [UIFont systemFontOfSize:12];
    _descriptionLabel.textColor = [UIColor colorWithRed:0.8 green:0.8 blue:0.9 alpha:1.0];
    _descriptionLabel.numberOfLines = 2;
    _descriptionLabel.textAlignment = NSTextAlignmentLeft;
    [self addSubview:_descriptionLabel];
    
    // 分类标签
    _categoryBadge = [[UIView alloc] init];
    _categoryBadge.layer.cornerRadius = 8;
    [self addSubview:_categoryBadge];
    
    _categoryLabel = [[UILabel alloc] init];
    _categoryLabel.font = [UIFont boldSystemFontOfSize:10];
    _categoryLabel.textColor = [UIColor whiteColor];
    _categoryLabel.textAlignment = NSTextAlignmentCenter;
    [_categoryBadge addSubview:_categoryLabel];
    
    // 性能指示器
    _performanceIndicator = [[UIView alloc] init];
    _performanceIndicator.layer.cornerRadius = 4;
    [self addSubview:_performanceIndicator];
    
    // 选中遮罩
    _selectionOverlay = [[UIView alloc] init];
    _selectionOverlay.backgroundColor = [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:0.3];
    _selectionOverlay.layer.cornerRadius = 16;
    _selectionOverlay.alpha = 0;
    [self addSubview:_selectionOverlay];
    
    // 🎨 配置按钮（仅在特定特效上显示）
    _configButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *configImage = nil;
    if (@available(iOS 13.0, *)) {
        configImage = [UIImage systemImageNamed:@"gearshape.fill"];
    }
    [_configButton setImage:configImage forState:UIControlStateNormal];
    [_configButton setTitle:@"" forState:UIControlStateNormal];
    _configButton.tintColor = [UIColor whiteColor];
    if (_configButton.imageView) {
        _configButton.imageView.contentMode = UIViewContentModeCenter;
    }
    _configButton.titleLabel.font = [UIFont systemFontOfSize:24];
    _configButton.backgroundColor = [UIColor colorWithRed:0.2 green:0.2 blue:0.3 alpha:0.9];
    _configButton.layer.cornerRadius = 18;
    _configButton.layer.borderWidth = 1.5;
    _configButton.layer.borderColor = [UIColor colorWithRed:0.5 green:0.5 blue:0.6 alpha:1.0].CGColor;
    [_configButton addTarget:self action:@selector(configButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    _configButton.hidden = YES;  // 默认隐藏
    [self addSubview:_configButton];
    
    // 添加点击手势
    UITapGestureRecognizer *tapGesture = [[UITapGestureRecognizer alloc] initWithTarget:self action:@selector(cardTapped:)];
    [self addGestureRecognizer:tapGesture];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    _backgroundGradient.frame = bounds;
    _borderLayer.path = [UIBezierPath bezierPathWithRoundedRect:bounds cornerRadius:16].CGPath;
    _selectionOverlay.frame = bounds;
    
    // 布局子视图
    CGFloat padding = 12;
    CGFloat imageSize = 60;
    
    _previewImageView.frame = CGRectMake(padding, padding, imageSize, imageSize);
    
    CGFloat labelX = padding + imageSize + 12;
    CGFloat labelWidth = bounds.size.width - labelX - padding;
    
    _nameLabel.frame = CGRectMake(labelX, padding, labelWidth - 50, 20);  // 为设置按钮留出空间
    _descriptionLabel.frame = CGRectMake(labelX, padding + 24, labelWidth, 32);
    
    // 分类标签
    CGSize categorySize = [_categoryLabel.text sizeWithAttributes:@{NSFontAttributeName: _categoryLabel.font}];
    _categoryBadge.frame = CGRectMake(bounds.size.width - categorySize.width - 16, padding, categorySize.width + 16, 16);
    _categoryLabel.frame = _categoryBadge.bounds;
    
    // 性能指示器
    _performanceIndicator.frame = CGRectMake(bounds.size.width - 20, bounds.size.height - 20, 8, 8);
    
    // 🎨 配置按钮（右上角）
    _configButton.frame = CGRectMake(bounds.size.width - 48, padding + 2, 36, 36);
}

- (void)updateContent {
    _nameLabel.text = _effectInfo.name;
    _descriptionLabel.text = _effectInfo.effectDescription;
    
    // 更新分类标签
    [self updateCategoryBadge];
    
    // 更新性能指示器
    [self updatePerformanceIndicator];
    
    // 更新预览图
    [self updatePreviewImage];
    
    // 更新支持状态
    [self updateSupportStatus];
    
    // 🎨 根据特效类型决定是否显示设置按钮
    [self updateSettingsButtonVisibility];
}

- (void)updateSettingsButtonVisibility {
    // 只在 Galaxy 和 CyberPunk 特效上显示配置按钮
    BOOL shouldShowSettings = (_effectInfo.type == VisualEffectTypeGalaxy || 
                               _effectInfo.type == VisualEffectTypeCyberPunk);
    _configButton.hidden = !shouldShowSettings;
}

- (void)updateCategoryBadge {
    switch (_effectInfo.category) {
        case EffectCategoryBasic:
            _categoryBadge.backgroundColor = [UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0];
            _categoryLabel.text = @"基础";
            break;
        case EffectCategoryMetal:
            _categoryBadge.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.8 alpha:1.0];
            _categoryLabel.text = @"Metal";
            break;
        case EffectCategoryCreative:
            _categoryBadge.backgroundColor = [UIColor colorWithRed:0.8 green:0.6 blue:0.4 alpha:1.0];
            _categoryLabel.text = @"创意";
            break;
        case EffectCategoryExperimental:
            _categoryBadge.backgroundColor = [UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0];
            _categoryLabel.text = @"实验";
            break;
    }
}

- (void)updatePerformanceIndicator {
    switch (_effectInfo.performanceLevel) {
        case PerformanceLevelLow:
            _performanceIndicator.backgroundColor = [UIColor greenColor];
            break;
        case PerformanceLevelMedium:
            _performanceIndicator.backgroundColor = [UIColor yellowColor];
            break;
        case PerformanceLevelHigh:
            _performanceIndicator.backgroundColor = [UIColor orangeColor];
            break;
        case PerformanceLevelExtreme:
            _performanceIndicator.backgroundColor = [UIColor redColor];
            break;
    }
}

- (void)updatePreviewImage {
    // 生成程序化预览图
    UIImage *previewImage = [self generatePreviewImageForEffect:_effectInfo.type];
    _previewImageView.image = previewImage;
}

- (void)updateSupportStatus {
    BOOL supported = [[VisualEffectRegistry sharedRegistry] deviceSupportsEffect:_effectInfo.type];
    _isSupported = supported;
    
    if (!supported) {
        self.alpha = 0.5;
        _nameLabel.textColor = [UIColor colorWithRed:0.6 green:0.6 blue:0.6 alpha:1.0];
    } else {
        self.alpha = 1.0;
        _nameLabel.textColor = [UIColor whiteColor];
    }
}

- (UIImage *)generatePreviewImageForEffect:(VisualEffectType)effectType {
    CGSize size = CGSizeMake(60, 60);
    UIGraphicsBeginImageContextWithOptions(size, NO, 0);
    CGContextRef context = UIGraphicsGetCurrentContext();
    
    // 根据效果类型生成不同的预览图
    switch (effectType) {
        case VisualEffectTypeNeonGlow:
            [self drawNeonGlowPreview:context size:size];
            break;
        case VisualEffectType3DWaveform:
            [self draw3DWaveformPreview:context size:size];
            break;
        case VisualEffectTypeFluidSimulation:
            [self drawFluidSimulationPreview:context size:size];
            break;
        case VisualEffectTypeChromaticCaustics:
            [self drawChromaticCausticsPreview:context size:size];
            break;
        default:
            [self drawDefaultPreview:context size:size];
            break;
    }
    
    UIImage *image = UIGraphicsGetImageFromCurrentImageContext();
    UIGraphicsEndImageContext();
    
    return image;
}

- (void)drawNeonGlowPreview:(CGContextRef)context size:(CGSize)size {
    // 绘制霓虹发光效果预览
    CGContextSetRGBFillColor(context, 0.0, 0.8, 1.0, 1.0);
    CGContextFillEllipseInRect(context, CGRectMake(10, 10, 40, 40));
    
    CGContextSetRGBStrokeColor(context, 0.0, 1.0, 1.0, 0.8);
    CGContextSetLineWidth(context, 3);
    CGContextStrokeEllipseInRect(context, CGRectMake(5, 5, 50, 50));
}

- (void)draw3DWaveformPreview:(CGContextRef)context size:(CGSize)size {
    // 绘制3D波形效果预览
    CGContextSetRGBStrokeColor(context, 0.8, 0.4, 1.0, 1.0);
    CGContextSetLineWidth(context, 2);
    
    CGContextMoveToPoint(context, 10, 30);
    for (int i = 0; i < 40; i += 4) {
        CGFloat y = 30 + sin(i * 0.3) * 15;
        CGContextAddLineToPoint(context, 10 + i, y);
    }
    CGContextStrokePath(context);
}

- (void)drawFluidSimulationPreview:(CGContextRef)context size:(CGSize)size {
    // 绘制流体模拟效果预览
    CGGradientRef gradient;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.2, 0.6, 1.0, 1.0,
        0.8, 0.2, 1.0, 1.0
    };
    gradient = CGGradientCreateWithColorComponents(colorSpace, colors, NULL, 2);
    
    CGPoint startPoint = CGPointMake(0, 0);
    CGPoint endPoint = CGPointMake(size.width, size.height);
    CGContextDrawLinearGradient(context, gradient, startPoint, endPoint, 0);
    
    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
}

- (void)drawChromaticCausticsPreview:(CGContextRef)context size:(CGSize)size {
    CGColorSpaceRef colorSpace = CGColorSpaceCreateDeviceRGB();
    CGFloat colors[] = {
        0.07, 0.04, 0.18, 1.0,
        0.10, 0.20, 0.40, 1.0,
        0.92, 0.46, 0.78, 1.0,
        1.00, 0.82, 0.36, 1.0
    };
    CGFloat locations[] = {0.0, 0.4, 0.78, 1.0};
    CGGradientRef gradient = CGGradientCreateWithColorComponents(colorSpace, colors, locations, 4);
    CGContextDrawLinearGradient(context,
                                gradient,
                                CGPointMake(0, size.height),
                                CGPointMake(size.width, 0),
                                0);

    CGContextSetBlendMode(context, kCGBlendModeScreen);
    CGContextSetLineWidth(context, 3.0);

    [[UIColor colorWithRed:0.55 green:0.95 blue:1.0 alpha:0.85] setStroke];
    CGContextMoveToPoint(context, 8, 42);
    CGContextAddCurveToPoint(context, 18, 14, 38, 12, 52, 40);
    CGContextStrokePath(context);

    [[UIColor colorWithRed:1.0 green:0.62 blue:0.86 alpha:0.75] setStroke];
    CGContextMoveToPoint(context, 10, 50);
    CGContextAddCurveToPoint(context, 24, 22, 36, 22, 49, 50);
    CGContextStrokePath(context);

    CGContextSetRGBFillColor(context, 1.0, 0.95, 0.78, 0.42);
    CGContextFillEllipseInRect(context, CGRectMake(18, 20, 24, 24));

    CGGradientRelease(gradient);
    CGColorSpaceRelease(colorSpace);
}

- (void)drawDefaultPreview:(CGContextRef)context size:(CGSize)size {
    // 绘制默认预览
    CGContextSetRGBFillColor(context, 0.5, 0.5, 0.7, 1.0);
    CGContextFillRect(context, CGRectMake(0, 0, size.width, size.height));
}

- (void)updateSelectionState:(BOOL)selected animated:(BOOL)animated {
    _isSelected = selected;
    
    void (^updateBlock)(void) = ^{
        self->_selectionOverlay.alpha = selected ? 1.0 : 0.0;
        self->_borderLayer.strokeColor = selected ? 
            [UIColor colorWithRed:0.0 green:0.5 blue:1.0 alpha:1.0].CGColor :
            [UIColor colorWithRed:0.3 green:0.3 blue:0.4 alpha:0.5].CGColor;
        
        if (selected) {
            self.transform = CGAffineTransformMakeScale(1.05, 1.05);
        } else {
            self.transform = CGAffineTransformIdentity;
        }
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 
                              delay:0 
             usingSpringWithDamping:0.8 
              initialSpringVelocity:0.5 
                            options:UIViewAnimationOptionCurveEaseInOut 
                         animations:updateBlock 
                         completion:nil];
    } else {
        updateBlock();
    }
}

- (void)cardTapped:(UITapGestureRecognizer *)gesture {
    if (!_isSupported) return;
    
    // 发送选择通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"EffectCardSelected" 
                                                        object:self 
                                                      userInfo:@{@"effectType": @(_effectType)}];
}

- (void)configButtonTapped:(UIButton *)sender {
    // 🎨 发送特效配置通知
    [[NSNotificationCenter defaultCenter] postNotificationName:@"EffectSettingsButtonTapped" 
                                                        object:self 
                                                      userInfo:@{@"effectType": @(_effectType)}];
    NSLog(@"🎨 特效配置按钮被点击: %@", _effectInfo.name);
}

@end

#pragma mark - CategoryButton

@interface CategoryButton ()
@property (nonatomic, strong) CAGradientLayer *backgroundGradient;
@end

@implementation CategoryButton

- (instancetype)initWithCategory:(EffectCategory)category {
    if (self = [super init]) {
        _category = category;
        [self setupButton];
        [self updateForCategory:category];
    }
    return self;
}

- (void)setupButton {
    self.layer.cornerRadius = 20;
    self.clipsToBounds = YES;
    
    _backgroundGradient = [CAGradientLayer layer];
    [self.layer insertSublayer:_backgroundGradient atIndex:0];
    
    self.titleLabel.font = [UIFont boldSystemFontOfSize:14];
    [self setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    _backgroundGradient.frame = self.bounds;
}

- (void)updateForCategory:(EffectCategory)category {
    NSString *title;
    NSArray *colors;
    
    switch (category) {
        case EffectCategoryBasic:
            title = @"基础效果";
            colors = @[(id)[UIColor colorWithRed:0.4 green:0.8 blue:0.4 alpha:1.0].CGColor,
                      (id)[UIColor colorWithRed:0.2 green:0.6 blue:0.2 alpha:1.0].CGColor];
            break;
        case EffectCategoryMetal:
            title = @"Metal效果";
            colors = @[(id)[UIColor colorWithRed:0.8 green:0.4 blue:0.8 alpha:1.0].CGColor,
                      (id)[UIColor colorWithRed:0.6 green:0.2 blue:0.6 alpha:1.0].CGColor];
            break;
        case EffectCategoryCreative:
            title = @"创意效果";
            colors = @[(id)[UIColor colorWithRed:0.8 green:0.6 blue:0.4 alpha:1.0].CGColor,
                      (id)[UIColor colorWithRed:0.6 green:0.4 blue:0.2 alpha:1.0].CGColor];
            break;
        case EffectCategoryExperimental:
            title = @"实验效果";
            colors = @[(id)[UIColor colorWithRed:0.8 green:0.4 blue:0.4 alpha:1.0].CGColor,
                      (id)[UIColor colorWithRed:0.6 green:0.2 blue:0.2 alpha:1.0].CGColor];
            break;
    }
    
    [self setTitle:title forState:UIControlStateNormal];
    _backgroundGradient.colors = colors;
}

- (void)updateSelectionState:(BOOL)selected animated:(BOOL)animated {
    _isSelected = selected;
    
    void (^updateBlock)(void) = ^{
        self.alpha = selected ? 1.0 : 0.6;
        self.transform = selected ? CGAffineTransformMakeScale(1.1, 1.1) : CGAffineTransformIdentity;
    };
    
    if (animated) {
        [UIView animateWithDuration:0.3 animations:updateBlock];
    } else {
        updateBlock();
    }
}

@end

#pragma mark - EffectSelectorView

@interface EffectSelectorView ()
@property (nonatomic, strong) UIScrollView *categoriesScrollView;
@property (nonatomic, strong) UICollectionView *effectsCollectionView;
@property (nonatomic, strong) UIButton *settingsButton;
@property (nonatomic, strong) UIButton *closeButton;
@property (nonatomic, strong) NSMutableArray<CategoryButton *> *categoryButtons;
@property (nonatomic, strong) NSArray<VisualEffectInfo *> *currentEffects;
@property (nonatomic, assign) EffectCategory selectedCategory;
@end

@implementation EffectSelectorView

- (instancetype)init {
    if (self = [super init]) {
        [self setupViews];
        [self setupData];
    }
    return self;
}

- (void)setupViews {
    self.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.1 alpha:0.95];
    self.layer.cornerRadius = 24;
    self.clipsToBounds = YES;
    
    // 关闭按钮
    _closeButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *closeImage = nil;
    if (@available(iOS 13.0, *)) {
        closeImage = [UIImage systemImageNamed:@"xmark"];
    }
    [_closeButton setImage:closeImage forState:UIControlStateNormal];
    [_closeButton setTitle:@"" forState:UIControlStateNormal];
    _closeButton.tintColor = [UIColor whiteColor];
    if (_closeButton.imageView) {
        _closeButton.imageView.contentMode = UIViewContentModeCenter;
    }
    [_closeButton setTitleColor:[UIColor whiteColor] forState:UIControlStateNormal];
    _closeButton.titleLabel.font = [UIFont systemFontOfSize:18];
    [_closeButton addTarget:self action:@selector(closeButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_closeButton];
    
    // 设置按钮
    _settingsButton = [UIButton buttonWithType:UIButtonTypeSystem];
    UIImage *settingsImage = nil;
    if (@available(iOS 13.0, *)) {
        settingsImage = [UIImage systemImageNamed:@"gearshape.fill"];
    }
    [_settingsButton setImage:settingsImage forState:UIControlStateNormal];
    [_settingsButton setTitle:@"" forState:UIControlStateNormal];
    _settingsButton.tintColor = [UIColor whiteColor];
    if (_settingsButton.imageView) {
        _settingsButton.imageView.contentMode = UIViewContentModeCenter;
    }
    _settingsButton.titleLabel.font = [UIFont systemFontOfSize:18];
    [_settingsButton addTarget:self action:@selector(settingsButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
    [self addSubview:_settingsButton];
    
    // 分类滚动视图
    _categoriesScrollView = [[UIScrollView alloc] init];
    _categoriesScrollView.showsHorizontalScrollIndicator = NO;
    [self addSubview:_categoriesScrollView];
    
    // 效果集合视图
    UICollectionViewFlowLayout *layout = [[UICollectionViewFlowLayout alloc] init];
    layout.itemSize = CGSizeMake(280, 80);
    layout.minimumLineSpacing = 12;
    layout.sectionInset = UIEdgeInsetsMake(20, 20, 20, 20);
    
    _effectsCollectionView = [[UICollectionView alloc] initWithFrame:CGRectZero collectionViewLayout:layout];
    _effectsCollectionView.backgroundColor = [UIColor clearColor];
    _effectsCollectionView.delegate = self;
    _effectsCollectionView.dataSource = self;
    [_effectsCollectionView registerClass:[UICollectionViewCell class] forCellWithReuseIdentifier:@"EffectCell"];
    [self addSubview:_effectsCollectionView];
    
    // 创建分类按钮
    [self createCategoryButtons];
    
    // 监听卡片选择通知
    [[NSNotificationCenter defaultCenter] addObserver:self 
                                             selector:@selector(effectCardSelected:) 
                                                 name:@"EffectCardSelected" 
                                               object:nil];
}

- (void)setupData {
    _selectedCategory = EffectCategoryBasic;
    [self updateEffectsForCategory:_selectedCategory];
}

- (void)createCategoryButtons {
    _categoryButtons = [NSMutableArray array];
    
    for (NSInteger i = 0; i < 4; i++) {
        CategoryButton *button = [[CategoryButton alloc] initWithCategory:i];
        [button addTarget:self action:@selector(categoryButtonTapped:) forControlEvents:UIControlEventTouchUpInside];
        [_categoryButtons addObject:button];
        [_categoriesScrollView addSubview:button];
    }
    
    // 默认选中第一个
    [_categoryButtons.firstObject updateSelectionState:YES animated:NO];
}

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGRect bounds = self.bounds;
    CGFloat padding = 20;
    
    // 顶部按钮
    _closeButton.frame = CGRectMake(padding, padding, 44, 44);
    _settingsButton.frame = CGRectMake(bounds.size.width - padding - 44, padding, 44, 44);
    
    // 分类按钮区域
    CGFloat categoryHeight = 40;
    _categoriesScrollView.frame = CGRectMake(0, 80, bounds.size.width, categoryHeight);
    
    // 布局分类按钮
    CGFloat buttonWidth = 100;
    CGFloat buttonSpacing = 12;
    for (NSInteger i = 0; i < _categoryButtons.count; i++) {
        CategoryButton *button = _categoryButtons[i];
        button.frame = CGRectMake(padding + i * (buttonWidth + buttonSpacing), 0, buttonWidth, categoryHeight);
    }
    
    _categoriesScrollView.contentSize = CGSizeMake(padding * 2 + _categoryButtons.count * (buttonWidth + buttonSpacing), categoryHeight);
    
    // 效果集合视图
    _effectsCollectionView.frame = CGRectMake(0, 140, bounds.size.width, bounds.size.height - 140);
}

- (void)updateEffectsForCategory:(EffectCategory)category {
    _currentEffects = [[VisualEffectRegistry sharedRegistry] effectsForCategory:category];
    [_effectsCollectionView reloadData];
}

#pragma mark - Actions

- (void)categoryButtonTapped:(CategoryButton *)sender {
    if (sender.category == _selectedCategory) return;
    
    // 更新选中状态
    for (CategoryButton *button in _categoryButtons) {
        [button updateSelectionState:(button == sender) animated:YES];
    }
    
    _selectedCategory = sender.category;
    [self updateEffectsForCategory:_selectedCategory];
}

- (void)closeButtonTapped:(UIButton *)sender {
    [self hideWithAnimation:YES];
}

- (void)settingsButtonTapped:(UIButton *)sender {
    if ([self.delegate respondsToSelector:@selector(effectSelector:didChangeSettings:)]) {
        [self.delegate effectSelector:self didChangeSettings:@{}];
    }
}

- (void)effectCardSelected:(NSNotification *)notification {
    EffectCardView *cardView = notification.object;
    VisualEffectType effectType = [notification.userInfo[@"effectType"] integerValue];
    
    [self setCurrentEffectType:effectType animated:YES];
    
    if ([self.delegate respondsToSelector:@selector(effectSelector:didSelectEffect:)]) {
        [self.delegate effectSelector:self didSelectEffect:effectType];
    }
}

#pragma mark - Public Methods

- (void)showWithAnimation:(BOOL)animated {
    if (_isVisible) return;
    _isVisible = YES;
    
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
                            options:UIViewAnimationOptionCurveEaseInOut 
                         animations:showBlock 
                         completion:nil];
    } else {
        showBlock();
    }
}

- (void)hideWithAnimation:(BOOL)animated {
    if (!_isVisible) return;
    _isVisible = NO;
    
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

- (void)setCurrentEffectType:(VisualEffectType)effectType animated:(BOOL)animated {
    _currentEffectType = effectType;
    // 更新UI显示当前选中的效果
}

- (void)refreshDeviceSupport {
    [_effectsCollectionView reloadData];
}

#pragma mark - UICollectionViewDataSource

- (NSInteger)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(NSInteger)section {
    return _currentEffects.count;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    UICollectionViewCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:@"EffectCell" forIndexPath:indexPath];
    
    // 清除旧的卡片视图
    for (UIView *subview in cell.subviews) {
        if ([subview isKindOfClass:[EffectCardView class]]) {
            [subview removeFromSuperview];
        }
    }
    
    // 添加新的卡片视图
    VisualEffectInfo *effectInfo = _currentEffects[indexPath.item];
    EffectCardView *cardView = [[EffectCardView alloc] initWithEffectInfo:effectInfo];
    cardView.frame = cell.bounds;
    [cell addSubview:cardView];
    
    return cell;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

@end

#pragma mark - EffectSettingsPanel

@implementation EffectSettingsPanel
// 设置面板实现...
@end

#pragma mark - EffectPreviewWindow

@implementation EffectPreviewWindow
// 预览窗口实现...
@end
