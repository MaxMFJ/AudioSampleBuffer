#include "ShaderCommon.metal"

// Two instanced glass O rings. 160 x 28 quads per ring; no ray marching.
// galaxyParams1 = low, mid, high, impact; galaxyParams2 = phase, strain, impactAge, energy.
static float3 glassRingRotate(float3 p, uint ring, constant Uniforms &u) {
    float phase=u.galaxyParams2.x*(ring==0 ? 0.80f : -0.64f);
    p.xy=float2(cos(phase)*p.x-sin(phase)*p.y,sin(phase)*p.x+cos(phase)*p.y);
    // Keep the aperture facing the record. Full Y orbits made the old shape
    // collapse into an edge-on strip and caused large reflected-light flashes.
    float a=(ring==0 ? 0.075f : -0.085f)+0.025*sin(phase)+u.cyberpunkControls.y;
    p=float3(p.x,cos(a)*p.y-sin(a)*p.z,sin(a)*p.y+cos(a)*p.z);
    float yaw=u.cyberpunkControls.x;
    return float3(cos(yaw)*p.x+sin(yaw)*p.z,p.y,-sin(yaw)*p.x+cos(yaw)*p.z);
}
static float3 glassCenter(float t, uint ring, constant Uniforms &u) {
    float low=u.galaxyParams1.x, mid=u.galaxyParams1.y;
    float phase=u.galaxyParams2.x;
    float r=(ring==0 ? 1.045f : 1.34f)+low*0.035;
    r+=0.009*mid*sin(3*t+phase)+0.008*u.galaxyParams1.w*sin(4*t-phase*3);
    return float3(r*cos(t),r*sin(t),0.018*mid*sin(3*t+phase));
}
static float3 glassSurface(float t, float v, uint ring, constant Uniforms &u) {
    float3 center=glassCenter(t,ring,u);
    float3 tangent=normalize(glassCenter(t+0.002,ring,u)-glassCenter(t-0.002,ring,u));
    float3 b=normalize(cross(tangent,float3(0,0,1)));
    float3 n=cross(b,tangent);
    float radius=(ring==0 ? 0.072f : 0.085f)*(1+u.galaxyParams1.x*0.16);
    // Broad polished flutes make opposite rotation visible while preserving O.
    radius*=1+0.075*cos(4*t)+0.035*u.galaxyParams1.z*sin(8*t+u.galaxyParams2.x);
    v+=0.35*sin(3*t);
    float oval=1.22+u.galaxyParams1.y*0.12;
    return center+radius*(cos(v)*n*oval+sin(v)*b/oval);
}
struct GlassVertex {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float3 center;
};
vertex GlassVertex glassResonanceVertex(uint id [[vertex_id]],uint ring [[instance_id]],constant Uniforms &u [[buffer(0)]]) {
    float t=float(id/29)*(2*M_PI_F/160), v=float(id%29)*(2*M_PI_F/28);
    float3 p=glassSurface(t,v,ring,u);
    float3 du=glassSurface(t+0.002,v,ring,u)-glassSurface(t-0.002,v,ring,u);
    float3 dv=glassSurface(t,v+0.002,ring,u)-glassSurface(t,v-0.002,ring,u);
    float3 n=normalize(cross(du,dv));
    float3 center=glassCenter(t,ring,u);
    if(dot(n,p-center)<0) n=-n;
    p=glassRingRotate(p,ring,u); n=glassRingRotate(n,ring,u); center=glassRingRotate(center,ring,u);
    float z=4.4-p.z;
    float squareScale=min(u.resolution.z,1.0f);
    GlassVertex o;
    float cameraZoom=clamp(u.cyberpunkFrequencyControls.x,0.99f,1.025f);
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
    float impact=u.galaxyParams1.w, energy=u.galaxyParams2.w;
    float aspect=clamp(u.resolution.z,0.15f,1.0f);
    // Stratified screen positions, not world coordinates divided by depth a
    // second time. Each cell covers a different part of the full phone screen.
    float2 cell=float2(id%32,id/32)+float2(seed,seed2);
    float2 screen=(cell/float2(32,36)*2-1)*1.06;
    screen+=float2(sin(phase*0.35+seed*21),cos(phase*0.28+seed2*17))*float2(0.08,0.055);
    screen+=float2(sin(phase*1.3+screen.y*7),cos(phase+screen.x*5))*0.024*(low+mid);
    float2 clip=float2(screen.x*aspect,screen.y);
    float radius=length(float2(clip.x,clip.y)/aspect);
    float outsideRecord=smoothstep(0.73f,1.05f,radius);

    // All touch forces use post-projection square NDC, the same coordinates
    // recorded by UIKit. A finger at the top must affect particles at the top.
    float2 touch=u.galaxyParams3.zw;
    float touchPower=u.cyberpunkControls.z;
    float2 fromTouch=clip-touch;
    float touchDistance=max(length(fromTouch),0.03f);
    float touchFalloff=exp(-touchDistance*2.8f)*touchPower;
    clip+=fromTouch/touchDistance*touchFalloff*0.14;
    clip+=float2(-fromTouch.y,fromTouch.x)*touchFalloff*0.18;
    // The recent swipe history forms a force field. This makes ambient
    // particles visibly peel away from and curl around the whole gesture.
    float trailEnergy=0;
    float2 trailForce=0;
    for (uint i=0; i<GlassTrailPointCount; i++) {
        float4 trailPoint=trail.points[i];
        float2 delta=clip-trailPoint.xy;
        float distance=max(length(delta),0.025f);
        float force=trailPoint.w*exp(-distance*4.0f)*(1-smoothstep(0.0f,1.6f,trailPoint.z));
        trailForce+=delta/distance*force*0.045f+float2(-delta.y,delta.x)/distance*force*0.025f;
        trailEnergy=max(trailEnergy,force);
    }

    clip+=trailForce/max(1.0f,length(trailForce)/0.22f);
    float depth=2.5+seed2*4.0;
    GlassParticle o;
    o.position=float4(clip*depth,0.90*depth,depth);
    float pixelScale=clamp(u.resolution.x/1200,0.55f,1.4f);
    o.pointSize=(1.8+seed*2.4+high*2.0+impact*2.0+trailEnergy*5.0)*pixelScale;
    float3 tint=mix(float3(0.46,0.68,0.84),float3(0.83,0.71,0.49),smoothstep(0.65,0.95,seed));
    float shimmer=0.55+0.45*pow(0.5+0.5*sin(phase*1.7+seed*40),2.0f);
    float edgeFade=1-smoothstep(0.94f,1.10f,max(abs(screen.x),abs(screen.y)));
    float alpha=(0.13+energy*0.22+high*0.20+impact*0.15)*shimmer*outsideRecord*edgeFade;
    o.color=float4(tint*(0.65+high*0.65),alpha+trailEnergy*0.35);
    return o;
}

