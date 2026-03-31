//
//  LightningShader.metal
//  AudioSampleBuffer
//
//  音频闪电雷暴效果着色器 - 电光闪烁，频率驱动
//  特点：分形闪电、脉冲能量、低频主闪电、高频枝干跳动
//

#include "ShaderCommon.metal"

#pragma mark - 辅助函数

// 闪电分形噪声（增强版）
static inline float lightningNoise(float2 p, float time) {
    float2 i = floor(p);
    float2 f = fract(p);
    
    // 四角随机值
    float a = noise(i);
    float b = noise(i + float2(1.0, 0.0));
    float c = noise(i + float2(0.0, 1.0));
    float d = noise(i + float2(1.0, 1.0));
    
    // 时间扰动
    a += sin(time * 3.0 + a * 6.28) * 0.3;
    b += sin(time * 3.5 + b * 6.28) * 0.3;
    c += sin(time * 4.0 + c * 6.28) * 0.3;
    d += sin(time * 4.5 + d * 6.28) * 0.3;
    
    // 平滑插值
    float2 u = f * f * (3.0 - 2.0 * f);
    
    return mix(mix(a, b, u.x), mix(c, d, u.x), u.y);
}

// 分形布朗运动（增强闪电纹理）
static inline float fbmLightning(float2 p, float time, int octaves) {
    float value = 0.0;
    float amplitude = 0.6;
    float frequency = 1.0;
    
    for (int i = 0; i < octaves; i++) {
        value += lightningNoise(p * frequency + float2(time * 0.5, 0.0), time) * amplitude;
        frequency *= 2.1;
        amplitude *= 0.45;
    }
    
    return value;
}

// 闪电主干生成
static inline float lightningBolt(float2 uv, float2 start, float2 end, float thickness, float time, float audioValue) {
    float2 pa = uv - start;
    float2 ba = end - start;
    float h = clamp(dot(pa, ba) / dot(ba, ba), 0.0, 1.0);
    
    float2 closestPoint = start + ba * h;
    float dist = length(uv - closestPoint);
    
    // 添加扰动
    float perturbation = fbmLightning(closestPoint * 10.0, time * 5.0, 3) * 0.03;
    dist += perturbation * audioValue;
    
    // 主干亮度
    float bolt = exp(-dist / thickness * 30.0);
    
    // 增强音频响应
    bolt *= (1.0 + audioValue * 1.5);
    
    return bolt;
}

// 闪电分支生成
static inline float lightningBranches(float2 uv, float time, float audioValue, float density) {
    float branches = 0.0;
    
    // 多个分支方向
    for (int i = 0; i < 8; i++) {
        float angle = float(i) * 0.785398; // 45度间隔
        float branchPhase = sin(time * 2.0 + float(i)) * 0.5 + 0.5;
        
        if (branchPhase > (1.0 - density)) {
            float2 dir = float2(cos(angle), sin(angle));
            float2 start = float2(0.5, 0.5);
            float2 end = start + dir * (0.2 + audioValue * 0.15);
            
            branches += lightningBolt(uv, start, end, 0.008, time + float(i), audioValue) * 0.6;
        }
    }
    
    return branches;
}

// 电弧效果
static inline float electricArc(float2 uv, float time, float audioValue) {
    float2 center = float2(0.5, 0.5);
    float dist = length(uv - center);
    float angle = atan2(uv.y - center.y, uv.x - center.x);
    
    // 圆形电弧
    float arcRadius = 0.25 + audioValue * 0.1;
    float arcDist = abs(dist - arcRadius);
    
    // 电弧闪烁
    float arcPattern = sin(angle * 12.0 - time * 8.0) * 0.5 + 0.5;
    arcPattern = smoothstep(0.6, 0.8, arcPattern);
    
    float arc = exp(-arcDist * 60.0) * arcPattern;
    arc *= (0.5 + audioValue * 0.8);
    
    return arc;
}

// 辉光效果
static inline float glow(float intensity, float radius) {
    return intensity * (1.0 + radius * 2.0);
}

#pragma mark - 主片段着色器

