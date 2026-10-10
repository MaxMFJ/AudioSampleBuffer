#include <metal_stdlib>
using namespace metal;

struct CoverDotVisualAudio {
    float time; float bass; float mid; float treble; float aspectRatio;
    float guitar; float piano; float drums; float playbackTime;
};
struct DesktopMoodColors {
    float4 atmosphere, volumetricBeam, topLightArray, laserFanBlue, laserFanGreen;
    float4 rotatingBeam, rotatingBeamExtra, edgeLight, coronaFilaments, pulseRing;
};
struct DesktopDotParticleOut {
    float4 position [[position]];
    float pointSize [[point_size]];
    float3 color;
    float opacity;
    float height;
};
constexpr sampler desktopCoverSampler(coord::normalized, address::clamp_to_edge, filter::linear);

// iOS CoverDotMatrix base style: one Metal point per fixed cover sample.
vertex DesktopDotParticleOut desktopDotParticleVertex(
    uint id [[vertex_id]],
    constant CoverDotVisualAudio &audio [[buffer(0)]],
    constant float4 &controls [[buffer(1)]],
    constant float4 &styleControls [[buffer(2)]],
    constant DesktopMoodColors &mood [[buffer(3)]],
    texture2d<float> cover [[texture(0)]]) {
    float grid = clamp(round(controls.x), 72.0, 384.0);
    uint gridCount = uint(grid);
    float screenAspect = max(audio.aspectRatio, 0.1);
    uint gridRows = uint(max(1.0, round(grid / screenAspect)));
    float2 uv = float2((float(id % gridCount) + 0.5) / grid,
                       (float(id / gridCount) + 0.5) / float(gridRows));
    float coverAspect = float(cover.get_width()) / max(float(cover.get_height()), 1.0);
    // Keep this effect's album-art mask square. Other desktop effects may draw
    // the separate circular record overlay, but the cover-dot field stays square.
    float coverHeight = 0.68;
    float coverWidth = coverHeight / screenAspect;
    float2 coverSize = float2(coverWidth, coverHeight);
    float2 coverOrigin = (1.0 - coverSize) * 0.5;
    float2 coverUV = (uv - coverOrigin) / max(coverSize, float2(0.001));
    bool insideCover = controls.z > 0.5 && all(coverUV >= 0.0) && all(coverUV <= 1.0);
    float2 imageUV = clamp(coverUV, 0.0, 1.0);
    if (coverAspect > 1.0) imageUV.x = (imageUV.x - 0.5) / coverAspect + 0.5;
    else imageUV.y = (imageUV.y - 0.5) * coverAspect + 0.5;
    float3 sampledColor = cover.sample(desktopCoverSampler, imageUV, level(0.0)).rgb;
    // The texture is decoded as linear sRGB but MTKView writes to a non-sRGB
    // drawable. Encode for display here; otherwise album art looks muddy/dim.
    float3 displayColor = pow(max(sampledColor, float3(0.0)), float3(1.0 / 2.2));
    float luminance = dot(displayColor, float3(0.2126, 0.7152, 0.0722));
    float3 vividColor = clamp((displayColor - luminance) * 1.16 + luminance * 1.12, 0.0, 1.0);
    float3 coverColor = insideCover ? vividColor : float3(0.048, 0.060, 0.086);
    float2 visualUV = insideCover ? coverUV : uv;
    float middle = saturate(audio.mid);
    float high = saturate(audio.treble);
    float piano = saturate(max(audio.piano, middle * 0.8 * controls.z));
    float guitar = saturate(max(audio.guitar, high * 0.75 * controls.z));
    float beat = saturate(styleControls.y);
    float pianoWave = sin(visualUV.x * 21.0 + audio.time * 2.4) * cos(visualUV.y * 17.0 - audio.time * 1.7);
    float guitarWave = sin(visualUV.x * 42.0 + visualUV.y * 35.0 + audio.time * 5.2);
    float idleWave = sin(visualUV.x * 9.0 + visualUV.y * 4.0 - audio.time * 0.72) * 0.035;
    // The drum wave lives only in the empty dot field outside the artwork.
    float2 coverEdge = max(abs(coverUV - 0.5) - 0.5, 0.0);
    float outsideDistance = length(coverEdge) * coverHeight;
    float waveDistance = 0.025 + min(styleControls.z, 0.65) * 0.90;
    float wave = exp(-pow((outsideDistance - waveDistance) / 0.11, 2.0));
    float sparkle = fract(sin(dot(floor(uv * float2(grid, float(gridRows))), float2(12.9898, 78.233))) * 43758.5453);
    float outerBeat = insideCover ? 0.0 : beat * wave * smoothstep(0.30, 0.80, sparkle);
    // HTDemucs stem envelopes drive independent piano/guitar fields. FFT remains
    // the fallback when those model-derived envelopes are unavailable.
    float height = idleWave + pianoWave * piano * 0.23 + guitarWave * guitar * 0.16;
    float crest = saturate(0.5 + height * 1.4);

    float2 clip = float2(uv.x * 2.0 - 1.0, 1.0 - uv.y * 2.0);
    clip += height * float2(0.018, 0.064);
    float pitch = controls.w / grid;
    // Fixed screen-space dots keep Retina drawable dimensions from inflating each sample.
    // Drum hits illuminate the surrounding dots without changing their size.
    float size = min(pitch * controls.y * 0.82, 8.0) * (0.98 + height * 0.14);

    DesktopDotParticleOut out;
    out.position = float4(clip, 0.0, 1.0);
    out.pointSize = clamp(size, 1.5, 8.0);
    float3 paletteWarm = mood.edgeLight.rgb;
    float3 paletteCool = mood.volumetricBeam.rgb;
    out.color = insideCover
              ? coverColor * (1.06 + crest * 0.28) + paletteCool * guitar * 0.14 + paletteWarm * piano * 0.13
              : coverColor + outerBeat * mood.pulseRing.rgb;
    // The independent artwork pass replaces only the cover samples. Keep every
    // empty-field point, its motion, and the original drum illumination unchanged.
    out.opacity = insideCover
                ? (styleControls.w > 0.5 ? 0.0 : 0.96)
                : 0.11 + outerBeat * 0.73;
    out.height = height;
    return out;
}

