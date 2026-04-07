//
//  NeuralResonanceShader.metal
//  AudioSampleBuffer
//
//  Neural Resonance - Optimized
//  目标：低负载 + 音乐分区触发 + 单次脉冲感 + 远端LLM主题色
//

#include "ShaderCommon.metal"

using namespace metal;

static inline float nrHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static inline float nrNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = nrHash(i);
    float b = nrHash(i + float2(1.0, 0.0));
    float c = nrHash(i + float2(0.0, 1.0));
    float d = nrHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static inline float segGlow(float2 p, float2 a, float2 b, float width) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    float2 d = pa - ba * h;
    return exp(-dot(d, d) / max(width * width, 0.00001));
}

static inline float currentPulse(float h, float phase, float width) {
    float x = h - phase;
    return exp(-(x * x) / max(width * width, 0.00001));
}

fragment float4 neuralResonanceFragment(RasterizerData in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 p = uv - 0.5;
    float t = uniforms.time.x;
    float tMotion = uniforms.time.z; // 仅音乐活跃时由CPU推进

    // 轻量音频能量
    float bass = clamp(uniforms.audioData[4].x * 1.8, 0.0, 1.2);
    float mid = clamp(uniforms.audioData[28].x * 1.6, 0.0, 1.2);
    float treb = clamp(uniforms.audioData[62].x * 1.7, 0.0, 1.2);
    float energy = clamp(bass * 0.44 + mid * 0.35 + treb * 0.21, 0.0, 1.25);
    float activity = clamp(0.24 + energy * 0.92, 0.0, 1.0);

    // 远端 LLM 主题色（由 CPU 注入）
    float llmThemeEnabled = uniforms.cyberpunkFrequencyControls.w;
    float3 llmTheme = clamp(uniforms.cyberpunkBackgroundParams.rgb, 0.0, 1.0);
    float paletteBoost = clamp(uniforms.cyberpunkBackgroundParams.w, 0.75, 1.35);

    float3 baseTheme = float3(0.58, 0.68, 1.00);
    float3 theme = mix(baseTheme, llmTheme, llmThemeEnabled);

    // 背景呼吸：增强可见度（音乐联动更明显）
    float breatheBg = 0.82 + 0.42 * sin(t * 1.05 + energy * 4.6);
    float flickerBg = 0.94 + 0.06 * sin(t * 3.6 + bass * 5.2 + mid * 4.0);

    // 背景：平滑渐变，消除分层感
    float3 bgTop = mix(float3(0.038, 0.058, 0.130), theme * float3(0.10, 0.12, 0.16), 0.88);
    float3 bgBottom = mix(float3(0.014, 0.020, 0.072), theme * float3(0.028, 0.032, 0.048), 0.82);
    float3 color = mix(bgBottom, bgTop, uv.y); // 线性，无 smoothstep，无分层

    float breath = (0.94 + 0.08 * sin(t * 1.15 + energy * 4.0)) * breatheBg;

    float2 c1 = float2(0.30 + sin(t * 0.08) * 0.035, 0.78 + cos(t * 0.10) * 0.028) - 0.5;
    float2 c2 = float2(0.80 + cos(t * 0.07) * 0.045, 0.25 + sin(t * 0.08) * 0.035) - 0.5;
    float2 d1 = p - c1;
    float2 d2v = p - c2;
    float o1 = exp(-dot(d1, d1) / 0.17);
    float o2 = exp(-dot(d2v, d2v) / 0.12);
    color += theme * float3(0.52, 0.78, 1.06) * o1 * (0.22 + 0.20 * activity) * breath * flickerBg * paletteBoost;
    color += theme.bgr * float3(0.44, 0.34, 0.86) * o2 * (0.17 + 0.16 * activity) * breath * flickerBg * paletteBoost;

    float haze = nrNoise(uv * 1.9 + float2(t * 0.025, -t * 0.018));
    color += float3(0.016, 0.022, 0.040) * haze * (0.14 + 0.04 * activity);

    // 小图例式提示（左上角）：让用户理解"音乐驱动"
    float2 legendCenter = float2(-0.40, 0.36);
    float2 lp = p - legendCenter;

    float panel = smoothstep(0.13, 0.09, length(lp));
    color += float3(0.03, 0.05, 0.10) * panel * 0.32;

    // 三个频段点：低/中/高
    float bassDot = exp(-dot(lp - float2(-0.055, 0.018), lp - float2(-0.055, 0.018)) / 0.00038);
    float midDot  = exp(-dot(lp - float2( 0.000, 0.018), lp - float2( 0.000, 0.018)) / 0.00038);
    float treDot  = exp(-dot(lp - float2( 0.055, 0.018), lp - float2( 0.055, 0.018)) / 0.00038);

    color += theme * 0.50 * bassDot * (0.20 + 0.75 * bass) * paletteBoost;
    color += mix(theme, theme.bgr, 0.42) * 0.58 * midDot  * (0.20 + 0.75 * mid) * paletteBoost;
    color += mix(theme, float3(1.0), 0.38) * 0.72 * treDot  * (0.20 + 0.75 * treb) * paletteBoost;

    // 一条示意脉冲线（单向流动）
    float lineMask = exp(-pow(lp.y + 0.032, 2.0) / 0.00011) * smoothstep(-0.080, -0.020, lp.x) * (1.0 - smoothstep(0.042, 0.090, lp.x));
    float legendPhase = fract(tMotion * 0.95);
    float pulseOnLine = exp(-pow(lp.x - (-0.075 + legendPhase * 0.14), 2.0) / 0.00014) * exp(-pow(lp.y + 0.032, 2.0) / 0.00012);
    color += mix(theme, float3(0.82, 0.90, 1.0), 0.45) * lineMask * 0.28;
    color += mix(float3(0.96, 0.98, 1.0), theme, 0.28) * pulseOnLine * (0.25 + 0.55 * activity);

    // 背景板神经节点（低成本）：缓慢随机移动 + 音乐闪烁
    // early-out 阈值：halo exp(-d2/0.0048) < 0.005 时 d2 > 0.025，直接跳过
    const float bgNodeMaxD2 = 0.028;
    const int bgNodeCount = 8;
    for (int i = 0; i < bgNodeCount; i++) {
        float fi = float(i);
        float sx = nrHash(float2(fi * 1.732 + 0.3, fi * 2.618 + 1.9));
        float sy = nrHash(float2(fi * 3.302 + 2.1, fi * 1.273 + 4.7));
        float sd = nrHash(float2(fi * 2.449 + 6.3, fi * 0.809 + 3.1));

        float2 base = float2(sx * 0.94 - 0.47, sy * 0.94 - 0.47);
        float2 drift = float2(
            sin(t * (0.08 + sd * 0.06) + fi * 2.1),
            cos(t * (0.07 + sd * 0.05) + fi * 1.7)
        ) * 0.035;

        float2 bn = base + drift;
        float2 db = p - bn;
        float d2b = dot(db, db);

        // 距离 early-out：超出 halo 可见范围直接跳过
        if (d2b > bgNodeMaxD2) continue;

        float band = (i % 3 == 0) ? bass : ((i % 3 == 1) ? mid : treb);
        float blink = 0.72 + 0.28 * sin(t * (2.0 + sd) + band * 6.0 + fi);

        float bCore = exp(-d2b / 0.00042);
        float bHalo = exp(-d2b / 0.0048);
        color += mix(theme, float3(0.90, 0.95, 1.0), 0.28) * (0.10 * bCore + 0.05 * bHalo) * blink * (0.65 + 0.35 * activity) * paletteBoost;
    }

    // 节点：随机全屏游走（可跨象限）+ 生命周期出现/消失
    const int nodeCount = 10;
    float2 nodes[nodeCount];
    float lives[nodeCount];

    float3 nodeC = mix(theme, float3(0.95, 0.98, 1.0), 0.30);
    float3 linkC = mix(theme, theme.bgr, 0.22);
    float3 pulseC = mix(float3(0.98, 1.00, 1.00), theme, 0.24);

    // 音乐很弱时可关闭节点大幅运动（避免空段乱动）
    float nodeMotionOn = step(0.10, activity);

    // early-out 阈值：halo exp(-d2/0.0032) < 0.005 时 d2 > 0.017
    const float nodeMaxD2 = 0.020;

    for (int i = 0; i < nodeCount; i++) {
        float fi = float(i);
        float seedA = nrHash(float2(fi * 1.618 + 0.5, fi * 2.713 + 3.7));
        float seedB = nrHash(float2(fi * 3.141 + 1.2, fi * 1.414 + 7.3));
        float seedC = nrHash(float2(fi * 2.236 + 5.1, fi * 0.577 + 2.9));

        float2 base = float2(seedA * 0.92 - 0.46, seedB * 0.92 - 0.46);

        float walkX = sin(t * (0.24 + seedA * 0.20) + seedC * 6.28318) * 0.18
                    + sin(t * (0.13 + seedB * 0.12) + fi * 1.2) * 0.09;
        float walkY = cos(t * (0.22 + seedB * 0.18) + seedA * 6.28318) * 0.18
                    + cos(t * (0.12 + seedC * 0.11) + fi * 1.6) * 0.09;

        float2 moved = base + float2(walkX, walkY) * nodeMotionOn;
        nodes[i] = clamp(moved, float2(-0.48, -0.48), float2(0.48, 0.48));

        float lifePhase = fract(t * (0.052 + seedA * 0.020) + seedB * 2.2);
        float fadeIn = smoothstep(0.08, 0.26, lifePhase);
        float fadeOut = 1.0 - smoothstep(0.70, 0.94, lifePhase);
        lives[i] = 0.12 + 0.88 * (fadeIn * fadeOut);

        float band = (i < 4) ? bass : ((i < 8) ? mid : treb);
        float twinkle = 0.78 + 0.22 * sin(t * (2.2 + seedA * 0.9) + fi * 1.31 + energy * 3.2);

        float2 d = p - nodes[i];
        float d2 = dot(d, d);

        // 距离 early-out：超出 halo 可见范围直接跳过（连线循环仍需 nodes[i]，故继续存储）
        if (d2 <= nodeMaxD2) {
            float core = exp(-d2 / 0.00024);
            float halo = exp(-d2 / 0.0032);
            color += nodeC * (0.32 * core + 0.13 * halo) * twinkle * (0.78 + 0.48 * band) * lives[i];
        }
    }

    // 连线：树杈算法（parent-child），长度超阈值断开
    float linkRange = 0.35 + 0.06 * activity;
    float linkWidth = 0.00215 + 0.00065 * activity;
    // segGlow 的可见边界：exp(-d^2/w^2) < 0.005 => d > w*sqrt(-ln(0.005)) ≈ w*2.32
    // 用 linkWidth_max*2.5 作为像素到线段端点的 AABB 快速剔除距离
    float linkCullDist = linkWidth * 3.2;
    float linkCullDist2 = linkCullDist * linkCullDist;

    for (int i = 0; i < nodeCount; i++) {
        int parent = (i == 0) ? -1 : (i - 1);
        int branch = (i + 4) % nodeCount;

        float band = (i < 4) ? bass : ((i < 8) ? mid : treb);
        float trigger = max(0.14 * activity, smoothstep(0.08, 0.24, band));

        // parent edge（主干）
        if (parent >= 0) {
            float2 a = nodes[i];
            float2 b = nodes[parent];
            float distAB = length(a - b);
            if (distAB < linkRange) {
                // AABB 快速剔除：像素到线段包围盒的最小距离
                float2 minAB = min(a, b) - linkCullDist;
                float2 maxAB = max(a, b) + linkCullDist;
                if (p.x >= minAB.x && p.x <= maxAB.x && p.y >= minAB.y && p.y <= maxAB.y) {
                    float nearStrength = 1.0 - smoothstep(linkRange * 0.62, linkRange, distAB);
                    float line = segGlow(p, a, b, linkWidth);
                    float lifeMix = lives[i] * lives[parent];

                    color += linkC * line * (0.13 + 0.34 * nearStrength) * lifeMix;

                    float2 pa = p - a;
                    float2 ba = b - a;
                    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);

                    float seed = nrHash(float2(float(i) * 0.91, float(parent) * 1.27));
                    float speed = 0.20 + 0.82 * trigger;
                    float phase = fract(tMotion * speed + seed);
                    float pulse = currentPulse(h, phase, 0.056);

                    color += pulseC * pulse * line * (0.24 + 0.52 * nearStrength) * trigger * lifeMix;
                }
            }
        }

        // branch edge（树杈）
        {
            float2 a = nodes[i];
            float2 b = nodes[branch];
            float distAB = length(a - b);
            if (distAB < linkRange * 0.92) {
                float2 minAB = min(a, b) - linkCullDist;
                float2 maxAB = max(a, b) + linkCullDist;
                if (p.x >= minAB.x && p.x <= maxAB.x && p.y >= minAB.y && p.y <= maxAB.y) {
                    float nearStrength = 1.0 - smoothstep(linkRange * 0.58, linkRange * 0.92, distAB);
                    float line = segGlow(p, a, b, linkWidth * 0.82);
                    float lifeMix = lives[i] * lives[branch];

                    color += linkC * line * (0.06 + 0.14 * nearStrength) * lifeMix;

                    float2 pa = p - a;
                    float2 ba = b - a;
                    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);

                    float seed = nrHash(float2(float(i) * 1.07, float(branch) * 1.19));
                    float speed = 0.16 + 0.58 * trigger;
                    float phase = fract(tMotion * speed + seed);
                    float pulse = currentPulse(h, phase, 0.060);

                    color += pulseC * pulse * line * (0.07 + 0.16 * nearStrength) * trigger * lifeMix;
                }
            }
        }
    }

    float vignette = 1.0 - smoothstep(0.36, 0.90, length(p));
    color *= (0.88 + 0.12 * vignette);
    color = color / (color + 0.95);

    return float4(color, 1.0);
}
