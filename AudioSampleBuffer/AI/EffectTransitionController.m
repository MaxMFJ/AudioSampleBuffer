//
//  EffectTransitionController.m
//  AudioSampleBuffer
//

#import "EffectTransitionController.h"

#pragma mark - TransitionConfiguration

@implementation TransitionConfiguration

+ (instancetype)defaultConfiguration {
    return [self configurationWithType:TransitionTypeCrossfade duration:0.5];
}

+ (instancetype)configurationWithType:(TransitionType)type duration:(NSTimeInterval)duration {
    TransitionConfiguration *config = [[TransitionConfiguration alloc] init];
    config.type = type;
    config.duration = duration;
    config.easeInFactor = 0.3;
    config.easeOutFactor = 0.3;
    config.waitForBeat = (type == TransitionTypeBeatSync);
    return config;
}

@end

#pragma mark - EffectTransitionController

@interface EffectTransitionController ()

@property (nonatomic, assign) TransitionState state;
@property (nonatomic, assign) float progress;
@property (nonatomic, assign) VisualEffectType fromEffect;
@property (nonatomic, assign) VisualEffectType toEffect;

@property (nonatomic, strong) TransitionConfiguration *currentConfig;
@property (nonatomic, assign) NSTimeInterval elapsedTime;
@property (nonatomic, assign) BOOL beatDetectedDuringWait;

@end

@implementation EffectTransitionController

+ (instancetype)sharedController {
    static EffectTransitionController *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[EffectTransitionController alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _state = TransitionStateIdle;
        _progress = 0;
        _fromEffect = VisualEffectTypeClassicSpectrum;
        _toEffect = VisualEffectTypeClassicSpectrum;
        _elapsedTime = 0;
        _beatDetectedDuringWait = NO;
    }
    return self;
}

- (BOOL)isTransitioning {
    return self.state == TransitionStateTransitioning || self.state == TransitionStateWaitingBeat;
}

#pragma mark - Transition Control

- (void)transitionFromEffect:(VisualEffectType)from
                    toEffect:(VisualEffectType)to
              transitionType:(TransitionType)type
                    duration:(NSTimeInterval)duration {
    
    TransitionConfiguration *config = [TransitionConfiguration configurationWithType:type duration:duration];
    [self transitionFromEffect:from toEffect:to configuration:config];
}

- (void)transitionFromEffect:(VisualEffectType)from
                    toEffect:(VisualEffectType)to
               configuration:(TransitionConfiguration *)config {
    
    if (from == to) {
        NSLog(@"⚠️ 源特效和目标特效相同，跳过过渡");
        return;
    }
    
    // 取消正在进行的过渡
    if (self.isTransitioning) {
        [self cancelTransition];
    }
    
    self.fromEffect = from;
    self.toEffect = to;
    self.currentConfig = config;
    self.progress = 0;
    self.elapsedTime = 0;
    self.beatDetectedDuringWait = NO;
    
    // 通知即将开始
    if ([self.delegate respondsToSelector:@selector(transitionController:willStartTransitionFromEffect:toEffect:)]) {
        [self.delegate transitionController:self willStartTransitionFromEffect:from toEffect:to];
    }
    
    if (config.type == TransitionTypeBeatSync && config.waitForBeat) {
        self.state = TransitionStateWaitingBeat;
        NSLog(@"⏱️ 等待节拍开始过渡: %lu -> %lu", (unsigned long)from, (unsigned long)to);
    } else if (config.type == TransitionTypeInstant) {
        self.progress = 1.0;
        self.state = TransitionStateCompleted;
        [self notifyCompletion];
    } else {
        self.state = TransitionStateTransitioning;
        NSLog(@"🔄 开始过渡: %lu -> %lu (%.2fs)", (unsigned long)from, (unsigned long)to, config.duration);
    }
}

