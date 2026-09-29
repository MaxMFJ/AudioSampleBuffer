//
//  MirrorStrataShader.metal
//  AudioSampleBuffer
//
//  Nested 3D glass frames receding as a corridor. Geometry and shading follow
//  Glass Resonance: parametric tubes, Fresnel, rear-face refraction, HDR bloom.
//  Audio lights the frames themselves as neon rounded rings travelling inward→out.
//

#include <metal_stdlib>
#include "ShaderCommon.metal"
using namespace metal;

constant int kMirrorPathSeg = 128;
constant int kMirrorTubeSeg = 16;
constant int kMirrorLayers = 6;

static float3 mirrorAxis(float3 p, float3 axis, float a) {
    axis = normalize(axis);
    float s = sin(a), c = cos(a);
    return p * c + cross(axis, p) * s + axis * dot(axis, p) * (1.0 - c);
}

static float2 mirrorPath2(float t, float2 halfSize, float r) {
    r = min(r, min(halfSize.x, halfSize.y) * 0.48);
    float hw = max(halfSize.x - r, 0.002);
    float hh = max(halfSize.y - r, 0.002);
    float u = fract(t) * 8.0;
    int sec = min(int(u), 7);
    float f = saturate(u - float(sec));
    if (sec == 0) return float2(halfSize.x, mix(-hh, hh, f));
    if (sec == 1) {
        float a = f * 0.5 * M_PI_F;
        return float2(hw, hh) + r * float2(cos(a), sin(a));
    }
    if (sec == 2) return float2(mix(hw, -hw, f), halfSize.y);
    if (sec == 3) {
        float a = 0.5 * M_PI_F + f * 0.5 * M_PI_F;
        return float2(-hw, hh) + r * float2(cos(a), sin(a));
    }
    if (sec == 4) return float2(-halfSize.x, mix(hh, -hh, f));
    if (sec == 5) {
        float a = M_PI_F + f * 0.5 * M_PI_F;
        return float2(-hw, -hh) + r * float2(cos(a), sin(a));
    }
    if (sec == 6) return float2(mix(-hw, hw, f), -halfSize.y);
    float a = 1.5 * M_PI_F + f * 0.5 * M_PI_F;
    return float2(hw, -hh) + r * float2(cos(a), sin(a));
}

static float3 mirrorAtmosphere(constant Uniforms &u) { return clamp(u.activityMeter3.rgb, 0.0, 1.2); }
static float3 mirrorPrimary(constant Uniforms &u) { return clamp(u.activityMeter4.rgb, 0.0, 1.2); }
static float3 mirrorAccent(constant Uniforms &u) { return clamp(u.activityMeter5.rgb, 0.0, 1.2); }

static float3 mirrorStudio(float3 d, float high, float climax, constant Uniforms &u) {
    d = normalize(d);
    float key = exp(-pow((d.x + 0.42) / 0.23, 2.0) - pow((d.y - 0.54) / 0.58, 4.0));
    float rim = exp(-pow((d.x - 0.65) / 0.085, 2.0) - pow((d.y + 0.10) / 0.75, 4.0));
    float top = pow(max(dot(d, normalize(float3(0.0, 0.82, 0.42))), 0.0), 16.0);
    float strip = exp(-pow((d.y + 0.38 + 0.14 * d.x) / 0.035, 2.0)) * smoothstep(-0.8, 0.2, d.z);
    float heat = 1.0 + climax * 0.34;
    float3 atmosphere = mirrorAtmosphere(u), primary = mirrorPrimary(u), accent = mirrorAccent(u);
    return atmosphere * 0.16
         + primary * key * 3.6 * heat
         + accent * rim * (2.6 + high * 1.35 + climax * 0.78)
         + mix(primary, accent, 0.38) * top * (1.0 + climax * 0.35)
         + mix(primary, accent, 0.28 + climax * 0.38) * strip * (1.9 + climax * 0.60);
}

static float4 mirrorProject(float3 p, constant Uniforms &u) {
    float z = 4.4 - p.z;
    float squareScale = min(u.resolution.z, 1.0);
    float zoom = clamp(u.galaxyParams3.z, 0.92, 1.18);
    return float4(p.xy * 2.55 * squareScale * zoom, (z - 0.1) * 10.0 / (10.0 - 0.1), z);
}

