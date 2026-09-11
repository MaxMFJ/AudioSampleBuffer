---
name: visual-effects-factory
description: Use when adding, modifying, or registering a visual effect in this project. Follow the factory-driven VisualEffects architecture, preserve square logical rendering to avoid distortion, and prioritize low-heat/high-expressiveness Metal effects with explicit enum, registry, factory, default-parameter, and performance integration steps.
---

# Visual Effects Factory Skill

Use this skill when creating or updating any effect under `AudioSampleBuffer/VisualEffects`.

## Goal

New effects must satisfy all of these goals at once:

- Low heat / low GPU pressure
- Strong visual identity and musical expressiveness
- No distortion on phone screens
- Consistent registration through enum + registry + factory + manager defaults
- Easy for future contributors to locate and extend

## Current Structure

- `Core/`
  - `VisualEffectType.h/.m`
  - `VisualEffectManager.h/.m`
- `Metal/`
  - `MetalRenderer.h/.m`
  - all Metal shaders
- `Controls/`
  - optional effect control panels
- `UI/`
  - effect picker UI

When adding a new Metal effect, default to placing shader files in `Metal/`. Do not add new effect files back into the old flat root layout.

## Non-Negotiable Principles

### 1. Preserve square logical rendering

This project intentionally uses a square logical render space to avoid screen-stretch distortion on phones.

- Do not change a new effect to use raw phone-width × phone-height logic by default.
- Keep circle, radial, vortex, tunnel, and polar-coordinate effects in square logic space.
- If lowering cost, reduce actual `drawableSize`, not the logical square design.
- Any full-screen adaptation must prove it does not reintroduce ellipse/stretch artifacts.

### 2. Favor low-cost expressiveness over brute-force complexity

Prefer:

- strong composition
- audio-reactive timing
- layered motion with few elements
- parameter modulation
- palette and glow design

Avoid relying on:

- large per-pixel loops
- many nested noise/fractal iterations
- repeated full-screen blur/bloom passes
- dense particle counts as the main source of richness
- high FPS as the only way to look good

Rule of thumb: a good effect should still read well at 24-30 fps and at reduced render scale.

### 3. New effects must degrade gracefully

Each effect should remain visually valid under conservative settings:

- reduced `drawableSize`
- 24 fps
- reduced glow / density / iterations

Do not design an effect that only looks acceptable at maximum quality.

## Registration Checklist

When adding a new effect type, update all relevant layers.

### Required registrations

1. Add enum case in `Core/VisualEffectType.h`
2. Add display metadata in `Core/VisualEffectType.m`
3. Add renderer class declaration in `Metal/MetalRenderer.h`
4. Add factory mapping in `Metal/MetalRenderer.m`
5. Add default parameters in `Core/VisualEffectManager.m`
6. If the effect is Metal-backed, register it in `VisualEffectManager -isMetalEffect:`
7. If the effect lives outside `EffectCategoryMetal` but still uses Metal, explicitly set `requiresMetal = YES` in registry metadata so support checks stay correct

### Conditional registrations

Add only if needed:

- special FPS policy in `Core/VisualEffectManager.m`
- special `drawableSize` / render-scale policy in `Core/VisualEffectManager.m`
- AI effect selection rules if the effect should be chosen automatically
- control panel under `Controls/` if the effect truly needs dedicated tuning UI

Do not add a new effect with only shader code and forget enum/factory/default settings.
Do not assume category alone is enough to make a Metal effect reachable; selection, support-state, and renderer visibility may depend on separate Metal registration.

## Naming Rules

Keep names aligned across enum, renderer, shader, and display name.

Preferred pattern:

- enum: `VisualEffectTypeMyNewEffect`
- renderer: `MyNewEffectRenderer`
- shader file: `MyNewEffectShader.metal`
- UI name: short, distinctive, music-facing

Avoid vague names like `CoolEffect`, `TestEffect`, `Shader2`, `NewRenderer`.

## Factory Rules

Factory ownership lives in `MetalRendererFactory`.

