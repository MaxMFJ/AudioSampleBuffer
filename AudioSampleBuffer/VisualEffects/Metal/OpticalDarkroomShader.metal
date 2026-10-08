// Optical Darkroom: flowing dichroic film, independent exposures, retained silver marks.
#include <metal_stdlib>
#include "ShaderCommon.metal"
using namespace metal;

static float filmHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}
static float filmNoise(float2 p) {
    float2 i = floor(p), f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    return mix(mix(filmHash(i), filmHash(i + float2(1, 0)), f.x),
               mix(filmHash(i + float2(0, 1)), filmHash(i + 1), f.x), f.y);
}
static float filmBell(float d, float width) {
    float v = d / width;
    return exp(-v * v);
}
fragment float4 opticalDarkroomFragment(RasterizerData in [[stage_in]],
                                        constant Uniforms &u [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, u.resolution);
    float2 p = (uv - 0.5) * 2.0;
    float3 stems = saturate(u.galaxyParams3.xyz);
    float3 exposure = saturate(u.galaxyParams1.xyz);
    float flow = u.cyberpunkControls.y;
    float grainAmount = u.cyberpunkControls.z;
    float development = saturate(u.galaxyParams3.w);
    float paper = filmNoise(p * 3.2 + 7.0);
    // Broad folds share one low-frequency field; highlights have a crisp shoulder.
    float warp = (paper - 0.5) * 0.13;
    float upper = 1.0 - smoothstep(-0.05, 0.92, p.y);
    float3 light = float3(0.006, 0.010, 0.021);
    float3 teal = float3(0.035, 0.60, 0.69);
    float3 amber = float3(1.0, 0.25, 0.055);
    float3 blue = float3(0.17, 0.22, 0.66);
    for (int i = 0; i < 3; ++i) {
        float k = float(i);
        float center = -0.47 + k * 0.39 + 0.20 * sin(p.y * 2.65 + k * 1.75 + flow)
                       + 0.10 * sin(p.y * 5.1 - flow * 0.63 + k) + warp;
        float d = p.x - center;
        float width = 0.13 + k * 0.022 + stems.x * 0.045 + exposure.x * 0.018;
        float body = filmBell(d, width);
        float edgeWidth = max(0.015 + 0.009 * paper, fwidth(d) * 1.25);
        float edge = filmBell(d - width * 0.64, edgeWidth);
        float veil = filmBell(d + 0.065, width * 2.3);
        float along = 0.60 + 0.40 * sin(p.y * 1.6 + k * 1.8 + 1.2);
        float3 dye = i == 0 ? teal : (i == 1 ? blue : amber);
        light += dye * (body * 0.58 + veil * 0.13) * along * upper *
                 (0.80 + exposure.x * 0.40 + stems.x * 0.75);
        light += mix(dye, float3(1.0, 0.82, 0.60), 0.38) * edge * along * upper *
                 (0.23 + stems.x * 0.50);
    }
    // Developed emulsion remains fixed in screen space across subsequent notes.
    for (int i = 0; i < 8; ++i) {
        float4 mark = u.guitarWaves[i]; // x, y, signed strength, radius
        if (abs(mark.z) < 0.001) continue;
        float2 q = p - mark.xy;
        float density = exp(-dot(q, q) / (mark.w * mark.w));
        float3 dye = mark.z > 0.0 ? float3(0.20, 0.42, 0.60) : float3(0.65, 0.14, 0.075);
        light += dye * density * abs(mark.z) * (0.045 + development * 0.10);
    }
    // Each note owns its age and position. New notes cannot reset older exposures.
    for (int i = 0; i < 16; ++i) {
        float4 event = u.pigmentEvents[i]; // age, signed strength, x, y
        float strength = abs(event.y);
        if (strength < 0.001) continue;
        bool piano = event.y > 0.0;
        float lifetime = piano ? 10.0 : 16.0;
        float age = event.x;
        float fade = smoothstep(0.0, 0.35, age) * (1.0 - smoothstep(lifetime * 0.3, lifetime, age));
        float radius = piano ? 0.024 + 0.047 * (1.0 - exp(-age * 0.5)) :
                               0.11 + 0.17 * (1.0 - exp(-age * 0.22));
        float2 q = p - event.zw;
        q = piano ? q : q * float2(0.72, 1.24);
        float r2 = dot(q, q) / (radius * radius);
        float core = exp(-r2 * 2.5), halo = exp(-r2 * 0.34);
        float3 dye = piano ? float3(0.70, 0.87, 1.0) : float3(1.0, 0.26, 0.065);
        light += dye * (core * (piano ? 1.35 : 0.32) + halo * 0.25) * strength * fade;
    }
    // Fine fixed grain, without crawling noise or coarse procedural squares.
    float grain = filmHash(floor(in.position.xy)) - 0.5;
    light *= 0.90 + 0.10 * paper;
    light *= 1.0 - smoothstep(0.65, 1.48, length(p * float2(0.75, 1.0))) * 0.33;
    float3 color = 1.0 - exp(-light * 1.75);
    color = pow(max(color, 0.0), float3(0.83));
    color += grain * (0.012 + grainAmount * 0.025) * (0.35 + sqrt(max(color.g, 0.0)));
    return float4(saturate(color), 1.0);
}
