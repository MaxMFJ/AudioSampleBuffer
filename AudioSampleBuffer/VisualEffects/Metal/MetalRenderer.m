//
//  MetalRenderer.m
//  AudioSampleBuffer
//
//  Metal高性能渲染器实现
//

#import "MetalRenderer.h"
#import "../../AI/AIColorConfiguration.h"
#import "../../AI/MusicAIAnalyzer.h"
#import <simd/simd.h>

// 顶点结构体
typedef struct {
    vector_float2 position;
    vector_float4 color;
    vector_float2 texCoord;
} Vertex;

// 统一缓冲区结构体
typedef struct {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    vector_float4 time;
    vector_float4 resolution;
    vector_float4 audioData[80]; // 频谱数据
    vector_float4 galaxyParams1; // 星系参数1: (coreIntensity, edgeIntensity, rotationSpeed, glowRadius)
    vector_float4 galaxyParams2; // 星系参数2: (colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity)
    vector_float4 galaxyParams3; // 星系参数3: (starDensity, spiralArms, colorTheme, reserved)
    vector_float4 cyberpunkControls; // 赛博朋克控制: (enableClimaxEffect, showDebugBars, enableGrid, backgroundMode)
    vector_float4 cyberpunkFrequencyControls; // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
    vector_float4 cyberpunkBackgroundParams; // 赛博朋克背景参数: (solidColorR, solidColorG, solidColorB, intensity)
} Uniforms;

// AI 增强的统一缓冲区（用于丁达尔效应等需要动态颜色的效果）
typedef struct {
    matrix_float4x4 projectionMatrix;
    matrix_float4x4 modelViewMatrix;
    vector_float4 time;
    vector_float4 resolution;
    vector_float4 audioData[80];
    vector_float4 galaxyParams1;
    vector_float4 galaxyParams2;
    vector_float4 galaxyParams3;
    vector_float4 cyberpunkControls;
    vector_float4 cyberpunkFrequencyControls;
    vector_float4 cyberpunkBackgroundParams;
    
    // AI 音乐分析参数
    vector_float4 aiParams1;  // (bpm/100, energy, danceability, valence)
    vector_float4 aiParams2;  // (animSpeed, brightness, triggerSens, atmoIntensity)
    
    // AI 动态颜色（RGB + reserved）
    vector_float4 aiColorAtmosphere;
    vector_float4 aiColorVolumetricBeam;
    vector_float4 aiColorTopLightArray;
    vector_float4 aiColorLaserFanBlue;
    vector_float4 aiColorLaserFanGreen;
    vector_float4 aiColorRotatingBeam;
    vector_float4 aiColorRotatingBeamExtra;   // 额外6条旋转细丝颜色
    vector_float4 aiColorEdgeLight;           // 底部边缘描绘光颜色
    vector_float4 aiColorCoronaFilaments;     // 外围长丝 + 放射日冕丝颜色
    vector_float4 aiColorPulseRing;           // 脉冲环颜色
} UniformsAI;

@interface BaseMetalRenderer () {
    float _smoothedAudioState[80];
    float _previousAudioState[80];
}
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLLibrary> defaultLibrary;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, assign) NSTimeInterval startTime;
@end

@implementation BaseMetalRenderer

- (instancetype)initWithMetalView:(MTKView *)metalView {
    if (self = [super init]) {
        _metalView = metalView;
        _device = metalView.device ?: MTLCreateSystemDefaultDevice();
        
        if (!_device) {
            NSLog(@"❌ Metal不受支持");
            return nil;
        }
        
        _commandQueue = [_device newCommandQueue];
        _defaultLibrary = [_device newDefaultLibrary];
        _renderParameters = [NSMutableDictionary dictionary];
        _startTime = CACurrentMediaTime();
        
        [self setupMetal];
        [self setupPipeline];
        
        // 🔥 监听应用即将终止的通知，确保GPU资源被释放
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(applicationWillTerminate:)
                                                     name:UIApplicationWillTerminateNotification
                                                   object:nil];
    }
    return self;
}

- (void)applicationWillTerminate:(NSNotification *)notification {
    NSLog(@"🔥 应用即将终止，清理GPU资源...");
    [self stopRendering];
}

- (void)dealloc {
    // 移除通知监听
    [[NSNotificationCenter defaultCenter] removeObserver:self];
    
    // 确保GPU资源被释放
    [self stopRendering];
    
    NSLog(@"♻️ MetalRenderer已释放");
}

- (void)setupMetal {
    self.metalView.device = self.device;
    // 🔥 不在初始化时设置delegate，等待startRendering时再设置
    // self.metalView.delegate = self;  // 移除，由startRendering设置
    
    // 🔋 优化1：降低默认帧率到30fps（节省50%GPU功耗，视觉上依然流畅）
    self.metalView.preferredFramesPerSecond = 30;
    
    // 🔥 默认暂停状态，避免自动渲染
    self.metalView.paused = YES;
    self.metalView.enableSetNeedsDisplay = NO;
    
    self.metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    self.metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);
    
    // 创建统一缓冲区
    self.uniformBuffer = [self.device newBufferWithLength:sizeof(Uniforms) 
                                                  options:MTLResourceStorageModeShared];
}

- (void)setupPipeline {
    // 子类需要重写此方法
}

- (void)updateSpectrumData:(NSArray<NSNumber *> *)spectrumData {
    // 防御性检查并copy数组，避免传入的数组在使用时被修改
    if (spectrumData && [spectrumData isKindOfClass:[NSArray class]]) {
        self.currentSpectrumData = [spectrumData copy];
    } else {
        self.currentSpectrumData = nil;
    }
}

- (void)setRenderParameters:(NSDictionary *)parameters {
    [self.renderParameters addEntriesFromDictionary:parameters];
}

- (void)startRendering {
    self.startTime = CACurrentMediaTime();
    self.isRendering = YES;
    
    // 🔥 设置delegate并开始渲染
    self.metalView.delegate = self;
    self.metalView.paused = NO;
    
    NSLog(@"🚀 Metal渲染已启动");
}

- (void)stopRendering {
    self.isRendering = NO;
    self.metalView.paused = YES;
    
    // 🔥 移除delegate，确保完全停止
    self.metalView.delegate = nil;
    
    // 🔥 新增：等待所有GPU命令执行完毕，确保GPU资源释放
    if (self.commandQueue) {
        // 创建一个空的命令缓冲并等待完成，强制清空队列
        id<MTLCommandBuffer> finalBuffer = [self.commandQueue commandBuffer];
        if (finalBuffer) {
            [finalBuffer commit];
            [finalBuffer waitUntilCompleted];
        }
    }
    
    NSLog(@"⏹️ Metal渲染已停止 (delegate已移除, GPU队列已清空)");
}

- (void)pauseRendering {
    // 🔋 优化：完全停止Metal渲染，降低CPU/GPU占用
    self.isRendering = NO;
    self.metalView.paused = YES;
    
    // 🔥 关键：移除delegate，确保drawInMTKView不再被调用
    self.metalView.delegate = nil;
    
    // 🔥 新增：等待所有GPU命令执行完毕，确保GPU资源释放
    if (self.commandQueue) {
        // 创建一个空的命令缓冲并等待完成，强制清空队列
        id<MTLCommandBuffer> finalBuffer = [self.commandQueue commandBuffer];
        if (finalBuffer) {
            [finalBuffer commit];
            [finalBuffer waitUntilCompleted];
        }
    }
    
    NSLog(@"⏸️ Metal渲染已暂停 (delegate已移除, GPU队列已清空)");
}

- (void)resumeRendering {
    // 🔋 优化：恢复Metal渲染
    self.isRendering = YES;
    
    // 🔥 关键：恢复delegate，开始渲染
    self.metalView.delegate = self;
    self.metalView.paused = NO;
    
    NSLog(@"▶️ Metal渲染已恢复 (delegate已设置)");
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // 处理尺寸变化
}

- (void)drawInMTKView:(MTKView *)view {
    // 🛑 严格检查：确保暂停时不渲染
    if (!self.isRendering) {
        NSLog(@"⚠️ drawInMTKView被调用但isRendering=NO，跳过渲染");
        return;
    }
    
    if (view.paused) {
        NSLog(@"⚠️ drawInMTKView被调用但view.paused=YES，跳过渲染");
        return;
    }
    
    NSTimeInterval currentTime = CACurrentMediaTime() - self.startTime;
    
    // 更新统一缓冲区
    [self updateUniforms:currentTime];
    
    // 创建命令缓冲区
    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    commandBuffer.label = @"VisualEffect";
    
    // 获取渲染通道描述符
    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor) {
        // 创建渲染编码器
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"VisualEffectEncoder";
        
        // 编码渲染命令
        [self encodeRenderCommands:renderEncoder];
        
        [renderEncoder endEncoding];
        
        // 呈现drawable
        [commandBuffer presentDrawable:view.currentDrawable];
    }
    
    // 提交命令缓冲区
    [commandBuffer commit];
    
    // 通知代理
    if ([self.delegate respondsToSelector:@selector(metalRenderer:didFinishFrame:)]) {
        [self.delegate metalRenderer:self didFinishFrame:currentTime];
    }
}

