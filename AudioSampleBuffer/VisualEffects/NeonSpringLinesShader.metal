//
//  NeonSpringLinesShader.metal
//  AudioSampleBuffer
//
//  霓虹弹簧竖线效果 - 发光霓虹竖线随音频产生弹簧动画
//  特色: 中间长两边短 + 灵魂出窍残影 + 霓虹发光 + 音频响应
//

#include "ShaderCommon.metal"

// 弹簧动画函数 - 模拟弹簧的阻尼振动
static inline float springAnimation(float amplitude, float time, float frequency, float damping) {
    // 阻尼振动公式: A * e^(-damping*t) * cos(frequency*t)
    float decay = exp(-damping * time);
    float oscillation = cos(frequency * time);
    return amplitude * decay * oscillation;
}

// 计算单根竖线的强度（增强版）
static inline float verticalLine(float2 uv, float xPos, float width, float height, float yOffset) {
    // 计算到竖线中心的水平距离
    float distX = abs(uv.x - xPos);
    
    // 竖线的水平强度（使用平滑过渡）
    float horizontalIntensity = 1.0 - smoothstep(0.0, width, distX);
    
    // 竖线的垂直范围（从底部向上延伸）
    float yStart = 0.5 - height * 0.5 + yOffset;
    float yEnd = 0.5 + height * 0.5 + yOffset;
    float verticalMask = smoothstep(yStart - 0.08, yStart, uv.y) * 
                         (1.0 - smoothstep(yEnd, yEnd + 0.08, uv.y));
    
    return horizontalIntensity * verticalMask;
}

// 平衡的霓虹发光效果（避免过曝）
static inline float3 neonGlow(float intensity, float3 baseColor, float glowStrength) {
    // 核心亮度（适中）
    float3 core = baseColor * intensity * 1.2;
    
    // 外发光（适中范围）
    float glowFactor = pow(intensity, 0.4) * glowStrength;
    float3 glow = baseColor * glowFactor * 0.8;
    
    // 内发光（适中的中心）
    float3 innerGlow = baseColor * pow(intensity, 1.5) * 1.5;
    
    return core + glow + innerGlow;
}

// 竖线跳动触发的波纹扩散（跟随弹簧动画，渐渐消失）
static inline float3 shockwaveRipple(float2 uv, float xPos, float width, float height, 
                                     float yOffset, float3 color, float audioEnergy, 
                                     float springOffset, float time) {
    float3 rippleColor = float3(0.0);
    
    // 波纹触发强度（基于音频能量和弹簧位移）
    float rippleTrigger = audioEnergy * (0.5 + abs(springOffset) * 2.0);
    
    // 如果音频能量太低，不产生波纹
    if (audioEnergy < 0.05) {
        return rippleColor;
    }
    
    // 只产生2圈波纹，短距离扩散
    const int rippleCount = 2;
    
    for (int r = 0; r < rippleCount; r++) {
        float ripplePhase = float(r) / float(rippleCount);
        
        // 波纹扩散距离（扩散12%）
        float rippleTime = time * 4.0 + ripplePhase * 0.8;
        float rippleProgress = fract(rippleTime * 0.5); // 0-1的进度
        float spreadDistance = rippleProgress * 0.12;
        
        // 🌊 优化消失效果：使用更平滑的渐变曲线
        // smoothstep提供更平滑的过渡，避免突然消失
        float fadeOut = 1.0 - smoothstep(0.0, 1.0, rippleProgress);
        // 额外的软化：在末端更加平滑
        fadeOut = fadeOut * fadeOut * (3.0 - 2.0 * fadeOut); // Hermite平滑
        float rippleAlpha = fadeOut * rippleTrigger * 3.0;
        
        // 计算到竖线的水平距离
        float distToLine = abs(uv.x - xPos);
        
        // 波纹宽度（随扩散逐渐变细，更自然的消失）
        float rippleWidth = 0.020 * (1.0 - rippleProgress * 0.5);
        
        // 波纹强度（在特定距离处形成峰值）
        float rippleIntensity = exp(-abs(distToLine - spreadDistance) / rippleWidth);
        
        // 波纹只在竖线的垂直范围内显示（使用更平滑的边缘）
        float yStart = 0.5 - height * 0.5 + yOffset;
        float yEnd = 0.5 + height * 0.5 + yOffset;
        float verticalMask = smoothstep(yStart - 0.15, yStart + 0.05, uv.y) * 
                            (1.0 - smoothstep(yEnd - 0.05, yEnd + 0.15, uv.y));
        
        // 添加波纹颜色（增强可见度）
        rippleColor += color * rippleIntensity * rippleAlpha * verticalMask * 2.5;
        
        // 添加发光效果（也随扩散渐变消失）
        float glowWidth = rippleWidth * 2.0 * (1.0 - rippleProgress * 0.3);
        float glowIntensity = exp(-abs(distToLine - spreadDistance) / glowWidth);
        rippleColor += color * glowIntensity * rippleAlpha * verticalMask * 1.5;
    }
    
    return rippleColor;
}

