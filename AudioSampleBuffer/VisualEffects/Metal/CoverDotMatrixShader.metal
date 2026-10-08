#include <metal_stdlib>
#include "ShaderCommon.metal"
using namespace metal;

struct CoverDotMatrixControls {
    float4 values; // grid count, dot size, audio sensitivity, halo strength
};

vertex RasterizerData coverDotMatrixVertex(uint id [[vertex_id]]) {
    constexpr float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
    constexpr float2 uvs[3] = {float2(0.0, 1.0), float2(2.0, 1.0), float2(0.0, -1.0)};
    RasterizerData out;
    out.position = float4(positions[id], 0.0, 1.0);
    out.texCoord = uvs[id];
    out.color = 1.0;
    return out;
}

constexpr sampler coverDotSampler(coord::normalized, address::clamp_to_edge, filter::linear);

fragment float4 coverDotMatrixFragment(RasterizerData in [[stage_in]],
                                       constant Uniforms &u [[buffer(0)]],
                                       constant CoverDotMatrixControls &controls [[buffer(1)]],
                                       constant float4 &styleControls [[buffer(2)]],
                                       texture2d<float> cover [[texture(0)]]) {
    float2 uv = in.texCoord;
    float time = u.time.x;
    int style = clamp(int(round(styleControls.x)), 0, 4);
    float sensitivity = clamp(controls.values.z, 0.35, 1.8);
    // Fall back to the live spectrum when separated stems are unavailable;
    // otherwise a newly selected effect can look almost frozen.
    float audioBass = saturate(max(max(u.audioData[2].y, u.audioData[4].y), u.audioData[7].y) * 2.8);
    float audioMid = saturate(max(max(u.audioData[16].y, u.audioData[23].y), u.audioData[31].y) * 2.5);
    float audioTreble = saturate(max(max(u.audioData[46].y, u.audioData[59].y), u.audioData[72].y) * 3.0);
    float audioTransient = saturate(max(max(u.audioData[2].w, u.audioData[16].w), u.audioData[46].w) * 3.5);
    float guitar = saturate(max(u.instrumentStems.x, audioTreble * 0.72) * sensitivity);
    float piano = saturate(max(u.instrumentStems.y, audioMid * 0.78) * sensitivity);
    float drums = saturate(max(u.instrumentStems.z, audioBass * 0.90) * sensitivity);
    float kick = max(max(drums, audioTransient * 0.72), max(audioBass * 0.60, saturate(u.categoryFeatures.y) * 0.78));
    float energy = saturate((audioBass + audioMid + audioTreble) * 0.34);

    // Keep every dot and every cover sample anchored to the same UV. Styles
    // change only the brightness/size wave over the fixed dot field.
    float2 centered = uv - 0.5;
    float coverRadius = length(centered);
    float angle = atan2(centered.y, centered.x);
    float grid = clamp(controls.values.x, 72.0, 144.0);
    float2 cellUV = fract(uv * grid) - 0.5;
    float2 cellCenter = (floor(uv * grid) + 0.5) / grid;
    float2 coverUV = clamp(cellCenter, 0.0, 1.0);
    float3 sampled = cover.sample(coverDotSampler, coverUV).rgb;
    float luma = dot(sampled, float3(0.2126, 0.7152, 0.0722));

    float phase;
    if (style == 1) { // Tunnel-like concentric brightness wave.
        phase = coverRadius * 34.0 - time * (2.1 + kick * 1.4);
    } else if (style == 2) { // Orbiting spiral wave, dots stay in place.
        phase = angle * 5.0 + coverRadius * 24.0 - time * (1.25 + guitar * 1.1);
    } else if (style == 3) { // Beat-triggered radial wave.
        phase = coverRadius * 48.0 + sin(angle * 4.0 - time) * 2.2 - time * (1.8 + drums * 2.0);
    } else if (style == 4) { // Record-like grooves made by brightness only.
        phase = coverRadius * 86.0 + sin(angle * 3.0 - time * 0.7) * 1.6 - time * 0.45;
    } else { // Silk-like diagonal wave across the fixed cover.
        phase = (uv.y * 0.82 + uv.x * 0.28) * 30.0 - time * (1.65 + piano * 1.2);
    }
    float wave = 0.5 + 0.5 * sin(phase);
    wave = saturate(wave + kick * 0.20 + energy * 0.08);

    float cellAngle = atan2(cellUV.y, cellUV.x);
    float radial = length(cellUV);
    float directional = 0.5 + 0.5 * sin(cellAngle * 3.0 + time * 0.7 + guitar * 2.4);
    float dotRadius = controls.values.y * (0.72 + luma * 0.22);
    dotRadius *= 0.60 + wave * 0.78 + kick * (0.12 + 0.16 * directional) + piano * 0.08;
    float edge = 1.0 - smoothstep(dotRadius - 0.035, dotRadius + 0.018, radial);
    float halo = exp(-max(radial - dotRadius, 0.0) * 42.0) * (controls.values.w + kick * 0.18);
    float visibility = 0.18 + 0.82 * smoothstep(0.08, 0.80, wave + kick * 0.16);
    edge *= visibility;
    halo *= visibility;

    float3 stemTint = u.stemPalette[0].rgb * guitar * 0.16
                    + u.stemPalette[1].rgb * piano * 0.14
                    + u.stemPalette[2].rgb * drums * 0.19;
    float3 color = sampled * (0.34 + wave * 1.05 + luma * 0.16 + piano * 0.14 + kick * 0.24);
    color += stemTint * (0.22 + luma * 0.26);
    color += sampled * halo;
    color *= edge;

    float background = (0.008 + kick * 0.012) * (1.0 - edge);
    float3 bgTint = mix(float3(0.012, 0.015, 0.024), u.stemPalette[2].rgb * 0.10, kick);
    color += bgTint * background;
    float alpha = max(edge, background);
    return float4(color, alpha);
}

