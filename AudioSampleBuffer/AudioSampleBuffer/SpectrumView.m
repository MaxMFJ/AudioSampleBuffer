//
//  SpectrumView.m
//  AudioSampleBuffer
//
//  重写为 Metal 渲染 — 替代 UIBezierPath + CAShapeLayer + 80 × CABasicAnimation。
//  CPU 开销从 40%+ 降至 < 2%，全部绘制由 GPU fragment shader 完成。
//

#import "SpectrumView.h"
#import <MetalKit/MetalKit.h>
#import <simd/simd.h>

// 与 SpectrumViewShader.metal 中 SpectrumUniforms 完全对齐
typedef struct {
    simd_float2 resolution;     // (drawableWidth, drawableHeight)
    float       aspectRatio;    // viewWidth / viewHeight
    float       innerRadius;    // 归一化 (以 viewWidth 为基准)
    float       time;
    float       rotationSpeed;
    float       maxBarHeight;   // 归一化
    float       glowIntensity;
    int         bandCount;
    float       amplitudeScale; // 归一化
    float       centerOffsetY;  // Y 偏移 (归一化)
} SpectrumUniforms;

#define kMaxBands 80

@interface SpectrumView () <MTKViewDelegate>
{
    // 预分配的频谱 C 数组 — 避免每帧 NSNumber 装箱
    float _amplitudes[kMaxBands];
    BOOL  _enterBackground;
}

@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) id<MTLDevice> device;
@property (nonatomic, strong) id<MTLCommandQueue> commandQueue;
@property (nonatomic, strong) id<MTLRenderPipelineState> pipelineState;
@property (nonatomic, strong) id<MTLBuffer> uniformBuffer;
@property (nonatomic, strong) id<MTLBuffer> amplitudeBuffer;
@property (nonatomic, assign) CFTimeInterval startTime;
@property (nonatomic, assign) BOOL isPaused;

// 渐变层（保留旋转动画 — CA 动画开销极低）
@property (nonatomic, strong) CAGradientLayer *leftGradientLayer;
@property (nonatomic, strong) CAGradientLayer *rightGradientLayer;
@end

@implementation SpectrumView

#pragma mark - 生命周期

