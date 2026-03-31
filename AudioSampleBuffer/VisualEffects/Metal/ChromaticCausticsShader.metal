//
//  ChromaticCausticsShader.metal
//  AudioSampleBuffer
//
//  Chromatic Caustics
//  以光绘轨迹、焦散纹理与音频驱动的棱镜扩散构造艺术化创意特效
//

#include "ShaderCommon.metal"

using namespace metal;

static inline float ccHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float ccNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = ccHash(i);
    float b = ccHash(i + float2(1.0, 0.0));
    float c = ccHash(i + float2(0.0, 1.0));
    float d = ccHash(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static inline float ribbonGlow(float2 p, float phase, float width, float frequency, float drift) {
    float bend = p.x * 0.36 - p.x * abs(p.x) * 0.95;
    float wave = bend +
                 sin(p.x * frequency + phase) * 0.10 +
                 sin(p.x * (frequency * 0.48) - phase * 1.2 + drift) * 0.05 +
                 sin((p.x + p.y) * 2.2 + phase * 0.6) * 0.025;
    float d = abs(p.y - wave);
    return exp(-(d * d) / max(width * width, 0.00002));
}

fragment float4 chromaticCausticsFragment(RasterizerData in [[stage_in]],
                                          constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr float TAU = 6.28318530718;

    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 p = uv - 0.5;

    float t = uniforms.time.x;
    float bass = clamp(uniforms.audioData[4].x * 1.85, 0.0, 1.25);
    float mid = clamp(uniforms.audioData[28].x * 1.65, 0.0, 1.20);
    float treble = clamp(uniforms.audioData[58].x * 1.90, 0.0, 1.25);
    float energy = clamp(bass * 0.42 + mid * 0.36 + treble * 0.22, 0.0, 1.25);

    int ribbonCount = clamp((int)round(uniforms.galaxyParams1.x), 2, 4);
    float prismSeparation = clamp(uniforms.galaxyParams1.y, 0.05, 0.24);
    float flowSpeed = clamp(uniforms.galaxyParams1.z, 0.35, 1.50);
    float glowIntensity = clamp(uniforms.galaxyParams1.w, 0.65, 1.80);

    float causticScale = clamp(uniforms.galaxyParams2.x, 0.70, 1.60);
    float interference = clamp(uniforms.galaxyParams2.y, 0.20, 1.30);
    float audioSensitivity = clamp(uniforms.galaxyParams2.z, 0.70, 1.80);
    float sparkleDensity = clamp(uniforms.galaxyParams2.w, 0.05, 0.65);

    float hueDrift = clamp(uniforms.galaxyParams3.x, 0.0, 0.35);
    float vignetteAmount = clamp(uniforms.galaxyParams3.y, 0.0, 0.55);
    float bassLift = clamp(uniforms.galaxyParams3.z, 0.0, 0.50);

    float radial = length(p);
    float2 dir = p / max(radial, 0.0001);

    float3 bgA = float3(0.030, 0.040, 0.110);
    float3 bgB = float3(0.120, 0.030, 0.170);
    float3 bgC = float3(0.060, 0.180, 0.260);
    float gradient = smoothstep(-0.55, 0.60, p.y + sin(t * 0.12) * 0.05);
    float3 color = mix(bgA, bgB, gradient);
    color = mix(color, bgC, smoothstep(0.18, 0.82, uv.x) * 0.30);

    float driftTime = t * (0.30 + flowSpeed * 0.48);
    float causticField = 0.0;
    for (int layer = 0; layer < 2; layer++) {
        float lf = (float)layer;
        float scale = (4.8 + lf * 2.7) * causticScale;
        float2 q = p * scale;
        q += float2(sin(driftTime * (0.8 + lf * 0.35) + q.y * 1.7),
                    cos(driftTime * (0.65 + lf * 0.28) - q.x * 1.4)) * (0.18 + lf * 0.05);
        float field = sin(q.x + sin(q.y * 1.35 + driftTime * 1.2)) *
                      sin(q.y * 1.22 - cos(q.x * 1.12 - driftTime * 0.9));
        field = pow(clamp(0.5 + 0.5 * field, 0.0, 1.0), 3.0 + lf);
        causticField += field * (0.70 - lf * 0.18);
    }
    causticField *= 0.62 + energy * 0.34;

    float moire = sin((p.x + p.y) * 36.0 * interference + driftTime * 2.2) *
                  sin((p.x - p.y) * 31.0 * interference - driftTime * 1.7);
    moire = 0.5 + 0.5 * moire;
    moire = pow(moire, 4.0);

    float3 causticColor = mix(float3(0.36, 0.92, 1.05), float3(1.00, 0.46, 0.82), 0.42 + 0.18 * sin(driftTime));
    color += causticColor * causticField * (0.16 + glowIntensity * 0.10);
    color += float3(1.0, 0.92, 0.62) * moire * (0.03 + treble * 0.12);

    float ribbonEnergy = clamp((energy + bass * bassLift) * audioSensitivity, 0.0, 1.6);
    float baseLayerFade = 1.0;
    float midLayerFade = smoothstep(0.08, 0.24, mid);
    float trebleLayerFade = smoothstep(0.10, 0.28, treble);
    float climaxLayerFade = smoothstep(0.22, 0.46, ribbonEnergy);

    for (int i = 0; i < 4; i++) {
        if (i >= ribbonCount) continue;
        float fi = (float)i;
        float lane = fi - (float)(ribbonCount - 1) * 0.5;
        float laneOffset = lane * prismSeparation;
        float phase = driftTime * (1.2 + fi * 0.24) + lane * 1.6;
        float width = 0.028 + 0.008 * fi;
        float2 rp = p;
        rp.y -= laneOffset;

        float ribbonBase = ribbonGlow(rp, phase, width, 7.0 + fi * 1.2, driftTime * (0.6 + fi * 0.1));
        float ribbonMid = ribbonGlow(rp, phase + 0.22, width * 0.78, 9.4 + fi * 1.35, driftTime * 0.82);
        float ribbonCore = ribbonGlow(rp, phase + 0.12, width * 0.42, 8.2 + fi, driftTime);

        float hue = fract(0.56 + fi * 0.11 + hueDrift * sin(driftTime * 0.4 + fi));
        float3 prism = hsv2rgb(float3(hue, 0.62, 1.0));
        float3 ribbonColor = mix(prism, float3(1.0, 0.92, 0.70), 0.18 + bass * 0.12);
        float3 ribbonAccent = mix(ribbonColor, float3(0.60, 0.96, 1.0), 0.42 + 0.18 * fi);

        float sweep = smoothstep(0.0, 0.9, 1.0 - abs(rp.x) * 0.9);
        color += ribbonColor * ribbonBase * sweep * (0.12 + baseLayerFade * 0.08 + bass * 0.10);
        color += ribbonAccent * ribbonMid * sweep * (0.05 + midLayerFade * 0.18 + mid * 0.08);
        color += float3(1.0) * ribbonCore * (0.02 + trebleLayerFade * 0.07 + climaxLayerFade * 0.10 + glowIntensity * 0.04);
    }

    // 中频驱动的扇面层：只扩展形态，不改变主弧线运动
    float fanLayer = 0.0;
    float fanSweep = 0.0;
    for (int i = 0; i < 3; i++) {
        float fi = (float)i;
        float fanPhase = driftTime * (0.52 + fi * 0.12) + fi * 2.1;
        float2 axis = normalize(float2(cos(fanPhase), sin(fanPhase * 0.82 + fi * 0.7)));
        float projection = dot(p, axis);
        float orth = dot(p, float2(-axis.y, axis.x));
        float sheet = exp(-(orth * orth) / (0.006 + fi * 0.003));
        float reach = smoothstep(-0.08, 0.55 + fi * 0.14, projection) * (1.0 - smoothstep(0.30 + fi * 0.12, 0.78 + fi * 0.15, radial));
        fanLayer += sheet * reach;
        fanSweep += exp(-pow(radial - (0.18 + fi * 0.08 + 0.03 * sin(fanPhase)), 2.0) / (0.006 + fi * 0.002)) * sheet;
    }
    float3 fanColor = mix(float3(0.42, 0.90, 1.0), float3(1.0, 0.56, 0.82), 0.35 + 0.25 * sin(driftTime * 0.6));
    color += fanColor * fanLayer * (0.02 + midLayerFade * 0.16);
    color += float3(1.0, 0.86, 0.70) * fanSweep * (0.01 + trebleLayerFade * 0.09);

    float ringWave = sin(dir.x * (5.2 + interference * 1.8) +
                         dir.y * (3.8 + interference * 1.4) -
                         driftTime * (1.0 + flowSpeed * 0.35));
    float halo = exp(-radial * (6.5 - bass * 1.8)) * (0.12 + bass * 0.18);
    float ring = exp(-pow(radial - (0.20 + 0.05 * ringWave), 2.0) / 0.010);
    color += float3(1.0, 0.78, 0.54) * halo;
    color += mix(float3(0.34, 0.88, 1.0), float3(0.96, 0.54, 0.84), 0.5 + 0.5 * dir.y) *
             ring * (0.06 + mid * 0.18);

    // 外围脉冲环：高潮时才显著解锁，增强音乐段落差异
    float outerPulseA = exp(-pow(radial - (0.33 + 0.02 * sin(driftTime * 1.4)), 2.0) / 0.0045);
    float outerPulseB = exp(-pow(radial - (0.45 + 0.03 * sin(driftTime * 0.9 + 1.2)), 2.0) / 0.0065);
    float pulseGate = 0.4 + 0.6 * pow(saturate(0.5 + 0.5 * sin(dir.x * 6.0 - dir.y * 5.0 + driftTime * 1.1)), 2.0);
    float3 pulseColor = mix(float3(0.48, 0.96, 1.0), float3(1.0, 0.66, 0.78), 0.55 + 0.20 * sin(driftTime));
    color += pulseColor * outerPulseA * pulseGate * (0.01 + climaxLayerFade * 0.16 + bass * 0.04);
    color += float3(1.0, 0.92, 0.80) * outerPulseB * (0.005 + climaxLayerFade * 0.08);

    float2 sparkleUV = uv * (8.0 + sparkleDensity * 10.0) + float2(driftTime * 0.12, -driftTime * 0.07);
    float2 sparkleCell = floor(sparkleUV);
    float2 sparkleLocal = fract(sparkleUV) - 0.5;
    float sparkleSeed = ccHash(sparkleCell);
    if (sparkleSeed > (0.92 - sparkleDensity * 0.18)) {
        float2 sparkleOffset = float2(ccHash(sparkleCell + 1.7), ccHash(sparkleCell + 4.2)) - 0.5;
        float2 sd = sparkleLocal - sparkleOffset * 0.75;
        float sparkle = exp(-dot(sd, sd) * 36.0);
        float twinkle = 0.55 + 0.45 * sin(t * 5.0 + sparkleSeed * TAU + treble * 3.0);
        float3 sparkleColor = mix(float3(1.0, 0.92, 0.72), float3(0.62, 0.95, 1.0), sparkleSeed);
        color += sparkleColor * sparkle * twinkle * (0.06 + treble * 0.12);
    }

    float haze = ccNoise(uv * (2.4 + causticScale) + float2(driftTime * 0.08, -driftTime * 0.05));
    color += float3(0.08, 0.04, 0.12) * haze * (0.10 + 0.08 * energy);

    float vignette = 1.0 - smoothstep(0.34, 0.88, radial);
    color *= 1.0 - vignetteAmount * (1.0 - vignette);

    color = color / (color + 0.88);
    return float4(color, 1.0);
}
