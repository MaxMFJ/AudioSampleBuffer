//
//  VisualEffectManager.m
//  AudioSampleBuffer
//
//  视觉效果统一管理器实现
//

#import "VisualEffectManager.h"
#import "../../AudioSampleBuffer/SpectrumView.h"
#import "../../AI/VisualEffectAIController.h"
#import "../../AI/EffectDecisionAgent.h"
#import "../../AI/RealtimeParameterTuner.h"
#import "../../AI/MusicStyleClassifier.h"
#import "../../AI/AudioFeatureExtractor.h"
#import "../../AI/MusicAIAnalyzer.h"

static const CGFloat kDefaultEffectRenderScale = 0.85f;

@interface VisualEffectManager () <MetalRendererDelegate, VisualEffectAIControllerDelegate>

@property (nonatomic, strong) UIView *effectContainerView;
@property (nonatomic, strong) MTKView *metalView;
@property (nonatomic, strong) EffectSelectorView *effectSelector;
@property (nonatomic, strong) id<MetalRenderer> currentRenderer;
@property (nonatomic, assign) VisualEffectType currentEffectType;
@property (nonatomic, assign) BOOL isEffectActive;

// 原有频谱视图引用
@property (nonatomic, weak) SpectrumView *originalSpectrumView;

// 性能统计
@property (nonatomic, assign) NSTimeInterval lastFrameTime;
@property (nonatomic, assign) NSInteger frameCount;
@property (nonatomic, assign) NSTimeInterval totalFrameTime;

// 设置
@property (nonatomic, strong) NSMutableDictionary *effectSettings;

// 实际屏幕容器尺寸（用于计算特效缩放比例）
@property (nonatomic, assign) CGSize actualContainerSize;

// 💾 保存用户的性能设置，切换特效时重新应用
@property (nonatomic, copy) NSDictionary *savedPerformanceSettings;

// 🤖 AI控制器 (readwrite for internal use, header declares readonly)
@property (nonatomic, strong, readwrite) VisualEffectAIController *aiController;

@end

@implementation VisualEffectManager

- (instancetype)initWithContainerView:(UIView *)containerView {
    if (self = [super init]) {
        _effectContainerView = containerView;
        _currentEffectType = VisualEffectTypeClassicSpectrum;
        _effectSettings = [NSMutableDictionary dictionary];
        
        [self setupMetalView];
        [self setupEffectSelector];
        [self loadDefaultSettings];
        [self setupAIController];
    }
    return self;
}

- (void)setupAIController {
    _aiController = [VisualEffectAIController sharedController];
    _aiController.delegate = self;
    _aiAutoModeEnabled = YES;  // 默认启用AI自动模式
    
    // 监听播放器开始播放歌曲的通知
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(handleSongDidStart:)
                                                 name:@"AudioSpectrumPlayerDidStartSongNotification"
                                               object:nil];
    
    NSLog(@"🤖 AI控制器已集成到 VisualEffectManager");
}

- (void)handleSongDidStart:(NSNotification *)notification {
    if (!_aiAutoModeEnabled) return;
    
    NSString *songName = notification.userInfo[@"songName"];
    NSString *artist = notification.userInfo[@"artist"];
    
    if (songName.length > 0) {
        // 1) 原有 AI 决策链路
        [self startAIModeWithSongName:songName artist:artist];

        // 2) 额外触发远端 LLM 颜色分析（丁达尔/神经共振共享）
        [[MusicAIAnalyzer sharedAnalyzer] analyzeSong:songName
                                               artist:artist ?: @""
                                           completion:^(AIColorConfiguration * _Nullable config, NSError * _Nullable error) {
            if (error) {
                NSLog(@"⚠️ 远端LLM主题色分析失败，使用本地降级: %@", error.localizedDescription);
                return;
            }
            if (config) {
                NSLog(@"🎨 已更新远端LLM主题色: %@ - %@", songName, artist ?: @"Unknown");
            }
        }];
    }
}

