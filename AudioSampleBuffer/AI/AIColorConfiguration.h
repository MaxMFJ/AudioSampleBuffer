//
//  AIColorConfiguration.h
//  AudioSampleBuffer
//
//  AI 音乐分析配置数据模型
//

#import <Foundation/Foundation.h>
#import <simd/simd.h>

NS_ASSUME_NONNULL_BEGIN

/// 音乐情感类型
typedef NS_ENUM(NSInteger, MusicEmotion) {
    MusicEmotionCalm = 0,      // 平静
    MusicEmotionSad,           // 悲伤
    MusicEmotionHappy,         // 快乐
    MusicEmotionEnergetic,     // 活力
    MusicEmotionIntense        // 强烈
};

/// AI 颜色配置模型
@interface AIColorConfiguration : NSObject <NSCoding, NSSecureCoding>

// 歌曲信息
@property (nonatomic, copy) NSString *songName;
@property (nonatomic, copy) NSString *artist;
@property (nonatomic, copy) NSString *songIdentifier;  // 用于缓存的唯一标识

// 分析数据
@property (nonatomic, assign) NSInteger bpm;
@property (nonatomic, assign) MusicEmotion emotion;
@property (nonatomic, assign) float energy;         // 0-1
@property (nonatomic, assign) float danceability;   // 0-1
@property (nonatomic, assign) float valence;        // 情绪正负值 0-1

// 颜色方案（RGB，每个值 0-1）
@property (nonatomic, assign) simd_float3 atmosphereColor;
@property (nonatomic, assign) simd_float3 volumetricBeamColor;
@property (nonatomic, assign) simd_float3 topLightArrayColor;
@property (nonatomic, assign) simd_float3 laserFanBlueColor;
@property (nonatomic, assign) simd_float3 laserFanGreenColor;
@property (nonatomic, assign) simd_float3 rotatingBeamColor;
@property (nonatomic, assign) simd_float3 rotatingBeamExtraColor;
@property (nonatomic, assign) simd_float3 edgeLightColor;
@property (nonatomic, assign) simd_float3 coronaFilamentsColor;
@property (nonatomic, assign) simd_float3 pulseRingColor;

// 动画参数
@property (nonatomic, assign) float animationSpeed;      // 动画速度倍数，默认 1.0
@property (nonatomic, assign) float brightnessMultiplier;// 整体亮度，默认 1.0
@property (nonatomic, assign) float triggerSensitivity;  // 触发灵敏度，默认 1.0
@property (nonatomic, assign) float atmosphereIntensity; // 氛围强度，默认 0.45

// 来源标记
@property (nonatomic, assign) BOOL isLLMGenerated;       // YES=来自 DeepSeek 成功响应, NO=降级/本地生成

// 缓存时间
@property (nonatomic, strong) NSDate *cachedDate;

/// 从 JSON 字典创建配置
+ (instancetype)configurationFromJSON:(NSDictionary *)json;

/// 转换为 JSON 字典（用于缓存）
- (NSDictionary *)toJSON;

/// 默认配置（用于降级）
+ (instancetype)defaultConfiguration;

/// 根据情感生成默认颜色方案
+ (instancetype)configurationForEmotion:(MusicEmotion)emotion;

@end

NS_ASSUME_NONNULL_END