- (void)updateUniforms:(NSTimeInterval)time {
    Uniforms *uniforms = (Uniforms *)[self.uniformBuffer contents];
    
    // 更新时间
    uniforms->time = (vector_float4){time, sin(time), cos(time), time * 0.5};
    
    // 更新分辨率 - 使用实际容器的宽高比来计算特效缩放
    CGSize drawableSize = self.metalView.drawableSize;
    
    // 如果有设置实际容器尺寸，使用它来计算宽高比
    // 否则使用Metal视图自己的尺寸（向后兼容）
    float aspectRatio;
    if (self.actualContainerSize.width > 0 && self.actualContainerSize.height > 0) {
        aspectRatio = self.actualContainerSize.width / self.actualContainerSize.height;
    } else {
        CGSize viewSize = self.metalView.frame.size;
        aspectRatio = viewSize.width / viewSize.height;
    }
    
    // resolution: (drawableWidth, drawableHeight, aspectRatio, pixelScale)
    uniforms->resolution = (vector_float4){drawableSize.width, drawableSize.height, aspectRatio, 1.0};
    
    // 🔋 优化2：减少日志输出，降低CPU负载
    // 调试日志（仅输出第一帧）
    static int frameCounter = 0;
    if (frameCounter == 0) {
        NSLog(@"📐 [初始化] 分辨率设置:");
        NSLog(@"   Metal视图: %.0fx%.0f | 容器: %.0fx%.0f | 绘制: %.0fx%.0f | 比例: %.4f", 
              self.metalView.frame.size.width, self.metalView.frame.size.height,
              self.actualContainerSize.width, self.actualContainerSize.height,
              drawableSize.width, drawableSize.height, aspectRatio);
        frameCounter++;
    }
    
    // 更新频谱数据 - 使用本地副本防止多线程问题
    NSArray<NSNumber *> *spectrumData = self.currentSpectrumData;
    for (NSUInteger i = 0; i < 80; i++) {
        float rawValue = 0.0f;
        if (spectrumData && i < spectrumData.count) {
            NSNumber *number = spectrumData[i];
            if (number && [number isKindOfClass:[NSNumber class]]) {
                float value = [number floatValue];
                if (!isnan(value) && !isinf(value)) {
                    rawValue = fmaxf(value, 0.0f);
                }
            }
        }

        float previousSmoothed = _smoothedAudioState[i];
        float smoothedValue = previousSmoothed + (rawValue - previousSmoothed) * 0.18f;
        float transientValue = fmaxf(rawValue - previousSmoothed, 0.0f);

        _smoothedAudioState[i] = smoothedValue;
        _previousAudioState[i] = rawValue;

        uniforms->audioData[i] = (vector_float4){
            rawValue,
            smoothedValue,
            sqrtf(fabsf(rawValue)),
            transientValue
        };
    }
    
    // 更新星系参数（如果是星系渲染器）
    if ([self isKindOfClass:[GalaxyRenderer class]]) {
        [self updateGalaxyUniforms:uniforms];
    }
    
    // 更新赛博朋克参数（如果是赛博朋克渲染器）
    if ([self isKindOfClass:[CyberPunkRenderer class]]) {
        [self updateCyberpunkUniforms:uniforms];
    }
    
    // 更新投影矩阵
    // float aspect = size.width / size.height; // 暂时未使用
    uniforms->projectionMatrix = matrix_identity_float4x4;
    uniforms->modelViewMatrix = matrix_identity_float4x4;
}

// 更新星系参数的方法（在子类中重写）
- (void)updateGalaxyUniforms:(Uniforms *)uniforms {
    // 默认实现，子类重写
}

// 更新赛博朋克参数的方法（在子类中重写）
- (void)updateCyberpunkUniforms:(Uniforms *)uniforms {
    // 默认实现，子类重写
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    // 子类需要重写此方法
}

#pragma mark - 辅助方法

- (id<MTLBuffer>)createBufferWithData:(const void *)data length:(NSUInteger)length {
    return [self.device newBufferWithBytes:data length:length options:MTLResourceStorageModeShared];
}

- (id<MTLTexture>)createTextureWithWidth:(NSUInteger)width height:(NSUInteger)height {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatRGBA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.usage = MTLTextureUsageShaderRead | MTLTextureUsageShaderWrite;
    return [self.device newTextureWithDescriptor:descriptor];
}

- (id<MTLTexture>)createRenderTargetTextureWithWidth:(NSUInteger)width height:(NSUInteger)height {
    MTLTextureDescriptor *descriptor = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatBGRA8Unorm
                                                                                          width:width
                                                                                         height:height
                                                                                      mipmapped:NO];
    descriptor.storageMode = MTLStorageModePrivate;
    descriptor.usage = MTLTextureUsageRenderTarget | MTLTextureUsageShaderRead;
    return [self.device newTextureWithDescriptor:descriptor];
}

@end

#pragma mark - 具体渲染器实现

@implementation NeonGlowRenderer

