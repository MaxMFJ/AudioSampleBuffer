// GeometricMorphShader.metal
// 几何变形效果

#include "ShaderCommon.metal"

fragment float4 geometricMorphFragment(RasterizerData in [[stage_in]],
                                       constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    uv = uv * 2.0 - 1.0;
    float time = uniforms.time.x;
    
    float bassAudio = 0.0, midAudio = 0.0, trebleAudio = 0.0;
    for (int i = 0; i < 15; i++) bassAudio += uniforms.audioData[i].x;
    for (int i = 18; i < 53; i++) midAudio += uniforms.audioData[i].x;
    for (int i = 50; i < 75; i++) trebleAudio += uniforms.audioData[i].x;
    float bassIntensity = min((bassAudio / 15.0) * 1.8, 1.5);
    float midIntensity = min((midAudio / 35.0) * 1.9, 1.5);
    float trebleIntensity = min((trebleAudio / 25.0) * 1.6, 1.5);
    float averageAudio = (bassIntensity + midIntensity + trebleIntensity) / 3.0;
    
    // 🎵 中音控制旋转
    float angle = time * (0.3 + midIntensity * 0.5);
    float2 rotated = float2(
        uv.x * cos(angle) - uv.y * sin(angle),
        uv.x * sin(angle) + uv.y * cos(angle)
    );
    
    // 🎵 低音控制形状复杂度
    float sides = 3.0 + floor(fract(time * 0.1) * 5.0);
    float a = atan2(rotated.y, rotated.x) + 3.14159;
    float r = length(rotated);
    float shapeAngle = 6.28318 / sides;
    float d = cos(floor(0.5 + a / shapeAngle) * shapeAngle - a) * r;
    
    // 低音驱动大小
    float scale = 0.45 + bassIntensity * 0.15;
    float shape = smoothstep(scale + 0.02, scale, d) * (1.0 + averageAudio * 0.5);
    
    // 🎨 动态颜色
    float hue = time * 0.15 + r * 0.3 + averageAudio * 0.4;
    float3 color = hsv2rgb(float3(hue, 0.85, 1.0));
    color *= shape;
    
    // 🌟 高音边缘光
    float edge = smoothstep(scale + 0.03, scale, abs(d - scale));
    color += edge * float3(1.0) * (2.0 + trebleIntensity * 2.0);
    
    return float4(color, 1.0);
}

