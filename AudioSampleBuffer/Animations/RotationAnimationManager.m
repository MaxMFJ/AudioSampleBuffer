//
//  RotationAnimationManager.m
//  AudioSampleBuffer
//
//

#import "RotationAnimationManager.h"

@interface RotationAnimationManager ()
@property (nonatomic, strong) NSMutableArray<UIView *> *managedViews;
@property (nonatomic, strong) NSMutableArray<CALayer *> *managedLayers;
@end

@implementation RotationAnimationManager

- (instancetype)initWithTargetView:(UIView *)targetView 
                      rotationType:(RotationType)rotationType 
                          duration:(NSTimeInterval)duration {
    if (self = [super initWithTargetView:targetView]) {
        _managedViews = [NSMutableArray array];
        _managedLayers = [NSMutableArray array];
        
        // 设置默认参数
        [self setAnimationParameters:@{
            @"rotations": @(3.0),
            @"duration": @(duration),
            @"rotationType": @(rotationType)
        }];
        
        if (targetView) {
            [_managedViews addObject:targetView];
        }
    }
    return self;
}

- (void)startAnimation {
    [super startAnimation];
    
    // 为所有管理的视图添加旋转动画
    for (UIView *view in self.managedViews) {
        [self addRotationAnimationToLayer:view.layer];
    }
    
    // 为所有管理的图层添加旋转动画
    for (CALayer *layer in self.managedLayers) {
        [self addRotationAnimationToLayer:layer];
    }
}

- (void)stopAnimation {
    [super stopAnimation];
    
    // 移除所有旋转动画
    for (UIView *view in self.managedViews) {
        [view.layer removeAnimationForKey:@"rotationAnimation"];
    }
    
    for (CALayer *layer in self.managedLayers) {
        [layer removeAnimationForKey:@"rotationAnimation"];
    }
}

- (void)pauseAnimation {
    [super pauseAnimation];
    
    // 使用 layer 的 speed 和 timeOffset 来暂停动画，保持当前位置
    for (UIView *view in self.managedViews) {
        [self pauseLayerAnimation:view.layer];
    }
    
    for (CALayer *layer in self.managedLayers) {
        [self pauseLayerAnimation:layer];
    }
}

- (void)resumeAnimation {
    [super resumeAnimation];
    
    // 恢复 layer 动画，从暂停位置继续
    for (UIView *view in self.managedViews) {
        [self resumeLayerAnimation:view.layer];
    }
    
    for (CALayer *layer in self.managedLayers) {
        [self resumeLayerAnimation:layer];
    }
}

- (void)pauseLayerAnimation:(CALayer *)layer {
    CFTimeInterval pausedTime = [layer convertTime:CACurrentMediaTime() fromLayer:nil];
    layer.speed = 0.0;
    layer.timeOffset = pausedTime;
}

- (void)resumeLayerAnimation:(CALayer *)layer {
    CFTimeInterval pausedTime = layer.timeOffset;
    layer.speed = 1.0;
    layer.timeOffset = 0.0;
    layer.beginTime = 0.0;
    CFTimeInterval timeSincePause = [layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
    layer.beginTime = timeSincePause;
}

- (void)setRotations:(CGFloat)rotations 
            duration:(NSTimeInterval)duration 
        rotationType:(RotationType)rotationType {
    [self setAnimationParameters:@{
        @"rotations": @(rotations),
        @"duration": @(duration),
        @"rotationType": @(rotationType)
    }];
}

- (void)addRotationAnimationsToViews:(NSArray<UIView *> *)views
                           rotations:(NSArray<NSNumber *> *)rotations
                           durations:(NSArray<NSNumber *> *)durations
                       rotationTypes:(NSArray<NSNumber *> *)rotationTypes {
    
    [self.managedViews addObjectsFromArray:views];
    
    for (NSInteger i = 0; i < views.count; i++) {
        UIView *view = views[i];
        
        // 获取参数，如果数组长度不够则使用默认值
        CGFloat rotation = i < rotations.count ? [rotations[i] floatValue] : [self.parameters[@"rotations"] floatValue];
        NSTimeInterval duration = i < durations.count ? [durations[i] doubleValue] : [self.parameters[@"duration"] doubleValue];
        RotationType rotationType = i < rotationTypes.count ? [rotationTypes[i] integerValue] : [self.parameters[@"rotationType"] integerValue];
        
        [self addRotationAnimationToLayer:view.layer 
                             withRotations:rotation 
                                  duration:duration 
                              rotationType:rotationType];
    }
}

- (void)addRotationAnimationToLayer:(CALayer *)layer {
    CGFloat rotations = [self.parameters[@"rotations"] floatValue];
    NSTimeInterval duration = [self.parameters[@"duration"] doubleValue];
    RotationType rotationType = [self.parameters[@"rotationType"] integerValue];
    
    [self addRotationAnimationToLayer:layer 
                        withRotations:rotations 
                             duration:duration 
                         rotationType:rotationType];
}

- (void)addRotationAnimationToLayer:(CALayer *)layer 
                      withRotations:(CGFloat)rotations 
                           duration:(NSTimeInterval)duration 
                       rotationType:(RotationType)rotationType {
    
    CABasicAnimation *rotationAnimation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotationAnimation.fromValue = @(0);
    
    // 🔧 修复：每次循环旋转一整圈 (2π)，这样循环时不会有跳跃感
    // rotations 参数现在表示"每 duration 秒旋转多少圈"
    // 为了实现无缝循环，我们让单次动画旋转一圈，并调整 duration 以达到期望的速度
    CGFloat absRotations = fabs(rotations);
    
    // 安全检查：防止除以零
    if (absRotations < 0.001) {
        absRotations = 1.0;
    }
    
    // 计算每圈需要的时间
    NSTimeInterval durationPerRotation = duration / absRotations;
    
    // 每次动画循环旋转一整圈 (2π)，方向由 rotationType 决定
    CGFloat singleRotationValue;
    switch (rotationType) {
        case RotationTypeClockwise:
            singleRotationValue = 2.0 * M_PI; // 顺时针一整圈
            break;
        case RotationTypeCounterClockwise:
            singleRotationValue = -2.0 * M_PI; // 逆时针一整圈
            break;
        case RotationTypeAlternating:
            singleRotationValue = 2.0 * M_PI; // 交替旋转逻辑保持顺时针
            break;
    }
    
    rotationAnimation.toValue = @(singleRotationValue);
    rotationAnimation.duration = durationPerRotation;
    rotationAnimation.repeatCount = MAXFLOAT;
    rotationAnimation.removedOnCompletion = NO;
    rotationAnimation.fillMode = kCAFillModeForwards;
    
    [layer addAnimation:rotationAnimation forKey:@"rotationAnimation"];
    
    // 添加到管理列表中
    if (![self.managedLayers containsObject:layer]) {
        [self.managedLayers addObject:layer];
    }
}

@end