fragment float4 glassParticleFragment(GlassParticle in [[stage_in]], float2 coord [[point_coord]]) {
    float r=length(coord-0.5f)*2;
    float core=exp(-r*r*7.5f);
    float alpha=in.color.a*core*(1-smoothstep(0.72f,1.0f,r));
    return float4(in.color.rgb,alpha);
}

struct GlassWaveVertex {
    float4 position [[position]];
    float4 color;
    float across;
};

// Six thin moving wave ribbons above / below the record. Spectrum shapes the
// peaks, while continuous phase transports them; there are no spectrum bars.
vertex GlassWaveVertex glassWaveVertex(uint id [[vertex_id]],uint lane [[instance_id]],
                                       constant Uniforms &u [[buffer(0)]]) {
    float x=float(id/2)/160*2-1;
    float side=(id%2)==0 ? -1.0f : 1.0f;
    float tier=float(lane/2), sign=(lane%2)==0 ? 1.0f : -1.0f;
    float phase=u.galaxyParams2.x;
    float bandPosition=(x*0.5+0.5)*77;
    uint band=uint(bandPosition);
    float a=(u.audioData[band].y+u.audioData[band+1].y)*0.5;
    float b=(u.audioData[band+1].y+u.audioData[band+2].y)*0.5;
    float peak=mix(a,b,smoothstep(0.0f,1.0f,fract(bandPosition)));
    float low=u.galaxyParams1.x, mid=u.galaxyParams1.y, high=u.galaxyParams1.z;
    float music=u.galaxyParams2.w;
    float carrier=sin(x*(5.0+tier)+phase*(2.0+tier*0.25)+tier*1.3);
    float detail=sin(x*13-phase*2.4+tier)*high*0.22;
    float envelope=pow(max(1-x*x,0.0f),0.65f);
    float amplitude=0.006+0.07*low+0.08*mid+0.045*u.galaxyParams1.w+peak*0.12;
    float y=sign*(0.56+tier*0.13+envelope*amplitude*(carrier+detail));
    float width=(1.2+high*0.6+peak*0.6)*2/max(u.resolution.y,1.0f);
    GlassWaveVertex o;
    o.position=float4(x*min(u.resolution.z,1.0f),y+side*width,0.85,1);
    float3 tint=mix(float3(0.27,0.53,0.69),float3(0.82,0.67,0.43),tier*0.38);
    float flow=0.65+0.35*sin(x*3-phase*3+tier);
    o.color=float4(tint*(0.55+music*0.7+peak*0.3),envelope*(0.10+0.65*music)*flow);
    o.across=side;
    return o;
}
fragment float4 glassWaveFragment(GlassWaveVertex in [[stage_in]]) {
    return float4(in.color.rgb,in.color.a*(1-smoothstep(0.20f,1.0f,abs(in.across))));
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
