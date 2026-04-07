//
//  ShaderCommon.metal
//  AudioSampleBuffer
//
//  Metal着色器公共定义
//

#ifndef ShaderCommon_metal
#define ShaderCommon_metal

#include <metal_stdlib>
using namespace metal;

// 顶点结构体
struct Vertex {
    float2 position [[attribute(0)]];
    float4 color [[attribute(1)]];
    float2 texCoord [[attribute(2)]];
};

// 光栅化数据
struct RasterizerData {
    float4 position [[position]];
    float4 color;
    float2 texCoord;
};

// 统一缓冲区
struct Uniforms {
    float4x4 projectionMatrix;
    float4x4 modelViewMatrix;
    float4 time;
    float4 resolution;
    float4 audioData[80];
    float4 galaxyParams1; // 星系参数1: (coreIntensity, edgeIntensity, rotationSpeed, glowRadius)
    float4 galaxyParams2; // 星系参数2: (colorShiftSpeed, nebulaIntensity, pulseStrength, audioSensitivity)
    float4 galaxyParams3; // 星系参数3: (starDensity, spiralArms, colorTheme, reserved)
    float4 cyberpunkControls; // 赛博朋克控制: (enableClimaxEffect, showDebugBars, enableGrid, backgroundMode)
    float4 cyberpunkFrequencyControls; // 赛博朋克频段控制: (enableBass, enableMid, enableTreble, reserved)
    float4 cyberpunkBackgroundParams; // 赛博朋克背景参数: (solidColorR, solidColorG, solidColorB, intensity)
};

// AI 增强的 Uniforms（用于丁达尔效应等需要动态颜色的效果）
struct UniformsAI {
    float4x4 projectionMatrix;
    float4x4 modelViewMatrix;
    float4 time;
    float4 resolution;
    float4 audioData[80];
    float4 galaxyParams1;
    float4 galaxyParams2;
    float4 galaxyParams3;
    float4 cyberpunkControls;
    float4 cyberpunkFrequencyControls;
    float4 cyberpunkBackgroundParams;
    
    // AI 音乐分析参数
    float4 aiParams1;  // (bpm/100, energy, danceability, valence)
    float4 aiParams2;  // (animSpeed, brightness, triggerSens, atmoIntensity)
    
    // AI 动态颜色（RGB + reserved）
    float4 aiColorAtmosphere;
    float4 aiColorVolumetricBeam;
    float4 aiColorTopLightArray;
    float4 aiColorLaserFanBlue;
    float4 aiColorLaserFanGreen;
    float4 aiColorRotatingBeam;
    float4 aiColorRotatingBeamExtra;   // 额外6条旋转细丝颜色
    float4 aiColorEdgeLight;           // 底部边缘描绘光颜色
    float4 aiColorCoronaFilaments;     // 外围长丝 + 放射日冕丝颜色
    float4 aiColorPulseRing;           // 脉冲环颜色
};

#pragma mark - 辅助函数（使用static inline避免重复符号）

// 宽高比校正 + 缩放函数
// Metal视图是正方形(926x926)，但需要缩放特效使其适合屏幕宽度(428)
static inline float2 aspectCorrect(float2 uv, float4 resolution) {
    // resolution.x = drawableWidth (926*3 = 2778)
    // resolution.y = drawableHeight (926*3 = 2778)
    // resolution.z = aspectRatio (should be screen width/height, e.g., 428/926 ≈ 0.462)
    
    // 计算缩放因子：视图是正方形，但我们希望特效基于屏幕宽度
    // 如果 resolution.z < 1.0（竖屏），说明宽度 < 高度
    // 我们需要将特效缩小到 resolution.z 的比例
    float scaleFactor = (resolution.z < 1.0) ? resolution.z : 1.0;
    
    // 转换到中心坐标系 [-0.5, 0.5]
    float2 pos = uv - 0.5;
    
    // 应用缩放（缩小特效）
    pos /= scaleFactor;
    
    // 转回UV坐标 [0, 1]
    return pos + 0.5;
}

// 通用顶点输入结构（用于全屏四边形）
struct VertexIn {
    float2 position;
    float2 texCoord;
};

// 通用顶点输出结构
struct VertexOut {
    float4 position [[position]];
    float2 texCoord;
};

// 噪声函数
static inline float noise(float2 uv) {
    return fract(sin(dot(uv, float2(12.9898, 78.233))) * 43758.5453);
}

// 分形噪声
static inline float fractalNoise(float2 uv, int octaves) {
    float value = 0.0;
    float amplitude = 0.5;
    
    for (int i = 0; i < octaves; i++) {
        value += noise(uv) * amplitude;
        uv *= 2.0;
        amplitude *= 0.5;
    }
    
    return value;
}

// HSV 转 RGB（无分支版本，GPU SIMD 友好）
static inline float3 hsv2rgb(float3 hsv) {
    float3 rgb = clamp(
        abs(fmod(hsv.x * 6.0 + float3(0.0, 4.0, 2.0), 6.0) - 3.0) - 1.0,
        0.0, 1.0
    );
    return hsv.z * mix(float3(1.0), rgb, hsv.y);
}

// 角度转弧度
static inline float radians(float degrees) {
    return degrees * M_PI_F / 180.0;
}

#endif /* ShaderCommon_metal */

