// Direct port of CoverDotMatrix.metal's particle field and 3D artwork relief.
// Each Metal samplePosition becomes a D3D instanced screen-space quad, preserving its size.
struct CoverDotVisualAudio {
    float time; float bass; float mid; float treble; float aspectRatio;
    float guitar; float piano; float drums; float playbackTime;
    float electricGuitarConfidence; float vocal; float guitarPeak; float playing; float other;
    float4 dspFeatureSignals;
    float4 dspFeatureTexture;
};
struct CoverMoodColors {
    float4 atmosphere, volumetricBeam, topLightArray, laserFanBlue, laserFanGreen;
    float4 rotatingBeam, rotatingBeamExtra, edgeLight, coronaFilaments, pulseRing;
};
struct DesktopDotParticleOut {
    float4 position;
    float pointSize;
    float3 color;
    float opacity;
    float height;
};

float3 desktopCoverDisplayColor(float3 linearColor);

// iOS CoverDotMatrix base style: one Metal samplePosition per fixed cover sample.
DesktopDotParticleOut desktopDotParticleVertex(
    uint id ,
    CoverDotVisualAudio audio ,
    float4 controls ,
    float4 styleControls ,
    CoverMoodColors mood ,
    uint unusedTexture ) {
    float grid = clamp(round(controls.x), 72.0, 384.0);
    uint gridCount = uint(grid);
    float screenAspect = max(audio.aspectRatio, 0.1);
    uint gridRows = uint(max(1.0, round(grid / screenAspect)));
    float2 uv = float2((float(id % gridCount) + 0.5) / grid,
                       (float(id / gridCount) + 0.5) / float(gridRows));
    // Keep this effect's album-art mask square. Other desktop effects may draw
    // the separate circular record overlay, but the cover-dot field stays square.
    float coverHeight = 0.68;
    float coverWidth = coverHeight / screenAspect;
    float2 coverSize = float2(coverWidth, coverHeight);
    float2 coverOrigin = (1.0 - coverSize) * 0.5;
    float2 coverUV = (uv - coverOrigin) / max(coverSize, float2(0.001));
    bool insideCover = controls.z > 0.5 & all(coverUV >= 0.0) & all(coverUV <= 1.0);
    float2 visualUV = insideCover ? coverUV : uv;
    float middle = saturate(audio.mid);
    float high = saturate(audio.treble);
    float piano = saturate(max(audio.piano, middle * 0.8 * controls.z));
    float guitar = saturate(max(audio.guitar, high * 0.75 * controls.z));
    float beat = saturate(styleControls.y);
    float pianoWave = sin(visualUV.x * 21.0 + audio.time * 2.4) * cos(visualUV.y * 17.0 - audio.time * 1.7);
    float guitarWave = sin(visualUV.x * 42.0 + visualUV.y * 35.0 + audio.time * 5.2);
    float otherDrive = saturate(audio.other);
    float otherWave = sin(visualUV.x * 12.0 - visualUV.y * 8.0 + audio.time * 2.8)
                    * cos(visualUV.y * 15.0 + audio.time * 1.9);
    float idleWave = sin(visualUV.x * 9.0 + visualUV.y * 4.0 - audio.time * 0.72) * 0.035;
    // The drum wave lives only in the empty dot field outside the artwork.
    float2 coverEdge = max(abs(coverUV - 0.5) - 0.5, 0.0);
    float outsideDistance = length(coverEdge) * coverHeight;
    float waveDistance = 0.025 + min(styleControls.z, 0.65) * 0.90;
    float wave = exp(-pow((outsideDistance - waveDistance) / 0.11, 2.0));
    float sparkle = frac(sin(dot(floor(uv * float2(grid, float(gridRows))), float2(12.9898, 78.233))) * 43758.5453);
    float outerBeat = insideCover ? 0.0 : beat * wave * smoothstep(0.30, 0.80, sparkle);
    // HTDemucs stem envelopes drive independent piano/guitar fields. FFT remains
    // the fallback when those model-derived envelopes are unavailable.
    float height = idleWave + pianoWave * piano * 0.23 + guitarWave * guitar * 0.16
                 + otherWave * otherDrive * 0.075;
    float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    clip += height * float2(0.018, 0.064);
    // HPSS residual + spectral flatness drive a restrained, horizontal current tear.
    // It is isolated to the dot field and leaves the artwork and drum pulse intact.
    float rawElectric = saturate(audio.dspFeatureSignals.y);
    float electricTear = smoothstep(0.06, 0.38, rawElectric) * saturate(audio.playing);
    float tearRow = floor(uv.y * 34.0 + floor(audio.time * 9.0));
    float tearHash = frac(sin(tearRow * 127.1 + floor(audio.time * 6.0) * 311.7) * 43758.5453);
    float tearGate = step(0.58 - electricTear * 0.32, tearHash)
                   * (1.0 - step(0.28, abs(frac(uv.y * 34.0) - 0.5)));
    float tearStrength = electricTear * tearGate;
    clip.x += (tearHash - 0.5) * tearStrength * 0.22;
    clip.y += (tearHash - 0.5) * tearStrength * 0.012;
    float pitch = controls.w / grid;
    // Fixed screen-space dots keep Retina drawable dimensions from inflating each sample.
    // Drum hits illuminate the surrounding dots without changing their size.
    float size = min(pitch * controls.y * 0.82, 8.0) * (0.98 + height * 0.14);

    DesktopDotParticleOut result;
    result.position = float4(clip, 0.0, 1.0);
    result.pointSize = clamp(size, 1.5, 8.0);
    float3 fieldColor = float3(0.048, 0.060, 0.086);
    float3 tearColor = lerp(float3(0.05, 0.82, 1.0), float3(1.0, 0.12, 0.62), tearHash);
    result.color = fieldColor + outerBeat * mood.pulseRing.rgb + tearColor * tearStrength * 0.9;
    // Keep a dim underlay below cover particles so the square render target
    // cannot show through their gaps. Outside it, retain the original response.
    result.opacity = insideCover ? 0.38 : 0.11 + outerBeat * 0.73;
    result.height = height;
    return result;
}