- Every Metal effect must have a clear `switch` case in factory creation
- The default case must not be used as implicit registration
- If an effect is not ready, do not add the enum yet

Factory changes should stay explicit and readable. Do not hide registration behind dynamic string lookup.

## Default Parameter Rules

Every new effect needs conservative default parameters in `VisualEffectManager`.

Defaults should:

- look good immediately
- avoid thermal spikes
- avoid requiring manual tuning
- expose only the few parameters that materially shape the effect

Prefer defaults that bias toward:

- medium density
- medium glow
- controlled motion speed
- moderate audio sensitivity

Do not ship defaults that are “demo mode only”.

## Performance Budget Rules

When designing a new Metal effect, optimize in this order:

1. Minimize full-screen fragment cost
2. Minimize loop counts in shader code
3. Minimize expensive math inside hot paths
4. Minimize overdraw and additive glow abuse
5. Minimize auxiliary passes

Preferred techniques:

- fewer but better-shaped layers
- temporal modulation from audio bands
- reuse of simple geometry or masks
- cheap domain warping in moderation
- quality scaling through a small number of knobs

Use caution with:

- iterative raymarch-like patterns
- multi-octave fbm in several stacked regions
- large blur kernels
- many branches driven by per-pixel logic

## Shader Design Rules

New shader code should aim for “readable hot path”.

- keep core effect math localized
- separate parameter shaping from rendering where possible
- prefer a few meaningful uniforms over many loosely defined values
- document only the non-obvious cost or geometry assumptions

If a shader is audio-reactive:

- use audio data to drive motion, contrast, unlock states, pulse, density, hue, or deformation
- do not map every band independently unless the effect truly needs it
- prefer grouped musical behavior over noisy per-band flicker

## Square-Space Guidance

For effects with circles, rings, spirals, tunnels, radial beams, or polar layouts:

- derive visual geometry from square logical space
- treat aspect-ratio correction as presentation logic, not as permission to redesign coordinates arbitrarily
- verify the effect still looks centered and circular on tall phone screens

If you need a non-square `drawableSize` for performance, keep the effect's internal geometry invariant.

## Control Panel Rules

Only create a dedicated control panel when:

- the effect has a real user-facing identity
- 3-6 parameters are meaningfully adjustable
- the controls are not just debug toggles

Do not create a control panel just because a shader has many uniforms.

## Validation Checklist

Before considering a new effect complete, verify:

- it compiles
- it is reachable from enum + registry + factory
- it is reachable through `VisualEffectManager -isMetalEffect:` if it uses Metal rendering
- its registry metadata reports `requiresMetal` correctly, especially for creative/experimental effects
- it has manager defaults
- it renders without stretch on phone aspect ratios
- it remains acceptable at reduced render scale
- it does not require 60/120 fps to feel alive
- it does not visibly overheat the device during normal playback expectations

Use simulator build verification, but prefer real-device judgment for thermal and visual quality.

## Anti-Patterns

Avoid these common mistakes:

- adding only the shader and forgetting registration
- pushing performance problems into higher FPS
- making the effect depend on very high `drawableSize`
- breaking square logical rendering to “fill the phone screen”
- adding effect-specific hacks into unrelated effects
- overfitting defaults to one device tier
- using massive particle count as a substitute for visual design

## Suggested Workflow For A New Effect

1. Decide the effect's visual identity and cost target
2. Choose the minimal audio features that drive it
3. Implement the shader in `Metal/`
4. Add renderer declaration and factory registration
5. Add enum and registry metadata
6. Add conservative defaults in manager
7. Add any effect-specific FPS/render-scale guard only if necessary
8. Build and visually verify on tall phone layouts
9. Tune for “balanced by default”, not showcase-by-default

## Output Expectation For Future AI Edits

When adding a new effect, future AI should report:

- which files were added or modified
- which enum/factory/registry/default hooks were registered
- what the default performance posture is
- whether the effect needs any custom FPS or render-scale policy