- (void)setupMetalView {
    // 检查Metal支持
    if (![MetalRendererFactory isMetalSupported]) {
        NSLog(@"⚠️ Metal不受支持，将使用基础渲染");
        return;
    }
    
    // 创建Metal视图 - 使用正方形视图避免变形，居中显示
    CGRect containerBounds = _effectContainerView.bounds;
    
    // 保存实际容器尺寸，用于计算特效缩放比例
    _actualContainerSize = containerBounds.size;
    
    // 使用较长的边作为正方形尺寸（通常是高度），让特效更大更震撼
    CGFloat squareSize = MAX(containerBounds.size.width, containerBounds.size.height);
    
    // 计算居中位置（左右会超出屏幕）
    CGFloat x = (containerBounds.size.width - squareSize) / 2.0;
    CGFloat y = (containerBounds.size.height - squareSize) / 2.0;
    
    // 创建正方形Metal视图
    _metalView = [[MTKView alloc] initWithFrame:CGRectMake(x, y, squareSize, squareSize)];
    _metalView.device = MTLCreateSystemDefaultDevice();
    _metalView.opaque = NO;
    _metalView.layer.opaque = NO;
    _metalView.backgroundColor = [UIColor clearColor];
    _metalView.clearColor = MTLClearColorMake(0.0, 0.0, 0.0, 0.0);
    
    // 提高渲染清晰度
    _metalView.contentScaleFactor = [UIScreen mainScreen].scale;
    
    // 使用正方形的绘制尺寸（这样圆形自然就是正圆）
    CGFloat drawableSize = squareSize * [UIScreen mainScreen].scale;
    _metalView.drawableSize = CGSizeMake(drawableSize, drawableSize);
    
    // 🔋 优化3：禁用MSAA抗锯齿（节省大量GPU功耗，视觉效果影响极小）
    _metalView.colorPixelFormat = MTLPixelFormatBGRA8Unorm;
    _metalView.depthStencilPixelFormat = MTLPixelFormatDepth32Float;
    _metalView.sampleCount = 1; // 禁用MSAA（从4降到1，节省75%抗锯齿开销）
    
    // 保持正确的宽高比
    _metalView.layer.masksToBounds = YES;
    
    [_effectContainerView addSubview:_metalView];
    
    // 🔋 优化4：统一使用30fps（不再根据设备区分，避免高端设备过热）
    // 所有设备使用30fps，节省功耗，视觉效果依然流畅
    _metalView.preferredFramesPerSecond = 30;
    
    // ⚠️ 关键修复：禁用自动渲染，使用手动渲染模式
    // 这样paused=YES时才能真正停止渲染
    _metalView.enableSetNeedsDisplay = NO;  // 使用自动模式，但会通过paused控制
    _metalView.paused = YES;  // 默认暂停，等待startRendering启动
    
    // 监听容器视图大小变化
    [[NSNotificationCenter defaultCenter] addObserver:self
                                             selector:@selector(containerViewDidChangeFrame:)
                                                 name:UIApplicationDidChangeStatusBarOrientationNotification
                                               object:nil];
    
    // 🔋 优化：合并日志输出
    NSLog(@"🌌 Metal视图初始化: 容器%.0fx%.0f | 正方形%.0f | 位置(%.0f,%.0f) | 绘制%.0fx%.0f", 
          containerBounds.size.width, containerBounds.size.height, squareSize,
          x, y, _metalView.drawableSize.width, _metalView.drawableSize.height);
}

- (void)setupEffectSelector {
    _effectSelector = [[EffectSelectorView alloc] init];
    _effectSelector.delegate = self;
    _effectSelector.currentEffectType = _currentEffectType;
}

- (void)loadDefaultSettings {
    // 加载默认的特效设置
    [_effectSettings setObject:@{
        @"intensity": @(1.0),
        @"speed": @(1.0),
        @"color": @{@"r": @(1.0), @"g": @(1.0), @"b": @(1.0)},
        @"quality": @"auto"
    } forKey:@"default"];
    
    // 为每种特效类型设置默认参数
    for (VisualEffectType type = 0; type < VisualEffectTypeCount; type++) {
        [self loadDefaultSettingsForEffect:type];
    }
}

