//
//  RhythmColorMaskEffect.m
//

#import "RhythmColorMaskEffect.h"

@interface RhythmColorMaskEffect ()
@property (nonatomic, assign) CGFloat intensity;       // 0..1，beat 后衰减
@property (nonatomic, assign) CGPoint offset;          // 当前位移
@property (nonatomic, assign) NSInteger hueIndex;      // 色循环索引
@end

@implementation RhythmColorMaskEffect

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];
    if (self) {
        self.userInteractionEnabled = NO;
        self.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
        self.alpha = 0.0;
        self.backgroundColor = [self colorForIndex:0 style:RhythmColorMaskStyleHueCycle];
        _style = RhythmColorMaskStyleHueCycle;
        _maxAlpha = 0.0;
        _shiftMax = 0.0;
        _intensity = 0.0;
        _offset = CGPointZero;
        _hueIndex = 0;
    }
    return self;
}

#pragma mark - Color palette

- (UIColor *)colorForIndex:(NSInteger)idx style:(RhythmColorMaskStyle)style {
    switch (style) {
        case RhythmColorMaskStyleWarmCool: {
            switch (idx % 2) {
                case 0:  return [UIColor colorWithRed:0.95 green:0.30 blue:0.20 alpha:1.0]; // 暖红
                default: return [UIColor colorWithRed:0.20 green:0.60 blue:0.95 alpha:1.0]; // 冷蓝
            }
        }
        case RhythmColorMaskStyleNeon: {
            switch (idx % 3) {
                case 0:  return [UIColor colorWithRed:0.95 green:0.20 blue:0.85 alpha:1.0]; // 粉
                case 1:  return [UIColor colorWithRed:0.20 green:0.95 blue:0.95 alpha:1.0]; // 青
                default: return [UIColor colorWithRed:0.50 green:0.20 blue:0.95 alpha:1.0]; // 紫
            }
        }
        case RhythmColorMaskStyleHueCycle:
        default: {
            switch (idx % 6) {
                case 0:  return [UIColor colorWithRed:0.95 green:0.20 blue:0.30 alpha:1.0]; // 红
                case 1:  return [UIColor colorWithRed:0.20 green:0.55 blue:0.95 alpha:1.0]; // 蓝
                case 2:  return [UIColor colorWithRed:0.95 green:0.50 blue:0.10 alpha:1.0]; // 橙
                case 3:  return [UIColor colorWithRed:0.30 green:0.85 blue:0.55 alpha:1.0]; // 青绿
                case 4:  return [UIColor colorWithRed:0.75 green:0.25 blue:0.85 alpha:1.0]; // 紫
                default: return [UIColor colorWithRed:0.95 green:0.80 blue:0.20 alpha:1.0]; // 黄
            }
        }
    }
}

#pragma mark - Public API

- (void)triggerOnBeatWithStrongMix:(float)strongMix axis:(NSInteger)axis {
    if (self.maxAlpha < 0.005) return;

    self.hueIndex = self.hueIndex + 1;
    self.backgroundColor = [self colorForIndex:self.hueIndex style:self.style];

    self.intensity = (CGFloat)(0.85 + 0.15 * strongMix);

    CGFloat dir = (self.hueIndex % 2 == 0) ? 1.0 : -1.0;
    CGFloat amp = self.shiftMax * (CGFloat)(0.55 + 0.45 * strongMix);
    if (axis == 0) {
        self.offset = CGPointMake(dir * amp, 0);
    } else {
        self.offset = CGPointMake(0, dir * amp);
    }
}

- (void)tickWithDelta:(CFTimeInterval)dt {
    if (self.maxAlpha < 0.005) {
        if (self.alpha > 0.0 || !CGAffineTransformIsIdentity(self.transform)) {
            [CATransaction begin];
            [CATransaction setDisableActions:YES];
            self.alpha = 0.0;
            self.transform = CGAffineTransformIdentity;
            [CATransaction commit];
        }
        self.intensity = 0.0;
        self.offset = CGPointZero;
        return;
    }

    // alpha 衰减 ~110ms 半衰期
    self.intensity *= exp(-6.0 * dt);
    if (self.intensity < 0.005) self.intensity = 0.0;

    // 位移衰减 ~105ms 半衰期
    CGFloat decay = exp(-6.5 * dt);
    CGPoint p = self.offset;
    p.x *= decay;
    p.y *= decay;
    if (fabs(p.x) < 0.05) p.x = 0.0;
    if (fabs(p.y) < 0.05) p.y = 0.0;
    self.offset = p;

    CGFloat alpha = self.intensity * self.maxAlpha;
    if (alpha < 0.001) alpha = 0.0;
    if (alpha > self.maxAlpha) alpha = self.maxAlpha;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.alpha = alpha;
    self.transform = CGAffineTransformMakeTranslation(p.x, p.y);
    [CATransaction commit];
}

- (void)reset {
    self.intensity = 0.0;
    self.offset = CGPointZero;
    self.hueIndex = 0;
    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.alpha = 0.0;
    self.transform = CGAffineTransformIdentity;
    [CATransaction commit];
}

@end
