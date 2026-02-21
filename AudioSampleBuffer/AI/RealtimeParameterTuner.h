//
//  RealtimeParameterTuner.h
//  AudioSampleBuffer
//
//  实时参数调谐器 - 根据音频特征动态微调特效参数
//

#import <Foundation/Foundation.h>
#import "AudioFeatureExtractor.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 特效参数模型

@interface EffectParameters : NSObject <NSCopying>

@property (nonatomic, assign) float animationSpeed;       // 动画速度倍率 [0.1-3.0]
@property (nonatomic, assign) float brightness;           // 亮度 [0.1-2.0]
@property (nonatomic, assign) float particleDensity;      // 粒子密度 [0.1-3.0]
@property (nonatomic, assign) float colorSaturation;      // 色彩饱和度 [0.0-2.0]
@property (nonatomic, assign) float beatReactivity;       // 节拍响应强度 [0.0-2.0]
@property (nonatomic, assign) float motionBlur;           // 运动模糊 [0.0-1.0]
@property (nonatomic, assign) float glowIntensity;        // 发光强度 [0.0-2.0]
@property (nonatomic, assign) float waveAmplitude;        // 波形幅度 [0.1-3.0]

+ (instancetype)defaultParameters;
+ (instancetype)parametersFromDictionary:(NSDictionary *)dict;
- (NSDictionary *)toDictionary;

@end

#pragma mark - 调谐配置

@interface TunerConfiguration : NSObject

@property (nonatomic, assign) float speedMultiplierRange;     // 速度调节范围 (default: 1.5)
@property (nonatomic, assign) float brightnessMultiplierRange;// 亮度调节范围 (default: 0.5)
@property (nonatomic, assign) float beatFlashIntensity;       // 节拍闪烁强度 (default: 0.3)
@property (nonatomic, assign) float smoothingFactor;          // 平滑因子 [0-1] (default: 0.3)
@property (nonatomic, assign) BOOL enableBeatSync;            // 是否启用节拍同步 (default: YES)
@property (nonatomic, assign) BOOL enableEnergyMapping;       // 是否启用能量映射 (default: YES)
@property (nonatomic, assign) BOOL enableSegmentAdjustment;   // 是否启用段落调整 (default: YES)

+ (instancetype)defaultConfiguration;

@end

#pragma mark - 实时参数调谐器

@interface RealtimeParameterTuner : NSObject

/// 单例
+ (instancetype)sharedTuner;

/// 调谐配置
@property (nonatomic, strong) TunerConfiguration *configuration;

/// 基础参数（调谐的基准）
@property (nonatomic, strong) EffectParameters *baseParameters;

/// 当前调谐后的参数
@property (nonatomic, strong, readonly) EffectParameters *currentParameters;

/// 是否启用调谐
@property (nonatomic, assign) BOOL enabled;

#pragma mark - 调谐方法

/// 根据音频特征调谐参数
/// @param features 当前音频特征
/// @return 调谐后的参数
- (EffectParameters *)tuneParametersWithFeatures:(AudioFeatures *)features;

/// 根据音频特征和基础参数调谐
/// @param features 当前音频特征
/// @param base 基础参数
/// @return 调谐后的参数
- (EffectParameters *)tuneParametersWithFeatures:(AudioFeatures *)features
                                  baseParameters:(EffectParameters *)base;

/// 重置到基础参数
- (void)reset;

/// 设置新的基础参数
- (void)setBaseParametersFromDictionary:(NSDictionary *)dict;

@end

NS_ASSUME_NONNULL_END
