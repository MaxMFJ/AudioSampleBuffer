//
//  VinylRecordView.m
//  AudioSampleBuffer
//
//  黑胶唱片动画视图实现
//

#import "VinylRecordView.h"

@interface VinylRecordView ()

// 视图层级
@property (nonatomic, strong) CALayer *vinylLayer;           // 黑胶唱片主体
@property (nonatomic, strong) CAGradientLayer *glossLayer;   // 光泽层
@property (nonatomic, strong) CALayer *labelLayer;           // 中心标签
@property (nonatomic, strong) CAShapeLayer *groovesLayer;    // 纹路层

// 动画相关
@property (nonatomic, assign) BOOL isSpinning;
@property (nonatomic, assign) CFTimeInterval pausedTime;
@property (nonatomic, strong) CADisplayLink *displayLink;

// 随机种子
@property (nonatomic, assign) NSUInteger currentSeed;

@end

@implementation VinylRecordView

#pragma mark - 初始化

- (instancetype)initWithFrame:(CGRect)frame {
    return [self initWithFrame:frame seed:arc4random()];
}

- (instancetype)initWithFrame:(CGRect)frame seed:(NSUInteger)seed {
    self = [super initWithFrame:frame];
    if (self) {
        _currentSeed = seed;
        _rotationsPerSecond = 0.5;
        _glossIntensity = 0.3;
        [self setupLayers];
    }
    return self;
}

- (instancetype)initWithFrame:(CGRect)frame songName:(NSString *)songName {
    NSUInteger seed = [self seedFromString:songName];
    return [self initWithFrame:frame seed:seed];
}

- (NSUInteger)seedFromString:(NSString *)string {
    // 使用字符串哈希值作为种子，确保相同字符串产生相同的外观
    return string.hash;
}

#pragma mark - 视图层设置

- (void)setupLayers {
    self.backgroundColor = [UIColor clearColor];
    self.clipsToBounds = NO;
    
    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    CGPoint center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    
    // 1. 创建黑胶唱片主体
    [self setupVinylLayerWithSize:size center:center];
    
    // 2. 创建纹路
    [self setupGroovesLayerWithSize:size center:center];
    
    // 3. 创建光泽效果
    [self setupGlossLayerWithSize:size center:center];
    
    // 4. 创建中心标签
    [self setupLabelLayerWithSize:size center:center];
    
    // 5. 创建中心孔
    [self setupCenterHoleWithSize:size center:center];
}

- (void)setupVinylLayerWithSize:(CGFloat)size center:(CGPoint)center {
    self.vinylLayer = [CALayer layer];
    self.vinylLayer.bounds = CGRectMake(0, 0, size, size);
    self.vinylLayer.position = center;
    self.vinylLayer.cornerRadius = size / 2;
    self.vinylLayer.masksToBounds = YES;
    
    // 黑胶基底色 - 深灰色略带蓝调
    self.vinylLayer.backgroundColor = [UIColor colorWithRed:0.08 green:0.08 blue:0.10 alpha:1.0].CGColor;
    
    // 添加微妙的边缘阴影
    self.vinylLayer.shadowColor = [UIColor blackColor].CGColor;
    self.vinylLayer.shadowOffset = CGSizeMake(0, 4);
    self.vinylLayer.shadowOpacity = 0.5;
    self.vinylLayer.shadowRadius = 8;
    self.vinylLayer.masksToBounds = NO;
    
    [self.layer addSublayer:self.vinylLayer];
}