static float mirrorWave(float farness, constant Uniforms &u) {
    float light = 0.0;
    float4 ages = u.cyberpunkControls;
    float4 amps = u.cyberpunkFrequencyControls;
    for (int w = 0; w < 4; ++w) {
        float amp = amps[w];
        if (amp < 0.015) continue;
        float age = max(ages[w], 0.0);
        float since = age - (1.0 - farness);
        float approach = exp(-pow(max(-since, 0.0) / 0.22, 2.0));
        float afterglow = exp(-max(since, 0.0) * 1.15);
        float envelope = since < 0.0 ? approach : afterglow;
        float fadeIn = smoothstep(0.0, 0.14, age);
        light += amp * envelope * fadeIn;
    }
    return saturate(light);
}

static float mirrorIdle(float farness, constant Uniforms &u) {
    float spec = saturate(u.audioData[clamp(int(farness * 79.99), 0, 79)].y);
    float low = u.galaxyParams1.x, mid = u.galaxyParams1.y, high = u.galaxyParams1.z;
    float energy = u.galaxyParams2.w, climax = u.galaxyParams2.z;
    return saturate(spec * 0.22 + low * (1.0 - farness) * 0.14 + high * farness * 0.16
                    + mid * 0.07 + energy * 0.05 + climax * 0.05);
}

static float3 mirrorNeon(float farness, float facing, constant Uniforms &u) {
    float wave = mirrorWave(farness, u);
    float idle = mirrorIdle(farness, u);
    float punch = wave * 0.82 + idle * 0.28;
    float climax = u.galaxyParams2.z;
    float3 neon = mix(mirrorAccent(u), mirrorPrimary(u), 0.34 + climax * 0.18);
    neon *= 0.98 + climax * 0.12;
    float filament = exp(-pow(facing - 0.22, 2.0) / 0.08) + pow(max(1.0 - facing, 0.0), 1.8);
    return neon * punch * (1.18 + 1.85 * filament);
}

struct MirrorFrameVertex {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 center;
    float farness;
};

vertex MirrorFrameVertex mirrorFrameVertex(uint id [[vertex_id]],
                                           uint layer [[instance_id]],
                                           constant Uniforms &u [[buffer(0)]]) {
    float t = float(id / (kMirrorTubeSeg + 1)) / float(kMirrorPathSeg);
    float v = float(id % (kMirrorTubeSeg + 1)) * (2.0 * M_PI_F / float(kMirrorTubeSeg));
    float farness = float(layer) / float(kMirrorLayers - 1);
    float low = u.galaxyParams1.x, mid = u.galaxyParams1.y, high = u.galaxyParams1.z;
    float impact = u.galaxyParams1.w, phase = u.galaxyParams2.x, climax = u.galaxyParams2.z;
    int band = clamp(int(farness * 79.99), 0, 79);
    float spec = saturate(u.audioData[band].y);

    float aspect = min(u.resolution.z, 1.0);
    float zoom = clamp(u.galaxyParams3.z, 0.92, 1.18);
    float cover = clamp(u.galaxyParams3.w, 0.12, 0.38);
    float zPos = mix(1.68, -2.85, pow(farness, 0.58));
    float persp = max(4.4 - zPos, 0.85);
    float k = max(2.55 * aspect * zoom, 1e-4);
    float2 ndcInner = float2(cover, cover) * 1.08;
    float2 ndcOuter = float2(aspect, 1.0) * 0.97;
    float recede = pow(farness, 0.62);
    float2 ndc = mix(ndcOuter, ndcInner, recede);
    float2 halfSize = ndc * persp / k;
    halfSize *= 1.0 + low * 0.028 * (1.0 - farness) + impact * 0.020 * (1.0 - farness);
    float corner = mix(0.11, 0.30, farness) * min(halfSize.x, halfSize.y);
    float radius = 0.024 * min(halfSize.x, halfSize.y)
                 * (1.0 + spec * 0.22 + low * 0.16 * (1.0 - farness)
                    + climax * 0.06 + high * farness * 0.08);
    float emit = saturate(mirrorWave(farness, u) + mirrorIdle(farness, u) * 0.45);
    radius *= 1.0 + emit * 0.28;
    float oval = 1.36 + mid * 0.08;

    float ds = 1.0 / float(kMirrorPathSeg);
    float2 p0 = mirrorPath2(t, halfSize, corner);
    float2 p1 = mirrorPath2(t + ds, halfSize, corner);
    float2 p2 = mirrorPath2(t - ds, halfSize, corner);
    float3 path = float3(p0, 0.0);
    float3 tangent = normalize(float3(p1 - p2, 0.0));
    float3 binormal = float3(0, 0, 1);
    float3 normal = normalize(cross(binormal, tangent));
    binormal = cross(tangent, normal);
    float3 offset = radius * (cos(v) * normal * oval + sin(v) * binormal / oval);
    float3 p = path + offset;
    float3 n = normalize(cos(v) * normal * oval + sin(v) * binormal / oval);

    float lagTwist = pow(farness, 1.35);
    float twistAmp = 0.040 + mid * 0.07 + climax * 0.36 + impact * 0.03;
    float angle = twistAmp * sin(phase * 0.85) * lagTwist;
    p = mirrorAxis(p, float3(0, 0, 1), angle);
    n = mirrorAxis(n, float3(0, 0, 1), angle);
    path = mirrorAxis(path, float3(0, 0, 1), angle);
    float lean = (0.16 + climax * 0.04 + mid * 0.02) * mix(0.08, 1.0, pow(farness, 0.55));
    p = mirrorAxis(p, float3(1.0, 0.12, 0.0), lean);
    n = mirrorAxis(n, float3(1.0, 0.12, 0.0), lean);
    path = mirrorAxis(path, float3(1.0, 0.12, 0.0), lean);
    p.z += zPos;
    path.z += zPos;
    float breath = 0.014 * mid * sin(phase * 0.7 + farness * 4.0);
    p.z += breath;
    path.z += breath;

    MirrorFrameVertex o;
    o.position = mirrorProject(p, u);
    o.world = p;
    o.normal = n;
    o.center = path;
    o.farness = farness;
    return o;
}

