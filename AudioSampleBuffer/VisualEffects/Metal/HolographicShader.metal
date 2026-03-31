//
//  HolographicShader.metal
//  AudioSampleBuffer
//
//  梦幻全息效果着色器 - 柔和、立体、科技感
//  特点：冷色系、Fresnel发光、色差、体积雾、能量流动
//

#include "ShaderCommon.metal"

#pragma mark - 辅助函数

// Fresnel 边缘发光效果
float fresnel(float2 uv, float2 center, float power) {
    float2 diff = uv - center;
    float dist = length(diff);
    float fresnel = pow(1.0 - dist * 2.0, power);
    return saturate(fresnel);
}

// 柔和噪声函数
float softNoise(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

// 2D旋转
float2 rotate2D(float2 p, float angle) {
    float s = sin(angle);
    float c = cos(angle);
    return float2(
        p.x * c - p.y * s,
        p.x * s + p.y * c
    );
}

// 柔和步进函数
float softStep(float edge0, float edge1, float x) {
    float t = saturate((x - edge0) / (edge1 - edge0));
    return t * t * (3.0 - 2.0 * t);
}

// 能量脉冲函数
float energyPulse(float time, float frequency, float offset) {
    return sin(time * frequency + offset) * 0.5 + 0.5;
}

#pragma mark - 全息梦幻效果

fragment float4 holographic_fragment(RasterizerData in [[stage_in]],
                                     constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 originalUV = in.texCoord;
    float time = uniforms.time.x;
    
    float2 center = float2(0.5, 0.5);
    float2 diff = uv - center;
    float radius = length(diff);
    float angle = atan2(diff.y, diff.x);
    
    // ===== 音频数据处理 =====
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x;
    
    // 频段分析
    float bassEnergy = 0.0;
    float midEnergy = 0.0;
    float trebleEnergy = 0.0;
    
    for (int i = 0; i < 10; i++) {
        bassEnergy += uniforms.audioData[i].x;
    }
    for (int i = 10; i < 40; i++) {
        midEnergy += uniforms.audioData[i].x;
    }
    for (int i = 40; i < 79; i++) {
        trebleEnergy += uniforms.audioData[i].x;
    }
    
    bassEnergy /= 10.0;
    midEnergy /= 30.0;
    trebleEnergy /= 39.0;
    
    float totalEnergy = (bassEnergy + midEnergy + trebleEnergy) / 3.0;
    
    // ===== 🔥 高潮检测系统（多维度音乐响应）=====
    // 1. 综合能量响应
    float totalEnergyResponse = totalEnergy * 2.0;
    
    // 2. 低音响应（降低阈值，提高响应系数）
    float bassResponse = smoothstep(0.08, 0.35, bassEnergy) * 1.5;
    
    // 3. 中音响应
    float midResponse = smoothstep(0.08, 0.35, midEnergy) * 1.4;
    
    // 4. 高音响应
    float trebleResponse = smoothstep(0.08, 0.35, trebleEnergy) * 1.5;
    
    // 5. 峰值响应
    float peakValue = max(max(bassEnergy, midEnergy), trebleEnergy);
    float peakResponse = smoothstep(0.12, 0.4, peakValue) * 1.6;
    
    // 6. 综合响应强度
    float responseA = totalEnergyResponse;
    float responseB = max(max(bassResponse, midResponse), trebleResponse) * 1.3;
    float responseC = (bassResponse + midResponse + trebleResponse) / 2.8;
    float responseD = peakResponse * 1.2;
    
    // 最终高潮强度（音乐波动强度）
    float musicIntensity = max(max(responseA, responseB), max(responseC, responseD));
    
    // 轻微提升低值
    if (musicIntensity < 0.3) {
        musicIntensity = musicIntensity * 0.6;
    }
    
    // 非线性压缩高值
    if (musicIntensity > 1.0) {
        float excess = musicIntensity - 1.0;
        musicIntensity = 1.0 + sqrt(excess) * 0.5;
    }
    
    // 最终限制
    musicIntensity = clamp(musicIntensity, 0.0, 1.6);
    
    // ===== 🌀 音乐驱动的转动和扩散 =====
    // 整体旋转角度（平滑累积，避免抖动）
    float rotationAccel = musicIntensity * 1.5 + bassEnergy * 1.0;
    
    // 脉冲旋转 - 只在有音乐时才转
    float rotationPulse = smoothstep(0.08, 0.3, totalEnergy); // 降低阈值，更容易触发
    
    // 平滑旋转（只用时间累积，避免抖动）
    float globalRotation = time * rotationAccel * rotationPulse * 0.4;
    
    // 扩散/收缩效果（大幅增强低音响应）
    float expansion = 1.0 + bassEnergy * 0.35 + musicIntensity * 0.2; // 提升基础扩散
    
    // 低音冲击扩散（增强到明显可见）
    float bassImpact = bassResponse * 0.25; // 从 0.08 提升到 0.25
    expansion += bassImpact;
    
    // 脉冲式扩散（高潮时刻）
    float pulseExpansion = sin(musicIntensity * 10.0 + time * 3.0) * musicIntensity * 0.15;
    expansion += pulseExpansion;
    
    // 应用旋转到 UV 坐标
    float2 rotatedDiff = rotate2D(diff, globalRotation);
    float2 rotatedUV = center + rotatedDiff * expansion;
    
    // 重新计算旋转后的极坐标
    float rotatedRadius = length(rotatedDiff) * expansion;
    float rotatedAngle = atan2(rotatedDiff.y, rotatedDiff.x);
    
    // 更新音频数据索引（基于旋转后的角度）
    float rotatedNormalizedAngle = (rotatedAngle + M_PI_F) / (2.0 * M_PI_F);
    int rotatedSpectrumIndex = int(rotatedNormalizedAngle * 79.0);
    float rotatedAudioValue = uniforms.audioData[rotatedSpectrumIndex].x;
    
    // ===== 背景层：全屏空间雾层（深色渐变 + 体积雾 + 漂浮粒子）=====
    // 全屏深色渐变（从中心向边缘）- 使用旋转扩散后的半径
    float bgGradient = 1.0 - smoothstep(0.0, 1.0, rotatedRadius);
    bgGradient = pow(bgGradient, 0.8);
    
    // 多层体积雾（全屏覆盖，缓慢漂浮）
    float2 fogUV1 = uv * 2.5 + float2(time * 0.02, time * 0.015);
    float2 fogUV2 = uv * 4.0 - float2(time * 0.018, time * 0.022);
    float2 fogUV3 = uv * 6.0 + float2(time * 0.012, -time * 0.016);
    
    float fog1 = softNoise(fogUV1);
    float fog2 = softNoise(fogUV2);
    float fog3 = softNoise(fogUV3);
    
    // 混合多层雾，创造深度
    float volumeFog = (fog1 * 0.5 + fog2 * 0.3 + fog3 * 0.2);
    volumeFog = smoothstep(0.25, 0.75, volumeFog);
    
    // 全屏雾层（带微弱的径向衰减）
    float fogIntensity = volumeFog * (0.25 + bgGradient * 0.15);
    
    // 音频驱动的雾层脉动
    float fogPulse = energyPulse(time, 0.8, totalEnergy * 2.0) * 0.1 + 0.9;
    fogIntensity *= fogPulse;
    
    // 全屏漂浮粒子系统（多尺度，圆形粒子）- 中音主导，低音辅助
    float bgParticles = 0.0;
    
    // 粒子尺寸控制：中音时减小衰减系数，让粒子变大（主要效果）
    float particleSizeBoost = 1.0 - midResponse * 0.6; // 中音响应时衰减降低60%（主要）
    particleSizeBoost *= 1.0 - bassResponse * 0.3; // 低音响应时额外降低30%（辅助）
    
    // 粒子密度控制：中音时降低阈值，让更多粒子出现
    float densityBoost = midResponse * 0.06 + bassResponse * 0.03; // 中音6%，低音3%
    
    // 大粒子（明亮圆形）- 低音时变得更大更多
    float2 particleUV1 = uv * 6.0 + float2(time * 0.03, time * 0.02);
    float2 particleCell1 = floor(particleUV1);
    float2 particleFract1 = fract(particleUV1);
    float particleSeed1 = softNoise(particleCell1);
    
    if (particleSeed1 > (0.93 - densityBoost)) { // 低音时更容易出现
        float2 particlePos1 = particleFract1 - 0.5;
        float particleDist1 = length(particlePos1);
        // 低音时粒子变大（衰减系数从 12.0 降到 6.0）
        float decay1 = 12.0 * particleSizeBoost;
        float particles1 = exp(-particleDist1 * decay1);
        particles1 *= (0.4 + totalEnergy * 0.2);
        bgParticles += particles1;
    }
    
    // 中粒子（中等亮度圆形）- 低音时变大变多
    float2 particleUV2 = uv * 10.0 - float2(time * 0.025, time * 0.035);
    float2 particleCell2 = floor(particleUV2);
    float2 particleFract2 = fract(particleUV2);
    float particleSeed2 = softNoise(particleCell2);
    
    if (particleSeed2 > (0.95 - densityBoost)) { // 低音时更容易出现
        float2 particlePos2 = particleFract2 - 0.5;
        float particleDist2 = length(particlePos2);
        // 低音时粒子变大（衰减系数从 15.0 降到 7.5）
        float decay2 = 15.0 * particleSizeBoost;
        float particles2 = exp(-particleDist2 * decay2);
        particles2 *= (0.3 + midEnergy * 0.15);
        bgParticles += particles2;
    }
    
    // 小粒子（细密星尘圆形）- 低音时变大变多
    float2 particleUV3 = uv * 15.0 + float2(time * 0.015, -time * 0.02);
    float2 particleCell3 = floor(particleUV3);
    float2 particleFract3 = fract(particleUV3);
    float particleSeed3 = softNoise(particleCell3);
    
    if (particleSeed3 > (0.96 - densityBoost)) { // 低音时更容易出现
        float2 particlePos3 = particleFract3 - 0.5;
        float particleDist3 = length(particlePos3);
        // 低音时粒子变大（衰减系数从 18.0 降到 9.0）
        float decay3 = 18.0 * particleSizeBoost;
        float particles3 = exp(-particleDist3 * decay3);
        particles3 *= 0.22;
        bgParticles += particles3;
    }
    
    // 超细粒子（闪烁星点圆形）- 低音时变大变多
    float2 particleUV4 = uv * 25.0 + float2(time * 0.01, -time * 0.015);
    float2 particleCell4 = floor(particleUV4);
    float2 particleFract4 = fract(particleUV4);
    float particleSeed4 = softNoise(particleCell4);
    
    if (particleSeed4 > (0.98 - densityBoost)) { // 低音时更容易出现
        float2 particlePos4 = particleFract4 - 0.5;
        float particleDist4 = length(particlePos4);
        // 低音时粒子变大（衰减系数从 20.0 降到 10.0）
        float decay4 = 20.0 * particleSizeBoost;
        float particles4 = exp(-particleDist4 * decay4);
        particles4 *= 0.18;
        bgParticles += particles4;
    }
    
    // 粒子闪烁效果（强化中音响应，让粒子主要表现中音）
    // 中音 = 人声、旋律、和声的主要频段，应该让粒子主要响应这个频段
    
    // 基础亮度（跟随总能量）
    float baseFlicker = 0.85 + totalEnergy * 0.15;
    
    // 🎵 中音闪烁（主要效果 - 大幅增强）
    float midFlicker = 1.0 + midResponse * 1.2; // 中音响应时亮度提升120%（最强）
    float midEnergyFlicker = 1.0 + midEnergy * 1.0; // 中音能量持续影响（强）
    
    // 🥁 低音冲击闪烁（辅助效果 - 降低）
    float bassFlicker = 1.0 + bassResponse * 0.6; // 低音时亮度提升60%（降低）
    float bassEnergyFlicker = 1.0 + bassEnergy * 0.4; // 低音能量辅助影响（降低）
    
    // 🎸 高音响应（轻微辅助）
    float trebleFlicker = 1.0 + trebleResponse * 0.5; // 高音响应提升50%
    float trebleEnergyFlicker = 1.0 + trebleEnergy * 0.3; // 高音能量轻微影响
    
    // 🎶 音乐强度闪烁（整体律动）
    float musicFlicker = 1.0 + musicIntensity * 0.3;
    
    // 组合所有闪烁效果（中音为主）
    float particleFlicker = baseFlicker * 
                           midFlicker * midEnergyFlicker *        // 中音主导
                           bassFlicker * bassEnergyFlicker *      // 低音辅助
                           trebleFlicker * trebleEnergyFlicker *  // 高音辅助
                           musicFlicker;
    
    bgParticles *= particleFlicker;
    
    // 全屏云雾纹理（增强空间感）
    float2 cloudUV = uv * 1.5 + float2(time * 0.008, time * 0.006);
    float cloudPattern = softNoise(cloudUV) * softNoise(cloudUV * 2.3);
    cloudPattern = smoothstep(0.3, 0.8, cloudPattern) * 0.18;
    
    // 组合背景层
    float backgroundLayer = bgGradient * 0.15 + fogIntensity + bgParticles + cloudPattern;
    
    // ===== 中景层：主频谱动画（立体波形 + 能量脉冲）=====
    float spectrumLayer = 0.0;
    
    // 主频谱环（音频响应）- 使用旋转扩散后的坐标，强化低音响应
    float mainRingRadius = 0.25 + bassEnergy * 0.18 + musicIntensity * 0.1; // 提升低音影响
    float mainRingThickness = 0.04 + midEnergy * 0.03;
    float mainRingDist = abs(rotatedRadius - mainRingRadius);
    
    // 柔光主环（增强亮度和低音响应）
    float mainRing = exp(-mainRingDist / mainRingThickness * 8.0);
    mainRing *= (0.7 + rotatedAudioValue * 0.8 + musicIntensity * 0.3);
    
    // 低音冲击增强（让鼓点时明显变亮）
    mainRing *= (1.0 + bassResponse * 0.5); // 低音响应时亮度提升50%
    
    // 能量脉冲（跟随低音能量，不再使用周期性）
    float breathePulse = 0.8 + bassEnergy * 0.4 + bassResponse * 0.3;
    mainRing *= breathePulse;
    
    spectrumLayer += mainRing * 1.3;
    
    // 次级频谱环（立体层次）
    float secondRingRadius = 0.18 + midEnergy * 0.08;
    float secondRingDist = abs(radius - secondRingRadius);
    float secondRing = exp(-secondRingDist * 30.0) * 0.6;
    spectrumLayer += secondRing;
    
    // 音频波纹（从中心扩散）
    float waveSpeed = 3.0 + totalEnergy * 2.0;
    float wave = sin(radius * 30.0 - time * waveSpeed) * 0.5 + 0.5;
    wave = smoothstep(0.4, 0.7, wave);
    wave *= exp(-radius * 2.0) * (0.3 + bassEnergy * 0.4);
    spectrumLayer += wave;
    
    // 径向频谱条（立体波形）- 使用旋转后的角度和半径
    float radialSpectrum = 0.0;
    for (int i = 0; i < 16; i++) {
        float rayAngle = float(i) * 0.39269908; // 22.5度间隔
        float angleDiff = abs(rotatedAngle - rayAngle);
        angleDiff = min(angleDiff, abs(angleDiff - 6.28318));
        
        int dataIndex = i * 5;
        float dataValue = uniforms.audioData[dataIndex].x;
        
        // 能量条长度（音乐强度影响）
        float barLength = 0.15 + dataValue * 0.18 + musicIntensity * 0.05;
        float barWidth = 0.015;
        
        float barShape = exp(-angleDiff / barWidth * 60.0);
        barShape *= smoothstep(barLength + 0.08, barLength - 0.02, rotatedRadius);
        barShape *= (0.5 + dataValue * 0.8 + musicIntensity * 0.15);
        
        // 能量流动（从内向外）- 音乐强度加速流动
        float flowAnim = sin(rotatedRadius * 15.0 - time * (4.0 + musicIntensity * 2.0) + float(i) * 0.5) * 0.3 + 0.7;
        radialSpectrum += barShape * flowAnim;
    }
    
    spectrumLayer += radialSpectrum * (0.9 + musicIntensity * 0.2);
    
    // 核心能量球（强化低频驱动）
    float coreRadius = 0.08 + bassEnergy * 0.08; // 提升低音影响
    float coreDist = radius / coreRadius;
    float coreGlow = exp(-coreDist * coreDist * 3.0);
    coreGlow *= (0.7 + bassEnergy * 0.8); // 提升低音亮度
    
    // 低音冲击增强（让核心鼓点时爆发）
    coreGlow *= (1.0 + bassResponse * 0.6); // 低音响应时亮度提升60%
    
    // 核心脉冲（跟随低音和音乐强度，不再使用周期性）
    float corePulse = 0.8 + bassEnergy * 0.3 + musicIntensity * 0.2;
    coreGlow *= corePulse;
    
    spectrumLayer += coreGlow * 1.2;
    
    // ===== 前景层：粒子扫描线层 =====
    float foregroundLayer = 0.0;
    
    // 漂浮粒子（柔和模糊）- 使用音乐驱动旋转
    float2 particleSpace = uv * 20.0;
    // 使用音乐驱动的旋转，而不是固定速度
    float particleRotation = globalRotation * 0.5; // 与整体旋转同步，但速度减半
    particleSpace = rotate2D(particleSpace, particleRotation);
    
    float2 particleCell = floor(particleSpace);
    float2 particleFract = fract(particleSpace);
    
    // 粒子出现随音乐强度变化
    float particleSeed = softNoise(particleCell + floor(time * 0.5 * (0.5 + totalEnergy)));
    
    // 粒子出现概率
    if (particleSeed > 0.88) {
        float2 particlePos = particleFract - 0.5;
        float particleDist = length(particlePos);
        
        // 粒子形状（模糊圆）
        float particle = exp(-particleDist * 15.0);
        
        // 粒子亮度：主要响应中音，辅助响应低音
        // 基础亮度 + 中音响应（主要）+ 低音响应（辅助）
        float particleBrightness = 0.6 + totalEnergy * 0.2 + midResponse * 0.6 + bassResponse * 0.3;
        particle *= particleBrightness;
        
        // 粒子透明度
        particle *= smoothstep(0.5, 0.2, radius);
        particle *= 0.25;
        
        foregroundLayer += particle;
    }
    
    // 扫描线（柔和穿梭）
    // 水平扫描线（细密）
    float fineScan = sin(originalUV.y * 300.0 + time * 0.8) * 0.5 + 0.5;
    fineScan = smoothstep(0.3, 0.7, fineScan) * 0.08;
    
    // 垂直扫描线（轻微）
    float vertScan = sin(originalUV.x * 150.0 - time * 0.5) * 0.5 + 0.5;
    vertScan = smoothstep(0.4, 0.6, vertScan) * 0.05;
    
    foregroundLayer += (fineScan + vertScan);
    
    // 动态扫描波（能量穿梭）
    float scanWavePos = fract(time * 0.1 + bassEnergy * 0.4);
    float scanWaveDist = abs(originalUV.y - scanWavePos);
    float scanWave = exp(-scanWaveDist * 25.0);
    scanWave *= (0.5 + totalEnergy * 0.7);
    
    // 色差效果（扫描波）
    float scanWaveR = exp(-abs(originalUV.y - scanWavePos - 0.005) * 25.0);
    float scanWaveB = exp(-abs(originalUV.y - scanWavePos + 0.005) * 25.0);
    
    foregroundLayer += scanWave * 0.6;
    
    // 能量流线（螺旋）- 平滑音乐驱动旋转，强化低音响应
    float spiralRotation = globalRotation * 0.8; // 使用音乐驱动的旋转
    float spiralAngle = rotatedAngle + spiralRotation;
    float spiralPattern = sin(spiralAngle * 8.0 + rotatedRadius * 20.0) * 0.5 + 0.5;
    spiralPattern = smoothstep(0.6, 0.65, spiralPattern);
    spiralPattern *= exp(-abs(rotatedRadius - 0.22) * 15.0) * 0.25;
    
    // 螺旋流线随音乐强度显示（强化低音响应）
    spiralPattern *= (0.3 + musicIntensity * 0.5 + bassEnergy * 0.4); // 低音时更明显
    
    // 低音冲击增强（让螺旋在鼓点时闪亮）
    spiralPattern *= (1.0 + bassResponse * 0.6);
    
    foregroundLayer += spiralPattern;
    
    // ===== Fresnel 边缘发光 =====
    float fresnelEffect = fresnel(uv, center, 3.0);
    fresnelEffect = pow(fresnelEffect, 2.0);
    fresnelEffect *= smoothstep(0.25, 0.4, radius);
    fresnelEffect *= (0.6 + trebleEnergy * 0.7);
    
    // ===== 色差（Chromatic Aberration）=====
    // 轻微的RGB偏移（0.5-1.5%）
    float2 caOffset = normalize(diff) * 0.008;
    float chromaR = mainRing;
    float chromaB = exp(-abs(radius - mainRingRadius - 0.01) / mainRingThickness * 8.0) * (0.4 + audioValue * 0.5);
    
    // ===== 干涉图案（全息特征）=====
    float interference = 0.0;
    
    // 同心圆干涉
    float concentricWave = sin(radius * 50.0 - time * 2.5 + totalEnergy * 8.0);
    concentricWave = smoothstep(0.5, 0.8, concentricWave);
    concentricWave *= exp(-radius * 1.2) * 0.2;
    interference += concentricWave;
    
    // 莫尔纹（角度干涉）
    float moirePattern = sin(angle * 16.0 + time) * sin(radius * 40.0);
    moirePattern = smoothstep(0.3, 0.7, moirePattern * 0.5 + 0.5);
    moirePattern *= smoothstep(0.35, 0.2, radius) * 0.15;
    interference += moirePattern;
    
    // ===== 梦幻色彩系统（冷色系：青蓝紫粉）=====
    // 主色：柔和青蓝色
    float3 primaryColor = float3(0.35, 0.75, 0.95);
    
    // 次色：淡紫色
    float3 secondaryColor = float3(0.65, 0.55, 0.95);
    
    // 强调色：粉色
    float3 accentColor = float3(0.85, 0.55, 0.85);
    
    // 能量色：微弱橙粉（点缀）
    float3 energyColor = float3(0.95, 0.65, 0.75);
    
    // 核心色：温柔的白蓝
    float3 coreColor = float3(0.85, 0.90, 1.0);
    
    // 雾色：深蓝紫
    float3 fogColor = float3(0.15, 0.20, 0.35);
    
    // 颜色混合（基于半径和音频）
    float colorMix1 = energyPulse(time, 0.6, radius * 3.0);
    float colorMix2 = energyPulse(time, 0.8, angle * 2.0);
    
    float3 baseColor = mix(primaryColor, secondaryColor, colorMix1);
    baseColor = mix(baseColor, accentColor, audioValue * 0.3);
    
    // 核心区域使用核心色
    float coreBlend = exp(-radius * 10.0);
    baseColor = mix(baseColor, coreColor, coreBlend * 0.7);
    
    // 外围Fresnel使用紫色
    float3 fresnelColor = mix(secondaryColor, accentColor, 0.6);
    
    // 能量脉冲使用橙粉色
    float3 pulseColor = energyColor;
    
    // ===== 组合所有层 =====
    // 背景层（全屏深色雾）- 增强可见度
    float3 finalColor = fogColor * backgroundLayer * 1.5;
    
    // 背景粒子专用高亮（让粒子更明显）- 大幅增强
    // 使用明亮的青蓝白色系
    float3 bgParticleColor = mix(float3(0.7, 0.9, 1.0), float3(0.9, 0.95, 1.0), 0.5);
    
    // 增加粒子对比度和亮度
    float particleBrightness = bgParticles * 2.5;
    
    // 为粒子添加柔和光晕效果（圆形，中音时变大）
    float glowTotal = 0.0;
    
    // 光晕尺寸控制：中音时光晕变大（主要），低音辅助
    float glowSizeBoost = 1.0 - midResponse * 0.7; // 中音响应时光晕衰减降低70%（主要）
    glowSizeBoost *= 1.0 - bassResponse * 0.4; // 低音响应时额外降低40%（辅助）
    
    // 大粒子光晕（柔和扩散）- 低音时范围扩大
    float2 particleGlow1UV = uv * 6.0 + float2(time * 0.03, time * 0.02);
    float2 particleGlow1Cell = floor(particleGlow1UV);
    float2 particleGlow1Fract = fract(particleGlow1UV);
    float particleGlow1Seed = softNoise(particleGlow1Cell);
    
    if (particleGlow1Seed > 0.93) {
        float2 glowPos1 = particleGlow1Fract - 0.5;
        float glowDist1 = length(glowPos1);
        // 低音时光晕变大（衰减从 6.0 降到 2.4）
        float glowDecay1 = 6.0 * glowSizeBoost;
        float glow1 = exp(-glowDist1 * glowDecay1) * 0.5;
        glowTotal += glow1;
    }
    
    // 中粒子光晕（中等扩散）- 低音时范围扩大
    float2 particleGlow2UV = uv * 10.0 - float2(time * 0.025, time * 0.035);
    float2 particleGlow2Cell = floor(particleGlow2UV);
    float2 particleGlow2Fract = fract(particleGlow2UV);
    float particleGlow2Seed = softNoise(particleGlow2Cell);
    
    if (particleGlow2Seed > 0.95) {
        float2 glowPos2 = particleGlow2Fract - 0.5;
        float glowDist2 = length(glowPos2);
        // 低音时光晕变大（衰减从 8.0 降到 3.2）
        float glowDecay2 = 8.0 * glowSizeBoost;
        float glow2 = exp(-glowDist2 * glowDecay2) * 0.4;
        glowTotal += glow2;
    }
    
    // 叠加粒子和光晕（中音时光晕强度增强）
    finalColor += bgParticleColor * particleBrightness;
    finalColor += bgParticleColor * glowTotal * (2.0 + midResponse * 2.0 + bassResponse * 0.8); // 中音时光晕更亮（主要）
    
    // 中景层（主频谱）
    float3 midColor = baseColor * spectrumLayer;
    
    // 色差效果（应用于主频谱环）
    midColor.r += chromaR * primaryColor.r * 0.2;
    midColor.b += chromaB * accentColor.b * 0.2;
    
    // 前景层（粒子扫描线）
    float3 foreColor = mix(baseColor, coreColor, 0.4) * foregroundLayer;
    
    // 扫描波色差（RGB分离）
    foreColor.r += scanWaveR * energyColor.r * totalEnergy * 0.5;
    foreColor.b += scanWaveB * primaryColor.b * totalEnergy * 0.5;
    
    // Fresnel边缘光
    float3 fresnelGlow = fresnelColor * fresnelEffect;
    
    // 能量脉冲（低频驱动）
    float3 pulseGlow = pulseColor * coreGlow * bassEnergy * 0.5;
    
    // 干涉图案
    float3 interferenceColor = baseColor * interference;
    
    // 柔光叠加（Soft Light）
    finalColor += midColor * 1.2;
    finalColor += foreColor * 1.3;
    finalColor += fresnelGlow * 1.5;
    finalColor += pulseGlow;
    finalColor += interferenceColor;
    
    // ===== 柔和处理 =====
    // 保存粒子贡献（不应被过度柔化）
    float3 particleContribution = bgParticleColor * particleBrightness + bgParticleColor * glowTotal * (2.0 + midResponse * 2.0 + bassResponse * 0.8);
    
    // 对其他层应用柔和处理
    float3 nonParticleColor = finalColor - particleContribution;
    
    // 整体呼吸律动（跟随音乐强度，不再使用周期性）
    float breathe = 0.85 + totalEnergy * 0.12 + musicIntensity * 0.08;
    nonParticleColor *= breathe;
    
    // 轻微闪烁（全息不稳定感）
    float shimmer = sin(time * 6.0 + originalUV.y * 15.0) * 0.05 + 0.95;
    nonParticleColor *= shimmer;
    
    // 降低饱和度（柔和处理）- 减少降饱和度
    float luminance = dot(nonParticleColor, float3(0.299, 0.587, 0.114));
    nonParticleColor = mix(float3(luminance), nonParticleColor, 0.92);
    
    // 重新组合，粒子保持明亮
    finalColor = nonParticleColor + particleContribution * 0.95;
    
    // 亮度控制（提高上限，但不影响粒子）
    float totalIntensity = length(finalColor);
    if (totalIntensity > 1.5) {
        finalColor *= 1.5 / totalIntensity;
    }
    
    // Gamma校正（减少柔化）
    finalColor = pow(finalColor, float3(1.02));
    
    // ===== 边缘柔化和景深 =====
    // 前景和中景的边缘淡化
    float edgeFade = smoothstep(0.55, 0.25, radius);
    
    // 背景层全屏保留（不受边缘淡化影响）
    float bgEdgeFade = smoothstep(0.7, 0.5, radius);
    bgEdgeFade = max(bgEdgeFade, 0.6); // 确保背景层在边缘也可见
    
    // 景深模糊（外围虚化）- 进一步减少，保持背景清晰
    float depthBlur = smoothstep(0.5, 0.6, radius);
    finalColor = mix(finalColor, fogColor * 1.0, depthBlur * 0.15);
    
    // ===== 透明度 =====
    // 前景和中景使用局部淡化
    float alpha = (spectrumLayer + foregroundLayer + fresnelEffect) * edgeFade;
    
    // 背景层使用全屏淡化（覆盖整个屏幕）
    alpha += backgroundLayer * bgEdgeFade * 0.8;
    
    // 粒子额外透明度贡献（让粒子更可见）
    alpha += bgParticles * 0.6;
    alpha += glowTotal * 0.5;
    
    // 干涉图案
    alpha += interference * 0.3;
    
    // 限制透明度范围（提高上限）
    alpha = clamp(alpha * 1.0, 0.0, 0.98);
    
    // 最终颜色限制
    finalColor = clamp(finalColor, 0.0, 1.0);
    
    return float4(finalColor, alpha);
}
