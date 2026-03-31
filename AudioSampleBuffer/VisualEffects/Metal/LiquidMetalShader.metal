// LiquidMetalShader.metal
// 液态金属效果

#include "ShaderCommon.metal"

fragment float4 liquidMetalFragment(RasterizerData in [[stage_in]],
                                    constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    float bassAudio = 0.0, midAudio = 0.0, trebleAudio = 0.0;
    for (int i = 0; i < 15; i++) bassAudio += uniforms.audioData[i].x;
    for (int i = 18; i < 53; i++) midAudio += uniforms.audioData[i].x;
    for (int i = 50; i < 75; i++) trebleAudio += uniforms.audioData[i].x;
    float bassIntensity = min((bassAudio / 15.0) * 1.8, 1.5);
    float midIntensity = min((midAudio / 35.0) * 1.9, 1.5);
    float trebleIntensity = min((trebleAudio / 25.0) * 1.6, 1.5);
    float averageAudio = (bassIntensity + midIntensity + trebleIntensity) / 3.0;
    
    // 🎵 低音驱动的液态波动
    float waveFreq1 = 8.0 + bassIntensity * 5.0;
    float waveFreq2 = 12.0 + bassIntensity * 8.0;
    float waveSpeed = 1.5 + midIntensity * 1.0;
    float wave1 = sin(uv.x * waveFreq1 + time * waveSpeed) * cos(uv.y * (waveFreq1 * 0.8) - time * waveSpeed * 0.8);
    float wave2 = sin(uv.x * waveFreq2 - time * waveSpeed * 1.2) * sin(uv.y * waveFreq2 + time * waveSpeed);
    float surface = (wave1 + wave2) * 0.5 * (0.4 + bassIntensity * 0.8);
    
    // 法线计算（简化）
    float2 normal = float2(
        cos(uv.x * 10.0 + time * 2.0),
        cos(uv.y * 8.0 - time * 1.5)
    );
    normal = normalize(normal);
    
    // 反射效果
    float reflection = dot(normal, float2(0.7, 0.7));
    reflection = reflection * 0.5 + 0.5;
    
    // 🎨 音频响应的金属色
    float3 baseColor = float3(0.65, 0.7, 0.75) * (1.0 + averageAudio * 0.3);
    float3 color = baseColor * reflection;
    
    // 🌟 高音驱动的高光
    float specularPower = 15.0 + trebleIntensity * 15.0;
    float specular = pow(reflection, specularPower);
    color += specular * (2.0 + trebleIntensity * 2.0);
    
    // 🎵 动态流动色彩
    float flowHue = fract(time * (0.08 + midIntensity * 0.1) + uv.x * 0.3 + averageAudio * 0.2);
    float3 flowColor = hsv2rgb(float3(flowHue, 0.25 + bassIntensity * 0.3, 0.9));
    float mixAmount = 0.15 + midIntensity * 0.2;
    color = mix(color, flowColor, mixAmount);
    
    // 增强音频响应
    color *= (0.75 + averageAudio * 0.5);
    
    return float4(color, 1.0);
}