fragment float4 desktopDotParticleFragment(DesktopDotParticleOut in [[stage_in]],
                                           float2 pointCoord [[point_coord]]) {
    float distanceFromCenter = length(pointCoord - 0.5) * 2.0;
    float core = 1.0 - smoothstep(0.72, 0.98, distanceFromCenter);
    float glow = exp(-distanceFromCenter * distanceFromCenter * 7.0);
    float alpha = saturate(core * 0.98 + glow * 0.06) * in.opacity;
    if (alpha < 0.015) discard_fragment();
    float3 color = in.color * (0.96 + saturate(in.height + 0.5) * 0.24);
    return float4(color, alpha);
}

// Native Metal implementation of a regular artwork point plane with restrained
// depth relief and perspective-scaled dots. The grid never jitters in image space.
// Color is sampled independently of depth so small artwork details stay intact.
float3 desktopCoverDisplayColor(float3 linearColor) {
    return select(1.055 * pow(max(linearColor, float3(0.0)), float3(1.0 / 2.4)) - 0.055,
                  linearColor * 12.92, linearColor <= 0.0031308);
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

float3 desktopStageRotate(float3 p, constant DesktopCoverStageUniforms &stage) {
    float yaw = stage.rotation.x, pitch = stage.rotation.y, roll = stage.rotation.w;
    p = float3(p.x * cos(yaw) + p.z * sin(yaw), p.y,
               -p.x * sin(yaw) + p.z * cos(yaw));
    p = float3(p.x, p.y * cos(pitch) - p.z * sin(pitch),
               p.y * sin(pitch) + p.z * cos(pitch));
    return float3(p.x * cos(roll) - p.y * sin(roll),
                  p.x * sin(roll) + p.y * cos(roll), p.z);
}

float desktopHash3(float3 p) {
    p = fract(p * 0.1031);
    p += dot(p, p.yzx + 33.33);
    return fract((p.x + p.y) * p.z);
}

float desktopValueNoise3(float3 p) {
    float3 cell = floor(p);
    float3 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = mix(desktopHash3(cell), desktopHash3(cell + float3(1, 0, 0)), f.x);
    float b = mix(desktopHash3(cell + float3(0, 1, 0)), desktopHash3(cell + float3(1, 1, 0)), f.x);
    float c = mix(desktopHash3(cell + float3(0, 0, 1)), desktopHash3(cell + float3(1, 0, 1)), f.x);
    float d = mix(desktopHash3(cell + float3(0, 1, 1)), desktopHash3(cell + float3(1, 1, 1)), f.x);
    return mix(mix(a, b, f.y), mix(c, d, f.y), f.z) * 2.0 - 1.0;
}

float4 desktopStageProject(float3 p, constant DesktopCoverStageUniforms &stage) {
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

vertex DesktopDotParticleOut desktopCoverReliefVertex(
    uint id [[vertex_id]],
    constant CoverDotVisualAudio &audio [[buffer(0)]],
    constant float4 &controls [[buffer(1)]],
    constant DesktopMoodColors &mood [[buffer(3)]],
    constant float4 &layout [[buffer(4)]],
    constant DesktopCoverStageUniforms &stage [[buffer(5)]],
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
    float3 linearColor = cover.sample(desktopCoverSampler, sampleUV, level(0.0)).rgb;
    float3 color = desktopCoverDisplayColor(linearColor);

    // Smooth local luminance creates a shallow relief; it is a heuristic depth
    // field, not an inferred semantic depth map or another Core ML job.
    float2 step = 2.0 / float2(float(columns), float(rows));
    float3 neighborhood = linearColor * 0.4
        + (cover.sample(desktopCoverSampler, sampleUV + float2(step.x, 0), level(0.0)).rgb
        +  cover.sample(desktopCoverSampler, sampleUV - float2(step.x, 0), level(0.0)).rgb
        +  cover.sample(desktopCoverSampler, sampleUV + float2(0, step.y), level(0.0)).rgb
        +  cover.sample(desktopCoverSampler, sampleUV - float2(0, step.y), level(0.0)).rgb) * 0.15;
    float luminance = dot(desktopCoverDisplayColor(neighborhood), float3(0.2126, 0.7152, 0.0722));
    float edgeGuard = 1.0 - smoothstep(0.965, 1.0, edgeDistance);
    // Use the entire square image in cover mode; circular clipping is reserved
    // for the record overlay used by the other desktop effects.
    color = controls.w > 0.5 ? color : mix(float3(0.07, 0.10, 0.16), mood.atmosphere.rgb, 0.18);
    float rim = squareCover ? 0.0 : exp(-pow((radius - 0.975) / 0.012, 2.0));
    color += mood.volumetricBeam.rgb * rim * (0.055 + saturate(audio.bass) * 0.07);
    float z = (luminance - 0.5) * 0.12 * edgeGuard;
    float3 point = float3(discUV.x * 0.5, -discUV.y * 0.5, z);
    // Restore the cover's instrument response: a diagonal guitar resonance
    // travels through depth and light, while piano adds a quieter broad lift.
    // Neither stem moves the artwork samples sideways or changes their UVs.
    float guitarDrive = squareCover ? smoothstep(0.08, 0.62, saturate(stage.audio.x)) : 0.0;
    float pianoDrive = squareCover ? saturate(stage.audio.y) : 0.0;
    float stringAxis = uv.x * 0.88 + uv.y * 0.46;
    float stringPhase = stringAxis * 34.0 - stage.viewport.w * 6.0
                      + sin(uv.x * 8.0 - stage.viewport.w * 0.65) * 0.65;
    float stringLane = exp(-pow((uv.y - 0.50
                      - sin(uv.x * 5.0 - stage.viewport.w * 0.48) * 0.10) / 0.34, 2.0));
    float stringWave = sin(stringPhase) + 0.22 * sin(stringPhase * 1.72 + uv.x * 5.0);
    float pianoWave = sin(uv.y * 14.0 + stage.viewport.w * 1.7);
    point.z += guitarDrive * stringLane * stringWave * 0.085
             + pianoDrive * pianoWave * 0.022;
    DesktopDotParticleOut out;
    out.position = desktopStageProject(point, stage);
    // Perspective size returns on the square 3D cover. Keep the spinning
    // record's dot size constant to avoid shimmer during its slow rotation.
    out.pointSize = max(1.0, controls.z * (squareCover ? stage.layout.w / out.position.w : 1.0));
    float resonanceLight = guitarDrive * stringLane
        * (0.5 + 0.5 * saturate(stringWave * 0.62 + 0.5)) * 0.30;
    float pianoLight = pianoDrive * (0.5 + 0.5 * pianoWave) * 0.06;
    out.color = clamp(((color - 0.5) * 1.08 + 0.5)
                * (1.0 + resonanceLight + pianoLight), 0.0, 1.0);
    out.opacity = 0.98;
    if (!squareCover) {
        out.opacity *= 1.0 - smoothstep(0.965, 1.0, radius);
        if (radius > 1.0) out.opacity = 0.0;
    }
    out.height = z;
    return out;
}

fragment float4 desktopCoverReliefFragment(DesktopDotParticleOut in [[stage_in]],
                                           float2 pointCoord [[point_coord]]) {
    float r = length(pointCoord - 0.5) * 2.0;
    float feather = clamp(fwidth(r), 0.035, 0.12);
    float alpha = (1.0 - smoothstep(1.0 - feather, 1.0, r)) * in.opacity;
    if (alpha < 0.01) discard_fragment();
    return float4(in.color, alpha);
}

struct DesktopStageLyricOut {
    float4 position [[position]];
    float2 uv;
    float2 maskUV;
    float progress;
    float active;
    float opacity;
    float time;
};

vertex DesktopStageLyricOut desktopStageLyricVertex(
    uint id [[vertex_id]],
    constant float4 &placement [[buffer(1)]],
    constant float4 &style [[buffer(2)]],
    constant float4 &highlight [[buffer(3)]],
    constant DesktopCoverStageUniforms &stage [[buffer(5)]]) {
    constexpr float2 corners[6] = {
        float2(0, 0), float2(1, 0), float2(0, 1),
        float2(0, 1), float2(1, 0), float2(1, 1)
    };
    float2 uv = corners[id];
    float2 local = (uv - 0.5) * float2(placement.z, placement.w) * mix(1.0, 1.035, style.y);
    float3 point = float3(placement.xy * float2(stage.layout.z, 1.0) + local, 0.16);
    DesktopStageLyricOut out;
    out.position = desktopStageProject(point, stage);
    out.uv = uv;
    // Correct AppKit's vertical bitmap origin only. Keep U increasing from left
    // to right so Chinese lyric text and the karaoke sweep read naturally.
    out.maskUV = float2(uv.x, 1.0 - uv.y);
    out.progress = style.x;
    out.active = style.y;
    out.opacity = style.z;
    out.time = stage.viewport.w;
    return out;
}

fragment float4 desktopStageLyricFragment(DesktopStageLyricOut in [[stage_in]],
                                          texture2d<float> glyphMask [[texture(1)]],
                                          constant float4 &highlight [[buffer(3)]]) {
    constexpr sampler maskSampler(coord::normalized, address::clamp_to_edge, filter::linear);
    float coverage = glyphMask.sample(maskSampler, in.maskUV).a;
    if (coverage < 0.025) discard_fragment();
    float sweep = in.active * (1.0 - smoothstep(in.progress - 0.08, in.progress + 0.08, in.uv.x));
    float shimmer = 0.97 + 0.03 * sin(in.uv.x * 18.0 + in.time * 1.2);
    float3 inactive = float3(0.70, 0.77, 0.89);
    float3 active = mix(float3(0.70, 0.91, 1.0), highlight.rgb, 0.30);
    float3 color = mix(inactive, active, in.active * (0.72 + 0.28 * sweep));
    float glow = 1.0 + in.active * (0.12 + 0.10 * sweep);
    return float4(color * glow * shimmer, coverage * in.opacity);
}
