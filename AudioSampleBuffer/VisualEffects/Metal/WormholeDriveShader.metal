//
// WormholeDriveShader.metal
// AudioSampleBuffer
//
// Wormhole Transit
// 深空虫洞隧道 + 音频驱动星尘柱状冲刺
//

#include "ShaderCommon.metal"
using namespace metal;

static inline float whHash(float n) {
    return fract(sin(n) * 43758.5453123);
}

static inline float whHash2(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453123);
}

static inline float whNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);

    float a = whHash2(i);
    float b = whHash2(i + float2(1.0, 0.0));
    float c = whHash2(i + float2(0.0, 1.0));
    float d = whHash2(i + float2(1.0, 1.0));

    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

static inline float capsuleGlow(float2 p, float2 a, float2 b, float radius) {
    float2 pa = p - a;
    float2 ba = b - a;
    float h = clamp(dot(pa, ba) / max(dot(ba, ba), 0.0001), 0.0, 1.0);
    float2 d = pa - ba * h;
    float r2 = max(radius * radius, 0.00001);
    return exp(-dot(d, d) / r2);
}

static inline float ringGlow(float value, float center, float width) {
    float w = max(width, 0.0001);
    float delta = (value - center) / w;
    return exp(-(delta * delta));
}

fragment float4 wormholeDriveFragment(RasterizerData in [[stage_in]],
                                      constant Uniforms &uniforms [[buffer(0)]]) {
    constexpr float TAU = 6.28318530718;

    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 p = uv - 0.5;
    float r = length(p);
    float ang = atan2(p.y, p.x);

    float motionTime = uniforms.time.z;
    float slowTime = uniforms.time.x;

    float musicActive = clamp(uniforms.cyberpunkControls.x, 0.0, 1.0);
    float activity = clamp(uniforms.cyberpunkControls.y, 0.0, 1.0);
    float bass = clamp(uniforms.cyberpunkControls.z, 0.0, 1.5);
    float mid = clamp(uniforms.cyberpunkControls.w, 0.0, 1.5);
    float treble = clamp(uniforms.cyberpunkFrequencyControls.x, 0.0, 1.5);
    float energy = clamp(uniforms.cyberpunkFrequencyControls.y, 0.0, 1.5);

    float llmThemeEnabled = clamp(uniforms.cyberpunkFrequencyControls.w, 0.0, 1.0);
    float3 llmTheme = clamp(uniforms.cyberpunkBackgroundParams.rgb, 0.0, 1.0);
    float3 baseTheme = float3(0.42, 0.70, 1.00);
    float3 theme = mix(baseTheme, llmTheme, llmThemeEnabled);
    float3 coolColor = mix(theme, float3(0.48, 0.94, 1.16), 0.35 + treble * 0.12);
    float3 hotColor = mix(float3(1.06, 0.78, 0.95), float3(1.08, 0.86, 0.58), 0.45 + bass * 0.10);
    float3 mistColor = mix(theme * float3(0.18, 0.28, 0.54), hotColor * float3(0.18, 0.10, 0.18), 0.32);
    float paletteBoost = clamp(uniforms.cyberpunkBackgroundParams.w, 0.75, 1.35);

    int barCount = clamp((int)uniforms.galaxyParams1.x, 6, 10);
    int starLaneCount = clamp((int)uniforms.galaxyParams1.y, 10, 18);
    float tunnelRadius = clamp(uniforms.galaxyParams1.z, 0.30, 0.48);
    float flashIntensity = clamp(uniforms.galaxyParams1.w, 0.70, 1.60);

    float travelSpeed = clamp(uniforms.galaxyParams2.x, 0.55, 1.50);
    float swirlAmount = clamp(uniforms.galaxyParams2.y, 0.35, 1.55);
    float tunnelPulse = clamp(uniforms.galaxyParams2.z, 0.0, 1.0);
    float audioSensitivity = clamp(uniforms.galaxyParams2.w, 0.65, 1.80);

    float aperture = clamp(uniforms.galaxyParams3.x, 0.10, 0.20);
    float tunnelDensity = clamp(uniforms.galaxyParams3.y, 8.0, 22.0);
    float laneStretch = clamp(uniforms.galaxyParams3.z, 0.9, 2.2);
    float beatEnv = clamp(uniforms.galaxyParams3.w, 0.0, 1.3);

    float verticalGradient = smoothstep(-0.55, 0.55, p.y);
    float3 color = mix(float3(0.004, 0.007, 0.018), float3(0.010, 0.018, 0.048), verticalGradient);

    float2 dustDrift = float2(slowTime * 0.015, -slowTime * 0.010);
    float deepMist = whNoise(uv * 5.2 + dustDrift) * 0.55 + whNoise(uv * 10.8 - dustDrift * 2.3) * 0.45;
    color += mistColor * deepMist * (0.12 + 0.16 * activity);

    for (int layer = 0; layer < 2; layer++) {
        float layerF = (float)layer;
        float scale = 14.0 + layerF * 8.0;
        float speed = 0.0016 + layerF * 0.0008;
        float2 field = (uv + float2(0.0, slowTime * speed)) * scale;
        float2 cell = floor(field);
        float2 local = fract(field) - 0.5;
        float seed = whHash2(cell + float2(7.1 * layerF, 13.4));

        if (seed > (0.76 - layerF * 0.03)) {
            float2 offset = float2(whHash2(cell + float2(2.3 + layerF, 4.7 + layerF)),
                                   whHash2(cell + float2(9.7 + layerF, 1.9 + layerF))) - 0.5;
            float2 d = local - offset * 0.75;
            float d2 = dot(d, d);
            float starCore = exp(-d2 * (110.0 + layerF * 62.0));
            float starHalo = exp(-d2 * (18.0 + layerF * 8.0));
            float star = starCore + starHalo * 0.42;
            float twinkle = 0.78 + 0.22 * sin(slowTime * (0.9 + layerF * 0.22) + seed * 30.0);
            float hue = fract(seed * 1.71 + layerF * 0.19);
            float sat = 0.28 + layerF * 0.08;
            float3 prismColor = hsv2rgb(float3(hue, sat, 1.0));
            float3 starColor = mix(prismColor, coolColor, 0.45);
            starColor = mix(starColor, hotColor, smoothstep(0.72, 0.98, seed) * 0.22);
            color += starColor * star * twinkle * (0.090 + treble * 0.09 + beatEnv * 0.05 + activity * 0.03);
        }
    }

    float depth = 1.0 / max(r + aperture * 1.15, 0.045);
    float innerWall = smoothstep(aperture * 1.02, aperture + 0.16, r);
    float outerWall = 1.0 - smoothstep(tunnelRadius + 0.36, tunnelRadius + 0.62, r);
    float wallMask = innerWall * outerWall;

    float tunnelFlow = motionTime * (1.5 + travelSpeed * 2.0);
    int ribArmsAInt = max(6, (int)round(6.0 + swirlAmount * 8.0));
    int ribArmsBInt = max(4, (int)round(4.0 + swirlAmount * 5.0));
    float ribArmsA = (float)ribArmsAInt;
    float ribArmsB = (float)ribArmsBInt;
    float twistA = ang * ribArmsA - depth * (2.4 + tunnelDensity * 0.34) + tunnelFlow;
    float twistB = -ang * ribArmsB - depth * (1.2 + tunnelDensity * 0.18) + tunnelFlow * 0.65;
    float helixA = pow(saturate(0.5 + 0.5 * sin(twistA)), 4.0);
    float helixB = pow(saturate(0.5 + 0.5 * sin(twistB)), 5.0);
    float tunnelRibs = 0.5 + 0.5 * sin(depth * (7.0 + tunnelDensity * 0.85) - tunnelFlow * (1.4 + energy));
    int cloudArmsInt = max(3, (int)round(3.0 + swirlAmount * 3.0));
    float cloudSpin = ang * (float)cloudArmsInt + tunnelFlow * 0.12;
    float2 cloudDir = float2(cos(cloudSpin), sin(cloudSpin));
    float tunnelCloud = whNoise(cloudDir * (1.35 + swirlAmount * 0.28) +
                                float2(depth * 0.18 + tunnelFlow * 0.05,
                                       depth * 0.09 - tunnelFlow * 0.03));
    float wallEnergy = wallMask * (helixA * 0.92 + helixB * 0.58) * (0.58 + 0.42 * tunnelRibs) * (0.78 + 0.22 * tunnelCloud);
    color += coolColor * wallEnergy * (0.18 + energy * 0.30 + tunnelPulse * 0.12);
    color += hotColor * wallMask * helixB * tunnelRibs * (0.05 + bass * 0.16 + beatEnv * 0.16);

    float portalRim = ringGlow(r, aperture + 0.02 + beatEnv * 0.014, 0.020 + bass * 0.007);
    float outerRim = ringGlow(r, tunnelRadius + 0.02 * sin(ang * 3.0 + tunnelFlow * 0.08), 0.060 + beatEnv * 0.020);
    color += coolColor * portalRim * (0.55 + bass * 0.72 + beatEnv * 0.42);
    color += theme * float3(0.18, 0.30, 0.50) * outerRim * (0.15 + mid * 0.18);

    float centerVoid = 1.0 - smoothstep(aperture * 0.82, aperture * 1.10, r);
    color *= 1.0 - centerVoid * 0.93;

    float originHalo = exp(-r * (18.0 - bass * 3.0)) * (0.10 + bass * 0.16);
    color += hotColor * originHalo * 0.35;

    float laneRotation = motionTime * 0.05 * swirlAmount;

    for (int i = 0; i < 10; i++) {
        if (i >= barCount) continue;

        float fi = (float)i;
        float lanePhase = (fi + 0.5) / max((float)barCount, 1.0);
        float laneAngle = lanePhase * TAU + laneRotation;
        float2 dir = float2(cos(laneAngle), sin(laneAngle));

        int sampleIndex = min(79, (int)(lanePhase * 79.0));
        int prevIndex = sampleIndex > 0 ? sampleIndex - 1 : 0;
        int nextIndex = sampleIndex < 79 ? sampleIndex + 1 : 79;
        float rawSample = uniforms.audioData[sampleIndex].x * 0.55 +
                          uniforms.audioData[prevIndex].x * 0.20 +
                          uniforms.audioData[nextIndex].x * 0.25;
        float sample = clamp(rawSample * audioSensitivity, 0.0, 1.45);
        float morph = smoothstep(0.05, 0.42, sample);

        float sourceLength = mix(0.008, 0.13 + bass * 0.05 + beatEnv * 0.04, morph);
        float sourceWidth = mix(0.0026, 0.0068, morph);
        float2 sourceA = dir * (aperture * 0.58);
        float2 sourceB = dir * (aperture * 0.58 + sourceLength);
        float sourceBar = capsuleGlow(p, sourceA, sourceB, sourceWidth);

        float3 laneColor = mix(coolColor, hotColor, 0.18 + lanePhase * 0.52);
        color += laneColor * sourceBar * (0.16 + sample * 0.34 + beatEnv * 0.12);

        for (int pulseIndex = 0; pulseIndex < 2; pulseIndex++) {
            float pulseSeed = whHash(fi * 13.1 + (float)pulseIndex * 29.7);
            float pulseSpeed = 0.09 + travelSpeed * 0.09 + sample * 0.08 + (float)pulseIndex * 0.016;
            float z = fract(pulseSeed + motionTime * pulseSpeed);
            float perspective = pow(z, 1.75);
            float radial = mix(aperture * (0.90 + 0.06 * (float)pulseIndex),
                               1.08 + 0.11 * (float)pulseIndex,
                               perspective);
            float trail = mix(0.012,
                              0.11 + sample * 0.26 + laneStretch * 0.10 + beatEnv * 0.07,
                              morph) * (0.28 + perspective * 1.28);
            float width = mix(0.0028, 0.0078 + sample * 0.0045, morph) * mix(0.95, 1.35, perspective);

            float2 head = dir * radial;
            float2 tail = dir * max(aperture * 0.72, radial - trail);
            float body = capsuleGlow(p, tail, head, width);
            float tip = exp(-dot(p - head, p - head) / max(width * width * 2.8, 0.00002));
            float nearBoost = smoothstep(0.35, 1.0, perspective);
            float gain = (0.05 + sample * 0.44 + beatEnv * 0.18) * (0.34 + nearBoost * 1.08);

            color += laneColor * body * gain;
            color += mix(float3(1.0), laneColor, 0.32) * tip * gain * (0.60 + morph * 0.75);
        }
    }

    for (int i = 0; i < 18; i++) {
        if (i >= starLaneCount) continue;

        float fi = (float)i;
        float seed = 19.7 + fi * 11.3;
        float selector = whHash(seed);
        int sampleIndex = min(79, (int)(selector * 79.0));
        float bandSample = clamp((uniforms.audioData[sampleIndex].x * 0.60 +
                                  uniforms.audioData[sampleIndex].z * 0.40) * audioSensitivity,
                                 0.0,
                                 1.35);

        float band = selector < 0.33 ? bass : (selector < 0.66 ? mid : treble);
        band = mix(band, bandSample, 0.45);

        float flightSpeed = 0.018 + travelSpeed * 0.030 + selector * 0.010;
        float z = fract(whHash(seed + 4.9) + slowTime * flightSpeed);
        float perspective = pow(z, 1.9);
        float angleOffset = (whHash(seed + 9.2) - 0.5) * 0.30 + perspective * swirlAmount * 0.46;
        float laneAngle = whHash(seed + 2.7) * TAU + angleOffset;
        float2 dir = float2(cos(laneAngle), sin(laneAngle));

        float radial = mix(aperture + 0.02, 1.18 + whHash(seed + 12.4) * 0.12, perspective);
        float trail = mix(0.010,
                          0.080 + band * 0.15 + beatEnv * 0.06,
                          perspective) * (0.46 + perspective * 1.36);
        float width = mix(0.0028, 0.0074, perspective) * (1.00 + perspective * 0.22);

        float2 head = dir * radial;
        float2 tail = dir * max(aperture * 0.84, radial - trail);
        float streak = capsuleGlow(p, tail, head, width);
        float spark = exp(-dot(p - head, p - head) / max(width * width * 10.0, 0.00004));
        float headBloom = exp(-dot(p - head, p - head) / max(width * width * 28.0, 0.00008));

        float hue = fract(selector * 0.83 + fi * 0.071);
        float3 accentColor = hsv2rgb(float3(hue, 0.34, 1.0));
        float3 streakColor = mix(float3(0.56, 0.84, 1.10), accentColor, 0.28);
        streakColor = mix(streakColor, hotColor, selector * 0.48);
        float presence = smoothstep(0.18, 1.0, perspective);
        float gain = (0.16 + selector * 0.06) *
                     (0.52 + perspective * 1.18) *
                     (0.72 + presence * 0.58);
        color += streakColor * streak * gain;
        color += mix(float3(1.0), streakColor, 0.22) * spark * gain * 1.02;
        color += streakColor * headBloom * gain * 0.42;
    }

    float beatShock = ringGlow(r, aperture + 0.06 + beatEnv * 0.28, 0.026 + beatEnv * 0.018);
    color += hotColor * beatShock * flashIntensity * (0.16 + beatEnv * 0.78);
    color += mix(coolColor, hotColor, 0.45) * beatEnv * flashIntensity * 0.06;
    color *= 1.0 + beatEnv * flashIntensity * 0.18;

    float vignette = smoothstep(1.08, 0.18, r);
    color *= vignette * (0.92 + 0.16 * musicActive);
    color += coolColor * (1.0 - vignette) * 0.04;

    color = color / (1.0 + color * (0.86 / max(paletteBoost, 0.01)));
    return float4(saturate(color), 1.0);
}