- (void)setupPipeline {
    // 创建霓虹发光效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"NeonGlow";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"neon_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建霓虹发光管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation Waveform3DRenderer

- (void)setupPipeline {
    // 创建3D波形效果的渲染管线 - 使用通用顶点着色器
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Waveform3D";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"waveform3d_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建3D波形管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation FluidSimulationRenderer

- (void)setupPipeline {
    // 创建流体模拟效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"FluidSimulation";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"fluid_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建流体模拟管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    // 设置性能优化参数
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    // 根据设备性能调整渲染参数
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        // 高端设备 - 使用更高质量设置
        params[@"fluidQuality"] = @(1.0);
        params[@"particleCount"] = @(16);
        params[@"densityIterations"] = @(8);
        NSLog(@"🌊 流体模拟: 高端设备，使用高质量设置");
        
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        // 中端设备 - 平衡设置
        params[@"fluidQuality"] = @(0.8);
        params[@"particleCount"] = @(12);
        params[@"densityIterations"] = @(6);
        NSLog(@"🌊 流体模拟: 中端设备，使用平衡设置");
        
    } else {
        // 低端设备 - 性能优先
        params[@"fluidQuality"] = @(0.6);
        params[@"particleCount"] = @(8);
        params[@"densityIterations"] = @(4);
        NSLog(@"🌊 流体模拟: 低端设备，使用性能优化设置");
    }
    
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation QuantumFieldRenderer

- (void)setupPipeline {
    // 创建量子场效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"QuantumField";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"quantum_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建量子场管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation HolographicRenderer

- (void)setupPipeline {
    // 创建全息效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Holographic";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"holographic_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建全息效果管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation CyberPunkRenderer

- (void)setupPipeline {
    // 创建赛博朋克效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"CyberPunk";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"cyberpunk_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建赛博朋克管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)updateCyberpunkUniforms:(Uniforms *)uniforms {
    // 从渲染参数中获取赛博朋克设置
    NSDictionary *params = self.renderParameters;
    
    // 赛博朋克控制: (enableClimaxEffect, showDebugBars, enableGrid, backgroundMode)
    // 使用默认值，防止参数为空
    float enableClimaxEffect = params[@"enableClimaxEffect"] ? [params[@"enableClimaxEffect"] floatValue] : 1.0f;
    float showDebugBars = params[@"showDebugBars"] ? [params[@"showDebugBars"] floatValue] : 0.0f;
    float enableGrid = params[@"enableGrid"] ? [params[@"enableGrid"] floatValue] : 1.0f; // 默认显示网格
    float backgroundMode = params[@"backgroundMode"] ? [params[@"backgroundMode"] floatValue] : 0.0f; // 默认网格背景
    uniforms->cyberpunkControls = (vector_float4){enableClimaxEffect, showDebugBars, enableGrid, backgroundMode};
    
    // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
    float enableBassEffect = params[@"enableBassEffect"] ? [params[@"enableBassEffect"] floatValue] : 1.0f;
    float enableMidEffect = params[@"enableMidEffect"] ? [params[@"enableMidEffect"] floatValue] : 1.0f;
    float enableTrebleEffect = params[@"enableTrebleEffect"] ? [params[@"enableTrebleEffect"] floatValue] : 1.0f;
    uniforms->cyberpunkFrequencyControls = (vector_float4){enableBassEffect, enableMidEffect, enableTrebleEffect, 0.0f};
    
    // 赛博朋克背景参数: (solidColorR, solidColorG, solidColorB, intensity)
    float solidColorR = params[@"solidColorR"] ? [params[@"solidColorR"] floatValue] : 0.15f;
    float solidColorG = params[@"solidColorG"] ? [params[@"solidColorG"] floatValue] : 0.1f;
    float solidColorB = params[@"solidColorB"] ? [params[@"solidColorB"] floatValue] : 0.25f;
    float backgroundIntensity = params[@"backgroundIntensity"] ? [params[@"backgroundIntensity"] floatValue] : 0.8f;
    uniforms->cyberpunkBackgroundParams = (vector_float4){solidColorR, solidColorG, solidColorB, backgroundIntensity};
    
    // 🔋 优化：移除频繁日志输出
    // 日志已禁用以降低CPU负载
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation GalaxyRenderer

- (void)setupPipeline {
    // 创建星系效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Galaxy";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"galaxy_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建星系管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)updateGalaxyUniforms:(Uniforms *)uniforms {
    // 从渲染参数中获取星系设置
    NSDictionary *params = self.renderParameters;
    
    // 星系参数1: (coreIntensity, edgeIntensity, rotationSpeed, glowRadius)
    float coreIntensity = [params[@"coreIntensity"] floatValue] ?: 2.0f;
    float edgeIntensity = [params[@"edgeIntensity"] floatValue] ?: 1.0f;
    float rotationSpeed = [params[@"rotationSpeed"] floatValue] ?: 0.5f;
    float glowRadius = [params[@"glowRadius"] floatValue] ?: 0.3f;
    uniforms->galaxyParams1 = (vector_float4){coreIntensity, edgeIntensity, rotationSpeed, glowRadius};
    
    // 星系参数2: (colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity)
    float colorShiftSpeed = [params[@"colorShiftSpeed"] floatValue] ?: 1.0f;
    float nebulaIntensity = [params[@"nebulaIntensity"] floatValue] ?: 0.3f;
    float pulseStrength = [params[@"pulseStrength"] floatValue] ?: 0.1f;
    float audioSensitivity = [params[@"audioSensitivity"] floatValue] ?: 1.5f;
    uniforms->galaxyParams2 = (vector_float4){colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity};
    
    // 星系参数3: (starDensity, spiralArms, colorTheme, reserved)
    float starDensity = [params[@"starDensity"] floatValue] ?: 0.7f;
    float spiralArms = [params[@"spiralArms"] floatValue] ?: 2.0f;
    float colorTheme = [params[@"colorTheme"] floatValue] ?: 0.0f;
    uniforms->galaxyParams3 = (vector_float4){starDensity, spiralArms, colorTheme, 0.0f};
    
    // 🔋 优化：移除每帧日志
    // NSLog(@"🌌 更新星系参数");
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation LiquidMetalRenderer

- (void)setupPipeline {
    // 创建液态金属效果的渲染管线（使用流体模拟着色器）
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"LiquidMetal";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"fluid_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建液态金属管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation LightningRenderer

- (void)setupPipeline {
    // 创建闪电雷暴效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Lightning";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"lightning_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建闪电雷暴管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation ChromaticCausticsRenderer

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"ChromaticCaustics";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"chromaticCausticsFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;

    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];

    if (!self.pipelineState) {
        NSLog(@"❌ 创建光绘焦散管线失败: %@", error);
        return;
    }
}

- (void)updateUniforms:(NSTimeInterval)time {
    [super updateUniforms:time];

    Uniforms *uniforms = (Uniforms *)[self.uniformBuffer contents];
    NSDictionary *params = self.renderParameters;

    float ribbonCount = params[@"ribbonCount"] ? [params[@"ribbonCount"] floatValue] : 3.0f;
    float prismSeparation = params[@"prismSeparation"] ? [params[@"prismSeparation"] floatValue] : 0.14f;
    float flowSpeed = params[@"flowSpeed"] ? [params[@"flowSpeed"] floatValue] : 0.82f;
    float glowIntensity = params[@"glowIntensity"] ? [params[@"glowIntensity"] floatValue] : 1.18f;
    uniforms->galaxyParams1 = (vector_float4){ribbonCount, prismSeparation, flowSpeed, glowIntensity};

    float causticScale = params[@"causticScale"] ? [params[@"causticScale"] floatValue] : 1.05f;
    float interference = params[@"interference"] ? [params[@"interference"] floatValue] : 0.72f;
    float audioSensitivity = params[@"audioSensitivity"] ? [params[@"audioSensitivity"] floatValue] : 1.12f;
    float sparkleDensity = params[@"sparkleDensity"] ? [params[@"sparkleDensity"] floatValue] : 0.32f;
    uniforms->galaxyParams2 = (vector_float4){causticScale, interference, audioSensitivity, sparkleDensity};

    float hueDrift = params[@"hueDrift"] ? [params[@"hueDrift"] floatValue] : 0.16f;
    float vignette = params[@"vignette"] ? [params[@"vignette"] floatValue] : 0.22f;
    float bassLift = params[@"bassLift"] ? [params[@"bassLift"] floatValue] : 0.18f;
    uniforms->galaxyParams3 = (vector_float4){hueDrift, vignette, bassLift, 0.0f};
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 新增渲染器实现

@implementation CircularWaveRenderer

- (void)setupPipeline {
    // 创建环形波浪效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"CircularWave";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"circularWaveFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建环形波浪管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 环形波浪管线创建成功");
    
    // 设置性能优化参数
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        // 高端设备 - 高质量设置
        params[@"waveCount"] = @(7);
        params[@"waveQuality"] = @(1.0);
        params[@"detailLevel"] = @(1.0);
        NSLog(@"🌊 环形波浪: 高端设备，使用高质量设置");
        
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        // 中端设备 - 平衡设置
        params[@"waveCount"] = @(5);
        params[@"waveQuality"] = @(0.8);
        params[@"detailLevel"] = @(0.8);
        NSLog(@"🌊 环形波浪: 中端设备，使用平衡设置");
        
    } else {
        // 低端设备 - 性能优先
        params[@"waveCount"] = @(3);
        params[@"waveQuality"] = @(0.6);
        params[@"detailLevel"] = @(0.6);
        NSLog(@"🌊 环形波浪: 低端设备，使用性能优化设置");
    }
    
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation ParticleFlowRenderer

- (void)setupPipeline {
    // 创建粒子流效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"ParticleFlow";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"particleFlowFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建粒子流管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 粒子流管线创建成功");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"particleCount"] = @(50);
        params[@"particleQuality"] = @(1.0);
        params[@"flowComplexity"] = @(1.0);
        NSLog(@"🌊 粒子流: 高端设备，使用高质量设置");
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"particleCount"] = @(40);
        params[@"particleQuality"] = @(0.8);
        params[@"flowComplexity"] = @(0.8);
        NSLog(@"🌊 粒子流: 中端设备，使用平衡设置");
    } else {
        params[@"particleCount"] = @(25);
        params[@"particleQuality"] = @(0.6);
        params[@"flowComplexity"] = @(0.6);
        NSLog(@"🌊 粒子流: 低端设备，使用性能优化设置");
    }
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) {
        NSLog(@"❌ ParticleFlow: pipelineState为空，无法渲染！");
        return;
    }
    
    static int frameCount = 0;
    if (frameCount < 3) {
        NSLog(@"🎬 ParticleFlow: 正在渲染第 %d 帧", frameCount);
        frameCount++;
    }
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation AudioReactive3DRenderer

- (void)setupPipeline {
    // 创建音频响应3D效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"AudioReactive3D";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"audioReactive3DFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建音频响应3D管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 音频响应3D管线创建成功");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"geometryComplexity"] = @(1.0);
        params[@"renderQuality"] = @(1.0);
        NSLog(@"🎨 音频响应3D: 高端设备，使用高质量设置");
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"geometryComplexity"] = @(0.8);
        params[@"renderQuality"] = @(0.8);
        NSLog(@"🎨 音频响应3D: 中端设备，使用平衡设置");
    } else {
        params[@"geometryComplexity"] = @(0.6);
        params[@"renderQuality"] = @(0.6);
        NSLog(@"🎨 音频响应3D: 低端设备，使用性能优化设置");
    }
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation LuminousMistCoreRenderer

- (void)setupPipeline {
    // 创建漂浮光点效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"FloatingLights";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"luminousMistCoreFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合模式（Additive Blending）
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOne;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建漂浮光点管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 漂浮光点管线创建成功");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    // 漂浮光点效果极度优化，流畅度优先
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    // 极致性能优化配置
    params[@"lightCount"] = @(8);   // 8个主光球（中音控制大小，高音控制颜色）
    params[@"starCount"] = @(5);    // 5个闪烁星点
    params[@"fullScreen"] = @(YES); // 全屏显示
    params[@"quality"] = @(1.0);
    
    NSLog(@"✨ 漂浮光点: 超轻量级 - 8光球(高音变色)+5星点，GPU<20%");
    
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation GeometricMorphRenderer

- (void)setupPipeline {
    // 创建几何变形效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"GeometricMorph";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"geometricMorphFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建几何变形管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 几何变形管线创建成功");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"shapeComplexity"] = @(8);
        params[@"edgeQuality"] = @(1.0);
        NSLog(@"🔷 几何变形: 高端设备，使用高质量设置");
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"shapeComplexity"] = @(6);
        params[@"edgeQuality"] = @(0.8);
        NSLog(@"🔷 几何变形: 中端设备，使用平衡设置");
    } else {
        params[@"shapeComplexity"] = @(4);
        params[@"edgeQuality"] = @(0.6);
        NSLog(@"🔷 几何变形: 低端设备，使用性能优化设置");
    }
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation FractalPatternRenderer

- (void)setupPipeline {
    // 创建分形图案效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"FractalPattern";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"fractalPatternFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建分形图案管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 分形图案管线创建成功");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"maxIterations"] = @(40);
        params[@"fractalQuality"] = @(1.0);
        NSLog(@"🌀 分形图案: 高端设备，使用高质量设置");
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"maxIterations"] = @(30);
        params[@"fractalQuality"] = @(0.8);
        NSLog(@"🌀 分形图案: 中端设备，使用平衡设置");
    } else {
        params[@"maxIterations"] = @(20);
        params[@"fractalQuality"] = @(0.6);
        NSLog(@"🌀 分形图案: 低端设备，使用性能优化设置");
    }
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

@implementation DefaultEffectRenderer

- (void)setupPipeline {
    // 创建默认效果的渲染管线（使用霓虹效果）
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"Default";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"neon_fragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建默认效果管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 极光波纹渲染器 (实验性效果)

@implementation AuroraRippleRenderer

- (void)setupPipeline {
    // 创建极光波纹效果的渲染管线
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"AuroraRipple";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"auroraRippleFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    // 配置MSAA采样 - 匹配MTKView的设置
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    
    // 配置深度缓冲格式
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合模式（Additive Blending增强发光效果）
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建极光波纹管线失败: %@", error);
        NSLog(@"❌ 顶点函数: %@", pipelineDescriptor.vertexFunction);
        NSLog(@"❌ 片段函数: %@", pipelineDescriptor.fragmentFunction);
        return;
    }
    
    NSLog(@"✅ 极光波纹管线创建成功 - 实验性效果");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        // 高端设备 - 高质量极光效果
        params[@"auroraLayers"] = @(4);
        params[@"rippleCount"] = @(5);
        params[@"starDensity"] = @(1.0);
        params[@"effectQuality"] = @(1.0);
        NSLog(@"🌌 极光波纹: 高端设备，使用高质量设置");
        
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        // 中端设备 - 平衡设置
        params[@"auroraLayers"] = @(3);
        params[@"rippleCount"] = @(4);
        params[@"starDensity"] = @(0.7);
        params[@"effectQuality"] = @(0.8);
        NSLog(@"🌌 极光波纹: 中端设备，使用平衡设置");
        
    } else {
        // 低端设备 - 性能优先
        params[@"auroraLayers"] = @(2);
        params[@"rippleCount"] = @(3);
        params[@"starDensity"] = @(0.5);
        params[@"effectQuality"] = @(0.6);
        NSLog(@"🌌 极光波纹: 低端设备，使用性能优化设置");
    }
    
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) {
        NSLog(@"❌ AuroraRipple: pipelineState为空，无法渲染！");
        return;
    }
    
    static int frameCount = 0;
    if (frameCount < 3) {
        NSLog(@"🌌 AuroraRipple: 正在渲染第 %d 帧", frameCount);
        frameCount++;
    }
    
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    
    // 绘制全屏四边形
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 恒星涡旋渲染器 (实验性效果)

@implementation StarVortexRenderer

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"StarVortex";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"starVortexFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建恒星涡旋管线失败: %@", error);
        return;
    }
    
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"vortexLayers"] = @(4);
        params[@"flareComplexity"] = @(1.0);
    } else {
        params[@"vortexLayers"] = @(2);
        params[@"flareComplexity"] = @(0.7);
    }
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 霓虹弹簧竖线渲染器 (实验性效果)

