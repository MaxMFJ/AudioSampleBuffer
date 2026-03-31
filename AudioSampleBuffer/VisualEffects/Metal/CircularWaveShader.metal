//
//  CircularWaveShader.metal
//  AudioSampleBuffer
//
//  环形波浪效果 - 音频响应的圆形波纹扩散
//

#include "ShaderCommon.metal"

// 计算圆形波浪效果
static inline float circularWave(float2 uv, float2 center, float radius, float width, float frequency) {
    float dist = length(uv - center);
    float wave = sin((dist - radius) * frequency);
    float mask = smoothstep(width, 0.0, abs(dist - radius));
    return wave * mask;
}

// 片段着色器 - 环形波浪
fragment float4 circularWaveFragment(RasterizerData in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 center = float2(0.5, 0.5);
    float time = uniforms.time.x;
    
    // 🎵 详细的音频频段分析（参考赛博朋克）
    float bassAudio = 0.0;
    float midAudio = 0.0;
    float trebleAudio = 0.0;
    
    // 低音：0-15
    for (int i = 0; i < 15; i++) {
        bassAudio += uniforms.audioData[i].x;
    }
    bassAudio = (bassAudio / 15.0) * 1.8;
    
    // 中音：18-53
    for (int i = 18; i < 53; i++) {
        midAudio += uniforms.audioData[i].x;
    }
    midAudio = (midAudio / 35.0) * 1.9;
    
    // 高音：50-75
    for (int i = 50; i < 75; i++) {
        trebleAudio += uniforms.audioData[i].x;
    }
    trebleAudio = (trebleAudio / 25.0) * 1.6;
    
    // 限制最大值
    float bassIntensity = min(bassAudio, 1.5);
    float midIntensity = min(midAudio, 1.5);
    float trebleIntensity = min(trebleAudio, 1.5);
    
    float averageAudio = (bassIntensity + midIntensity + trebleIntensity) / 3.0;
    
    // 🎵 多层波浪 - 低音驱动波浪大小和强度
    float totalWave = 0.0;
    const int waveCount = 5;
    
    for (int i = 0; i < waveCount; i++) {
        float phase = float(i) / float(waveCount);
        // 中音控制波浪速度
        float waveSpeed = 0.15 + midIntensity * 0.15;
        float radius = fract(time * waveSpeed + phase);
        
        // 低音控制波浪宽度和强度
        float width = 0.2 * (1.0 - radius) * (0.3 + bassIntensity * 0.7);
        float frequency = 25.0 + bassIntensity * 30.0;
        
        totalWave += circularWave(uv, center, radius, width, frequency);
    }
    
    totalWave /= float(waveCount);
    
    // 🎵 高音驱动的细节波纹
    float dist = length(uv - center);
    float detailWave = sin(dist * (40.0 + trebleIntensity * 30.0) - time * 3.0) * 0.5 + 0.5;
    detailWave *= smoothstep(0.8, 0.0, dist) * trebleIntensity * 1.5;
    
    float finalWave = totalWave * 0.7 + detailWave * 0.3;
    finalWave = clamp(finalWave, 0.0, 1.0);
    
    // 音频响应的动态颜色
    float hue = time * 0.1 + averageAudio * 0.3;
    
    // 低音 - 红橙色系
    float3 bassColor = hsv2rgb(float3(hue, 0.9, 1.0)) * bassIntensity;
    // 中音 - 青绿色系
    float3 midColor = hsv2rgb(float3(hue + 0.35, 0.8, 1.0)) * midIntensity;
    // 高音 - 蓝紫色系
    float3 trebleColor = hsv2rgb(float3(hue + 0.65, 0.95, 1.0)) * trebleIntensity;
    
    float3 color = bassColor + midColor + trebleColor;
    color *= (0.4 + finalWave * 0.6 + averageAudio * 0.3);
    
    // 音频驱动的发光效果
    float brightness = dot(color, float3(0.299, 0.587, 0.114));
    float glowStrength = 0.5 + averageAudio * 1.0;
    color += color * pow(brightness, 2.0) * glowStrength;
    
    // 动态背景
    float vignette = 1.0 - smoothstep(0.3, 1.0, dist);
    float3 bgColor = float3(0.05, 0.1, 0.2) * (1.0 + bassIntensity * 0.5);
    color += bgColor * vignette;
    
    return float4(color, 1.0);
}