fragment float4 lightning_fragment(RasterizerData in [[stage_in]],
                                   constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    float2 center = float2(0.5, 0.5);
    float2 diff = uv - center;
    float radius = length(diff);
    float angle = atan2(diff.y, diff.x);
    
    // ===== 音频数据处理（参考赛博朋克shader）=====
    // 1️⃣ 直接从音频数据获取频段能量（赛博朋克方式）
    float bassAudio = 0.0;
    float midAudio = 0.0;
    float trebleAudio = 0.0;
    
    // 低频 (0-9): 贝斯、底鼓
    for (int i = 0; i < 10; i++) {
        bassAudio += uniforms.audioData[i].x;
    }
    bassAudio = bassAudio / 10.0;
    
    // 中频 (10-39): 人声、吉他、键盘
    for (int i = 10; i < 40; i++) {
        midAudio += uniforms.audioData[i].x;
    }
    midAudio = midAudio / 30.0;
    
    // 高频 (40-79): 镲片、高音合成器
    for (int i = 40; i < 80; i++) {
        trebleAudio += uniforms.audioData[i].x;
    }
    trebleAudio = trebleAudio / 40.0;
    
    // 平均音频强度
    float averageAudio = (bassAudio + midAudio + trebleAudio) / 3.0;
    
    // 💡 关键：保存原始音频数据用于高潮检测（不被后续处理削弱）
    float bassAudioOriginal = bassAudio;
    float midAudioOriginal = midAudio;
    float trebleAudioOriginal = trebleAudio;
    
    // 2️⃣ 获取局部音频值（用于细节）
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x;
    
    // 重命名为更清晰的变量名
    float bassEnergy = bassAudio;
    float midEnergy = midAudio;
    float trebleEnergy = trebleAudio;
    float totalEnergy = averageAudio;
    
    // ===== 🔥 高潮检测系统（完全参考赛博朋克 - 使用原始音频数据）=====
    // 多维度检测音乐高能时刻 - 大幅降低阈值，确保能触发
    
    // 1. 综合能量（使用原始数据）
    float totalEnergyResponse = (bassAudioOriginal + midAudioOriginal + trebleAudioOriginal) / 3.0 * 2.5; // 提升2.5倍
    
    // 2. 低音响应（使用原始数据，降低阈值，提高响应系数）
    float bassResponse = smoothstep(0.08, 0.35, bassAudioOriginal) * 1.8; // 8%开始，35%满
    
    // 3. 中音响应（使用原始数据，降低阈值）
    float midResponse = smoothstep(0.08, 0.35, midAudioOriginal) * 1.6;
    
    // 4. 高音响应（使用原始数据，降低阈值）
    float trebleResponse = smoothstep(0.08, 0.35, trebleAudioOriginal) * 1.8;
    
    // 5. 峰值响应（使用原始数据，降低峰值要求）
    float peakValue = max(max(bassAudioOriginal, midAudioOriginal), trebleAudioOriginal);
    float peakResponse = smoothstep(0.12, 0.4, peakValue) * 2.0; // 12%开始
    
    // 6. 综合响应强度（提高增益系数）
    float responseA = totalEnergyResponse;
    float responseB = max(max(bassResponse, midResponse), trebleResponse) * 1.5;
    float responseC = (bassResponse + midResponse + trebleResponse) / 2.5;
    float responseD = peakResponse * 1.4;
    
    // 最终音乐强度（取最大值）
    float musicIntensity = max(max(responseA, responseB), max(responseC, responseD));
    
    // 🔥 轻微提升低值，让低音频强度也能触发
    if (musicIntensity < 0.3) {
        musicIntensity = musicIntensity * 0.7; // 低值轻微提升
    }
    
    // 🔥 非线性压缩：高值时压缩（避免刺眼）
    if (musicIntensity > 1.0) {
        float excess = musicIntensity - 1.0;
        musicIntensity = 1.0 + sqrt(excess) * 0.5;
    }
    
    // 最终限制：最高1.8
    musicIntensity = clamp(musicIntensity, 0.0, 1.8);
    
    // ===== 低频主闪电触发（使用原始音频数据，大幅降低阈值）=====
    float bassThreshold = smoothstep(0.05, 0.3, bassAudioOriginal); // 使用原始数据，5%开始触发
    float lightningTrigger = bassThreshold * (sin(time * 10.0 + bassAudioOriginal * 20.0) * 0.5 + 0.5);
    
    // ===== 简化背景：纯渐变（去掉复杂FBM，避免卡顿）=====
    float background = 1.0 - smoothstep(0.0, 0.6, radius);
    background *= 0.12; // 很暗的背景
    
    // 音频让背景轻微变亮（不闪烁，只是变亮）
    background *= (1.0 + musicIntensity * 0.3);
    
    // ===== 主闪电层：清晰的闪电纹理（不用模糊的分形）=====
    float mainLightning = 0.0;
    
    // 方法1：基于距离场的清晰闪电条纹
    float2 lightningUV = uv * 8.0;
    lightningUV.y += time * 0.5; // 向下流动
    
    // 创建垂直闪电条纹
    float stripe = abs(sin(lightningUV.x * 3.14159 + time * 2.0));
    stripe = pow(stripe, 3.0); // 锐化
    
    // 添加一些扰动让闪电不规则
    float distortion = sin(lightningUV.y * 2.0 + time) * 0.3;
    stripe += distortion;
    
    // 闪电强度（直接由音频控制，不用阈值）
    mainLightning = stripe * (bassAudioOriginal * 2.0 + musicIntensity * 1.5);
    mainLightning = clamp(mainLightning, 0.0, 1.0);
    
    // ===== 主闪电脉冲：清晰的中心闪电束（简化，直接绘制）=====
    float centralBolt = 0.0;
    
    // 垂直闪电束（从中心向上下延伸）
    float centerDist = abs(uv.x - 0.5); // 距离中心的横向距离
    
    // 创建清晰的中心闪电线
    float boltLine = exp(-centerDist * 60.0); // 很细的线
    
    // 添加一些左右摇摆
    float sway = sin(uv.y * 8.0 + time * 3.0) * 0.02;
    boltLine += exp(-(centerDist - sway) * 40.0) * 0.5;
    
    // 音频控制强度（低音越强，闪电越亮）
    centralBolt = boltLine * (bassAudioOriginal * 3.0 + musicIntensity * 2.0);
    centralBolt = clamp(centralBolt, 0.0, 1.0);
    
    // ===== 闪电枝干：径向清晰线条（高音触发）=====
    float branches = 0.0;
    
    // 创建从中心向外的径向线条（枝干）
    float radialLines = abs(sin(angle * 6.0 + time * 2.0)); // 12条径向线
    radialLines = pow(radialLines, 8.0); // 锐化成细线
    
    // 只在一定半径范围内显示
    float radialMask = smoothstep(0.15, 0.2, radius) * smoothstep(0.5, 0.45, radius);
    
    // 高音控制枝干强度（高音越强，枝干越亮）
    branches = radialLines * radialMask * (trebleAudioOriginal * 3.0 + musicIntensity * 1.5);
    branches = clamp(branches, 0.0, 1.0);
    
    // ===== 电弧环：清晰的旋转圆环（中音控制大小）=====
    float arc = 0.0;
    
    // 圆环半径（中音越强，圆环越大）
    float arcRadius = 0.25 + midAudioOriginal * 0.15;
    float arcDist = abs(radius - arcRadius);
    
    // 清晰的圆环
    float arcRing = exp(-arcDist * 120.0); // 很细的环
    
    // 旋转的亮点（中音控制旋转速度）
    float arcSpots = sin(angle * 8.0 - time * (2.0 + midAudioOriginal * 3.0)) * 0.5 + 0.5;
    arcSpots = pow(arcSpots, 4.0); // 锐化成点
    
    // 中音控制强度和旋转速度
    arc = (arcRing + arcSpots * arcRing * 2.0) * (midAudioOriginal * 2.5 + musicIntensity);
    arc = clamp(arc, 0.0, 1.0);
    
    // ===== 去掉复杂的光束和网格（避免卡顿）=====
    float beamFlash = 0.0; // 暂时关闭
    float lightningGrid = 0.0; // 暂时关闭
    
    // ===== 雷暴能量核心：简单的中心光晕（音频控制大小）=====
    float core = 0.0;
    
    // 核心大小由总音频能量控制
    float coreSize = 10.0 + totalEnergy * 20.0 + musicIntensity * 15.0;
    core = exp(-radius * radius * coreSize);
    
    // 核心强度（音频越强，核心越亮）
    core *= (0.5 + totalEnergy * 1.5 + musicIntensity * 2.0);
    core = clamp(core, 0.0, 1.0);
    
    // ===== ⚡️ 闪电粒子系统（清晰大粒子，不是噪点）=====
    float particles = 0.0;
    
    // 1️⃣ 清晰的大电火花（高音驱动）
    float2 sparkUV = uv * 8.0; // 减少到8x8网格（更稀疏）
    sparkUV.x += time * 0.4; // 横向飘动
    sparkUV.y += sin(uv.x * 6.28 + time * 1.5) * 0.3; // 波浪式移动
    
    // 使用noise确定粒子位置
    float sparkNoise = noise(sparkUV + time * 0.3);
    
    // 大幅提高阈值，只留下少量明显的粒子
    float sparkThreshold = 0.75 + (1.0 - musicIntensity) * 0.15; // 基础阈值0.75，音频弱时更高
    float sparkMask = smoothstep(sparkThreshold, sparkThreshold + 0.1, sparkNoise);
    
    // 在每个格子中心创建大光晕（不是点）
    float2 cellPos = fract(sparkUV) - 0.5;
    float sparkDist = length(cellPos);
    float sparkGlow = exp(-sparkDist * 8.0); // 大光晕（8.0比较柔和）
    
    // 只有被选中的格子才显示粒子
    float sparks = sparkGlow * sparkMask;
    
    // 高音控制粒子亮度
    sparks *= (trebleAudioOriginal * 2.5 + musicIntensity * 1.5);
    sparks = clamp(sparks, 0.0, 1.0);
    
    // 2️⃣ 屏幕边缘的电弧放电（保持）
    float edgeArc = 0.0;
    
    // 四边的电弧（距离边缘越近越亮）
    float distToEdge = min(min(uv.x, 1.0 - uv.x), min(uv.y, 1.0 - uv.y));
    float edgeMask = smoothstep(0.15, 0.0, distToEdge);
    
    // 边缘电弧纹理（更清晰）
    float edgePattern = abs(sin((uv.x + uv.y) * 15.0 + time * 4.0));
    edgePattern = pow(edgePattern, 8.0); // 更锐利的线条
    
    // 低音触发边缘放电
    edgeArc = edgeMask * edgePattern * (bassAudioOriginal * 3.0 + musicIntensity * 1.5);
    edgeArc = clamp(edgeArc, 0.0, 1.0);
    
    // 3️⃣ 移除密集微粒（避免噪点）
    // float dustParticles = 0.0; // 已移除
    
    // 4️⃣ 清晰的大能量球（中音驱动）
    float2 orbUV = uv * 5.0; // 5x5网格
    float orbNoise = noise(orbUV + time * 0.5);
    
    // 创建圆形光球
    float2 orbCellPos = fract(orbUV) - 0.5;
    float orbDist = length(orbCellPos);
    float orb = exp(-orbDist * 10.0); // 大光晕
    
    // 提高阈值，只显示部分光球
    float orbMask = step(0.65 - musicIntensity * 0.25, orbNoise);
    float energyOrbs = orb * orbMask * (midAudioOriginal * 2.5 + musicIntensity * 1.5);
    energyOrbs = clamp(energyOrbs, 0.0, 1.0);
    
    // 5️⃣ 合并清晰粒子效果（去掉噪点层）
    particles = sparks * 0.8 + edgeArc * 1.0 + energyOrbs * 0.7;
    particles = clamp(particles, 0.0, 1.0);
    
    // ===== 简化的颜色系统 =====
    // 青白色闪电（主色调）
    float3 lightningColor = float3(0.3, 0.7, 1.0);
    
    // 紫色高光（高音部分）
    float3 trebleColor = float3(0.6, 0.4, 1.0);
    
    // 纯白核心
    float3 whiteCore = float3(1.0, 1.0, 1.0);
    
    // 深色背景
    float3 bgColor = float3(0.02, 0.03, 0.08);
    
    // ===== 简单清晰的颜色合成 =====
    // 背景色
    float3 finalColor = bgColor * (1.0 + background);
    
    // 边缘淡化（只影响中心效果）
    float edgeFade = smoothstep(0.6, 0.3, radius);
    
    // 中心效果（受边缘淡化影响）
    float3 centerEffects = float3(0.0);
    centerEffects += lightningColor * mainLightning * 2.0;        // 主闪电条纹（低音）
    centerEffects += whiteCore * centralBolt * 2.5;               // 中心闪电束（低音）
    centerEffects += trebleColor * branches * 1.8;                // 径向枝干（高音）
    centerEffects += lightningColor * arc * 1.5;                  // 电弧环（中音）
    centerEffects += whiteCore * core * 1.5;                      // 中心核心（总能量）
    centerEffects *= edgeFade; // 应用淡化
    
    // ⚡️ 粒子效果（覆盖全屏，不受中心淡化影响）
    float3 particleColor = mix(lightningColor, trebleColor, particles * 0.5);
    float3 particleLayer = particleColor * particles * 1.2;
    
    // 最终合成
    finalColor = finalColor + centerEffects + particleLayer;
    
    // ===== 透明度（清晰可见，包含粒子）=====
    float alpha = mainLightning * 0.5 + centralBolt * 0.8 + branches * 0.6 + arc * 0.5 + core * 0.7 + background * 0.3 + particles * 0.4;
    alpha = clamp(alpha * 1.5, 0.1, 0.95);
    
    // 最终颜色限制
    finalColor = clamp(finalColor, 0.0, 1.0);
    
    return float4(finalColor, alpha);
}