@implementation NeonSpringLinesRenderer

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"NeonSpringLines";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"neonSpringLinesFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合模式以实现发光效果
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建霓虹弹簧竖线管线失败: %@", error);
        return;
    }
    
    NSLog(@"✅ 霓虹弹簧竖线渲染器初始化成功");
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 樱花飘雪渲染器 (实验性效果)

@implementation CherryBlossomSnowRenderer

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"CherryBlossomSnow";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"cherryBlossomSnowFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    // 启用混合模式（柔和叠加）
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建樱花飘雪管线失败: %@", error);
        return;
    }
    
    NSLog(@"✅ 樱花飘雪管线创建成功 - 实验性效果");
    [self setupPerformanceOptimizations];
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"petalLayers"] = @(4);
        params[@"petalDensity"] = @(1.0);
        params[@"effectQuality"] = @(1.0);
        NSLog(@"🌸 樱花飘雪: 高端设备，使用高质量设置");
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"petalLayers"] = @(3);
        params[@"petalDensity"] = @(0.7);
        params[@"effectQuality"] = @(0.8);
        NSLog(@"🌸 樱花飘雪: 中端设备，使用平衡设置");
    } else {
        params[@"petalLayers"] = @(2);
        params[@"petalDensity"] = @(0.5);
        params[@"effectQuality"] = @(0.6);
        NSLog(@"🌸 樱花飘雪: 低端设备，使用性能优化设置");
    }
    
    [self setRenderParameters:params];
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 丁达尔光束渲染器 (实验性效果)

@interface TyndallBeamRenderer ()
@property (nonatomic, strong) AIColorConfiguration *currentAIConfig;
@end

@implementation TyndallBeamRenderer

- (instancetype)initWithMetalView:(MTKView *)metalView {
    self = [super initWithMetalView:metalView];
    if (self) {
        // 重新创建更大的 uniformBuffer 来容纳 UniformsAI
        self.uniformBuffer = [self.device newBufferWithLength:sizeof(UniformsAI)
                                                      options:MTLResourceStorageModeShared];
        NSLog(@"✅ 丁达尔光束渲染器使用 UniformsAI，缓冲区大小: %lu 字节", sizeof(UniformsAI));
        
        // 监听 AI 配置变化（播放新歌时 MusicAIAnalyzer 会发送通知）
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(tyndallAIConfigurationDidChange:)
                                                     name:kAIConfigurationDidChangeNotification
                                                   object:nil];
        
        // 若已有当前配置（例如切到丁达尔时正在播放的歌曲已分析过），直接使用
        _currentAIConfig = [MusicAIAnalyzer sharedAnalyzer].currentConfiguration;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)tyndallAIConfigurationDidChange:(NSNotification *)notification {
    AIColorConfiguration *config = notification.userInfo[kAIConfigurationKey];
    if (config) {
        self.currentAIConfig = config;
        NSLog(@"🎨 丁达尔: 已应用 AI 配色 %@ - %@", config.songName, config.artist ?: @"");
    }
}

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"TyndallBeam";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"tyndallBeamFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;
    
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOne;
    
    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    
    if (!self.pipelineState) {
        NSLog(@"❌ 创建丁达尔光束管线失败: %@", error);
        return;
    }
    
    NSLog(@"✅ 丁达尔光束渲染器初始化成功");
}

