// FractalPatternShader.metal
// 半透明柔光流体波动球 - Apple 风格音频可视化

#include "ShaderCommon.metal"

// === 哈希函数 - 用于粒子抖动 ===
static inline float hash21(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float2 hash22(float2 p) {
    p = float2(dot(p, float2(127.1, 311.7)), dot(p, float2(269.5, 183.3)));
    return fract(sin(p) * 43758.5453);
}

// === 柔和噪声 - 用于流体感 ===
static inline float softNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f); // Smoothstep
    
    float a = hash21(i);
    float b = hash21(i + float2(1.0, 0.0));
    float c = hash21(i + float2(0.0, 1.0));
    float d = hash21(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// === 体积噪声 - 多层叠加（优化：减少层数）===
static inline float volumeNoise(float2 p, float time) {
    float n = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    
    // 优化：从4层减少到3层，保持视觉质量
    for (int i = 0; i < 3; i++) {
        n += softNoise(p * frequency + time * 0.1) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
    }
    
    return n;
}

fragment float4 fractalPatternFragment(RasterizerData in [[stage_in]],
                                       constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 🎵 音频分析 - 优化：间隔采样
    float bassAudio = 0.0, midAudio = 0.0, trebleAudio = 0.0;
    for (int i = 0; i < 15; i += 2) bassAudio += uniforms.audioData[i].x; // 间隔2采样
    for (int i = 18; i < 53; i += 3) midAudio += uniforms.audioData[i].x; // 间隔3采样
    for (int i = 50; i < 75; i += 3) trebleAudio += uniforms.audioData[i].x; // 间隔3采样
    
    float bassIntensity = min((bassAudio / 8.0) * 1.5, 1.2);
    float midIntensity = min((midAudio / 12.0) * 1.3, 1.0);
    float trebleIntensity = min((trebleAudio / 9.0) * 1.4, 1.0);
    float averageAudio = (bassIntensity + midIntensity + trebleIntensity) / 3.0;
    
    // 🎯 低音冲击检测 - 快速抖动触发
    float bassImpact = smoothstep(0.3, 0.8, bassIntensity);
    float impactDecay = exp(-fmod(time * 8.0, 6.28) * 2.0); // 快速衰减
    float shockWave = bassImpact * impactDecay;
    
    // 🫧 呼吸式脉动 - 低音驱动
    float breathPhase = sin(time * 0.8) * 0.5 + 0.5;
    float breathScale = 1.0 + breathPhase * 0.15 + bassIntensity * 0.25 + shockWave * 0.4;
    
    // 🌊 流体网格点阵 - 增加密度形成球体
    float2 gridUV = uv * 18.0; // 点阵密度（从12提升到18，更密集）
    float2 gridID = floor(gridUV);
    float2 gridLocal = fract(gridUV);
    
    float finalAlpha = 0.0;
    float3 finalColor = float3(0.0);
    
    // 预先计算中心位置用于球体遮罩
    float2 center = float2(0.5, 0.5);
    float2 toCenter = uv - center;
    float centerDist = length(toCenter);
    
    // 遍历周围的网格点 - 优化：只检查最近的点
    for (float y = -1.0; y <= 1.0; y += 1.0) {
        for (float x = -1.0; x <= 1.0; x += 1.0) {
            float2 neighbor = float2(x, y);
            float2 cellID = gridID + neighbor;
            
            // 🎲 每个点的随机偏移
            float2 randomOffset = hash22(cellID) - 0.5;
            
            // 🎵 音频驱动的抖动 - 高音控制基础抖动
            float jitterAmount = trebleIntensity * 0.4 + midIntensity * 0.2;
            
            // 💥 低音冲击 - 剧烈快速抖动
            float impactJitter = shockWave * 0.8;
            float impactSpeed = 15.0; // 冲击时加速
            
            float2 audioJitter = float2(
                sin(time * (3.0 + impactJitter * impactSpeed) + cellID.x * 10.0) * (jitterAmount + impactJitter),
                cos(time * (3.0 + impactJitter * impactSpeed) + cellID.y * 10.0) * (jitterAmount + impactJitter)
            );
            
            // 点的最终位置
            float2 pointPos = neighbor + randomOffset * 0.6 + audioJitter;
            float2 toPoint = gridLocal - pointPos;
            
            // 🫧 呼吸式距离场
            float dist = length(toPoint) / breathScale;
            
            // 柔和的点光晕 - 密度增加后调整点大小
            float glowRadius = 10.0 - bassIntensity * 2.5; // 基础更紧凑，低音时扩大
            float pointGlow = exp(-dist * glowRadius) * 0.7; // 降低基础亮度避免过曝
            
            // 🔊 低音增强亮度 - 整体点阵变亮
            float bassBrightness = 1.0 + bassIntensity * 1.2 + shockWave * 1.5;
            pointGlow *= bassBrightness;
            
            // 🌟 高音闪烁 - 点亮度脉冲
            float treblePulse = sin(time * 6.0 + hash21(cellID) * 6.28) * 0.5 + 0.5;
            treblePulse = pow(treblePulse, 3.0) * trebleIntensity;
            pointGlow *= (1.0 + treblePulse * 0.8);
            
            // 🎨 基于位置的色相变化 + 中音色彩偏移
            float hue = hash21(cellID) * 0.3 + time * 0.05 + averageAudio * 0.2;
            hue += midIntensity * 0.15; // 中音改变色相
            float saturation = 0.6 + midIntensity * 0.3; // 中音增强饱和度
            float brightness = 0.9 + bassIntensity * 0.3; // 低音增加颜色亮度
            float3 pointColor = hsv2rgb(float3(fract(hue + 0.55), saturation, brightness));
            
            // 🌐 球体遮罩 - 让点在球体外部逐渐消失
            float particleSphereRadius = 0.32 + bassIntensity * 0.15; // 球体影响范围
            float sphereFade = smoothstep(particleSphereRadius + 0.2, particleSphereRadius - 0.05, centerDist);
            pointGlow *= (0.3 + sphereFade * 0.7); // 外部保留30%，内部100%
            
            finalColor += pointColor * pointGlow;
            finalAlpha += pointGlow;
        }
    }
    
    // 🌀 体积感 - 折射式噪声层（优化：降低采样频率）
    float angle = atan2(toCenter.y, toCenter.x);
    
    float volumeFog = volumeNoise(uv * 2.5, time * 0.5); // 降低频率
    volumeFog = pow(volumeFog, 1.5) * 0.3;
    
    // 🎵 中音增强体积雾 - 让雾气随中音柔和变化
    volumeFog *= (1.0 + midIntensity * 0.5);
    
    // 🔮 中心球形渐变 - 调整为合适大小
    float sphereRadius = 0.28 + bassIntensity * 0.12; // 基础半径0.28，音频响应0.12
    float sphereMask = smoothstep(sphereRadius + 0.15, sphereRadius - 0.1, centerDist);
    
    // 🌊 呼吸波纹 - 从中心扩散（中音强化）
    float ripple = sin(centerDist * 20.0 - time * 4.0) * 0.5 + 0.5;
    ripple = pow(ripple, 3.0) * midIntensity * 0.5;
    
    // 🎸 中音脉冲环 - 扩散的能量环
    float midRing = sin(centerDist * 30.0 - time * 8.0 + midIntensity * 10.0) * 0.5 + 0.5;
    midRing *= smoothstep(0.1, 0.2, centerDist) * smoothstep(0.45, 0.35, centerDist);
    midRing = pow(midRing, 4.0) * midIntensity * 0.6;
    
    // 🎵 中音柔光层 - 旋转的柔和光晕
    float midGlowAngle = angle * 0.5 + time * 0.3 * midIntensity; // 缓慢旋转
    float midGlowPattern = sin(midGlowAngle * 3.0) * 0.5 + 0.5; // 3瓣柔光
    midGlowPattern = pow(midGlowPattern, 2.0); // 柔和边缘
    float midGlowMask = exp(-centerDist * 4.0) * (1.0 - exp(-centerDist * 12.0)); // 环形分布
    float midGlow = midGlowPattern * midGlowMask * midIntensity * 0.4;
    
    // 🌊 中音流体波动 - 柔和的颜色流动
    float flowPhase = sin(time * 1.5 + centerDist * 8.0) * 0.5 + 0.5;
    flowPhase += cos(angle * 2.0 - time * 0.8) * 0.3;
    flowPhase = saturate(flowPhase);
    float midFlow = flowPhase * exp(-centerDist * 5.0) * midIntensity * 0.3;
    
    // 🎶 中音呼吸光雾 - 整体球体的柔和明暗呼吸
    float breathGlow = sin(time * 1.2 + centerDist * 3.0) * 0.5 + 0.5;
    breathGlow = pow(breathGlow, 1.5);
    breathGlow *= smoothstep(0.5, 0.1, centerDist) * midIntensity * 0.25;
    
    // ⚡ 高音径向光束 - 从中心放射
    float trebleBeams = 0.0;
    float beamAngle = angle + time * 1.0;
    float beamPattern = abs(sin(beamAngle * 8.0)); // 8条光束
    beamPattern = pow(beamPattern, 6.0); // 锐化成细光束
    float beamMask = smoothstep(0.05, 0.15, centerDist) * smoothstep(0.4, 0.3, centerDist);
    trebleBeams = beamPattern * beamMask * trebleIntensity * 0.7;
    
    // 合成最终颜色 - 分层叠加
    finalColor = finalColor * sphereMask + volumeFog;
    finalColor += ripple * float3(0.9, 0.95, 1.0); // 蓝白色波纹
    
    // 🎸 中音能量环（暖色调）
    finalColor += midRing * float3(0.95, 0.7, 1.0); // 粉紫色
    
    // 🎵 中音柔光层（柔和橙粉色）
    finalColor += midGlow * float3(1.0, 0.85, 0.75); // 暖橙粉
    
    // 🌊 中音流体波动（青绿色）
    finalColor += midFlow * float3(0.6, 0.95, 0.85); // 薄荷青
    
    // 🎶 中音呼吸光雾（柔和紫色）
    finalColor += breathGlow * float3(0.85, 0.75, 1.0); // 淡紫色
    
    // ⚡ 高音光束（冷白色）
    finalColor += trebleBeams * float3(1.0, 0.95, 0.85); // 亮黄白色
    
    // ✨ 边缘光晕散射 - 调整为球体边缘
    float edgeGlow = smoothstep(sphereRadius - 0.05, sphereRadius + 0.05, centerDist) 
                   * (1.0 - smoothstep(sphereRadius + 0.05, sphereRadius + 0.2, centerDist));
    edgeGlow *= (0.5 + averageAudio * 0.5);
    finalColor += edgeGlow * float3(0.7, 0.85, 1.0) * 0.8;
    
    // 💥 低音冲击闪光
    float impactFlash = shockWave * exp(-centerDist * 3.0);
    finalColor += impactFlash * float3(1.0, 1.0, 0.9) * 0.5;
    
    // 🎭 半透明度控制 - 包含所有特效
    finalAlpha = saturate(finalAlpha * sphereMask * 0.7 + volumeFog + ripple + midRing + 
                          midGlow * 0.6 + midFlow * 0.5 + breathGlow * 0.4 + trebleBeams * 0.5);
    finalAlpha = mix(0.3, 0.9, finalAlpha); // 保持半透明
    
    // 🌈 柔和的颜色增强
    finalColor = pow(finalColor, float3(0.9)); // 轻微提亮
    finalColor *= (0.8 + averageAudio * 0.4);
    
    return float4(finalColor, finalAlpha);
}

