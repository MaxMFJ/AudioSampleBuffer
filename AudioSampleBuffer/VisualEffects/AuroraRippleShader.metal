//
//  AuroraRippleShader.metal
//  AudioSampleBuffer
//
//  极光波纹视觉效果 - 优化版本
//  特色: 自然流动的极光带 + 音频响应的波纹扩散
//  性能优化: 减少循环、简化计算、降低GPU负载
//

#include <metal_stdlib>
#include "ShaderCommon.metal"

using namespace metal;

// ============================================================================
// 极光波纹着色器 - Aurora Ripples (性能优化版)
// ============================================================================

// 简化的噪声函数
float auroraHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

// 简化的噪声（无循环）
float auroraNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    
    float a = auroraHash(i);
    float b = auroraHash(i + float2(1.0, 0.0));
    float c = auroraHash(i + float2(0.0, 1.0));
    float d = auroraHash(i + float2(1.0, 1.0));
    
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 简化的分形噪声 - 仅2次迭代（原来5次）
float auroraFbmFast(float2 p, float time) {
    float value = 0.0;
    value += 0.5 * auroraNoise(p + float2(time * 0.1, 0.0));
    value += 0.25 * auroraNoise(p * 2.0 + float2(time * 0.15, time * 0.1));
    return value * 1.33; // 归一化
}

// 简化的极光曲线
float auroraWaveFast(float x, float time, float frequency, float offset, float audioIntensity) {
    float wave = sin(x * frequency + time * 0.5 + offset) * 0.15;
    wave += sin(x * frequency * 1.7 + time * 0.7 + offset) * 0.08 * audioIntensity;
    return wave;
}

// 优化的极光光带 - 简化计算
float3 auroraBeamFast(float2 uv, float time, float yCenter, float width, 
                       float3 color1, float3 color2, float frequency, float audioIntensity, float phase) {
    // 简化的极光曲线
    float wave = auroraWaveFast(uv.x, time, frequency, phase, audioIntensity);
    
    // 添加轻微噪声
    wave += (auroraNoise(float2(uv.x * 2.0 + time * 0.2, time * 0.1)) - 0.5) * 0.1;
    
    float beamY = yCenter + wave;
    float dist = abs(uv.y - beamY);
    
    // 动态宽度
    float dynamicWidth = width * (1.0 + audioIntensity * 0.3);
    
    // 简化的光带强度
    float intensity = 1.0 - smoothstep(0.0, dynamicWidth, dist);
    intensity = intensity * intensity;
    
    // 简化的边缘发光
    intensity += exp(-dist * 6.0 / dynamicWidth) * 0.4;
    
    // 简化的颜色混合
    float colorMix = sin(uv.x * 2.0 + time * 0.3) * 0.5 + 0.5;
    float3 color = mix(color1, color2, colorMix);
    
    return color * intensity;
}

// 简化的星空背景 - 单层，减少计算
float3 starFieldFast(float2 uv, float time) {
    float3 stars = float3(0.0);
    
    float scale = 60.0;
    float2 gridPos = floor(uv * scale);
    float2 gridUV = fract(uv * scale);
    
    float random = auroraHash(gridPos);
    
    if (random > 0.96) {
        float2 starPos = float2(auroraHash(gridPos * 1.5), auroraHash(gridPos * 2.3)) * 0.6 + 0.2;
        float dist = length(gridUV - starPos);
        
        // 简化的闪烁
        float twinkle = sin(time * 2.0 + random * 6.28) * 0.3 + 0.7;
        float starBright = (1.0 - smoothstep(0.0, 0.08, dist)) * twinkle;
        
        stars = float3(0.7, 0.8, 1.0) * starBright * 0.4;
    }
    
    return stars;
}