- (void)updateUniforms:(NSTimeInterval)time {
    // 先调用父类方法填充基础 Uniforms 数据
    [super updateUniforms:time];
    
    UniformsAI *uniforms = (UniformsAI *)[self.uniformBuffer contents];
    AIColorConfiguration *config = self.currentAIConfig;
    
    if (config) {
        // 使用 AI 分析返回的配色
        uniforms->aiParams1 = (vector_float4){config.bpm / 100.f, config.energy, config.danceability, config.valence};
        uniforms->aiParams2 = (vector_float4){config.animationSpeed, config.brightnessMultiplier, config.triggerSensitivity, config.atmosphereIntensity};
        
        uniforms->aiColorAtmosphere      = (vector_float4){config.atmosphereColor.x, config.atmosphereColor.y, config.atmosphereColor.z, 1.0};
        uniforms->aiColorVolumetricBeam = (vector_float4){config.volumetricBeamColor.x, config.volumetricBeamColor.y, config.volumetricBeamColor.z, 1.0};
        uniforms->aiColorTopLightArray  = (vector_float4){config.topLightArrayColor.x, config.topLightArrayColor.y, config.topLightArrayColor.z, 1.0};
        uniforms->aiColorLaserFanBlue   = (vector_float4){config.laserFanBlueColor.x, config.laserFanBlueColor.y, config.laserFanBlueColor.z, 1.0};
        uniforms->aiColorLaserFanGreen  = (vector_float4){config.laserFanGreenColor.x, config.laserFanGreenColor.y, config.laserFanGreenColor.z, 1.0};
        uniforms->aiColorRotatingBeam       = (vector_float4){config.rotatingBeamColor.x, config.rotatingBeamColor.y, config.rotatingBeamColor.z, 1.0};
        // 额外旋转细丝：在主旋转光束颜色基础上偏亮
        uniforms->aiColorRotatingBeamExtra  = (vector_float4){
            fminf(config.rotatingBeamColor.x + 0.1f, 1.0f),
            fminf(config.rotatingBeamColor.y + 0.1f, 1.0f),
            fminf(config.rotatingBeamColor.z + 0.1f, 1.0f), 1.0};
        uniforms->aiColorEdgeLight          = (vector_float4){config.volumetricBeamColor.x, config.volumetricBeamColor.y * 0.85f, config.volumetricBeamColor.z * 0.5f, 1.0};
        uniforms->aiColorCoronaFilaments    = (vector_float4){config.coronaFilamentsColor.x, config.coronaFilamentsColor.y, config.coronaFilamentsColor.z, 1.0};
        uniforms->aiColorPulseRing          = (vector_float4){config.pulseRingColor.x, config.pulseRingColor.y, config.pulseRingColor.z, 1.0};
    } else {
        // 默认颜色（未分析或 API 未返回时）
        uniforms->aiParams1 = (vector_float4){1.2, 0.7, 0.7, 0.7};
        uniforms->aiParams2 = (vector_float4){1.0, 1.0, 1.0, 0.45};
        
        uniforms->aiColorAtmosphere         = (vector_float4){0.06, 0.055, 0.08, 1.0};
        uniforms->aiColorVolumetricBeam     = (vector_float4){1.0, 0.88, 0.72, 1.0};
        uniforms->aiColorTopLightArray      = (vector_float4){0.3, 0.6, 1.0, 1.0};
        uniforms->aiColorLaserFanBlue       = (vector_float4){0.25, 0.55, 1.0, 1.0};
        uniforms->aiColorLaserFanGreen      = (vector_float4){0.35, 1.0, 0.45, 1.0};
        uniforms->aiColorRotatingBeam       = (vector_float4){1.0, 0.4, 0.8, 1.0};
        uniforms->aiColorRotatingBeamExtra  = (vector_float4){1.0, 0.5, 0.9, 1.0};
        uniforms->aiColorEdgeLight          = (vector_float4){1.0, 0.75, 0.35, 1.0};
        uniforms->aiColorCoronaFilaments    = (vector_float4){0.9, 0.6, 0.8, 1.0};
        uniforms->aiColorPulseRing          = (vector_float4){0.8, 0.3, 1.0, 1.0};
    }
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 神经共振渲染器 (实验性效果)

@interface NeuralResonanceRenderer ()
@property (nonatomic, assign) NSTimeInterval lastHostTime;
@property (nonatomic, assign) float motionTime;
@property (nonatomic, assign) float smoothedActivity;
@property (nonatomic, strong) AIColorConfiguration *currentAIConfig;
@end

@implementation NeuralResonanceRenderer

- (instancetype)initWithMetalView:(MTKView *)metalView {
    self = [super initWithMetalView:metalView];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(neuralAIConfigurationDidChange:)
                                                     name:kAIConfigurationDidChangeNotification
                                                   object:nil];
        _currentAIConfig = [MusicAIAnalyzer sharedAnalyzer].currentConfiguration;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)neuralAIConfigurationDidChange:(NSNotification *)notification {
    AIColorConfiguration *config = notification.userInfo[kAIConfigurationKey];
    if (config) {
        self.currentAIConfig = config;
        NSLog(@"🧠 神经共振: 已应用 AI 主题色 %@ - %@", config.songName, config.artist ?: @"");
    }
}

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"NeuralResonance";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"neuralResonanceFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;

    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;

    // 发光叠加但保留层次，避免过曝
    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];

    if (!self.pipelineState) {
        NSLog(@"❌ 创建神经共振管线失败: %@", error);
        return;
    }

    [self setupPerformanceOptimizations];
    NSLog(@"✅ 神经共振渲染器初始化成功");
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];

    // 根据 SoC 档位降低 shader 复杂度，控制发热
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"shaderComplexity"] = @(0.9);
        params[@"nodeCount"] = @(12);
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"shaderComplexity"] = @(0.78);
        params[@"nodeCount"] = @(10);
    } else {
        params[@"shaderComplexity"] = @(0.65);
        params[@"nodeCount"] = @(8);
    }

    // 神经共振专用控制参数
    params[@"silenceThreshold"] = params[@"silenceThreshold"] ?: @(0.022); // 无音乐门限
    params[@"linkBrightness"] = params[@"linkBrightness"] ?: @(1.18);     // 连线提亮
    params[@"rippleIntensity"] = params[@"rippleIntensity"] ?: @(1.08);   // 余波强度
    params[@"currentIntensity"] = params[@"currentIntensity"] ?: @(1.15);  // 电流亮度
    params[@"paletteBoost"] = params[@"paletteBoost"] ?: @(1.05);         // 调色增强

    [self setRenderParameters:params];
}

- (void)updateUniforms:(NSTimeInterval)time {
    [super updateUniforms:time];

    Uniforms *uniforms = (Uniforms *)[self.uniformBuffer contents];

    NSTimeInterval dt = 0.0;
    if (self.lastHostTime > 0.0) {
        dt = time - self.lastHostTime;
        if (dt < 0.0) dt = 0.0;
        if (dt > 0.12) dt = 0.12;
    }
    self.lastHostTime = time;

    NSArray<NSNumber *> *spectrum = self.currentSpectrumData;
    float bass = 0.0f;
    float mid = 0.0f;
    float treble = 0.0f;

    if (spectrum.count > 0) {
        NSUInteger count = MIN(spectrum.count, (NSUInteger)80);

        float bassSum = 0.0f; int bassN = 0;
        float midSum = 0.0f; int midN = 0;
        float trebleSum = 0.0f; int trebleN = 0;

        for (NSUInteger i = 0; i < count; i++) {
            float v = [spectrum[i] floatValue];
            if (isnan(v) || isinf(v)) v = 0.0f;

            if (i <= 16) {
                bassSum += v;
                bassN++;
            } else if (i <= 50) {
                midSum += v;
                midN++;
            } else {
                trebleSum += v;
                trebleN++;
            }
        }

        bass = bassN > 0 ? bassSum / (float)bassN : 0.0f;
        mid = midN > 0 ? midSum / (float)midN : 0.0f;
        treble = trebleN > 0 ? trebleSum / (float)trebleN : 0.0f;
    }

    NSDictionary *params = self.renderParameters;
    float threshold = params[@"silenceThreshold"] ? [params[@"silenceThreshold"] floatValue] : 0.022f;
    threshold = fmaxf(0.005f, fminf(threshold, 0.12f));

    float energy = bass * 0.42f + mid * 0.35f + treble * 0.23f;
    BOOL musicActive = energy > threshold;

    float targetActivity = musicActive ? 1.0f : 0.0f;
    float rise = 7.0f;
    float fall = 4.0f;
    float k = (targetActivity > self.smoothedActivity ? rise : fall) * (float)dt;
    k = fminf(fmaxf(k, 0.0f), 1.0f);
    self.smoothedActivity = self.smoothedActivity + (targetActivity - self.smoothedActivity) * k;

    // 仅在音乐活跃时推进“余波/电流相位时间”，无音乐时冻结余波动画
    if (musicActive && dt > 0.0) {
        float speed = 0.72f + fminf(energy * 1.1f, 1.2f);
        self.motionTime += (float)(dt * speed);
    }

    // 覆盖time向量：x作为主时间，z携带冻结相位时间（给余波/电流使用）
    uniforms->time = (vector_float4){time, sin(time), self.motionTime, time * 0.5};

    // LLM 主题色注入（供 shader 统一主导所有颜色）
    vector_float3 themeColor = (vector_float3){0.58f, 0.68f, 1.0f};
    float llmThemeEnabled = 0.0f;
    if (self.currentAIConfig && self.currentAIConfig.isLLMGenerated) {
        // 用 pulseRing + volumetricBeam 混合生成神经共振主主题色
        vector_float3 p = (vector_float3){self.currentAIConfig.pulseRingColor.x,
                                          self.currentAIConfig.pulseRingColor.y,
                                          self.currentAIConfig.pulseRingColor.z};
        vector_float3 v = (vector_float3){self.currentAIConfig.volumetricBeamColor.x,
                                          self.currentAIConfig.volumetricBeamColor.y,
                                          self.currentAIConfig.volumetricBeamColor.z};
        themeColor = p * 0.62f + v * 0.38f;
        llmThemeEnabled = 1.0f;
    }

    // 复用控制槽位给神经共振（不影响其他效果）
    float paletteBoost = params[@"paletteBoost"] ? [params[@"paletteBoost"] floatValue] : 1.05f;

    uniforms->cyberpunkControls = (vector_float4){musicActive ? 1.0f : 0.0f, self.smoothedActivity, bass, mid};
    uniforms->cyberpunkFrequencyControls = (vector_float4){treble, energy, self.motionTime, llmThemeEnabled};
    uniforms->cyberpunkBackgroundParams = (vector_float4){themeColor.x, themeColor.y, themeColor.z, paletteBoost};
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 虫洞穿梭渲染器 (实验性效果)

@interface WormholeDriveRenderer ()
@property (nonatomic, assign) NSTimeInterval lastHostTime;
@property (nonatomic, assign) float motionTime;
@property (nonatomic, assign) float smoothedActivity;
@property (nonatomic, assign) float beatEnvelope;
@property (nonatomic, assign) float bassFollower;
@property (nonatomic, assign) float energyFollower;
@property (nonatomic, strong) AIColorConfiguration *currentAIConfig;
@end

@implementation WormholeDriveRenderer

- (instancetype)initWithMetalView:(MTKView *)metalView {
    self = [super initWithMetalView:metalView];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(wormholeAIConfigurationDidChange:)
                                                     name:kAIConfigurationDidChangeNotification
                                                   object:nil];
        _currentAIConfig = [MusicAIAnalyzer sharedAnalyzer].currentConfiguration;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)wormholeAIConfigurationDidChange:(NSNotification *)notification {
    AIColorConfiguration *config = notification.userInfo[kAIConfigurationKey];
    if (config) {
        self.currentAIConfig = config;
        NSLog(@"🌀 虫洞穿梭: 已应用 AI 主题色 %@ - %@", config.songName, config.artist ?: @"");
    }
}

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"WormholeDrive";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"wormholeDriveFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;

    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;

    pipelineDescriptor.colorAttachments[0].blendingEnabled = NO;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];

    if (!self.pipelineState) {
        NSLog(@"❌ 创建虫洞穿梭管线失败: %@", error);
        return;
    }

    [self setupPerformanceOptimizations];
    NSLog(@"✅ 虫洞穿梭渲染器初始化成功");
}

