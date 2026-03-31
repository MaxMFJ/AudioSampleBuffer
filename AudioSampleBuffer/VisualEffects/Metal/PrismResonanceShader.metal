//
//  PrismResonanceShader.metal - Prism Resonance v7
//  性能优化版：低清晰度 + 半透明大圆背景 + 3秒锁定形变
//
#include "ShaderCommon.metal"
using namespace metal;

static inline float prH(float n){ return fract(sin(n*127.1)*43758.5453); }
static inline float2 prRot(float2 q,float a){
    return float2(cos(a)*q.x-sin(a)*q.y, sin(a)*q.x+cos(a)*q.y);
}
static inline float prSDDiamond(float2 q,float r){ return abs(q.x)*1.35 + abs(q.y)*0.82 - r; }
static inline float prSDCircle(float2 q,float r){ return length(q)-r; }
static inline float prSDHeart(float2 q,float r){
    float2 w=q/max(r,1e-5); w.x=abs(w.x); w.y+=0.07;
    return max(length(w-float2(0.23,-0.10))-0.32,
               max(w.x*0.90+w.y*1.10,-w.y*0.75)-0.10)*r;
}
static inline float prShapeDistance(int state, float2 q, float r) {
    if(state==0) return prSDDiamond(q, r);
    if(state==1) return prSDCircle(q, r*0.92);
    return prSDHeart(q, r*1.08);
}
static inline float prFill(float d,float fw){ return smoothstep(fw,-fw,d); }
static inline float prRing(float d,float fw,float th){ return prFill(d,fw)-prFill(d-th,fw); }
static constant sampler prLinearSampler(coord::normalized, address::clamp_to_edge, filter::linear);

static inline float3 prismResonanceBackground(float2 p,
                                              float t,
                                              float radial,
                                              float low,
                                              float beatPulse,
                                              float atmoI,
                                              float3 cAtmo,
                                              float3 cPulse,
                                              float3 cCorona) {
    float atmoLum = dot(cAtmo, float3(0.299,0.587,0.114));
    float atmoLift = 1.08 + smoothstep(0.00, 0.22, 0.24 - atmoLum) * 0.38;
    float3 liftedAtmo = mix(cAtmo * atmoLift, float3(max(atmoLum, 0.18)), 0.08);

    float3 col = mix(liftedAtmo*float3(0.12,0.08,0.28),
                     liftedAtmo*float3(0.05,0.03,0.12),
                     smoothstep(-0.5,0.5,p.y));

    for(int i=0;i<4;i++){
        float fi=float(i);
        float seed=fi*13.7+1.0;
        float depth = 0.78 + 0.22 * prH(seed * 5.9);
        float jitterPhase = t * (1.8 + fi * 0.11) + seed * 3.1;
        float2 beatJitter = float2(
            sin(jitterPhase),
            cos(jitterPhase * 1.17 + seed)
        ) * beatPulse * (0.010 + 0.007 * prH(seed * 8.3)) * depth;
        float2 basePos = float2(
            (prH(seed*1.3)-0.5)*1.18,
            (prH(seed*2.1)-0.5)*1.10
        );
        float2 drift = float2(
            sin(t*(0.11+fi*0.02)+seed)*0.18,
            cos(t*(0.09+fi*0.018)+seed*1.7)*0.16
        ) * depth;
        float2 c = float2(basePos.x + drift.x, basePos.y + drift.y) + beatJitter;
        float r = ((0.16 + 0.06*prH(seed*3.3)) / depth) * (1.0 + beatPulse * 0.08);
        float d = length(p-c) - r;
        float bubbleFill = smoothstep(0.018, -0.018, d);
        float bubbleRim = smoothstep(0.020, 0.002, abs(d));
        float bubbleInner = smoothstep(0.055, -0.004, d + r * 0.42);
        float breath = 0.90 + 0.10*sin(t*(0.18+fi*0.02)+seed*2.1+low*1.4);
        float3 bCol = mix(cCorona, cPulse, prH(seed*4.7));
        float edgeFade = 1.0 - smoothstep(1.05, 1.42, length(c));
        float bubbleAlpha = (0.19 + atmoI*0.12) * (0.94 + low*0.24 + beatPulse*0.26) * breath * edgeFade;
        col += bCol * bubbleFill * bubbleAlpha * 0.60;
        col += mix(bCol, float3(1.0), 0.34) * bubbleInner * bubbleAlpha * 0.26;
        col += mix(bCol, float3(1.0), 0.68) * bubbleRim * bubbleAlpha * 0.76;
    }

    for(int i=0;i<7;i++){
        float fi = float(i);
        float seed = 101.0 + fi * 9.7;
        float depth = 0.72 + 0.28 * prH(seed * 1.9);
        float2 basePos = float2(
            (prH(seed*2.3)-0.5)*1.52,
            (prH(seed*3.1)-0.5)*1.44
        );
        float2 drift = float2(
            sin(t*(0.072+fi*0.008)+seed)*0.082,
            cos(t*(0.066+fi*0.007)+seed*1.3)*0.070
        ) * depth;
        float2 c = basePos + drift;
        float r = (0.040 + 0.026 * prH(seed*4.1)) / depth;
        float d = length(p-c) - r;
        float bubbleFill = smoothstep(0.030, -0.020, d);
        float bubbleSoft = smoothstep(0.080, -0.035, d);
        float3 sCol = mix(liftedAtmo, cCorona, prH(seed*5.7));
        float alpha = (0.076 + atmoI*0.052) * (0.92 + 0.16*sin(t*(0.18+fi*0.012)+seed)) * (1.0 - smoothstep(1.10, 1.55, length(c)));
        col += sCol * bubbleSoft * alpha * 0.38;
        col += mix(sCol, float3(1.0), 0.14) * bubbleFill * alpha * 0.54;
    }

    col += cPulse * exp(-radial*(4.0-low*1.5)) * (0.10 + atmoI*0.10);
    return col;
}

