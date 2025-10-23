//
//  LuminousMistCoreShader.metal
//  AudioSampleBuffer
//
//  「漂浮光点 (Floating Lights)」
//  适合慢歌抒情的柔和视觉效果
//  灵感：萤火虫、漂浮的蒲公英、夜空中的星光
//

#include "ShaderCommon.metal"

// ============================================================================
// 简单哈希函数 - 用于生成伪随机数
// ============================================================================

static inline float hash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static inline float2 hash2(float n) {
    return fract(sin(float2(n, n + 1.0)) * float2(43758.5453123, 22578.1459123));
}

// ============================================================================
// 柔光球体 - 单个光球的渲染
// ============================================================================

static inline float softCircle(float2 uv, float2 pos, float radius, float softness) {
    float dist = length(uv - pos);
    return smoothstep(radius + softness, radius - softness, dist);
}

// 更柔和的光晕效果
static inline float glowCircle(float2 uv, float2 pos, float radius, float intensity) {
    float dist = length(uv - pos);
    float glow = exp(-dist * dist / (radius * radius)) * intensity;
    return glow;
}

// ============================================================================
// 光点结构
// ============================================================================

struct LightOrb {
    float2 position;
    float size;
    float brightness;
    float3 color;
    float phase; // 用于闪烁动画
    float alpha; // 淡入淡出
};

// 生成光点属性（基于ID）
static inline LightOrb generateLightOrb(int id, float time, float audioEnergy, float trebleEnergy) {
    LightOrb orb;
    
    float seed = float(id) * 12.345;
    
    // 位置：从屏幕底部外(-0.2)出现，向上漂浮到顶部外(1.2)消失
    float x = hash(seed); // 0.0 到 1.0 全屏宽度
    
    // 生命周期：-0.2 到 1.2（完整的出现和消失过程）
    float cycleSpeed = 0.03 + hash(seed + 2.0) * 0.02; // 每个光球不同速度
    float lifecycle = fract(hash(seed + 1.0) + time * cycleSpeed);
    float y = -0.2 + lifecycle * 1.4; // -0.2 到 1.2 的范围
    
    // 计算淡入淡出 alpha
    float fadeIn = smoothstep(-0.2, 0.0, y);  // 底部淡入
    float fadeOut = smoothstep(1.2, 1.0, y); // 顶部淡出
    orb.alpha = fadeIn * fadeOut;
    
    // 添加轻微的水平漂移（正弦波动）
    float xDrift = sin(time * 0.5 + seed) * 0.06;
    x = clamp(x + xDrift, 0.0, 1.0);
    
    orb.position = float2(x, y);
    
    // 大小：分为大、中、小三种（稍微增大，因为数量减少）
    float sizeType = hash(seed + 3.0);
    if (sizeType < 0.3) {
        // 大光球 (30%)
        orb.size = 0.10 + hash(seed + 4.0) * 0.05; // 增大
    } else if (sizeType < 0.7) {
        // 中等光球 (40%)
        orb.size = 0.05 + hash(seed + 5.0) * 0.04; // 增大
    } else {
        // 小光点 (30%)
        orb.size = 0.02 + hash(seed + 6.0) * 0.02; // 增大
    }
    
    // 音频控制大小（增强响应）
    orb.size *= (1.0 + audioEnergy * 0.8);
    
    // 亮度：随时间和音频变化（增强音频响应）
    float baseIntensity = 0.6 + hash(seed + 7.0) * 0.4;
    float flickerSpeed = 0.3 + hash(seed + 8.0) * 0.5;
    float flicker = sin(time * flickerSpeed + seed) * 0.5 + 0.5;
    orb.brightness = baseIntensity * (0.7 + flicker * 0.3) * (1.0 + audioEnergy * 1.2); // 增强响应
    
    // 颜色：温暖色调 + 高音响应（变黄红色）
    float colorChoice = hash(seed + 9.0);
    float3 baseColor;
    
    if (colorChoice < 0.4) {
        // 暖黄色
        baseColor = float3(1.0, 0.9, 0.7);
    } else if (colorChoice < 0.7) {
        // 淡粉色
        baseColor = float3(1.0, 0.8, 0.85);
    } else {
        // 浅蓝色
        baseColor = float3(0.7, 0.85, 1.0);
    }
    
    // 高音时混合黄红色（热烈色调）
    float3 trebleColor = float3(1.0, 0.7, 0.3); // 橙黄色
    if (trebleEnergy > 0.3) {
        trebleColor = float3(1.0, 0.5, 0.2); // 更红
    }
    
    // 根据高音强度混合颜色
    orb.color = mix(baseColor, trebleColor, trebleEnergy * 0.8);
    
    orb.phase = seed;
    
    return orb;
}

