//
//  RealtimeParameterTuner.m
//  AudioSampleBuffer
//

#import "RealtimeParameterTuner.h"

#pragma mark - EffectParameters

@implementation EffectParameters

+ (instancetype)defaultParameters {
    EffectParameters *params = [[EffectParameters alloc] init];
    params.animationSpeed = 1.0;
    params.brightness = 1.0;
    params.particleDensity = 1.0;
    params.colorSaturation = 1.0;
    params.beatReactivity = 0.8;
    params.motionBlur = 0.0;
    params.glowIntensity = 1.0;
    params.waveAmplitude = 1.0;
    return params;
}

+ (instancetype)parametersFromDictionary:(NSDictionary *)dict {
    EffectParameters *params = [EffectParameters defaultParameters];
    
    if (dict[@"animationSpeed"]) params.animationSpeed = [dict[@"animationSpeed"] floatValue];
    if (dict[@"brightness"]) params.brightness = [dict[@"brightness"] floatValue];
    if (dict[@"particleDensity"]) params.particleDensity = [dict[@"particleDensity"] floatValue];
    if (dict[@"colorSaturation"]) params.colorSaturation = [dict[@"colorSaturation"] floatValue];
    if (dict[@"beatReactivity"]) params.beatReactivity = [dict[@"beatReactivity"] floatValue];
    if (dict[@"motionBlur"]) params.motionBlur = [dict[@"motionBlur"] floatValue];
    if (dict[@"glowIntensity"]) params.glowIntensity = [dict[@"glowIntensity"] floatValue];
    if (dict[@"waveAmplitude"]) params.waveAmplitude = [dict[@"waveAmplitude"] floatValue];
    
    return params;
}

- (NSDictionary *)toDictionary {
    return @{
        @"animationSpeed": @(self.animationSpeed),
        @"brightness": @(self.brightness),
        @"particleDensity": @(self.particleDensity),
        @"colorSaturation": @(self.colorSaturation),
        @"beatReactivity": @(self.beatReactivity),
        @"motionBlur": @(self.motionBlur),
        @"glowIntensity": @(self.glowIntensity),
        @"waveAmplitude": @(self.waveAmplitude),
    };
}

- (id)copyWithZone:(NSZone *)zone {
    EffectParameters *copy = [[EffectParameters alloc] init];
    copy.animationSpeed = self.animationSpeed;
    copy.brightness = self.brightness;
    copy.particleDensity = self.particleDensity;
    copy.colorSaturation = self.colorSaturation;
    copy.beatReactivity = self.beatReactivity;
    copy.motionBlur = self.motionBlur;
    copy.glowIntensity = self.glowIntensity;
    copy.waveAmplitude = self.waveAmplitude;
    return copy;
}

@end

#pragma mark - TunerConfiguration

@implementation TunerConfiguration

+ (instancetype)defaultConfiguration {
    TunerConfiguration *config = [[TunerConfiguration alloc] init];
    config.speedMultiplierRange = 1.5;
    config.brightnessMultiplierRange = 0.5;
    config.beatFlashIntensity = 0.3;
    config.smoothingFactor = 0.3;
    config.enableBeatSync = YES;
    config.enableEnergyMapping = YES;
    config.enableSegmentAdjustment = YES;
    return config;
}

@end

#pragma mark - RealtimeParameterTuner

@interface RealtimeParameterTuner ()

@property (nonatomic, strong) EffectParameters *currentParameters;
@property (nonatomic, strong) EffectParameters *smoothedParameters;

// 节拍闪烁状态
@property (nonatomic, assign) float beatFlashValue;
@property (nonatomic, assign) NSTimeInterval lastBeatTime;

@end

@implementation RealtimeParameterTuner

+ (instancetype)sharedTuner {
    static RealtimeParameterTuner *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[RealtimeParameterTuner alloc] init];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];
    if (self) {
        _configuration = [TunerConfiguration defaultConfiguration];
        _baseParameters = [EffectParameters defaultParameters];
        _currentParameters = [EffectParameters defaultParameters];
        _smoothedParameters = [EffectParameters defaultParameters];
        _enabled = YES;
        _beatFlashValue = 0;
        _lastBeatTime = 0;
    }
    return self;
}

- (void)reset {
    self.currentParameters = [self.baseParameters copy];
    self.smoothedParameters = [self.baseParameters copy];
    self.beatFlashValue = 0;
}

- (void)setBaseParametersFromDictionary:(NSDictionary *)dict {
    self.baseParameters = [EffectParameters parametersFromDictionary:dict];
    [self reset];
}

#pragma mark - Tuning

- (EffectParameters *)tuneParametersWithFeatures:(AudioFeatures *)features {
    return [self tuneParametersWithFeatures:features baseParameters:self.baseParameters];
}

- (EffectParameters *)tuneParametersWithFeatures:(AudioFeatures *)features
                                  baseParameters:(EffectParameters *)base {
    if (!self.enabled) {
        return base;
    }
    
    EffectParameters *tuned = [base copy];
    
    // 1. 能量映射
    if (self.configuration.enableEnergyMapping) {
        [self applyEnergyMapping:tuned features:features];
    }
    
    // 2. 节拍同步
    if (self.configuration.enableBeatSync) {
        [self applyBeatSync:tuned features:features];
    }
    
    // 3. 段落调整
    if (self.configuration.enableSegmentAdjustment) {
        [self applySegmentAdjustment:tuned features:features];
    }
    
    // 4. 平滑处理
    [self applySmoothingToParameters:tuned];
    
    // 5. 限制范围
    [self clampParameters:tuned];
    
    self.currentParameters = tuned;
    return tuned;
}

