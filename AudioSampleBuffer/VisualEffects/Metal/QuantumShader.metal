//
//  QuantumShader.metal
//  AudioSampleBuffer
//
//  量子场效果着色器
//

#include "ShaderCommon.metal"

#pragma mark - 量子场效果

fragment float4 quantum_fragment(RasterizerData in [[stage_in]],
                                 constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证量子场效果不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 量子涨落
    float quantum = 0.0;
    
    for (int i = 0; i < 10; i++) {
        float audioValue = uniforms.audioData[i * 8].x;
        float phase = float(i) * 0.628 + time * (1.0 + audioValue);
        
        float2 center = float2(
            sin(phase) * 0.3 + 0.5,
            cos(phase * 1.3) * 0.3 + 0.5
        );
        
        float dist = length(uv - center);
        quantum += audioValue / (dist * 10.0 + 0.1) * sin(phase * 5.0);
    }
    
    // 量子干涉图案
    float interference = sin(quantum * 50.0) * sin(quantum * 30.0 + time);
    
    // 能量场颜色
    float3 color = float3(
        abs(sin(quantum * 2.0 + time)),
        abs(sin(quantum * 2.0 + time + 2.09)),
        abs(sin(quantum * 2.0 + time + 4.18))
    );
    
    float alpha = smoothstep(0.0, 1.0, abs(interference) * 2.0);
    
    return float4(color, alpha);
}

