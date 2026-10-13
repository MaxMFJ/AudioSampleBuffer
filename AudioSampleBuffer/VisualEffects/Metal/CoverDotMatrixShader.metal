#include <metal_stdlib>
using namespace metal;

// Phone port of the Mac cover-dot stage. Screen-space math matches the desktop
// shaders; screenMap then places that frame inside the centered square drawable.
struct PhoneCoverAudio {
    float time; float bass; float mid; float treble; float aspectRatio;
    float guitar; float piano; float drums; float playbackTime; float other;
};
struct PhoneCoverMood {
    float4 atmosphere;
    float4 volumetricBeam;
    float4 pulseRing;
};
struct PhoneCoverParticle {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float opacity;
    float height;
};
struct PhoneCoverStage {
    float4 rotation; // yaw, pitch, zoom, roll
    float4 pointer;  // screen NDC x/y, force, radius
    float4 layout;   // screen aspect, cover height, reserved, camera distance
    float4 audio;    // guitar, piano, other, treble
    float4 viewport; // drawable size, pixel ratio, time
    float4 screenMap; // visible width/square, visible height/square
};

constexpr sampler phoneCoverSampler(coord::normalized, address::clamp_to_edge, filter::linear);

float3 phoneCoverDisplayColor(float3 linearColor) {
    return select(1.055 * pow(max(linearColor, float3(0.0)), float3(1.0 / 2.4)) - 0.055,
                  linearColor * 12.92, linearColor <= 0.0031308);
}

float phoneCoverHeight(float aspect) {
    // Landscape uses the Mac 0.68 screen-height square. Portrait uses 0.68 of
    // the shorter side so the same square stays fully on screen.
    return 0.68 * min(max(aspect, 0.1), 1.0);
}

vertex float4 phoneCoverBackdropVertex(uint id [[vertex_id]]) {
    float2 positions[3] = {float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0)};
    return float4(positions[id], 0.0, 1.0);
}

fragment float4 phoneCoverBackdropFragment() {
    return float4(0.006, 0.009, 0.025, 1.0);
}

vertex PhoneCoverParticle phoneCoverFieldVertex(
    uint id [[vertex_id]],
    constant PhoneCoverAudio &audio [[buffer(0)]],
    constant float4 &controls [[buffer(1)]],
    constant float4 &styleControls [[buffer(2)]],
    constant PhoneCoverMood &mood [[buffer(3)]],
    constant float4 &screenMap [[buffer(4)]],
    texture2d<float> cover [[texture(0)]]) {
    float grid = clamp(round(controls.x), 72.0, 384.0);
    uint gridCount = uint(grid);
    float screenAspect = max(audio.aspectRatio, 0.1);
    uint gridRows = uint(max(1.0, screenMap.z));
    float2 uv = float2((float(id % gridCount) + 0.5) / grid,
                       (float(id / gridCount) + 0.5) / float(gridRows));
    float coverHeight = phoneCoverHeight(screenAspect);
    float coverWidth = coverHeight / screenAspect;
    float2 coverSize = float2(coverWidth, coverHeight);
    float2 coverOrigin = (1.0 - coverSize) * 0.5;
    float2 coverUV = (uv - coverOrigin) / max(coverSize, float2(0.001));
    bool insideCover = controls.z > 0.5 && all(coverUV >= 0.0) && all(coverUV <= 1.0);
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
    float2 coverEdge = max(abs(coverUV - 0.5) - 0.5, 0.0);
    float outsideDistance = length(coverEdge) * coverHeight;
    float waveDistance = 0.025 + min(styleControls.z, 0.65) * 0.90;
    float wave = exp(-pow((outsideDistance - waveDistance) / 0.11, 2.0));
    float sparkle = fract(sin(dot(floor(uv * float2(grid, float(gridRows))), float2(12.9898, 78.233))) * 43758.5453);
    float outerBeat = insideCover ? 0.0 : beat * wave * smoothstep(0.30, 0.80, sparkle);
    float height = idleWave + pianoWave * piano * 0.23 + guitarWave * guitar * 0.16
                 + otherWave * otherDrive * 0.075;
    float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    clip += height * float2(0.018, 0.064);
    clip *= max(screenMap.xy, float2(0.001));
    float pitch = controls.w / grid;
    float size = min(pitch * controls.y * 0.82, 8.0) * (0.98 + height * 0.14);

    PhoneCoverParticle out;
    out.position = float4(clip, 0.0, 1.0);
    out.pointSize = clamp(size, 1.5, 8.0);
    float3 fieldColor = float3(0.048, 0.060, 0.086);
    out.color = fieldColor + outerBeat * mood.pulseRing.rgb;
    // Keep a dim underlay below cover particles so the square render target
    // cannot show through their gaps. Outside it, retain the original response.
    out.opacity = insideCover ? 0.38 : 0.11 + outerBeat * 0.73;
    out.height = height;
    return out;
}