constexpr sampler mirrorSampler(coord::normalized, address::clamp_to_edge, filter::linear);

fragment float4 mirrorFrameBackFragment(MirrorFrameVertex in [[stage_in]],
                                        constant Uniforms &u [[buffer(0)]]) {
    float3 n = normalize(in.normal);
    float3 view = normalize(float3(0, 0, 4.4) - in.world);
    float edge = pow(1.0 - abs(dot(n, view)), 3.0);
    float climax = u.galaxyParams2.z;
    float3 studio = mirrorStudio(reflect(-view, n), u.galaxyParams1.z, climax, u);
    float facing = clamp(abs(dot(n, view)), 0.0, 1.0);
    float emit = saturate(mirrorWave(in.farness, u) + mirrorIdle(in.farness, u) * 0.45);
    float3 glass = studio * (0.035 + 0.30 * edge) * (1.0 + climax * 0.18);
    glass *= mix(1.0, 0.32, pow(in.farness, 1.05));
    glass *= mix(1.0, 0.62, emit);
    return float4(glass + mirrorNeon(in.farness, facing, u) * 0.52, 1.0);
}

fragment float4 mirrorFrameFragment(MirrorFrameVertex in [[stage_in]],
                                    constant Uniforms &u [[buffer(0)]],
                                    texture2d<float> rear [[texture(0)]]) {
    float3 n = normalize(in.normal);
    float3 incident = normalize(in.world - float3(0, 0, 4.4));
    n = faceforward(n, incident, n);
    float facing = clamp(-dot(incident, n), 0.0, 1.0);
    float fresnel = 0.040 + 0.96 * pow(1.0 - facing, 5.0);
    float high = u.galaxyParams1.z, climax = u.galaxyParams2.z;
    float spread = 0.006 + high * 0.018 + climax * 0.026;
    float thickness = 2.0 * length(in.world - in.center) * max(facing, 0.12);
    float3 transmission = 0;
    for (uint c = 0; c < 3; ++c) {
        float ior = 1.46 + (float(c) - 1.0) * spread;
        float3 inside = refract(incident, n, 1.0 / ior);
        float3 exitNormal = normalize(n + inside * (2.0 * max(-dot(n, inside), 0.05)));
        float3 outgoing = refract(inside, -exitNormal, ior);
        if (dot(outgoing, outgoing) < 0.001) outgoing = reflect(inside, -exitNormal);
        transmission[c] = mirrorStudio(outgoing, high, climax, u)[c];
    }
    transmission *= exp(-float3(0.42, 0.20, 0.13) * thickness * 1.8);
    float3 reflection = mirrorStudio(reflect(incident, n), high, climax, u);
    float2 screenUV = in.position.xy / u.resolution.xy;
    float2 bend = n.xy * thickness * 0.10 * min(u.resolution.z, 1.0);
    float3 through;
    for (uint c = 0; c < 3; ++c) {
        through[c] = rear.sample(mirrorSampler, screenUV + bend * (1.0 + (float(c) - 1.0) * spread * 8.0))[c];
    }
    float3 color = (through * 0.88 + transmission * 0.10) * (1.0 - fresnel) + reflection * fresnel;
    color += reflection * 0.028 + mirrorAtmosphere(u) * pow(1.0 - facing, 3.0) * 0.28;
    color += mix(mirrorAccent(u), mirrorPrimary(u), climax) * pow(1.0 - facing, 2.2) * (0.08 + climax * 0.12);
    color *= mix(1.0, 0.34, pow(in.farness, 1.05));
    color = mix(color, mirrorAtmosphere(u) * 0.10, pow(in.farness, 1.45) * 0.42);

    float emit = saturate(mirrorWave(in.farness, u) + mirrorIdle(in.farness, u) * 0.45);
    color *= mix(1.0, 0.58, emit);
    color += mirrorNeon(in.farness, facing, u);
    return float4(color, 1.0);
}