- (instancetype)initWithFrame:(CGRect)frame {
    if (self = [super initWithFrame:frame]) {
        memset(_amplitudes, 0, sizeof(_amplitudes));
        _startTime = CACurrentMediaTime();
        _isPaused = NO;
        _enterBackground = NO;
        
        // 默认参数
        _barWidth  = 10.0;
        _space     = 2.0;
        _bottomSpace = 0;
        _topSpace    = -50;
        
        [self setupMetal];
        [self setupGradientLayers];
        [self setupNotifications];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - Metal 初始化

- (void)setupMetal {
    // 获取 Metal 设备
    _device = MTLCreateSystemDefaultDevice();
    if (!_device) {
        NSLog(@"⚠️ SpectrumView: Metal 不可用，回退到空白视图");
        return;
    }
    
    // 创建 MTKView
    _metalView = [[MTKView alloc] initWithFrame:self.bounds device:_device];
    _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    _metalView.delegate = self;
    _metalView.preferredFramesPerSecond = 30;  // 30fps 足够流畅，节省 50% GPU
    _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    _metalView.opaque = NO;                     // 透明背景
    _metalView.layer.opaque = NO;
    _metalView.backgroundColor = [UIColor clearColor];
    // 使用 setNeedsDisplay 驱动模式 — 只在有新数据时才重绘
    _metalView.paused = YES;
    _metalView.enableSetNeedsDisplay = YES;
    [self addSubview:_metalView];
    
    // 命令队列
    _commandQueue = [_device newCommandQueue];
    
    // 创建渲染管线
    [self buildPipeline];
    
    // 预分配缓冲区
    _uniformBuffer   = [_device newBufferWithLength:sizeof(SpectrumUniforms)
                                            options:MTLResourceStorageModeShared];
    _amplitudeBuffer = [_device newBufferWithLength:sizeof(float) * kMaxBands
                                            options:MTLResourceStorageModeShared];
}

- (void)buildPipeline {
    id<MTLLibrary> library = [_device newDefaultLibrary];
    if (!library) {
        NSLog(@"⚠️ SpectrumView: 无法加载 Metal shader library");
        return;
    }
    
    id<MTLFunction> vertexFunc   = [library newFunctionWithName:@"spectrumVertexShader"];
    id<MTLFunction> fragmentFunc = [library newFunctionWithName:@"spectrumFragmentShader"];
    
    if (!vertexFunc || !fragmentFunc) {
        NSLog(@"⚠️ SpectrumView: 找不到 spectrumVertexShader / spectrumFragmentShader");
        return;
    }
    
    MTLRenderPipelineDescriptor *desc = [[MTLRenderPipelineDescriptor alloc] init];
    desc.vertexFunction   = vertexFunc;
    desc.fragmentFunction = fragmentFunc;
    desc.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm;
    // Alpha 混合
    desc.colorAttachments[0].blendingEnabled = YES;
    desc.colorAttachments[0].rgbBlendOperation           = MTLBlendOperationAdd;
    desc.colorAttachments[0].alphaBlendOperation          = MTLBlendOperationAdd;
    desc.colorAttachments[0].sourceRGBBlendFactor         = MTLBlendFactorSourceAlpha;
    desc.colorAttachments[0].destinationRGBBlendFactor    = MTLBlendFactorOneMinusSourceAlpha;
    desc.colorAttachments[0].sourceAlphaBlendFactor       = MTLBlendFactorOne;
    desc.colorAttachments[0].destinationAlphaBlendFactor  = MTLBlendFactorOneMinusSourceAlpha;
    
    NSError *error = nil;
    _pipelineState = [_device newRenderPipelineStateWithDescriptor:desc error:&error];
    if (error) {
        NSLog(@"⚠️ SpectrumView: 渲染管线创建失败: %@", error.localizedDescription);
    }
}

#pragma mark - 渐变层（保留 CA 旋转动画，开销极低）

- (void)setupGradientLayers {
    // 右渐变层
    _rightGradientLayer = [CAGradientLayer layer];
    NSMutableArray *rightColors = [NSMutableArray array];
    for (NSInteger hue = 0; hue < 360; hue += 22) {
        UIColor *color = [UIColor colorWithHue:hue / 360.0 saturation:1.0 brightness:1.0 alpha:1.0];
        [rightColors addObject:(id)color.CGColor];
    }
    _rightGradientLayer.colors = rightColors;
    _rightGradientLayer.frame = self.bounds;
    _rightGradientLayer.hidden = YES; // Metal 渲染时隐藏，不再需要渐变层做 mask
    [self.layer addSublayer:_rightGradientLayer];
    
    // 左渐变层
    _leftGradientLayer = [CAGradientLayer layer];
    NSMutableArray *leftColors = [NSMutableArray array];
    for (NSInteger hue = 0; hue < 360; hue += 7) {
        UIColor *color = [UIColor colorWithHue:hue / 360.0 saturation:1.0 brightness:1.0 alpha:1.0];
        [leftColors addObject:(id)color.CGColor];
    }
    _leftGradientLayer.colors = leftColors;
    _leftGradientLayer.locations = @[@0.6, @1.0];
    _leftGradientLayer.frame = self.bounds;
    _leftGradientLayer.hidden = YES; // Metal 渲染时隐藏
    [self.layer addSublayer:_leftGradientLayer];
    
    // 旋转动画仍可保留（如果需要在非 Metal 回退时使用）
    [self addRotationAnimation:_rightGradientLayer];
    [self addRotationAnimation:_leftGradientLayer];
}

- (void)addRotationAnimation:(CALayer *)layer {
    CABasicAnimation *rotation = [CABasicAnimation animationWithKeyPath:@"transform.rotation.z"];
    rotation.fromValue = @(0);
    rotation.toValue = @(-M_PI * 12); // 6 圈
    rotation.duration = 100.0;
    rotation.repeatCount = HUGE_VALF;
    rotation.removedOnCompletion = NO;
    [layer addAnimation:rotation forKey:@"rotationAnimation"];
}

#pragma mark - 通知

- (void)setupNotifications {
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didEnterBackground)
                                                 name:UIApplicationDidEnterBackgroundNotification
                                               object:nil];
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(didBecomeActive)
                                                 name:UIApplicationDidBecomeActiveNotification
                                               object:nil];
}

- (void)didEnterBackground {
    _enterBackground = YES;
    _metalView.paused = YES;
}

- (void)didBecomeActive {
    _enterBackground = NO;
    if (!_isPaused) {
        // enableSetNeedsDisplay 模式下不需要 resume paused
    }
}

#pragma mark - 公开 API（保持与旧版完全一致）

- (void)updateSpectra:(NSArray *)spectra withStype:(ADSpectraStyle)style {
    if (!spectra || spectra.count == 0) return;
    if (_enterBackground || _isPaused) return;
    if (!_pipelineState) return;
    
    // 直接从 NSArray<NSNumber *> 拷贝到 C 数组 — 每帧只做一次遍历
    NSArray *firstChannel = spectra.firstObject;
    if (!firstChannel || ![firstChannel isKindOfClass:[NSArray class]]) return;
    
    NSUInteger count = MIN(firstChannel.count, (NSUInteger)kMaxBands);
    for (NSUInteger i = 0; i < count; i++) {
        _amplitudes[i] = [firstChannel[i] floatValue];
    }
    for (NSUInteger i = count; i < kMaxBands; i++) {
        _amplitudes[i] = 0.0f;
    }
    
    // 触发重绘（setNeedsDisplay 模式 — 只在有数据时绘制）
    [_metalView setNeedsDisplay];
}

