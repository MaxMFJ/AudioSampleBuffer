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
    float  opacity;         // 整体透明度
    int    layoutStyle;     // 0=圆环, 1=竖向音柱, 2=双向音柱
    float2 layoutOffset;    // 归一化偏移，基于视图中心
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
    int bandCount = u.bandCount;
    float2 centerUV = float2(0.5 + u.layoutOffset.x, 0.5 + u.layoutOffset.y);

    if (u.layoutStyle == 0) {
        float2 d = (uv - centerUV) * res;
        float r = 2.0 * length(d) / min(res.x, res.y);
        float theta = atan2(-d.x, d.y);
        if (theta < 0.0) theta += 2.0 * M_PI_F;

        float bandAngle = 2.0 * M_PI_F / float(bandCount);
        float gapRatio = 0.15;
        float barAngle = bandAngle * (1.0 - gapRatio);

        int bandIdx = int(theta / bandAngle);
        if (bandIdx >= bandCount) bandIdx = bandCount - 1;
        float localAngle = theta - float(bandIdx) * bandAngle;
        bool inBar = (localAngle >= 0.0 && localAngle <= barAngle);

        float amplitude = amplitudes[bandIdx];
        float barHeight = clamp(amplitude * u.amplitudeScale, 0.002, u.maxBarHeight);
        float outerR = u.innerRadius + barHeight;
        bool inRadius = (r >= u.innerRadius && r <= outerR);

        if (inBar && inRadius) {
            float radialPos = (r - u.innerRadius) / max(barHeight, 0.001);
            float baseBrightness = mix(0.85, 1.0, radialPos) * u.colorBrightness;
            float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                         u.colorSaturation, baseBrightness, u.hueShift,
                                         bandIdx, bandCount, u.time, u.rotationSpeed, radialPos);

            float edgeSoft = 0.008;
            float radialAlpha = smoothstep(u.innerRadius - edgeSoft, u.innerRadius, r)
                              * smoothstep(outerR + edgeSoft, outerR, r);
            float angularAlpha = smoothstep(0.0, edgeSoft, localAngle)
                               * smoothstep(barAngle, barAngle - edgeSoft, localAngle);
            float alpha = radialAlpha * angularAlpha;

            return float4(rgb, alpha * u.opacity);
        }

        if (u.glowIntensity > 0.0 && inBar) {
            float amplitude2 = amplitudes[bandIdx];
            float barH = clamp(amplitude2 * u.amplitudeScale, 0.002, u.maxBarHeight);
            float outerR2 = u.innerRadius + barH;
            float glowRange = max(barH * 0.25, 0.01);
            if (r > outerR2 && r < outerR2 + glowRange) {
                float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                             u.colorSaturation * 0.8, u.colorBrightness, u.hueShift,
                                             bandIdx, bandCount, u.time, u.rotationSpeed, 1.0);
                float glowAlpha = (1.0 - (r - outerR2) / glowRange) * u.glowIntensity * amplitude2 * 0.4;
                return float4(rgb, glowAlpha * u.opacity);
            }
        }
    } else {
        float contentWidth = 0.78;
        float slotWidth = contentWidth / float(bandCount);
        float barWidth = slotWidth * 0.68;
        float halfBarWidth = barWidth * 0.5;
        float leftX = centerUV.x - contentWidth * 0.5;
        float localX = uv.x - leftX;

        if (localX >= 0.0 && localX <= contentWidth) {
            int bandIdx = min(int(localX / slotWidth), bandCount - 1);
            float barCenterX = leftX + (float(bandIdx) + 0.5) * slotWidth;
            float xDist = abs(uv.x - barCenterX);
            float amplitude = clamp(amplitudes[bandIdx], 0.0, 1.0);
            float scaledHeight = clamp(amplitude * 0.52, 0.015, 0.42);
            float edgeSoftX = max(slotWidth * 0.12, 0.0025);

            if (u.layoutStyle == 1) {
                float baseY = clamp(0.84 + u.layoutOffset.y, 0.38, 0.92);
                float topY = max(0.05, baseY - scaledHeight);
                bool inRect = (xDist <= halfBarWidth && uv.y >= topY && uv.y <= baseY);
                if (inRect) {
                    float radialPos = clamp((baseY - uv.y) / max(baseY - topY, 0.001), 0.0, 1.0);
                    float baseBrightness = mix(0.8, 1.08, radialPos) * u.colorBrightness;
                    float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                                 u.colorSaturation, baseBrightness, u.hueShift,
                                                 bandIdx, bandCount, u.time, u.rotationSpeed, radialPos);
                    float alphaX = smoothstep(halfBarWidth + edgeSoftX, halfBarWidth - edgeSoftX, xDist);
                    float edgeSoftY = 0.01;
                    float alphaY = smoothstep(topY - edgeSoftY, topY + edgeSoftY, uv.y)
                                 * smoothstep(baseY + edgeSoftY, baseY - edgeSoftY, uv.y);
                    return float4(rgb, alphaX * alphaY * u.opacity);
                }
            } else {
                float centerY = clamp(centerUV.y, 0.18, 0.82);
                float topY = max(0.04, centerY - scaledHeight);
                float bottomY = min(0.96, centerY + scaledHeight);
                bool inRect = (xDist <= halfBarWidth && uv.y >= topY && uv.y <= bottomY);
                if (inRect) {
                    float radialPos = 1.0 - clamp(abs(uv.y - centerY) / max(scaledHeight, 0.001), 0.0, 1.0);
                    float baseBrightness = mix(0.82, 1.12, radialPos) * u.colorBrightness;
                    float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                                 u.colorSaturation, baseBrightness, u.hueShift,
                                                 bandIdx, bandCount, u.time, u.rotationSpeed, radialPos);
                    float alphaX = smoothstep(halfBarWidth + edgeSoftX, halfBarWidth - edgeSoftX, xDist);
                    float edgeSoftY = 0.01;
                    float alphaY = smoothstep(topY - edgeSoftY, topY + edgeSoftY, uv.y)
                                 * smoothstep(bottomY + edgeSoftY, bottomY - edgeSoftY, uv.y);
                    return float4(rgb, alphaX * alphaY * u.opacity);
                }
            }

            if (u.glowIntensity > 0.0 && xDist <= halfBarWidth + slotWidth * 0.25) {
                float3 rgb = computeBarColor(u.colorMode, u.primaryColor, u.secondaryColor,
                                             u.colorSaturation * 0.85, u.colorBrightness, u.hueShift,
                                             bandIdx, bandCount, u.time, u.rotationSpeed, 1.0);
                float glowAlpha = 0.0;
                if (u.layoutStyle == 1) {
                    float baseY = clamp(0.84 + u.layoutOffset.y, 0.38, 0.92);
                    float topY = max(0.05, baseY - scaledHeight);
                    if (uv.y < topY && uv.y > topY - 0.035) {
                        glowAlpha = (1.0 - (topY - uv.y) / 0.035) * amplitude * 0.22 * u.glowIntensity;
                    }
                } else {
                    float centerY = clamp(centerUV.y, 0.18, 0.82);
                    float topY = max(0.04, centerY - scaledHeight);
                    float bottomY = min(0.96, centerY + scaledHeight);
                    if (uv.y < topY && uv.y > topY - 0.03) {
                        glowAlpha = (1.0 - (topY - uv.y) / 0.03) * amplitude * 0.18 * u.glowIntensity;
                    } else if (uv.y > bottomY && uv.y < bottomY + 0.03) {
                        glowAlpha = (1.0 - (uv.y - bottomY) / 0.03) * amplitude * 0.18 * u.glowIntensity;
                    }
                }
                if (glowAlpha > 0.0) {
                    return float4(rgb, glowAlpha * u.opacity);
                }
            }
        }
    }

    return float4(0.0, 0.0, 0.0, 0.0);
}