- (void)setupGroovesLayerWithSize:(CGFloat)size center:(CGPoint)center {
    self.groovesLayer = [CAShapeLayer layer];
    self.groovesLayer.bounds = CGRectMake(0, 0, size, size);
    self.groovesLayer.position = center;
    
    UIBezierPath *groovesPath = [UIBezierPath bezierPath];
    
    // 从标签边缘到唱片边缘绘制同心圆纹路
    CGFloat labelRadius = size * 0.2;
    CGFloat outerRadius = size * 0.48;
    CGFloat grooveSpacing = 2.5; // 纹路间距
    
    CGPoint pathCenter = CGPointMake(size / 2, size / 2);
    
    for (CGFloat r = labelRadius; r < outerRadius; r += grooveSpacing) {
        [groovesPath moveToPoint:CGPointMake(pathCenter.x + r, pathCenter.y)];
        [groovesPath addArcWithCenter:pathCenter
                               radius:r
                           startAngle:0
                             endAngle:M_PI * 2
                            clockwise:YES];
    }
    
    self.groovesLayer.path = groovesPath.CGPath;
    self.groovesLayer.strokeColor = [UIColor colorWithWhite:0.15 alpha:0.6].CGColor;
    self.groovesLayer.fillColor = [UIColor clearColor].CGColor;
    self.groovesLayer.lineWidth = 0.5;
    
    [self.layer addSublayer:self.groovesLayer];
}

- (void)setupGlossLayerWithSize:(CGFloat)size center:(CGPoint)center {
    self.glossLayer = [CAGradientLayer layer];
    self.glossLayer.bounds = CGRectMake(0, 0, size, size);
    self.glossLayer.position = center;
    self.glossLayer.cornerRadius = size / 2;
    self.glossLayer.masksToBounds = YES;
    
    // 创建斜向光泽效果
    self.glossLayer.type = kCAGradientLayerConic;
    self.glossLayer.startPoint = CGPointMake(0.5, 0.5);
    self.glossLayer.endPoint = CGPointMake(0.5, 0);
    
    CGFloat intensity = self.glossIntensity;
    self.glossLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.8].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.3].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.5].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.8].CGColor,
    ];
    
    self.glossLayer.locations = @[@0, @0.15, @0.35, @0.5, @0.65, @0.85, @1.0];
    
    [self.layer addSublayer:self.glossLayer];
}

- (void)setupLabelLayerWithSize:(CGFloat)size center:(CGPoint)center {
    CGFloat labelSize = size * 0.38;
    
    self.labelLayer = [CALayer layer];
    self.labelLayer.bounds = CGRectMake(0, 0, labelSize, labelSize);
    self.labelLayer.position = center;
    self.labelLayer.cornerRadius = labelSize / 2;
    self.labelLayer.masksToBounds = YES;
    
    // 生成随机颜色和图案
    [self applyRandomLabelAppearanceWithSeed:self.currentSeed size:labelSize];
    
    [self.layer addSublayer:self.labelLayer];
}

- (void)applyRandomLabelAppearanceWithSeed:(NSUInteger)seed size:(CGFloat)labelSize {
    srand48(seed);
    
    // 如果设置了固定颜色，使用固定颜色
    UIColor *primaryColor = self.labelColor;
    if (!primaryColor) {
        // 随机生成漂亮的颜色
        primaryColor = [self randomVibrantColorWithSeed:seed];
    }
    
    // 创建渐变标签背景
    CAGradientLayer *labelGradient = [CAGradientLayer layer];
    labelGradient.frame = CGRectMake(0, 0, labelSize, labelSize);
    labelGradient.cornerRadius = labelSize / 2;
    
    // 随机选择渐变样式
    NSInteger gradientStyle = seed % 4;
    
    CGFloat hue, saturation, brightness, alpha;
    [primaryColor getHue:&hue saturation:&saturation brightness:&brightness alpha:&alpha];
    
    UIColor *secondaryColor;
    
    switch (gradientStyle) {
        case 0: // 同色调深浅渐变
            secondaryColor = [UIColor colorWithHue:hue
                                        saturation:saturation * 0.7
                                        brightness:brightness * 0.6
                                             alpha:1.0];
            break;
        case 1: // 互补色渐变
            secondaryColor = [UIColor colorWithHue:fmod(hue + 0.5, 1.0)
                                        saturation:saturation * 0.8
                                        brightness:brightness * 0.8
                                             alpha:1.0];
            break;
        case 2: // 邻近色渐变
            secondaryColor = [UIColor colorWithHue:fmod(hue + 0.1, 1.0)
                                        saturation:saturation
                                        brightness:brightness * 0.7
                                             alpha:1.0];
            break;
        default: // 单色带阴影
            secondaryColor = [UIColor colorWithHue:hue
                                        saturation:saturation * 0.5
                                        brightness:brightness * 0.4
                                             alpha:1.0];
            break;
    }
    
    labelGradient.colors = @[(id)primaryColor.CGColor, (id)secondaryColor.CGColor];
    labelGradient.startPoint = CGPointMake(0.2, 0);
    labelGradient.endPoint = CGPointMake(0.8, 1);
    
    // 清除旧的子层
    [self.labelLayer.sublayers makeObjectsPerformSelector:@selector(removeFromSuperlayer)];
    [self.labelLayer addSublayer:labelGradient];
    
    // 添加装饰图案
    [self addLabelDecorationsWithSeed:seed size:labelSize toLayer:self.labelLayer];
}

