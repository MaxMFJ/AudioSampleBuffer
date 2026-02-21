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
    float4 resolution;      // (drawableWidth, drawableHeight, 0, 0) 像素
    float  innerRadius;     // 内圆半径，归一化：1.0 = 内接圆半径 (min/2 像素)
    float  barWidth;
    float  time;
    float  rotationSpeed;
    float  maxBarHeight;
    float  glowIntensity;
    int    bandCount;
    float  amplitudeScale;
    
    // === 新增：颜色配置 ===
    int    colorMode;       // 0=彩虹(默认), 1=单色渐变, 2=双色渐变, 3=自定义主题
    float3 primaryColor;    // 主色 (RGB, 0-1)
    float3 secondaryColor;  // 副色 (RGB, 0-1)
    float  colorSaturation; // 饱和度 (0-1)
    float  colorBrightness; // 亮度倍数 (0.5-2.0)
    float  hueShift;        // 色相偏移 (0-1)
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

// 根据颜色模式计算频谱条颜色
static float3 computeBarColor(int colorMode, float3 primaryColor, float3 secondaryColor,
                              float saturation, float brightness, float hueShift,
                              int bandIdx, int bandCount, float time, float rotationSpeed, float radialPos) {
    float3 color;
    float t = float(bandIdx) / float(bandCount);  // 频段位置 0-1
    
    switch (colorMode) {
        case 1: {
            // 单色渐变模式：主色按亮度渐变
            float gradientFactor = mix(0.6, 1.0, radialPos);
            color = primaryColor * gradientFactor * brightness;
            break;
        }
        case 2: {
            // 双色渐变模式：主色到副色的渐变
            color = mix(primaryColor, secondaryColor, t) * brightness;
            break;
        }
        case 3: {
            // 自定义主题模式：主副色交替 + 亮度变化
            float mixFactor = sin(t * M_PI_F * 4.0 + time * rotationSpeed) * 0.5 + 0.5;
            color = mix(primaryColor, secondaryColor, mixFactor) * brightness;
            color = mix(color, color * 1.3, radialPos);
            break;
        }
        default: {
            // 彩虹模式（默认）
            float hueOffset = time * rotationSpeed + hueShift;
            float hue = fract(t + hueOffset);
            color = hsv2rgb(hue, saturation, brightness);
            break;
        }
    }
    return clamp(color, 0.0, 1.5);  // 允许少量过曝增加发光感
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
        // 计算径向位置用于亮度渐变
        float radialPos = (r - u.innerRadius) / max(barHeight, 0.001);
        float baseBrightness = mix(0.85, 1.0, radialPos) * u.colorBrightness;
        
        // 使用新的颜色计算函数
        float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                     u.colorSaturation, baseBrightness, u.hueShift,
                                     bandIdx, bandCount, u.time, u.rotationSpeed, radialPos);

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
            // 使用相同的颜色模式计算光晕颜色
            float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                         u.colorSaturation * 0.8, u.colorBrightness, u.hueShift,
                                         bandIdx, bandCount, u.time, u.rotationSpeed, 1.0);
            float glowAlpha = (1.0 - (r - outerR2) / glowRange) * u.glowIntensity * amplitude2 * 0.4;
            return float4(rgb, glowAlpha);
        }
    }

    return float4(0.0, 0.0, 0.0, 0.0);
}
