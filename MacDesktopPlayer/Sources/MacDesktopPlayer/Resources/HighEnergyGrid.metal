#include <metal_stdlib>
using namespace metal;

struct HighEnergyGridVertexOut {
    float4 position [[position]];
    float2 uv;
};

struct HighEnergyGridUniforms {
    float4 motion; // animation time, aspect ratio, glow, playing
    float4 color;
};

vertex HighEnergyGridVertexOut highEnergyGridDesktopVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 points[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    HighEnergyGridVertexOut out;
    out.position = float4(points[vertexID], 0.0, 1.0);
    out.uv = points[vertexID] * 0.5 + 0.5;
    return out;
}

static inline float highEnergyGridHash(float x) {
    return fract(sin(x * 127.1 + 311.7) * 43758.5453);
}

static inline float highEnergyGridLine(float coordinate, float width) {
    float distanceToLine = abs(fract(coordinate + 0.5) - 0.5);
    return 1.0 - smoothstep(width, width + max(fwidth(coordinate), 0.001), distanceToLine);
}

fragment float4 highEnergyGridDesktopFragment(
    HighEnergyGridVertexOut in [[stage_in]],
    constant HighEnergyGridUniforms &uniforms [[buffer(0)]]) {
    float time = uniforms.motion.x;
    float aspect = max(uniforms.motion.y, 0.1);
    float glow = saturate(uniforms.motion.z);
    float playing = uniforms.motion.w;
    float3 tint = uniforms.color.rgb;

    float2 uv = in.uv;
    float horizon = 0.56;
    float perspectiveDepth = 0.24 / max(0.025, horizon - uv.y);
    float2 world = float2((uv.x - 0.5) * perspectiveDepth * aspect * 2.4,
                          perspectiveDepth * 0.54 + time * 0.72);
    float visibleGround = smoothstep(0.06, 0.42, perspectiveDepth)
                        * (1.0 - smoothstep(22.0, 54.0, perspectiveDepth));
    float vertical = highEnergyGridLine(world.x * 1.55, 0.010) * visibleGround;
    float horizontal = highEnergyGridLine(world.y, 0.010) * visibleGround;
    float farFade = exp(-perspectiveDepth * 0.045);

    float gridGlow = max(glow, 0.0);
    float particleGate = smoothstep(0.34, 0.72, gridGlow);
    float verticalCell = floor(world.x * 1.55);
    float horizontalCell = floor(world.y);
    float verticalPhase = world.y * 0.88 - time * 1.8 + highEnergyGridHash(verticalCell) * 0.8;
    float horizontalPhase = world.x * 1.55 - time * 1.25 + highEnergyGridHash(horizontalCell + 91.0) * 0.8;
    float verticalLocal = fract(verticalPhase);
    float horizontalLocal = fract(horizontalPhase);
    float verticalHead = exp(-verticalLocal * verticalLocal * 210.0);
    float horizontalHead = exp(-horizontalLocal * horizontalLocal * 210.0);
    float verticalTrail = exp(-verticalLocal * 11.0) * (1.0 - smoothstep(0.42, 0.76, verticalLocal));
    float horizontalTrail = exp(-horizontalLocal * 11.0) * (1.0 - smoothstep(0.42, 0.76, horizontalLocal));
    float scanParticles = (vertical * (verticalHead + verticalTrail * 0.58)
                          + horizontal * (horizontalHead + horizontalTrail * 0.58)) * particleGate;

    float horizonGlow = exp(-pow((uv.y - horizon) * 16.0, 2.0)) * (0.015 + gridGlow * 0.10);
    float3 color = mix(float3(0.004, 0.006, 0.018), float3(0.012, 0.009, 0.030), uv.y);
    color += tint * (vertical + horizontal) * visibleGround * farFade * (0.035 + gridGlow * 0.30);
    color += tint * horizonGlow;
    color += tint * scanParticles * (0.20 + gridGlow * 0.86);
    color += float3(0.40, 0.66, 1.0) * scanParticles * (0.10 + gridGlow * 0.28);
    color *= 0.96 + 0.04 * playing;
    color = 1.0 - exp(-max(color, 0.0) * 1.35);
    return float4(saturate(color), 1.0);
}
