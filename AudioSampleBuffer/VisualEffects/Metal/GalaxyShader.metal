//
//  GalaxyShader.metal
//  AudioSampleBuffer
//
//  星系效果着色器
//

#include "ShaderCommon.metal"

#pragma mark - 星系效果

fragment float4 galaxy_fragment(RasterizerData in [[stage_in]],
                                constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证星系是圆形不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 从控制面板获取参数
    float coreIntensity = uniforms.galaxyParams1.x;
    float edgeIntensity = uniforms.galaxyParams1.y;
    float rotationSpeedParam = uniforms.galaxyParams1.z;
    float glowRadius = uniforms.galaxyParams1.w;
    
    float colorShiftSpeed = uniforms.galaxyParams2.x;
    float nebulaIntensity = uniforms.galaxyParams2.y;
    float pulseStrength = uniforms.galaxyParams2.z;
    float audioSensitivity = uniforms.galaxyParams2.w;
    
    float starDensity = uniforms.galaxyParams3.x;
    float spiralArms = uniforms.galaxyParams3.y;
    int colorTheme = int(uniforms.galaxyParams3.z);
    
    // 星系中心
    float2 center = float2(0.5, 0.5);
    float2 diff = uv - center;
    float radius = length(diff);
    float angle = atan2(diff.y, diff.x);
    
    // 基于音频和控制面板的星系旋转速度
    float averageAudio = 0.0;
    for (int i = 0; i < 20; i++) {
        averageAudio += uniforms.audioData[i].x;
    }
    averageAudio /= 20.0;
    float rotationSpeed = rotationSpeedParam + averageAudio * audioSensitivity;
    
    // 多层螺旋臂结构（使用控制面板的螺旋臂数量）
    float spiralArm1 = sin(angle * spiralArms - radius * 8.0 + time * rotationSpeed) * 0.5 + 0.5;
    float spiralArm2 = sin(angle * spiralArms - radius * 8.0 + time * rotationSpeed + 3.14159) * 0.5 + 0.5;
    float spiralArm3 = sin(angle * (spiralArms * 2.0) - radius * 12.0 + time * rotationSpeed * 0.7) * 0.3 + 0.3;
    
    // 音频驱动的螺旋臂亮度
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x * audioSensitivity;
    
    // 径向频谱分析
    int radiusIndex = int(clamp(radius * 79.0, 0.0, 79.0));
    float radiusAudio = uniforms.audioData[radiusIndex].x * audioSensitivity;
    
    // 星系核心亮度（基于低频和控制面板参数）
    float coreIntensityAudio = 0.0;
    for (int i = 0; i < 10; i++) {
        coreIntensityAudio += uniforms.audioData[i].x;
    }
    coreIntensityAudio /= 10.0;
    
    // 星系外围亮度（基于高频和控制面板参数）
    float edgeIntensityAudio = 0.0;
    for (int i = 60; i < 80; i++) {
        edgeIntensityAudio += uniforms.audioData[i].x;
    }
    edgeIntensityAudio /= 20.0;
    
    // 星系密度分布函数（使用控制面板参数）
    float coreDensity = exp(-radius * 15.0) * (coreIntensity + coreIntensityAudio * audioSensitivity);
    float diskDensity = exp(-radius * 2.5) * (1.0 - exp(-radius * 8.0));
    float haloDensity = exp(-radius * 0.8) * 0.3;
    
    // 螺旋臂组合
    float spiralPattern = (spiralArm1 + spiralArm2) * 0.5 + spiralArm3 * 0.3;
    spiralPattern *= (1.0 + audioValue * 1.5);
    
    // 星系结构亮度（使用控制面板参数）
    float galaxyBrightness = coreDensity + diskDensity * spiralPattern + haloDensity;
    galaxyBrightness *= (0.8 + radiusAudio * 0.4);
    
    // 动态颜色系统（使用控制面板的颜色变化速度）
    float3 coreColor = float3(1.0, 0.9, 0.7); // 温暖的核心颜色
    float3 diskColor = float3(0.8, 0.9, 1.0); // 冷色调的盘面
    float3 armColor = float3(0.9, 0.7, 1.0);  // 螺旋臂的紫色调
    
    // 基于音频频率和控制面板的颜色调制
    float colorShift = sin(time * colorShiftSpeed + averageAudio * 10.0) * 0.3;
    coreColor.r += colorShift;
    diskColor.g += colorShift * 0.5;
    armColor.b += colorShift * 0.7;
    
    // 颜色混合（使用控制面板的边缘亮度参数）
    float3 finalColor = coreColor * coreDensity;
    finalColor += diskColor * diskDensity * (0.7 + edgeIntensityAudio * edgeIntensity * 0.6);
    finalColor += armColor * spiralPattern * diskDensity;
    
    // 星光点缀系统（使用控制面板的星星密度参数）
    float2 starUV1 = uv * (30.0 * starDensity) + time * 0.1;
    float2 starUV2 = uv * (50.0 * starDensity) - time * 0.15;
    float2 starUV3 = uv * (80.0 * starDensity) + time * 0.08;
    
    // 大星星（亮星）
    float star1 = step(0.995, fractalNoise(starUV1, 2));
    float star1Brightness = star1 * (0.8 + audioValue * 0.4);
    
    // 中等星星
    float star2 = step(0.99, fractalNoise(starUV2, 3));
    float star2Brightness = star2 * (0.5 + edgeIntensityAudio * 0.3);
    
    // 小星星（密集）
    float star3 = step(0.985, fractalNoise(starUV3, 4));
    float star3Brightness = star3 * (0.3 + radiusAudio * 0.2);
    
    // 星光颜色（基于位置和音频）
    float3 starColor1 = float3(1.0, 0.95, 0.9) * star1Brightness;
    float3 starColor2 = float3(0.9, 0.95, 1.0) * star2Brightness;
    float3 starColor3 = float3(1.0, 1.0, 0.95) * star3Brightness;
    
    finalColor += starColor1 + starColor2 + starColor3;
    
    // 边缘模糊光源效果（使用控制面板的光晕半径参数）
    float glowIntensity = smoothstep(glowRadius + 0.1, glowRadius - 0.1, radius);
    
    // 多层光晕效果（使用控制面板参数）
    float innerGlow = exp(-radius * 5.0) * (0.5 + coreIntensityAudio * coreIntensity * 0.5);
    float outerGlow = exp(-radius * 1.5) * (0.2 + averageAudio * audioSensitivity * 0.3);
    float atmosphereGlow = exp(-radius * 0.5) * 0.1;
    
    // 光晕颜色
    float3 glowColor = float3(0.7, 0.8, 1.0) * (innerGlow + outerGlow + atmosphereGlow);
    
    // 脉冲效果（基于音频节拍和控制面板的脉冲强度）
    float pulse = sin(time * 3.0 + averageAudio * 20.0) * pulseStrength + (1.0 - pulseStrength);
    finalColor *= pulse;
    
    // 多彩星云效果（使用控制面板的星云强度参数）
    float2 nebulaUV1 = uv * 1.5 + time * 0.03;
    float2 nebulaUV2 = uv * 2.5 + time * 0.07;
    float2 nebulaUV3 = uv * 3.2 - time * 0.05;
    
    // 不同类型的星云（基于控制面板的星云强度）
    float nebula1 = fractalNoise(nebulaUV1, 4) * nebulaIntensity; // 红色星云
    float nebula2 = fractalNoise(nebulaUV2, 3) * nebulaIntensity; // 蓝色星云
    float nebula3 = fractalNoise(nebulaUV3, 5) * nebulaIntensity; // 绿色星云
    
    // 距离衰减
    float nebulaFalloff = exp(-radius * 0.8);
    nebula1 *= nebulaFalloff;
    nebula2 *= nebulaFalloff;
    nebula3 *= nebulaFalloff;
    
    // 音频调制不同颜色的星云
    float lowFreq = (uniforms.audioData[5].x + uniforms.audioData[6].x) * 0.5;
    float midFreq = (uniforms.audioData[25].x + uniforms.audioData[30].x) * 0.5;
    float highFreq = (uniforms.audioData[65].x + uniforms.audioData[70].x) * 0.5;
    
    // 丰富多彩的星云颜色系统
    // 主要星云层 - 基础三原色系
    float3 redNebula = float3(1.0, 0.2, 0.3) * nebula1 * (0.7 + lowFreq * 0.9);        // 深红发射星云
    float3 blueNebula = float3(0.1, 0.4, 1.0) * nebula2 * (0.6 + midFreq * 0.8);       // 深蓝反射星云
    float3 greenNebula = float3(0.2, 0.9, 0.4) * nebula3 * (0.5 + highFreq * 0.7);     // 翠绿行星状星云
    
    // 扩展彩色星云层
    float2 nebulaUV4 = uv * 1.8 + time * 0.02;
    float nebula4 = fractalNoise(nebulaUV4, 3) * 0.3 * nebulaFalloff;
    float3 purpleNebula = float3(0.8, 0.2, 1.0) * nebula4 * (0.6 + averageAudio * 0.7); // 深紫色星云
    
    float2 nebulaUV5 = uv * 2.8 - time * 0.04;
    float nebula5 = fractalNoise(nebulaUV5, 4) * 0.25 * nebulaFalloff;
    float3 orangeNebula = float3(1.0, 0.6, 0.1) * nebula5 * (0.5 + coreIntensity * 0.6); // 橙色星云
    
    // 新增多彩星云层
    float2 nebulaUV6 = uv * 2.2 + time * 0.06;
    float nebula6 = fractalNoise(nebulaUV6, 5) * 0.28 * nebulaFalloff;
    float3 yellowNebula = float3(1.0, 0.9, 0.2) * nebula6 * (0.4 + (lowFreq + midFreq) * 0.4); // 金黄色星云
    
    float2 nebulaUV7 = uv * 3.5 - time * 0.03;
    float nebula7 = fractalNoise(nebulaUV7, 3) * 0.22 * nebulaFalloff;
    float3 cyanNebula = float3(0.2, 0.8, 0.9) * nebula7 * (0.5 + highFreq * 0.5); // 青色星云
    
    float2 nebulaUV8 = uv * 1.6 + time * 0.08;
    float nebula8 = fractalNoise(nebulaUV8, 4) * 0.2 * nebulaFalloff;
    float3 magentaNebula = float3(1.0, 0.3, 0.8) * nebula8 * (0.3 + (midFreq + highFreq) * 0.4); // 洋红星云
    
    float2 nebulaUV9 = uv * 2.6 - time * 0.05;
    float nebula9 = fractalNoise(nebulaUV9, 6) * 0.18 * nebulaFalloff;
    float3 indigoNebula = float3(0.3, 0.1, 0.9) * nebula9 * (0.4 + lowFreq * 0.6); // 靛蓝星云
    
    // 主题驱动的颜色系统（使用控制面板的颜色主题参数）
    float timePhase = time * 0.2;
    float audioPhase = averageAudio * 5.0;
    
    // 定义8种不同的颜色主题（使用控制面板传递的主题ID）
    float3 nebulaColor = float3(0.0);
    
    if (colorTheme == 0) {
        // 🌈 彩虹主题 - 全光谱循环
        float3 rainbow1 = redNebula + orangeNebula + yellowNebula;
        float3 rainbow2 = greenNebula + cyanNebula + blueNebula;
        float3 rainbow3 = indigoNebula + purpleNebula + magentaNebula;
        float rainbowCycle = sin(timePhase * 2.0) * 0.5 + 0.5;
        nebulaColor = mix(mix(rainbow1, rainbow2, rainbowCycle), rainbow3, cos(timePhase) * 0.5 + 0.5);
        
    } else if (colorTheme == 1) {
        // 🔥 火焰主题 - 红橙黄为主
        nebulaColor = redNebula * 1.5 + orangeNebula * 1.3 + yellowNebula * 1.1;
        nebulaColor += purpleNebula * 0.3; // 少量紫色增加深度
        
    } else if (colorTheme == 2) {
        // ❄️ 冰霜主题 - 蓝青白为主
        nebulaColor = blueNebula * 1.4 + cyanNebula * 1.2 + indigoNebula * 0.8;
        nebulaColor = mix(nebulaColor, float3(0.9, 0.95, 1.0), 0.3); // 增加冰蓝色调
        
    } else if (colorTheme == 3) {
        // 🌸 樱花主题 - 粉色为主
        float3 pinkNebula = mix(redNebula, magentaNebula, 0.7);
        nebulaColor = pinkNebula * 1.3 + purpleNebula * 0.8 + float3(1.0, 0.8, 0.9) * 0.4;
        
    } else if (colorTheme == 4) {
        // 🌿 翠绿主题 - 绿色生机
        nebulaColor = greenNebula * 1.5 + cyanNebula * 0.7 + yellowNebula * 0.5;
        nebulaColor += float3(0.3, 0.8, 0.4) * 0.6; // 自然绿色
        
    } else if (colorTheme == 5) {
        // 🌅 日落主题 - 暖色渐变
        nebulaColor = orangeNebula * 1.4 + redNebula * 1.1 + yellowNebula * 0.9;
        nebulaColor += purpleNebula * 0.4; // 日落紫色
        
    } else if (colorTheme == 6) {
        // 🌌 深空主题 - 深蓝紫色
        nebulaColor = indigoNebula * 1.3 + purpleNebula * 1.1 + blueNebula * 0.8;
        nebulaColor += float3(0.2, 0.1, 0.4) * 0.5; // 深空色调
        
    } else {
        // ✨ 梦幻主题 - 多彩混合
        float dreamCycle = sin(timePhase * 3.0 + audioPhase) * 0.5 + 0.5;
        nebulaColor = mix(purpleNebula + magentaNebula, cyanNebula + greenNebula, dreamCycle);
        nebulaColor += (redNebula + yellowNebula) * 0.3;
    }
    
    // 通用颜色增强
    float intensityBoost = 1.2 + averageAudio * 1.8;
    float radialShift = sin(radius * 8.0 + time * 0.5) * 0.4 + 0.8;
    float angleShift = cos(angle * 3.0 + time * 0.3) * 0.3 + 0.9;
    
    nebulaColor *= intensityBoost * radialShift * angleShift;
    
    // 颜色闪烁效果
    float colorSparkle = sin(time * 2.5 + radius * 15.0) * 0.15 + 0.9;
    nebulaColor *= colorSparkle;
    
    finalColor += nebulaColor + glowColor;
    
    // 最终亮度和透明度
    float finalAlpha = clamp(galaxyBrightness + glowIntensity * 0.5, 0.0, 1.0);
    
    // 边缘软化
    float edgeSoftness = smoothstep(0.8, 0.6, radius);
    finalAlpha *= edgeSoftness;
    
    return float4(finalColor, finalAlpha);
}