- (void)setupPerformanceOptimizations {
    NSString *deviceName = self.device.name;
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];

    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        params[@"starLaneCount"] = @(16);
        params[@"barCount"] = @(10);
        params[@"travelSpeed"] = @(0.90);
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        params[@"starLaneCount"] = @(14);
        params[@"barCount"] = @(8);
        params[@"travelSpeed"] = @(0.86);
    } else {
        params[@"starLaneCount"] = @(12);
        params[@"barCount"] = @(6);
        params[@"travelSpeed"] = @(0.80);
    }

    params[@"silenceThreshold"] = params[@"silenceThreshold"] ?: @(0.02);
    params[@"flashIntensity"] = params[@"flashIntensity"] ?: @(1.12);
    params[@"tunnelRadius"] = params[@"tunnelRadius"] ?: @(0.34);
    params[@"swirlAmount"] = params[@"swirlAmount"] ?: @(1.00);
    params[@"paletteBoost"] = params[@"paletteBoost"] ?: @(1.08);
    params[@"audioSensitivity"] = params[@"audioSensitivity"] ?: @(1.10);
    params[@"beatDecay"] = params[@"beatDecay"] ?: @(5.4);

    [self setRenderParameters:params];
}

- (void)updateUniforms:(NSTimeInterval)time {
    [super updateUniforms:time];

    Uniforms *uniforms = (Uniforms *)[self.uniformBuffer contents];

    NSTimeInterval dt = 0.0;
    if (self.lastHostTime > 0.0) {
        dt = time - self.lastHostTime;
        if (dt < 0.0) dt = 0.0;
        if (dt > 0.12) dt = 0.12;
    }
    self.lastHostTime = time;

    NSArray<NSNumber *> *spectrum = self.currentSpectrumData;
    float bass = 0.0f;
    float mid = 0.0f;
    float treble = 0.0f;

    if (spectrum.count > 0) {
        NSUInteger count = MIN(spectrum.count, (NSUInteger)80);
        float bassSum = 0.0f; int bassN = 0;
        float midSum = 0.0f; int midN = 0;
        float trebleSum = 0.0f; int trebleN = 0;

        for (NSUInteger i = 0; i < count; i++) {
            float value = [spectrum[i] floatValue];
            if (isnan(value) || isinf(value)) value = 0.0f;

            if (i <= 16) {
                bassSum += value;
                bassN++;
            } else if (i <= 50) {
                midSum += value;
                midN++;
            } else {
                trebleSum += value;
                trebleN++;
            }
        }

        bass = bassN > 0 ? bassSum / (float)bassN : 0.0f;
        mid = midN > 0 ? midSum / (float)midN : 0.0f;
        treble = trebleN > 0 ? trebleSum / (float)trebleN : 0.0f;
    }

    NSDictionary *params = self.renderParameters;
    float threshold = params[@"silenceThreshold"] ? [params[@"silenceThreshold"] floatValue] : 0.02f;
    threshold = fmaxf(0.005f, fminf(threshold, 0.1f));

    float energy = fmaxf(0.0f, fminf(bass * 0.48f + mid * 0.34f + treble * 0.18f, 1.4f));
    BOOL musicActive = energy > threshold;

    float targetActivity = musicActive ? 1.0f : 0.0f;
    float rise = 7.6f;
    float fall = 3.5f;
    float response = (targetActivity > self.smoothedActivity ? rise : fall) * (float)dt;
    response = fminf(fmaxf(response, 0.0f), 1.0f);
    self.smoothedActivity = self.smoothedActivity + (targetActivity - self.smoothedActivity) * response;

    if (dt > 0.0) {
        float travelSpeed = params[@"travelSpeed"] ? [params[@"travelSpeed"] floatValue] : 1.12f;
        float idleDrift = 0.08f + travelSpeed * 0.08f;
        float musicBoost = musicActive ? (travelSpeed * 0.78f + energy * 0.95f + bass * 0.45f) : 0.0f;
        self.motionTime += (float)(dt * (idleDrift + musicBoost));
    }

    uniforms->time = (vector_float4){time, (float)dt, self.motionTime, time * 0.31f};

    vector_float3 themeColor = (vector_float3){0.52f, 0.72f, 1.0f};
    float llmThemeEnabled = 0.0f;
    if (self.currentAIConfig && self.currentAIConfig.isLLMGenerated) {
        vector_float3 pulse = (vector_float3){self.currentAIConfig.pulseRingColor.x,
                                              self.currentAIConfig.pulseRingColor.y,
                                              self.currentAIConfig.pulseRingColor.z};
        vector_float3 corona = (vector_float3){self.currentAIConfig.coronaFilamentsColor.x,
                                               self.currentAIConfig.coronaFilamentsColor.y,
                                               self.currentAIConfig.coronaFilamentsColor.z};
        themeColor = pulse * 0.58f + corona * 0.42f;
        llmThemeEnabled = 1.0f;
    }

    float barCount = params[@"barCount"] ? [params[@"barCount"] floatValue] : 10.0f;
    float starLaneCount = params[@"starLaneCount"] ? [params[@"starLaneCount"] floatValue] : 16.0f;
    float tunnelRadius = params[@"tunnelRadius"] ? [params[@"tunnelRadius"] floatValue] : 0.34f;
    float flashIntensity = params[@"flashIntensity"] ? [params[@"flashIntensity"] floatValue] : 1.35f;
    float swirlAmount = params[@"swirlAmount"] ? [params[@"swirlAmount"] floatValue] : 1.20f;
    float paletteBoost = params[@"paletteBoost"] ? [params[@"paletteBoost"] floatValue] : 1.10f;
    float audioSensitivity = params[@"audioSensitivity"] ? [params[@"audioSensitivity"] floatValue] : 1.08f;
    audioSensitivity = fmaxf(0.65f, fminf(audioSensitivity, 1.8f));

    float previousBassFollower = self.bassFollower;
    float previousEnergyFollower = self.energyFollower;
    if (dt > 0.0) {
        float bassFollowRate = (bass > self.bassFollower ? 10.0f : 2.8f) * (float)dt;
        bassFollowRate = fminf(fmaxf(bassFollowRate, 0.0f), 1.0f);
        self.bassFollower = self.bassFollower + (bass - self.bassFollower) * bassFollowRate;

        float energyFollowRate = (energy > self.energyFollower ? 7.2f : 2.6f) * (float)dt;
        energyFollowRate = fminf(fmaxf(energyFollowRate, 0.0f), 1.0f);
        self.energyFollower = self.energyFollower + (energy - self.energyFollower) * energyFollowRate;
    } else {
        self.bassFollower = bass;
        self.energyFollower = energy;
    }

    float beatTrigger = params[@"beatTrigger"] ? [params[@"beatTrigger"] floatValue] : 0.0f;
    beatTrigger = fmaxf(0.0f, fminf(beatTrigger, 1.2f));
    float bassRise = dt > 0.0 ? fmaxf(0.0f, bass - previousBassFollower) : 0.0f;
    float energyRise = dt > 0.0 ? fmaxf(0.0f, energy - previousEnergyFollower) : 0.0f;
    float localBeat = fminf(fmaxf(bassRise * 4.8f + energyRise * 3.2f + treble * 0.14f, 0.0f), 1.0f);
    float beatInput = fmaxf(beatTrigger, localBeat);
    self.beatEnvelope = fmaxf(self.beatEnvelope, beatInput);

    float beatDecay = params[@"beatDecay"] ? [params[@"beatDecay"] floatValue] : 6.2f;
    beatDecay = fmaxf(1.0f, fminf(beatDecay, 12.0f));
    if (dt > 0.0) {
        self.beatEnvelope *= expf(-beatDecay * (float)dt);
    }

    if (beatTrigger > 0.0f) {
        self.renderParameters[@"beatTrigger"] = @(0.0f);
    }

    uniforms->galaxyParams1 = (vector_float4){barCount, starLaneCount, tunnelRadius, flashIntensity};
    uniforms->galaxyParams2 = (vector_float4){params[@"travelSpeed"] ? [params[@"travelSpeed"] floatValue] : 0.90f,
                                              swirlAmount,
                                              self.smoothedActivity,
                                              audioSensitivity};
    uniforms->galaxyParams3 = (vector_float4){0.12f + bass * 0.055f,
                                              11.0f + mid * 8.0f + energy * 3.0f,
                                              1.05f + treble * 0.80f + beatInput * 0.18f,
                                              self.beatEnvelope};
    uniforms->cyberpunkControls = (vector_float4){musicActive ? 1.0f : 0.0f, self.smoothedActivity, bass, mid};
    uniforms->cyberpunkFrequencyControls = (vector_float4){treble, energy, self.motionTime, llmThemeEnabled};
    uniforms->cyberpunkBackgroundParams = (vector_float4){themeColor.x, themeColor.y, themeColor.z, paletteBoost};
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

@end

#pragma mark - 棱镜共振渲染器 (实验性效果)

@interface PrismResonanceRenderer ()
@property (nonatomic, strong) AIColorConfiguration *currentAIConfig;
@property (nonatomic, strong) id<MTLRenderPipelineState> backgroundPipelineState;
@property (nonatomic, strong) id<MTLTexture> backgroundTexture;
@property (nonatomic, assign) int lowShapeState;
@property (nonatomic, assign) int midShapeState;
@property (nonatomic, assign) int highShapeState;
@property (nonatomic, assign) NSTimeInterval lowTransitionStart;
@property (nonatomic, assign) NSTimeInterval midTransitionStart;
@property (nonatomic, assign) NSTimeInterval highTransitionStart;
@property (nonatomic, assign) NSTimeInterval lowLockUntil;
@property (nonatomic, assign) NSTimeInterval midLockUntil;
@property (nonatomic, assign) NSTimeInterval highLockUntil;
// 背景降频绘制：背景慢速漂移，每 3 帧更新一次即可，节省约 30% 背景 pass 开销
@property (nonatomic, assign) NSUInteger backgroundFrameCounter;
@end

@implementation PrismResonanceRenderer

- (instancetype)initWithMetalView:(MTKView *)metalView {
    self = [super initWithMetalView:metalView];
    if (self) {
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(prismAIConfigurationDidChange:)
                                                     name:kAIConfigurationDidChangeNotification
                                                   object:nil];
        _currentAIConfig = [MusicAIAnalyzer sharedAnalyzer].currentConfiguration;
        _lowShapeState = 0;
        _midShapeState = 0;
        _highShapeState = 0;
        _lowTransitionStart = -10.0;
        _midTransitionStart = -10.0;
        _highTransitionStart = -10.0;
        _lowLockUntil = 0;
        _midLockUntil = 0;
        _highLockUntil = 0;

        // 参考赛博朋克的低热量策略，进一步降低实际渲染成本
        self.metalView.contentScaleFactor = 0.78;
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)prismAIConfigurationDidChange:(NSNotification *)notification {
    AIColorConfiguration *config = notification.userInfo[kAIConfigurationKey];
    if (config) {
        self.currentAIConfig = config;
        NSLog(@"◇ 棱镜共振: 已应用 AI 主题色 %@ - %@", config.songName, config.artist ?: @"");
    }
}

- (void)setupPipeline {
    MTLRenderPipelineDescriptor *pipelineDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    pipelineDescriptor.label = @"PrismResonance";
    pipelineDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    pipelineDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"prismResonanceCompositeFragment"];
    pipelineDescriptor.colorAttachments[0].pixelFormat = self.metalView.colorPixelFormat;
    pipelineDescriptor.sampleCount = self.metalView.sampleCount;
    pipelineDescriptor.depthAttachmentPixelFormat = self.metalView.depthStencilPixelFormat;

    pipelineDescriptor.colorAttachments[0].blendingEnabled = YES;
    pipelineDescriptor.colorAttachments[0].rgbBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].alphaBlendOperation = MTLBlendOperationAdd;
    pipelineDescriptor.colorAttachments[0].sourceRGBBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].sourceAlphaBlendFactor = MTLBlendFactorSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationRGBBlendFactor = MTLBlendFactorOneMinusSourceAlpha;
    pipelineDescriptor.colorAttachments[0].destinationAlphaBlendFactor = MTLBlendFactorOneMinusSourceAlpha;

    NSError *error;
    self.pipelineState = [self.device newRenderPipelineStateWithDescriptor:pipelineDescriptor error:&error];
    if (!self.pipelineState) {
        NSLog(@"❌ 创建棱镜共振管线失败: %@", error);
        return;
    }

    MTLRenderPipelineDescriptor *backgroundDescriptor = [[MTLRenderPipelineDescriptor alloc] init];
    backgroundDescriptor.label = @"PrismResonanceBackground";
    backgroundDescriptor.vertexFunction = [self.defaultLibrary newFunctionWithName:@"neon_vertex"];
    backgroundDescriptor.fragmentFunction = [self.defaultLibrary newFunctionWithName:@"prismResonanceBackgroundFragment"];
    backgroundDescriptor.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    backgroundDescriptor.sampleCount = 1;

    self.backgroundPipelineState = [self.device newRenderPipelineStateWithDescriptor:backgroundDescriptor error:&error];
    if (!self.backgroundPipelineState) {
        NSLog(@"❌ 创建棱镜共振背景管线失败: %@", error);
        return;
    }

    [self setupPerformanceOptimizations];
    [self rebuildBackgroundTexture];
}

