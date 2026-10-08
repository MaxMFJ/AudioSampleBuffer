// LiquidPigmentShader.metal
// Layered translucent pigments flow with melody and diffuse locally on drum hits.
#include <metal_stdlib>
#include "ShaderCommon.metal"
using namespace metal;

static float pigmentHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

static float pigmentNoise(float2 p) {
    float2 cell = floor(p);
    float2 local = fract(p);
    local = local * local * (3.0 - 2.0 * local);
    return mix(mix(pigmentHash(cell), pigmentHash(cell + float2(1.0, 0.0)), local.x),
               mix(pigmentHash(cell + float2(0.0, 1.0)), pigmentHash(cell + 1.0), local.x), local.y);
}

static float2 pigmentRotate(float2 p, float angle) {
    float c = cos(angle), s = sin(angle);
    return float2(c * p.x - s * p.y, s * p.x + c * p.y);
}

fragment float4 liquidPigmentFragment(RasterizerData in [[stage_in]],
                                      constant Uniforms &u [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, u.resolution);
    float2 p = (uv - 0.5) * 2.0;
    float time = u.time.x;
    float flowSpeed = clamp(u.galaxyParams1.x, 0.15, 1.4);
    float pigmentOpacity = clamp(u.galaxyParams1.y, 0.25, 1.0);
    float sensitivity = clamp(u.galaxyParams1.z, 0.3, 2.0);

    float mid = 0.0, high = 0.0;
    for (int i = 18; i < 48; ++i) mid += u.audioData[i].y;
    for (int i = 48; i < 76; ++i) high += u.audioData[i].y;
    mid = saturate(mid * (0.45 * sensitivity));
    high = saturate(high * (0.55 * sensitivity));

    // The melody bends the shared current slowly; treble only sharpens refraction.
    // Integrated by the renderer with a positive rate, so the palette never rocks backward.
    float heading = u.galaxyParams1.w;
    float2 q = pigmentRotate(p, heading);
    float drift = time * (0.035 + flowSpeed * 0.05);
    float warp = pigmentNoise(q * 2.8 + float2(drift, -drift * 0.6)) - 0.5;
    float2 fluid = q + 0.075 * float2(sin(q.y * 3.4 + time * 0.11),
                                      cos(q.x * 2.7 - time * 0.09));
    fluid.y += warp * 0.09;
    float x = fluid.x + drift;

    float cyanAxis = fluid.y - 0.25 * sin(x * 2.0 - time * 0.07) - 0.055 * sin(x * 5.2 + time * 0.04);
    float roseAxis = fluid.y - 0.19 + 0.23 * sin((x + 0.52) * 1.55 + time * 0.06);
    float amberAxis = fluid.y + 0.23 - 0.27 * sin((x - 0.34) * 1.28 - time * 0.05);
    float pigmentGrain = pigmentNoise(fluid * 6.0 + float2(time * 0.025, -time * 0.018));
    float edgeShift = (pigmentGrain - 0.5) * 0.045;

    float cyan = 1.0 - smoothstep(0.045, 0.17, abs(cyanAxis + edgeShift));
    float rose = 1.0 - smoothstep(0.040, 0.15, abs(roseAxis - edgeShift * 0.8));
    float amber = 1.0 - smoothstep(0.035, 0.135, abs(amberAxis + edgeShift * 0.7));
    float3 color = float3(0.006, 0.008, 0.016);

    float cyanAlpha = cyan * pigmentOpacity * (0.52 + mid * 0.13);
    float roseAlpha = rose * pigmentOpacity * (0.48 + mid * 0.12);
    float amberAlpha = amber * pigmentOpacity * (0.44 + mid * 0.12);
    float3 cyanPigment = float3(0.055, 0.58, 0.92);
    float3 rosePigment = float3(0.82, 0.075, 0.38);
    float3 amberPigment = float3(1.0, 0.40, 0.08);
    color = mix(color, cyanPigment, cyanAlpha);
    color = mix(color, rosePigment, roseAlpha);
    color = mix(color, amberPigment, amberAlpha);

    // Thin refractive edges brighten the overlapping pigment without a global flash.
    float cyanRim = exp(-pow((abs(cyanAxis) - 0.105) / 0.025, 2.0));
    float roseRim = exp(-pow((abs(roseAxis) - 0.092) / 0.022, 2.0));
    float amberRim = exp(-pow((abs(amberAxis) - 0.082) / 0.020, 2.0));
    float refraction = 0.22 + high * 0.24 + pigmentGrain * 0.10;
    color += float3(0.22, 0.76, 1.0) * cyanRim * cyanAlpha * refraction;
    color += float3(1.0, 0.30, 0.62) * roseRim * roseAlpha * refraction;
    color += float3(1.0, 0.66, 0.25) * amberRim * amberAlpha * refraction;

    // Three guitar-colored filaments orbit continuously without pushing the other layers.
    float guitarLevel = saturate(u.galaxyParams3.x);
    float guitarEnabled = u.galaxyParams3.y;
    float guitarPresence = smoothstep(0.035, 0.16, guitarLevel) * guitarEnabled;
    float guitarAngle = u.galaxyParams1.w * 1.35;
    float guitarWidth = 0.012 + guitarLevel * 0.010;
    float3 guitarColors[3] = {cyanPigment, rosePigment, amberPigment};
    for (int lineIndex = 0; lineIndex < 3; ++lineIndex) {
        float angle = guitarAngle + float(lineIndex) * 2.0943951;
        float2 local = pigmentRotate(p, -angle);
        float bend = 0.025 * sin(local.x * 5.0 + time * 0.18 + float(lineIndex) * 1.8) +
                     0.010 * sin(local.x * 12.0 - time * 0.13);
        float axis = local.y - bend * (0.35 + guitarLevel * 1.5);
        float endFade = smoothstep(0.10, 0.30, abs(local.x)) *
                        (1.0 - smoothstep(0.78, 0.98, abs(local.x)));
        float line = (1.0 - smoothstep(guitarWidth, guitarWidth * 2.8, abs(axis))) *
                     endFade * guitarPresence;
        float rim = exp(-pow((abs(axis) - guitarWidth * 1.15) / 0.009, 2.0));
        color = mix(color, guitarColors[lineIndex], line * 0.82);
        color += guitarColors[lineIndex] * rim * line * (0.12 + guitarLevel * 0.24);
    }

    // Piano droplets and drum pools have independent lifetimes and can coexist on screen.
    for (int i = 0; i < 16; ++i) {
        float4 event = u.pigmentEvents[i];
        float signedStrength = event.y;
        float strength = abs(signedStrength);
        if (strength < 0.001) continue;
        float age = event.x;
        float2 center = event.zw;
        float distanceToEvent = length((p - center) * float2(1.0, 0.88));
        // Derive from immutable event data, never the compacting array index.
        float seed = pigmentHash(float2(center.x * 91.7 + center.y * 13.1,
                                        center.y * 73.3 - center.x * 21.9));
        if (signedStrength > 0.0) {
            float life = 2.8;
            float fade = (1.0 - smoothstep(life * 0.56, life, age)) * (1.0 - smoothstep(0.0, 0.12, age) * 0.18);
            float radius = 0.018 + smoothstep(0.0, 0.75, age) * 0.055;
            float ripple = 1.0 - smoothstep(radius * 0.76, radius, distanceToEvent);
            float rim = exp(-pow((distanceToEvent - radius * 0.70) / max(radius * 0.18, 0.004), 2.0));
            float3 pianoPigment = mix(float3(0.88, 0.78, 1.0), rosePigment, seed * 0.42);
            color = mix(color, pianoPigment, ripple * fade * strength * 0.68);
            color += pianoPigment * rim * fade * strength * 0.16;
        } else {
            float life = 6.0;
            float fade = 1.0 - smoothstep(life * 0.48, life, age);
            float progress = smoothstep(0.0, 0.62, age);
            float radius = 0.045 + progress * 0.31;
            float unevenRadius = radius * (0.84 + pigmentNoise((p - center) * 10.0 + seed * 12.0) * 0.32);
            float pool = 1.0 - smoothstep(unevenRadius * 0.72, unevenRadius * 1.18, distanceToEvent);
            float rim = exp(-pow((distanceToEvent - unevenRadius * 0.91) / max(radius * 0.12, 0.006), 2.0));
            float3 drumPigment = mix(cyanPigment, amberPigment, seed * 0.72);
            color = mix(color, drumPigment, pool * fade * strength * 0.82);
            color += drumPigment * rim * fade * strength * 0.14;
        }
    }

    float vignette = 1.0 - smoothstep(0.55, 1.42, length(p)) * 0.16;
    return float4(max(color * vignette, float3(0.0)), 1.0);
}