// 音乐驱动的波纹效果 - 完全由音频能量控制，无音乐则无波纹
// 颜色配置：低频=青色，中频=紫色/粉色，高频=青色
float3 audioRipplesFast(float2 uv, float time, float bassEnergy, float midEnergy, float trebleEnergy) {
    float3 rippleColor = float3(0.0);
    
    // 计算总能量，用于判断是否有音乐
    float totalEnergy = bassEnergy + midEnergy + trebleEnergy;
    
    // 如果几乎没有音频能量，直接返回黑色（无波纹）
    if (totalEnergy < 0.01) {
        return float3(0.0);
    }
    
    // 🔵 第一个波纹 - 低频驱动（鼓点/贝斯触发，青色）
    if (bassEnergy > 0.05) {
        float2 center = float2(0.5, 0.5);
        float dist = length(uv - center);
        // 多层波纹叠加，更明显的效果
        float wave1 = sin(dist * 18.0 - time * 4.5) * 0.5 + 0.5;
        float wave2 = sin(dist * 10.0 - time * 3.0 + 1.0) * 0.5 + 0.5;
        float wave = (wave1 + wave2 * 0.5) * 0.7;
        // 波纹强度由低频能量控制
        float intensity = bassEnergy * 2.0;
        float falloff = exp(-dist * 0.8) * intensity;  // 更慢的衰减，波纹更大
        wave *= falloff;
        // 青色波纹
        rippleColor += float3(0.0, 0.95, 1.0) * wave * 1.2;
    }
    
    // 💜 第二个波纹 - 中频驱动（人声/旋律触发，紫色/粉色）
    if (midEnergy > 0.04) {
        float2 center = float2(0.5 + cos(time * 0.5) * 0.12, 0.5 + sin(time * 0.4) * 0.08);
        float dist = length(uv - center);
        // 双层波纹
        float wave1 = sin(dist * 15.0 - time * 3.5) * 0.5 + 0.5;
        float wave2 = sin(dist * 22.0 - time * 4.0 + 0.5) * 0.5 + 0.5;
        float wave = (wave1 + wave2 * 0.4) * 0.65;
        float intensity = midEnergy * 1.8;
        float falloff = exp(-dist * 0.9) * intensity;
        wave *= falloff;
        // 紫色/粉色混合波纹 - 颜色随时间变化
        float colorShift = sin(time * 0.8) * 0.5 + 0.5;
        float3 purpleColor = float3(0.85, 0.2, 1.0);   // 紫色
        float3 pinkColor = float3(1.0, 0.4, 0.85);     // 粉色
        float3 midColor = mix(purpleColor, pinkColor, colorShift);
        rippleColor += midColor * wave * 1.1;
    }
    
    // 🔵 第三个波纹 - 高频驱动（高音/镲片触发，青色）
    if (trebleEnergy > 0.03) {
        float2 center = float2(0.5 + sin(time * 0.7) * 0.1, 0.5 - cos(time * 0.6) * 0.06);
        float dist = length(uv - center);
        float wave = sin(dist * 25.0 - time * 5.5) * 0.5 + 0.5;
        float intensity = trebleEnergy * 1.6;
        float falloff = exp(-dist * 1.0) * intensity;
        wave *= falloff;
        // 明亮的青色波纹
        rippleColor += float3(0.2, 1.0, 0.95) * wave * 1.0;
    }
    
    return rippleColor;
}

// 极光主片段着色器 - 性能优化版
fragment float4 auroraRippleFragment(VertexOut in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float time = uniforms.time.x;
    
    // 修正宽高比
    float aspectRatio = uniforms.resolution.z;
    float2 aspectUV = float2((uv.x - 0.5) * aspectRatio + 0.5, uv.y);
    
    // 音频能量计算 - 参照赛博朋克配置
    float bassEnergy = 0.0;
    float midEnergy = 0.0;
    float trebleEnergy = 0.0;
    
    // 低音：0-15（鼓点/贝斯）
    for (int i = 0; i < 15; i++) {
        bassEnergy += uniforms.audioData[i].x;
    }
    bassEnergy = (bassEnergy / 15.0) * 1.8;
    bassEnergy = min(bassEnergy, 1.5);
    
    // 中音：18-53（人声/旋律）
    for (int i = 18; i < 53; i++) {
        midEnergy += uniforms.audioData[i].x;
    }
    midEnergy = (midEnergy / 35.0) * 1.9;
    midEnergy = min(midEnergy, 1.5);
    
    // 高音：50-75（高频/镲片）
    for (int i = 50; i < 75; i++) {
        trebleEnergy += uniforms.audioData[i].x;
    }
    trebleEnergy = (trebleEnergy / 25.0) * 1.6;
    trebleEnergy = min(trebleEnergy, 1.5);
    
    float totalEnergy = (bassEnergy + midEnergy + trebleEnergy) * 0.33;
    
    // 简化的渐变背景
    float3 bgColor1 = float3(0.02, 0.03, 0.08);
    float3 bgColor2 = float3(0.05, 0.02, 0.1);
    float bgGradient = uv.y * 0.8;
    float3 background = mix(bgColor1, bgColor2, bgGradient);
    
    // 简化的星空
    background += starFieldFast(uv, time);
    
    // 极光光带 - 仅2层（原来4层）
    float3 aurora = float3(0.0);
    
    // 第一层极光 - 青绿色（低频驱动）
    float3 color1a = float3(0.2, 1.0, 0.6);
    float3 color1b = float3(0.3, 0.9, 1.0);
    aurora += auroraBeamFast(uv, time, 0.65 + bassEnergy * 0.08, 0.12, 
                              color1a, color1b, 3.0, bassEnergy, 0.0) * 0.8;
    
    // 第二层极光 - 紫粉色（中频驱动）
    float3 color2a = float3(0.7, 0.3, 1.0);
    float3 color2b = float3(1.0, 0.4, 0.8);
    aurora += auroraBeamFast(uv, time * 0.8, 0.5 + midEnergy * 0.06, 0.1, 
                              color2a, color2b, 4.0, midEnergy, 2.0) * 0.6;
    
    // 增强的波纹效果
    float3 ripples = audioRipplesFast(aspectUV, time, bassEnergy, midEnergy, trebleEnergy);
    
    // 组合最终颜色
    float3 finalColor = background + aurora + ripples;
    
    // 简化的呼吸效果
    float breathe = sin(time * 0.5) * 0.08 + 0.92;
    finalColor *= breathe + totalEnergy * 0.15;
    
    // 简化的晕影效果
    float2 vignetteUV = uv * 2.0 - 1.0;
    float vignette = 1.0 - dot(vignetteUV * 0.4, vignetteUV * 0.4);
    finalColor *= vignette * 0.25 + 0.75;
    
    // 简化的色调映射
    finalColor = finalColor / (finalColor + 0.8);
    
    return float4(finalColor, 1.0);
}
