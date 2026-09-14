#include "ShaderCommon.metal"

// Two instanced glass O rings. 160 x 28 quads per ring; no ray marching.
// galaxyParams1 = low, mid, high, impact; galaxyParams2 = phase, strain, climax, energy.
static float3 glassRotateAxis(float3 p, float3 axis, float a) {
    axis=normalize(axis);
    float s=sin(a), c=cos(a);
    return p*c+cross(axis,p)*s+axis*dot(axis,p)*(1-c);
}
static float3 glassRingRotate(float3 p, uint ring, constant Uniforms &u) {
    float phase=u.galaxyParams2.x, impact=u.galaxyParams1.w, energy=u.galaxyParams2.w;
    float climax=u.galaxyParams2.z;
    // Kick only changes integrated phase on the CPU. Adding it here as a pose
    // offset made stacked beats look like stuttered jumps.
    float3 leanAxis=ring==0 ? float3(0,1,0) : float3(1,0,0);
    float3 flipAxis=ring==0 ? float3(1,0.14,0.10) : float3(-0.12,1,-0.10);
    float lean=(ring==0 ? 0.56f : -0.50f)+0.10f*sin(phase*0.47f+(ring==0 ? 0.0f : 1.8f));
    lean+=climax*(ring==0 ? 0.05f : -0.04f);
    float flip=phase*(ring==0 ? 0.96f : -0.78f)+(ring==0 ? 0.62f : 1.38f);
    flip+=impact*(ring==0 ? 0.12f : -0.10f)+energy*0.04f*(ring==0 ? 1.0f : -1.0f);
    flip+=climax*(ring==0 ? 0.08f : -0.07f);
    p=glassRotateAxis(p,leanAxis,lean);
    return glassRotateAxis(p,flipAxis,flip);
}
static float3 glassCenter(float t, uint ring, constant Uniforms &u) {
    float low=u.galaxyParams1.x, mid=u.galaxyParams1.y;
    float phase=u.galaxyParams2.x;
    float r=(ring==0 ? 1.045f : 1.34f)+low*0.035+u.galaxyParams2.z*0.028;
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
static float4 glassProject(float3 p, constant Uniforms &u) {
    float z=4.4-p.z;
    float squareScale=min(u.resolution.z,1.0f);
    float zoom=clamp(u.cyberpunkFrequencyControls.x,0.94f,1.12f);
    return float4(p.xy*2.80*squareScale*zoom, (z-0.1)*10/(10-0.1), z);
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
    GlassVertex o;
    o.position=glassProject(p,u);
    o.world=p; o.normal=n; o.center=center; return o;
}
vertex RasterizerData glassFullscreenVertex(uint id [[vertex_id]]) {
    float2 p=float2((id<<1)&2,id&2);
    RasterizerData o; o.position=float4(p*2-1,0,1); o.texCoord=float2(p.x,1-p.y); o.color=1; return o;
}
static float3 glassAtmosphere(constant Uniforms &u) {
    return clamp(u.activityMeter3.rgb,0.0f,1.2f);
}
static float3 glassPrimary(constant Uniforms &u) {
    return clamp(u.activityMeter4.rgb,0.0f,1.2f);
}
static float3 glassAccent(constant Uniforms &u) {
    return clamp(u.activityMeter5.rgb,0.0f,1.2f);
}
// Procedural studio lighting is shared by reflection and refraction: warm softbox,
// cool rim, broad neutral ceiling. No downloaded environment or bitmap dependency.
static float3 glassStudio(float3 d, float high, float climax, constant Uniforms &u) {
    d=normalize(d);
    float key=exp(-pow((d.x+0.42)/0.23,2.0f)-pow((d.y-0.54)/0.58,4.0f));
    float rim=exp(-pow((d.x-0.65)/0.085,2.0f)-pow((d.y+0.10)/0.75,4.0f));
    float top=pow(max(dot(d,normalize(float3(0,0.8,0.4))),0.0f),18.0f);
    float strip=exp(-pow((d.y+0.38+0.14*d.x)/0.035,2.0f))*smoothstep(-0.8,0.2,d.z);
    float heat=1.0f+climax*0.32f;
    float3 atmosphere=glassAtmosphere(u), primary=glassPrimary(u), accent=glassAccent(u);
    return atmosphere*0.16+
      primary*key*3.6*heat+
      accent*rim*(2.4+high*1.3+climax*0.70)+
      mix(primary,accent,0.38)*top*(1.0+climax*0.35)+
      mix(primary,accent,0.28+climax*0.38)*strip*(1.8+climax*0.55);
}
constexpr sampler glassSampler(coord::normalized,address::clamp_to_edge,filter::linear);
constexpr sampler coverSampler(coord::normalized,address::clamp_to_edge,filter::linear,mip_filter::linear,max_anisotropy(8));
fragment float4 glassBackFragment(GlassVertex in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float3 n=normalize(in.normal), view=normalize(float3(0,0,4.4)-in.world);
    float edge=pow(1-abs(dot(n,view)),3.0f);
    float climax=u.galaxyParams2.z;
    return float4(glassStudio(reflect(-view,n),u.galaxyParams1.z,climax,u)*(0.035+0.28*edge)*(1+climax*0.18),1);
}
fragment float4 glassResonanceFragment(GlassVertex in [[stage_in]],constant Uniforms &u [[buffer(0)]],
                                      texture2d<float> rear [[texture(0)]]) {
    float3 n=normalize(in.normal), incident=normalize(in.world-float3(0,0,4.4));
    n=faceforward(n,incident,n);
    float facing=clamp(-dot(incident,n),0.0f,1.0f);
    float fresnel=0.04+0.96*pow(1-facing,5.0f);
    float high=u.galaxyParams1.z, strain=u.galaxyParams2.y, climax=u.galaxyParams2.z;
    float spread=0.006+high*0.018+strain*0.032+climax*0.028;
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
        transmission[c]=glassStudio(outgoing,high,climax,u)[c];
    }
    transmission*=exp(-float3(0.48,0.22,0.13)*thickness*2.0);
    float3 reflection=glassStudio(reflect(incident,n),high,climax,u);
    float2 screenUV=in.position.xy/u.resolution.xy;
    float2 bend=n.xy*thickness*0.10*min(u.resolution.z,1.0f);
    float3 through;
    for(uint c=0;c<3;c++) {
        through[c]=rear.sample(glassSampler,screenUV+bend*(1+(float(c)-1)*spread*8))[c];
    }
    float3 color=(through*0.82+transmission*0.10)*(1-fresnel)+reflection*fresnel;
    // Narrow reflected contours make the transparent volume legible on black.
    color+=reflection*0.025+glassAtmosphere(u)*pow(1-facing,3.0f)*0.34;
    color+=mix(glassAccent(u),glassPrimary(u),climax)*pow(1-facing,2.4f)*climax*0.18;
    return float4(color,1);
}
fragment float4 glassBackdropFragment(RasterizerData in [[stage_in]],constant Uniforms &u [[buffer(0)]]) {
    float2 p=(in.texCoord-0.5)*2/min(u.resolution.z,1.0f);
    float pool=exp(-dot(p*float2(1.5,4),p*float2(1.5,4)));
    float atmoIntensity=clamp(u.activityMeter5.w,0.20f,1.0f);
    float3 color=float3(0.0005)+glassAtmosphere(u)*(0.012f+0.030f*pool)*(0.72f+atmoIntensity);
    float climax=u.galaxyParams2.z;
    float rayEnvelope=saturate(u.cyberpunkBackgroundParams.x);
    float fade=rayEnvelope;
    if (fade>0.01f) {
        float r=length(p);
        float ang=atan2(p.y,p.x);
        float phase=u.galaxyParams2.x;
        float3 ice=glassAccent(u)*1.10f;
        float3 gold=glassPrimary(u)*1.08f;
        // Tyndall shafts through the studio volume. Cheap polar lobes, no extra pass.
        for (int i=0;i<6;i++) {
            float lobe=abs(sin(ang+phase*0.31+float(i)*1.0472f));
            float shaft=exp(-11.0f*lobe)*exp(-r*0.85f);
            color+=mix(ice,gold,float(i)/5.0f)*shaft*fade*0.58f;
        }
        float extra=smoothstep(0.45f,0.90f,rayEnvelope);
        if (extra>0.01f) {
            for (int i=0;i<4;i++) {
                float lobe=abs(sin(ang-phase*0.44+float(i)*1.5708f+0.4f));
                float shaft=exp(-20.0f*lobe)*exp(-r*1.25f);
                color+=mix(gold,ice,float(i)/3.0f)*shaft*extra*0.32f;
            }
        }
        // Sustained treble keeps the rays alive and emits a slow sequence of
        // expanding waves instead of stopping after a fixed one-shot lifetime.
        float ringPhase=fract(u.cyberpunkBackgroundParams.y/1.8f);
        float ringR=0.16f+ringPhase*(0.92f+climax*0.12f);
        float ring=exp(-pow((r-ringR)/(0.020f+climax*0.012f),2.0f));
        color+=gold*ring*fade*(1.0f-ringPhase)*0.52f;
        float ring2=exp(-pow((r-(ringR*0.62f))/(0.014f+climax*0.008f),2.0f));
        color+=ice*ring2*fade*(1.0f-ringPhase)*0.28f;
        color+=gold*exp(-r*2.1f)*fade*0.14f;
    }
    return float4(color,1);
}

