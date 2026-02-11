//
//  TyndallBeamShader.metal
//  AudioSampleBuffer
//
//  舞台灯光系统 - 6 个独立光学子系统分层协作（GPU 优化版）
//
//  1. AtmosphereField   - 烟雾/氛围场 (always on)
//  2. VolumetricBeam     - 体积光束 (energy > 0.08)
//  3. EdgeLight          - 底部边缘描绘光 (energy > 0.08)
//  4. TopLightArray      - 顶部灯光阵列 3D 照射 (energy > 0.22)
//  5. (Reserved)
//  6. LaserSystem        - 激光/镭射多样式 (energy > 0.40)
//
//  Audio mapping:
//    bass  -> atmosphere, volumetric brightness
//    mid   -> top array trigger (完整动画周期，不闪烁), edge glow
//    high  -> laser trigger + 旋转光束
//    energy(combined) -> layer unlock only
//
//  GPU 优化策略:
//    - 消除重复 stageNoise 计算（atmosphereField + main 共用）
//    - length(color) 改为 dot() 避免 sqrt
//    - 音频分析用 stride=2 减半循环次数
//    - 三角函数预计算，循环内复用
//    - pow(x, N) 替换为 exp(-k*x^2) 近似
//    - laserLine 内联到循环中减少函数调用
//    - atan2 延迟到真正需要时才计算
//

#include <metal_stdlib>
#include "ShaderCommon.metal"

using namespace metal;

// ============================================================================
// Utility
// ============================================================================

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

// ============================================================================
// 1. AtmosphereField - 烟雾氛围场
//    优化：hazeVal 由外部传入，避免重复计算
// ============================================================================

static float3 atmosphereField(float2 uv, float bass, float hazeVal, constant UniformsAI &uniforms) {
    float density = 0.6 + 0.4 * (1.0 - uv.y);
    float haze = hazeVal * density;
    float breath = 1.0 + bass * 0.4;
    
    float3 baseColor = uniforms.aiColorAtmosphere.rgb;
    if (!colorIsSet(baseColor)) {
        baseColor = float3(0.06, 0.055, 0.08);
    }
    return baseColor * haze * breath;
}

// ============================================================================
// 2. VolumetricBeamSystem - 体积光束
//    优化：内联 volumetricCone，减少函数调用
// ============================================================================

