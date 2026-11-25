#include <metal_stdlib>
using namespace metal;

struct VectorAssaultDesktopVertex {
    float2 position;
    float4 color;
};
struct VectorAssaultDesktopOutput {
    float4 position [[position]];
    float4 color;
};

vertex VectorAssaultDesktopOutput vectorAssaultDesktopVertex(
    const device VectorAssaultDesktopVertex *vertices [[buffer(0)]],
    uint index [[vertex_id]]) {
    VectorAssaultDesktopOutput out;
    out.position = float4(vertices[index].position, 0.0, 1.0);
    out.color = vertices[index].color;
    return out;
}

fragment float4 vectorAssaultDesktopFragment(VectorAssaultDesktopOutput in [[stage_in]]) {
    return in.color;
}