- (void)addLabelDecorationsWithSeed:(NSUInteger)seed size:(CGFloat)labelSize toLayer:(CALayer *)parentLayer {
    srand48(seed + 100);
    
    NSInteger decorationType = (seed / 4) % 5;
    CGPoint labelCenter = CGPointMake(labelSize / 2, labelSize / 2);
    
    switch (decorationType) {
        case 0:
            // 同心圆环装饰
            [self addConcentricRingsToLayer:parentLayer size:labelSize center:labelCenter];
            break;
        case 1:
            // 射线条纹装饰
            [self addRadialStripesToLayer:parentLayer size:labelSize center:labelCenter seed:seed];
            break;
        case 2:
            // 复古唱片标签风格
            [self addVintageStyleToLayer:parentLayer size:labelSize center:labelCenter];
            break;
        case 3:
            // 极简风格 - 只有中心圆环
            [self addMinimalStyleToLayer:parentLayer size:labelSize center:labelCenter];
            break;
        default:
            // 几何图案
            [self addGeometricPatternToLayer:parentLayer size:labelSize center:labelCenter seed:seed];
            break;
    }
}

- (void)addConcentricRingsToLayer:(CALayer *)parentLayer size:(CGFloat)size center:(CGPoint)center {
    CAShapeLayer *ringsLayer = [CAShapeLayer layer];
    ringsLayer.frame = CGRectMake(0, 0, size, size);
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    CGFloat radii[] = {size * 0.35, size * 0.42};
    
    for (int i = 0; i < 2; i++) {
        [path moveToPoint:CGPointMake(center.x + radii[i], center.y)];
        [path addArcWithCenter:center radius:radii[i] startAngle:0 endAngle:M_PI * 2 clockwise:YES];
    }
    
    ringsLayer.path = path.CGPath;
    ringsLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.3].CGColor;
    ringsLayer.fillColor = [UIColor clearColor].CGColor;
    ringsLayer.lineWidth = 1.5;
    
    [parentLayer addSublayer:ringsLayer];
}

- (void)addRadialStripesToLayer:(CALayer *)parentLayer size:(CGFloat)size center:(CGPoint)center seed:(NSUInteger)seed {
    CAShapeLayer *stripesLayer = [CAShapeLayer layer];
    stripesLayer.frame = CGRectMake(0, 0, size, size);
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    NSInteger stripeCount = 8 + (seed % 8); // 8-15 条射线
    CGFloat innerRadius = size * 0.15;
    CGFloat outerRadius = size * 0.45;
    
    for (NSInteger i = 0; i < stripeCount; i++) {
        CGFloat angle = (CGFloat)i / stripeCount * M_PI * 2;
        CGFloat startX = center.x + cos(angle) * innerRadius;
        CGFloat startY = center.y + sin(angle) * innerRadius;
        CGFloat endX = center.x + cos(angle) * outerRadius;
        CGFloat endY = center.y + sin(angle) * outerRadius;
        
        [path moveToPoint:CGPointMake(startX, startY)];
        [path addLineToPoint:CGPointMake(endX, endY)];
    }
    
    stripesLayer.path = path.CGPath;
    stripesLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.25].CGColor;
    stripesLayer.lineWidth = 2.0;
    stripesLayer.lineCap = kCALineCapRound;
    
    [parentLayer addSublayer:stripesLayer];
}

