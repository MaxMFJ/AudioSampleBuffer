//
//  StarVortexShader.metal
//  AudioSampleBuffer
//
//  恒星涡旋视觉效果 - 实验性高性能版
//  特色: 中心恒星日冕爆发 + 旋转等离子云气
//

#include <metal_stdlib>
#include "ShaderCommon.metal"

using namespace metal;

// ============================================================================
// 恒星涡旋着色器 - Star Vortex
// ============================================================================

// 快速旋转函数
float2 rotate(float2 p, float a) {
    float s = sin(a);
    float c = cos(a);
    return float2(p.x * c - p.y * s, p.x * s + p.y * c);
}

// 快速噪声函数
float starHash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

float starNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = starHash(i);
    float b = starHash(i + float2(1.0, 0.0));
    float c = starHash(i + float2(0.0, 1.0));
    float d = starHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 分形噪声用于等离子效果
float plasmaFbm(float2 p, float time) {
    float v = 0.0;
    v += starNoise(p + time * 0.2) * 0.5;
    v += starNoise(p * 2.1 + time * 0.4) * 0.25;
    v += starNoise(p * 4.2 - time * 0.1) * 0.125;
    return v / 0.875;
}

fragment float4 starVortexFragment(VertexOut in [[stage_in]],
                                   constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float time = uniforms.time.x;
    float aspectRatio = uniforms.resolution.z;
    
    // 居中并校正宽高比
    float2 p = (uv - 0.5);
    p.x *= aspectRatio;
    
    // 音频分析
    float bass = 0.0;
    for(int i=0; i<10; i++) bass += uniforms.audioData[i].x;
    bass = bass / 10.0;
    
    float mid = 0.0;
    for(int i=20; i<50; i++) mid += uniforms.audioData[i].x;
    mid = mid / 30.0;
    
    float high = 0.0;
    for(int i=50; i<80; i++) high += uniforms.audioData[i].x;
    high = high / 30.0;

    // 极坐标转换
    float dist = length(p);
    float angle = atan2(p.y, p.x);
    
    // --- 1. 中心恒星核 (Star Core) ---
    float coreSize = 0.08 + bass * 0.15;
    float coreGlow = exp(-dist * 15.0 / (1.0 + bass)) * 1.5;
    float3 coreColor = float3(1.0, 0.9, 0.6) * coreGlow;
    
    // --- 2. 旋转日冕 (Rotating Corona) ---
    // 基础旋转 + 随距离增加的扭曲
    float swirl = angle + time * 0.5 + dist * 5.0 * (1.0 + mid);
    float2 swirlP = float2(cos(swirl), sin(swirl)) * dist;
    
    float plasma = plasmaFbm(swirlP * 8.0, time);
    float corona = exp(-dist * 4.0) * plasma * (mid * 2.5 + 0.5);
    
    // 颜色渐变: 橙红 -> 紫蓝
    float3 coronaColor1 = float3(1.0, 0.4, 0.1); // 火焰橙
    float3 coronaColor2 = float3(0.5, 0.2, 0.8); // 电子紫
    float3 coronaColor = mix(coronaColor1, coronaColor2, saturate(dist * 1.5 - mid));
    
    // --- 3. 日冕丝 (Flare Filaments) ---
    // 🔥 高潮检测系统（学习自赛博朋克效果）
    // 综合能量检测
    float totalEnergy = (bass + mid + high) / 3.0;
    
    // 各频段响应（使用smoothstep平滑过渡）
    float bassResponse = smoothstep(0.08, 0.35, bass) * 1.5;
    float midResponse = smoothstep(0.08, 0.35, mid) * 1.4;
    float highResponse = smoothstep(0.08, 0.35, high) * 1.5;
    
    // 峰值响应
    float peakValue = max(max(bass, mid), high);
    float peakResponse = smoothstep(0.12, 0.4, peakValue) * 1.6;
    
    // 综合高潮强度（多维度取最大值）
    float climaxA = totalEnergy * 2.0;
    float climaxB = max(max(bassResponse, midResponse), highResponse) * 1.3;
    float climaxC = (bassResponse + midResponse + highResponse) / 2.0;  // 除数降低，增益更高
    float climaxD = peakResponse * 1.5;  // 峰值响应增强
    float isClimax = max(max(climaxA, climaxB), max(climaxC, climaxD));
    
    // 放大增益后再压缩，让高潮更容易触发
    isClimax = isClimax * 1.8;  // 放大1.8倍
    isClimax = pow(saturate(isClimax), 0.5);  // 0.5次幂让响应更敏感
    
    float3 flareColor = float3(0.0);
    
    // ============================================
    // === 基础层：始终显示的简洁日冕丝 (3条) ===
    // ============================================
    float flaresBase = 0.0;
    for(int i=0; i<3; i++) {
        float iFloat = float(i);
        float flareAngle = angle + time * 0.2 + iFloat * 2.094;  // 120度间隔
        float flare = abs(sin(flareAngle * 1.5));
        flare = pow(1.0 - flare, 18.0);
        // 基础长度适中，亮度调暗
        flaresBase += flare * exp(-dist * 2.5) * 0.25;
    }
    flareColor += float3(0.8, 0.6, 0.3) * flaresBase;  // 暗淡金色
    
    // ============================================
    // === 高潮层1：6条主日冕丝（随高潮渐显）===
    // ============================================
    float flares1 = 0.0;
    float climaxFade1 = smoothstep(0.1, 0.3, isClimax);  // 10%开始显示，30%全显
    if (climaxFade1 > 0.01) {
        for(int i=0; i<6; i++) {
            float iFloat = float(i);
            float flareAngle = angle + time * 0.25 + iFloat * 1.047;
            float flare = abs(sin(flareAngle * 3.0));
            flare = pow(1.0 - flare, 25.0);
            float breathe = 1.8 + 0.4 * sin(time * 0.3 + iFloat);
            flares1 += flare * exp(-dist * breathe) * 0.7;
        }
        flareColor += float3(1.0, 0.75, 0.2) * flares1 * climaxFade1;
    }
    
    // ============================================
    // === 高潮层2：12条细短丝（高潮更强时显示）===
    // ============================================
    float flares2 = 0.0;
    float climaxFade2 = smoothstep(0.2, 0.45, isClimax);  // 20%开始，45%全显
    if (climaxFade2 > 0.01) {
        for(int i=0; i<12; i++) {
            float iFloat = float(i);
            float flareAngle = angle - time * 0.4 + iFloat * 0.524;
            float flare = abs(sin(flareAngle * 6.0 + time * 0.5));
            flare = pow(1.0 - flare, 30.0);
            flares2 += flare * exp(-dist * 4.0) * 0.5;
        }
        flareColor += float3(1.0, 0.5, 0.15) * flares2 * climaxFade2;
    }
    
    // ============================================
    // === 高潮层3：外围长丝（高潮峰值时显示）===
    // ============================================
    float flares3 = 0.0;
    float climaxFade3 = smoothstep(0.3, 0.55, isClimax);  // 30%开始，55%全显
    if (climaxFade3 > 0.01) {
        for(int i=0; i<3; i++) {
            float iFloat = float(i);
            float flareAngle = angle - time * 0.15 + iFloat * 2.094;
            float wave = sin(dist * 8.0 - time * 2.0 + iFloat * 2.0) * 0.1;
            float flare = abs(sin(flareAngle * 1.5 + wave));
            flare = pow(1.0 - flare, 15.0);
            float pulse = 1.2 + 0.3 * sin(time * 0.5 + iFloat * 1.5);
            flares3 += flare * exp(-dist * pulse) * 0.6;
        }
        flareColor += float3(0.9, 0.6, 0.8) * flares3 * climaxFade3;
    }
    
    // ============================================
    // === 高潮层4：闪烁火花（最高潮时显示）===
    // ============================================
    float sparks = 0.0;
    float climaxFade4 = smoothstep(0.4, 0.65, isClimax);  // 40%开始，65%全显
    if (climaxFade4 > 0.01) {
        for(int i=0; i<8; i++) {
            float iFloat = float(i);
            float sparkAngle = angle + iFloat * 0.785 + sin(time * 0.8 + iFloat) * 0.3;
            float sparkDist = 0.1 + 0.15 * sin(time * 1.2 + iFloat * 1.7);
            float spark = exp(-abs(dist - sparkDist) * 30.0);
            spark *= pow(abs(sin(sparkAngle * 8.0)), 20.0);
            float twinkle = 0.5 + 0.5 * sin(time * 3.0 + iFloat * 2.5);
            sparks += spark * twinkle * 0.8;
        }
        flareColor += float3(1.0, 0.95, 0.7) * sparks * climaxFade4;
    }

    // --- 4. 星光闪烁 (Twinkling Stars) ---
    // 🌟 低音/鼓点直接驱动闪烁 - 增强版
    float3 starLight = float3(0.0);
    
    // 🥁 大幅放大低音信号，让闪烁更明显
    // bass 通常在 0.0 - 0.3 范围，放大5倍到 0-1.5 范围
    float bassIntensity = bass * 5.0;
    // 使用更陡峭的幂函数，让低音弱时几乎不亮，强时非常亮
    float bassFlash = pow(saturate(bassIntensity), 0.5);  // 0.5次幂让响应更敏感
    
    // 使用未校正宽高比的坐标来生成星星网格（确保网格单元在屏幕上是正方形）
    float2 pScreen = (uv - 0.5);  // 未校正的屏幕坐标
    
    // 创建三层不同尺度的星星
    for(int layer = 0; layer < 3; layer++) {
        float layerScale = 8.0 + float(layer) * 5.0;  // 8, 13, 18
        float layerSpeed = 0.02 + float(layer) * 0.01;
        
        // 🔧 使用屏幕坐标生成网格，确保正方形单元
        float2 starGrid = pScreen * layerScale + time * layerSpeed;
        float2 cellId = floor(starGrid);
        float2 cellPos = fract(starGrid);
        
        // 每个网格单元生成一颗星
        float starSeed = starHash(cellId + float(layer) * 10.0);
        
        // 只保留部分星星（避免过于密集）
        if (starSeed > 0.7) {  // 30% 的单元有星星
            // 星星在单元中的位置（随机偏移）
            float2 starOffset = float2(starHash(cellId * 7.0), starHash(cellId * 11.0));
            float2 starPos = cellPos - starOffset;
            
            // 🔧 修复椭圆问题：网格是正方形的，length直接得到圆形
            float starDist = length(starPos);
            
            // 星星大小（稍微增大）
            float starSize = 0.02 + starHash(cellId * 13.0) * 0.03;
            
            // 星星亮度（核心 + 光晕）- 增强光晕
            float starCore = smoothstep(starSize, starSize * 0.2, starDist);
            float starGlow = exp(-starDist * 40.0) * 0.6;
            float starBrightness = starCore + starGlow;
            
            // 🥁 闪烁效果：完全由低音驱动，大幅增强
            float starResponse = 0.7 + starHash(cellId * 19.0) * 0.3;  // 0.7-1.0 响应系数
            
            // 基础亮度极低，低音强时爆发式提升
            float baseBrightness = 0.05;  // 几乎不可见的基础亮度
            float flashBrightness = bassFlash * starResponse * 2.5;  // 大幅放大闪烁
            
            // 允许超过1.0，让闪烁更耀眼
            float twinkle = baseBrightness + flashBrightness;
            
            // 星星颜色：低音强时偏暖金色，更鲜艳
            float3 starColor = mix(
                float3(0.8, 0.9, 1.0),      // 冷蓝白
                float3(1.0, 0.8, 0.3),      // 明亮金色
                saturate(bassFlash * 0.8)
            );
            
            // 组合：不限制twinkle上限
            starLight += starColor * starBrightness * twinkle;
        }
    }
    
    // 星光随距离自然衰减（减弱衰减让星星更亮）
    float starFalloff = smoothstep(1.0, 0.1, dist);
    starLight *= starFalloff;
    
    // 提高上限，允许更亮
    starLight = min(starLight, float3(3.0));
    
    // --- 组合 ---
    float3 finalColor = coreColor + corona * coronaColor + flareColor + starLight;
    
    // 添加脉冲和呼吸
    finalColor *= (1.0 + bass * 0.3 * sin(time * 5.0));
    
    // 晕影
    float vignette = smoothstep(0.8, 0.2, dist);
    finalColor *= vignette;

    return float4(finalColor, 1.0);
}

