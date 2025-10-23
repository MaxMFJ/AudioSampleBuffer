// FireworksShader.metal
// 烟花效果

#include "ShaderCommon.metal"

static inline float fireworkRandom(float2 st) {
    return fract(sin(dot(st, float2(12.9898, 78.233))) * 43758.5453);
}

fragment float4 fireworksFragment(RasterizerData in [[stage_in]],
                                  constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 🎵 音频频段分析
    float bassAudio = 0.0, midAudio = 0.0, trebleAudio = 0.0;
    for (int i = 0; i < 15; i++) bassAudio += uniforms.audioData[i].x;
    for (int i = 18; i < 53; i++) midAudio += uniforms.audioData[i].x;
    for (int i = 50; i < 75; i++) trebleAudio += uniforms.audioData[i].x;
    
    float bassIntensity = min((bassAudio / 15.0) * 1.8, 1.5);
    float midIntensity = min((midAudio / 35.0) * 1.9, 1.5);
    float trebleIntensity = min((trebleAudio / 25.0) * 1.6, 1.5);
    
    // 夜空背景
    float3 color = float3(0.01, 0.01, 0.05) * (1.0 + uv.y * 0.3);
    
    float averageAudio = (bassIntensity + midIntensity + trebleIntensity) / 3.0;
    
    // 🎵 低音触发更多烟花
    int fireworkCount = 3 + int(bassIntensity * 2.0);
    for (int i = 0; i < 5; i++) {
        if (i >= fireworkCount) break;
        
        float id = float(i);
        // 低音加快发射频率
        float launchSpeed = 0.4 + bassIntensity * 0.3;
        float launchTime = floor(time * launchSpeed + id * 0.5);
        float t = fract(time * launchSpeed + id * 0.5);
        
        if (t < 0.85) {
            float2 center = float2(fireworkRandom(float2(launchTime, id)), 0.15 + t * 0.7);
            
            // 中音控制粒子数量
            int particleCount = int(15.0 + midIntensity * 10.0);
            for (int j = 0; j < 25; j++) {
                if (j >= particleCount) break;
                
                float particleId = float(j) / float(particleCount);
                float angle = particleId * 6.28318;
                // 低音增大爆炸半径
                float radius = t * (0.25 + bassIntensity * 0.2);
                
                float2 particlePos = center + float2(cos(angle), sin(angle)) * radius;
                particlePos.y -= t * t * 0.15; // 重力
                
                float dist = length(uv - particlePos);
                // 高音增加亮度和锐度
                float sharpness = 250.0 + trebleIntensity * 150.0;
                float brightness = exp(-dist * sharpness) * (1.0 - t * 0.8);
                
                // 动态颜色
                float hue = particleId + time * 0.15 + averageAudio * 0.3;
                float3 particleColor = hsv2rgb(float3(hue, 0.95, 1.0));
                
                // 高音闪烁
                brightness *= (0.8 + trebleIntensity * 0.2);
                
                color += particleColor * brightness * (1.0 + averageAudio * 0.5);
            }
        }
    }
    
    // 音频脉冲背景
    color *= (0.9 + averageAudio * 0.4);
    
    return float4(color, 1.0);
}

