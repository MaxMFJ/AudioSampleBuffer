//
//  NeonShader.metal
//  AudioSampleBuffer
//
//  霓虹发光效果着色器
//

#include "ShaderCommon.metal"

#pragma mark - 霓虹发光效果

fragment float4 neon_fragment(RasterizerData in [[stage_in]],
                              constant Uniforms& uniforms [[buffer(0)]]) {
    // 宽高比校正 - 保证圆形不变形
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 center = float2(0.5, 0.5);
    float time = uniforms.time.x;
    
    // 创建高精度环形频谱
    float angle = atan2(uv.y - center.y, uv.x - center.x);
    float radius = length(uv - center);
    
    // 将角度转换为频谱索引
    float normalizedAngle = (angle + M_PI_F) / (2.0 * M_PI_F);
    int spectrumIndex = int(normalizedAngle * 79.0);
    float audioValue = uniforms.audioData[spectrumIndex].x;
    
    // 高清晰度霓虹发光效果
    float baseRadius = 0.35;
    float glowRadius = baseRadius + audioValue * 0.15;
    
    // 多层发光效果
    float innerGlow = exp(-abs(radius - glowRadius) * 50.0) * 0.8;
    float middleGlow = exp(-abs(radius - glowRadius) * 20.0) * 0.4;
    float outerGlow = exp(-abs(radius - glowRadius) * 8.0) * 0.2;
    
    float totalGlow = innerGlow + middleGlow + outerGlow;
    
    // 更精细的彩虹色
    float hue = normalizedAngle + time * 0.5;
    float3 color = float3(
        sin(hue * 6.28) * 0.5 + 0.5,
        sin(hue * 6.28 + 2.09) * 0.5 + 0.5,
        sin(hue * 6.28 + 4.18) * 0.5 + 0.5
    );
    
    // 增强饱和度和亮度
    color = color * 1.5;
    color = clamp(color, 0.0, 1.0);
    
    // 音频响应的亮度调制
    float brightness = 0.8 + audioValue * 0.4;
    
    // 高频闪烁效果
    float flicker = sin(time * 15.0 + audioValue * 20.0) * 0.1 + 0.9;
    
    // 径向渐变增强
    float radialEnhancement = smoothstep(0.1, 0.6, 1.0 - radius);
    
    totalGlow *= brightness * flicker * radialEnhancement;
    
    return float4(color * totalGlow, totalGlow);
}

