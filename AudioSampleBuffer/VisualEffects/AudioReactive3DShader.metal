// AudioReactive3DShader.metal
// 音频响应3D效果

#include "ShaderCommon.metal"

fragment float4 audioReactive3DFragment(RasterizerData in [[stage_in]],
                                        constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    uv = uv * 2.0 - 1.0;
    float time = uniforms.time.x;
    
    // 🎵 音频频段分析
    float bassAudio = 0.0, midAudio = 0.0, trebleAudio = 0.0;
    for (int i = 0; i < 15; i++) bassAudio += uniforms.audioData[i].x;
    for (int i = 18; i < 53; i++) midAudio += uniforms.audioData[i].x;
    for (int i = 50; i < 75; i++) trebleAudio += uniforms.audioData[i].x;
    float bassIntensity = min((bassAudio / 15.0) * 1.8, 1.5);
    float midIntensity = min((midAudio / 35.0) * 1.9, 1.5);
    float trebleIntensity = min((trebleAudio / 25.0) * 1.6, 1.5);
    float averageAudio = (bassIntensity + midIntensity + trebleIntensity) / 3.0;
    
    // 🎵 中音控制旋转速度
    float angle = time * (0.2 + midIntensity * 0.4);
    float2 rotated = float2(
        uv.x * cos(angle) - uv.y * sin(angle),
        uv.x * sin(angle) + uv.y * cos(angle)
    );
    
    // 🎵 低音驱动的 3D 几何变形
    float dist = length(rotated);
    float frequency = 6.0 + bassIntensity * 6.0;
    float shape = smoothstep(0.25, 0.3, abs(sin(dist * frequency - time * 2.0)));
    shape *= (0.4 + bassIntensity * 0.8 + averageAudio * 0.3);
    
    // 🎨 动态颜色
    float hue = time * 0.1 + dist * 0.3 + averageAudio * 0.4;
    float3 color = hsv2rgb(float3(hue, 0.8, 1.0));
    color *= shape;
    
    // 🌟 高音边缘光
    float edge = smoothstep(0.32, 0.3, abs(dist * frequency - time * 2.0));
    color += edge * float3(1.0) * trebleIntensity * 2.0;
    
    return float4(color, 1.0);
}

