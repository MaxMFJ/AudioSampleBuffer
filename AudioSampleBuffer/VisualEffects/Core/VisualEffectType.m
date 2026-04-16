//
//  VisualEffectType.m
//  AudioSampleBuffer
//
//  高端视觉效果类型实现
//

#import "VisualEffectType.h"
#import <Metal/Metal.h>

@implementation VisualEffectInfo

+ (instancetype)effectWithType:(VisualEffectType)type 
                          name:(NSString *)name 
                   description:(NSString *)effectDescription 
                      category:(EffectCategory)category 
              performanceLevel:(PerformanceLevel)performanceLevel {
    VisualEffectInfo *info = [[VisualEffectInfo alloc] init];
    info.type = type;
    info.name = name;
    info.effectDescription = effectDescription;
    info.category = category;
    info.performanceLevel = performanceLevel;
    info.requiresMetal = (category == EffectCategoryMetal);
    info.supportsCustomization = YES;
    return info;
}

@end

@interface VisualEffectRegistry ()
@property (nonatomic, strong) NSArray<VisualEffectInfo *> *effects;
@end

@implementation VisualEffectRegistry

+ (instancetype)sharedRegistry {
    static VisualEffectRegistry *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[VisualEffectRegistry alloc] init];
        [instance setupEffects];
    });
    return instance;
}

- (void)setupEffects {
    NSMutableArray *effects = [NSMutableArray array];
    
    // 基础效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeClassicSpectrum
                                                   name:@"经典频谱"
                                            description:@"经典的频谱柱状图显示"
                                               category:EffectCategoryBasic
                                       performanceLevel:PerformanceLevelLow]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeCircularWave
                                                   name:@"环形波浪"
                                            description:@"圆形波浪扩散效果"
                                               category:EffectCategoryBasic
                                       performanceLevel:PerformanceLevelMedium]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeParticleFlow
                                                   name:@"粒子流"
                                            description:@"动态粒子流动效果"
                                               category:EffectCategoryBasic
                                       performanceLevel:PerformanceLevelMedium]];
    
    // Metal高端效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeNeonGlow
                                                   name:@"霓虹发光"
                                            description:@"炫酷的霓虹灯光效果"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectType3DWaveform
                                                   name:@"3D波形"
                                            description:@"立体的3D音频波形"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeFluidSimulation
                                                   name:@"流体模拟"
                                            description:@"真实的流体物理模拟"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelExtreme]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeQuantumField
                                                   name:@"量子场"
                                            description:@"神秘的量子场能量效果"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelExtreme]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeHolographic
                                                   name:@"全息效果"
                                            description:@"科幻的全息投影效果"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeCyberPunk
                                                   name:@"赛博朋克"
                                            description:@"未来主义的赛博朋克风格"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeAudioReactive3D
                                                   name:@"音频响应3D"
                                            description:@"立体音频响应几何体"
                                               category:EffectCategoryMetal
                                       performanceLevel:PerformanceLevelExtreme]];
    
    // 创意效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeGalaxy
                                                   name:@"星系"
                                            description:@"绚丽的星系旋转效果"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeLightning
                                                   name:@"闪电"
                                            description:@"电闪雷鸣的能量效果"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelMedium]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeFireworks
                                                   name:@"漂浮光点"
                                            description:@"温暖柔和的光球缓慢漂浮，适合抒情慢歌"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelLow]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeLiquidMetal
                                                   name:@"液态金属"
                                            description:@"流动的液态金属质感"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelExtreme]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeGeometricMorph
                                                   name:@"几何变形"
                                            description:@"动态几何形状变形"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeFractalPattern
                                                   name:@"分形图案"
                                            description:@"复杂的分形数学图案"
                                               category:EffectCategoryCreative
                                       performanceLevel:PerformanceLevelHigh]];

    VisualEffectInfo *chromaticCaustics = [VisualEffectInfo effectWithType:VisualEffectTypeChromaticCaustics
                                                                      name:@"光绘焦散"
                                                               description:@"长曝光般的棱镜光带与水纹焦散交织，随节拍呼吸与绽放"
                                                                  category:EffectCategoryCreative
                                                          performanceLevel:PerformanceLevelHigh];
    chromaticCaustics.requiresMetal = YES;
    [effects addObject:chromaticCaustics];
    
    // 实验性效果
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeAuroraRipples
                                                   name:@"极光波纹"
                                            description:@"北极光般的流动光带与音频驱动的多层波纹效果"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeStarVortex
                                                   name:@"恒星涡旋"
                                            description:@"中心恒星日冕爆发与旋转的等离子云气效果"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeNeonSpringLines
                                                   name:@"霓虹弹簧竖线"
                                            description:@"发光霓虹竖线随音频产生弹簧动画效果"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelMedium]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeCherryBlossomSnow
                                                   name:@"樱花飘雪"
                                            description:@"如梦似幻的粉色樱花花瓣随风飘落，柔光弥漫的春日梦境"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeTyndallBeam
                                                   name:@"丁达尔光束"
                                            description:@"舞台灯光照射感，随频谱高度解锁多层光柱与尘埃感"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelHigh]];
    
    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeNeuralResonance
                                                   name:@"神经共振"
                                            description:@"仿神经网络拓扑结构，节点随音频脉动并向相邻节点传递信号"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelMedium]];

    [effects addObject:[VisualEffectInfo effectWithType:VisualEffectTypeWormholeDrive
                                                   name:@"虫洞穿梭"
                                            description:@"深空虫洞隧道中，星尘随音频自原点凝成光柱并向屏幕穿梭冲刺"
                                               category:EffectCategoryExperimental
                                       performanceLevel:PerformanceLevelHigh]];

    VisualEffectInfo *prismResonance = [VisualEffectInfo effectWithType:VisualEffectTypePrismResonance
                                                                   name:@"棱镜共振"
                                                            description:@"梦幻漂浮的多层棱镜随频段闪烁、变圆或化作心形，带有远近层次与柔光氛围"
                                                               category:EffectCategoryExperimental
                                                       performanceLevel:PerformanceLevelMedium];
    prismResonance.requiresMetal = YES;
    [effects addObject:prismResonance];

    VisualEffectInfo *visualLyricsTunnel = [VisualEffectInfo effectWithType:VisualEffectTypeVisualLyricsTunnel
                                                                       name:@"视觉歌词"
                                                                description:@"歌词以 45° 斜向穿梭入场，多行交错缓慢滑动，并根据 AI 情绪分析切换发光色彩"
                                                                   category:EffectCategoryExperimental
                                                           performanceLevel:PerformanceLevelHigh];
    visualLyricsTunnel.requiresMetal = YES;
    [effects addObject:visualLyricsTunnel];
    
    self.effects = [effects copy];
}

- (NSArray<VisualEffectInfo *> *)allEffects {
    return self.effects;
}

- (NSArray<VisualEffectInfo *> *)effectsForCategory:(EffectCategory)category {
    return [self.effects filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(VisualEffectInfo *effect, NSDictionary *bindings) {
        return effect.category == category;
    }]];
}

- (VisualEffectInfo *)effectInfoForType:(VisualEffectType)type {
    for (VisualEffectInfo *effect in self.effects) {
        if (effect.type == type) {
            return effect;
        }
    }
    return nil;
}

- (BOOL)deviceSupportsEffect:(VisualEffectType)type {
    VisualEffectInfo *info = [self effectInfoForType:type];
    if (!info) return NO;
    
    // 检查Metal支持
    if (info.requiresMetal) {
        id<MTLDevice> device = MTLCreateSystemDefaultDevice();
        return device != nil;
    }
    
    return YES;
}

@end
