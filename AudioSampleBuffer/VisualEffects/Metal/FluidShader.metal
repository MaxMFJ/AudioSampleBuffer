//
//  FluidShader.metal
//  AudioSampleBuffer
//
//  流体模拟效果着色器
//

#include "ShaderCommon.metal"

#pragma mark - 流体模拟效果

fragment float4 fluid_fragment(RasterizerData in [[stage_in]],
                               constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证流体效果不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float time = uniforms.time.x;
    
    // 优化的流体场模拟 - 减少循环次数提高性能
    float2 field = float2(0.0);
    float2 velocity = float2(0.0);
    
    // 减少循环次数从80到16，大幅提升性能
    for (int i = 0; i < 16; i++) {
        // 使用更高效的索引映射
        int audioIndex = i * 5; // 0, 5, 10, 15, ..., 75
        float audioValue = uniforms.audioData[audioIndex].x;
        
        // 预计算角度值
        float angle = float(i) * 0.39269908; // 2π/16 = 0.39269908
        
        // 优化的源点位置计算
        float2 pos = float2(cos(angle + time * 0.5), sin(angle + time * 0.3)) * 0.25 + 0.5;
        
        float2 diff = uv - pos;
        float distSq = dot(diff, diff); // 使用平方距离避免sqrt
        
        // 避免除零和过小值
        if (distSq > 0.001) {
            float force = audioValue * audioValue;
            
            // 优化的衰减函数 - 避免除法
            float falloff = 1.0 / (distSq * 25.0 + 0.01);
            
            // 归一化方向向量
            float2 direction = diff * rsqrt(distSq); // 使用rsqrt代替normalize
            
            field += direction * force * falloff;
            
            // 简化的涡流效果
            float2 vortex = float2(-direction.y, direction.x) * force * falloff * 0.3;
            velocity += vortex;
        }
    }
    
    // 组合场和速度
    float2 totalField = field + velocity;
    float intensity = length(totalField);
    
    // 简化的流体密度计算 - 减少循环次数
    float density = 0.0;
    for (int j = 0; j < 8; j++) { // 从20减少到8
        int audioIdx = j * 10; // 0, 10, 20, ..., 70
        float audioVal = uniforms.audioData[audioIdx].x;
        float x = float(j) * 0.125; // 1/8 = 0.125
        
        // 优化的波形计算
        float wave = sin(uv.x * 15.0 - time * 2.5 + x * 6.28) * audioVal;
        density += wave * exp(-abs(uv.x - x) * 6.0);
    }
    
    // 限制密度范围防止数值溢出
    density = clamp(density, -1.0, 1.0);
    
    // 优化的颜色系统
    float hue = atan2(totalField.y, totalField.x) * 0.15915494 + 0.5; // 1/(2π) = 0.15915494
    float saturation = clamp(intensity * 1.5, 0.0, 1.0);
    
    // 使用更高效的颜色计算
    float3 color = float3(
        sin(hue * 6.28) * saturation + (1.0 - saturation),
        sin(hue * 6.28 + 2.09) * saturation + (1.0 - saturation),
        sin(hue * 6.28 + 4.18) * saturation + (1.0 - saturation)
    );
    
    // 密度影响颜色 - 减少混合强度
    color = mix(color, float3(0.7, 0.8, 0.9), density * 0.2);
    
    // 简化的流动纹理
    float2 flowUV = uv + totalField * 0.08;
    float flowNoise = sin(flowUV.x * 20.0 + time * 1.5) * sin(flowUV.y * 18.0 + time * 1.2);
    
    // 边缘锐化
    float edgeSharpening = smoothstep(0.2, 0.8, intensity);
    color *= (1.0 + edgeSharpening * 0.5);
    
    // 简化的流动效果
    float flow = sin(dot(totalField, float2(0.707, 0.707)) + time * 2.0) * 0.2 + 0.8;
    flow *= (1.0 + flowNoise * 0.15);
    
    // 最终颜色处理
    color = clamp(color * flow * 1.2, 0.0, 1.0);
    
    // 透明度基于强度
    float alpha = clamp(intensity * 1.2 + 0.3, 0.0, 1.0);
    
    return float4(color, alpha);
}

