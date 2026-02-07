//
//  SpectrumViewShader.metal
//  AudioSampleBuffer
//
//  圆环在屏幕上为真圆：半径按「像素等比例」计算，避免 UV 直接 length 导致竖屏被拉成 O 形。
//  r = 2 * length((uv-0.5)*resolution.xy) / min(resolution.x, resolution.y)，圆心 (0.5,0.5)。
//

#include <metal_stdlib>
using namespace metal;

// ─────────────────────────────────────────────────────────────────
#pragma mark - 数据结构
// ─────────────────────────────────────────────────────────────────

struct SpectrumUniforms {
    float4 resolution;   // (drawableWidth, drawableHeight, 0, 0) 像素
    float  innerRadius;   // 内圆半径，归一化：1.0 = 内接圆半径 (min/2 像素)
    float  barWidth;
    float  time;
    float  rotationSpeed;
    float  maxBarHeight;
    float  glowIntensity;
    int    bandCount;
    float  amplitudeScale;
};

struct SpectrumVertex {
    float4 position [[position]];
    float2 texCoord;
};

// ─────────────────────────────────────────────────────────────────
#pragma mark - 屏幕空间真圆半径（消除竖屏上下拉伸）
// 用 (uv-0.5)*resolution.xy 得到像素偏移，再除以 min 归一化，使 r=1 为内接圆
// ─────────────────────────────────────────────────────────────────

static inline float radiusInscribedCircle(float2 uv, float2 res) {
    float2 d = (uv - 0.5) * res;
    float minSide = min(res.x, res.y);
    return 2.0 * length(d) / minSide;  // 1.0 = 内接圆半径
}

// ─────────────────────────────────────────────────────────────────
#pragma mark - 顶点着色器
// ─────────────────────────────────────────────────────────────────

vertex SpectrumVertex spectrumVertexShader(uint vid [[vertex_id]]) {
    float2 positions[4] = {
        float2(-1.0, -1.0), float2( 1.0, -1.0),
        float2(-1.0,  1.0), float2( 1.0,  1.0)
    };
    float2 texCoords[4] = {
        float2(0.0, 1.0), float2(1.0, 1.0),
        float2(0.0, 0.0), float2(1.0, 0.0)
    };
    SpectrumVertex out;
    out.position = float4(positions[vid], 0.0, 1.0);
    out.texCoord = texCoords[vid];
    return out;
}

// ─────────────────────────────────────────────────────────────────
#pragma mark - 辅助
// ─────────────────────────────────────────────────────────────────

static float3 hsv2rgb(float h, float s, float v) {
    float3 c = float3(h, s, v);
    float3 p = abs(fract(float3(c.x, c.x + 2.0/3.0, c.x + 1.0/3.0)) * 6.0 - 3.0);
    return c.z * mix(float3(1.0), clamp(p - 1.0, 0.0, 1.0), c.y);
}

// ─────────────────────────────────────────────────────────────────
#pragma mark - 片段着色器（UV + 归一化半径，圆心固定 0.5,0.5）
// ─────────────────────────────────────────────────────────────────

fragment float4 spectrumFragmentShader(
    SpectrumVertex in [[stage_in]],
    constant SpectrumUniforms &u [[buffer(0)]],
    constant float *amplitudes [[buffer(1)]]
) {
    float2 uv = in.texCoord;
    float2 res = u.resolution.xy;
    float2 d = (uv - 0.5) * res;
    float r = radiusInscribedCircle(uv, res);  // 真圆半径，1.0 = 内接圆
    float theta = atan2(-d.x, d.y);
    if (theta < 0.0) theta += 2.0 * M_PI_F;

    int bandCount = u.bandCount;
    float bandAngle = 2.0 * M_PI_F / float(bandCount);
    float gapRatio = 0.15;
    float barAngle = bandAngle * (1.0 - gapRatio);

    int bandIdx = int(theta / bandAngle);
    if (bandIdx >= bandCount) bandIdx = bandCount - 1;
    float localAngle = theta - float(bandIdx) * bandAngle;
    bool inBar = (localAngle >= 0.0 && localAngle <= barAngle);

    float amplitude = amplitudes[bandIdx];
    float barHeight = amplitude * u.amplitudeScale;
    barHeight = clamp(barHeight, 0.002, u.maxBarHeight);
    float outerR = u.innerRadius + barHeight;
    bool inRadius = (r >= u.innerRadius && r <= outerR);

    if (inBar && inRadius) {
        float hueOffset = u.time * u.rotationSpeed;
        float hue = fract(float(bandIdx) / float(bandCount) + hueOffset);
        float brightness = mix(0.85, 1.0, (r - u.innerRadius) / max(barHeight, 0.001));
        float3 rgb = hsv2rgb(hue, 1.0, brightness);

        float edgeSoft = 0.008;
        float radialAlpha = smoothstep(u.innerRadius - edgeSoft, u.innerRadius, r)
                          * smoothstep(outerR + edgeSoft, outerR, r);
        float angularAlpha = smoothstep(0.0, edgeSoft, localAngle)
                           * smoothstep(barAngle, barAngle - edgeSoft, localAngle);
        float alpha = radialAlpha * angularAlpha;

        float glow = 0.0;
        if (u.glowIntensity > 0.0 && r > outerR - barHeight * 0.2) {
            float glowRange = barHeight * 0.3;
            float glowDist = max(0.0, r - outerR);
            if (glowDist < glowRange)
                glow = (1.0 - glowDist / glowRange) * u.glowIntensity * amplitude;
        }
        return float4(rgb, alpha + glow * 0.5);
    }

    if (u.glowIntensity > 0.0 && inBar) {
        float amplitude2 = amplitudes[bandIdx];
        float barH = clamp(amplitude2 * u.amplitudeScale, 0.002, u.maxBarHeight);
        float outerR2 = u.innerRadius + barH;
        float glowRange = max(barH * 0.25, 0.01);
        if (r > outerR2 && r < outerR2 + glowRange) {
            float hueOffset = u.time * u.rotationSpeed;
            float hue = fract(float(bandIdx) / float(bandCount) + hueOffset);
            float3 rgb = hsv2rgb(hue, 0.8, 1.0);
            float glowAlpha = (1.0 - (r - outerR2) / glowRange) * u.glowIntensity * amplitude2 * 0.4;
            return float4(rgb, glowAlpha);
        }
    }

    return float4(0.0, 0.0, 0.0, 0.0);
}
