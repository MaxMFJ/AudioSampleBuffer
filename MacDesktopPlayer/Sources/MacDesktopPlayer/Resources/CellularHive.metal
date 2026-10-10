#include <metal_stdlib>
using namespace metal;

struct CellularHiveVertexOut { float4 position [[position]]; float2 uv; };
struct CellularHiveAudio { float time; float bass; float mid; float treble; float aspectRatio; float guitar; float piano; float drums; float playbackTime; float electricGuitarConfidence; };
struct CellularHiveMood {
    float4 atmosphere, volumetricBeam, topLightArray, laserFanBlue, laserFanGreen;
    float4 rotatingBeam, rotatingBeamExtra, edgeLight, coronaFilaments, pulseRing;
};
struct CellularHiveGuitarUniforms {
    float4 wave0, wave1, wave2, wave3, wave4, wave5, wave6, wave7;
    float4 color0, color1, color2, color3;
};

static inline float cellularHiveHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

vertex CellularHiveVertexOut cellularHiveDesktopVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 points[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    CellularHiveVertexOut out;
    out.position = float4(points[vertexID], 0.0, 1.0);
    out.uv = points[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 cellularHiveDesktopFragment(
    CellularHiveVertexOut in [[stage_in]],
    constant CellularHiveAudio &audio [[buffer(0)]],
    constant CellularHiveMood &mood [[buffer(1)]],
    constant CellularHiveGuitarUniforms &guitarWaves [[buffer(2)]]) {
    constexpr float tau = 6.28318530718;
    float t = audio.time;
    float2 p = (in.uv - 0.5) * float2(max(audio.aspectRatio, 0.65), 1.0);
    float r = length(p);
    float angle = atan2(p.y, p.x);
    float bass = saturate(audio.bass);
    float mid = saturate(audio.mid);
    float high = saturate(audio.treble);
    float beat = saturate(audio.drums);
    float guitar = saturate(audio.guitar);
    float energy = saturate((bass + mid + high) * 0.42);
    float core = 0.285 + bass * 0.022 + beat * 0.014;
    float organic = 0.012 * sin(angle * 3.0 + t * 0.14) + 0.007 * sin(angle * 5.0 - t * 0.10);
    float wallRadius = r - core - organic;
    float depth = -log(max(wallRadius, 0.003)) * 2.15;
    float wall = smoothstep(0.0, 0.028, wallRadius);
    float inner = (1.0 - smoothstep(core - 0.05, core + 0.012, r)) * smoothstep(core * 0.28, core * 0.9, r);
    float cells = 19.0;
    float2 q = float2(angle / tau * cells + depth * 0.52 + t * 0.085,
                      depth * 0.70 + t * 0.31);
    q += float2(0.18 * sin(q.y * 1.8), 0.15 * sin(angle * 6.0 + depth));

    float2 baseCell = floor(q - 0.5);
    float poreDistance = 10.0;
    float poreSignal = 0.0;
    float poreSeed = 0.0;
    for (int y = 0; y <= 1; ++y) {
        for (int x = 0; x <= 1; ++x) {
            float2 id = baseCell + float2(x, y);
            float2 wrapped = float2(id.x - floor(id.x / cells) * cells, id.y);
            float seed = cellularHiveHash(wrapped);
            float jitter = cellularHiveHash(wrapped + 19.3);
            float signal = saturate((bass * 0.30 + mid * 0.24 + high * 0.20 + beat * 0.16 + guitar * 0.28) * (0.65 + seed * 0.7));
            float phase = t * (0.46 + seed * 0.34) + seed * tau;
            float2 center = id + 0.5 + float2(seed - 0.5, jitter - 0.5) * 0.22;
            center += signal * float2(sin(phase), cos(phase * 0.83)) * 0.12;
            float2 local = q - center;
            float twist = (seed - 0.5) * 0.42 + sin(phase) * signal * 0.95;
            float cs = cos(twist), sn = sin(twist);
            local = float2(cs * local.x - sn * local.y, sn * local.x + cs * local.y);
            local += signal * 0.12 * float2(sin(local.y * 5.0 + phase), cos(local.x * 4.0 - phase));
            local.x += ((seed - 0.5) * 0.62 + signal * sin(phase * 1.17) * 0.58) * local.y;
            float radius = clamp(0.31 + jitter * 0.07 + signal * 0.15 + beat * 0.02, 0.30, 0.48);
            float2 stretch = float2(1.0 + signal * sin(phase) * 0.25, 0.88 + seed * 0.18 - signal * cos(phase) * 0.20);
            float d = length(local * stretch) - radius;
            if (d < poreDistance) { poreDistance = d; poreSignal = signal; poreSeed = seed; }
        }
    }

    float aa = max(fwidth(poreDistance), 0.008);
    float membrane = smoothstep(-aa, aa, poreDistance);
    float lip = exp(-abs(poreDistance) * 32.0);
    float softGlow = exp(-abs(poreDistance) * 9.0);
    float detail = 1.0 - smoothstep(0.35, 1.2, fwidth(depth));
    float ridge = 0.68 + 0.32 * sin(depth * 2.5 - t * 0.35 + angle * 2.0);
    float nearLight = smoothstep(0.0, 0.55, wallRadius);
    float3 theme = mix(mood.atmosphere.rgb, mood.volumetricBeam.rgb, 0.38);
    float3 accent = mix(mood.coronaFilaments.rgb, mood.pulseRing.rgb, 0.30);
    float3 highlight = mix(theme, float3(1.0), 0.22);
    float3 deep = mix(float3(0.003, 0.008, 0.026), theme * 0.20, 0.74);
    float3 tint = mix(theme, deep, nearLight * 0.72);
    float3 color = float3(0.001, 0.003, 0.012) + deep * 0.10;
    float3 waveTrailColor = float3(0.0);
    float waveTrailWeight = 0.0;
    for (int waveIndex = 0; waveIndex < 8; ++waveIndex) {
        float4 wave;
        if (waveIndex == 0) wave = guitarWaves.wave0;
        else if (waveIndex == 1) wave = guitarWaves.wave1;
        else if (waveIndex == 2) wave = guitarWaves.wave2;
        else if (waveIndex == 3) wave = guitarWaves.wave3;
        else if (waveIndex == 4) wave = guitarWaves.wave4;
        else if (waveIndex == 5) wave = guitarWaves.wave5;
        else if (waveIndex == 6) wave = guitarWaves.wave6;
        else wave = guitarWaves.wave7;
        float waveAge = max(wave.x, 0.0);
        float waveStrength = saturate(wave.y);
        if (waveStrength <= 0.001 || waveAge >= 2.8) continue;
        float waveRadius = core + waveAge * 0.38;
        float waveReached = 1.0 - smoothstep(-0.012, 0.028, r - waveRadius);
        float lifeFade = 1.0 - smoothstep(2.0, 2.8, waveAge);
        float confidence = smoothstep(0.12, 0.80, waveStrength);
        float opacity = (0.38 + confidence * 0.62) * exp(-waveAge * 0.22) * lifeFade;
        int paletteIndex = clamp(int(wave.z + 0.5), 0, 3);
        float3 waveColor = paletteIndex == 0 ? guitarWaves.color0.rgb
                         : paletteIndex == 1 ? guitarWaves.color1.rgb
                         : paletteIndex == 2 ? guitarWaves.color2.rgb
                         : guitarWaves.color3.rgb;
        waveColor = mix(waveColor, float3(1.0), 0.10);
        float trailWeight = waveReached * opacity;
        waveTrailColor += waveColor * trailWeight;
        waveTrailWeight += trailWeight;
    }
    color += wall * membrane * tint * (0.34 + ridge * 0.42 + bass * 0.20);
    color += wall * detail * lip * highlight * (0.12 + poreSignal * 0.60 + beat * 0.24 + guitar * 0.16);
    color += wall * detail * softGlow * tint * (0.07 + energy * 0.13);
    color += wall * detail * softGlow * mood.volumetricBeam.rgb * guitar * 0.32;
    color += wall * detail * lip * mood.topLightArray.rgb * mid * 0.18;
    color += wall * detail * lip * mood.pulseRing.rgb * beat * 0.24;
    // Desktop-density micro grains assemble along the cell membranes.
    float2 grainUV = q * float2(2.7, 3.4);
    float2 grainID = floor(grainUV);
    float grainSeed = cellularHiveHash(grainID + 31.7);
    float grainSeed2 = cellularHiveHash(grainID + 73.1);
    float assembly = smoothstep(0.10, 0.78, fract(t * 0.19 + grainSeed - depth * 0.055));
    float2 grainCenter = 0.5 + float2(grainSeed - 0.5, grainSeed2 - 0.5) * 0.62;
    grainCenter.x += (1.0 - assembly) * sin(t * 1.7 + grainSeed * 27.0) * 0.42;
    grainCenter.y += (1.0 - assembly) * fract(t * 0.38 + grainSeed2) * 0.46;
    float2 grainLocal = fract(grainUV) - grainCenter;
    float flyingGrain = exp(-(grainLocal.x * grainLocal.x * 150.0 + grainLocal.y * grainLocal.y * 34.0));
    float settledGrain = exp(-dot(grainLocal, grainLocal) * 230.0);
    float grain = mix(flyingGrain, settledGrain, assembly);
    float edgeArrival = exp(-abs(poreDistance) * mix(6.0, 34.0, assembly));
    color += wall * detail * grain * (0.12 + energy * 0.35 + assembly * edgeArrival * 0.95) * highlight;

    // Fine membrane dust, high-frequency streaks and percussion spokes.
    float2 speckUV = q * float2(6.0, 8.0);
    float2 speckID = floor(speckUV);
    float speckSeed = cellularHiveHash(speckID + poreSeed * 41.0);
    float2 speckDelta = fract(speckUV) - (float2(cellularHiveHash(speckID + 3.1), cellularHiveHash(speckID + 9.7)) * 0.5 + 0.25);
    float speck = exp(-dot(speckDelta, speckDelta) * 190.0) * step(0.66 - high * 0.16, speckSeed);
    color += wall * membrane * speck * tint * (0.025 + high * 0.12);
    float spokes = pow(0.5 + 0.5 * cos(angle * 38.0 + t * 0.4 + sin(r * 13.0)), 30.0);
    float corona = exp(-abs(r - core) * 22.0);
    color += accent * spokes * corona * (high * 0.42 + beat * 0.62 + guitar * 0.20);

    float throat = exp(-pow(wallRadius / 0.022, 2.0));
    color += throat * theme * (0.20 + bass * 0.42);
    float ringPhase = fract(t * 0.24);
    float ringRadius = core + ringPhase * 0.48;
    float ring = exp(-pow((r - ringRadius) / (0.010 + beat * 0.008), 2.0));
    color += highlight * ring * (0.08 + beat * 0.72) * (1.0 - ringPhase);
    float burstRays = pow(0.5 + 0.5 * cos(angle * 28.0 - t * 1.25 + sin(r * 18.0) * 0.7), 18.0);
    color += mix(theme, highlight, 0.48) * burstRays * inner * (0.04 + guitar * 0.18 + beat * 0.15);

    // Two parallax star fields remain visible through the aperture and pores.
    float hole = max(1.0 - wall, wall * (1.0 - membrane));
    float2 dustUV = (p + float2(t * 0.0008, -t * 0.0005)) * 105.0;
    float2 dustID = floor(dustUV);
    float dustSeed = cellularHiveHash(dustID + 7.4);
    float2 dustLocal = fract(dustUV) - 0.5;
    float dust = exp(-dot(dustLocal, dustLocal) * 160.0) * step(0.936, dustSeed);
    float twinkle = 0.55 + 0.45 * sin(t * 1.3 + dustSeed * 60.0);
    float2 farUV = (p - float2(t * 0.00025, t * 0.0003)) * 57.0;
    float2 farLocal = fract(farUV) - 0.5;
    float farStar = exp(-dot(farLocal, farLocal) * 95.0) * step(0.965, cellularHiveHash(floor(farUV) + 91.2));
    color += hole * (dust * twinkle + farStar * 0.42) * mix(float3(0.72, 0.86, 1.0), highlight, 0.32) * (0.12 + high * 0.58);

    // Match iOS: recolor the finished honeycomb membrane and pore rims after
    // all other light layers, while leaving the dark openings intact.
    if (waveTrailWeight > 0.0001) {
        float3 waveHue = waveTrailColor / waveTrailWeight;
        float hiveMask = saturate(wall * (membrane + lip * 0.72)
                                  + inner * 0.90 + throat * 0.70);
        float hueOpacity = hiveMask * saturate(waveTrailWeight);
        float surfaceLight = max(max(color.r, color.g), color.b);
        color = mix(color, waveHue * surfaceLight, hueOpacity);
    }

    color *= 1.0 - 0.28 * smoothstep(0.50, 1.35, r);
    color = 1.0 - exp(-color * 1.55);
    return float4(saturate(color), 1.0);
}