fragment float4 mirrorBackdropFragment(RasterizerData in [[stage_in]],
                                       constant Uniforms &u [[buffer(0)]]) {
    float2 p = (in.texCoord - 0.5) * 2.0 / min(u.resolution.z, 1.0);
    float r = length(p);
    float ang = atan2(p.y, p.x);
    float low = u.galaxyParams1.x, mid = u.galaxyParams1.y, high = u.galaxyParams1.z;
    float phase = u.galaxyParams2.x, climax = u.galaxyParams2.z, energy = u.galaxyParams2.w;
    float activity = saturate(u.cyberpunkBackgroundParams.x);
    float3 atmosphere = mirrorAtmosphere(u);
    float3 primary = mirrorPrimary(u);
    float3 accent = mirrorAccent(u);

    float pool = exp(-dot(p * float2(1.28, 1.48), p * float2(1.28, 1.48)));
    float floorGlow = exp(-pow((p.y + 0.72) / 0.28, 2.0)) * exp(-abs(p.x) * 1.6);
    float3 color = float3(0.0005) + atmosphere * (0.010 + 0.028 * pool) * (0.68 + energy * 0.28);
    color += primary * pool * low * 0.05;
    color += mix(primary, accent, 0.35) * floorGlow * (0.03 + low * 0.08 + climax * 0.05);
    float well = exp(-dot(p * float2(2.15, 2.45), p * float2(2.15, 2.45)));
    color *= 1.0 - well * 0.28;

    float fade = activity * (0.22 + high * 0.48 + climax * 0.42 + energy * 0.22);
    if (fade > 0.01) {
        for (int i = 0; i < 6; ++i) {
            float lobe = abs(sin(ang + phase * 0.31 + float(i) * 1.0472));
            float shaft = exp(-11.0 * lobe) * exp(-r * 0.85);
            color += mix(accent, primary, float(i) / 5.0) * shaft * fade * 0.38;
        }
        float extra = smoothstep(0.40, 0.88, activity * (0.45 + energy + climax));
        if (extra > 0.01) {
            for (int i = 0; i < 4; ++i) {
                float lobe = abs(sin(ang - phase * 0.44 + float(i) * 1.5708 + 0.4));
                float shaft = exp(-20.0 * lobe) * exp(-r * 1.25);
                color += mix(primary, accent, float(i) / 3.0) * shaft * extra * 0.30;
            }
        }
    }

    float2 cell = floor(p * 64.0 + float2(phase * 0.12, -phase * 0.08));
    float spark = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5);
    color += accent * smoothstep(0.996, 0.999, spark) * (0.03 + high * 0.08 + climax * 0.05);
    color += primary * exp(-r * 2.2) * climax * 0.08;
    color += atmosphere * mid * 0.025;
    float vignette = smoothstep(1.65, 0.55, r);
    color *= 0.82 + 0.18 * vignette;
    return float4(color, 1.0);
}