- (void)addVintageStyleToLayer:(CALayer *)parentLayer size:(CGFloat)size center:(CGPoint)center {
    // 外圈金边
    CAShapeLayer *borderLayer = [CAShapeLayer layer];
    borderLayer.frame = CGRectMake(0, 0, size, size);
    
    UIBezierPath *borderPath = [UIBezierPath bezierPathWithArcCenter:center
                                                              radius:size * 0.46
                                                          startAngle:0
                                                            endAngle:M_PI * 2
                                                           clockwise:YES];
    borderLayer.path = borderPath.CGPath;
    borderLayer.strokeColor = [UIColor colorWithRed:0.85 green:0.75 blue:0.55 alpha:0.6].CGColor;
    borderLayer.fillColor = [UIColor clearColor].CGColor;
    borderLayer.lineWidth = 3.0;
    
    [parentLayer addSublayer:borderLayer];
    
    // 内圈装饰
    CAShapeLayer *innerRing = [CAShapeLayer layer];
    innerRing.frame = CGRectMake(0, 0, size, size);
    
    UIBezierPath *innerPath = [UIBezierPath bezierPathWithArcCenter:center
                                                             radius:size * 0.25
                                                         startAngle:0
                                                           endAngle:M_PI * 2
                                                          clockwise:YES];
    innerRing.path = innerPath.CGPath;
    innerRing.strokeColor = [UIColor colorWithRed:0.85 green:0.75 blue:0.55 alpha:0.4].CGColor;
    innerRing.fillColor = [UIColor clearColor].CGColor;
    innerRing.lineWidth = 1.5;
    
    [parentLayer addSublayer:innerRing];
}

- (void)addMinimalStyleToLayer:(CALayer *)parentLayer size:(CGFloat)size center:(CGPoint)center {
    CAShapeLayer *circleLayer = [CAShapeLayer layer];
    circleLayer.frame = CGRectMake(0, 0, size, size);
    
    UIBezierPath *path = [UIBezierPath bezierPathWithArcCenter:center
                                                        radius:size * 0.2
                                                    startAngle:0
                                                      endAngle:M_PI * 2
                                                     clockwise:YES];
    circleLayer.path = path.CGPath;
    circleLayer.strokeColor = [UIColor colorWithWhite:0 alpha:0.3].CGColor;
    circleLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.15].CGColor;
    circleLayer.lineWidth = 2.0;
    
    [parentLayer addSublayer:circleLayer];
}

- (void)addGeometricPatternToLayer:(CALayer *)parentLayer size:(CGFloat)size center:(CGPoint)center seed:(NSUInteger)seed {
    CAShapeLayer *patternLayer = [CAShapeLayer layer];
    patternLayer.frame = CGRectMake(0, 0, size, size);
    
    UIBezierPath *path = [UIBezierPath bezierPath];
    
    // 绘制多边形
    NSInteger sides = 3 + (seed % 4); // 3-6 边形
    CGFloat radius = size * 0.35;
    CGFloat startAngle = -M_PI_2;
    
    for (NSInteger i = 0; i <= sides; i++) {
        CGFloat angle = startAngle + (CGFloat)i / sides * M_PI * 2;
        CGFloat x = center.x + cos(angle) * radius;
        CGFloat y = center.y + sin(angle) * radius;
        
        if (i == 0) {
            [path moveToPoint:CGPointMake(x, y)];
        } else {
            [path addLineToPoint:CGPointMake(x, y)];
        }
    }
    [path closePath];
    
    patternLayer.path = path.CGPath;
    patternLayer.strokeColor = [UIColor colorWithWhite:1.0 alpha:0.35].CGColor;
    patternLayer.fillColor = [UIColor clearColor].CGColor;
    patternLayer.lineWidth = 2.0;
    patternLayer.lineJoin = kCALineJoinRound;
    
    [parentLayer addSublayer:patternLayer];
}

