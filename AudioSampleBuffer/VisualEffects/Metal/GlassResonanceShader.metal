#include "ShaderCommon.metal"

// A closed (2,3) torus knot, not a logo. 160 x 28 indexed quads, no ray marching.
// galaxyParams1 = low, mid, high, impact; galaxyParams2 = phase, strain, impactAge, energy.
static float3 glassRotate(float3 p, float phase, constant Uniforms &u) {
    float c=cos(phase), s=sin(phase);
    p=float3(c*p.x+s*p.z,p.y,-s*p.x+c*p.z);
    float a=-0.32+0.12*sin(phase*0.7)+u.cyberpunkControls.y;
    p=float3(p.x,cos(a)*p.y-sin(a)*p.z,sin(a)*p.y+cos(a)*p.z);
    float yaw=u.cyberpunkControls.x;
    return float3(cos(yaw)*p.x+sin(yaw)*p.z,p.y,-sin(yaw)*p.x+cos(yaw)*p.z);
}
static float3 glassCenter(float t, constant Uniforms &u) {
    float low=u.galaxyParams1.x, mid=u.galaxyParams1.y;
    float phase=u.galaxyParams2.x, strain=u.galaxyParams2.y;
    float r=0.80+0.27*cos(3*t);
    float3 p=float3(r*cos(2*t), r*sin(2*t), 0.32*sin(3*t));
    p.xy*=1.0+0.28*low;
    p.z+=mid*0.34*sin(5*t+phase*2)+strain*0.24*sin(9*t-phase);
    float wave=sin(4*t-u.galaxyParams2.z*15)*u.galaxyParams1.w;
    p+=normalize(float3(p.xy,0.3))*wave*0.22;
    float twist=mid*0.68*sin(3*t+phase)+strain*0.30*sin(7*t);
    p.xy=float2(cos(twist)*p.x-sin(twist)*p.y,sin(twist)*p.x+cos(twist)*p.y);
    return p;
}
static float3 glassSurface(float t, float v, constant Uniforms &u) {
    float3 center=glassCenter(t,u);
    float3 tangent=normalize(glassCenter(t+0.002,u)-glassCenter(t-0.002,u));
    float3 b=normalize(cross(tangent,float3(0,0,1)));
    float3 n=cross(b,tangent);
    float radius=0.135*(1+u.galaxyParams1.x*0.72);
    // Tension pinches the tube into alternating liquid seams without topology breaks.
    radius*=1+0.12*sin(3*t+u.galaxyParams2.x)+u.galaxyParams2.y*0.42*sin(11*t+u.galaxyParams2.x*3)
              +u.galaxyParams1.z*0.075*sin(19*t+5*v+u.galaxyParams2.x*5);
    float oval=1+u.galaxyParams1.y*0.48;
    return center+radius*(cos(v)*n*oval+sin(v)*b/oval);
}
struct GlassVertex {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 center;
};
vertex GlassVertex glassResonanceVertex(uint id [[vertex_id]],constant Uniforms &u [[buffer(0)]]) {
    float t=float(id/29)*(2*M_PI_F/160), v=float(id%29)*(2*M_PI_F/28);
    float3 p=glassSurface(t,v,u);
    float3 du=glassSurface(t+0.002,v,u)-glassSurface(t-0.002,v,u);
    float3 dv=glassSurface(t,v+0.002,u)-glassSurface(t,v-0.002,u);
    float3 n=normalize(cross(du,dv));
    float3 center=glassCenter(t,u);
    if(dot(n,p-center)<0) n=-n;
    float phase=u.galaxyParams2.x;
    p=glassRotate(p,phase,u); n=glassRotate(n,phase,u); center=glassRotate(center,phase,u);
    float z=4.4-p.z;
    float squareScale=min(u.resolution.z,1.0f);
    GlassVertex o;
    float cameraZoom=max(u.cyberpunkFrequencyControls.x,0.2f);
    o.position=float4(p.xy*2.80*squareScale*cameraZoom, (z-0.1)*10/(10-0.1), z);
    o.world=p; o.normal=n; o.center=center; return o;
}
vertex RasterizerData glassFullscreenVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2);
    RasterizerData o; o.position=float4(p*2-1,0,1); o.texCoord=float2(p.x,1-p.y); o.color=1; return o;
}
// Procedural studio lighting is shared by reflection and refraction: warm softbox,
// cool rim, broad neutral ceiling. No downloaded environment or bitmap dependency.
static float3 glassStudio(float3 d, float high) {
    d=normalize(d);
    float key=exp(-pow((d.x+0.42)/0.23,2.0f)-pow((d.y-0.54)/0.58,4.0f));
    float rim=exp(-pow((d.x-0.65)/0.085,2.0f)-pow((d.y+0.10)/0.75,4.0f));
    float top=pow(max(dot(d,normalize(float3(0,0.8,0.4))),0.0f),18.0f);
    float strip=exp(-pow((d.y+0.38+0.14*d.x)/0.035,2.0f))*smoothstep(-0.8,0.2,d.z);
    return float3(0.018,0.024,0.032)+
      float3(1.0,0.91,0.78)*key*3.6+
      float3(0.40,0.69,1.0)*rim*(2.4+high*1.3)+
      float3(0.68,0.79,0.92)*top*1.0+float3(1.0,0.61,0.32)*strip*1.8;
}
constexpr sampler glassSampler(coord::normalized,address::clamp_to_edge,filter::linear);
fragment float4 glassBackFragment(GlassVertex in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float3 n=normalize(in.normal), view=normalize(float3(0,0,4.4)-in.world);
    float edge=pow(1-abs(dot(n,view)),3.0f);
    return float4(glassStudio(reflect(-view,n),u.galaxyParams1.z)*(0.035+0.28*edge),1);
}
fragment float4 glassResonanceFragment(GlassVertex in [[stage_in]],constant Uniforms &u [[buffer(0)]],
                                      texture2d<float> rear [[texture(0)]]) {
    float3 n=normalize(in.normal), incident=normalize(in.world-float3(0,0,4.4));
    n=faceforward(n,incident,n);
    float facing=clamp(-dot(incident,n),0.0f,1.0f);
    float fresnel=0.04+0.96*pow(1-facing,5.0f);
    float high=u.galaxyParams1.z, strain=u.galaxyParams2.y;
    float spread=0.006+high*0.018+strain*0.032;
    float3 transmission=0;
    float thickness=2*length(in.world-in.center)*max(facing,0.12f);
    for(uint c=0;c<3;c++) {
        float ior=1.46+(float(c)-1)*spread;
        float3 inside=refract(incident,n,1/ior);
        // Local tube chord approximates the exit interface. This is environment
        // transmission, not a full scene ray tracer (bounded mobile cost).
        float3 exitNormal=normalize(n+inside*(2*max(-dot(n,inside),0.05f)));
        float3 outgoing=refract(inside,-exitNormal,ior);
        if(dot(outgoing,outgoing)<0.001) outgoing=reflect(inside,-exitNormal);
        transmission[c]=glassStudio(outgoing,high)[c];
    }
    transmission*=exp(-float3(0.48,0.22,0.13)*thickness*2.0);
    float3 reflection=glassStudio(reflect(incident,n),high);
    float2 screenUV=in.position.xy/u.resolution.xy;
    float2 bend=n.xy*thickness*0.10*min(u.resolution.z,1.0f);
    float3 through;
    for(uint c=0;c<3;c++) {
        through[c]=rear.sample(glassSampler,screenUV+bend*(1+(float(c)-1)*spread*8))[c];
    }
    float3 color=(through*0.82+transmission*0.10)*(1-fresnel)+reflection*fresnel;
    // Narrow reflected contours make the transparent volume legible on black.
    color+=reflection*0.025+float3(0.21,0.35,0.46)*pow(1-facing,3.0f)*0.22;
    return float4(color,1);
}
fragment float4 glassBackdropFragment(RasterizerData in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float2 p=(in.texCoord-0.5)*2/min(u.resolution.z,1.0f);
    float pool=exp(-dot(p*float2(1.5,4),p*float2(1.5,4)));
    float3 color=float3(0.0015,0.002,0.003)+float3(0.002,0.004,0.006)*pool;
    return float4(color,1);
}