- (void)loadDefaultSettingsForEffect:(VisualEffectType)effectType {
    NSMutableDictionary *settings = [NSMutableDictionary dictionary];
    
    switch (effectType) {
        case VisualEffectTypeNeonGlow:
            settings[@"glowIntensity"] = @(1.5);
            settings[@"pulseSpeed"] = @(2.0);
            settings[@"colorShift"] = @(YES);
            break;
            
        case VisualEffectType3DWaveform:
            settings[@"meshResolution"] = @(80);
            settings[@"heightScale"] = @(2.0);
            settings[@"rotationSpeed"] = @(0.5);
            break;
            
        case VisualEffectTypeFluidSimulation:
            settings[@"viscosity"] = @(0.8);
            settings[@"flowSpeed"] = @(1.2);
            settings[@"colorMix"] = @(YES);
            // 性能优化设置
            settings[@"fluidQuality"] = @(0.8);
            settings[@"particleCount"] = @(12);
            settings[@"densityIterations"] = @(6);
            settings[@"enableSafetyLimits"] = @(YES);
            break;
            
        case VisualEffectTypeQuantumField:
            settings[@"particleCount"] = @(10);
            settings[@"fieldStrength"] = @(1.0);
            settings[@"quantumFluctuation"] = @(YES);
            break;
            
        case VisualEffectTypeHolographic:
            settings[@"scanlineSpeed"] = @(0.1);
            settings[@"flickerRate"] = @(10.0);
            settings[@"hologramAlpha"] = @(0.8);
            break;
            
        case VisualEffectTypeCyberPunk:
            settings[@"matrixSpeed"] = @(2.0);
            settings[@"glitchEffect"] = @(YES);
            settings[@"neonColors"] = @(YES);
            // 网格和背景控制
            settings[@"enableGrid"] = @(1.0);  // 默认开启网格
            settings[@"backgroundMode"] = @(0.0);  // 默认网格背景模式
            settings[@"solidColorR"] = @(0.15);
            settings[@"solidColorG"] = @(0.1);
            settings[@"solidColorB"] = @(0.25);
            settings[@"backgroundIntensity"] = @(0.8);
            // 特效开关（默认全部开启）
            settings[@"enableClimaxEffect"] = @(1.0);
            settings[@"enableBassEffect"] = @(1.0);
            settings[@"enableMidEffect"] = @(1.0);
            settings[@"enableTrebleEffect"] = @(1.0);
            settings[@"showDebugBars"] = @(0.0);  // 调试条默认关闭
            break;
            
        case VisualEffectTypeGalaxy:
            settings[@"spiralArms"] = @(2);
            settings[@"starDensity"] = @(0.7);
            settings[@"rotationSpeed"] = @(0.5);
            settings[@"coreIntensity"] = @(2.0);
            settings[@"edgeIntensity"] = @(1.0);
            settings[@"glowRadius"] = @(0.3);
            settings[@"colorShiftSpeed"] = @(1.0);
            settings[@"nebulaIntensity"] = @(0.3);
            settings[@"pulseStrength"] = @(0.1);
            settings[@"audioSensitivity"] = @(1.5);
            break;
            
        case VisualEffectTypeLightning:
            settings[@"boltIntensity"] = @(1.5);
            settings[@"branchDensity"] = @(0.8);
            settings[@"flickerSpeed"] = @(2.0);
            settings[@"electricArcRadius"] = @(0.25);
            settings[@"bassResponse"] = @(1.5);
            settings[@"trebleResponse"] = @(1.2);
            break;

        case VisualEffectTypeChromaticCaustics:
            settings[@"ribbonCount"] = @(3);
            settings[@"prismSeparation"] = @(0.14);
            settings[@"flowSpeed"] = @(0.82);
            settings[@"glowIntensity"] = @(1.18);
            settings[@"causticScale"] = @(1.05);
            settings[@"interference"] = @(0.72);
            settings[@"audioSensitivity"] = @(1.12);
            settings[@"sparkleDensity"] = @(0.32);
            settings[@"hueDrift"] = @(0.16);
            settings[@"vignette"] = @(0.22);
            settings[@"bassLift"] = @(0.18);
            break;
            
        case VisualEffectTypeAuroraRipples:
            settings[@"auroraLayers"] = @(3);
            settings[@"rippleCount"] = @(4);
            settings[@"starDensity"] = @(0.7);
            break;
            
        case VisualEffectTypeStarVortex:
            settings[@"vortexLayers"] = @(3);
            settings[@"flareComplexity"] = @(0.8);
            settings[@"rotationSpeed"] = @(1.0);
            settings[@"colorIntensity"] = @(1.2);
            break;
            
        case VisualEffectTypeNeonSpringLines:
            settings[@"lineCount"] = @(7);
            settings[@"springDamping"] = @(2.5);
            settings[@"glowIntensity"] = @(1.5);
            settings[@"audioSensitivity"] = @(1.0);
            break;
            
        case VisualEffectTypeCherryBlossomSnow:
            settings[@"petalLayers"] = @(3);
            settings[@"petalDensity"] = @(0.8);
            settings[@"glowIntensity"] = @(1.2);
            settings[@"audioSensitivity"] = @(1.0);
            break;
            
        case VisualEffectTypeNeuralResonance:
            // 节点数量 & 连接半径
            settings[@"nodeCount"] = @(14);          // 14个节点（性能/细节平衡）
            settings[@"connectionRadius"] = @(0.8);  // 连接距离阈值
            // 发光强度
            settings[@"glowIntensity"] = @(1.2);
            // 信号脉冲速度
            settings[@"signalSpeed"] = @(0.6);
            // 音频灵敏度
            settings[@"audioSensitivity"] = @(1.0);
            // 冲击波强度
            settings[@"shockwaveIntensity"] = @(0.6);
            break;

        case VisualEffectTypeWormholeDrive:
            settings[@"barCount"] = @(10);
            settings[@"starLaneCount"] = @(16);
            settings[@"travelSpeed"] = @(0.88);
            settings[@"flashIntensity"] = @(1.18);
            settings[@"tunnelRadius"] = @(0.34);
            settings[@"swirlAmount"] = @(1.05);
            settings[@"paletteBoost"] = @(1.08);
            settings[@"audioSensitivity"] = @(1.15);
            settings[@"beatDecay"] = @(5.4);
            break;

        case VisualEffectTypeVisualLyricsTunnel:
            settings[@"lineDensity"] = @(6.0);
            settings[@"glowIntensity"] = @(1.15);
            settings[@"travelSpeed"] = @(0.82);
            settings[@"audioSensitivity"] = @(1.05);
            settings[@"trailSoftness"] = @(0.85);
            break;

        case VisualEffectTypeUserMediaBackground:
            settings[@"backgroundDim"] = @(0.18);
            settings[@"contentMode"] = @"aspectFill";
            break;
            
        default:
            settings[@"intensity"] = @(1.0);
            break;
    }
    
    NSString *key = [NSString stringWithFormat:@"effect_%lu", (unsigned long)effectType];
    [_effectSettings setObject:settings forKey:key];
}

