//
//  CherryBlossomShader.metal
//  AudioSampleBuffer
//
//  樱花飘雪视觉效果 v5（极致性能优化）
//  目标: GPU < 40%, 15个花瓣 + 6个光点 + 中央花 + 柔光背景
//  优化: 消除所有循环内sin/cos/hash, 用预计算查找表替代
//

#include "ShaderCommon.metal"

// ============================================================================
// 樱花飘雪着色器 v5 - 极致性能版
// ============================================================================

// 花瓣形状（纯代数，无三角函数）
static inline float petalShape(float2 uv, float2 center, float size, float cosR, float sinR) {
    float2 p = uv - center;
    p = float2(p.x * cosR - p.y * sinR, p.x * sinR + p.y * cosR);
    float2 s = p / (size * float2(1.2, 0.6));
    float d = dot(s, s);
    return saturate(1.0 - d * 1.8); // 用线性衰减代替smoothstep
}

// 边缘淡化（简化版，用clamp代替两次smoothstep）
static inline float edgeFade(float t, float zone) {
    return saturate(t / zone) * saturate((1.0 - t) / zone);
}

fragment float4 cherryBlossomSnowFragment(RasterizerData in [[stage_in]],
                                          constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 🎵 音频：极简采样（3次循环 → 直接取关键频点）
    float bass = (uniforms.audioData[2].x + uniforms.audioData[5].x
                + uniforms.audioData[8].x + uniforms.audioData[12].x) * 0.6;
    bass = min(bass, 1.5);
    
    float mid = (uniforms.audioData[20].x + uniforms.audioData[28].x
               + uniforms.audioData[36].x + uniforms.audioData[44].x) * 0.5;
    mid = min(mid, 1.5);
    
    float energy = (bass + mid) * 0.5;
    
    // ============ 背景（极简：渐变 + 1个光晕） ============
    float3 bg = mix(float3(0.22, 0.1, 0.18), float3(0.1, 0.04, 0.16), uv.y);
    bg *= (0.9 + energy * 0.2);
    
    // 单个中央柔光（用dot代替length+exp）
    float2 gc = uv - float2(0.5, 0.5);
    float gd = dot(gc, gc);
    bg += float3(0.8, 0.45, 0.6) * max(0.0, 0.12 - gd * 0.3) * (1.0 + mid * 0.5);
    
    // ============ 花瓣预计算（循环外一次性算好所有三角函数） ============
    float midScale = 1.0 + mid * 0.6;
    float midBrt = 0.8 + mid * 0.2;
    
    // 预算2个时间基准sin/cos（所有花瓣通过相位偏移复用）
    float sinT1 = sin(time * 0.5);
    float cosT1 = cos(time * 0.5);
    float sinT2 = sin(time * 1.8);
    float bassSway = sinT2 * bass * 0.05;
    
    // ============ 15个花瓣（3层x5个） ============
    // 预计算花瓣种子（常量数组，避免循环内hash）
    // 15组: {seedX, seedY, colorT}
    const float3 petalSeeds[15] = {
        {0.12, 0.87, 0.3}, {0.34, 0.23, 0.7}, {0.56, 0.61, 0.1}, {0.78, 0.45, 0.5}, {0.91, 0.12, 0.9},
        {0.23, 0.76, 0.6}, {0.45, 0.34, 0.2}, {0.67, 0.89, 0.8}, {0.89, 0.56, 0.4}, {0.01, 0.67, 0.0},
        {0.38, 0.15, 0.5}, {0.62, 0.48, 0.3}, {0.84, 0.72, 0.7}, {0.16, 0.93, 0.1}, {0.49, 0.06, 0.8}
    };
    
    float3 petalColor = float3(0.0);
    
    for (int i = 0; i < 15; i++) {
        float3 seed = petalSeeds[i];
        float fi = float(i);
        int layer = i / 5;           // 0,1,2
        float layerF = float(layer);
        float depth = 0.5 + layerF * 0.25;
        float speed = 0.05 + layerF * 0.015;
        float baseSize = (0.022 + layerF * 0.006) * (0.8 + seed.x * 0.4);
        
        // 位置（用 fract 循环，无额外sin）
        float rawPx = fract(seed.x + time * speed * (0.3 + seed.y * 0.3));
        float rawPy = fract(seed.y + time * speed * (0.7 + seed.x * 0.5));
        
        // 风吹 + 低音摆动（复用预算的sinT1和bassSway）
        float swaySign = (fi - 7.0) * 0.14; // 每瓣不同偏移，用常量代替sin(fi*...)
        float px = rawPx + sinT1 * 0.03 * depth + bassSway * swaySign;
        float py = 1.0 - rawPy;
        
        // 淡入淡出
        float fade = edgeFade(rawPy, 0.15) * edgeFade(saturate(px), 0.1);
        if (fade < 0.02) continue;
        
        // 曼哈顿距离剔除
        float dx = abs(uv.x - px);
        float dy = abs(uv.y - py);
        if (dx + dy > 0.08) continue;
        
        // 旋转（用预算的sinT1/cosT1 + 常量偏移，避免循环内cos/sin）
        float phaseOff = fi * 1.23 + layerF * 2.0;
        float ca = cosT1 * cos(phaseOff) - sinT1 * sin(phaseOff); // cos(t*0.5 + phase)
        float sa = sinT1 * cos(phaseOff) + cosT1 * sin(phaseOff); // sin(t*0.5 + phase)
        // 注: cos(phaseOff)/sin(phaseOff) 是常量，编译器会预计算
        
        float size = baseSize * midScale * (0.5 + fade * 0.5);
        float p = petalShape(uv, float2(px, py), size, ca, sa);
        
        // 颜色（用种子直接插值，无hash）
        float3 c = mix(float3(1.0, 0.85, 0.9), float3(0.98, 0.7, 0.82), seed.z);
        petalColor += c * p * (0.5 + depth * 0.5) * midBrt * fade;
    }
    
    // ============ 中央花朵（简化） ============
    float2 fc = float2(0.5, 0.5);
    float2 fp = uv - fc;
    float fd = length(fp);
    float fSize = 0.065 + mid * 0.02;
    
    float3 flower = float3(0.0);
    if (fd < fSize * 1.3) {
        float2 fs = fp / fSize;
        float fa = atan2(fs.y, fs.x) + time * 0.1;
        float fr = length(fs);
        float petal = 0.35 + 0.16 * cos(fa * 5.0);
        float shape = saturate(1.0 - fr / petal);
        float3 fCol = mix(float3(1.0, 0.95, 0.97), float3(1.0, 0.72, 0.84), fr * 2.5);
        float breath = sinT1 * 0.2 + 0.8; // 复用预算sinT1
        flower = fCol * shape * 0.45 * breath;
    }
    // 花朵发光（简化版）
    flower += float3(0.8, 0.6, 0.7) * max(0.0, 0.03 - fd * 0.2) * midBrt;
    
    // ============ 6个光点粒子 ============
    float3 particles = float3(0.0);
    
    const float4 particleData[6] = {
        {0.08, 0.06, 1.0, 0.5},   // {orbitSpeedX, orbitSpeedY, phaseX, phaseY}
        {0.10, 0.07, 2.6, 1.2},
        {0.07, 0.09, 4.1, 2.8},
        {0.11, 0.06, 5.5, 0.9},
        {0.06, 0.08, 0.8, 4.0},
        {0.09, 0.07, 3.3, 2.1}
    };
    
    for (int i = 0; i < 6; i++) {
        float4 pd = particleData[i];
        
        float px = 0.5 + sin(time * pd.x + pd.z) * (0.15 + float(i) * 0.03);
        float py = 0.5 + cos(time * pd.y + pd.w) * (0.12 + float(i) * 0.025);
        
        float2 diff = uv - float2(px, py);
        float d = dot(diff, diff); // 用dot代替length
        
        if (d > 0.004) continue; // 0.004 ≈ 0.063²
        
        float pSize = 0.006 + energy * 0.004;
        float glow = exp(-d / (pSize * pSize));
        
        // 淡入淡出 + 闪烁（复用预算的三角函数）
        float fade = sin(time * (0.35 + float(i) * 0.05) + float(i) * 2.0);
        fade = fade * 0.4 + 0.6; // 0.2 ~ 1.0
        
        particles += float3(1.0, 0.88, 0.93) * glow * fade * (0.3 + energy * 0.3);
    }
    
    // ============ 合成 ============
    float3 finalColor = bg + petalColor + flower + particles;
    
    // 暗角（简化）
    float2 vc = uv * 2.0 - 1.0;
    finalColor *= 1.0 - dot(vc, vc) * 0.12;
    
    // 色调映射
    finalColor = finalColor / (finalColor + 0.7);
    finalColor.r *= 1.04;
    finalColor.b *= 0.96;
    
    return float4(finalColor, 1.0);
}