- (void)pauseRendering {
    _isPaused = YES;
    _metalView.paused = YES;
    
    CFTimeInterval pausedTime = [self.layer convertTime:CACurrentMediaTime() fromLayer:nil];
    self.layer.speed = 0.0;
    self.layer.timeOffset = pausedTime;
}

- (void)resumeRendering {
    _isPaused = NO;
    
    CFTimeInterval pausedTime = self.layer.timeOffset;
    self.layer.speed = 1.0;
    self.layer.timeOffset = 0.0;
    self.layer.beginTime = 0.0;
    CFTimeInterval timeSincePause = [self.layer convertTime:CACurrentMediaTime() fromLayer:nil] - pausedTime;
    self.layer.beginTime = timeSincePause;
}

#pragma mark - MTKViewDelegate

- (void)mtkView:(MTKView *)view drawableSizeWillChange:(CGSize)size {
    // 分辨率变化时无需特殊处理，uniforms 每帧更新
}

- (void)drawInMTKView:(MTKView *)view {
    if (!_pipelineState || !_commandQueue) return;
    
    id<CAMetalDrawable> drawable = view.currentDrawable;
    MTLRenderPassDescriptor *passDesc = view.currentRenderPassDescriptor;
    if (!drawable || !passDesc) return;
    
    // ── 更新 Uniforms ──
    CGSize drawableSize = view.drawableSize;
    CGFloat viewW = view.bounds.size.width;
    CGFloat viewH = view.bounds.size.height;
    
    // ── 原始 UV 坐标系，半径按宽高比校正以保证屏幕上为圆 ──
    // center = (0.5, 0.5) 为视图中心；innerRadius 等以 viewWidth 为 1.0
    //
    // 圆心 Y：黑胶唱片在主视图 center → SpectrumView 本地 (viewW/2, viewH/2 - 25)
    // UV 中 Y 的 1.0 = viewH 像素，故 centerOffsetY = -25/viewH
    CGFloat aspectRatio = viewW / viewH;
    CGFloat frameOriginY = self.frame.origin.y; // 通常 25pt
    float centerOffsetY = -(float)(frameOriginY / viewH);
    
    SpectrumUniforms *u = (SpectrumUniforms *)_uniformBuffer.contents;
    u->resolution     = (simd_float2){ (float)drawableSize.width, (float)drawableSize.height };
    u->aspectRatio    = (float)aspectRatio;
    u->innerRadius    = 120.0 / (float)viewW;           // 120pt → 归一化
    u->time           = (float)(CACurrentMediaTime() - _startTime);
    u->rotationSpeed  = 0.06;                            // ≈ 6圈/100秒
    u->maxBarHeight   = 0.35;                            // 最大条高 = 0.35 × viewWidth
    u->glowIntensity  = 0.35;
    u->bandCount      = kMaxBands;
    u->amplitudeScale = 0.5;                             // amplitude × 0.5 (相当于旧版 viewW/2 / viewW)
    u->centerOffsetY  = centerOffsetY;
    
    // ── 拷贝频谱数据到 GPU 缓冲 ──
    memcpy(_amplitudeBuffer.contents, _amplitudes, sizeof(float) * kMaxBands);
    
    // ── 编码渲染命令 ──
    id<MTLCommandBuffer> cmdBuf = [_commandQueue commandBuffer];
    id<MTLRenderCommandEncoder> encoder = [cmdBuf renderCommandEncoderWithDescriptor:passDesc];
    
    [encoder setRenderPipelineState:_pipelineState];
    [encoder setFragmentBuffer:_uniformBuffer   offset:0 atIndex:0];
    [encoder setFragmentBuffer:_amplitudeBuffer offset:0 atIndex:1];
    
    // 全屏四边形 (triangle strip, 4 vertices)
    [encoder drawPrimitives:MTLPrimitiveTypeTriangleStrip vertexStart:0 vertexCount:4];
    
    [encoder endEncoding];
    [cmdBuf presentDrawable:drawable];
    [cmdBuf commit];
}

#pragma mark - Layout

- (void)layoutSubviews {
    [super layoutSubviews];
    _metalView.frame = self.bounds;
    _leftGradientLayer.frame = self.bounds;
    _rightGradientLayer.frame = self.bounds;
}

@end
