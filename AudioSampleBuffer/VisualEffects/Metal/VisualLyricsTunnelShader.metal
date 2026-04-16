//
//  VisualLyricsTunnelShader.metal
//  AudioSampleBuffer
//
//  视觉歌词隧道
//  45 度斜向歌词流 + 情绪主题色 + 入场/驻留/离场循环
//

#include "ShaderCommon.metal"
using namespace metal;

struct VisualLyricLine {
    float4 colorAndAlpha;
    float4 layout;
    float4 glow;
};

struct VisualLyricsUniforms {
    Uniforms base;
    float4 accentColor;
    float4 emotionColor;
    float4 timeline;
    float4 lyricMetrics;
    VisualLyricLine lines[8];
};

constant uint kLyricLineCount = 8;

static inline float vlHash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static inline float vlHash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float vlNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = vlHash2(i);
    float b = vlHash2(i + float2(1.0, 0.0));
    float c = vlHash2(i + float2(0.0, 1.0));
    float d = vlHash2(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static inline float sdRoundedBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

static inline float rectGlow(float2 uv, float2 center, float2 size, float radius) {
    float d = sdRoundedBox(uv - center, size, radius);
    return exp(-max(d, 0.0) * 42.0) * smoothstep(0.22, -0.28, d);
}

static inline float stripeGlyph(float2 local, float seed) {
    float glyph = 0.0;

    float topBar = rectGlow(local, float2(0.0, 0.34), float2(0.28, 0.042), 0.02);
    float midBar = rectGlow(local, float2(0.0, 0.0), float2(0.22, 0.036), 0.02);
    float lowBar = rectGlow(local, float2(0.0, -0.32), float2(0.28, 0.042), 0.02);
    float stem = rectGlow(local, float2(-0.24 + 0.18 * sin(seed * 13.1), 0.0), float2(0.045, 0.34), 0.02);
    float slash = rectGlow(float2(local.x * 0.78 + local.y * 0.62,
                                  -local.x * 0.62 + local.y * 0.78),
                           float2(0.0, 0.0),
                           float2(0.036, 0.42),
                           0.02);

    glyph = max(glyph, topBar);
    glyph = max(glyph, stem);
    glyph = max(glyph, midBar * step(0.32, seed));
    glyph = max(glyph, lowBar * step(0.58, seed));
    glyph = max(glyph, slash * step(0.78, seed));

    return glyph;
}

static inline float lyricBand(float2 uv, float baseline, float width, float density, float seed) {
    float2 local = uv;
    local.y -= baseline;
    local.x += seed * 0.9;
    local.x *= density;

    float glyphIndex = floor(local.x + 0.5);
    float2 glyphUV = float2(fract(local.x + 0.5) - 0.5, local.y / max(width, 0.0001));

    float glyphSeed = vlHash(glyphIndex + seed * 91.7);
    float glyph = stripeGlyph(glyphUV, glyphSeed);

    float spacingMask = smoothstep(0.60, 0.18, abs(glyphUV.x));
    return glyph * spacingMask;
}

static inline float giantLyricBand(float2 local, float width, float density, float seed) {
    float2 warped = local;
    warped.x *= density;
    warped.y /= max(width, 0.0001);

    float core = 0.0;
    float segmentCount = 7.0;
    float sweep = floor((warped.x + 0.5) * segmentCount);

    for (int i = -1; i <= 1; ++i) {
        float seg = sweep + float(i);
        float segSeed = vlHash(seg + seed * 53.1);
        float localX = fract((warped.x + 0.5) * segmentCount + float(i)) - 0.5;
        float2 glyphUV = float2(localX, warped.y);
        float glyph = stripeGlyph(glyphUV * float2(1.25, 1.85), segSeed);
        core = max(core, glyph);
    }

    float slab = rectGlow(float2(local.x * 0.92, local.y), float2(0.0, 0.0), float2(0.60, width * 0.92), 0.06);
    float centerBar = rectGlow(local, float2(0.0, 0.0), float2(0.78, width * 0.18), 0.05);
    float edgeGlow = exp(-abs(local.y) / max(width * 0.8, 0.0001));

    return max(core, slab * 0.78 + centerBar * 0.55) * edgeGlow;
}

static inline float2 rotate2D(float2 p, float angle) {
    float c = cos(angle);
    float s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

fragment float4 visualLyricsTunnelFragment(RasterizerData in [[stage_in]],
                                           constant VisualLyricsUniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float2 aspectUV = aspectCorrect(uv, uniforms.base.resolution);
    float2 p = aspectUV - 0.5;

    float time = uniforms.base.time.x;
    float motionTime = uniforms.timeline.x;
    float lyricProgress = saturate(uniforms.timeline.y);
    float lyricPulse = uniforms.timeline.z;
    float lyricIntensity = uniforms.timeline.w;

    float bass = uniforms.base.cyberpunkControls.z;
    float mid = uniforms.base.cyberpunkControls.w;
    float treble = uniforms.base.cyberpunkFrequencyControls.x;
    float energy = uniforms.base.cyberpunkFrequencyControls.y;

    float3 theme = clamp(uniforms.base.cyberpunkBackgroundParams.rgb, 0.0, 1.0);
    float3 accent = clamp(uniforms.accentColor.rgb, 0.0, 1.0);
    float3 emotion = clamp(uniforms.emotionColor.rgb, 0.0, 1.0);
    float3 bassColor = mix(theme, float3(0.16, 0.92, 1.00), 0.72);
    float3 midColor = mix(accent, float3(1.00, 0.34, 0.92), 0.78);
    float3 trebleColor = mix(emotion, float3(1.00, 0.92, 0.66), 0.82);

    float bgGradient = smoothstep(-0.55, 0.75, p.y);
    float3 color = mix(float3(0.010, 0.012, 0.030), theme * float3(0.14, 0.17, 0.24) + float3(0.015, 0.014, 0.032), bgGradient);

    float2 bgDrift = float2(motionTime * 0.018, -motionTime * 0.013);
    float haze = vlNoise(uv * 4.5 + bgDrift) * 0.55 + vlNoise(uv * 8.0 - bgDrift * 1.8) * 0.45;
    color += mix(theme, emotion, 0.38) * haze * (0.10 + energy * 0.12);

    float bassRail = exp(-abs(p.x + 0.18) * 4.6) * smoothstep(-0.92, 0.72, p.y + 0.28);
    float midRail = exp(-abs(p.y - 0.02) * 5.8) * smoothstep(-0.96, 0.86, p.x + 0.20);
    float trebleArc = exp(-abs(length(p - float2(0.18, -0.12)) - 0.36) * 10.5);
    color += bassColor * bassRail * (0.12 + bass * 0.28 + energy * 0.08);
    color += midColor * midRail * (0.10 + mid * 0.24 + lyricPulse * 0.06);
    color += trebleColor * trebleArc * (0.10 + treble * 0.26 + lyricIntensity * 0.06);

    float diagonalCoord = dot(p, normalize(float2(1.0, 1.0)));
    float counterCoord = dot(p, normalize(float2(-1.0, 1.0)));
    float reverseDiagonal = dot(p, normalize(float2(1.0, -1.0)));
    float reverseCounter = dot(p, normalize(float2(1.0, 1.0)));

    float laneFog = exp(-abs(counterCoord) * 4.0) + exp(-abs(reverseCounter) * 4.2);
    color += midColor * laneFog * 0.06;

    float vanishing = pow(saturate(1.0 - abs(diagonalCoord + 0.18)), 1.8);
    color += trebleColor * vanishing * (0.04 + bass * 0.08);

    for (uint i = 0; i < kLyricLineCount; ++i) {
        VisualLyricLine line = uniforms.lines[i];
        float alpha = line.colorAndAlpha.a;
        if (alpha <= 0.001) {
            continue;
        }

        float basePos = line.layout.x;
        float lateral = line.layout.y;
        float width = line.layout.z;
        float density = line.layout.w;

        float glow = line.glow.x;
        float drift = line.glow.y;
        float pulse = line.glow.z;
        float thickness = line.glow.w;
        float direction = line.colorAndAlpha.w > 0.55 ? 1.0 : -1.0;
        float highlightMix = saturate((alpha - 0.72) / 0.28);

        float primaryFlow = (direction > 0.0 ? diagonalCoord : reverseDiagonal) - basePos + motionTime * drift;
        float primaryCounter = (direction > 0.0 ? counterCoord : reverseCounter) - lateral;
        float lineMask = smoothstep(width + 0.10, width * 0.12, abs(primaryCounter));

        float2 localBand = float2(primaryFlow + 0.06, primaryCounter);
        float band = giantLyricBand(localBand, thickness * 1.72, density * 0.30, pulse + float(i) * 0.37);
        float envelope = smoothstep(-0.38, 0.22, primaryFlow + 0.62);
        envelope *= 1.0 - smoothstep(1.34, 2.08, primaryFlow + 0.62);
        envelope = max(envelope, 0.16 + alpha * 0.06);
        float shimmer = 0.90 + 0.10 * sin(time * (0.92 + pulse * 0.22) + float(i) * 0.8 + primaryFlow * 5.2);
        float colorMix = float(i) / float(max(kLyricLineCount - 1, 1u));

        float3 baseLineColor = mix(theme, accent, 0.28 + colorMix * 0.36);
        baseLineColor = mix(baseLineColor, emotion, 0.20 + lyricProgress * 0.28);
        float3 highlightColor = mix(float3(1.0, 0.97, 0.92), accent, 0.45);
        float3 lineColor = mix(baseLineColor, highlightColor, highlightMix);
        lineColor *= 0.92 + pulse * 0.18 + lyricIntensity * 0.14 + highlightMix * 0.24;

        float glyph = band * lineMask * envelope * alpha;
        float halo = exp(-abs(primaryCounter) * (6.8 - glow * 1.4)) * envelope * alpha;
        float slabFlash = rectGlow(localBand, float2(0.0, 0.0), float2(0.82, thickness * 0.96), 0.08) * envelope * alpha;

        color += lineColor * slabFlash * (0.22 + glow * 0.10 + highlightMix * 0.18);
        color += lineColor * glyph * (1.46 + glow * 0.54 + highlightMix * 0.90) * shimmer;
        color += mix(lineColor, float3(1.0), 0.24 + highlightMix * 0.16) * halo * (0.30 + glow * 0.18 + treble * 0.08 + highlightMix * 0.12);
    }

    float highlightRail = exp(-abs(counterCoord + 0.04) * 3.8) * smoothstep(-1.02, 0.56, diagonalCoord + 0.64);
    float reverseRail = exp(-abs(reverseCounter - 0.04) * 3.9) * smoothstep(-1.02, 0.56, reverseDiagonal + 0.64);
    color += midColor * highlightRail * (0.18 + lyricPulse * 0.22 + mid * 0.22);
    color += trebleColor * reverseRail * (0.18 + lyricPulse * 0.20 + treble * 0.24);

    float bassPulse = smoothstep(0.04, 0.94, 1.0 - abs(p.y + 0.28)) * smoothstep(0.06, 1.0, bass);
    float midPulse = smoothstep(0.04, 0.90, 1.0 - abs(counterCoord - 0.08)) * smoothstep(0.06, 1.0, mid);
    float treblePulse = smoothstep(0.04, 0.86, 1.0 - abs(reverseDiagonal + 0.10)) * smoothstep(0.06, 1.0, treble);
    color += bassColor * bassPulse * 0.14;
    color += midColor * midPulse * 0.12;
    color += trebleColor * treblePulse * 0.12;

    float sparks = 0.0;
    for (int i = 0; i < 8; ++i) {
        float fi = float(i);
        float seed = fi * 18.37;
        float t = fract(vlHash(seed) + motionTime * (0.09 + vlHash(seed + 1.9) * 0.14));
        float2 sparkPos = float2(-0.62 + t * 1.45,
                                 -0.52 + fract(vlHash(seed + 4.1) + t * 0.72) * 1.08);
        sparkPos = float2(sparkPos.x + sparkPos.y * 0.16, sparkPos.y);
        float2 delta = p - sparkPos;
        float d = dot(delta, delta);
        sparks += exp(-d * (180.0 + vlHash(seed + 8.3) * 140.0));
    }
    color += mix(midColor, trebleColor, 0.28) * sparks * (0.04 + bass * 0.05 + lyricPulse * 0.06);

    float vignette = smoothstep(1.10, 0.12, length((uv - 0.5) * float2(0.92, 1.14)));
    color *= vignette;

    color = pow(max(color, 0.0), float3(0.92));
    return float4(color, 1.0);
}
