//
//  Waveform3DShader.metal
//  AudioSampleBuffer
//
//  3D波形效果着色器
//

#include "ShaderCommon.metal"

#pragma mark - 3D波形效果

fragment float4 waveform3d_fragment(RasterizerData in [[stage_in]],
                                    constant Uniforms& uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float time = uniforms.time.x;
    
    // 高精度3D波形效果
    float waveform = 0.0;
    float maxWave = 0.0;
    
    // 增加采样点数量，提高清晰度
    for (int i = 0; i < 40; i++) {
        float audioValue = uniforms.audioData[i * 2].x;
        float x = float(i) / 40.0;
        
        // 高频波形，更锐利的边缘
        float wave = sin((uv.x - x) * 80.0 + time * 4.0) * audioValue;
        
        // 更精确的衰减函数
        float falloff = exp(-pow(abs(uv.x - x) * 15.0, 2.0));
        wave *= falloff;
        
        waveform += wave;
        maxWave = max(maxWave, abs(wave));
    }
    
    // 高清晰度3D深度效果
    float depth1 = sin(uv.y * 15.0 + time * 1.2) * 0.15;
    float depth2 = sin(uv.y * 25.0 - time * 0.8) * 0.1;
    float totalDepth = (depth1 + depth2) * 0.5 + 0.7;
    
    waveform *= totalDepth;
    
    // 额外的立体层次
    float layer1 = sin(uv.x * 30.0 + time * 2.0) * maxWave * 0.3;
    float layer2 = sin(uv.y * 20.0 + time * 1.5) * maxWave * 0.2;
    
    float finalWave = waveform + layer1 + layer2;
    
    // 增强的颜色系统
    float intensity = abs(finalWave);
    float3 baseColor = float3(0.1, 0.3, 0.8);
    float3 waveColor = float3(
        0.8 + finalWave * 3.0,
        0.4 + finalWave * 2.5,
        0.2 + finalWave * 2.0
    );
    
    float3 color = mix(baseColor, waveColor, intensity * 2.0);
    
    // 边缘锐化
    float edgeEnhancement = smoothstep(0.1, 0.8, intensity);
    color *= (1.0 + edgeEnhancement * 0.5);
    
    // 亮度和对比度增强
    color = clamp(color * 1.6, 0.0, 1.0);
    
    // 高精度alpha
    float alpha = clamp(intensity + 0.3, 0.0, 1.0);
    
    return float4(color, alpha);
}