static inline float3 prismResonanceForeground(float2 p,
                                              float2 uv,
                                              float t,
                                              float radial,
                                              constant Uniforms &uniforms,
                                              float low,
                                              float mid,
                                              float high,
                                              float energy,
                                              float aspd,
                                              float glowI,
                                              float bright,
                                              int nLayers,
                                              int nSlots,
                                              int lowState,
                                              int midState,
                                              int highState,
                                              float lowMorphProgress,
                                              float midMorphProgress,
                                              float highMorphProgress) {
    float3 col = float3(0.0);

    float fw = fwidth(length(p))*1.0 + 0.0010;
    for(int layer=0; layer<4; layer++){
        if(layer>=nLayers) continue;
        float lF     = float(layer)/float(max(nLayers-1,1));
        float szBase = mix(0.014,0.040,lF);
        float alpha  = mix(0.18,1.00,lF);
        float dAmp   = mix(0.006,0.024,lF);
        float dRate  = mix(0.18,0.45,lF)*aspd;
        float feath  = fw*mix(2.4,1.0,lF);

        for(int slot=0; slot<8; slot++){
            if(slot>=nSlots) continue;
            float seed=float(layer*43+slot*71)+3.14;

            int slotIndex = layer * nSlots + slot;
            int bandIndex = 4 + ((slotIndex * 9 + layer * 5 + 3) % 68);
            float bandSmooth = clamp(uniforms.audioData[bandIndex].y * 1.85, 0.0, 1.35);
            float bandTransient = clamp(uniforms.audioData[bandIndex].w * 5.4, 0.0, 1.4);

            float ev;
            int state;
            float morphProgress;
            float3 bc;
            if(bandIndex < 24){
                ev=bandSmooth;
                state=lowState;
                morphProgress=lowMorphProgress;
                bc=float3(1.00,0.28,0.52);
            } else if(bandIndex < 48){
                ev=bandSmooth;
                state=midState;
                morphProgress=midMorphProgress;
                bc=float3(0.25,0.68,1.00);
            } else {
                ev=bandSmooth;
                state=highState;
                morphProgress=highMorphProgress;
                bc=float3(0.86,0.24,1.00);
            }

            int stateOffset = (bandIndex + slot + layer) % 3;
            state = (state + stateOffset) % 3;

            float3 dc = mix(bc*float3(0.50,0.65,1.18), bc, lF) * mix(0.25,1.0,lF);
            float2 anchor = float2((prH(seed*1.37)-0.5)*0.90, (prH(seed*2.53)-0.5)*0.88);
            float2 drift  = float2(sin(t*dRate+seed*1.8)*dAmp,
                                   cos(t*dRate*0.75+seed*1.4)*dAmp*0.7);
            float rot = (prH(seed*3.7)-0.5)*1.2 + t*(prH(seed*0.43)-0.5)*0.03;
            float2 lp = prRot(p-anchor-drift, rot);
            float slotEnergy = clamp(ev * 0.82 + bandTransient * 0.24, 0.0, 1.4);
            float sz  = szBase*(0.82+slotEnergy*0.26);

            int prevState = (state + 2) % 3;
            float morphT = smoothstep(0.0, 1.0, morphProgress);
            float transitionDip = 1.0 - 0.42 * sin(morphT * 3.14159265);
            float dPrev = prShapeDistance(prevState, lp, sz);
            float dCurr = prShapeDistance(state, lp, sz);
            float th   = sz*0.13;
            float ringPrev = prRing(dPrev,feath,th);
            float ringCurr = prRing(dCurr,feath,th);
            float bodyPrev = prFill(dPrev-th,feath)*(0.05+slotEnergy*0.16);
            float bodyCurr = prFill(dCurr-th,feath)*(0.05+slotEnergy*0.16);
            float corePrev = prFill(dPrev-sz*0.65,feath*0.7);
            float coreCurr = prFill(dCurr-sz*0.65,feath*0.7);
            float ring = (ringPrev * (1.0 - morphT) + ringCurr * morphT) * transitionDip;
            float body = (bodyPrev * (1.0 - morphT) + bodyCurr * morphT) * transitionDip;
            float core = (corePrev * (1.0 - morphT) + coreCurr * morphT) * transitionDip;
            float aura = prFill(prSDCircle(lp,sz*3.5),feath*11.0) * (0.03+slotEnergy*0.08);
            float gain = alpha*bright*(0.78+0.22*sin(t*(1.7+prH(seed)*1.4)+seed));
            gain = clamp(gain,0.,2.0);

            col += dc * aura * glowI * gain;
            col += dc * ring * gain * (0.9+slotEnergy*0.8);
            col += dc * body * gain;
            col += mix(dc,float3(1.0),0.40) * core * gain * (0.6+slotEnergy*0.4);
        }
    }

    float sparkle = pow(max(0.,cos((atan2(p.y,p.x)+t*0.22)*2.5+energy*0.4)),16.0);
    col += float3(0.90,0.45,1.00) * sparkle * exp(-radial*3.0) * (0.02+high*0.04);
    col *= smoothstep(0.90,0.10,length(float2((uv.x-0.5)*1.10,uv.y-0.5)));
    return col;
}

