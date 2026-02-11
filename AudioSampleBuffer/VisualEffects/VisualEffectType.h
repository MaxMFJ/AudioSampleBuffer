//
//  VisualEffectType.h
//  AudioSampleBuffer
//
//  高端视觉效果类型定义
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/**
 * 视觉效果类型枚举
 */
typedef NS_ENUM(NSUInteger, VisualEffectType) {
    // 基础效果
    VisualEffectTypeClassicSpectrum = 0,    // 经典频谱
    VisualEffectTypeCircularWave,           // 环形波浪
    VisualEffectTypeParticleFlow,           // 粒子流
    
    // Metal高端效果
    VisualEffectTypeNeonGlow,               // 霓虹发光
    VisualEffectType3DWaveform,             // 3D波形
    VisualEffectTypeFluidSimulation,        // 流体模拟
    VisualEffectTypeQuantumField,           // 量子场
    VisualEffectTypeHolographic,            // 全息效果
    VisualEffectTypeCyberPunk,              // 赛博朋克
    VisualEffectTypeAudioReactive3D,        // 音频响应3D
    
    // 创意效果
    VisualEffectTypeGalaxy,                 // 星系
    VisualEffectTypeLightning,              // 闪电
    VisualEffectTypeFireworks,              // 漂浮光点（Floating Lights）
    VisualEffectTypeLiquidMetal,            // 液态金属
    VisualEffectTypeGeometricMorph,         // 几何变形
    VisualEffectTypeFractalPattern,         // 分形图案
    
    // 实验性效果
    VisualEffectTypeAuroraRipples,          // 极光波纹
    VisualEffectTypeStarVortex,             // 恒星涡旋
    VisualEffectTypeNeonSpringLines,        // 霓虹弹簧竖线
    VisualEffectTypeCherryBlossomSnow,      // 樱花飘雪
    VisualEffectTypeTyndallBeam,            // 丁达尔效应/舞台灯光
    
    // 数量
    VisualEffectTypeCount
};

/**
 * 效果分类
 */
typedef NS_ENUM(NSUInteger, EffectCategory) {
    EffectCategoryBasic = 0,                // 基础效果
    EffectCategoryMetal,                    // Metal效果
    EffectCategoryCreative,                 // 创意效果
    EffectCategoryExperimental,             // 实验性效果
};

/**
 * 效果性能等级
 */
typedef NS_ENUM(NSUInteger, PerformanceLevel) {
    PerformanceLevelLow = 0,                // 低性能要求
    PerformanceLevelMedium,                 // 中等性能要求
    PerformanceLevelHigh,                   // 高性能要求
    PerformanceLevelExtreme,                // 极致性能要求
};

/**
 * 视觉效果描述信息
 */
@interface VisualEffectInfo : NSObject

@property (nonatomic, assign) VisualEffectType type;
@property (nonatomic, copy) NSString *name;
@property (nonatomic, copy) NSString *effectDescription;
@property (nonatomic, assign) EffectCategory category;
@property (nonatomic, assign) PerformanceLevel performanceLevel;
@property (nonatomic, copy) NSString *previewImageName;
@property (nonatomic, assign) BOOL requiresMetal;
@property (nonatomic, assign) BOOL supportsCustomization;

+ (instancetype)effectWithType:(VisualEffectType)type 
                          name:(NSString *)name 
                   description:(NSString *)effectDescription 
                      category:(EffectCategory)category 
              performanceLevel:(PerformanceLevel)performanceLevel;

@end

/**
 * 视觉效果管理器
 */
@interface VisualEffectRegistry : NSObject

+ (instancetype)sharedRegistry;

/**
 * 获取所有效果信息
 */
- (NSArray<VisualEffectInfo *> *)allEffects;

/**
 * 根据分类获取效果
 */
- (NSArray<VisualEffectInfo *> *)effectsForCategory:(EffectCategory)category;

/**
 * 获取效果信息
 */
- (VisualEffectInfo *)effectInfoForType:(VisualEffectType)type;

/**
 * 检查设备是否支持指定效果
 */
- (BOOL)deviceSupportsEffect:(VisualEffectType)type;

@end

NS_ASSUME_NONNULL_END
