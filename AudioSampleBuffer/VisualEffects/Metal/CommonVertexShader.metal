//
//  CommonVertexShader.metal
//  AudioSampleBuffer
//
//  通用顶点着色器（只定义一次，避免重复符号）
//

#include "ShaderCommon.metal"

#pragma mark - 通用顶点着色器

// 全屏四边形顶点着色器（被所有特效共享）
vertex RasterizerData neon_vertex(uint vertexID [[vertex_id]],
                                  constant Uniforms& uniforms [[buffer(0)]]) {
    RasterizerData out;
    
    // 创建全屏四边形
    float2 positions[4] = {
        float2(-1.0, -1.0),
        float2( 1.0, -1.0),
        float2(-1.0,  1.0),
        float2( 1.0,  1.0)
    };
    
    float2 texCoords[4] = {
        float2(0.0, 1.0),
        float2(1.0, 1.0),
        float2(0.0, 0.0),
        float2(1.0, 0.0)
    };
    
    out.position = float4(positions[vertexID], 0.0, 1.0);
    out.texCoord = texCoords[vertexID];
    out.color = float4(1.0);
    
    return out;
}

