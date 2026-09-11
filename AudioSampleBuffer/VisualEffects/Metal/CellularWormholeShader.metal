// Deep-space cellular tunnel. All pores are procedural, so their silhouettes
// respond to the live spectrum rather than scaling a flat background image.
#include "ShaderCommon.metal"
using namespace metal;

static inline float cwHash(float2 p) {
    return fract(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

fragment float4 cellularWormholeFragment(RasterizerData in [[stage_in]],
                                         constant Uniforms &u [[buffer(0)]]) {
    constexpr float tau = 6.28318530718;
    float2 p = aspectCorrect(in.texCoord, u.resolution) - 0.5;
    float t = u.time.z; // Integrated speed: changes in energy never jump the tunnel.
    float bass = saturate(u.cyberpunkControls.z);
    float mid = saturate(u.cyberpunkControls.w);
    float treble = saturate(u.cyberpunkFrequencyControls.x);
    float energy = saturate(u.cyberpunkFrequencyControls.y);
    float beat = saturate(u.galaxyParams3.w);
    // Existing HPSS/EDM features, already delivered by the playback pipeline.
    // Spectrum fallbacks keep the main layers responsive on the legacy path.
    float musicGate = smoothstep(0.008, 0.065, max(energy, max(bass, max(mid, treble))));
    float low = max(bass, saturate(u.activityMeter1.x)) * musicGate;
    float hit = max(beat, saturate(u.activityMeter1.y)) * musicGate;
    float melody = max(mid * 0.70, saturate(u.activityMeter1.z)) * musicGate;
    float haze = saturate(u.activityMeter1.w) * musicGate;
    float highPeak = max(max(u.audioData[54].z, u.audioData[62].z),
                         max(u.audioData[70].z, u.audioData[78].z));
    float highInput = max(saturate(u.activityMeter2.x), max(treble * 2.20, highPeak * 1.18));
    float high = smoothstep(0.035, 0.52, highInput) * musicGate;
    float electric = saturate(u.activityMeter2.y) * musicGate;
    float chopped = saturate(u.activityMeter2.z) * musicGate;
    float sweep = saturate(u.activityMeter2.w) * musicGate;
    float pan = saturate(u.activityMeter3.x) * musicGate;
    float echo = saturate(u.activityMeter3.y) * musicGate;
    float sidechain = saturate(u.activityMeter3.z) * musicGate;
    float pluck = saturate(u.activityMeter5.x) * musicGate;
    float soundWall = saturate(u.activityMeter5.y) * musicGate;
    float impactAge = max(u.galaxyParams1.y, 0.0);
    float impact = saturate(u.galaxyParams1.z) * exp(-impactAge * 3.4) * musicGate;
    float climax = saturate(u.galaxyParams2.z) * musicGate;
    float llmThemeEnabled = saturate(u.cyberpunkFrequencyControls.w);
    float sensitivity = clamp(u.galaxyParams2.w, 0.65, 1.8);
    float paletteBoost = clamp(u.cyberpunkBackgroundParams.w, 0.75, 1.35);
    float3 defaultTheme = float3(0.035, 0.57, 0.70);
    float3 llmTheme = clamp(u.cyberpunkBackgroundParams.rgb, 0.0, 1.0);
    float3 theme = mix(defaultTheme, llmTheme, llmThemeEnabled);
    // Keep very dark LLM palettes readable without changing their hue identity.
    theme = mix(theme, theme / max(max(max(theme.r, theme.g), theme.b), 0.001) * 0.72,
                smoothstep(0.0, 0.24, 0.24 - max(max(theme.r, theme.g), theme.b)));
    float3 highlight = mix(theme, float3(1.0), 0.20);
    float3 deepTheme = mix(float3(0.004, 0.012, 0.035), theme * 0.24, 0.72);
    float r = length(p);
    float angle = atan2(p.y, p.x);
    float baseCore = u.galaxyParams1.x > 0.0 ? clamp(u.galaxyParams1.x, 0.26, 0.38) : 0.32;
    float core = baseCore + low * 0.024 + beat * 0.012
               - sidechain * beat * 0.009;
    float organic = 0.010 * sin(angle * 3.0 + t * 0.13)
                  + 0.006 * sin(angle * 5.0 - t * 0.09);
    float wallRadius = r - core - organic;
    float depth = -log(max(wallRadius, 0.003)) * 2.4;
    float wall = smoothstep(0.0, 0.035, wallRadius);
    float innerSpace = (1.0 - smoothstep(core - 0.055, core + 0.01, r))
                     * smoothstep(core * 0.30, core * 0.92, r);

    // Periodic angular IDs prevent an atan2 seam. Log depth packs tiny distant
    // holes around the throat while stretching foreground pores into a tunnel.
    float angularCells = clamp(u.galaxyParams1.w, 14.0, 24.0);
    float2 q = float2(angle / tau * angularCells + depth * 0.56 + t * 0.10,
                      depth * 0.68 + t * 0.34);
    q += float2(0.18 * sin(q.y * 1.8), 0.15 * sin(angle * 6.0 + depth));
    // Four surrounding centers are sufficient for this jitter range. This
    // cuts the hottest per-pixel loop from 9 pore evaluations to 4.
    float2 cell = floor(q - 0.5);
    float poreDistance = 10.0;
    float poreSignal = 0.0;
    float poreSeed = 0.0;
    for (int y = 0; y <= 1; ++y) {
        for (int x = 0; x <= 1; ++x) {
            float2 id = cell + float2(x, y);
            float2 periodicID = float2(id.x - floor(id.x / angularCells) * angularCells, id.y);
            float seed = cwHash(periodicID);
            float jitter = cwHash(periodicID + 19.3);
            int band = min(79, int(seed * 80.0));
            // Fast raw attack + smoothed release. Each pore keeps its own band
            // as it travels, including across the angular seam.
            float signal = saturate((u.audioData[band].x * 0.58 +
                                     u.audioData[band].y * 0.28 +
                                     u.audioData[band].z * 0.22) * sensitivity);
            float shapeSignal = saturate(signal * (1.18 + climax * 0.55) +
                                         climax * (0.08 + seed * 0.10));
            float2 center = id + 0.5 + float2(seed - 0.5, jitter - 0.5) * 0.20;
            float2 local = q - center;
            // Every pore owns one stable spectrum band. Its amplitude controls
            // size, rotation, asymmetric bending and center drift as one motion.
            float phase = t * (0.46 + seed * 0.34) + seed * tau;
            center += shapeSignal * float2(sin(phase), cos(phase * 0.83))
                    * (0.10 + climax * 0.035);
            local = q - center;
            float twist = (seed - 0.5) * 0.42
                        + sin(phase) * shapeSignal * (1.05 + climax * 0.38);
            float cs = cos(twist);
            float sn = sin(twist);
            local = float2(cs * local.x - sn * local.y, sn * local.x + cs * local.y);
            local += shapeSignal * (0.12 + climax * 0.045)
                   * float2(sin(local.y * 5.0 + phase), cos(local.x * 4.0 - phase * 0.9));
            float slant = (seed - 0.5) * 0.62
                        + shapeSignal * sin(phase * 1.17) * (0.58 + climax * 0.18);
            local.x += slant * local.y;
            float radius = clamp(0.30 + jitter * 0.075 + shapeSignal * 0.18
                                 + beat * 0.022 + climax * 0.025, 0.30, 0.49);
            float2 stretch = float2(1.0 + shapeSignal * sin(phase) * (0.25 + climax * 0.09),
                                    0.88 + seed * 0.18
                                    - shapeSignal * cos(phase) * (0.22 + climax * 0.08));
            float d = length(local * stretch) - radius;
            if (d < poreDistance) {
                poreDistance = d;
                poreSignal = shapeSignal;
                poreSeed = seed;
            }
        }
    }
    float aa = max(fwidth(poreDistance), 0.008);
    float membrane = smoothstep(-aa, aa, poreDistance);
    float lip = exp(-abs(poreDistance) * 32.0);
    float softGlow = exp(-abs(poreDistance) * 9.0);
    // Attenuate subpixel pores at the vanishing point instead of shimmering.
    float detail = 1.0 - smoothstep(0.35, 1.2, fwidth(depth));
    membrane = mix(0.32, membrane, detail);
    float ridges = 0.68 + 0.32 * sin(depth * 2.5 - t * 0.35 + angle * 2.0);
    float nearLight = smoothstep(0.0, 0.55, wallRadius);
    float3 tint = mix(theme, deepTheme, nearLight * 0.72);
    float3 color = mix(float3(0.001, 0.004, 0.014), deepTheme, 0.08);
    color += wall * membrane * tint * (0.30 + ridges * 0.45 + bass * 0.20);
    color += wall * detail * lip * highlight
           * (0.14 + poreSignal * 0.70 + beat * 0.20);
    color += wall * detail * softGlow * tint * (0.06 + energy * 0.10);
    float highShimmer = 0.62 + 0.38 * sin(t * 13.0 + poreSeed * 31.0 + depth * 1.7);
    color += wall * detail * lip * mix(highlight, float3(1.0), 0.48)
           * high * highShimmer * 0.46;

    // Thousands of flowing grains condense onto the pore edges. Before a grain
    // reaches its assembly phase it drifts through the tunnel; afterwards its
    // lateral motion collapses toward the nearest honeycomb boundary.
    float2 grainUV = q * float2(2.35, 3.15);
    float2 grainID = floor(grainUV);
    float grainSeed = cwHash(grainID + 31.7);
    float grainSeed2 = cwHash(grainID + 73.1);
    float assembly = smoothstep(0.12, 0.78,
                                fract(t * 0.19 + grainSeed - depth * 0.055));
    float2 grainCenter = 0.5 + float2(grainSeed - 0.5, grainSeed2 - 0.5) * 0.62;
    grainCenter.x += (1.0 - assembly) * sin(t * 1.7 + grainSeed * 27.0) * 0.42;
    grainCenter.y += (1.0 - assembly) * fract(t * 0.38 + grainSeed2) * 0.46;
    float2 grainLocal = fract(grainUV) - grainCenter;
    float flyingGrain = exp(-(grainLocal.x * grainLocal.x * 150.0 +
                              grainLocal.y * grainLocal.y * 34.0));
    float settledGrain = exp(-dot(grainLocal, grainLocal) * 230.0);
    float grain = mix(flyingGrain, settledGrain, assembly);
    float edgeArrival = exp(-abs(poreDistance) * mix(6.0, 34.0, assembly));
    float flying = (1.0 - assembly)
                 * (0.16 + 0.64 * smoothstep(0.2, 1.0, energy) + climax * 0.35);
    float settled = assembly * edgeArrival;
    float grainGate = step(0.25 - high * 0.14 - climax * 0.08, grainSeed2);
    float grainAudio = 0.38 + poreSignal * 0.68 + high * 0.34
                     + beat * 0.22 + climax * 0.25;
    color += wall * detail * grain * grainGate * (flying * 0.52 + settled * 1.25)
           * highlight * grainAudio;

    // Dense micro-particles make the membrane itself feel assembled rather
    // than painted, with treble revealing finer pieces around every pore.
    float2 speckUV = q * float2(6.0, 8.0);
    float2 speckID = floor(speckUV);
    float speckSeed = cwHash(speckID + poreSeed * 41.0);
    float2 speckCenter = float2(cwHash(speckID + 3.1),
                                cwHash(speckID + 9.7)) * 0.50 + 0.25;
    float2 speckDelta = fract(speckUV) - speckCenter;
    float speck = exp(-dot(speckDelta, speckDelta) * 190.0)
                * step(0.66 - high * 0.16 - climax * 0.08, speckSeed);
    color += wall * membrane * speck * tint * (0.025 + high * 0.10 + climax * 0.06);

    // A travelling band illuminates the porous surface on drum attacks.
    float wave = pow(0.5 + 0.5 * sin(depth * 2.0 - t * 5.0), 12.0);
    color += wall * membrane * wave * beat * highlight * 0.65;
    float throat = exp(-pow(wallRadius / 0.022, 2.0));
    color += throat * theme * (0.25 + bass * 0.40);

    // Climax layer: widen and twist the pores above, then unlock a sustained
    // radial burst and repeated outward shock fronts for a clear section change.
    float climaxBreath = 0.78 + 0.22 * sin(t * 5.4 + energy * 5.0);
    float climaxRays = pow(0.5 + 0.5 * cos(angle * 28.0 - t * 1.25
                                          + sin(r * 18.0) * 0.7), 18.0);
    float climaxRayMask = innerSpace * smoothstep(core * 0.28, core * 0.88, r);
    color += mix(theme, highlight, 0.48) * climaxRays * climaxRayMask
           * climax * climaxBreath * 0.48;
    float climaxPhase = fract(t * 0.24);
    float climaxRadius = core + climaxPhase * 0.46;
    float climaxRing = exp(-pow((r - climaxRadius) / (0.010 + climax * 0.008), 2.0));
    color += highlight * climaxRing * climax * (1.0 - climaxPhase) * 0.80;
    color += wall * membrane * tint * climax * (0.18 + climaxBreath * 0.20);

    // Layer 1: bass pressure launches an actual onset-timed ring outwards.
    // Echo adds delayed copies, rather than a constantly running beat clock.
    for (int ring = 0; ring < 3; ++ring) {
        float age = impactAge - float(ring) * 0.19;
        float radius = baseCore + max(age, 0.0) * 0.30;
        float ringWidth = 0.004 + low * 0.006 + float(ring) * 0.001;
        float ringMask = exp(-pow((r - radius) / ringWidth, 2.0));
        float gain = ring == 0 ? 1.0 : echo * (0.55 / float(ring));
        float envelope = step(0.0, age) * exp(-max(age, 0.0) * 3.4);
        color += highlight * ringMask * gain * envelope * saturate(u.galaxyParams1.z)
               * musicGate * (0.25 + low * 0.45);
    }

    // Layer 2: soft harmonic ribbons drift just inside the large opening.
    // Three arcs sample separate mid bands, keeping melodies spatially distinct.
    for (int arc = 0; arc < 3; ++arc) {
        float band = saturate(u.audioData[22 + arc * 12].y);
        float phase = angle * float(3 + arc) + t * (0.23 + float(arc) * 0.08);
        float arcRadius = core * (0.86 - float(arc) * 0.08)
                        + sin(phase) * (0.006 + band * 0.020);
        float arcMask = exp(-pow((r - arcRadius) / (0.003 + melody * 0.004), 2.0));
        float arcWindow = pow(0.5 + 0.5 * sin(angle * 2.0 - t * 0.31 + float(arc) * 2.1), 3.0);
        color += mix(theme, highlight, float(arc) * 0.18) * arcMask * arcWindow
               * melody * (0.15 + band * 0.32) * (1.0 - sidechain * beat * 0.45);
    }

    // Layer 3: Tyndall-like shafts in the inner haze, unlocked by sweep/noise.
    // The central 30% remains dark; only the rim carries the light curtain.
    float fog = 0.55 + 0.25 * sin(angle * 5.0 + r * 21.0 - t * 0.4)
                     + 0.20 * sin(angle * 9.0 - r * 35.0 + t * 0.27);
    float beamAngle = angle + t * 0.10 + pan * sin(t * 0.35) * 0.45;
    float shafts = pow(0.5 + 0.5 * cos(beamAngle * 12.0 + sin(r * 8.0 - t * 0.25)), 18.0);
    color += theme * innerSpace * fog * (haze * 0.045 + soundWall * 0.06);
    color += highlight * innerSpace * shafts * (sweep * 0.25 + haze * 0.08);

    // Layer 4: narrow corona filaments and short sparks for percussion/plucks.
    float spokeAngle = angle + t * 0.06;
    float spokes = pow(0.5 + 0.5 * cos(spokeAngle * 40.0 + sin(r * 13.0)), 35.0);
    float corona = exp(-abs(r - core) * 22.0);
    float choppedGate = mix(1.0, smoothstep(-0.15, 0.15, sin(t * 15.0 + angle * 8.0)), chopped);
    color += highlight * spokes * corona
           * (high * 0.52 + hit * 0.58 + pluck * 0.48 + electric * 0.25 + impact * 0.36)
           * choppedGate;
    float scanRadius = core * (0.60 + 0.32 * (0.5 + 0.5 * sin(t * 0.55)));
    float scan = exp(-pow((r - scanRadius) / 0.006, 2.0));
    color += highlight * scan * sweep * (0.12 + 0.16 * fog);

    // Layer 5: high-frequency shooting grains across the star-filled aperture.
    // Fixed angular lanes and integrated travel time keep motion continuous.
    float lane = floor((angle / tau + 0.5) * 64.0);
    float laneSeed = cwHash(float2(lane, 43.0));
    float laneLocal = fract((angle / tau + 0.5) * 64.0) - 0.5;
    float flight = fract(t * (0.13 + laneSeed * 0.09) + laneSeed);
    float head = core * (0.22 + flight * 0.77);
    float tailLength = 0.018 + high * 0.11 + impact * 0.08;
    float behindHead = max(head - r, 0.0);
    float trail = exp(-behindHead / tailLength) * step(r, head)
                * step(head - tailLength * 3.2, r);
    float headGlow = exp(-pow((r - head) / (0.0035 + high * 0.004), 2.0));
    float streak = exp(-laneLocal * laneLocal * 320.0) * (trail * 0.70 + headGlow * 1.35);
    color += mix(highlight, float3(1.0), 0.38) * streak * step(0.68, laneSeed) * innerSpace
           * (high * 0.90 + hit * 0.38 + impact * 0.34);

    // Short-lived point sparks make hats and sharp transients readable even
    // when long shafts share the same palette.
    float sparkClock = floor(t * (5.0 + high * 11.0 + hit * 4.0));
    float sparkLane = floor((angle / tau + 0.5) * 52.0);
    float sparkSeed = cwHash(float2(sparkLane, sparkClock + 17.0));
    float sparkAngle = fract((angle / tau + 0.5) * 52.0) - 0.5;
    float sparkRadius = core * (0.38 + cwHash(float2(sparkLane + 9.0, sparkClock)) * 0.57);
    float spark = exp(-sparkAngle * sparkAngle * 520.0)
                * exp(-pow((r - sparkRadius) / 0.0055, 2.0))
                * step(0.72, sparkSeed);
    color += mix(highlight, float3(1.0), 0.62) * spark * innerSpace
           * (high * 1.10 + hit * 0.72 + pluck * 0.55);

    // Stars are visible through the black apertures and the central void. Two
    // parallax layers create depth; treble controls sparkle and beat adds bloom.
    float holeVisibility = max(1.0 - wall, wall * (1.0 - membrane));
    float2 dustUV = (p + float2(t * 0.0008, -t * 0.0005)) * 105.0;
    float2 dustID = floor(dustUV);
    float dustSeed = cwHash(dustID + 7.4);
    float2 dustLocal = fract(dustUV) - 0.5;
    float dust = exp(-dot(dustLocal, dustLocal) * 160.0)
               * step(0.936, dustSeed);
    float twinkle = 0.55 + 0.45 * sin(t * 1.3 + dustSeed * 60.0);
    float2 farUV = (p - float2(t * 0.00025, t * 0.0003)) * 57.0;
    float2 farLocal = fract(farUV) - 0.5;
    float farSeed = cwHash(floor(farUV) + 91.2);
    float farStar = exp(-dot(farLocal, farLocal) * 95.0) * step(0.965, farSeed);
    float starBloom = dust * dust * (0.10 + beat * 0.75);
    color += holeVisibility * (dust * twinkle + farStar * 0.42)
           * mix(float3(0.72, 0.86, 1.0), highlight, 0.32)
           * (0.12 + high * 0.58);
    color += holeVisibility * starBloom * highlight * 0.34;
    color *= 1.0 - 0.32 * smoothstep(0.50, 1.35, r);
    color = 1.0 - exp(-color * (1.5 * paletteBoost));
    return float4(saturate(color), 1.0);
}