#define GlassVinylSegments 96
#define GlassVinylVertexCount (96*6*4)
struct VinylVertex {
    float4 position [[position]];
    float3 world;
    float3 normal;
    float2 polar;
};
static float2 vinylSpoke(uint seg) {
    float t=float(seg)*(2*M_PI_F/float(GlassVinylSegments));
    return float2(cos(t),sin(t));
}
vertex VinylVertex vinylDiscVertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(0)]]) {
    const uint segs=GlassVinylSegments;
    const uint faceVerts=segs*6;
    uint region=id/faceVerts;
    uint local=id%faceVerts;
    uint tri=local/3;
    uint corner=local%3;
    uint seg=tri/2;
    uint second=tri%2;
    uint vertSel=second==0 ? (corner==0 ? 0u : (corner==1 ? 1u : 2u))
                           : (corner==0 ? 0u : (corner==1 ? 2u : 3u));
    if (region==1 || region==3) {
        vertSel=second==0 ? (corner==0 ? 0u : (corner==1 ? 2u : 1u))
                          : (corner==0 ? 0u : (corner==1 ? 3u : 2u));
    }
    float2 u0=vinylSpoke(seg);
    float2 u1=vinylSpoke((seg+1)%segs);
    const float inner=0.048f, outer=0.74f, halfT=0.016f;
    float3 p, n;
    if (region<=1) {
        float z=region==0 ? halfT : -halfT;
        float2 xy=vertSel==0 ? u0*inner : vertSel==1 ? u0*outer : vertSel==2 ? u1*outer : u1*inner;
        p=float3(xy,z);
        n=float3(0,0,region==0 ? 1.0f : -1.0f);
    } else if (region==2) {
        float2 d=vertSel<=1 ? u0 : u1;
        float z=(vertSel==0 || vertSel==3) ? halfT : -halfT;
        p=float3(d*outer,z);
        n=float3(d,0);
    } else {
        float2 d=vertSel<=1 ? u0 : u1;
        float z=(vertSel==0 || vertSel==3) ? halfT : -halfT;
        p=float3(d*inner,z);
        n=float3(-d,0);
    }
    float spin=u.galaxyParams2.x*1.35f;
    float c=cos(spin), s=sin(spin);
    p=float3(c*p.x-s*p.y,s*p.x+c*p.y,p.z);
    n=float3(c*n.x-s*n.y,s*n.x+c*n.y,n.z);
    VinylVertex o;
    o.position=glassProject(p,u);
    o.world=p; o.normal=n;
    o.polar=p.xy; // cartesian: interpolating atan2 tears along the branch cut
    return o;
}
fragment float4 vinylDiscFragment(VinylVertex in [[stage_in]], constant Uniforms &u [[buffer(0)]],
                                 texture2d<float> cover [[texture(0)]]) {
    float2 xy=in.world.xy;
    float r=length(xy), ang=atan2(xy.y,xy.x);
    float3 n=normalize(in.normal);
    float3 view=normalize(float3(0,0,4.4)-in.world);
    float3 light=normalize(float3(-0.35,0.55,0.75));
    float grooves=(0.5+0.5*sin(r*220+0.35*sin(ang*2.0))) *
                  smoothstep(0.225,0.245,r)*smoothstep(0.705,0.68,r);
    float3 body=float3(0.026,0.027,0.032)+grooves*float3(0.05,0.053,0.06);
    float label=smoothstep(0.235,0.215,r)*smoothstep(0.050,0.062,r);
    float3 labelCol=mix(float3(0.70,0.22,0.18),float3(0.90,0.76,0.48),smoothstep(0.07,0.19,r));
    labelCol+=smoothstep(0.12,0.13,r)*smoothstep(0.16,0.15,r)*0.12;
    float3 color=mix(body,labelCol,label);
    bool front=n.z>0.0f;
    bool hasCover=u.cyberpunkControls.w>0.5f && !is_null_texture(cover) && cover.get_width()>2;
    const float artR=0.66f;
    if (hasCover && front && r<artR && r>0.052f) {
        float2 tex=float2(cover.get_width(),cover.get_height());
        float shortSide=min(tex.x,tex.y);
        float2 uv=0.5+float2(xy.x,-xy.y)/artR*(0.5*shortSide/max(tex,float2(1)));
        float3 art=cover.sample(coverSampler,uv).rgb;
        float disk=smoothstep(artR,artR-0.012f,r)*smoothstep(0.050f,0.062f,r);
        float grooveWash=smoothstep(0.42f,0.62f,r)*grooves*0.08f;
        art=art*(1.0f-grooveWash)+body*grooveWash;
        color=mix(color,art,disk);
        color=mix(color,float3(0.04,0.04,0.045),smoothstep(0.652f,0.668f,r)*0.55f);
    }
    float ndh=saturate(dot(n,normalize(view+light)));
    float spec=pow(ndh,52.0)*0.42;
    float2 q=in.world.xy;
    float streak=pow(saturate(0.55+0.45*sin(atan2(q.y,q.x)*2.0+0.9)),10.0);
    streak*=smoothstep(0.24,0.28,r)*(hasCover ? 0.45f : (1-label));
    color+=(spec*(hasCover?0.12:0.28)+streak*0.16)*float3(0.86,0.93,1.0);
    color+=smoothstep(0.70,0.74,r)*float3(0.07,0.08,0.10);
    float climax=u.galaxyParams2.z;
    color+=glassStudio(n,u.galaxyParams1.z,climax,u)*0.035;
    color+=glassPrimary(u)*smoothstep(0.062f,0.048f,r)*climax*0.42f;
    color+=glassAccent(u)*smoothstep(0.70f,0.74f,r)*climax*0.28f;
    float facing=saturate(abs(dot(n,view)));
    color*=0.78+0.22*facing;
    color+=spec*climax*0.08*mix(glassPrimary(u),glassAccent(u),0.25f);
    return float4(color,1);
}

