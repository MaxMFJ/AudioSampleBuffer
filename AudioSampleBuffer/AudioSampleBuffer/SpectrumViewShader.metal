//
//  SpectrumViewShader.metal
//  AudioSampleBuffer
//
//  GPU 渲染圆形频谱：完全替代 UIBezierPath + CAShapeLayer 的 CPU 方案。
//  坐标系与全息/闪电等效果一致：归一化 UV + aspectCorrect。
//

#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────
#pragma mark - 数据结构
// ─────────────────────────────────────────────────────────────────

struct SpectrumUniforms {
    float2 resolution;      // (drawableWidth, drawableHeight)
    float  aspectRatio;     // viewWidth / viewHeight (同 resolution.z)
    float  innerRadius;     // 内圆半径 (归一化, 以 viewWidth 为基准)
    float  time;            // 时间 (秒)
    float  rotationSpeed;   // 渐变旋转速度 (rad/s)
    float  maxBarHeight;    // 最大条高 (归一化)
    float  glowIntensity;   // 辉光强度 0..1
    int    bandCount;       // 频段数 (80)
    float  amplitudeScale;  // 振幅 → 条高的缩放
    float  centerOffsetY;   // 圆心 Y 偏移 (归一化, 补偿 frame.origin.y)
};

struct SpectrumVertex {
    float4 position [[position]];
    float2 texCoord;
};

// ─────────────────────────────────────────────────────────────────
#pragma mark - 顶点着色器
// ─────────────────────────────────────────────────────────────────

vertex SpectrumVertex spectrumVertexShader(uint vid [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    SpectrumVertex out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

// ─────────────────────────────────────────────────────────────────
#pragma mark - 辅助函数
// ─────────────────────────────────────────────────────────────────

/// HSV → RGB
static float3 hsv2rgb(float h, float s, float v) {
    float3 p = abs(fract(float3(h, h + 2.0/3.0, h + 1.0/3.0)) * 6.0 - 3.0);
    return v * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), s);
}

/// 在原始 UV 下计算「屏幕上的圆」的半径
/// uv: [0,1] 对应整块视图，diff = uv - center
/// 屏幕距离: dx_screen = diff.x * viewW, dy_screen = diff.y * viewH
/// 令 r = sqrt(diff.x^2 + (diff.y/aspectRatio)^2)，则 r 以 viewWidth 为单位且屏幕上为圆
static float circleRadiusInScreenSpace(float2 diff, float aspectRatio) {
    return length(float2(diff.x, diff.y / aspectRatio));
}

// ─────────────────────────────────────────────────────────────────
#pragma mark - 片段着色器
// ─────────────────────────────────────────────────────────────────

fragment float4 spectrumFragmentShader(
    SpectrumVertex in [[stage_in]],
    constant SpectrumUniforms &u [[buffer(0)]],
    constant float *amplitudes [[buffer(1)]]
) {
    // 使用原始 UV，圆心在 (0.5, 0.5 + centerOffsetY)
    float2 uv = in.texCoord;
    float2 center = float2(0.5, 0.5 + u.centerOffsetY);
    float2 diff = uv - center;
    
    // 半径按宽高比校正，使屏幕上为圆（不是椭圆）
    float r = circleRadiusInScreenSpace(diff, u.aspectRatio);
    
    // 极角: atan2 → [0, 2π]，从右侧开始顺时针（与旧版一致）
    float angle = atan2(diff.y, diff.x);
    // 转为 [0, 2π]
    float theta = angle;
    if (theta < 0.0) theta += 2.0 * M_PI_F;
    
    int bandCount = u.bandCount;
    float bandAngle = 2.0 * M_PI_F / float(bandCount);
    float gapRatio = 0.15;
    float barAngle = bandAngle * (1.0 - gapRatio);
    
    // 当前像素落入哪个频段
    int bandIdx = int(theta / bandAngle);
    if (bandIdx >= bandCount) bandIdx = bandCount - 1;
    
    // 在该频段内的角度偏移
    float localAngle = theta - float(bandIdx) * bandAngle;
    bool inBar = (localAngle >= 0.0 && localAngle <= barAngle);
    
    // 条形高度 (归一化单位, clamp)
    float amplitude = amplitudes[bandIdx];
    float barHeight = amplitude * u.amplitudeScale;
    barHeight = clamp(barHeight, 0.005, u.maxBarHeight);
    
    float innerR = u.innerRadius;
    float outerR = innerR + barHeight;
    
    // 是否在径向范围内
    bool inRadius = (r >= innerR && r <= outerR);
    
    if (inBar && inRadius) {
        // 渐变旋转 hue
        float hueOffset = u.time * u.rotationSpeed;
        float hue = fract(float(bandIdx) / float(bandCount) + hueOffset);
        
        // 径向渐变亮度
        float radialFactor = (r - innerR) / max(barHeight, 0.001);
        float brightness = mix(0.85, 1.0, radialFactor);
        
        float3 rgb = hsv2rgb(hue, 1.0, brightness);
        
        // 柔和抗锯齿
        float edgeSoft = 0.003;
        float radialAlpha = smoothstep(innerR - edgeSoft, innerR, r)
                          * smoothstep(outerR + edgeSoft, outerR, r);
        float angularAlpha = smoothstep(0.0, edgeSoft * 3.0, localAngle)
                           * smoothstep(barAngle, barAngle - edgeSoft * 3.0, localAngle);
        float alpha = radialAlpha * angularAlpha;
        
        return float4(rgb * alpha, alpha);
    }
    
    // 辉光区域
    if (u.glowIntensity > 0.0 && inBar) {
        float amp = amplitudes[bandIdx];
        float bh = clamp(amp * u.amplitudeScale, 0.005, u.maxBarHeight);
        float outerR2 = innerR + bh;
        float glowRange = max(bh * 0.25, 0.01);
        
        if (r > outerR2 && r < outerR2 + glowRange) {
            float hueOffset = u.time * u.rotationSpeed;
            float hue = fract(float(bandIdx) / float(bandCount) + hueOffset);
            float3 rgb = hsv2rgb(hue, 0.8, 1.0);
            float glowAlpha = (1.0 - (r - outerR2) / glowRange)
                            * u.glowIntensity * amp * 0.4;
            return float4(rgb * glowAlpha, glowAlpha);
        }
    }
    
    return float4(0.0);
}