- (float)updateWithDeltaTime:(NSTimeInterval)deltaTime {
    switch (self.state) {
        case TransitionStateIdle:
        case TransitionStateCompleted:
            return (self.state == TransitionStateCompleted) ? 1.0 : 0.0;
            
        case TransitionStateWaitingBeat:
            // 等待节拍
            if (self.beatDetectedDuringWait) {
                self.state = TransitionStateTransitioning;
                self.beatDetectedDuringWait = NO;
                NSLog(@"🎵 检测到节拍，开始过渡");
            }
            return 0.0;
            
        case TransitionStateTransitioning:
            return [self updateTransition:deltaTime];
    }
}

- (float)updateTransition:(NSTimeInterval)deltaTime {
    self.elapsedTime += deltaTime;
    
    if (self.currentConfig.duration > 0) {
        self.progress = MIN(1.0, self.elapsedTime / self.currentConfig.duration);
    } else {
        self.progress = 1.0;
    }
    
    // 通知进度更新
    if ([self.delegate respondsToSelector:@selector(transitionController:didUpdateProgress:fromEffect:toEffect:)]) {
        [self.delegate transitionController:self
                        didUpdateProgress:self.progress
                               fromEffect:self.fromEffect
                                 toEffect:self.toEffect];
    }
    
    // 检查是否完成
    if (self.progress >= 1.0) {
        self.state = TransitionStateCompleted;
        [self notifyCompletion];
    }
    
    return [self easedProgress];
}

- (void)notifyBeatDetected {
    if (self.state == TransitionStateWaitingBeat) {
        self.beatDetectedDuringWait = YES;
    }
}

- (void)cancelTransition {
    if (self.isTransitioning) {
        NSLog(@"❌ 取消过渡");
        self.state = TransitionStateIdle;
        self.progress = 0;
        self.elapsedTime = 0;
    }
}

- (void)completeImmediately {
    if (self.isTransitioning) {
        self.progress = 1.0;
        self.state = TransitionStateCompleted;
        [self notifyCompletion];
    }
}

- (void)notifyCompletion {
    NSLog(@"✅ 过渡完成: -> %lu", (unsigned long)self.toEffect);
    
    if ([self.delegate respondsToSelector:@selector(transitionController:didCompleteTransitionToEffect:)]) {
        [self.delegate transitionController:self didCompleteTransitionToEffect:self.toEffect];
    }
}

#pragma mark - Blend Calculations

- (void)getBlendWeightsForEffectA:(float *)effectA effectB:(float *)effectB {
    float eased = [self easedProgress];
    
    switch (self.currentConfig.type) {
        case TransitionTypeCrossfade:
        case TransitionTypeDissolve:
            // 线性混合
            *effectA = 1.0 - eased;
            *effectB = eased;
            break;
            
        case TransitionTypeWipe:
            // 擦除效果（A完全消失后B才出现）
            if (eased < 0.5) {
                *effectA = 1.0 - eased * 2;
                *effectB = 0;
            } else {
                *effectA = 0;
                *effectB = (eased - 0.5) * 2;
            }
            break;
            
        case TransitionTypeZoom:
            // 缩放过渡（中间点切换）
            if (eased < 0.5) {
                *effectA = 1.0;
                *effectB = 0;
            } else {
                *effectA = 0;
                *effectB = 1.0;
            }
            break;
            
        case TransitionTypeBeatSync:
        case TransitionTypeInstant:
        default:
            *effectA = 1.0 - eased;
            *effectB = eased;
            break;
    }
}

- (float)easedProgress {
    if (!self.currentConfig) {
        return self.progress;
    }
    
    float p = self.progress;
    float easeIn = self.currentConfig.easeInFactor;
    float easeOut = self.currentConfig.easeOutFactor;
    
    // 使用 smoothstep 缓动
    // ease-in-out: t * t * (3 - 2 * t)
    // 可调节的缓动：结合 easeIn 和 easeOut 因子
    
    if (easeIn > 0 && easeOut > 0) {
        // 缓入缓出
        return p * p * (3.0 - 2.0 * p);
    } else if (easeIn > 0) {
        // 仅缓入
        return p * p;
    } else if (easeOut > 0) {
        // 仅缓出
        return 1.0 - (1.0 - p) * (1.0 - p);
    }
    
    return p;
}

@end