static float glassHash(float n) { return fract(sin(n*91.3458f)*47453.5453f); }

struct GlassParticle {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
};

#define GlassTrailPointCount 28
struct GlassTouchTrailUniforms {
    float4 points[GlassTrailPointCount];
};

vertex GlassParticle glassParticleVertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(0)]],
                                         constant GlassTouchTrailUniforms &trail [[buffer(1)]]) {
    if (id >= 1152) {
        uint localID=id-1152;
        uint trailIndex=min(localID/10,uint(GlassTrailPointCount-1));
        uint sparkIndex=localID%10;
        float4 touch=trail.points[trailIndex];
        float seed=glassHash(float(localID)+17.2f);
        float angle=float(sparkIndex)*(2*M_PI_F/10)+seed*1.7f+touch.z*2.1f;
        float expansion=touch.z*(0.10f+0.34f*seed)+0.006f*float(sparkIndex);
        float2 direction=float2(cos(angle),sin(angle));
        float2 drift=float2(-direction.y,direction.x)*sin(touch.z*5+seed*8)*0.055f;
        GlassParticle o;
        o.position=float4(touch.xy+direction*expansion+drift,0.32f,1.0f);
        o.pointSize=(8.0f+24.0f*touch.w)*(0.52f+seed*0.75f);
        float warm=step(0.72f,seed);
        float3 color=mix(float3(0.20,0.60,1.25),float3(1.35,0.48,0.12),warm);
        o.color=float4(color*(0.8f+touch.w*1.8f),touch.w*(1-smoothstep(0.25f,1.5f,touch.z)));
        return o;
    }
    float seed=glassHash(float(id)+3.1f), seed2=glassHash(float(id)+91.7f);
    float phase=u.galaxyParams2.x;
    float low=u.galaxyParams1.x, mid=u.galaxyParams1.y, high=u.galaxyParams1.z;
    float impact=u.galaxyParams1.w, age=u.galaxyParams2.z, energy=u.galaxyParams2.w;
    float life=fract(seed2+phase*(0.08+energy*0.18));
    float angle=seed*2*M_PI_F+phase*(0.7+seed2*1.8)+mid*sin(phase*2+seed*9);
    float radius=mix(0.46f,1.72f,seed2)+(life-0.5f)*0.20f*low;
    float3 p=float3(cos(angle)*radius,
                    sin(angle)*(0.55+0.25*seed),
                    (seed-0.5f)*2.5f+sin(angle*2+phase)*0.24f);
    // Drum hits launch a shell through the whole depth field. High frequency
    // breaks it into fine glitter; sustained energy keeps it circulating.
    float shell=impact*exp(-age*2.4f)*smoothstep(0.0f,0.18f,life)*(1-smoothstep(0.55f,1.0f,life));
    p+=normalize(p+float3(0.01))*shell*(0.42+seed*1.2);
    p.xy+=float2(sin(seed*83+phase*9),cos(seed2*71-phase*8))*high*0.11;
    p=glassRotate(p,phase*0.42,u);
    float cameraZoom=max(u.cyberpunkFrequencyControls.x,0.2f);
    float aspect=min(u.resolution.z,1.0f);
    // Fill the entire visible portrait canvas. Only X follows the square-view
    // crop; Y deliberately spans the full height instead of collapsing into
    // the central sculpture / vinyl region.
    float2 clip=float2(p.x*aspect*1.55f,p.y*1.24f)*cameraZoom;

    // Taps send a bright ripple away from the finger. Dragging continuously
    // pulls nearby particles into a small vortex around the touch position.
    float2 touch=u.galaxyParams3.zw;
    float touchPower=u.cyberpunkControls.z;
    float2 fromTouch=clip-touch;
    float touchDistance=max(length(fromTouch),0.03f);
    float touchFalloff=exp(-touchDistance*2.8f)*touchPower;
    clip+=normalize(fromTouch)*touchFalloff*(0.18+0.42*life);
    clip+=float2(-fromTouch.y,fromTouch.x)*touchFalloff*0.18;
    // The recent swipe history forms a force field. This makes ambient
    // particles visibly peel away from and curl around the whole gesture.
    float trailEnergy=0;
    for (uint i=0; i<GlassTrailPointCount; i++) {
        float4 trailPoint=trail.points[i];
        float2 delta=clip-trailPoint.xy;
        float distance=max(length(delta),0.025f);
        float force=trailPoint.w*exp(-distance*4.0f)*(1-smoothstep(0.0f,1.6f,trailPoint.z));
        clip+=normalize(delta)*force*0.10f+float2(-delta.y,delta.x)/distance*force*0.045f;
        trailEnergy=max(trailEnergy,force);
    }

    float z=4.8-p.z;
    GlassParticle o;
    o.position=float4(clip,(z-0.1)*10/(10-0.1),z);
    o.pointSize=(2.4+6.5*high+9.0*shell+8.0*touchFalloff+5.0*trailEnergy)*(0.58+seed);
    float hue=seed<0.64 ? 0.0f : 1.0f;
    float3 cool=mix(float3(0.28,0.54,0.82),float3(0.88,0.58,0.25),hue);
    float alpha=(0.13+energy*0.40+high*0.62+shell*1.15+touchFalloff+trailEnergy)*smoothstep(0,0.12,life)*(1-smoothstep(0.78,1,life));
    o.color=float4(cool*(0.6+high*1.8+shell*2.2),alpha);
    return o;
}