- (void)setupPerformanceOptimizations {
    NSMutableDictionary *params = [self.renderParameters mutableCopy] ?: [NSMutableDictionary dictionary];
    // 减负：图元数量稍降
    params[@"shapeLayers"]      = @(3);
    params[@"glyphsPerLayer"]   = @(6);
    params[@"morphSensitivity"] = @(1.00);
    params[@"audioSensitivity"] = @(1.20);
    params[@"glowIntensity"]    = @(1.00);
    [self setRenderParameters:params];

    // 进一步降载，减少整体卡顿
    self.metalView.preferredFramesPerSecond = 24;
}

- (void)rebuildBackgroundTexture {
    CGSize drawableSize = self.metalView.drawableSize;
    NSUInteger bgWidth = MAX(1, (NSUInteger)lrint(drawableSize.width * 0.5));
    NSUInteger bgHeight = MAX(1, (NSUInteger)lrint(drawableSize.height * 0.5));
    self.backgroundTexture = [self createRenderTargetTextureWithWidth:bgWidth height:bgHeight];
}

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    [super mtkView:view drawableSizeWillChange:size];
    [self rebuildBackgroundTexture];
}

- (void)updateUniforms:(NSTimeInterval)time {
    [super updateUniforms:time];

    Uniforms *uniforms = (Uniforms *)[self.uniformBuffer contents];
    NSDictionary *params = self.renderParameters;

    float shapeLayers = params[@"shapeLayers"] ? [params[@"shapeLayers"] floatValue] : 2.0f;
    float glyphsPerLayer = params[@"glyphsPerLayer"] ? [params[@"glyphsPerLayer"] floatValue] : 4.0f;
    float glowIntensity = params[@"glowIntensity"] ? [params[@"glowIntensity"] floatValue] : 0.68f;
    float morphSensitivity = params[@"morphSensitivity"] ? [params[@"morphSensitivity"] floatValue] : 0.92f;

    vector_float3 atmosphere = (vector_float3){0.10f, 0.07f, 0.14f};
    vector_float3 pulse = (vector_float3){0.96f, 0.62f, 0.84f};
    vector_float3 corona = (vector_float3){0.58f, 0.88f, 1.0f};
    float atmosphereIntensity = 0.42f;
    float brightness = 1.0f;
    float animSpeed = 1.0f;

    if (self.currentAIConfig) {
        atmosphere = self.currentAIConfig.atmosphereColor;
        pulse = self.currentAIConfig.pulseRingColor;
        corona = self.currentAIConfig.coronaFilamentsColor;
        atmosphereIntensity = self.currentAIConfig.atmosphereIntensity;
        brightness = self.currentAIConfig.brightnessMultiplier;
        animSpeed = self.currentAIConfig.animationSpeed;
    }

    // 音频触发形变：低/中/高频分别驱动一组形态状态
    // 触发后锁定3秒，不再受音频影响
    float low  = uniforms->audioData[4].y;   // bass smooth
    float mid  = uniforms->audioData[28].y;  // mid smooth
    float high = uniforms->audioData[58].y;  // high smooth
    NSTimeInterval lockDuration = 3.0;
    float clampedMorphSensitivity = fmaxf(0.7f, fminf(morphSensitivity, 1.8f));
    NSTimeInterval transitionDuration = 0.42 / clampedMorphSensitivity;

    if (time >= self.lowLockUntil && low > 0.18f) {
        self.lowShapeState = (self.lowShapeState + 1) % 3;
        self.lowTransitionStart = time;
        self.lowLockUntil = time + lockDuration;
    }
    if (time >= self.midLockUntil && mid > 0.15f) {
        self.midShapeState = (self.midShapeState + 1) % 3;
        self.midTransitionStart = time;
        self.midLockUntil = time + lockDuration;
    }
    if (time >= self.highLockUntil && high > 0.12f) {
        self.highShapeState = (self.highShapeState + 1) % 3;
        self.highTransitionStart = time;
        self.highLockUntil = time + lockDuration;
    }

    float lowMorphProgress = fminf(fmaxf((float)((time - self.lowTransitionStart) / transitionDuration), 0.0f), 1.0f);
    float midMorphProgress = fminf(fmaxf((float)((time - self.midTransitionStart) / transitionDuration), 0.0f), 1.0f);
    float highMorphProgress = fminf(fmaxf((float)((time - self.highTransitionStart) / transitionDuration), 0.0f), 1.0f);

    uniforms->galaxyParams1 = (vector_float4){shapeLayers, glyphsPerLayer, glowIntensity, morphSensitivity};
    uniforms->galaxyParams2 = (vector_float4){atmosphere.x, atmosphere.y, atmosphere.z, atmosphereIntensity};
    uniforms->galaxyParams3 = (vector_float4){pulse.x, pulse.y, pulse.z, brightness};
    uniforms->cyberpunkBackgroundParams = (vector_float4){corona.x, corona.y, corona.z, animSpeed};
    uniforms->cyberpunkControls = (vector_float4){(float)self.lowShapeState, (float)self.midShapeState, (float)self.highShapeState, 0.0f};
    uniforms->cyberpunkFrequencyControls = (vector_float4){lowMorphProgress, midMorphProgress, highMorphProgress, 0.0f};
}