// Native Metal implementation of a regular artwork samplePosition plane with restrained
// depth relief and perspective-scaled dots. The grid never jitters in image space.
// Color is sampled independently of depth so small artwork details stay intact.
float displayChannel(float x) {
    return x <= 0.0031308 ? x * 12.92 : 1.055 * pow(max(x, 0.0), 1.0 / 2.4) - 0.055;
}
float3 desktopCoverDisplayColor(float3 linearColor) {
    return float3(displayChannel(linearColor.r), displayChannel(linearColor.g), displayChannel(linearColor.b));
}

// Identical stage geometry for the cover and lyric particles. All coordinates
// are in artwork-height units; the projection preserves physical image aspect.
struct DesktopCoverStageUniforms {
    float4 rotation;
    float4 pointer;
    float4 layout;
    float4 audio;
    float4 viewport;
};

float3 desktopStageRotate(float3 p, DesktopCoverStageUniforms stage) {
    float yaw = stage.rotation.x, pitch = stage.rotation.y, roll = stage.rotation.w;
    p = float3(p.x * cos(yaw) + p.z * sin(yaw), p.y,
               -p.x * sin(yaw) + p.z * cos(yaw));
    p = float3(p.x, p.y * cos(pitch) - p.z * sin(pitch),
               p.y * sin(pitch) + p.z * cos(pitch));
    return float3(p.x * cos(roll) - p.y * sin(roll),
                  p.x * sin(roll) + p.y * cos(roll), p.z);
}