- (void)updateMetalViewDrawableSizeForEffect:(VisualEffectType)effectType {
    if (!_metalView) return;

    CGSize containerSize = _actualContainerSize;
    if (containerSize.width <= 0.0 || containerSize.height <= 0.0) {
        containerSize = _effectContainerView.bounds.size;
    }

    CGFloat screenScale = [UIScreen mainScreen].scale;
    CGFloat squareSize = MAX(containerSize.width, containerSize.height);

    if (effectType == VisualEffectTypeWormholeDrive) {
        // 虫洞特效本身已针对宽屏做过专门调优，保留原有低功耗缩放。
        CGFloat renderScale = 0.58;
        _metalView.drawableSize = CGSizeMake(containerSize.width * screenScale * renderScale,
                                             containerSize.height * screenScale * renderScale);
    } else if (effectType == VisualEffectTypePrismResonance) {
        // 棱镜共振：参考赛博朋克的低热量策略，进一步压低实际绘制分辨率
        CGFloat renderScale = 0.58;
        _metalView.drawableSize = CGSizeMake(containerSize.width * screenScale * renderScale,
                                             containerSize.height * screenScale * renderScale);
    } else if (effectType == VisualEffectTypeVisualLyricsTunnel) {
        // 视觉歌词以宽屏斜向流动构图为主，直接使用容器宽高，保留对角线运动的空间感。
        CGFloat renderScale = 0.72;
        _metalView.drawableSize = CGSizeMake(containerSize.width * screenScale * renderScale,
                                             containerSize.height * screenScale * renderScale);
    } else if (effectType == VisualEffectTypeNeuralResonance) {
        // 神经共振：点线 halo 效果，对像素密度要求低，使用正方形 0.65 缩放降低 fragment 负载
        CGFloat renderScale = 0.65;
        CGFloat drawableSize = squareSize * screenScale * renderScale;
        _metalView.drawableSize = CGSizeMake(drawableSize, drawableSize);
    } else {
        // 保持正方形逻辑画布不变，只温和降低实际渲染分辨率。
        // 这样圆形/极坐标类效果不会重新出现拉伸变形问题。
        CGFloat drawableSize = squareSize * screenScale * kDefaultEffectRenderScale;
        _metalView.drawableSize = CGSizeMake(drawableSize, drawableSize);
    }
}

#pragma mark - Public Methods

- (void)showEffectSelector {
    if (!_effectSelector.superview) {
        _effectSelector.frame = CGRectMake(20, 100, 
                                          _effectContainerView.bounds.size.width - 40, 
                                          _effectContainerView.bounds.size.height - 200);
        [_effectContainerView addSubview:_effectSelector];
    }
    
    [_effectSelector showWithAnimation:YES];
}

- (void)hideEffectSelector {
    [_effectSelector hideWithAnimation:YES];
}

- (void)setOriginalSpectrumView:(SpectrumView *)spectrumView {
    _originalSpectrumView = spectrumView;
}

- (void)setCurrentEffect:(VisualEffectType)effectType animated:(BOOL)animated {
    if (_currentEffectType == effectType) return;
    
    // 🔋 优化：简化切换日志
    NSLog(@"🎨 切换特效: %lu->%lu", (unsigned long)_currentEffectType, (unsigned long)effectType);
    
    // 停止当前渲染器
    [_currentRenderer stopRendering];
    
    // 特别处理流体模拟效果 - 添加性能检查
    if (effectType == VisualEffectTypeFluidSimulation) {
        [self setupFluidSimulationSafety];
    }
    
    // 创建新的渲染器
    if ([self isEffectSupported:effectType]) {
        @try {
            _currentRenderer = [[MetalRendererFactory sharedFactory] createRendererForEffect:effectType 
                                                                                   metalView:_metalView];
            
            if (_currentRenderer) {
                _currentRenderer.delegate = self;
                
                // 设置实际容器尺寸，用于计算特效缩放
                if ([_currentRenderer respondsToSelector:@selector(setActualContainerSize:)]) {
                    [(BaseMetalRenderer *)_currentRenderer setActualContainerSize:_actualContainerSize];
                }
                
                // 🔧 关键修复：切换特效后重新应用保存的性能设置
                if (_savedPerformanceSettings) {
                    NSInteger savedFPS = [_savedPerformanceSettings[@"fps"] integerValue];
                    if (savedFPS > 0 && _metalView) {
                        _metalView.preferredFramesPerSecond = savedFPS;
                        NSLog(@"🔄 切换特效后恢复FPS设置: %ldfps", (long)savedFPS);
                    }
                    
                    // 如果有shader复杂度设置，也重新应用
                    float shaderComplexity = [_savedPerformanceSettings[@"shaderComplexity"] floatValue];
                    if (shaderComplexity > 0) {
                        NSMutableDictionary *renderParams = [NSMutableDictionary dictionary];
                        renderParams[@"shaderComplexity"] = @(shaderComplexity);
                        [self setRenderParameters:renderParams];
                    }
                }
                
                // 判断是否为Metal特效
                BOOL isMetalEffect = [self isMetalEffect:effectType];
                
                // 如果是Metal特效，暂停原有频谱特效
                if (isMetalEffect && _originalSpectrumView) {
                    NSLog(@"🎭 暂停原有频谱特效，启用Metal特效");
                    _originalSpectrumView.hidden = YES;
                    [_originalSpectrumView pauseRendering];  // 🔧 真正停止原生特效的渲染
                    _metalView.hidden = NO;
                } else {
                    // 如果不是Metal特效，显示原有频谱特效
                    NSLog(@"🎵 启用原有频谱特效，暂停Metal特效");
                    if (_originalSpectrumView) {
                        _originalSpectrumView.hidden = NO;
                        [_originalSpectrumView resumeRendering];  // 🔧 恢复原生特效的渲染
                    }
                    if (_metalView) _metalView.hidden = YES;
                }
                
                // 应用设置
                NSString *settingsKey = [NSString stringWithFormat:@"effect_%lu", (unsigned long)effectType];
                NSDictionary *settings = _effectSettings[settingsKey];
                if (settings) {
                    [_currentRenderer setRenderParameters:settings];
                }
                
                _currentEffectType = effectType;
                [self updateMetalViewDrawableSizeForEffect:effectType];

                // 神经共振在 A15（iPhone 13 Pro Max）上使用更稳的帧率，显著降GPU占用
                if (effectType == VisualEffectTypeNeuralResonance) {
                    NSInteger targetFPS = 24;
                    if (_metalView.preferredFramesPerSecond != targetFPS) {
                        _metalView.preferredFramesPerSecond = targetFPS;
                        NSLog(@"🧠 神经共振启用低负载帧率: %ldfps", (long)targetFPS);
                    }
                } else if (effectType == VisualEffectTypeWormholeDrive) {
                    NSInteger targetFPS = 18;
                    if (_metalView.preferredFramesPerSecond != targetFPS) {
                        _metalView.preferredFramesPerSecond = targetFPS;
                        NSLog(@"🌀 虫洞穿梭启用稳定帧率: %ldfps", (long)targetFPS);
                    }
                } else if (effectType == VisualEffectTypeVisualLyricsTunnel) {
                    NSInteger targetFPS = 24;
                    if (_metalView.preferredFramesPerSecond != targetFPS) {
                        _metalView.preferredFramesPerSecond = targetFPS;
                        NSLog(@"📝 视觉歌词启用电影感帧率: %ldfps", (long)targetFPS);
                    }
                } else if (!_savedPerformanceSettings && _metalView.preferredFramesPerSecond < 30) {
                    _metalView.preferredFramesPerSecond = 30;
                }
                
                // 开始渲染（仅对Metal特效）
                if (isMetalEffect) {
                    // 🔧 修复：切换Metal特效后总是启动渲染
                    [_currentRenderer startRendering];
                    _isEffectActive = YES;  // 确保标志被设置
                    NSLog(@"▶️ ParticleFlow: 已启动渲染，isEffectActive=%d", _isEffectActive);
                    
                    // 🔍 调试：检查MTKView的状态
                    NSLog(@"🔍 MTKView状态:");
                    NSLog(@"   hidden: %d", _metalView.hidden);
                    NSLog(@"   alpha: %.2f", _metalView.alpha);
                    NSLog(@"   frame: %@", NSStringFromCGRect(_metalView.frame));
                    NSLog(@"   superview: %@", _metalView.superview);
                    NSLog(@"   paused: %d", _metalView.paused);
                    NSLog(@"   device: %@", _metalView.device.name);
                    NSLog(@"   clearColor: (%.2f, %.2f, %.2f, %.2f)", 
                          _metalView.clearColor.red, _metalView.clearColor.green, 
                          _metalView.clearColor.blue, _metalView.clearColor.alpha);
                }
                
                // 通知代理
                if ([_delegate respondsToSelector:@selector(visualEffectManager:didChangeEffect:)]) {
                    [_delegate visualEffectManager:self didChangeEffect:effectType];
                }
                
                NSLog(@"✅ 成功切换到特效: %@", [[VisualEffectRegistry sharedRegistry] effectInfoForType:effectType].name);
            } else {
                NSLog(@"❌ 创建渲染器失败: %lu", (unsigned long)effectType);
                // 回退到霓虹效果
                if (effectType != VisualEffectTypeNeonGlow) {
                    [self setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];
                }
            }
        } @catch (NSException *exception) {
            NSLog(@"❌ 渲染器创建异常: %@", exception.reason);
            // 回退到霓虹效果
            if (effectType != VisualEffectTypeNeonGlow) {
                [self setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];
            }
        }
    } else {
        NSLog(@"❌ 特效不受支持: %lu", (unsigned long)effectType);
        // 回退到霓虹效果
        if (effectType != VisualEffectTypeNeonGlow) {
            [self setCurrentEffect:VisualEffectTypeNeonGlow animated:NO];
        }
    }
}