- (void)encodeRenderCommands:(id<MTLRenderCommandEncoder>)encoder {
    if (!self.pipelineState) return;
    [encoder setRenderPipelineState:self.pipelineState];
    [encoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
    [encoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
    if (self.backgroundTexture) {
        [encoder setFragmentTexture:self.backgroundTexture atIndex:0];
    }
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
}

- (void)drawInMTKView:(MTKView *)view {
    if (!self.isRendering || view.paused) {
        return;
    }

    if (!self.backgroundTexture ||
        self.backgroundTexture.width != MAX(1, (NSUInteger)lrint(view.drawableSize.width * 0.5)) ||
        self.backgroundTexture.height != MAX(1, (NSUInteger)lrint(view.drawableSize.height * 0.5))) {
        [self rebuildBackgroundTexture];
    }

    NSTimeInterval currentTime = CACurrentMediaTime() - self.startTime;
    [self updateUniforms:currentTime];

    id<MTLCommandBuffer> commandBuffer = [self.commandQueue commandBuffer];
    commandBuffer.label = @"PrismResonanceMultiPass";

    // 背景降频绘制：每 3 帧更新一次背景纹理
    // 背景气泡以 0.07-0.18 rad/s 漂移，3 帧（@24fps ≈ 125ms）的位移 < 0.02，不可察觉
    self.backgroundFrameCounter = (self.backgroundFrameCounter + 1) % 3;
    if (self.backgroundTexture && self.backgroundFrameCounter == 0) {
        MTLRenderPassDescriptor *backgroundPass = [MTLRenderPassDescriptor renderPassDescriptor];
        backgroundPass.colorAttachments[0].texture = self.backgroundTexture;
        backgroundPass.colorAttachments[0].loadAction = MTLLoadActionClear;
        backgroundPass.colorAttachments[0].storeAction = MTLStoreActionStore;
        backgroundPass.colorAttachments[0].clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 1.0);

        id<MTLRenderCommandEncoder> backgroundEncoder = [commandBuffer renderCommandEncoderWithDescriptor:backgroundPass];
        backgroundEncoder.label = @"PrismBackgroundEncoder";
        [backgroundEncoder setRenderPipelineState:self.backgroundPipelineState];
        [backgroundEncoder setVertexBuffer:self.uniformBuffer offset:0 atIndex:0];
        [backgroundEncoder setFragmentBuffer:self.uniformBuffer offset:0 atIndex:0];
        [backgroundEncoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
        [backgroundEncoder endEncoding];
    }

    MTLRenderPassDescriptor *renderPassDescriptor = view.currentRenderPassDescriptor;
    if (renderPassDescriptor) {
        id<MTLRenderCommandEncoder> renderEncoder = [commandBuffer renderCommandEncoderWithDescriptor:renderPassDescriptor];
        renderEncoder.label = @"PrismCompositeEncoder";
        [self encodeRenderCommands:renderEncoder];
        [renderEncoder endEncoding];
        [commandBuffer presentDrawable:view.currentDrawable];
    }

    [commandBuffer commit];

    if ([self.delegate respondsToSelector:@selector(metalRenderer:didFinishFrame:)]) {
        [self.delegate metalRenderer:self didFinishFrame:currentTime];
    }
}

@end

#pragma mark - 渲染器工厂

@implementation MetalRendererFactory

+ (instancetype)sharedFactory {
    static MetalRendererFactory *instance = nil;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [[MetalRendererFactory alloc] init];
    });
    return instance;
}

- (id<MetalRenderer>)createRendererForEffect:(VisualEffectType)effectType 
                                   metalView:(MTKView *)metalView {
    switch (effectType) {
        // 基础效果
        case VisualEffectTypeCircularWave:
            return [[CircularWaveRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeParticleFlow:
            return [[ParticleFlowRenderer alloc] initWithMetalView:metalView];
            
        // Metal高端效果
        case VisualEffectTypeNeonGlow:
            return [[NeonGlowRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectType3DWaveform:
            return [[Waveform3DRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeFluidSimulation:
            return [[FluidSimulationRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeQuantumField:
            return [[QuantumFieldRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeHolographic:
            return [[HolographicRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeCyberPunk:
            return [[CyberPunkRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeAudioReactive3D:
            return [[AudioReactive3DRenderer alloc] initWithMetalView:metalView];
            
        // 创意效果
        case VisualEffectTypeGalaxy:
            return [[GalaxyRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeLightning:
            return [[LightningRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeFireworks:
            return [[LuminousMistCoreRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeLiquidMetal:
            return [[LiquidMetalRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeGeometricMorph:
            return [[GeometricMorphRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeFractalPattern:
            return [[FractalPatternRenderer alloc] initWithMetalView:metalView];

        case VisualEffectTypeChromaticCaustics:
            return [[ChromaticCausticsRenderer alloc] initWithMetalView:metalView];
            
        // 实验性效果
        case VisualEffectTypeAuroraRipples:
            return [[AuroraRippleRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeStarVortex:
            return [[StarVortexRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeNeonSpringLines:
            return [[NeonSpringLinesRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeCherryBlossomSnow:
            return [[CherryBlossomSnowRenderer alloc] initWithMetalView:metalView];
            
        case VisualEffectTypeTyndallBeam:
            return [[TyndallBeamRenderer alloc] initWithMetalView:metalView];

        case VisualEffectTypeNeuralResonance:
            return [[NeuralResonanceRenderer alloc] initWithMetalView:metalView];

        case VisualEffectTypeWormholeDrive:
            return [[WormholeDriveRenderer alloc] initWithMetalView:metalView];

        case VisualEffectTypePrismResonance:
            return [[PrismResonanceRenderer alloc] initWithMetalView:metalView];
            
        default:
            return [[DefaultEffectRenderer alloc] initWithMetalView:metalView];
    }
}

+ (BOOL)isMetalSupported {
    return MTLCreateSystemDefaultDevice() != nil;
}

+ (NSDictionary *)recommendedSettingsForDevice:(id<MTLDevice>)device {
    // 根据设备性能返回推荐设置
    NSString *deviceName = device.name;
    
    if ([deviceName containsString:@"A17"] || [deviceName containsString:@"A16"]) {
        // 高端设备
        return @{
            @"preferredFramesPerSecond": @(120),
            @"enableComplexEffects": @(YES),
            @"particleCount": @(10000),
            @"textureQuality": @"high"
        };
    } else if ([deviceName containsString:@"A15"] || [deviceName containsString:@"A14"]) {
        // 中端设备
        return @{
            @"preferredFramesPerSecond": @(60),
            @"enableComplexEffects": @(YES),
            @"particleCount": @(5000),
            @"textureQuality": @"medium"
        };
    } else {
        // 低端设备
        return @{
            @"preferredFramesPerSecond": @(30),
            @"enableComplexEffects": @(NO),
            @"particleCount": @(1000),
            @"textureQuality": @"low"
        };
    }
}

@end
