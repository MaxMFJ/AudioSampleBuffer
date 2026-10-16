// Direct3D 11 wallpaper pixel shader.  The constant buffer is deliberately
// flat so a native caller can fill it without mirroring any Swift/Metal types.
// effectIndex: 0 cellular membrane, 1 Tyndall stage, 2 cover dots, 3 hex grid.

cbuffer WallpaperConstants : register(b0)
{
    float time;
    float low;
    float mid;
    float high;
    float guitar;
    float piano;
    float drums;
    float aspect;
    uint effectIndex;
    float hasArtwork;
    float2 _padding;
    float4 bands[32];
    float4 viewport; // physical width/height, DPI scale, playing
    float4 dynamics; // beat envelope/age, guitar peak, smoothed piano
    float4 animationStarts;
    float4 animationStrengths;
    float4 animationPeak;
    float4 laserGeometry;
    float4 laserMotion;
    float4 laserAppearance;
    float4 hiveWaves[8];
    float4 coverRotation;
    float4 coverPointer;
    float4 tyndallBands;
    float4 instrumentEnvelopes;
    float4 dspFeatureSignals;
    float4 dspFeatureTexture;
};

Texture2D artwork : register(t0);
SamplerState artworkSampler : register(s0);

struct VSOut { float4 position : SV_Position; float2 uv : TEXCOORD0; };

VSOut wallpaperVS(uint vertexID : SV_VertexID)
{
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VSOut o;
    o.position = float4(p[vertexID], 0, 1);
    o.uv = float2(p[vertexID].x * 0.5 + 0.5, 0.5 - p[vertexID].y * 0.5);
    return o;
}

float hash21(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float bandAt(float x)
{
    uint index = (uint)clamp(x, 0.0, 127.0);
    return bands[index >> 2][index & 3];
}

#include "CellularHive.hlsli"
#include "Tyndall.hlsli"
#include "CoverParticles.hlsli"

// Restore the original WPF hexagon geometry, palette and alpha composition.
// All dimensions are in logical desktop points, matching DrawingContext.
float3 hexPalette(int i) {
    const float3 palette[5] = {float3(73,226,205),float3(103,122,255),float3(187,91,233),
                                float3(255,173,110),float3(110,185,255)};
    return palette[abs(i)%5]/255.0;
}
float3 hexMorph(float2 uv) {
    float2 size=viewport.xy/max(viewport.z,1);
    float2 pixel=uv*size;
    float radius=clamp(min(size.x/31,size.y/18)*.47,8,40);
    float dx=radius*1.78, dy=radius*1.54;
    int row0=(int)floor(pixel.y/dy);
    float3 color=float3(3,7,18)/255.0;
    [unroll] for(int ry=-1;ry<=1;++ry) {
        int row=row0+ry;
        if(row < -1 || row >= (int)(size.y/dy)+2) continue;
        float offset=row%2==0 ? 0 : dx/2;
        int col0=(int)floor((pixel.x-offset)/dx);
        [unroll] for(int cx=-1;cx<=1;++cx) {
            int col=col0+cx;
            if(col < -1 || col >= (int)(size.x/dx)+2) continue;
            float2 p=pixel-float2(col*dx+offset,row*dy);
            // Six vertices at PI/6 + k*PI/3, exactly as the original StreamGeometry.
            float distance=-1e5;
            [unroll] for(int side=0;side<6;++side) {
                float angle=side*1.0471975512;
                distance=max(distance,dot(p,float2(cos(angle),sin(angle)))-radius*.8660254038);
            }
            float aa=max(fwidth(distance),.001);
            float fill=1-smoothstep(-aa,aa,distance);
            float stroke=1-smoothstep(.5-aa,.5+aa,abs(distance));
            float b=bandAt(abs(col*5+row*11)%48);
            float pulse=(sin(time*.65+col*.23+row*.29)+1)*.5;
            float3 tint=hexPalette(col+row*3);
            color=lerp(color,tint,fill*floor(10+pulse*20+b*150)/255.0);
            color=lerp(color,tint,stroke*floor(18+b*130)/255.0);
        }
    }
    return color;
}
float4 wallpaperPS(VSOut input) : SV_Target {
    float3 color=float3(0,0,0);
    if(effectIndex==0) color=cellular(input.uv);
    else if(effectIndex==1) color=tyndall(input.uv);
    else if(effectIndex==3) color=hexMorph(input.uv);
    // Mac's view is bgra8Unorm; its effect output is already display color.
    // Do not apply a second global gamma curve to the original shader math.
    return float4(saturate(color),1);
}