- (void)setupFluidSimulationSafety {
    // 🔋 优化：流体模拟已通过全局30fps优化，无需额外降低帧率
    NSLog(@"🌊 流体模拟优化已启用");
    
    // 设置优化的渲染参数（保持视觉效果）
    NSMutableDictionary *safeParams = [NSMutableDictionary dictionary];
    safeParams[@"fluidQuality"] = @(0.75);  // 提高到0.75（保持效果）
    safeParams[@"particleCount"] = @(10);   // 提高到10（保持效果）
    safeParams[@"densityIterations"] = @(5); // 提高到5（保持效果）
    safeParams[@"enableSafetyLimits"] = @(YES);
    
    // 更新效果设置
    NSString *settingsKey = @"effect_2"; // FluidSimulation = 2
    [_effectSettings setObject:safeParams forKey:settingsKey];
}

- (void)updateSpectrumData:(NSArray<NSNumber *> *)spectrumData {
    if (_currentRenderer && _isEffectActive) {
        [_currentRenderer updateSpectrumData:spectrumData];
    }
    
    // 🤖 同时将频谱数据发送给AI控制器
    if (_aiAutoModeEnabled && _aiController) {
        [_aiController processSpectrumData:spectrumData];
    }
}

- (void)startRendering {
    _isEffectActive = YES;
    [_currentRenderer startRendering];
    
    // 重置性能统计
    _frameCount = 0;
    _totalFrameTime = 0;
    _lastFrameTime = CACurrentMediaTime();
}

- (void)stopRendering {
    _isEffectActive = NO;
    [_currentRenderer stopRendering];
}

- (void)pauseRendering {
    [_currentRenderer pauseRendering];
    
    // 🔧 如果当前不是Metal特效，也要暂停原生频谱视图
    if (![self isMetalEffect:_currentEffectType] && _originalSpectrumView) {
        [_originalSpectrumView pauseRendering];
    }
}