- (void)setupCenterHoleWithSize:(CGFloat)size center:(CGPoint)center {
    CGFloat holeSize = size * 0.06;
    
    CALayer *holeLayer = [CALayer layer];
    holeLayer.bounds = CGRectMake(0, 0, holeSize, holeSize);
    holeLayer.position = center;
    holeLayer.cornerRadius = holeSize / 2;
    holeLayer.backgroundColor = [UIColor colorWithRed:0.05 green:0.05 blue:0.07 alpha:1.0].CGColor;
    
    // 添加中心孔的光泽
    CAGradientLayer *holeGloss = [CAGradientLayer layer];
    holeGloss.frame = CGRectMake(0, 0, holeSize, holeSize);
    holeGloss.cornerRadius = holeSize / 2;
    holeGloss.colors = @[
        (id)[UIColor colorWithWhite:0.3 alpha:0.5].CGColor,
        (id)[UIColor colorWithWhite:0 alpha:0.8].CGColor
    ];
    holeGloss.startPoint = CGPointMake(0.3, 0.2);
    holeGloss.endPoint = CGPointMake(0.7, 0.8);
    
    [holeLayer addSublayer:holeGloss];
    [self.layer addSublayer:holeLayer];
}

#pragma mark - 颜色生成

- (UIColor *)randomVibrantColorWithSeed:(NSUInteger)seed {
    srand48(seed);
    
    // 预定义一组漂亮的颜色调色板
    NSArray<UIColor *> *palette = @[
        // 暖色系
        [UIColor colorWithRed:0.95 green:0.35 blue:0.25 alpha:1.0], // 珊瑚红
        [UIColor colorWithRed:0.95 green:0.55 blue:0.25 alpha:1.0], // 橙色
        [UIColor colorWithRed:0.90 green:0.75 blue:0.30 alpha:1.0], // 金色
        
        // 冷色系
        [UIColor colorWithRed:0.25 green:0.60 blue:0.90 alpha:1.0], // 天蓝
        [UIColor colorWithRed:0.30 green:0.45 blue:0.85 alpha:1.0], // 宝蓝
        [UIColor colorWithRed:0.45 green:0.35 blue:0.80 alpha:1.0], // 紫色
        
        // 自然色系
        [UIColor colorWithRed:0.35 green:0.75 blue:0.55 alpha:1.0], // 翠绿
        [UIColor colorWithRed:0.55 green:0.80 blue:0.45 alpha:1.0], // 草绿
        [UIColor colorWithRed:0.25 green:0.65 blue:0.65 alpha:1.0], // 青色
        
        // 复古色系
        [UIColor colorWithRed:0.70 green:0.50 blue:0.40 alpha:1.0], // 褐色
        [UIColor colorWithRed:0.80 green:0.45 blue:0.55 alpha:1.0], // 玫瑰
        [UIColor colorWithRed:0.55 green:0.55 blue:0.65 alpha:1.0], // 灰蓝
        
        // 鲜艳色系
        [UIColor colorWithRed:0.95 green:0.25 blue:0.55 alpha:1.0], // 洋红
        [UIColor colorWithRed:0.35 green:0.85 blue:0.85 alpha:1.0], // 青蓝
        [UIColor colorWithRed:0.85 green:0.85 blue:0.25 alpha:1.0], // 柠檬黄
    ];
    
    NSUInteger index = seed % palette.count;
    return palette[index];
}

#pragma mark - 动画控制

- (void)startSpinning {
    if (self.isSpinning) return;
    
    self.isSpinning = YES;
    
    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = @0;
    rotation.toValue = @(M_PI * 2);
    rotation.duration = 1.0 / self.rotationsPerSecond;
    rotation.repeatCount = HUGE_VALF;
    rotation.timingFunction = [CAMediaTimingFunction functionWithName:kCAMediaTimingFunctionLinear];
    rotation.removedOnCompletion = NO;
    
    [self.layer addAnimation:rotation forKey:@"vinylRotation"];
}