// 片段着色器 - 霓虹弹簧竖线
fragment float4 neonSpringLinesFragment(RasterizerData in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 🎵 音频频段分析（参考其他效果的配置）
    float bassAudio = 0.0;
    float midAudio = 0.0;
    float trebleAudio = 0.0;
    
    // 🔧 优化CPU：总计60次循环（低音15 + 中音30 + 高音15）
    
    // 低音：0-15（鼓点/贝斯）- 保持15次不变
    for (int i = 0; i < 15; i++) {
        bassAudio += uniforms.audioData[i].x;
    }
    bassAudio = (bassAudio / 15.0) * 2.0;
    bassAudio = min(bassAudio, 1.8);
    
    // 中音：18-48（人声/旋律）- 减少到30次
    for (int i = 18; i < 48; i++) {
        midAudio += uniforms.audioData[i].x;
    }
    midAudio = (midAudio / 30.0) * 1.8;
    midAudio = min(midAudio, 1.5);
    
    // 高音：50-65（高频）- 减少到15次
    for (int i = 50; i < 65; i++) {
        trebleAudio += uniforms.audioData[i].x;
    }
    trebleAudio = (trebleAudio / 15.0) * 1.7;
    trebleAudio = min(trebleAudio, 1.5);
    
    float totalEnergy = (bassAudio + midAudio + trebleAudio) / 3.0;
    
    // 🎨 配置竖线参数 - 中间长两边短（超长竖线版本）
    const int lineCount = 7; // 7根竖线
    float lineSpacing = 0.13; // 竖线间距
    float baseWidth = 0.010; // 基础宽度（稍微加粗）
    float baseHeight = 1.1; // 基础高度（超长！视觉冲击力更强）
    
    // 计算起始位置（居中）
    float startX = 0.5 - (float(lineCount - 1) * lineSpacing * 0.5);
    
    // 累积所有竖线的颜色
    float3 finalColor = float3(0.0);
    
    // 🌈 为每根竖线生成不同的颜色和动画
    for (int i = 0; i < lineCount; i++) {
        float lineIndex = float(i);
        float xPos = startX + lineIndex * lineSpacing;
        
        // 🎵 每根竖线响应不同的音频频段
        float audioResponse = 0.0;
        if (i < 2) {
            // 前2根响应低音
            audioResponse = bassAudio;
        } else if (i < 5) {
            // 中间3根响应中音
            audioResponse = midAudio;
        } else {
            // 后2根响应高音
            audioResponse = trebleAudio;
        }
        
        // 🏔️ 山峰形状：中间高，两边短（驼峰更突出）
        // 使用抛物线函数计算高度系数
        float centerDistance = abs(lineIndex - float(lineCount - 1) * 0.5);
        float heightMultiplier = 1.0 - (centerDistance / (float(lineCount) * 0.5)) * 0.7;
        // 中间的线最高(1.0)，两边的线降低到约0.35（再缩短30%）
        
        // 🔊 弹簧动画参数（由音频驱动）
        float springAmplitude = audioResponse * 0.2; // 振幅（增大）
        float springFrequency = 10.0 + audioResponse * 8.0; // 频率（增大，更快）
        float springDamping = 1.8; // 阻尼系数（降低，振动更持久）
        
        // 计算弹簧偏移（每根竖线有不同的相位）
        float phase = lineIndex * 0.4;
        float springOffset = springAnimation(springAmplitude, 
                                             fmod(time * 2.5 + phase, 3.14159 * 2.0), 
                                             springFrequency, 
                                             springDamping);
        
        // 🎵 音频驱动的高度变化（应用山峰形状）
        float dynamicHeight = baseHeight * heightMultiplier * (0.8 + audioResponse * 0.8);
        
        // 🎵 音频驱动的宽度变化（更强的音频=更粗的线）
        float dynamicWidth = baseWidth * (1.0 + audioResponse * 2.0);
        
        // 计算竖线强度
        float lineIntensity = verticalLine(uv, xPos, dynamicWidth, dynamicHeight, springOffset);
        
        // 🌈 超丰富动态颜色变换
        // 基础色相：每根线有不同起始色，覆盖完整彩虹光谱
        float baseHue = (lineIndex / float(lineCount)) * 1.0;
        
        // 时间驱动的色相旋转（全局缓慢旋转）
        float timeHueShift = time * 0.15;
        
        // 音频驱动的色相跳跃（音频越强，色相变化越剧烈）
        float audioHueShift = audioResponse * 0.3 * sin(time * 3.0 + lineIndex);
        
        // 弹簧跳动时的色相闪烁
        float springHueFlash = abs(springOffset) * 0.2;
        
        // 组合所有色相变化
        float hue = fract(baseHue + timeHueShift + audioHueShift + springHueFlash);
        
        // 饱和度：音频越强越鲜艳，有轻微波动
        float saturation = 0.85 + audioResponse * 0.15 + sin(time * 2.0 + lineIndex * 0.5) * 0.05;
        
        // 亮度：基础高亮度，音频增强，跳动时闪烁
        float brightness = 0.95 + audioResponse * 0.3 + abs(springOffset) * 0.5;
        brightness = min(brightness, 1.5); // 限制最大亮度
        
        float3 lineColor = hsv2rgb(float3(hue, saturation, brightness));
        
        // 🎨 添加额外的颜色层次：渐变叠加
        // 从竖线底部到顶部的颜色渐变
        float verticalPos = (uv.y - (0.5 - baseHeight * 0.5)) / baseHeight;
        verticalPos = clamp(verticalPos, 0.0, 1.0);
        float gradientHue = fract(hue + verticalPos * 0.15); // 顶部和底部颜色稍有不同
        float3 gradientColor = hsv2rgb(float3(gradientHue, saturation, brightness));
        
        // 混合基础颜色和渐变颜色
        lineColor = mix(lineColor, gradientColor, 0.3);
        
        // 🎵 音频驱动的发光强度（增强）
        float glowStrength = 1.5 + audioResponse * 3.0;
        
        // 应用霓虹发光效果
        float3 glowingLine = neonGlow(lineIntensity, lineColor, glowStrength);
        
        // 🌊 添加跳动触发的波纹扩散效果（跟随弹簧动画）
        float3 rippleEffect = shockwaveRipple(uv, xPos, dynamicWidth, dynamicHeight, 
                                              springOffset, lineColor, audioResponse, 
                                              springOffset, time);
        
        // 累加到最终颜色（主线 + 波纹）
        finalColor += glowingLine + rippleEffect;
    }
    
    // 取消波纹效果，保持简洁
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);
    
    // 🎨 深色背景渐变（避免过曝）
    float bgGradient = uv.y * 0.6 + 0.4;
    float3 bgColor1 = float3(0.02, 0.01, 0.06); // 深紫色
    float3 bgColor2 = float3(0.01, 0.02, 0.08); // 深蓝色
    float3 background = mix(bgColor1, bgColor2, bgGradient);
    
    // 音频驱动的背景脉动（适中）
    background *= (0.6 + totalEnergy * 0.4);
    
    // 添加背景
    finalColor += background * 0.3;
    
    // 🌟 适度的暗角效果
    float vignette = 1.0 - smoothstep(0.4, 1.3, dist);
    finalColor *= (vignette * 0.4 + 0.6);
    
    // 🎵 整体亮度随音频脉动（适中，避免过曝）
    finalColor *= (0.85 + totalEnergy * 0.4);
    
    // ✨ 适度的发光提升
    float brightness = dot(finalColor, float3(0.299, 0.587, 0.114));
    finalColor += finalColor * pow(brightness, 1.5) * totalEnergy * 0.2;
    
    // 色调映射（防止过曝）
    finalColor = finalColor / (finalColor + 0.6);
    
    return float4(finalColor, 1.0);
}