- (void)resumeRendering {
    [_currentRenderer resumeRendering];
    
    // 🔧 如果当前不是Metal特效，也要恢复原生频谱视图
    if (![self isMetalEffect:_currentEffectType] && _originalSpectrumView) {
        [_originalSpectrumView resumeRendering];
    }
}

- (void)setRenderParameters:(NSDictionary *)parameters {
    [_currentRenderer setRenderParameters:parameters];
    
    // 保存设置
    NSString *settingsKey = [NSString stringWithFormat:@"effect_%lu", (unsigned long)_currentEffectType];
    NSMutableDictionary *currentSettings = [_effectSettings[settingsKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    [currentSettings addEntriesFromDictionary:parameters];
    [_effectSettings setObject:currentSettings forKey:settingsKey];
    
    // 🔋 优化：减少参数更新日志
    // 特别处理星系效果参数
    if (_currentEffectType == VisualEffectTypeGalaxy) {
        // 立即更新渲染器参数
        if ([_currentRenderer respondsToSelector:@selector(setRenderParameters:)]) {
            [_currentRenderer setRenderParameters:parameters];
        }
    }
    
    // 特别处理赛博朋克效果参数
    if (_currentEffectType == VisualEffectTypeCyberPunk) {
        // 立即更新渲染器参数
        if ([_currentRenderer respondsToSelector:@selector(setRenderParameters:)]) {
            [_currentRenderer setRenderParameters:parameters];
        }
    }
}

- (NSDictionary *)performanceStatistics {
    if (_frameCount == 0) return @{};
    
    double averageFrameTime = _totalFrameTime / _frameCount;
    double fps = 1.0 / averageFrameTime;
    
    return @{
        @"fps": @(fps),
        @"averageFrameTime": @(averageFrameTime * 1000), // 毫秒
        @"frameCount": @(_frameCount),
        @"currentEffect": [[VisualEffectRegistry sharedRegistry] effectInfoForType:_currentEffectType].name ?: @"Unknown"
    };
}

- (BOOL)isEffectSupported:(VisualEffectType)effectType {
    return [[VisualEffectRegistry sharedRegistry] deviceSupportsEffect:effectType];
}

- (NSDictionary *)recommendedSettingsForCurrentDevice {
    if (_metalView.device) {
        return [MetalRendererFactory recommendedSettingsForDevice:_metalView.device];
    }
    
    // 默认设置
    return @{
        @"preferredFramesPerSecond": @(30),
        @"enableComplexEffects": @(NO),
        @"particleCount": @(1000),
        @"textureQuality": @"low"
    };
}

#pragma mark - EffectSelectorDelegate

- (void)effectSelector:(EffectSelectorView *)selector didSelectEffect:(VisualEffectType)effectType {
    [self setCurrentEffect:effectType animated:YES];
    [self hideEffectSelector];
    
    // 📊 记录用户手动选择特效（通知 AI Controller）
    [_aiController userDidManuallySelectEffect:effectType];
}

- (void)effectSelector:(EffectSelectorView *)selector didChangeSettings:(NSDictionary *)settings {
    [self setRenderParameters:settings];
}

- (void)effectSelectorDidRequestPreview:(EffectSelectorView *)selector effect:(VisualEffectType)effectType {
    // 实现预览功能
    NSLog(@"🔍 预览特效: %lu", (unsigned long)effectType);
}

#pragma mark - MetalRendererDelegate

- (void)metalRenderer:(id<MetalRenderer>)renderer didFinishFrame:(NSTimeInterval)frameTime {
    // 更新性能统计
    _frameCount++;
    NSTimeInterval currentTime = CACurrentMediaTime();
    _totalFrameTime += (currentTime - _lastFrameTime);
    _lastFrameTime = currentTime;
    
    // 每100帧报告一次性能
    if (_frameCount % 100 == 0) {
        NSDictionary *stats = [self performanceStatistics];
        if ([_delegate respondsToSelector:@selector(visualEffectManager:didUpdatePerformance:)]) {
            [_delegate visualEffectManager:self didUpdatePerformance:stats];
        }
    }
}

- (void)metalRenderer:(id<MetalRenderer>)renderer didEncounterError:(NSError *)error {
    NSLog(@"❌ 渲染错误: %@", error.localizedDescription);
    
    if ([_delegate respondsToSelector:@selector(visualEffectManager:didEncounterError:)]) {
        [_delegate visualEffectManager:self didEncounterError:error];
    }
}

- (void)containerViewDidChangeFrame:(NSNotification *)notification {
    // 当容器视图大小变化时，重新调整Metal视图大小
    if (_metalView) {
        CGRect containerBounds = _effectContainerView.bounds;
        
        // 更新实际容器尺寸
        _actualContainerSize = containerBounds.size;
        
        // 使用较长的边作为正方形尺寸（通常是高度）
        CGFloat squareSize = MAX(containerBounds.size.width, containerBounds.size.height);
        
        // 计算居中位置
        CGFloat x = (containerBounds.size.width - squareSize) / 2.0;
        CGFloat y = (containerBounds.size.height - squareSize) / 2.0;
        
        // 更新Metal视图frame为居中的正方形
        _metalView.frame = CGRectMake(x, y, squareSize, squareSize);
        
        // 更新绘制尺寸（不同特效可能有不同渲染分辨率策略）
        [self updateMetalViewDrawableSizeForEffect:_currentEffectType];
        
        // 更新当前renderer的容器尺寸
        if (_currentRenderer && [_currentRenderer respondsToSelector:@selector(setActualContainerSize:)]) {
            [(BaseMetalRenderer *)_currentRenderer setActualContainerSize:_actualContainerSize];
        }
        
        // 🔋 优化：减少尺寸变化日志
        // NSLog(@"🌌 Metal视图尺寸已更新");
    }
}

- (BOOL)isMetalEffect:(VisualEffectType)effectType {
    // 判断是否为需要Metal渲染的特效
    switch (effectType) {
        // 旧Metal特效
        case VisualEffectTypeNeonGlow:
        case VisualEffectType3DWaveform:
        case VisualEffectTypeFluidSimulation:
        case VisualEffectTypeQuantumField:
        case VisualEffectTypeHolographic:
        case VisualEffectTypeCyberPunk:
        case VisualEffectTypeGalaxy:
        case VisualEffectTypeLiquidMetal:
        case VisualEffectTypeLightning:
        // 新Metal特效
        case VisualEffectTypeCircularWave:
        case VisualEffectTypeParticleFlow:
        case VisualEffectTypeAudioReactive3D:
        case VisualEffectTypeFireworks:
        case VisualEffectTypeGeometricMorph:
        case VisualEffectTypeFractalPattern:
        case VisualEffectTypeChromaticCaustics:
        // 实验性Metal特效
        case VisualEffectTypeAuroraRipples:
        case VisualEffectTypeStarVortex:
        case VisualEffectTypeNeonSpringLines:
        case VisualEffectTypeCherryBlossomSnow:
        case VisualEffectTypeTyndallBeam:
        case VisualEffectTypeNeuralResonance:
        case VisualEffectTypeWormholeDrive:
        case VisualEffectTypePrismResonance:
        case VisualEffectTypeVisualLyricsTunnel:
            return YES;

        case VisualEffectTypeUserMediaBackground:
            return NO;
            
        case VisualEffectTypeClassicSpectrum:
        default:
            return NO;
    }
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

#pragma mark - AI 自动模式

- (void)startAIModeWithSongName:(NSString *)songName artist:(NSString *)artist {
    if (!_aiAutoModeEnabled) {
        NSLog(@"🔇 AI自动模式已禁用");
        return;
    }
    
    [_aiController startWithSongName:songName artist:artist];
    NSLog(@"🤖 AI自动模式已启动: %@ - %@", songName, artist ?: @"Unknown");
}

- (void)stopAIMode {
    [_aiController stop];
    NSLog(@"🤖 AI自动模式已停止");
}

- (void)userDidManuallySelectEffect:(VisualEffectType)effectType {
    [_aiController userDidManuallySelectEffect:effectType];
}

- (void)userDidSkipSong {
    [_aiController userDidSkipSong];
}

- (void)userDidFinishListening {
    [_aiController userDidFinishListening];
}

#pragma mark - VisualEffectAIControllerDelegate

- (void)aiController:(id)controller didSelectEffect:(VisualEffectType)effect withDecision:(EffectDecision *)decision {
    if (!_aiAutoModeEnabled) {
        NSLog(@"⚠️ AI模式未启用，跳过特效切换");
        return;
    }
    
    NSString *effectName = [[VisualEffectRegistry sharedRegistry] effectInfoForType:effect].name ?: @"Unknown";
    NSLog(@"🤖 AI选择特效: %@ (ID:%lu, 置信度: %.2f)", effectName, (unsigned long)effect, decision.confidence);
    
    // 应用AI选择的特效
    [self setCurrentEffect:effect animated:YES];
    NSLog(@"🎨 正在应用AI选择的特效: %@", effectName);
    
    // 应用AI推荐的参数
    if (decision.parameters) {
        [self setRenderParameters:decision.parameters];
        
        // === 应用颜色配置到经典频谱 ===
        NSDictionary *colorConfig = decision.parameters[@"effectColor"];
        NSLog(@"🔍 颜色配置检查: colorConfig=%@, effect=%lu, spectrumView=%@",
              colorConfig ? @"有" : @"无", (unsigned long)effect, _originalSpectrumView ? @"有" : @"无");
        
        if (colorConfig && effect == VisualEffectTypeClassicSpectrum) {
            if (_originalSpectrumView) {
                [_originalSpectrumView applyTheme:colorConfig];
                NSLog(@"🎨 已应用AI颜色配置到经典频谱: %@", colorConfig);
            } else {
                NSLog(@"⚠️ _originalSpectrumView 为空，无法应用颜色配置");
            }
        }
    } else {
        NSLog(@"⚠️ decision.parameters 为空");
    }
    
    // 通知代理
    if ([_delegate respondsToSelector:@selector(visualEffectManager:aiDidSelectEffect:withDecision:)]) {
        [_delegate visualEffectManager:self aiDidSelectEffect:effect withDecision:decision];
    }
}

- (void)aiController:(id)controller didTuneParameters:(EffectParameters *)parameters {
    if (!_aiAutoModeEnabled) return;
    
    // 将EffectParameters转换为字典并应用
    NSDictionary *paramsDict = [parameters toDictionary];
    
    // 只应用部分实时参数（避免干扰用户设置的静态参数）
    NSMutableDictionary *realtimeParams = [NSMutableDictionary dictionary];
    if (paramsDict[@"animationSpeed"]) realtimeParams[@"animationSpeed"] = paramsDict[@"animationSpeed"];
    if (paramsDict[@"brightness"]) realtimeParams[@"brightness"] = paramsDict[@"brightness"];
    if (paramsDict[@"glowIntensity"]) realtimeParams[@"glowIntensity"] = paramsDict[@"glowIntensity"];
    
    if (realtimeParams.count > 0) {
        [_currentRenderer setRenderParameters:realtimeParams];
    }
    
    // 通知代理
    if ([_delegate respondsToSelector:@selector(visualEffectManager:aiDidTuneParameters:)]) {
        [_delegate visualEffectManager:self aiDidTuneParameters:parameters];
    }
}

- (void)aiController:(id)controller didDetectSegmentChange:(MusicSegment)segment suggestedEffect:(VisualEffectType)effect {
    if (!_aiAutoModeEnabled) return;
    
    NSLog(@"🎭 AI检测到段落变化，建议切换到特效: %lu", (unsigned long)effect);
    
    // 平滑切换到建议的特效
    if (effect != _currentEffectType) {
        [self setCurrentEffect:effect animated:YES];
    }
}

- (void)aiController:(id)controller didDetectBeatWithIntensity:(float)intensity {
    if (_currentEffectType == VisualEffectTypeWormholeDrive && _currentRenderer) {
        float clamped = fmaxf(0.0f, fminf(intensity, 0.9f));
        [_currentRenderer setRenderParameters:@{@"beatTrigger": @(clamped)}];
    }
}

- (void)aiController:(id)controller didClassifyStyle:(MusicStyle)style confidence:(float)confidence {
    NSLog(@"🎵 AI识别音乐风格: %@ (置信度: %.2f)",
          [MusicStyleClassifier nameForStyle:style], confidence);
}

#pragma mark - 性能设置

- (void)applyPerformanceSettings:(NSDictionary *)settings {
    // 检查参数有效性
    if (!settings || [settings count] == 0) {
        NSLog(@"❌ 性能设置为空，使用默认值");
        settings = @{
            @"fps": @(30),
            @"msaa": @(1),
            @"shaderComplexity": @(1.0)
        };
    }
    
    // 💾 保存设置，切换特效时会重新应用
    _savedPerformanceSettings = [settings copy];
    
    NSInteger fps = [settings[@"fps"] integerValue];
    NSInteger msaa = [settings[@"msaa"] integerValue];
    float shaderComplexity = [settings[@"shaderComplexity"] floatValue];
    NSString *mode = settings[@"mode"] ?: @"balanced";
    
    NSLog(@"⚙️ 应用性能设置:");
    NSLog(@"   模式: %@", mode);
    NSLog(@"   FPS: %ld", (long)fps);
    NSLog(@"   MSAA: %ldx", (long)msaa);
    NSLog(@"   Shader复杂度: %.1f", shaderComplexity);
    
    // 更新帧率
    if (_metalView && fps > 0) {
        _metalView.preferredFramesPerSecond = fps;
        NSLog(@"✅ 帧率已立即更新为 %ldfps", (long)fps);
    } else {
        NSLog(@"⚠️ 帧率无效或Metal视图未初始化");
    }
    
    // 更新MSAA（需要重新创建渲染管线，在下次切换特效时生效）
    if (_metalView && msaa > 0) {
        // 保存设置，在下次创建渲染器时应用
        _effectSettings[@"msaa_setting"] = @(msaa);
        NSLog(@"✅ MSAA设置已保存为 %ldx（切换特效后生效）", (long)msaa);
        
        // 只有在MSAA不是1的时候才提示
        if (msaa > 1) {
            dispatch_async(dispatch_get_main_queue(), ^{
                UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"ℹ️ 提示" 
                                                                               message:@"抗锯齿设置需要切换特效后生效\n\n建议：切换到其他特效再切回当前特效" 
                                                                        preferredStyle:UIAlertControllerStyleAlert];
                [alert addAction:[UIAlertAction actionWithTitle:@"知道了" style:UIAlertActionStyleDefault handler:nil]];
                
                UIViewController *rootVC = [UIApplication sharedApplication].keyWindow.rootViewController;
                if (rootVC) {
                    [rootVC presentViewController:alert animated:YES completion:nil];
                }
            });
        }
    } else {
        NSLog(@"⚠️ MSAA无效或Metal视图未初始化");
    }
    
    // 更新Shader复杂度（添加到渲染参数）
    if (shaderComplexity > 0) {
        NSMutableDictionary *renderParams = [NSMutableDictionary dictionary];
        renderParams[@"shaderComplexity"] = @(shaderComplexity);
        [self setRenderParameters:renderParams];
        NSLog(@"✅ Shader复杂度已立即更新为 %.1f", shaderComplexity);
    } else {
        NSLog(@"⚠️ Shader复杂度无效");
    }
    
    // 输出性能预估
    NSString *powerConsumption = @"中等";
    NSString *expectedBattery = @"4-5小时";
    
    if (fps <= 20 && msaa == 1 && shaderComplexity <= 0.8) {
        powerConsumption = @"低（省电模式）";
        expectedBattery = @"5-6小时";
    } else if (fps >= 60 || msaa >= 4 || shaderComplexity >= 1.5) {
        powerConsumption = @"高（性能模式）";
        expectedBattery = @"2-3小时";
    }
    
    NSLog(@"📊 性能预估:");
    NSLog(@"   功耗等级: %@", powerConsumption);
    NSLog(@"   预计续航: %@", expectedBattery);
    NSLog(@"   GPU负载: %@", fps <= 20 ? @"低" : (fps <= 30 ? @"中" : @"高"));
}

@end
