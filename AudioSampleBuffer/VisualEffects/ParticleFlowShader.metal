// ParticleFlowShader.metal
// 竖向条状粒子 - 音频频谱绑定的高性能可视化

#include "ShaderCommon.metal"

// === 简单哈希函数 ===
static inline float hash(float n) {
    return fract(sin(n) * 43758.5453);
}

// === HSV 转 RGB（简化版）===
static inline float3 hsvToRgb(float h, float s, float v) {
    float c = v * s;
    float x = c * (1.0 - abs(fmod(h * 6.0, 2.0) - 1.0));
    float m = v - c;
    
    float3 rgb;
    float h6 = h * 6.0;
    if (h6 < 1.0) rgb = float3(c, x, 0.0);
    else if (h6 < 2.0) rgb = float3(x, c, 0.0);
    else if (h6 < 3.0) rgb = float3(0.0, c, x);
    else if (h6 < 4.0) rgb = float3(0.0, x, c);
    else if (h6 < 5.0) rgb = float3(x, 0.0, c);
    else rgb = float3(c, 0.0, x);
    
    return rgb + m;
}

// === 竖向条状粒子（单个粒子）===
static inline float verticalBarParticle(float2 uv, float barX, float barY, float barWidth, float barHeight) {
    // 水平方向的柔和边缘
    float xDist = abs(uv.x - barX);
    float xAlpha = smoothstep(barWidth, barWidth * 0.3, xDist);
    
    // 垂直方向的渐变
    float yDist = abs(uv.y - barY);
    float yAlpha = smoothstep(barHeight, 0.0, yDist);
    
    return xAlpha * yAlpha;
}

// === 主片段着色器 - 竖向条状粒子可视化 ===
fragment float4 particleFlowFragment(RasterizerData in [[stage_in]],
                                     constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float time = uniforms.time.x;
    float aspectRatio = uniforms.resolution.z;
    
    // === 增强的流动背景动画 ===
    float3 color = float3(0.01, 0.02, 0.05); // 基础深色
    
    // 多层波动渐变 - 更强的流动感
    float flow1 = sin(uv.y * 4.0 + time * 0.8) * 0.5 + 0.5;
    float flow2 = sin(uv.y * 6.0 - time * 0.6 + uv.x * 3.0) * 0.5 + 0.5;
    float flow3 = sin(uv.x * 2.0 + uv.y * 2.0 + time * 0.4) * 0.5 + 0.5;
    
    // 更鲜艳的背景流动色彩
    float3 flowColor1 = hsvToRgb(time * 0.15, 0.5, 0.06); // 更高饱和度和亮度
    float3 flowColor2 = hsvToRgb(time * 0.15 + 0.4, 0.4, 0.04);
    float3 flowColor3 = hsvToRgb(time * 0.15 + 0.7, 0.35, 0.03);
    
    color += flowColor1 * flow1 + flowColor2 * flow2 + flowColor3 * flow3;
    
    // 音频平均值
    float avgAudio = 0.0;
    for (int i = 0; i < 20; i++) {
        avgAudio += uniforms.audioData[i].x;
    }
    avgAudio = saturate(avgAudio / 20.0 * 2.5);
    
    // 多条水平流光（更明显）
    float stripe1 = sin((uv.y - time * 0.3) * 15.0) * 0.5 + 0.5;
    stripe1 = pow(stripe1, 6.0); // 细线
    color += hsvToRgb(time * 0.2, 0.6, avgAudio * 0.2) * stripe1;
    
    float stripe2 = sin((uv.y + time * 0.25) * 12.0 + uv.x * 5.0) * 0.5 + 0.5;
    stripe2 = pow(stripe2, 5.0);
    color += hsvToRgb(time * 0.2 + 0.5, 0.5, avgAudio * 0.15) * stripe2;
    
    // 脉冲圆环（音频驱动）
    if (avgAudio > 0.3) {
        float pulseTime = fract(time * 0.8);
        float2 center = float2(0.5, 0.5);
        float dist = length((uv - center) * float2(aspectRatio, 1.0));
        float ring = abs(dist - pulseTime * 0.8) / 0.05;
        float pulse = exp(-ring * ring) * (1.0 - pulseTime) * avgAudio;
        color += hsvToRgb(time * 0.1, 0.7, 0.2) * pulse;
    }
    
    // === 竖向条状粒子系统（大幅减少）===
    int numBars = 10; // 减少到10个竖条
    float barSpacing = 1.0 / float(numBars);
    
    for (int i = 0; i < numBars; i++) {
        float barIndex = float(i);
        
        // 每个条绑定到频谱数据
        int audioIndex = int(barIndex / float(numBars) * 50.0); // 采样50个频谱
        float audioValue = uniforms.audioData[audioIndex].x;
        
        // 条的X位置（交错分布）
        float barX = (barIndex + 0.5) * barSpacing;
        
        // 宽高比校正
        barX = (barX - 0.5) * aspectRatio + 0.5;
        
        // 条的宽度 - 稍宽一些
        float barWidth = barSpacing * 0.35 * aspectRatio;
        
        // 每个条只有2-3个粒子
        int particlesPerBar = int(1 + audioValue * 2.0); // 1-3个
        
        for (int j = 0; j < 3; j++) {
            if (j >= particlesPerBar) break;
            
            float particleId = float(j);
            float seed = hash(barIndex * 10.0 + particleId);
            
            // 粒子向上运动
            float particleLife = fract(time * (0.25 + audioValue * 0.3) + seed * 2.0);
            float barY = particleLife * 1.3 - 0.15; // 从底部到顶部
            
            // 粒子高度（拖尾长度）
            float barHeight = 0.1 + audioValue * 0.2;
            
            // 绘制竖向条状粒子
            float particle = verticalBarParticle(uv, barX, barY, barWidth, barHeight);
            
            if (particle > 0.0) {
                // 颜色：根据音频和位置
                float hue = barIndex / float(numBars) * 0.6 + time * 0.08;
                float saturation = 0.7 + audioValue * 0.25;
                float brightness = 0.5 + audioValue * 0.6 + particleLife * 0.2;
                
                float3 particleColor = hsvToRgb(hue, saturation, brightness);
                
                // 添加到颜色，带渐变透明
                float alpha = (1.0 - particleLife * 0.8) * particle;
                color += particleColor * alpha * (0.7 + audioValue * 0.5);
            }
        }
    }
    
    // === 极简后处理 ===
    color = pow(color, float3(0.9)); // 伽马校正
    
    return float4(saturate(color), 1.0);
}
