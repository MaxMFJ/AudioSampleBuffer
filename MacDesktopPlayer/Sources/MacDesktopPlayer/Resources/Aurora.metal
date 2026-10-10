#include <metal_stdlib>
using namespace metal;

struct AuroraVertexOut { float4 position [[position]]; float2 uv; };
struct AuroraVisualAudio { float time; float bass; float mid; float treble; float aspectRatio; };
struct DesktopMoodColors {
    float4 atmosphere, volumetricBeam, topLightArray, laserFanBlue, laserFanGreen;
    float4 rotatingBeam, rotatingBeamExtra, edgeLight, coronaFilaments, pulseRing;
};

vertex AuroraVertexOut auroraDesktopVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 points[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    AuroraVertexOut out;
    out.position = float4(points[vertexID], 0.0, 1.0);
    out.uv = points[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 desktopFragment(AuroraVertexOut in [[stage_in]], constant AuroraVisualAudio &audio [[buffer(0)]],
                                constant DesktopMoodColors &mood [[buffer(1)]]) {
    float2 p = (in.uv - 0.5) * float2(1.0, 0.62);
    float radius = length(p);
    float angle = atan2(p.y, p.x);
    float bass = clamp(audio.bass, 0.0, 1.0);
    float mid = clamp(audio.mid, 0.0, 1.0);
    float treble = clamp(audio.treble, 0.0, 1.0);
    float flow = sin(radius * (17.0 + bass * 8.0) - audio.time * (0.24 + bass * 0.16) + sin(angle * 3.0 + audio.time * 0.12) * (0.48 + mid * 0.5));
    float filament = smoothstep(0.90 - treble * 0.16, 1.0, flow) * exp(-radius * (1.25 - bass * 0.25));
    float halo = exp(-pow((radius - (0.18 + bass * 0.05)), 2.0) * 34.0) * (0.12 + mid * 0.38);
    float3 deep = float3(0.006, 0.009, 0.025);
    float3 blue = mood.atmosphere.rgb * float3(0.10, 0.27, 0.56);
    float3 teal = mood.volumetricBeam.rgb * float3(0.30, 0.76, 0.72);
    float3 color = deep + blue * (filament * 0.75 + halo * 0.45) + teal * (filament * treble * 0.55 + halo * 0.30);
    float vignette = smoothstep(0.86, 0.13, radius);
    return float4(color * vignette, 1.0);
}

struct GuitarSurgeUniforms {
    float cyclePhase;
    float beatPhase;
    float bpm;
    float guitar;
    float drumPulse;
    float activity;
};

vertex AuroraVertexOut guitarSurgeVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 points[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    AuroraVertexOut out;
    out.position = float4(points[vertexID], 0.0, 1.0);
    out.uv = points[vertexID] * 0.5 + 0.5;
    return out;
}

fragment float4 guitarSurgeFragment(
    AuroraVertexOut in [[stage_in]],
    constant GuitarSurgeUniforms &u [[buffer(0)]],
    constant DesktopMoodColors &mood [[buffer(1)]]) {
    float2 uv = in.uv;
    float phase = fract(u.cyclePhase);
    float beat = fract(u.beatPhase);
    // A broad, rippling scan travels across the whole desktop every four beats.
    float scanX = mix(-0.18, 1.18, phase);
    float ripple = 0.025 * sin(uv.y * 12.0 - beat * 6.2831853 + uv.x * 3.0);
    float distance = uv.x - scanX + ripple;
    float head = exp(-distance * distance * 1700.0);
    float glow = exp(-distance * distance * 90.0);
    float tail = distance > 0.0 ? exp(-distance * 9.0) : 0.0;
    float sweep = saturate(head * 0.95 + glow * 0.42 + tail * 0.10);

    // Each detected beat launches an expanding ring and a restrained screen flash.
    float2 centered = (uv - 0.5) * float2(1.0, 0.70);
    float radius = length(centered);
    float expandingRadius = beat * 0.95;
    float drumRing = exp(-pow((radius - expandingRadius) / 0.018, 2.0)) * u.drumPulse;
    float drumFlash = u.drumPulse * 0.11;

    float intensity = saturate(u.activity) * (0.30 + saturate(u.guitar) * 0.42);
    float3 electricBlue = mood.volumetricBeam.rgb;
    float3 hotWhite = float3(1.0, 0.91, 0.76);
    float3 waveColor = mix(electricBlue, hotWhite, saturate(head * 0.85 + u.guitar * 0.25));
    float3 drumColor = mood.pulseRing.rgb;
    float3 color = waveColor * sweep * intensity + drumColor * (drumRing * 0.72 + drumFlash);
    float alpha = saturate(sweep * intensity * 0.68 + drumRing * 0.40 + drumFlash * 0.65);
    return float4(color, alpha);
}