float desktopHash3(float3 p) {
    p = frac(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return frac((p.x + p.y) * p.z);
}

float desktopValueNoise3(float3 p) {
    float3 cell = floor(p);
    float3 f = frac(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = lerp(desktopHash3(cell), desktopHash3(cell + float3(1, 0, 0)), f.x);
    float b = lerp(desktopHash3(cell + float3(0, 1, 0)), desktopHash3(cell + float3(1, 1, 0)), f.x);
    float c = lerp(desktopHash3(cell + float3(0, 0, 1)), desktopHash3(cell + float3(1, 0, 1)), f.x);
    float d = lerp(desktopHash3(cell + float3(0, 1, 1)), desktopHash3(cell + float3(1, 1, 1)), f.x);
    return lerp(lerp(a, b, f.y), lerp(c, d, f.y), f.z) * 2.0 - 1.0;
}

float4 desktopStageProject(float3 p, DesktopCoverStageUniforms stage) {
    // Keep every sample fixed in the artwork plane. Time-varying depth noise
    // made the dots shimmer as they crossed pixels during a slow record turn.
    float3 rotated = desktopStageRotate(p, stage);
    float camera = stage.layout.w;
    float2 scale = float2(stage.layout.y * 2.0 / stage.layout.x, stage.layout.y * 2.0);
    float2 projected = rotated.xy * scale * camera / max(camera - rotated.z, 0.3);
    float2 delta = (projected - stage.pointer.xy) * float2(stage.layout.x, 1.0);
    float proximity = saturate(1.0 - length(delta) / max(stage.pointer.w, 0.01));
    float hoverBulge = proximity * proximity * max(stage.pointer.z, 0.0);
    float pressDent = proximity * proximity * max(-stage.pointer.z, 0.0);
    // Hover gently lifts the field; holding the mouse presses a wider concavity.
    rotated.z += hoverBulge * 0.11 - pressDent * 0.42;
    rotated.xy += delta * (hoverBulge * 0.012 - pressDent * 0.035);
    rotated *= stage.rotation.z;
    float w = max(camera - rotated.z, 0.3);
    return float4(rotated.xy * scale * camera, w * 0.5, w);
}

DesktopDotParticleOut desktopCoverReliefVertex(
    uint id ,
    CoverDotVisualAudio audio ,
    float4 controls ,
    CoverMoodColors mood ,
    float4 layout ,
    DesktopCoverStageUniforms stage ,
    uint unusedTexture ) {
    uint artWidth, artHeight;
    artwork.GetDimensions(artWidth, artHeight);
    uint columns = uint(controls.x);
    uint rows = uint(controls.y);
    float2 uv = (float2(float(id % columns), float(id / columns)) + 0.5)
              / float2(float(columns), float(rows));
    float2 discUV = (uv - 0.5) * 2.0;
    float radius = length(discUV);
    bool squareCover = layout.z > 0.5;
    float edgeDistance = squareCover ? max(abs(discUV.x), abs(discUV.y)) : radius;
    float imageAspect = float(artWidth) / max(float(artHeight), 1.0);
    float2 sampleUV = uv;
    if (imageAspect > 1.0) sampleUV.x = (uv.x - 0.5) / imageAspect + 0.5;
    else sampleUV.y = (uv.y - 0.5) * imageAspect + 0.5;
    float3 linearColor = artwork.SampleLevel(artworkSampler, sampleUV, 0.0).rgb;
    float3 color = desktopCoverDisplayColor(linearColor);

    // Smooth local luminance creates a shallow relief; it is a heuristic depth
    // field, not an inferred semantic depth map or another Core ML job.
    float2 sampleStep = 2.0 / float2(float(columns), float(rows));
    float3 neighborhood = linearColor * 0.4
        + (artwork.SampleLevel(artworkSampler, sampleUV + float2(sampleStep.x, 0), 0.0).rgb
        +  artwork.SampleLevel(artworkSampler, sampleUV - float2(sampleStep.x, 0), 0.0).rgb
        +  artwork.SampleLevel(artworkSampler, sampleUV + float2(0, sampleStep.y), 0.0).rgb
        +  artwork.SampleLevel(artworkSampler, sampleUV - float2(0, sampleStep.y), 0.0).rgb) * 0.15;
    float luminance = dot(desktopCoverDisplayColor(neighborhood), float3(0.2126, 0.7152, 0.0722));
    float edgeGuard = 1.0 - smoothstep(0.965, 1.0, edgeDistance);
    // Use the entire square image in cover mode; circular clipping is reserved
    // for the record overlay used by the other desktop effects.
    color = controls.w > 0.5 ? color : lerp(float3(0.07, 0.10, 0.16), mood.atmosphere.rgb, 0.18);
    float rim = squareCover ? 0.0 : exp(-pow((radius - 0.975) / 0.012, 2.0));
    color += mood.volumetricBeam.rgb * rim * (0.055 + saturate(audio.bass) * 0.07);
    float z = (luminance - 0.5) * 0.12 * edgeGuard;
    float3 samplePosition = float3(discUV.x * 0.5, -discUV.y * 0.5, z);
    // Restore the cover's instrument response: a diagonal guitar resonance
    // travels through depth and light, while piano adds a quieter broad lift.
    // Neither stem moves the artwork samples sideways or changes their UVs.
    float guitarDrive = squareCover ? smoothstep(0.03, 0.42, saturate(stage.audio.x)) : 0.0;
    float pianoDrive = squareCover ? saturate(stage.audio.y) : 0.0;
    float otherDrive = squareCover ? saturate(stage.audio.z) : 0.0;
    float stringAxis = uv.x * 0.88 + uv.y * 0.46;
    float stringPhase = stringAxis * 34.0 - stage.viewport.w * 6.0
                      + sin(uv.x * 8.0 - stage.viewport.w * 0.65) * 0.65;
    float stringLane = exp(-pow((uv.y - 0.50
                      - sin(uv.x * 5.0 - stage.viewport.w * 0.48) * 0.10) / 0.34, 2.0));
    float stringWave = sin(stringPhase) + 0.22 * sin(stringPhase * 1.72 + uv.x * 5.0);
    float pianoWave = sin(uv.y * 14.0 + stage.viewport.w * 1.7);
    float otherWave = sin((uv.x * 0.68 + uv.y * 0.32) * 22.0 - stage.viewport.w * 2.2)
                    * cos(uv.y * 10.0 + stage.viewport.w * 1.25);
    samplePosition.z += guitarDrive * stringLane * stringWave * 0.085
             + pianoDrive * pianoWave * 0.022
             + otherDrive * otherWave * 0.040;
    // Feed the live DSP feature into the foreground cover particles too. The
    // full-screen background field is rendered first and is mostly hidden here.
    float electricActivity = squareCover
        ? smoothstep(0.045, 0.30, saturate(audio.dspFeatureSignals.y)) * saturate(audio.playing)
        : 0.0;
    float electricRow = floor(uv.y * 30.0 + floor(stage.viewport.w * 8.0));
    float electricHash = frac(sin(electricRow * 127.1 + floor(stage.viewport.w * 5.0) * 311.7) * 43758.5453);
    float electricLane = step(0.60 - electricActivity * 0.34, electricHash)
                       * (1.0 - step(0.32, abs(frac(uv.y * 30.0) - 0.5)));
    float electricTear = electricActivity * electricLane;
    samplePosition.x += (electricHash - 0.5) * electricTear * 0.11;
    samplePosition.y += (electricHash - 0.5) * electricTear * 0.008;
    DesktopDotParticleOut result;
    result.position = desktopStageProject(samplePosition, stage);
    // Perspective size returns on the square 3D cover. Keep the spinning
    // record's dot size to avoid shimmer during its slow rotation.
    result.pointSize = max(1.0, controls.z * (squareCover ? stage.layout.w / result.position.w : 1.0));
    float resonanceLight = guitarDrive * stringLane
        * (0.5 + 0.5 * saturate(stringWave * 0.62 + 0.5)) * 0.30;
    float pianoLight = pianoDrive * (0.5 + 0.5 * pianoWave) * 0.06;
    float otherLight = otherDrive * (0.5 + 0.5 * otherWave) * 0.16;
    float3 electricColor = lerp(float3(0.05, 0.88, 1.0), float3(1.0, 0.08, 0.62), electricHash);
    result.color = clamp(((color - 0.5) * 1.08 + 0.5)
                * (1.0 + resonanceLight + pianoLight + otherLight)
                + electricColor * electricTear * 0.92, 0.0, 1.0);
    result.opacity = 0.98;
    if (!squareCover) {
        result.opacity *= 1.0 - smoothstep(0.965, 1.0, radius);
        if (radius > 1.0) result.opacity = 0.0;
    }
    result.height = z;
    return result;
}


CoverMoodColors coverMood() {
    CoverMoodColors m;
    m.atmosphere=float4(1,.88,.72,1); m.volumetricBeam=float4(1,.85,.65,1);
    m.topLightArray=float4(.3,.6,1,1); m.laserFanBlue=float4(.25,.55,1,1);
    m.laserFanGreen=float4(.35,1,.45,1); m.rotatingBeam=float4(1,.4,.8,1);
    m.rotatingBeamExtra=float4(1,.5,.9,1); m.edgeLight=float4(1,.75,.35,1);
    m.coronaFilaments=float4(.9,.6,.8,1); m.pulseRing=float4(.8,.3,1,1);
    return m;
}
CoverDotVisualAudio coverAudio() {
    CoverDotVisualAudio a=(CoverDotVisualAudio)0;
    a.time=time; a.bass=low; a.mid=mid; a.treble=high; a.aspectRatio=aspect;
    a.guitar=guitar; a.piano=piano; a.drums=drums; a.playbackTime=instrumentEnvelopes.z;
    a.guitarPeak=dynamics.z; a.playing=viewport.w;
    a.dspFeatureSignals=dspFeatureSignals; a.dspFeatureTexture=dspFeatureTexture;
    return a;
}
struct ParticleQuad {
    float4 position : SV_Position;
    float2 pointCoord : TEXCOORD0;
    float3 color : COLOR0;
    float opacity : TEXCOORD1;
};
ParticleQuad expandParticle(DesktopDotParticleOut p, uint vertexID) {
    const float2 corners[6] = {float2(-1,-1),float2(1,-1),float2(-1,1),
                               float2(-1,1),float2(1,-1),float2(1,1)};
    float2 corner=corners[vertexID];
    ParticleQuad q;
    q.position=p.position;
    q.position.xy += corner * p.pointSize / max(viewport.xy,float2(1,1)) * p.position.w;
    q.pointCoord=corner*.5+.5; q.color=p.color; q.opacity=p.opacity;
    return q;
}
ParticleQuad coverFieldVS(uint vertexID : SV_VertexID, uint id : SV_InstanceID) {
    float4 controls=float4(256,1,hasArtwork,viewport.y);
    DesktopDotParticleOut p=desktopDotParticleVertex(id,coverAudio(),controls,
                                float4(0,dynamics.x,dynamics.y,1),coverMood(),0);
    return expandParticle(p,vertexID);
}
ParticleQuad coverReliefVS(uint vertexID : SV_VertexID, uint id : SV_InstanceID) {
    bool squareCover=effectIndex==2;
    float coverHeight=squareCover ? .68 : .56;
    float columns=clamp(round(coverHeight*viewport.y/max(viewport.z,1)/2.8),2,512);
    float pitch=coverHeight*viewport.y/columns;
    DesktopCoverStageUniforms s;
    s.rotation=coverRotation;
    if (!squareCover) s.rotation.w+=instrumentEnvelopes.z*.24;
    s.pointer=coverPointer; s.layout=float4(aspect,coverHeight,1,3.2);
    s.audio=float4(instrumentEnvelopes.xy,0,saturate(high)); s.viewport=float4(viewport.xyz,time);
    DesktopDotParticleOut p=desktopCoverReliefVertex(id,coverAudio(),
                          float4(columns,columns,pitch*.90,hasArtwork),coverMood(),
                          float4(coverHeight/aspect,coverHeight,squareCover?1:0,0),s,0);
    return expandParticle(p,vertexID);
}
float4 coverFieldPS(ParticleQuad input) : SV_Target {
    float d=length(input.pointCoord-.5)*2;
    float core=1-smoothstep(.72,.98,d), glow=exp(-d*d*7);
    float alpha=saturate(core*.98+glow*.06)*input.opacity;
    clip(alpha-.015);
    return float4(input.color,alpha);
}
float4 coverReliefPS(ParticleQuad input) : SV_Target {
    float r=length(input.pointCoord-.5)*2;
    float feather=clamp(fwidth(r),.035,.12);
    float alpha=(1-smoothstep(1-feather,1,r))*input.opacity;
    clip(alpha-.01);
    return float4(input.color,alpha);
}

struct CoverBackingOut {
    float4 position : SV_Position;
    float2 discPosition : TEXCOORD0;
};
CoverBackingOut coverBackingVS(uint vertexID : SV_VertexID) {
    const float2 corners[6]={float2(-1,-1),float2(1,-1),float2(-1,1),
                            float2(-1,1),float2(1,-1),float2(1,1)};
    DesktopCoverStageUniforms s;
    s.rotation=coverRotation; s.rotation.w+=instrumentEnvelopes.z*.24;
    s.pointer=coverPointer; s.layout=float4(aspect,.56,1,3.2);
    s.audio=0; s.viewport=float4(viewport.xyz,time);
    CoverBackingOut q; q.discPosition=corners[vertexID];
    q.position=desktopStageProject(float3(q.discPosition*.505,0),s);
    return q;
}
float4 coverBackingPS(CoverBackingOut input) : SV_Target {
    float radius=length(input.discPosition);
    float feather=max(fwidth(radius),.001);
    float alpha=1-smoothstep(1-feather,1,radius);
    clip(alpha-.001);
    return float4(0,0,0,alpha);
}