fragment float4 phoneCoverFieldFragment(PhoneCoverParticle in [[stage_in]],
                                        float2 pointCoord [[point_coord]]) {
    float distanceFromCenter = length(pointCoord - 0.5) * 2.0;
    float core = 1.0 - smoothstep(0.72, 0.98, distanceFromCenter);
    float glow = exp(-distanceFromCenter * distanceFromCenter * 7.0);
    float alpha = saturate(core * 0.98 + glow * 0.06) * in.opacity;
    if (alpha < 0.015) discard_fragment();
    return float4(in.color, alpha);
}

float3 phoneStageRotate(float3 p, constant PhoneCoverStage &stage) {
    float yaw = stage.rotation.x, pitch = stage.rotation.y, roll = stage.rotation.w;
    p = float3(p.x * cos(yaw) + p.z * sin(yaw), p.y,
               -p.x * sin(yaw) + p.z * cos(yaw));
    p = float3(p.x, p.y * cos(pitch) - p.z * sin(pitch),
               p.y * sin(pitch) + p.z * cos(pitch));
    return float3(p.x * cos(roll) - p.y * sin(roll),
                  p.x * sin(roll) + p.y * cos(roll), p.z);
}

float4 phoneStageProject(float3 p, constant PhoneCoverStage &stage) {
    float3 rotated = phoneStageRotate(p, stage);
    float camera = stage.layout.w;
    float2 scale = float2(stage.layout.y * 2.0 / stage.layout.x, stage.layout.y * 2.0);
    float2 projected = rotated.xy * scale * camera / max(camera - rotated.z, 0.3);
    float2 delta = (projected - stage.pointer.xy) * float2(stage.layout.x, 1.0);
    float proximity = saturate(1.0 - length(delta) / max(stage.pointer.w, 0.01));
    float hoverBulge = proximity * proximity * max(stage.pointer.z, 0.0);
    float pressDent = proximity * proximity * max(-stage.pointer.z, 0.0);
    rotated.z += hoverBulge * 0.11 - pressDent * 0.42;
    rotated.xy += delta * (hoverBulge * 0.012 - pressDent * 0.035);
    rotated *= stage.rotation.z;
    float w = max(camera - rotated.z, 0.3);
    float4 position = float4(rotated.xy * scale * camera, w * 0.5, w);
    position.xy *= max(stage.screenMap.xy, float2(0.001));
    return position;
}