fragment float4 glassParticleFragment(GlassParticle in [[stage_in]], float2 coord [[point_coord]]) {
    float r=length(coord-0.5f)*2;
    float core=exp(-r*r*7.5f);
    float alpha=in.color.a*core*smoothstep(1.0f,0.72f,r);
    return float4(in.color.rgb,alpha);
}
fragment float4 glassBloomHorizontal(RasterizerData in [[stage_in]],texture2d<float> scene [[texture(0)]]) {
    float2 step=float2(2.0/scene.get_width(),0);
    float3 color=0; float weights[5]={0.227027,0.1945946,0.1216216,0.054054,0.016216};
    for(int i=-4;i<=4;i++) {
        float3 c=scene.sample(glassSampler,in.texCoord+step*float(i)*2).rgb;
        color+=max(c-0.85,0.0f)*weights[abs(i)];
    }
    return float4(color,1);
}
fragment float4 glassCompositeFragment(RasterizerData in [[stage_in]],constant Uniforms &u [[buffer(0)]],
                                      texture2d<float> scene [[texture(0)]],texture2d<float> bloom [[texture(1)]]) {
    float3 glow=0; float weights[5]={0.227027,0.1945946,0.1216216,0.054054,0.016216};
    for(int i=-4;i<=4;i++) glow+=bloom.sample(glassSampler,in.texCoord+float2(0,float(i)*2/bloom.get_height())).rgb*weights[abs(i)];
    float3 c=scene.sample(glassSampler,in.texCoord).rgb+glow*u.galaxyParams3.x;
    c*=u.galaxyParams3.y;
    c=(c*(2.51*c+0.03))/(c*(2.43*c+0.59)+0.14); // ACES fit, linear HDR to display.
    return float4(pow(clamp(c,0.0f,1.0f),float3(1/2.2)),1);
}
