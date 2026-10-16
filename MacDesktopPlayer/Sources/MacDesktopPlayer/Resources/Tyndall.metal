#include <metal_stdlib>
using namespace metal;

struct TyndallVertexOut { float4 position [[position]]; float2 uv; };
struct TyndallVisualAudio {
    float time, bass, mid, treble, aspectRatio;
    float guitar, piano, drums, playbackTime, electricGuitarConfidence, vocal, guitarPeak, playing;
};
struct DesktopMoodColors {
    float4 atmosphere, volumetricBeam, topLightArray, laserFanBlue, laserFanGreen;
    float4 rotatingBeam, rotatingBeamExtra, edgeLight, coronaFilaments, pulseRing;
};
struct TyndallAnimationUniforms {
    float4 starts, strengths, peak;
};

vertex TyndallVertexOut tyndallDesktopVertex(uint vertexID [[vertex_id]]) {
    constexpr float2 points[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    TyndallVertexOut out;
    out.position = float4(points[vertexID], 0.0, 1.0);
    out.uv = points[vertexID] * 0.5 + 0.5;
    return out;
}

// iOS Tyndall optical systems, with instrument-specific audio triggers.
static float stageHash(float2 p) {
    return fract(sin(dot(p, float2(12.9898, 78.233))) * 43758.5453);
}

static float stageNoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = stageHash(i);
    float b = stageHash(i + float2(1.0, 0.0));
    float c = stageHash(i + float2(0.0, 1.0));
    float d = stageHash(i + float2(1.0, 1.0));
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

// 快速颜色非零检查（避免 sqrt）
static inline bool colorIsSet(float3 c) {
    return dot(c, c) > 0.0001;
}

// 渐显-保持-渐消包络（通用，避免重复代码）
static inline float fadeEnvelope(float phase, float fadeIn, float fadeOut) {
    float env = 1.0;
    if (phase < fadeIn) {
        env = smoothstep(0.0, fadeIn, phase);
    } else if (phase > 1.0 - fadeOut) {
        env = smoothstep(1.0, 1.0 - fadeOut, phase);
    }
    return env;
}

// A trigger runs its full optical sequence. Only the first and last moments
// fade, so short gaps in the source cannot extinguish a beam mid-animation.
static inline float activationEnvelope(float elapsed, float duration) {
    return smoothstep(0.0, 0.45, elapsed)
         * (1.0 - smoothstep(duration - 0.8, duration, elapsed));
}

// ============================================================================
// 1. AtmosphereField - 烟雾氛围场
//    优化：hazeVal 由外部传入，避免重复计算
// ============================================================================

static float3 atmosphereField(float2 uv, float bass, float hazeVal, constant DesktopMoodColors &mood) {
    float density = 0.6 + 0.4 * (1.0 - uv.y);
    float haze = hazeVal * density;
    float breath = 1.0 + bass * 0.4;
    
    float3 baseColor = mood.atmosphere.rgb;
    // The shared Mac palette defaults to a warm full-brightness color, while
    // the iOS Tyndall default haze is deliberately much darker.
    if (all(abs(baseColor - float3(1.0, 0.88, 0.72)) < 0.001)) {
        baseColor = float3(0.06, 0.055, 0.08);
    }
    if (!colorIsSet(baseColor)) {
        baseColor = float3(0.06, 0.055, 0.08);
    }
    return baseColor * haze * breath;
}

// ============================================================================
// 2. VolumetricBeamSystem - 体积光束
//    优化：内联 volumetricCone，减少函数调用
// ============================================================================

static float3 volumetricBeamSystem(float2 p, float time, float bass, float hazeVal, float aspectRatio,
                                   constant DesktopMoodColors &mood) {
    float volume = 0.5 + hazeVal * 0.5;
    float brightness = 0.45 + bass * 0.35;
    float coneW = 0.52 + bass * 0.15;
    float cosThresh = cos(coneW);
    float radSq = 0.95 * 0.95;  // radius^2 预计算
    
    float3 color = mood.volumetricBeam.rgb;
    if (!colorIsSet(color)) {
        color = float3(1.0, 0.88, 0.72);
    }
    color *= brightness;
    
    // Two large fixtures sit just beyond the left and right screen edges,
    // sweeping upward and inward like the iOS stage rig.
    float edgeX = aspectRatio * 0.5 + 0.12;
    float inwardAim = atan2(edgeX, 0.42);
    float2 toL = p - float2(-edgeX, 0.42);
    float distLSq = dot(toL, toL);
    float distL = sqrt(distLSq);
    float beamL = 0.0;
    if (distL > 0.001) {
        float2 dL = toL / distL;
        float sweepL_angle = inwardAim + sin(time * 0.35) * 0.24;
        float2 dirLn = float2(sin(sweepL_angle), -cos(sweepL_angle));
        float alignL = dot(dL, dirLn);
        float coneL = smoothstep(cosThresh, 0.94, alignL);
        float falloffL = exp(-distLSq / radSq);
        // 沿光轴体积积分：光束中轴线上的点更亮，边缘散射衰减
        float axialL = dot(toL, dirLn);
        float axialFadeL = exp(-axialL * axialL * 0.08);
        beamL = coneL * falloffL * volume * axialFadeL;
    }
    
    float2 toR = p - float2(edgeX, 0.42);
    float distRSq = dot(toR, toR);
    float distR = sqrt(distRSq);
    float beamR = 0.0;
    if (distR > 0.001) {
        float2 dR = toR / distR;
        float sweepR_angle = -inwardAim + sin(time * 0.28 + 2.1) * 0.24;
        float2 dirRn = float2(sin(sweepR_angle), -cos(sweepR_angle));
        float alignR = dot(dR, dirRn);
        float coneR = smoothstep(cosThresh, 0.94, alignR);
        float falloffR = exp(-distRSq / radSq);
        // 沿光轴体积积分
        float axialR = dot(toR, dirRn);
        float axialFadeR = exp(-axialR * axialR * 0.08);
        beamR = coneR * falloffR * volume * axialFadeR;
    }
    
    return color * (beamL + beamR);
}

// ============================================================================
// 3. EdgeLight - 底部边缘描绘光
// ============================================================================

static float3 edgeLight(float2 uv, float mid, constant DesktopMoodColors &mood) {
    float ySq = uv.y * uv.y;
    // exp(-y^2 / w^2) where w=0.12, 1/w^2 = 69.44
    float glow = exp(-ySq * 69.44);
    float intensity = 0.2 + mid * 0.6;
    float3 edgeColor = mood.edgeLight.rgb;
    if (!colorIsSet(edgeColor)) {
        edgeColor = float3(1.0, 0.75, 0.35);
    }
    return edgeColor * glow * intensity;
}

// ============================================================================
// 4. FloorLightArray - 中音触发的底部四盏雾灯（iOS UV 的 +Y 为屏幕下方）
//    性能优化：减少灯数 7→4，触发后锁定包络期间不再计算 DSP
// ============================================================================

static float3 floorLightArray(float2 p, float time, float mid, float aspectRatio,
                              constant DesktopMoodColors &mood) {
    float cycleDuration = 12.0;  // 完整周期 12 秒（更长展示时间）
    float cyclePhase = fract(time / cycleDuration);
    
    // 三阶段包络：
    // [0, 0.15): 渐显 + DSP 监听触发阶段（1.8s）
    // [0.15, 0.75): 展示锁定阶段（不计算 DSP，固定 envelope=1.0，7.2s）
    // [0.75, 1.0): 渐消阶段（3s）
    float envelope = 0.0;
    bool needTriggerCheck = false;
    
    if (cyclePhase < 0.15) {
        // 渐显 + 触发监听阶段
        envelope = smoothstep(0.0, 0.15, cyclePhase);
        needTriggerCheck = true;
    } else if (cyclePhase < 0.75) {
        // 展示锁定阶段：envelope 固定为 1.0，跳过 DSP 计算
        envelope = 1.0;
        needTriggerCheck = false;
    } else {
        // 渐消阶段
        envelope = smoothstep(1.0, 0.75, cyclePhase);
        needTriggerCheck = false;
    }
    
    // 只在渐显阶段检查触发条件（节省 smoothstep 计算）
    if (needTriggerCheck) {
        float trigger = smoothstep(0.02, 0.08, mid);
        envelope *= trigger;
    }
    
    if (envelope < 0.01) return float3(0.0);
    
    // AI 颜色只读一次
    float3 blueBeam = mood.topLightArray.rgb;
    if (!colorIsSet(blueBeam)) {
        blueBeam = float3(0.3, 0.6, 1.0);
    }
    blueBeam *= 0.75 * envelope;  // 亮度从 0.52 提升到 0.65
    
    float3 arrayOut = float3(0.0);
    float screenWidth = max(aspectRatio, 0.1);
    float wideFactor = saturate((screenWidth - 1.0) / 1.4);
    float fanSpread = atan(screenWidth * 0.10);
    float scanAmplitude = mix(0.18, 0.28, wideFactor);
    
    // Four floor fixtures span 68% of the screen width, independent of aspect.
    for (int i = 0; i < 4; i++) {
        float iFloat = float(i);
        float fanPosition = (iFloat - 1.5) / 1.5;
        float xPos = fanPosition * screenWidth * 0.34;
        float yPos = 0.56 + stageHash(float2(iFloat, 0.0)) * 0.03;
        float2 lightPos = float2(xPos, yPos);
        
        float randomAngle = stageHash(float2(iFloat, 1.0)) * 0.08 - 0.04;
        float tiltAngle = fanPosition * fanSpread + randomAngle;
        float scanSpeed = 0.40 + stageHash(float2(iFloat, 2.0)) * 0.12;  // 摆动速度从 0.1~0.16 提升到 0.24~0.36
        float scanOffset = sin(time * scanSpeed + iFloat * 0.7) * scanAmplitude;
        float beamAngle = tiltAngle + scanOffset;
        
        float2 toP = p - lightPos;
        float dist = length(toP);
        if (dist < 0.001) continue;
        
        // 预计算方向的 sin/cos
        float sa = sin(beamAngle);
        float ca = -cos(beamAngle);
        float2 dir = float2(sa, ca);
        float along = dot(toP, dir);
        if (along < 0.0) continue;
        
        float perpDistSq = dot(toP, toP) - along * along;
        
        // A wider volumetric cone spreads from each distinct floor aperture.
        float beamWidth = 0.022 + along * mix(0.055, 0.08, wideFactor);
        float bwSq = beamWidth * beamWidth;
        float beamCore = exp(-perpDistSq / bwSq);
        
        float lengthFade = exp(-along * 1.2);
        // 底部雾灯向上照射，沿光轴保留近亮远暗的纵深。
        float axialFade = exp(-along * along * 0.12);
        
        float3 beam = blueBeam * (beamCore * lengthFade * axialFade);
        // 柔和叠加：防止多束光交汇时过曝（使用 soft-light 混合而非线性累加）
        // 公式：out = out + beam * (1 - out*k)，高亮区域增长变缓
        arrayOut += beam * (1.0 - dot(arrayOut, arrayOut) * 0.35);
    }
    
    return arrayOut;
}

// ============================================================================
// 6. LaserSystem - 激光/镭射多样式
//    优化：
//    - laserLine 内联，避免函数调用 + 减少 length() 调用
//    - AI 颜色每个子系统只读一次
//    - pow(1-x, N) 替换为 exp(-N*x) 近似（视觉几乎一致）
//    - atan2 延迟到 C/D/E/F 区块（仅在 envelope > 0 时计算）
//    - 共用 sin/cos 预计算
// ============================================================================

// 内联版激光线 + 沿光轴体积积分感
// axialFade 让光有「从舞台深处射出」的纵深层次，扇形转竖时前后自然拉开
static inline float laserLineInline(float2 toP, float2 dir, float thickness) {
    float along = dot(toP, dir);
    if (along < 0.0) return 0.0;
    float perpDistSq = dot(toP, toP) - along * along;
    float perpDist = sqrt(max(perpDistSq, 0.0));
    float core = step(perpDist, thickness);
    float invThick3 = 1.0 / (thickness * 3.0);
    float glow = exp(-perpDist * invThick3);
    float intensity = core * 0.8 + glow * 0.35;
    // 沿光轴的体积积分衰减：近处亮、远处暗，模拟光穿过烟雾的散射
    float axialFade = exp(-along * along * 0.15);
    return intensity * axialFade;
}

// Finite 3D laser volumes. Coordinates and radii are world-space units;
// the fullscreen pass ray-renders the volumes rather than enlarging 2D lines.
struct DesktopLaserTunnelUniforms {
    float4 geometry;   // beamCount (total), fanAngle, depth, beamLength
    float4 motion;     // approachSpeed, cameraAimStrength, yawAmplitude, pitchAmplitude
    float4 appearance; // glowIntensity, nearPlane, verticalFOV, mode (0=legacy, 1=dual fan)
};
struct LaserCamera {
    float3 position, right, up, forward;
    float nearPlane, tanHalfFOV;
};

// Perspective projection into the existing aspect-correct p coordinates.
// Camera-local Y is up; the iOS-compatible stage coordinates use Y down.
static float2 laserProject(float3 point, thread const LaserCamera &camera) {
    float3 relative = point - camera.position;
    float z = max(dot(relative, camera.forward), camera.nearPlane);
    return float2(dot(relative, camera.right), -dot(relative, camera.up))
         / (2.0 * z * camera.tanHalfFOV);
}

static float laserVolume(float2 p, float3 origin, float3 direction, float beamLength,
                         float scanTravel, float pixelStep, thread const LaserCamera &camera) {
    // Clip the actual spatial segment against the camera near plane BEFORE projection.
    float zOrigin = dot(origin - camera.position, camera.forward);
    float zDirection = dot(direction, camera.forward);
    float startTravel = 0.0, endTravel = beamLength;
    if (abs(zDirection) < 0.00001) {
        if (zOrigin < camera.nearPlane) return 0.0;
    } else {
        float crossing = (camera.nearPlane - zOrigin) / zDirection;
        if (zDirection < 0.0) endTravel = min(endTravel, crossing);
        else startTravel = max(startTravel, crossing);
    }
    if (endTravel <= startTravel) return 0.0;
    float3 a = origin + direction * startTravel;
    float3 b = origin + direction * endTravel;
    float2 screenA = laserProject(a, camera), screenB = laserProject(b, camera);

    const float radius = 0.006;
    float nearestZ = max(min(dot(a - camera.position, camera.forward),
                            dot(b - camera.position, camera.forward)), camera.nearPlane);
    // Conservative projected bounds for the cylinder and its emissive halo.
    float projectedHalo = radius * 18.0 / (2.0 * nearestZ * camera.tanHalfFOV);
    float2 edge = screenB - screenA;
    float screenT = saturate(dot(p - screenA, edge) / max(dot(edge, edge), 0.000001));
    if (distance(p, screenA + edge * screenT) > projectedHalo) return 0.0;

    // Inverse perspective: a camera ray through this pixel, in the local camera basis.
    float3 rayDirection = normalize(camera.forward
        + camera.right * (p.x * 2.0 * camera.tanHalfFOV)
        - camera.up * (p.y * 2.0 * camera.tanHalfFOV));
    float3 rayOrigin = camera.position + rayDirection
        * (camera.nearPlane / max(dot(rayDirection, camera.forward), 0.00001));
    float3 relative = rayOrigin - a;
    float rayBeamDot = dot(rayDirection, direction);
    float rayOffset = dot(rayDirection, relative);
    float beamOffset = dot(direction, relative);
    float denominator = 1.0 - rayBeamDot * rayBeamDot;
    float clippedLength = endTravel - startTravel;
    float travel = denominator > 0.00001
        ? clamp((beamOffset - rayBeamDot * rayOffset) / denominator, 0.0, clippedLength)
        : clamp(beamOffset, 0.0, clippedLength);
    float rayTravel = max(rayBeamDot * travel - rayOffset, 0.0);
    travel = clamp(beamOffset + rayBeamDot * rayTravel, 0.0, clippedLength);
    rayTravel = max(rayBeamDot * travel - rayOffset, 0.0);
    float3 beamPoint = a + direction * travel;
    float radialDistance = distance(rayOrigin + rayDirection * rayTravel, beamPoint);
    float viewDepth = max(dot(beamPoint - camera.position, camera.forward), camera.nearPlane);
    float pixelRadius = 2.0 * viewDepth * camera.tanHalfFOV
                      * pixelStep;
    float core = 1.0 - smoothstep(max(radius - pixelRadius, 0.0), radius + pixelRadius, radialDistance);
    float halo = exp(-radialDistance / (radius * 3.0));
    float bloom = exp(-radialDistance / (radius * 6.0));

    // The head and its trailing streak move along the original world-space beam,
    // including the part beyond the near plane. It never sticks to the clipped tip.
    float headDistance = startTravel + travel - scanTravel;
    float head = exp(-headDistance * headDistance / (0.22 * 0.22));
    float trail = exp(-max(-headDistance, 0.0) / 0.55)
                * (1.0 - smoothstep(0.0, 0.18, headDistance));
    float scan = max(head, trail * 0.65);
    // Hide the cyclic wrap at the beam ends instead of snapping the head back.
    float scanPhase = scanTravel / max(beamLength, 0.001);
    float wrapFade = smoothstep(0.0, 0.045, scanPhase)
                   * (1.0 - smoothstep(0.955, 1.0, scanPhase));
    scan *= wrapFade;
    float scattering = exp(-viewDepth * 0.035);
    return (core * (0.32 + scan * 2.4) + halo * (0.24 + scan * 1.1)
            + bloom * (0.045 + scan * 0.20)) * scattering;
}

static float dualFanLaserPitchCrossing(float2 p, float pixelStep, float time, float treble,
                                      float horizontalSweep, constant DesktopLaserTunnelUniforms &settings) {
    if (settings.appearance.x <= 0.0) return 0.0;
    LaserCamera camera;
    camera.position = float3(0.0);
    camera.forward = normalize(float3(0, 0, 1));
    camera.right = normalize(cross(float3(0, 1, 0), camera.forward));
    camera.up = normalize(cross(camera.forward, camera.right));
    camera.nearPlane = clamp(settings.appearance.y, 0.01, 1.0);
    camera.tanHalfFOV = tan(clamp(settings.appearance.z, 0.35, 2.2) * 0.5);
    int beamCount = clamp(int(settings.geometry.x), 1, 64);
    int firstGroupCount = (beamCount + 1) / 2;
    float fanAngle = clamp(settings.geometry.y, 0.0, 1.4);
    float depth = max(settings.geometry.z, camera.nearPlane + 0.5);
    // Keep both fixed emitter points fully outside the visible screen.
    // The beams enter from beyond the edge; their source hardware is hidden.
    const float emitterEdge = 0.62;
    float height = emitterEdge * 2.0 * depth * camera.tanHalfFOV;
    float crossingDepth = depth * 0.43;
    float basePitch = atan2(height, depth - crossingDepth);
    float minimumVisiblePitch = atan2(height, max(depth - camera.nearPlane, 0.01));
    float pitchAmplitude = min(max(settings.motion.w, 0.0), max(basePitch - minimumVisiblePitch, 0.0));
    float minimumPitch = max(basePitch - pitchAmplitude, 0.12);
    float travelToCross = height / sin(minimumPitch);
    float safeLength = (depth - camera.nearPlane * 1.8) / cos(minimumPitch);
    float beamLength = max(0.01, min(max(settings.geometry.w, travelToCross + depth * 0.12), safeLength));
    float sum = 0.0;
    // One fixed emitter per row; yaw opens each fan while pitch moves the
    // entire upper and lower fans in opposite directions.
    // Quadrature pan/tilt keeps the beam moving through vertical turning points.
    float scanPhase = time * 0.55;
    float pitchScan = sin(scanPhase) * pitchAmplitude;
    float yawScan = cos(scanPhase) * settings.motion.z
                  * mix(0.40, 1.80, horizontalSweep);
    for (int i = 0; i < beamCount; ++i) {
        bool firstGroup = i < firstGroupCount;
        int groupCount = firstGroup ? firstGroupCount : beamCount - firstGroupCount;
        int groupIndex = firstGroup ? i : i - firstGroupCount;
        float row = firstGroup ? 1.0 : -1.0;
        float fanPosition = groupCount > 1 ? float(groupIndex) / float(groupCount - 1) * 2.0 - 1.0 : 0.35;
        // Preserve the upper/lower screen anchors, but keep one origin per
        // group so the fan is created by direction rather than moving emitters.
        float3 origin = camera.position + camera.forward * depth + camera.up * (row * height);
        float yaw = fanPosition * fanAngle * 0.5 + yawScan;
        float pitch = -row * (basePitch + pitchScan);
        float3 direction = normalize(camera.right * (sin(yaw) * cos(pitch))
                                   + camera.up * sin(pitch)
                                   - camera.forward * (cos(yaw) * cos(pitch)));
        // Keep scan velocity independent of per-frame FFT changes.
        float speed = max(settings.motion.x, 0.0);
        float scanTravel = fract(time * speed / beamLength - float(i) * 0.071) * beamLength;
        sum += laserVolume(p, origin, direction, beamLength, scanTravel, pixelStep, camera);
    }
    return sum * max(settings.appearance.x, 0.0);
}

static float3 laserSystem(float2 p, float pixelStep, float time, float treble, float piano,
                          float fftMid, float guitarPeak, float liveGuitarPeak,
                          constant DesktopMoodColors &mood, constant DesktopLaserTunnelUniforms &laserSettings) {
    float3 laserOut = float3(0.0);
    float distSq = dot(p, p);
    float dist = sqrt(distSq);
    
    // ====== A. Laser Fan Top + Bottom（蓝色激光扇形）======
    // The trigger envelope stays latched; FFT only modulates its brightness.
    float guitarClimax = smoothstep(0.28, 0.62, max(guitarPeak, liveGuitarPeak));
    float fanEnvelope = max(smoothstep(0.02, 0.12, treble), guitarClimax);
    if (fanEnvelope > 0.01) {
        float3 blueColor = mood.laserFanBlue.rgb;
        if (!colorIsSet(blueColor)) {
            blueColor = float3(0.25, 0.55, 1.0);
        }
        
        if (laserSettings.appearance.w > 0.5) {
            float sweepPhase = fract(time / 18.0);
            float horizontalSweep = smoothstep(0.34, 0.39, sweepPhase)
                                  * (1.0 - smoothstep(0.55, 0.60, sweepPhase));
            horizontalSweep = max(horizontalSweep, guitarClimax * 0.8);
            float blueBrightness = 1.0 + guitarClimax * 1.15;
            laserOut += blueColor * (dualFanLaserPitchCrossing(p, pixelStep, time, treble,
                                                               horizontalSweep, laserSettings)
                                     * 0.38 * fanEnvelope * blueBrightness);
        } else {
            // ====== Top 6 条 ======
            float2 fanOrigin = float2(0.0, 0.56);
            // 多频率叠加运动：组合快慢不同的正弦波，形成不规则、有机的运动感
            float planeRotation = time * 0.15 + sin(time * 0.06) * 0.4;  // 主旋转 + 缓慢摆动
            float cosPlane = cos(planeRotation);
            float sinPlane = sin(planeRotation);
            // 复合摆动：3 个频率叠加（主频 + 快频 + 慢频）→ 类似真人操作灯光的不规则感
            float baseSwing = sin(time * 0.28) * 0.42        // 主摆动
                            + sin(time * 0.17) * 0.18        // 慢摆动（增加"呼吸感"）
                            + sin(time * 0.51) * 0.08;       // 快抖动（微小抖动，更生动）
            float blueMul = 0.38 * fanEnvelope;

            float2 toP = p - fanOrigin;

            for (int i = 0; i < 6; i++) {  // 7→6
                float iF = float(i);
                // 调整分布：6 条均匀分布，保持扇形覆盖
                float spreadInPlane = (iF - 2.5) * 0.095;  // 中心为 i=2.5
                float angleInPlane = baseSwing + spreadInPlane;

                float worldAngle = angleInPlane * cosPlane;
                float depthAngle = angleInPlane * sinPlane;

                float2 dir = float2(sin(worldAngle), -cos(worldAngle));
                float beam = laserLineInline(toP, dir, 0.0012);  // 细激光（原 0.002）
                float depthFade = (1.0 - abs(depthAngle) * 0.3) * exp(-depthAngle * depthAngle * 2.5);

                laserOut += blueColor * (beam * blueMul * depthFade);
            }

            // ====== Bottom 6 条 ======
            float2 fanBottomOrigin = float2(0.0, -0.56);
            // 底部扇形：使用不同的频率组合，与顶部形成对比和呼应
            float planeRotationBottom = time * 0.18 + 1.57 + sin(time * 0.08) * 0.35;
            float cosPlaneB = cos(planeRotationBottom);
            float sinPlaneB = sin(planeRotationBottom);
            // 底部摆动：频率与顶部错开，避免同步（更自然）
            float baseSwingBottom = sin(time * 0.32 + 1.0) * 0.38
                                   + sin(time * 0.21 + 0.5) * 0.2   // 慢频，相位偏移
                                   + sin(time * 0.58 + 0.8) * 0.09; // 快频，相位偏移
            float blueMulB = 0.35 * fanEnvelope;

            float2 toPB = p - fanBottomOrigin;

            for (int i = 0; i < 6; i++) {  // 7→6
                float iF = float(i);
                float spreadInPlane = (iF - 2.5) * 0.095;
                float angleInPlane = baseSwingBottom + spreadInPlane;

                float worldAngle = 3.14159 + angleInPlane * cosPlaneB;
                float depthAngle = angleInPlane * sinPlaneB;

                float2 dir = float2(sin(worldAngle), -cos(worldAngle));
                float beam = laserLineInline(toPB, dir, 0.0012);  // 细激光（原 0.002）
                float depthFade = (1.0 - abs(depthAngle) * 0.3) * exp(-depthAngle * depthAngle * 2.5);

                laserOut += blueColor * (beam * blueMulB * depthFade);
            }
        }
    }

    // ====== B. Green Laser Patterns（绿色激光多样式）- 渐入渐出 + DSP 展示 ======
    float greenPhase = fract(time * 0.11);   // Match iOS global pattern timing.
    // The iOS green pattern geometry follows the separated piano envelope.
    float greenTrigger = smoothstep(0.04, 0.12, piano) * 0.88;
    float greenEnvelope = fadeEnvelope(greenPhase, 0.28, 0.28);
    greenEnvelope *= smoothstep(0.25, 0.65, greenTrigger);
    float dspBreath = 0.78 + 0.55 * piano;
    greenEnvelope *= saturate(dspBreath);
    
    if (greenEnvelope > 0.01) {
        float patternSwitch = fract(time * 0.065);  // Match iOS pattern rotation.
        float patternPhase = fract(patternSwitch * 5.0);
        greenEnvelope *= smoothstep(0.0, 0.08, patternPhase)
                       * (1.0 - smoothstep(0.92, 1.0, patternPhase));
        float3 greenColor = mood.laserFanGreen.rgb;
        if (!colorIsSet(greenColor)) {
            greenColor = float3(0.35, 1.0, 0.45);
        }
        
        if (patternSwitch < 0.2) {
            // Pattern 1: 左右两侧扇形各 3 条（DSP：摆幅受 piano 影响）
            float baseSwingGreen = sin(time * 0.3) * (0.5 + piano * 0.25);
            float greenMul = 0.78 * greenEnvelope;
            float2 greenLeftOrigin = float2(-0.2, 0.56);
            float2 toPL = p - greenLeftOrigin;
            float2 greenRightOrigin = float2(0.2, 0.56);
            float2 toPR = p - greenRightOrigin;
            for (int i = 0; i < 3; i++) {
                float spread = (float(i) - 1.0) * 0.12;
                float beamAngle = baseSwingGreen + spread;
                float2 dir = float2(sin(beamAngle), -cos(beamAngle));
                float beamL = laserLineInline(toPL, dir, 0.0017);
                float beamR = laserLineInline(toPR, dir, 0.0017);
                float spreadVol = exp(-spread * spread * 3.0);
                laserOut += greenColor * ((beamL + beamR) * greenMul * spreadVol);
            }
            
        } else if (patternSwitch < 0.4) {
            // Pattern 2: 单条聚光灯从左扫到右（DSP：扫速略随 piano）
            float scanSpeed = 1.2 + piano * 0.4;
            float scanAngle = -0.7 + fract(time * 0.08) * scanSpeed * 1.4;
            float2 greenScanOrigin = float2(0.0, 0.58);
            float2 toP = p - greenScanOrigin;
            float2 dir = float2(sin(scanAngle), -cos(scanAngle));
            float beam = laserLineInline(toP, dir, 0.0025);
            laserOut += greenColor * (beam * 1.2 * greenEnvelope);
            
        } else if (patternSwitch < 0.6) {
            // Pattern 3: X 形交叉（开口随 phase 变化）
            float2 greenCrossOrigin = float2(0.0, -0.56);
            float crossSpread = 0.35 + greenPhase * 0.35;
            float2 toP = p - greenCrossOrigin;
            float aL = 3.14159 - crossSpread;
            float aR = 3.14159 + crossSpread;
            float2 dirL = float2(sin(aL), -cos(aL));
            float2 dirR = float2(sin(aR), -cos(aR));
            float beamL = laserLineInline(toP, dirL, 0.0016);
            float beamR = laserLineInline(toP, dirR, 0.0016);
            laserOut += greenColor * ((beamL + beamR) * 0.88 * greenEnvelope);
            
        } else if (patternSwitch < 0.8) {
            // Pattern 4: 中心径向放射 6 条（DSP：旋转 + 扩散受 piano 影响）
            float2 centerOrigin = float2(0.0, 0.0);
            float2 toP = p - centerOrigin;
            float baseAngle = time * 0.2 + piano * 0.5;
            float greenMul = (0.65 + 0.4 * piano) * greenEnvelope;  // 低音越强越亮
            for (int i = 0; i < 6; i++) {
                float angle = baseAngle + float(i) * 1.047;
                float2 dir = float2(sin(angle), cos(angle));
                float beam = laserLineInline(toP, dir, 0.0022);
                laserOut += greenColor * (beam * greenMul);
            }
            
        } else {
            // Pattern 5: 上下双源斜扫（DSP：亮度随 piano 脉冲）
            float tilt = time * 0.25 + piano * 0.3;
            float topY = 0.52;
            float botY = -0.52;
            float2 toTop = p - float2(0.0, topY);
            float2 toBot = p - float2(0.0, botY);
            float angleTop = 1.57 + sin(tilt) * 0.6;
            float angleBot = -1.57 - sin(tilt + 0.8) * 0.6;
            float2 dirT = float2(sin(angleTop), -cos(angleTop));
            float2 dirB = float2(sin(angleBot), -cos(angleBot));
            float beamT = laserLineInline(toTop, dirT, 0.002);
            float beamB = laserLineInline(toBot, dirB, 0.002);
            float pulse = 0.75 + 0.35 * piano;
            laserOut += greenColor * ((beamT + beamB) * 0.82 * greenEnvelope * pulse);
        }
    }
    
    // ====== C. 旋转光束（粉色/品红）- 渐显-保持-渐消 ======
    float beamPhase = fract(time / 9.0);
    float beamEnvelope = fadeEnvelope(beamPhase, 0.2, 0.2);
    // Match iOS: center beams follow the current FFT mid band, rather than a
    // separated guitar stem held at its activation strength for nine seconds.
    float beamTrigger = smoothstep(0.04, 0.15, fftMid);
    beamEnvelope *= beamTrigger;
    
    if (beamEnvelope > 0.01 && dist > 0.01) {
        // 延迟 atan2 到这里（只有需要时才计算）
        float angle = atan2(p.y, p.x);
        float distFade = exp(-dist * 2.0);
        
        float3 rotBeamColor = mood.rotatingBeam.rgb;
        if (!colorIsSet(rotBeamColor)) {
            rotBeamColor = float3(1.0, 0.4, 0.8);
        }
        
        // 3 条旋转光束 - pow(1-x, 20) ≈ exp(-20*x) 对 x∈[0,1] 近似
        float baseAngle = angle + time * 0.3;
        for (int i = 0; i < 3; i++) {
            float beamAngle = baseAngle + float(i) * 2.094;
            float s = abs(sin(beamAngle * 1.5));
            // exp(-20*s) 近似 pow(1-s, 20)，视觉效果几乎一致
            float beam = exp(-20.0 * s) * distFade;
            laserOut += rotBeamColor * (beam * beamEnvelope);
        }
        
        // 额外 6 条细丝
        float climaxFade = smoothstep(0.12, 0.28, fftMid);
        if (climaxFade > 0.01) {
            float3 rotExtraColor = mood.rotatingBeamExtra.rgb;
            if (!colorIsSet(rotExtraColor)) {
                rotExtraColor = float3(1.0, 0.5, 0.9);
            }
            float distFade2 = exp(-dist * 2.5) * 0.8;
            float extraMul = climaxFade * beamEnvelope;
            
            float baseAngle2 = angle - time * 0.4;
            for (int i = 0; i < 6; i++) {
                float beamAngle = baseAngle2 + float(i) * 1.047;
                float s = abs(sin(beamAngle * 3.0));
                float beam = exp(-25.0 * s) * distFade2;
                laserOut += rotExtraColor * (beam * extraMul);
            }
        }
        
        // ====== D. 外围长丝（粉紫）- 渐显-保持-渐消 ======
        float longBeamPhase = fract(time / 11.0);
        float longBeamEnvelope = fadeEnvelope(longBeamPhase, 0.18, 0.18);
        float longBeamTrigger = smoothstep(0.05, 0.18, fftMid);
        longBeamEnvelope *= longBeamTrigger;
        
        if (longBeamEnvelope > 0.01) {
            float3 coronaColor = mood.coronaFilaments.rgb;
            if (!colorIsSet(coronaColor)) {
                coronaColor = float3(0.9, 0.6, 0.8);
            }
            float coronaMul = 0.6 * longBeamEnvelope;
            
            for (int i = 0; i < 3; i++) {
                float iFloat = float(i);
                float flareAngle = angle - time * 0.15 + iFloat * 2.094;
                float wave = sin(dist * 8.0 - time * 2.0 + iFloat * 2.0) * 0.1;
                float s = abs(sin(flareAngle * 1.5 + wave));
                float flare = exp(-15.0 * s);  // 替代 pow(1-s, 15)
                float pulse = 1.2 + 0.3 * sin(time * 0.5 + iFloat * 1.5);
                float beam = flare * exp(-dist * pulse) * coronaMul;
                laserOut += coronaColor * beam;
            }
        }
        
        // ====== E. 放射状日冕丝 - 渐显-保持-渐消 ======
        float coronaPhase = fract(time / 13.0);
        float coronaEnvelope = fadeEnvelope(coronaPhase, 0.15, 0.15);
        float coronaTrigger = smoothstep(0.06, 0.2, guitarPeak);
        coronaEnvelope *= coronaTrigger;
        
        if (coronaEnvelope > 0.01) {
            float3 coronaRadColor = mood.coronaFilaments.rgb;
            if (!colorIsSet(coronaRadColor)) {
                coronaRadColor = float3(1.0, 0.6, 0.2);
            } else {
                coronaRadColor = mix(coronaRadColor, float3(1.0, 0.7, 0.3), 0.4);
            }
            float coronaMul = exp(-dist * 3.5) * 0.5 * coronaEnvelope;
            
            // 12 条放射状细丝
            // 优化：预计算基础角度，pow(1-x, 30) ≈ exp(-30*x)
            float baseCoronaAngle = angle + time * 0.2;
            for (int i = 0; i < 12; i++) {
                float coronaAngle = baseCoronaAngle + float(i) * 0.524;
                float s = abs(sin(coronaAngle * 6.0));
                float beam = exp(-30.0 * s) * coronaMul;
                laserOut += coronaRadColor * beam;
            }
        }
    }
    
    // ====== F. 脉冲环（紫色）- 渐显-保持-渐消 ======
    float ringPhase = fract(time / 7.0);
    float ringEnvelope = fadeEnvelope(ringPhase, 0.2, 0.2);
    float ringTrigger = smoothstep(0.05, 0.15, guitarPeak);
    ringEnvelope *= ringTrigger;
    
    if (ringEnvelope > 0.01) {
        float3 ringColor = mood.pulseRing.rgb;
        if (!colorIsSet(ringColor)) {
            ringColor = float3(0.8, 0.3, 1.0);
        }
        float ringDist = ringPhase * 0.8;
        float ring = exp(-abs(dist - ringDist) * 25.0);
        laserOut += ringColor * (ring * ringEnvelope * 0.6);
    }
    
    return laserOut;
}

fragment float4 desktopTyndallFragment(TyndallVertexOut in [[stage_in]],
                                     constant TyndallVisualAudio &uniforms [[buffer(0)]],
                                     constant DesktopMoodColors &mood [[buffer(1)]],
                                     constant TyndallAnimationUniforms &animation [[buffer(2)]],
                                     constant DesktopLaserTunnelUniforms &laserSettings [[buffer(3)]]) {
    // CommonVertexShader on iOS maps the top of the screen to uv.y = 0.
    // The fullscreen triangle's interpolated UV runs in the opposite direction.
    float2 uv = float2(in.uv.x, 1.0 - in.uv.y);
    float time = uniforms.time;
    float2 p = uv - 0.5;
    p.x *= uniforms.aspectRatio;
    float pixelStep = max(length(dfdx(p)), length(dfdy(p)));

    // Keep the iOS light geometry, layer unlocks, rhythm and color processing.
    float aiBpm = 120.0;
    float aiEnergy = 0.7;
    float aiAnimSpeed = 1.0;
    float aiBright = 1.0;
    float aiTrigSens = 1.0;
    float aiAtmoInt = 0.45;
    float animTime = time * aiAnimSpeed;

    float bass = uniforms.bass * aiTrigSens * uniforms.playing;
    float mid = uniforms.mid * aiTrigSens * uniforms.playing;
    float high = uniforms.treble * aiTrigSens * uniforms.playing;
    float4 elapsed = max(float4(time) - animation.starts, 0.0);
    float peakElapsed = max(time - animation.peak.x, 0.0);
    float floorMid = animation.strengths.x * activationEnvelope(elapsed.x, 12.0);
    float treble = animation.strengths.y * activationEnvelope(elapsed.y, 3.0);
    float piano = animation.strengths.z * activationEnvelope(elapsed.z, 15.384615);
    float guitar = animation.strengths.w * activationEnvelope(elapsed.w, 9.0);
    float guitarPeak = animation.peak.y * activationEnvelope(peakElapsed, 3.0);

    float totalEnergy = (bass + mid + high) / 3.0;
    float peakValue = max(max(bass, mid), high);
    float energy = pow(saturate(max(totalEnergy * 1.2, smoothstep(0.08, 0.38, peakValue))), 0.55);

    float beatPeriod = 60.0 / max(aiBpm, 60.0);
    float beatPhase = fract(time / beatPeriod);
    float beatPulse = exp(-beatPhase * 5.0);
    float musicGate = smoothstep(0.02, 0.08, totalEnergy);
    beatPulse *= musicGate;

    float3 finalColor = float3(0.015, 0.012, 0.025);
    float hazeVal = stageNoise(p * 5.0 + animTime * 0.15) * 0.55
                  + stageNoise(p * 10.0 - animTime * 0.08) * 0.3;

    float atmoBreath = 1.0 + beatPulse * 0.15 * aiEnergy;
    finalColor += atmosphereField(uv, bass, hazeVal, mood) * aiAtmoInt / 0.45 * atmoBreath;

    float unlock1 = smoothstep(0.02, 0.08, energy);
    if (unlock1 > 0.01) {
        float volBright = aiBright * (1.0 + beatPulse * 0.2 * aiEnergy);
        finalColor += volumetricBeamSystem(p, animTime, bass, hazeVal, uniforms.aspectRatio, mood)
                    * unlock1 * volBright;
        finalColor += edgeLight(uv, piano, mood) * unlock1 * aiBright;
    }

    float floorActivity = smoothstep(0.02, 0.08, floorMid);
    float unlock2 = smoothstep(0.02, 0.08, max(energy, floorActivity * 0.12));
    if (unlock2 > 0.01 && floorMid > 0.001) {
        float3 floorLight = floorLightArray(p, animTime, floorMid, uniforms.aspectRatio, mood)
                          * unlock2 * aiBright;
        floorLight *= (1.0 + beatPulse * 0.25 * aiEnergy);
        finalColor += floorLight;
    }

    float liveGuitarPeak = uniforms.guitarPeak * uniforms.playing;
    float laserActivity = max(max(treble, piano), max(guitar, max(guitarPeak, liveGuitarPeak)));
    float unlock3 = smoothstep(0.015, 0.12, max(energy, laserActivity));
    if (unlock3 > 0.01) {
        float3 laser = laserSystem(p, pixelStep, animTime, treble, piano, mid, guitarPeak, liveGuitarPeak,
                                   mood, laserSettings) * unlock3 * aiBright;
        laser *= (1.0 + beatPulse * 0.35 * aiEnergy);
        finalColor += laser;
    }

    float luminance = dot(finalColor, float3(0.299, 0.587, 0.114));
    float compress = luminance / (1.0 + luminance * 0.45);
    if (luminance > 0.01) finalColor *= compress / luminance;
    float pLenSq = dot(p, p);
    finalColor *= max(1.0 - 0.2 * pLenSq, 0.0);
    return float4(finalColor, 1.0);
}