vertex PhoneCoverParticle phoneCoverReliefVertex(
    uint id [[vertex_id]],
    constant PhoneCoverAudio &audio [[buffer(0)]],
    constant float4 &controls [[buffer(1)]],
    constant PhoneCoverMood &mood [[buffer(3)]],
    constant float4 &layout [[buffer(4)]],
    constant PhoneCoverStage &stage [[buffer(5)]],
    texture2d<float> cover [[texture(0)]]) {
    uint columns = uint(controls.x);
    uint rows = uint(controls.y);
    float2 uv = (float2(float(id % columns), float(id / columns)) + 0.5)
              / float2(float(columns), float(rows));
    float2 discUV = (uv - 0.5) * 2.0;
    float radius = length(discUV);
    bool squareCover = layout.z > 0.5;
    float edgeDistance = squareCover ? max(abs(discUV.x), abs(discUV.y)) : radius;
    float imageAspect = float(cover.get_width()) / max(float(cover.get_height()), 1.0);
    float2 sampleUV = uv;
    if (imageAspect > 1.0) sampleUV.x = (uv.x - 0.5) / imageAspect + 0.5;
    else sampleUV.y = (uv.y - 0.5) * imageAspect + 0.5;
    float3 linearColor = cover.sample(phoneCoverSampler, sampleUV, level(0.0)).rgb;
    float3 color = phoneCoverDisplayColor(linearColor);

    float2 step = 2.0 / float2(float(columns), float(rows));
    float3 neighborhood = linearColor * 0.4
        + (cover.sample(phoneCoverSampler, sampleUV + float2(step.x, 0), level(0.0)).rgb
        +  cover.sample(phoneCoverSampler, sampleUV - float2(step.x, 0), level(0.0)).rgb
        +  cover.sample(phoneCoverSampler, sampleUV + float2(0, step.y), level(0.0)).rgb
        +  cover.sample(phoneCoverSampler, sampleUV - float2(0, step.y), level(0.0)).rgb) * 0.15;
    float luminance = dot(phoneCoverDisplayColor(neighborhood), float3(0.2126, 0.7152, 0.0722));
    float edgeGuard = 1.0 - smoothstep(0.965, 1.0, edgeDistance);
    color = controls.w > 0.5 ? color : mix(float3(0.07, 0.10, 0.16), mood.atmosphere.rgb, 0.18);
    float rim = squareCover ? 0.0 : exp(-pow((radius - 0.975) / 0.012, 2.0));
    color += mood.volumetricBeam.rgb * rim * (0.055 + saturate(audio.bass) * 0.07);
    float z = (luminance - 0.5) * 0.12 * edgeGuard;
    float3 point = float3(discUV.x * 0.5, -discUV.y * 0.5, z);
    // Stems lead, but live FFT keeps the same waves moving when a stem is quiet.
    // The stem curve reaches full strength earlier than the desktop 0.42 gate.
    float fftGuitar = smoothstep(0.02, 0.42, saturate(audio.treble));
    float fftPiano = smoothstep(0.02, 0.40, saturate(audio.mid));
    float fftOther = smoothstep(0.02, 0.38, saturate(max(audio.bass, audio.mid * 0.45)));
    float guitarDrive = squareCover ? max(smoothstep(0.0, 0.16, saturate(stage.audio.x)), fftGuitar * 0.82) : 0.0;
    float pianoDrive = squareCover ? max(smoothstep(0.0, 0.14, saturate(stage.audio.y)), fftPiano * 0.72) : 0.0;
    float otherDrive = squareCover ? max(smoothstep(0.0, 0.12, saturate(stage.audio.z)), fftOther * 0.68) : 0.0;
    float stringAxis = uv.x * 0.88 + uv.y * 0.46;
    float stringPhase = stringAxis * 34.0 - stage.viewport.w * 6.0
                      + sin(uv.x * 8.0 - stage.viewport.w * 0.65) * 0.65;
    float stringLane = exp(-pow((uv.y - 0.50
                      - sin(uv.x * 5.0 - stage.viewport.w * 0.48) * 0.10) / 0.34, 2.0));
    float stringWave = sin(stringPhase) + 0.22 * sin(stringPhase * 1.72 + uv.x * 5.0);
    float pianoWave = sin(uv.y * 14.0 + stage.viewport.w * 1.7);
    float otherWave = sin((uv.x * 0.68 + uv.y * 0.32) * 22.0 - stage.viewport.w * 2.2)
                    * cos(uv.y * 10.0 + stage.viewport.w * 1.25);
    point.z += guitarDrive * stringLane * stringWave * 0.085
             + pianoDrive * pianoWave * 0.022
             + otherDrive * otherWave * 0.040;
    PhoneCoverParticle out;
    out.position = phoneStageProject(point, stage);
    out.pointSize = max(1.0, controls.z * (squareCover ? stage.layout.w / out.position.w : 1.0));
    float resonanceLight = guitarDrive * stringLane
        * (0.5 + 0.5 * saturate(stringWave * 0.62 + 0.5)) * 0.30;
    float pianoLight = pianoDrive * (0.5 + 0.5 * pianoWave) * 0.06;
    float otherLight = otherDrive * (0.5 + 0.5 * otherWave) * 0.16;
    out.color = clamp(((color - 0.5) * 1.08 + 0.5)
                * (1.0 + resonanceLight + pianoLight + otherLight), 0.0, 1.0);
    out.opacity = 0.98;
    if (!squareCover) {
        out.opacity *= 1.0 - smoothstep(0.965, 1.0, radius);
        if (radius > 1.0) out.opacity = 0.0;
    }
    out.height = z;
    return out;
}

fragment float4 phoneCoverReliefFragment(PhoneCoverParticle in [[stage_in]],
                                         float2 pointCoord [[point_coord]]) {
    float r = length(pointCoord - 0.5) * 2.0;
    float feather = clamp(fwidth(r), 0.035, 0.12);
    float alpha = (1.0 - smoothstep(1.0 - feather, 1.0, r)) * in.opacity;
    if (alpha < 0.01) discard_fragment();
    return float4(in.color, alpha);
}
