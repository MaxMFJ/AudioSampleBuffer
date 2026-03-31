//
//  MetalRenderer.h
//  AudioSampleBuffer
//
//  Metal高性能渲染器
//

#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <MetalKit/MetalKit.h>
#import <QuartzCore/QuartzCore.h>
#import "../Core/VisualEffectType.h"

NS_ASSUME_NONNULL_BEGIN

@protocol MetalRendererDelegate <NSObject>
@optional
- (void)metalRenderer:(id)renderer didFinishFrame:(NSTimeInterval)frameTime;
- (void)metalRenderer:(id)renderer didEncounterError:(NSError *)error;
@end

/**
 * Metal渲染器协议
 */
@protocol MetalRenderer <NSObject>

@property (nonatomic, weak) id<MetalRendererDelegate> delegate;
@property (nonatomic, strong, readonly) id<MTLDevice> device;
@property (nonatomic, strong, readonly) MTKView *metalView;

/**
 * 更新频谱数据
 */
- (void)updateSpectrumData:(NSArray<NSNumber *> *)spectrumData;

/**
 * 设置渲染参数
 */
- (void)setRenderParameters:(NSDictionary *)parameters;

/**
 * 开始渲染
 */
- (void)startRendering;

/**
 * 停止渲染
 */
- (void)stopRendering;

/**
 * 暂停渲染
 */
- (void)pauseRendering;

/**
 * 恢复渲染
 */
- (void)resumeRendering;

@end

/**
 * Metal渲染器基类
 */
@interface BaseMetalRenderer : NSObject <MetalRenderer, MTKViewDelegate>

@property (nonatomic, weak) id<MetalRendererDelegate> delegate;
@property (nonatomic, strong, readonly) id<MTLDevice> device;
@property (nonatomic, strong, readonly) MTKView *metalView;
@property (nonatomic, strong, readonly) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong, readonly) id<MTLLibrary> defaultLibrary;

@property (nonatomic, assign) BOOL isRendering;
@property (atomic, strong) NSArray<NSNumber *> *currentSpectrumData; // 使用atomic保证线程安全
@property (nonatomic, strong) NSMutableDictionary *renderParameters;
@property (nonatomic, assign) CGSize actualContainerSize; // 实际屏幕容器尺寸（用于计算缩放）

/**
 * 初始化渲染器
 */
- (instancetype)initWithMetalView:(MTKView *)metalView;

/**
 * 子类需要重写的方法
 */
- (void)setupPipeline;
- (void)updateUniforms:(NSTimeInterval)time;
- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder;

/**
 * 辅助方法
 */
- (id<MTLBuffer>)createBufferWithData:(const void *)data length:(NSUInteger)length;
- (id<MTLTexture>)createTextureWithWidth:(NSUInteger)width height:(NSUInteger)height;
- (id<MTLTexture>)createRenderTargetTextureWithWidth:(NSUInteger)width height:(NSUInteger)height;

@end

/**
 * 霓虹发光渲染器
 */
@interface NeonGlowRenderer : BaseMetalRenderer
@end

/**
 * 3D波形渲染器
 */
@interface Waveform3DRenderer : BaseMetalRenderer
@end

/**
 * 流体模拟渲染器
 */
@interface FluidSimulationRenderer : BaseMetalRenderer
@end

/**
 * 量子场渲染器
 */
@interface QuantumFieldRenderer : BaseMetalRenderer
@end

/**
 * 全息效果渲染器
 */
@interface HolographicRenderer : BaseMetalRenderer
@end

/**
 * 赛博朋克渲染器
 */
@interface CyberPunkRenderer : BaseMetalRenderer
@end

/**
 * 星系渲染器
 */
@interface GalaxyRenderer : BaseMetalRenderer
@end

/**
 * 液态金属渲染器
 */
@interface LiquidMetalRenderer : BaseMetalRenderer
@end

/**
 * 闪电雷暴渲染器
 */
@interface LightningRenderer : BaseMetalRenderer
@end

/**
 * 环形波浪渲染器
 */
@interface CircularWaveRenderer : BaseMetalRenderer
@end

/**
 * 粒子流渲染器
 */
@interface ParticleFlowRenderer : BaseMetalRenderer
@end

/**
 * 音频响应3D渲染器
 */
@interface AudioReactive3DRenderer : BaseMetalRenderer
@end

/**
 * 光雾之心效果渲染器
 */
@interface LuminousMistCoreRenderer : BaseMetalRenderer
@end

/**
 * 几何变形渲染器
 */
@interface GeometricMorphRenderer : BaseMetalRenderer
@end

/**
 * 分形图案渲染器
 */
@interface FractalPatternRenderer : BaseMetalRenderer
@end

/**
 * 光绘焦散渲染器
 * 以长曝光光绘轨迹与焦散干涉纹理构建偏艺术化的创意效果
 */
@interface ChromaticCausticsRenderer : BaseMetalRenderer
@end

/**
 * 极光波纹渲染器 - 实验性效果
 * 融合北极光流动美学与音频驱动的多层波纹效果
 */
@interface AuroraRippleRenderer : BaseMetalRenderer
@end

/**
 * 恒星涡旋渲染器 - 实验性效果
 * 中心恒星日冕爆发与旋转的等离子云气效果
 */
@interface StarVortexRenderer : BaseMetalRenderer
@end

/**
 * 霓虹弹簧竖线渲染器 - 实验性效果
 * 发光霓虹竖线随音频产生弹簧动画效果
 */
@interface NeonSpringLinesRenderer : BaseMetalRenderer
@end

/**
 * 樱花飘雪渲染器 - 实验性效果
 * 如梦似幻的粉色樱花花瓣随风飘落，柔光弥漫的春日梦境
 */
@interface CherryBlossomSnowRenderer : BaseMetalRenderer
@end

/**
 * 丁达尔光束渲染器 - 实验性效果
 * 舞台灯光照射感，随频谱高度分层解锁光柱与尘埃
 */
@interface TyndallBeamRenderer : BaseMetalRenderer
@end

/**
 * 神经共振渲染器 - 实验性效果
 * 仿神经网络拓扑结构，节点随音频脉动，信号沿连线实时传递
 * 性能等级：Medium（14个节点 × 3条连线，30fps友好）
 */
@interface NeuralResonanceRenderer : BaseMetalRenderer
@end

/**
 * 虫洞穿梭渲染器 - 实验性效果
 * 星尘在原点汇聚成柱状脉冲，并沿虫洞纵深冲向观察者
 */
@interface WormholeDriveRenderer : BaseMetalRenderer
@end

/**
 * 棱镜共振渲染器 - 实验性效果
 * 以清晰几何线稿分层表现低频、中频与高频，强调边缘锐度与结构可读性
 */
@interface PrismResonanceRenderer : BaseMetalRenderer
@end

/**
 * 默认效果渲染器
 */
@interface DefaultEffectRenderer : BaseMetalRenderer
@end

/**
 * 渲染器工厂
 */
@interface MetalRendererFactory : NSObject

+ (instancetype)sharedFactory;

/**
 * 创建指定类型的渲染器
 */
- (id<MetalRenderer>)createRendererForEffect:(VisualEffectType)effectType 
                                   metalView:(MTKView *)metalView;

/**
 * 检查设备是否支持Metal
 */
+ (BOOL)isMetalSupported;

/**
 * 获取推荐的渲染设置
 */
+ (NSDictionary *)recommendedSettingsForDevice:(id<MTLDevice>)device;

@end

NS_ASSUME_NONNULL_END