- (void)stopSpinning {
    if (!self.isSpinning) return;
    
    self.isSpinning = NO;
    
    // 获取当前旋转角度
    CALayer *presentationLayer = self.layer.presentationLayer;
    if (presentationLayer) {
        CGFloat currentRotation = [[presentationLayer valueForKeyPath:@"transform.rotation.z"] floatValue];
        
        // 移除动画并设置到当前角度
        [self.layer removeAnimationForKey:@"vinylRotation"];
        self.layer.transform = CATransform3DMakeRotation(currentRotation, 0, 0, 1);
        
        // 缓出动画到最近的静止位置
        [UIView animateWithDuration:0.5
                              delay:0
             usingSpringWithDamping:0.8
              initialSpringVelocity:0.5
                            options:UIViewAnimationOptionCurveEaseOut
                         animations:^{
            self.layer.transform = CATransform3DIdentity;
        } completion:nil];
    } else {
        [self.layer removeAnimationForKey:@"vinylRotation"];
    }
}

- (void)pauseSpinning {
    if (!self.isSpinning) return;
    
    CFTimeInterval pausedTime = [self.layer convertTime:CACurrentMediaTime() fromLayer:nil];
    self.layer.speed = 0.0;
    self.layer.timeOffset = pausedTime;
    self.pausedTime = pausedTime;
}

- (void)resumeSpinning {
    if (!self.isSpinning) return;
    
    CFTimeInterval pausedTime = self.layer.timeOffset;
    self.layer.speed = 1.0;
    self.layer.timeOffset = 0.0;
    self.layer.beginTime = 0.0;
    CFTimeInterval timeSincePause = [self.layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
    self.layer.beginTime = timeSincePause;
}

#pragma mark - 外观更新

- (void)regenerateAppearance {
    [self regenerateAppearanceWithSeed:arc4random()];
}

- (void)regenerateAppearanceWithSeed:(NSUInteger)seed {
    self.currentSeed = seed;
    
    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    CGFloat labelSize = size * 0.38;
    
    [self applyRandomLabelAppearanceWithSeed:seed size:labelSize];
}

- (void)regenerateAppearanceWithSongName:(NSString *)songName {
    [self regenerateAppearanceWithSeed:[self seedFromString:songName]];
}

#pragma mark - 布局

- (void)layoutSubviews {
    [super layoutSubviews];
    
    CGFloat size = MIN(self.bounds.size.width, self.bounds.size.height);
    CGPoint center = CGPointMake(self.bounds.size.width / 2, self.bounds.size.height / 2);
    
    // 更新所有层的位置和大小
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    
    self.vinylLayer.bounds = CGRectMake(0, 0, size, size);
    self.vinylLayer.position = center;
    self.vinylLayer.cornerRadius = size / 2;
    
    self.groovesLayer.bounds = CGRectMake(0, 0, size, size);
    self.groovesLayer.position = center;
    
    self.glossLayer.bounds = CGRectMake(0, 0, size, size);
    self.glossLayer.position = center;
    self.glossLayer.cornerRadius = size / 2;
    
    CGFloat labelSize = size * 0.38;
    self.labelLayer.bounds = CGRectMake(0, 0, labelSize, labelSize);
    self.labelLayer.position = center;
    self.labelLayer.cornerRadius = labelSize / 2;
    
    [CATransaction commit];
}

#pragma mark - Setter

- (void)setGlossIntensity:(CGFloat)glossIntensity {
    _glossIntensity = MIN(1.0, MAX(0, glossIntensity));
    
    CGFloat intensity = _glossIntensity;
    self.glossLayer.colors = @[
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.8].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.3].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.5].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:0].CGColor,
        (id)[UIColor colorWithWhite:1.0 alpha:intensity * 0.8].CGColor,
    ];
}

- (void)setLabelColor:(UIColor *)labelColor {
    _labelColor = labelColor;
    [self regenerateAppearanceWithSeed:self.currentSeed];
}

- (void)setRotationsPerSecond:(CGFloat)rotationsPerSecond {
    _rotationsPerSecond = MAX(0.1, rotationsPerSecond);
    
    // 如果正在旋转，重新启动动画
    if (self.isSpinning) {
        [self.layer removeAnimationForKey:@"vinylRotation"];
        _isSpinning = NO;
        [self startSpinning];
    }
}

- (void)dealloc {
    [self.displayLink invalidate];
}

@end