// ============================================================================
// 背景渐变
// ============================================================================

static inline float3 renderBackground(float2 uv, float time, float audioEnergy) {
    // 深色柔和渐变背景
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);
    
    // 基础渐变：从中心到边缘
    float3 centerColor = float3(0.05, 0.08, 0.15); // 深蓝紫
    float3 edgeColor = float3(0.02, 0.02, 0.05); // 几乎黑色
    
    float gradient = smoothstep(0.0, 0.8, dist);
    float3 bgColor = mix(centerColor, edgeColor, gradient);
    
    // 轻微的色彩波动
    float colorWave = sin(time * 0.3 + uv.y * 2.0) * 0.5 + 0.5;
    bgColor += float3(0.02, 0.01, 0.03) * colorWave * audioEnergy;
    
    return bgColor;
}

// ============================================================================
// 主渲染函数
// ============================================================================

fragment float4 luminousMistCoreFragment(RasterizerData in [[stage_in]],
                                          constant Uniforms &uniforms [[buffer(0)]]) {
    // 获取UV坐标（带宽高比校正）
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 🎵 音频分析（极简版，参考赛博朋克优化）
    float bassEnergy = 0.0;
    float midEnergy = 0.0;
    float trebleEnergy = 0.0;
    
    // 减少采样次数，提升性能
    for (int i = 0; i < 8; i++) {
        bassEnergy += uniforms.audioData[i].x;
    }
    for (int i = 20; i < 35; i++) {
        midEnergy += uniforms.audioData[i].x;
    }
    for (int i = 50; i < 65; i++) {
        trebleEnergy += uniforms.audioData[i].x;
    }
    
    bassEnergy = min(bassEnergy / 8.0, 1.0);
    midEnergy = min(midEnergy / 15.0, 1.0);
    trebleEnergy = min(trebleEnergy / 15.0, 1.0);
    
    float avgEnergy = (bassEnergy + midEnergy + trebleEnergy) / 3.0;
    
    // 1. 渲染背景
    float3 color = renderBackground(uv, time, avgEnergy);
    
    // 2. 渲染光点（减少到8个，中音控制大小，高音控制颜色）
    const int numLights = 8;
    
    for (int i = 0; i < numLights; i++) {
        LightOrb orb = generateLightOrb(i, time, midEnergy, trebleEnergy); // 传入高音参数
        
        // 渲染整个生命周期（包括屏幕外的淡入淡出）
        // 不需要跳过，让光球自然出现和消失
        
        // 光晕效果（主要发光）
        float glow = glowCircle(uv, orb.position, orb.size, orb.brightness);
        
        // 应用 alpha 淡入淡出
        glow *= orb.alpha;
        
        // 叠加光点颜色（增强亮度）
        color += orb.color * glow * 3.0;
    }
    
    // 3. 添加闪烁星点（性能优化版，仅5个）
    for (int i = 0; i < 5; i++) {
        float seed = float(i) * 34.567;
        
        // 固定位置（分布更分散）
        float2 starPos = hash2(seed);
        
        // 确保分布在屏幕四角和中心（避免聚集）
        starPos = starPos * 0.8 + 0.1; // 映射到 0.1-0.9 范围
        
        // 轻微抖动
        float jitterX = sin(time * 0.8 + seed) * 0.01;
        float jitterY = cos(time * 0.6 + seed * 1.5) * 0.01;
        starPos += float2(jitterX, jitterY);
        
        // 简化的闪烁
        float twinkle = sin(time * 1.5 + seed * 10.0) * 0.5 + 0.5;
        twinkle = pow(twinkle, 3.0);
        
        // 渲染星点
        float starGlow = glowCircle(uv, starPos, 0.005, twinkle * (0.5 + trebleEnergy * 0.5));
        color += float3(1.0, 1.0, 1.0) * starGlow * 0.8;
    }
    
    // 5. 柔和的中心光晕（整体氛围）
    float2 center = float2(0.5, 0.5);
    float centerDist = length(uv - center);
    float centerGlow = exp(-centerDist * 2.0) * avgEnergy * 0.2;
    color += float3(0.1, 0.08, 0.15) * centerGlow;
    
    // 6. 全屏显示（移除圆形裁剪）
    // 保持全部效果，无边界限制
    
    // 7. 色调映射（保持柔和）
    color = color / (color + 0.6);
    
    // 7. Gamma校正
    color = pow(color, float3(1.0 / 2.2));
    
    return float4(color, 1.0);
}