static float glassHash(float n) { return fract(sin(n*91.3458f)*47453.5453f); }

struct GlassParticle {
    float4 position [[position]];
    float pointSize [[point_size]];
    float4 color;
    float softness;
};

#define GlassAmbientParticleCount 1152
#define GlassTrailPointCount 28
#define GlassTrailSparksPerPoint 16
struct GlassTouchTrailUniforms {
    float4 points[GlassTrailPointCount];
    float4 tangents[GlassTrailPointCount];
};

vertex GlassParticle glassParticleVertex(uint id [[vertex_id]], constant Uniforms &u [[buffer(0)]],
                                         constant GlassTouchTrailUniforms &trail [[buffer(1)]]) {
    float pixelScale=clamp(u.resolution.x/1200,0.55f,1.4f);
    if (id >= GlassAmbientParticleCount) {
        uint localID=id-GlassAmbientParticleCount;
        uint trailIndex=min(localID/GlassTrailSparksPerPoint,uint(GlassTrailPointCount-1));
        uint spark=localID%GlassTrailSparksPerPoint;
        float4 touch=trail.points[trailIndex];
        float4 tangent=trail.tangents[trailIndex];
        float seed=glassHash(float(localID)+17.2f);
        float seed2=glassHash(float(localID)+63.9f);
        float age=touch.z, life=touch.w*(1-smoothstep(0.08f,1.65f,age));
        float2 dir=tangent.xy;
        float dirLen=length(dir);
        bool hasStroke=dirLen>0.12f;
        dir=hasStroke ? dir/dirLen : float2(0,1);
        float2 perp=float2(-dir.y,dir.x);
        float2 pos=touch.xy;
        float softness=0.45f;
        float3 ice=glassAccent(u)*1.16f;
        float3 gold=glassPrimary(u)*1.16f;
        float3 white=mix(glassPrimary(u),float3(1.18),0.58f);
        float3 color=mix(ice,gold,smoothstep(0.42f,0.88f,seed));
        float size=8.0f;
        float alpha=life;
        if (hasStroke) {
            float along, across;
            if (spark<4) {
                along=(seed-0.5f)*0.034f;
                across=(seed2-0.5f)*0.0065f;
                size=(16.0f+30.0f*touch.w)*(0.72f+seed*0.38f);
                color=mix(color,white,0.48f);
                softness=0.28f;
                alpha*=0.95f;
            } else if (spark<10) {
                along=-(0.018f+0.11f*age)*(0.35f+seed)+(seed2-0.5f)*0.02f;
                across=(seed-0.5f)*(0.012f+0.038f*age);
                across+=sin(age*7.5f+seed*11.0f)*0.010f;
                size=(8.0f+18.0f*touch.w)*(0.55f+seed*0.55f);
                softness=0.72f;
                alpha*=0.48f;
            } else {
                along=-(0.04f+0.16f*age)*seed-0.008f*float(spark);
                across=(seed2-0.5f)*(0.02f+0.055f*age);
                across+=sin(age*11.0f+seed2*17.0f)*0.016f;
                float twinkle=0.35f+0.65f*pow(0.5f+0.5f*sin(age*18.0f+seed*40.0f),4.0f);
                size=(3.2f+9.0f*touch.w)*(0.45f+seed*0.85f);
                softness=0.18f;
                alpha*=0.55f*twinkle;
                color=mix(color,white,0.35f);
            }
            pos+=dir*along+perp*across;
        } else {
            float angle=float(spark)*(2*M_PI_F/GlassTrailSparksPerPoint)+seed*1.4f;
            float expansion=age*(0.045f+0.16f*seed)+0.004f*float(spark%5);
            float2 radial=float2(cos(angle),sin(angle));
            pos+=radial*expansion;
            pos+=float2(-radial.y,radial.x)*sin(age*5.5f+seed*8.0f)*0.018f;
            float head=spark<5;
            size=(head ? 18.0f+26.0f*touch.w : 6.0f+12.0f*touch.w)*(0.55f+seed*0.6f);
            softness=head ? 0.40f : 0.70f;
            color=mix(color,white,head ? 0.40f : 0.12f);
            alpha*=(1-smoothstep(0.15f,1.2f,age))*(head ? 0.85f : 0.42f);
        }
        GlassParticle o;
        o.position=float4(pos,0.28f,1.0f);
        o.pointSize=size*pixelScale;
        o.color=float4(color*(0.75f+touch.w*1.35f),max(alpha,0.0f));
        o.softness=softness;
        return o;
    }
    float seed=glassHash(float(id)+3.1f), seed2=glassHash(float(id)+91.7f);
    float phase=u.galaxyParams2.x;
    float low=u.galaxyParams1.x, mid=u.galaxyParams1.y, high=u.galaxyParams1.z;
    float impact=u.galaxyParams1.w, energy=u.galaxyParams2.w, climax=u.galaxyParams2.z;
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
    if (u.cyberpunkBackgroundParams.z>0.5f) {
        for (uint i=0; i<GlassTrailPointCount; i++) {
            float4 trailPoint=trail.points[i];
            if (trailPoint.w<=0.0f) continue;
            float2 delta=clip-trailPoint.xy;
            float distance=max(length(delta),0.025f);
            float force=trailPoint.w*exp(-distance*4.0f)*(1-smoothstep(0.0f,1.6f,trailPoint.z));
            trailForce+=delta/distance*force*0.045f+float2(-delta.y,delta.x)/distance*force*0.025f;
            trailEnergy=max(trailEnergy,force);
        }
    }

    clip+=trailForce/max(1.0f,length(trailForce)/0.22f);
    float depth=2.5+seed2*4.0;
    GlassParticle o;
    o.position=float4(clip*depth,0.90*depth,depth);
    o.pointSize=(1.8+seed*2.4+high*2.0+impact*2.0+trailEnergy*5.0+climax*2.2)*pixelScale;
    float3 tint=mix(glassAccent(u),glassPrimary(u),smoothstep(0.65,0.95,seed));
    tint=mix(tint,mix(glassPrimary(u),glassAccent(u),0.22f),climax*0.28f);
    float shimmer=0.55+0.45*pow(0.5+0.5*sin(phase*1.7+seed*40),2.0f);
    float edgeFade=1-smoothstep(0.94f,1.10f,max(abs(screen.x),abs(screen.y)));
    float alpha=(0.13+energy*0.22+high*0.20+impact*0.15+climax*0.14)*shimmer*outsideRecord*edgeFade;
    o.color=float4(tint*(0.65+high*0.65),alpha+trailEnergy*0.35);
    o.softness=0.55f;
    return o;
}