#pragma mark - Energy Mapping

- (void)applyEnergyMapping:(EffectParameters *)params features:(AudioFeatures *)features {
    float energy = features.energy;
    float bassEnergy = features.bassEnergy;
    float highEnergy = features.highEnergy;
    
    // 动画速度：能量越高越快
    // 范围：0.5 + energy * 1.5 = [0.5, 2.0]
    float speedMultiplier = 0.5 + energy * self.configuration.speedMultiplierRange;
    params.animationSpeed = params.animationSpeed * speedMultiplier;
    
    // 亮度：能量影响亮度
    // 范围：0.7 + energy * 0.5 = [0.7, 1.2]
    float brightnessMultiplier = 0.7 + energy * self.configuration.brightnessMultiplierRange;
    params.brightness = params.brightness * brightnessMultiplier;
    
    // 粒子密度：高频能量影响
    params.particleDensity = params.particleDensity * (0.6 + highEnergy * 0.8);
    
    // 波形幅度：低频能量影响
    params.waveAmplitude = params.waveAmplitude * (0.5 + bassEnergy * 1.0);
    
    // 发光强度：整体能量影响
    params.glowIntensity = params.glowIntensity * (0.6 + energy * 0.8);
    
    // 运动模糊：高速时增加
    if (params.animationSpeed > 1.5) {
        params.motionBlur = MIN(1.0, (params.animationSpeed - 1.5) * 0.5);
    }
}

#pragma mark - Beat Sync

- (void)applyBeatSync:(EffectParameters *)params features:(AudioFeatures *)features {
    // 更新节拍闪烁值
    if (features.beatDetected) {
        self.beatFlashValue = 1.0;
        self.lastBeatTime = features.timestamp;
    } else {
        // 衰减
        float decay = 0.85;
        self.beatFlashValue *= decay;
        if (self.beatFlashValue < 0.01) {
            self.beatFlashValue = 0;
        }
    }
    
    // 应用节拍响应
    float beatIntensity = self.configuration.beatFlashIntensity * params.beatReactivity;
    
    // 节拍时增加亮度
    params.brightness += self.beatFlashValue * beatIntensity;
    
    // 节拍时增加发光
    params.glowIntensity += self.beatFlashValue * beatIntensity * 0.5;
    
    // 节拍时短暂加速
    params.animationSpeed += self.beatFlashValue * 0.2;
}

#pragma mark - Segment Adjustment

- (void)applySegmentAdjustment:(EffectParameters *)params features:(AudioFeatures *)features {
    switch (features.currentSegment) {
        case MusicSegmentIntro:
            // 前奏：渐进式增强
            params.brightness *= 0.8;
            params.particleDensity *= 0.7;
            break;
            
        case MusicSegmentVerse:
            // 主歌：保持稳定
            break;
            
        case MusicSegmentChorus:
            // 副歌/高潮：全面增强
            params.brightness *= 1.2;
            params.particleDensity *= 1.5;
            params.glowIntensity *= 1.3;
            params.animationSpeed *= 1.1;
            params.colorSaturation *= 1.2;
            break;
            
        case MusicSegmentBridge:
            // 过渡：轻微变化
            params.animationSpeed *= 0.9;
            break;
            
        case MusicSegmentOutro:
            // 尾奏：渐弱
            params.brightness *= 0.7;
            params.particleDensity *= 0.6;
            params.animationSpeed *= 0.7;
            break;
            
        default:
            break;
    }
}

#pragma mark - Smoothing

- (void)applySmoothingToParameters:(EffectParameters *)params {
    float alpha = self.configuration.smoothingFactor;
    float oneMinusAlpha = 1.0 - alpha;
    
    params.animationSpeed = alpha * params.animationSpeed + oneMinusAlpha * self.smoothedParameters.animationSpeed;
    params.brightness = alpha * params.brightness + oneMinusAlpha * self.smoothedParameters.brightness;
    params.particleDensity = alpha * params.particleDensity + oneMinusAlpha * self.smoothedParameters.particleDensity;
    params.colorSaturation = alpha * params.colorSaturation + oneMinusAlpha * self.smoothedParameters.colorSaturation;
    params.glowIntensity = alpha * params.glowIntensity + oneMinusAlpha * self.smoothedParameters.glowIntensity;
    params.waveAmplitude = alpha * params.waveAmplitude + oneMinusAlpha * self.smoothedParameters.waveAmplitude;
    params.motionBlur = alpha * params.motionBlur + oneMinusAlpha * self.smoothedParameters.motionBlur;
    
    self.smoothedParameters = [params copy];
}

#pragma mark - Clamping

- (void)clampParameters:(EffectParameters *)params {
    params.animationSpeed = MAX(0.1, MIN(3.0, params.animationSpeed));
    params.brightness = MAX(0.1, MIN(2.0, params.brightness));
    params.particleDensity = MAX(0.1, MIN(3.0, params.particleDensity));
    params.colorSaturation = MAX(0.0, MIN(2.0, params.colorSaturation));
    params.beatReactivity = MAX(0.0, MIN(2.0, params.beatReactivity));
    params.motionBlur = MAX(0.0, MIN(1.0, params.motionBlur));
    params.glowIntensity = MAX(0.0, MIN(2.0, params.glowIntensity));
    params.waveAmplitude = MAX(0.1, MIN(3.0, params.waveAmplitude));
}

@end