// Every style uses one real point per fixed cover sample. Only the point's
// position, size and light change; the source image is never warped.
struct CoverDotParticle {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float opacity;
    float height;
};

vertex CoverDotParticle coverDotParticleVertex(uint id [[vertex_id]],
                                               constant Uniforms &u [[buffer(0)]],
                                               constant CoverDotMatrixControls &controls [[buffer(1)]],
                                               constant float4 &styleControls [[buffer(2)]],
                                               texture2d<float> cover [[texture(0)]]) {
    float grid = clamp(round(controls.values.x), 72.0, 144.0);
    uint gridCount = uint(grid);
    float2 uv = (float2(float(id % gridCount), float(id / gridCount)) + 0.5) / grid;
    float3 coverColor = cover.sample(coverDotSampler, uv, level(0.0)).rgb;
    float sensitivity = clamp(controls.values.z, 0.35, 1.8);
    float low = saturate(max(max(max(u.audioData[2].y, u.audioData[4].y), u.audioData[7].y) * 2.8,
                             u.categoryFeatures.x));
    float middle = saturate(max(max(u.audioData[16].y, u.audioData[23].y), u.audioData[31].y) * 2.5);
    float high = saturate(max(max(u.audioData[46].y, u.audioData[59].y), u.audioData[72].y) * 3.0);
    float piano = saturate(max(u.instrumentStems.y, middle * 0.8) * sensitivity);
    float guitar = saturate(max(u.instrumentStems.x, high * 0.75) * sensitivity);
    float beat = saturate(styleControls.y);
    float beatAge = max(styleControls.z, 0.0);
    float t = u.time.x;
    float2 centered = uv - 0.5;
    float radius = length(centered);
    float angle = atan2(centered.y, centered.x);
    int style = clamp(int(round(styleControls.x)), 0, 4);

    // Piano rolls through the middle and guitar excites small local ripples.
    // Drum hits are reserved for a brightness pulse below, so they do not
    // disturb the movement already driven by the other stems.
    float bassWave = sin(uv.x * 8.0 - uv.y * 5.0 - t * 1.8);
    float pianoWave = sin(uv.x * 21.0 + t * 2.4) * cos(uv.y * 17.0 - t * 1.7);
    float guitarWave = sin(uv.x * 42.0 + uv.y * 35.0 + t * 5.2);
    if (style == 1) { // radial silk folds
        bassWave = sin(radius * 29.0 - t * 2.0);
        pianoWave = sin(radius * 45.0 - t * 2.7 + angle * 2.0);
        guitarWave = sin(angle * 9.0 + radius * 68.0 + t * 4.2);
    } else if (style == 2) { // tunnel: rings travel through the point field
        bassWave = sin(radius * 38.0 - t * 3.0);
        pianoWave = sin(radius * 54.0 + angle * 3.0 - t * 2.5);
        guitarWave = sin(angle * 12.0 - radius * 84.0 + t * 4.7);
    } else if (style == 3) { // orbital spiral
        bassWave = sin(angle * 3.0 + radius * 24.0 - t * 1.9);
        pianoWave = sin(angle * 5.0 - radius * 36.0 + t * 2.1);
        guitarWave = sin(angle * 11.0 + radius * 72.0 - t * 4.1);
    } else if (style == 4) { // vinyl grooves
        bassWave = sin(radius * 52.0 - t * 1.3);
        pianoWave = sin(radius * 77.0 + angle * 1.4 - t * 1.6);
        guitarWave = sin(radius * 109.0 - angle * 5.0 + t * 3.6);
    }
    float idleWave = sin(uv.x * 9.0 + uv.y * 4.0 - t * 0.72) * 0.035;
    float ringWidth = style == 4 ? 0.055 : 0.09;
    float ringFront = beatAge * (style == 2 ? 0.94 : 0.78);
    float beatRing = beat * exp(-pow((radius - ringFront) / ringWidth, 2.0));
    float height = idleWave + pianoWave * piano * 0.21 + guitarWave * guitar * 0.11;
    float crest = saturate(0.5 + height * 1.4);

    float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    clip += height * float2(0.018, 0.064);
    float pitch = u.resolution.x / grid;
    float size = pitch * controls.values.y * 2.25 * (0.88 + height * 0.50);

    CoverDotParticle out;
    out.position = float4(clip, 0.0, 1.0);
    out.pointSize = clamp(size, 1.5, 12.0);
    float3 stemTint = u.stemPalette[0].rgb * guitar * 0.08
                    + u.stemPalette[1].rgb * piano * 0.06;
    out.color = coverColor * (0.82 + crest * 0.34) + stemTint
              + beatRing * float3(0.72, 0.68, 0.58);
    out.opacity = 0.62 + crest * 0.28;
    out.height = height;
    return out;
}

fragment float4 coverDotParticleFragment(CoverDotParticle in [[stage_in]],
                                         float2 pointCoord [[point_coord]]) {
    float distanceFromCenter = length(pointCoord - 0.5) * 2.0;
    float core = 1.0 - smoothstep(0.66, 0.96, distanceFromCenter);
    float glow = exp(-distanceFromCenter * distanceFromCenter * 4.8);
    float alpha = saturate(core * 0.94 + glow * 0.06) * in.opacity;
    if (alpha < 0.015) discard_fragment();
    float3 color = in.color * (0.88 + saturate(in.height + 0.5) * 0.24);
    return float4(color, alpha);
}