static float3 volumetricBeamSystem(float2 p, float time, float bass, float hazeVal, constant UniformsAI &uniforms) {
    float volume = 0.5 + hazeVal * 0.5;
    float brightness = 0.45 + bass * 0.35;
    float coneW = 0.55 + bass * 0.15;
    float cosThresh = cos(coneW);
    float radSq = 0.95 * 0.95;  // radius^2 预计算
    
    float3 color = uniforms.aiColorVolumetricBeam.rgb;
    if (!colorIsSet(color)) {
        color = float3(1.0, 0.88, 0.72);
    }
    color *= brightness;
    
    // 左侧光束
    float2 toL = p - float2(-0.42, 0.48);
    float distLSq = dot(toL, toL);
    float distL = sqrt(distLSq);
    float beamL = 0.0;
    if (distL > 0.001) {
        float2 dL = toL / distL;
        float sweepL_angle = sin(time * 0.35) * 1.1;
        float2 dirLn = float2(sin(sweepL_angle), -cos(sweepL_angle));
        float alignL = dot(dL, dirLn);
        float coneL = smoothstep(cosThresh, 0.94, alignL);
        float falloffL = exp(-distLSq / radSq);
        // 沿光轴体积积分：光束中轴线上的点更亮，边缘散射衰减
        float axialL = dot(toL, dirLn);
        float axialFadeL = exp(-axialL * axialL * 0.08);
        beamL = coneL * falloffL * volume * axialFadeL;
    }
    
    // 右侧光束
    float2 toR = p - float2(0.42, 0.48);
    float distRSq = dot(toR, toR);
    float distR = sqrt(distRSq);
    float beamR = 0.0;
    if (distR > 0.001) {
        float2 dR = toR / distR;
        float sweepR_angle = sin(time * 0.28 + 2.1) * 1.1;
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

static float3 edgeLight(float2 uv, float mid, constant UniformsAI &uniforms) {
    float ySq = uv.y * uv.y;
    // exp(-y^2 / w^2) where w=0.12, 1/w^2 = 69.44
    float glow = exp(-ySq * 69.44);
    float intensity = 0.2 + mid * 0.6;
    float3 edgeColor = uniforms.aiColorEdgeLight.rgb;
    if (!colorIsSet(edgeColor)) {
        edgeColor = float3(1.0, 0.75, 0.35);
    }
    return edgeColor * glow * intensity;
}

// ============================================================================
// 4. TopLightArray - 顶部灯光阵列 3D 照射（优化版：4 盏灯 + 锁定包络）
//    性能优化：减少灯数 7→4，触发后锁定包络期间不再计算 DSP
// ============================================================================

static float3 topLightArray(float2 p, float time, float mid, constant UniformsAI &uniforms) {
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
    float3 blueBeam = uniforms.aiColorTopLightArray.rgb;
    if (!colorIsSet(blueBeam)) {
        blueBeam = float3(0.3, 0.6, 1.0);
    }
    blueBeam *= 0.65 * envelope;  // 亮度从 0.52 提升到 0.65
    
    float3 arrayOut = float3(0.0);
    
    // 优化：4 盏灯（从 7 减少），调整间距保持覆盖范围
    for (int i = 0; i < 4; i++) {
        float iFloat = float(i);
        // 间距从 0.05 增加到 0.08，总跨度从 0.3 减少到 0.24
        float xPos = -0.12 + iFloat * 0.08;  // [-0.12, -0.04, 0.04, 0.12]
        float yPos = 0.56 + stageHash(float2(iFloat, 0.0)) * 0.03;
        float2 lightPos = float2(xPos, yPos);
        
        float randomAngle = stageHash(float2(iFloat, 1.0)) * 0.15 - 0.075;
        float tiltAngle = (iFloat - 1.5) * 0.03 + randomAngle;  // 中心为 i=1.5
        float scanSpeed = 0.24 + stageHash(float2(iFloat, 2.0)) * 0.12;  // 摆动速度从 0.1~0.16 提升到 0.24~0.36
        float scanOffset = sin(time * scanSpeed + iFloat * 0.7) * 0.15;
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
        
        float beamWidth = 0.018 + along * 0.022;
        float bwSq = beamWidth * beamWidth;
        float beamCore = exp(-perpDistSq / bwSq);
        
        float lengthFade = exp(-along * 1.2);
        // 沿光轴体积积分：顶部灯阵的光穿过烟雾，近亮远暗
        float axialFade = exp(-along * along * 0.12);
        
        arrayOut += blueBeam * (beamCore * lengthFade * axialFade);
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

static float3 laserSystem(float2 p, float time, float high, float mid, float bass, constant UniformsAI &uniforms) {
    float3 laserOut = float3(0.0);
    float distSq = dot(p, p);
    float dist = sqrt(distSq);
    
    // ====== A. Laser Fan Top + Bottom（蓝色激光扇形，优化版：12 条总 + 锁定包络）======
    // 性能优化：顶+底合并为 12 条（原 14），触发后锁定包络期间不计算 DSP
    float fanCycleDuration = 14.0;  // 完整周期 14 秒
    float fanPhase = fract(time / fanCycleDuration);
    
    // 三阶段包络（渐显拉长，避免出现太突然）：
    // [0, 0.22): 渐渐出现 + DSP 触发监听（约 3.1s 渐显）
    // [0.22, 0.72): 展示锁定阶段（不计算 DSP，固定 envelope=1.0）
    // [0.72, 1.0): 渐消阶段（3.92s）
    float fanEnvelope = 0.0;
    bool fanNeedTrigger = false;
    
    if (fanPhase < 0.22) {
        // 渐显：用较长区间 smoothstep，使亮度缓慢上升
        fanEnvelope = smoothstep(0.0, 0.22, fanPhase);
        fanNeedTrigger = true;
    } else if (fanPhase < 0.72) {
        fanEnvelope = 1.0;
        fanNeedTrigger = false;  // 锁定期，跳过 DSP
    } else {
        fanEnvelope = smoothstep(1.0, 0.72, fanPhase);
        fanNeedTrigger = false;
    }
    
    // 只在渐显阶段检查 DSP 触发
    if (fanNeedTrigger) {
        float fanTrigger = smoothstep(0.02, 0.07, high);
        fanEnvelope *= fanTrigger;
    }
    
    if (fanEnvelope > 0.01) {
        float3 blueColor = uniforms.aiColorLaserFanBlue.rgb;
        if (!colorIsSet(blueColor)) {
            blueColor = float3(0.25, 0.55, 1.0);
        }
        
        // ====== Top 6 条 ======
        float2 fanOrigin = float2(0.0, 0.56);
        float planeRotation = time * 0.15;
        float cosPlane = cos(planeRotation);
        float sinPlane = sin(planeRotation);
        float baseSwing = sin(time * 0.28) * 0.5;
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
            float beam = laserLineInline(toP, dir, 0.002);
            float depthFade = (1.0 - abs(depthAngle) * 0.3) * exp(-depthAngle * depthAngle * 2.5);
            
            laserOut += blueColor * (beam * blueMul * depthFade);
        }
        
        // ====== Bottom 6 条 ======
        float2 fanBottomOrigin = float2(0.0, -0.56);
        float planeRotationBottom = time * 0.18 + 1.57;
        float cosPlaneB = cos(planeRotationBottom);
        float sinPlaneB = sin(planeRotationBottom);
        float baseSwingBottom = sin(time * 0.32 + 1.0) * 0.5;
        float blueMulB = 0.35 * fanEnvelope;
        
        float2 toPB = p - fanBottomOrigin;
        
        for (int i = 0; i < 6; i++) {  // 7→6
            float iF = float(i);
            float spreadInPlane = (iF - 2.5) * 0.095;
            float angleInPlane = baseSwingBottom + spreadInPlane;
            
            float worldAngle = 3.14159 + angleInPlane * cosPlaneB;
            float depthAngle = angleInPlane * sinPlaneB;
            
            float2 dir = float2(sin(worldAngle), -cos(worldAngle));
            float beam = laserLineInline(toPB, dir, 0.002);
            float depthFade = (1.0 - abs(depthAngle) * 0.3) * exp(-depthAngle * depthAngle * 2.5);
            
            laserOut += blueColor * (beam * blueMulB * depthFade);
        }
    }
    
    // ====== B. Green Laser Patterns（绿色激光多样式）- 渐入渐出 + DSP 展示 ======
    float greenPhase = fract(time * 0.11);   // 周期略慢，便于看清
    // 触发：mid / high / bass 任一达标即可，易触发
    float greenTrigger = max(max(
        smoothstep(0.04, 0.12, mid),
        smoothstep(0.035, 0.11, high)),
        smoothstep(0.05, 0.16, bass)) * 0.88;
    float greenEnvelope = fadeEnvelope(greenPhase, 0.28, 0.28);
    greenEnvelope *= smoothstep(0.25, 0.65, greenTrigger);
    // DSP 展示：整体亮度随 mid 呼吸，随 bass 有轻微脉冲
    float dspBreath = 0.78 + 0.35 * mid + 0.2 * bass;
    greenEnvelope *= saturate(dspBreath);
    
    if (greenEnvelope > 0.01) {
        float patternSwitch = fract(time * 0.065);  // 5 种样式轮换
        float3 greenColor = uniforms.aiColorLaserFanGreen.rgb;
        if (!colorIsSet(greenColor)) {
            greenColor = float3(0.35, 1.0, 0.45);
        }
        
        if (patternSwitch < 0.2) {
            // Pattern 1: 左右两侧扇形各 3 条（DSP：摆幅受 high 影响）
            float baseSwingGreen = sin(time * 0.3) * (0.5 + high * 0.25);
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
            // Pattern 2: 单条聚光灯从左扫到右（DSP：扫速略随 mid）
            float scanSpeed = 1.2 + mid * 0.4;
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
            // Pattern 4: 中心径向放射 6 条（DSP：旋转 + 扩散受 bass 影响）
            float2 centerOrigin = float2(0.0, 0.0);
            float2 toP = p - centerOrigin;
            float baseAngle = time * 0.2 + bass * 0.5;
            float greenMul = (0.65 + 0.4 * bass) * greenEnvelope;  // 低音越强越亮
            for (int i = 0; i < 6; i++) {
                float angle = baseAngle + float(i) * 1.047;
                float2 dir = float2(sin(angle), cos(angle));
                float beam = laserLineInline(toP, dir, 0.0022);
                laserOut += greenColor * (beam * greenMul);
            }
            
        } else {
            // Pattern 5: 上下双源斜扫（DSP：亮度随 high 脉冲）
            float tilt = time * 0.25 + mid * 0.3;
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
            float pulse = 0.75 + 0.35 * high;
            laserOut += greenColor * ((beamT + beamB) * 0.82 * greenEnvelope * pulse);
        }
    }
    
    // ====== C. 旋转光束（粉色/品红）- 渐显-保持-渐消 ======
    float beamPhase = fract(time / 9.0);
    float beamEnvelope = fadeEnvelope(beamPhase, 0.2, 0.2);
    float beamTrigger = smoothstep(0.04, 0.15, mid);
    beamEnvelope *= beamTrigger;
    
    if (beamEnvelope > 0.01 && dist > 0.01) {
        // 延迟 atan2 到这里（只有需要时才计算）
        float angle = atan2(p.y, p.x);
        float distFade = exp(-dist * 2.0);
        
        float3 rotBeamColor = uniforms.aiColorRotatingBeam.rgb;
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
        float climaxFade = smoothstep(0.12, 0.28, mid);
        if (climaxFade > 0.01) {
            float3 rotExtraColor = uniforms.aiColorRotatingBeamExtra.rgb;
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
        float longBeamTrigger = smoothstep(0.05, 0.18, mid);
        longBeamEnvelope *= longBeamTrigger;
        
        if (longBeamEnvelope > 0.01) {
            float3 coronaColor = uniforms.aiColorCoronaFilaments.rgb;
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
        float coronaTrigger = smoothstep(0.06, 0.2, high);
        coronaEnvelope *= coronaTrigger;
        
        if (coronaEnvelope > 0.01) {
            float3 coronaRadColor = uniforms.aiColorCoronaFilaments.rgb;
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
    float ringTrigger = smoothstep(0.05, 0.15, high);
    ringEnvelope *= ringTrigger;
    
    if (ringEnvelope > 0.01) {
        float3 ringColor = uniforms.aiColorPulseRing.rgb;
        if (!colorIsSet(ringColor)) {
            ringColor = float3(0.8, 0.3, 1.0);
        }
        float ringDist = ringPhase * 0.8;
        float ring = exp(-abs(dist - ringDist) * 25.0);
        laserOut += ringColor * (ring * ringEnvelope * 0.6);
    }
    
    return laserOut;
}

// ============================================================================
// Main Fragment
// ============================================================================

fragment float4 tyndallBeamFragment(VertexOut in [[stage_in]],
                                    constant UniformsAI &uniforms [[buffer(0)]]) {
    float2 uv = in.texCoord;
    float time = uniforms.time.x;
    float aspectRatio = uniforms.resolution.z;
    
    float2 p = (uv - 0.5);
    p.x *= aspectRatio;
    
    // --- 解析 AI 参数 ---
    // aiParams1: (bpm/100, energy, danceability, valence)
    // aiParams2: (animSpeed, brightness, triggerSens, atmoIntensity)
    float aiBpm       = uniforms.aiParams1.x * 100.0;  // 还原为真实 BPM
    float aiEnergy    = uniforms.aiParams1.y;           // 0-1 歌曲能量
    float aiValence   = uniforms.aiParams1.w;           // 0-1 情绪正负
    float aiAnimSpeed = uniforms.aiParams2.x;           // 动画速度倍数
    float aiBright    = uniforms.aiParams2.y;           // 亮度倍数
    float aiTrigSens  = uniforms.aiParams2.z;           // 触发灵敏度倍数
    float aiAtmoInt   = uniforms.aiParams2.w;           // 氛围强度
    
    // 用 aiAnimSpeed 调制所有动画时间（快歌动画更快，慢歌更慢）
    float animTime = time * aiAnimSpeed;
    
    // --- Audio analysis (优化：stride=2 减半循环次数) ---
    float bass = 0.0, mid = 0.0, high = 0.0;
    for (int i = 0; i < 10; i += 2)  bass += uniforms.audioData[i].x;
    bass *= 0.2;
    for (int i = 20; i < 50; i += 2) mid  += uniforms.audioData[i].x;
    mid  /= 15.0;
    for (int i = 50; i < 80; i += 2) high += uniforms.audioData[i].x;
    high /= 15.0;
    
    // AI 触发灵敏度：放大或缩小音频数据的有效范围
    bass *= aiTrigSens;
    mid  *= aiTrigSens;
    high *= aiTrigSens;
    
    float totalEnergy = (bass + mid + high) / 3.0;
    float peakValue = max(max(bass, mid), high);
    float energy = pow(saturate(max(totalEnergy * 1.2, smoothstep(0.08, 0.38, peakValue))), 0.55);
    
    // BPM 驱动的节拍脉冲：仅在音乐播放且能量足够时启用，避免静音时持续闪烁
    float beatPeriod = 60.0 / max(aiBpm, 60.0);  // 每拍时长（秒），限制最低 60 BPM
    float beatPhase = fract(time / beatPeriod);
    float beatPulse = exp(-beatPhase * 5.0);  // 拍头亮，0.2 秒内衰减
    // 全局节拍门限：只有音乐在播放时才有节拍闪烁（totalEnergy > 阈值），否则 beatPulse = 0
    float musicGate = smoothstep(0.02, 0.08, totalEnergy);
    beatPulse *= musicGate;  // 没有音乐时 beatPulse = 0，不会闪烁
    
    float3 finalColor = float3(0.015, 0.012, 0.025);
    
    // 计算 hazeVal 一次，共用于 atmosphere 和 volumetric
    // 烟雾速度也受 animSpeed 影响
    float hazeVal = stageNoise(p * 5.0 + animTime * 0.15) * 0.55
                  + stageNoise(p * 10.0 - animTime * 0.08) * 0.3;
    
    // Layer 0: Atmosphere (always on)
    // AI 氛围强度 + 节拍呼吸
    float atmoBreath = 1.0 + beatPulse * 0.15 * aiEnergy;  // 高能量歌曲节拍呼吸更明显
    float3 atmo = atmosphereField(uv, bass, hazeVal, uniforms) * aiAtmoInt / 0.45 * atmoBreath;
    finalColor += atmo;
    
    // Layer 1: Volumetric Beams + Edge Light
    float unlock1 = smoothstep(0.02, 0.08, energy);
    if (unlock1 > 0.01) {
        // 体积光亮度受 AI 亮度参数和节拍影响
        float volBright = aiBright * (1.0 + beatPulse * 0.2 * aiEnergy);
        finalColor += volumetricBeamSystem(p, animTime, bass, hazeVal, uniforms) * unlock1 * volBright;
        finalColor += edgeLight(uv, mid, uniforms) * unlock1 * aiBright;
    }
    
    // Layer 2: Top Light Array
    float unlock2 = smoothstep(0.02, 0.08, energy);
    if (unlock2 > 0.01) {
        // 灯阵扫描速度受 animSpeed 影响（已通过 animTime 传入）
        float3 topLight = topLightArray(p, animTime, mid, uniforms) * unlock2 * aiBright;
        // 节拍脉冲给灯阵一个微妙的闪烁增强
        topLight *= (1.0 + beatPulse * 0.25 * aiEnergy);
        finalColor += topLight;
    }
    
    // Layer 3: Laser System
    float unlock3 = smoothstep(0.03, 0.12, energy);
    if (unlock3 > 0.01) {
        float3 laser = laserSystem(p, animTime, high, mid, bass, uniforms) * unlock3 * aiBright;
        // 激光在拍点处有短促增亮（模拟灯光师卡点）
        laser *= (1.0 + beatPulse * 0.35 * aiEnergy);
        finalColor += laser;
    }
    
    float pLenSq = dot(p, p);
    float vig = 1.0 - 0.2 * pLenSq;
    finalColor *= max(vig, 0.0);
    
    return float4(finalColor, 1.0);
}