fragment float4 prismResonanceBackgroundFragment(RasterizerData in [[stage_in]],
                                                 constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 p  = uv - 0.5;
    float t   = uniforms.time.x;
    float radial = length(p);
    float low  = clamp(uniforms.audioData[4].x *1.9, 0.,1.3);
    float beatPulse = smoothstep(0.05, 0.32, uniforms.audioData[4].w * 5.8 + low * 0.22);
    float3 cAtmo = length(uniforms.galaxyParams2.xyz) > 0.01
                 ? uniforms.galaxyParams2.xyz : float3(0.05,0.02,0.13);
    float atmoI  = clamp(uniforms.galaxyParams2.w, 0.1, 2.0);
    float3 cPulse= length(uniforms.galaxyParams3.xyz) > 0.01
                 ? uniforms.galaxyParams3.xyz : float3(0.90,0.45,1.00);
    float3 cCorona= length(uniforms.cyberpunkBackgroundParams.xyz) > 0.01
                  ? uniforms.cyberpunkBackgroundParams.xyz : float3(0.38,0.72,1.00);
    float3 col = prismResonanceBackground(p, t, radial, low, beatPulse, atmoI, cAtmo, cPulse, cCorona);
    return float4(saturate(col), 1.0);
}

fragment float4 prismResonanceCompositeFragment(RasterizerData in [[stage_in]],
                                                constant Uniforms &uniforms [[buffer(0)]],
                                                texture2d<float> backgroundTexture [[texture(0)]]) {
    float2 uv = in.texCoord;
    float2 correctedUV = aspectCorrect(uv, uniforms.resolution);
    float2 p  = correctedUV - 0.5;
    float t   = uniforms.time.x;
    float radial = length(p);

    int nLayers = clamp((int)round(uniforms.galaxyParams1.x), 2, 3);
    int nSlots  = clamp((int)round(uniforms.galaxyParams1.y), 4, 6);
    float glowI = clamp(uniforms.galaxyParams1.z, 0.5, 2.0);
    float bright = clamp(uniforms.galaxyParams3.w, 0.7, 2.0);
    float aspd = clamp(uniforms.cyberpunkBackgroundParams.w, 0.3, 2.5);
    float low  = clamp(uniforms.audioData[4].x *1.9, 0.,1.3);
    float mid  = clamp(uniforms.audioData[28].x*1.7, 0.,1.2);
    float high = clamp(uniforms.audioData[58].x*2.0, 0.,1.3);
    float energy = clamp(low*0.42 + mid*0.34 + high*0.24, 0., 1.3);

    int lowState  = clamp((int)round(uniforms.cyberpunkControls.x), 0, 2);
    int midState  = clamp((int)round(uniforms.cyberpunkControls.y), 0, 2);
    int highState = clamp((int)round(uniforms.cyberpunkControls.z), 0, 2);
    float lowMorphProgress  = clamp(uniforms.cyberpunkFrequencyControls.x, 0.0, 1.0);
    float midMorphProgress  = clamp(uniforms.cyberpunkFrequencyControls.y, 0.0, 1.0);
    float highMorphProgress = clamp(uniforms.cyberpunkFrequencyControls.z, 0.0, 1.0);

    float3 col = backgroundTexture.sample(prLinearSampler, uv).rgb;
    col += prismResonanceForeground(p, correctedUV, t, radial, uniforms, low, mid, high, energy, aspd, glowI, bright,
                                    nLayers, nSlots, lowState, midState, highState,
                                    lowMorphProgress, midMorphProgress, highMorphProgress);

    col = col/(col+0.82);
    float lum = dot(col,float3(0.299,0.587,0.114));
    col = mix(float3(lum),col,1.16);
    return float4(saturate(col),1.0);
}