fragment float4 glassParticleFragment(GlassParticle in [[stage_in]], float2 coord [[point_coord]]) {
    float r=length(coord-0.5f)*2;
    float softness=clamp(in.softness,0.0f,1.0f);
    float core=exp(-r*r*mix(14.0f,5.5f,softness));
    float halo=exp(-r*r*mix(5.5f,2.1f,softness))*mix(0.22f,0.55f,softness);
    float spark=pow(max(1.0f-r,0.0f),5.0f)*mix(0.35f,0.08f,softness);
    float alpha=in.color.a*(core+halo+spark)*(1-smoothstep(0.78f,1.0f,r));
    return float4(in.color.rgb*(0.62f+0.55f*core),alpha);
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
    float music=u.galaxyParams2.w, climax=u.galaxyParams2.z;
    float carrier=sin(x*(5.0+tier)+phase*(2.0+tier*0.25)+tier*1.3);
    float detail=sin(x*13-phase*2.4+tier)*high*0.22;
    float envelope=pow(max(1-x*x,0.0f),0.65f);
    float amplitude=0.006+0.07*low+0.08*mid+0.045*u.galaxyParams1.w+peak*0.12+climax*0.045;
    float y=sign*(0.56+tier*0.13+envelope*amplitude*(carrier+detail));
    float width=(1.2+high*0.6+peak*0.6+climax*0.8)*2/max(u.resolution.y,1.0f);
    GlassWaveVertex o;
    o.position=float4(x*min(u.resolution.z,1.0f),y+side*width,0.85,1);
    float3 tint=mix(glassAccent(u),glassPrimary(u),tier*0.38);
    tint=mix(tint,mix(glassPrimary(u),glassAccent(u),0.18f),climax*0.28f);
    float flow=0.65+0.35*sin(x*3-phase*3+tier);
    o.color=float4(tint*(0.55+music*0.7+peak*0.3+climax*0.22),envelope*(0.10+0.65*music+climax*0.16)*flow);
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
    float3 c=scene.sample(glassSampler,in.texCoord).rgb+glow*u.galaxyParams3.x*(1.0+u.galaxyParams2.z*0.32);
    c*=u.galaxyParams3.y;
    c=(c*(2.51*c+0.03))/(c*(2.43*c+0.59)+0.14); // ACES fit, linear HDR to display.
    return float4(pow(clamp(c,0.0f,1.0f),float3(1/2.2)),1);
}