fragment float4 prismResonanceFragment(RasterizerData in [[stage_in]],
                                       constant Uniforms &uniforms [[buffer(0)]]) {
    float2 uv = aspectCorrect(in.texCoord, uniforms.resolution);
    float2 p  = uv - 0.5;
    float t   = uniforms.time.x;
    float radial = length(p);

    int nLayers = clamp((int)round(uniforms.galaxyParams1.x), 2, 3);
    int nSlots  = clamp((int)round(uniforms.galaxyParams1.y), 4, 6);
    float glowI = clamp(uniforms.galaxyParams1.z, 0.5, 2.0);

    float3 cAtmo = length(uniforms.galaxyParams2.xyz) > 0.01
                 ? uniforms.galaxyParams2.xyz : float3(0.05,0.02,0.13);
    float atmoI  = clamp(uniforms.galaxyParams2.w, 0.1, 2.0);
    float3 cPulse= length(uniforms.galaxyParams3.xyz) > 0.01
                 ? uniforms.galaxyParams3.xyz : float3(0.90,0.45,1.00);
    float bright = clamp(uniforms.galaxyParams3.w, 0.7, 2.0);
    float3 cCorona= length(uniforms.cyberpunkBackgroundParams.xyz) > 0.01
                  ? uniforms.cyberpunkBackgroundParams.xyz : float3(0.38,0.72,1.00);
    float aspd = clamp(uniforms.cyberpunkBackgroundParams.w, 0.3, 2.5);

    // 低/中/高频能量（仅用于亮度和缩放，不再影响形态状态）
    float low  = clamp(uniforms.audioData[4].x *1.9, 0.,1.3);
    float mid  = clamp(uniforms.audioData[28].x*1.7, 0.,1.2);
    float high = clamp(uniforms.audioData[58].x*2.0, 0.,1.3);
    float energy = clamp(low*0.42 + mid*0.34 + high*0.24, 0., 1.3);
    float beatPulse = smoothstep(0.05, 0.32, uniforms.audioData[4].w * 5.8 + low * 0.22);

    // CPU传来的锁定状态：0=◇ 1=○ 2=❤
    int lowState  = clamp((int)round(uniforms.cyberpunkControls.x), 0, 2);
    int midState  = clamp((int)round(uniforms.cyberpunkControls.y), 0, 2);
    int highState = clamp((int)round(uniforms.cyberpunkControls.z), 0, 2);
    float lowMorphProgress  = clamp(uniforms.cyberpunkFrequencyControls.x, 0.0, 1.0);
    float midMorphProgress  = clamp(uniforms.cyberpunkFrequencyControls.y, 0.0, 1.0);
    float highMorphProgress = clamp(uniforms.cyberpunkFrequencyControls.z, 0.0, 1.0);

    // 背景：简化渐变
    float3 col = mix(cAtmo*float3(0.10,0.06,0.24),
                     cAtmo*float3(0.03,0.02,0.08),
                     smoothstep(-0.5,0.5,p.y));

    // 低成本背景：明确可见的超大半透明气泡，避免被读成雾
    for(int i=0;i<4;i++){
        float fi=float(i);
        float seed=fi*13.7+1.0;
        float depth = 0.78 + 0.22 * prH(seed * 5.9);
        float jitterPhase = t * (1.8 + fi * 0.11) + seed * 3.1;
        float2 beatJitter = float2(
            sin(jitterPhase),
            cos(jitterPhase * 1.17 + seed)
        ) * beatPulse * (0.010 + 0.007 * prH(seed * 8.3)) * depth;
        float2 basePos = float2(
            (prH(seed*1.3)-0.5)*1.18,
            (prH(seed*2.1)-0.5)*1.10
        );
        float2 drift = float2(
            sin(t*(0.11+fi*0.02)+seed)*0.18,
            cos(t*(0.09+fi*0.018)+seed*1.7)*0.16
        ) * depth;
        float2 c = float2(
            basePos.x + drift.x,
            basePos.y + drift.y
        ) + beatJitter;
        float r = ((0.16 + 0.06*prH(seed*3.3)) / depth) * (1.0 + beatPulse * 0.08);
        float d = length(p-c) - r;
        float bubbleFill = smoothstep(0.018, -0.018, d);
        float bubbleRim = smoothstep(0.020, 0.002, abs(d));
        float bubbleInner = smoothstep(0.055, -0.004, d + r * 0.42);
        float breath = 0.90 + 0.10*sin(t*(0.18+fi*0.02)+seed*2.1+low*1.4);
        float3 bCol = mix(cCorona, cPulse, prH(seed*4.7));
        float edgeFade = 1.0 - smoothstep(1.05, 1.42, length(c));
        float bubbleAlpha = (0.19 + atmoI*0.12) * (0.94 + low*0.24 + beatPulse*0.26) * breath * edgeFade;
        col += bCol * bubbleFill * bubbleAlpha * 0.60;
        col += mix(bCol, float3(1.0), 0.34) * bubbleInner * bubbleAlpha * 0.26;
        col += mix(bCol, float3(1.0), 0.68) * bubbleRim * bubbleAlpha * 0.76;
    }

    // 额外小气泡层：不绑定音乐，只做慢速移动和轻微柔化，增加景深层次
    for(int i=0;i<7;i++){
        float fi = float(i);
        float seed = 101.0 + fi * 9.7;
        float depth = 0.72 + 0.28 * prH(seed * 1.9);
        float2 basePos = float2(
            (prH(seed*2.3)-0.5)*1.52,
            (prH(seed*3.1)-0.5)*1.44
        );
        float2 drift = float2(
            sin(t*(0.072+fi*0.008)+seed)*0.082,
            cos(t*(0.066+fi*0.007)+seed*1.3)*0.070
        ) * depth;
        float2 c = basePos + drift;
        float r = (0.040 + 0.026 * prH(seed*4.1)) / depth;
        float d = length(p-c) - r;
        float bubbleFill = smoothstep(0.030, -0.020, d);
        float bubbleSoft = smoothstep(0.080, -0.035, d);
        float3 sCol = mix(cAtmo, cCorona, prH(seed*5.7));
        float alpha = (0.058 + atmoI*0.040) * (0.90 + 0.16*sin(t*(0.18+fi*0.012)+seed)) * (1.0 - smoothstep(1.10, 1.55, length(c)));
        col += sCol * bubbleSoft * alpha * 0.30;
        col += mix(sCol, float3(1.0), 0.12) * bubbleFill * alpha * 0.44;
    }

    // 中心柔光
    col += cPulse * exp(-radial*(4.0-low*1.5)) * (0.10 + atmoI*0.10);

    // 棱镜绘制
    float fw = fwidth(length(p))*1.0 + 0.0010;
    for(int layer=0; layer<4; layer++){
        if(layer>=nLayers) continue;
        float lF     = float(layer)/float(max(nLayers-1,1));
        float szBase = mix(0.014,0.040,lF);
        float alpha  = mix(0.18,1.00,lF);
        float dAmp   = mix(0.006,0.024,lF);
        float dRate  = mix(0.18,0.45,lF)*aspd;
        float feath  = fw*mix(2.4,1.0,lF);

        for(int slot=0; slot<8; slot++){
            if(slot>=nSlots) continue;
            float seed=float(layer*43+slot*71)+3.14;

            // 每个棱形绑定到不同频谱索引，避免整组共用同一触发
            int slotIndex = layer * nSlots + slot;
            int bandIndex = 4 + ((slotIndex * 9 + layer * 5 + 3) % 68);
            float bandSmooth = clamp(uniforms.audioData[bandIndex].y * 1.85, 0.0, 1.35);
            float bandTransient = clamp(uniforms.audioData[bandIndex].w * 5.4, 0.0, 1.4);

            float ev;
            int state;
            float morphProgress;
            float3 bc;
            if(bandIndex < 24){
                ev=bandSmooth;
                state=lowState;
                morphProgress=lowMorphProgress;
                bc=float3(1.00,0.28,0.52);
            } else if(bandIndex < 48){
                ev=bandSmooth;
                state=midState;
                morphProgress=midMorphProgress;
                bc=float3(0.25,0.68,1.00);
            } else {
                ev=bandSmooth;
                state=highState;
                morphProgress=highMorphProgress;
                bc=float3(0.86,0.24,1.00);
            }

            // 同一频段内再做轻微错相，让相邻棱形不再同步硬切
            int stateOffset = (bandIndex + slot + layer) % 3;
            state = (state + stateOffset) % 3;

            float3 dc = mix(bc*float3(0.50,0.65,1.18), bc, lF) * mix(0.25,1.0,lF);

            // 可移动，不固定位置
            float2 anchor = float2((prH(seed*1.37)-0.5)*0.90, (prH(seed*2.53)-0.5)*0.88);
            float2 drift  = float2(sin(t*dRate+seed*1.8)*dAmp,
                                   cos(t*dRate*0.75+seed*1.4)*dAmp*0.7);
            float rot = (prH(seed*3.7)-0.5)*1.2 + t*(prH(seed*0.43)-0.5)*0.03;
            float2 lp = prRot(p-anchor-drift, rot);
            float slotEnergy = clamp(ev * 0.82 + bandTransient * 0.24, 0.0, 1.4);
            float sz  = szBase*(0.82+slotEnergy*0.26);

            // 形态锁定（由CPU状态控制，3s锁定）
            int prevState = (state + 2) % 3;
            float morphT = smoothstep(0.0, 1.0, morphProgress);
            float transitionDip = 1.0 - 0.42 * sin(morphT * 3.14159265);
            float dPrev = prShapeDistance(prevState, lp, sz);
            float dCurr = prShapeDistance(state, lp, sz);
            float th   = sz*0.13;
            float ringPrev = prRing(dPrev,feath,th);
            float ringCurr = prRing(dCurr,feath,th);
            float bodyPrev = prFill(dPrev-th,feath)*(0.05+slotEnergy*0.16);
            float bodyCurr = prFill(dCurr-th,feath)*(0.05+slotEnergy*0.16);
            float corePrev = prFill(dPrev-sz*0.65,feath*0.7);
            float coreCurr = prFill(dCurr-sz*0.65,feath*0.7);
            float ring = (ringPrev * (1.0 - morphT) + ringCurr * morphT) * transitionDip;
            float body = (bodyPrev * (1.0 - morphT) + bodyCurr * morphT) * transitionDip;
            float core = (corePrev * (1.0 - morphT) + coreCurr * morphT) * transitionDip;
            float aura = prFill(prSDCircle(lp,sz*3.5),feath*11.0) * (0.03+slotEnergy*0.08);
            float gain = alpha*bright*(0.78+0.22*sin(t*(1.7+prH(seed)*1.4)+seed));
            gain = clamp(gain,0.,2.0);

            col += dc * aura * glowI * gain;
            col += dc * ring * gain * (0.9+slotEnergy*0.8);
            col += dc * body * gain;
            col += mix(dc,float3(1.0),0.40) * core * gain * (0.6+slotEnergy*0.4);
        }
    }

    // 全局轻微闪光
    float sparkle = pow(max(0.,cos((atan2(p.y,p.x)+t*0.22)*2.5+energy*0.4)),16.0);
    col += cPulse * sparkle * exp(-radial*3.0) * (0.02+high*0.04);

    // 暗角 + tonemap
    col *= smoothstep(0.90,0.10,length(float2((uv.x-0.5)*1.10,uv.y-0.5)));
    col = col/(col+0.82);
    float lum = dot(col,float3(0.299,0.587,0.114));
    col = mix(float3(lum),col,1.16);

    return float4(saturate(col),1.0);
}
