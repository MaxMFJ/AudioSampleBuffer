// Direct3D 11 wallpaper pixel shader.  The constant buffer is deliberately
// flat so a native caller can fill it without mirroring any Swift/Metal types.
// effectIndex: 0 cellular membrane, 1 Tyndall stage, 2 cover dots, 3 hex grid.

cbuffer WallpaperConstants : register(b0)
{
    float time;
    float low;
    float mid;
    float high;
    float guitar;
    float piano;
    float drums;
    float aspect;
    uint effectIndex;
    float hasArtwork;
    float2 _padding;
    float4 bands[32];
};

Texture2D artwork : register(t0);
SamplerState artworkSampler : register(s0);

struct VSOut { float4 position : SV_Position; float2 uv : TEXCOORD0; };

VSOut wallpaperVS(uint vertexID : SV_VertexID)
{
    float2 p[3] = { float2(-1, -1), float2(3, -1), float2(-1, 3) };
    VSOut o;
    o.position = float4(p[vertexID], 0, 1);
    o.uv = p[vertexID] * 0.5 + 0.5;
    return o;
}

float hash21(float2 p)
{
    return frac(sin(dot(p, float2(127.1, 311.7))) * 43758.5453);
}

float bandAt(float x)
{
    uint index = (uint)clamp(x, 0.0, 127.0);
    return bands[index >> 2][index & 3];
}

float3 cellular(float2 uv)
{
    float2 p = (uv - 0.5) * float2(max(aspect, 0.65), 1.0);
    float r = length(p), a = atan2(p.y, p.x), tau = 6.2831853;
    float bass = saturate(low), beat = saturate(drums);
    float core = 0.285 + bass * 0.022 + beat * 0.014;
    float wallRadius = r - core - 0.012 * sin(a * 3 + time * .14);
    float wall = smoothstep(0.0, .028, wallRadius);
    float depth = -log(max(wallRadius, .003)) * 2.15;
    float2 q = float2(a / tau * 19 + depth * .52 + time * .085,
                      depth * .70 + time * .31);
    // Four-neighbour jittered Voronoi, matching CellularHive's moving pore
    // centres, twist and anisotropic stretch in its tunnel coordinates.
    float2 baseCell = floor(q - .5), local = q;
    float pore = 10.0, poreSignal = 0.0, poreSeed = 0.0;
    [unroll] for (int yy = 0; yy <= 1; ++yy) [unroll] for (int xx = 0; xx <= 1; ++xx) {
        float2 id = baseCell + float2(xx, yy);
        float seed = hash21(id), jitter = hash21(id + 19.3);
        float signal = saturate((low * .30 + mid * .24 + high * .20 + beat * .16 + guitar * .28) * (.65 + seed * .7));
        float phase = time * (.46 + seed * .34) + seed * tau;
        float2 centre = id + .5 + (float2(seed, jitter) - .5) * .22;
        centre += signal * float2(sin(phase), cos(phase * .83)) * .12;
        float2 d = q - centre;
        float twist = (seed - .5) * .42 + sin(phase) * signal * .95;
        float cs = cos(twist), sn = sin(twist);
        d = float2(cs * d.x - sn * d.y, sn * d.x + cs * d.y);
        d += signal * .12 * float2(sin(d.y * 5 + phase), cos(d.x * 4 - phase));
        d.x += ((seed - .5) * .62 + signal * sin(phase * 1.17) * .58) * d.y;
        float radius = clamp(.31 + frac(jitter * 17) * .07 + signal * .15 + beat * .02, .30, .48);
        float2 stretch = float2(1 + signal * sin(phase) * .25, .88 + seed * .18 - signal * cos(phase) * .20);
        float candidate = length(d * stretch) - radius;
        if (candidate < pore) { pore = candidate; poreSignal = signal; poreSeed = seed; }
    }
    float membrane = smoothstep(-.01, .01, pore);
    float lip = exp(-abs(pore) * 32.0);
    float ridge = .68 + .32 * sin(depth * 2.5 - time * .35 + a * 2);
    float3 theme = float3(.10, .56, .72);
    float3 accent = float3(.35, .80, 1.0);
    float3 c = float3(.001, .003, .012) + wall * membrane * theme * (.34 + ridge * .42 + bass * .20);
    c += wall * lip * accent * (.12 + poreSignal * .60 + beat * .24 + guitar * .16);
    c += exp(-abs(r - core) * 22) * pow(.5 + .5 * cos(a * 38 + time * .4), 30) * accent * (high * .42 + beat * .62);
    float ringPhase = frac(time * .24), ringRadius = core + ringPhase * .48;
    c += exp(-pow((r - ringRadius) / (.01 + beat * .008), 2)) * float3(.7, .9, 1) * (.08 + beat * .72) * (1 - ringPhase);
    float2 dust = frac(p * 105 + float2(time * .0008, -time * .0005)) - .5;
    c += (1 - wall) * exp(-dot(dust, dust) * 160) * step(.936, hash21(floor(p * 105))) * (.12 + high * .58);
    float hole = max(1 - wall, wall * (1 - membrane));
    float farStar = exp(-dot(frac(p * 57) - .5, frac(p * 57) - .5) * 95) * step(.965, hash21(floor(p * 57) + 91.2));
    c += hole * (farStar * .42) * float3(.72, .86, 1) * (.12 + high * .58);
    c += wall * membrane * exp(-abs(pore) * 18) * theme * (.04 + high * .12);
    return c;
}

float3 tyndall(float2 uv)
{
    float2 p = (uv - .5) * float2(max(aspect, .65), 1);
    float3 c = float3(.012, .014, .025) * (.7 + .3 * (1 - uv.y));
    float2 center = float2(0, -.14);
    float haze = (.12 + low * .22) * (.55 + .45 * (1 - uv.y));
    c += float3(.08, .06, .10) * haze * (0.65 + .35 * sin(time * .18 + uv.x * 4));
    for (int i = 0; i < 17; ++i) {
        float f = i / 16.0 - .5;
        float x = f * max(aspect, .65) * 1.3 + sin(time * .2) * .04;
        float2 end = float2(x, .84 + bandAt(i * 3) * .08);
        float2 d = p - center;
        // Two fixtures sweep independently from beyond the screen edges.
        float side = (i < 9) ? -1.0 : 1.0;
        float fixtureX = side * (max(aspect, .65) * .5 + .12);
        float fixtureY = .42;
        float sweep = (side < 0 ? 1 : -1) * (.52 + low * .15) + sin(time * (.35 - side * .035) + side * 2.1) * .24;
        float2 axis = normalize(float2(sin(sweep), -cos(sweep)));
        float2 fromFixture = p - float2(fixtureX, fixtureY);
        float along = dot(fromFixture, axis), across = abs(fromFixture.x * axis.y - fromFixture.y * axis.x);
        float width = .025 + bandAt(i * 3) * .10;
        float beam = exp(-across * across / max(width * width, .0001)) * exp(-dot(fromFixture, fromFixture) * .22) * smoothstep(-.05, .2, along);
        c += beam * float3(.15 + .04 * (i % 3), .58, .82) * (.12 + low * .35 + guitar * .25);
    }
    c += exp(-uv.y * uv.y * 69.44) * float3(1, .55, .25) * (.2 + mid * .6);
    return c;
}

float3 coverDots(float2 uv)
{
    float2 coverSize = float2(.68 / max(aspect, .1), .68);
    float2 cuv = (uv - (.5 - coverSize * .5)) / coverSize;
    bool inside = hasArtwork > 0.5 && all(cuv >= 0) && all(cuv <= 1);
    float2 sampleUV = saturate(cuv);
    float3 art = artwork.Sample(artworkSampler, sampleUV).rgb;
    float wave = sin((inside ? cuv.x * 21 : uv.x * 9) + time * 2.4) * cos((inside ? cuv.y * 17 : uv.y * 4) - time * 1.7);
    float beat = saturate(drums) * exp(-pow((length(max(abs(cuv - .5) - .5, 0)) - .08) / .11, 2));
    float grid = 256.0;
    float2 cellUV = frac(uv * float2(grid, grid / max(aspect, .1))) - .5;
    float dotDistance = length(cellUV);
    float dotRadius = .20 + wave * .03 + (inside ? guitar : beat) * .06;
    float dotMask = 1 - smoothstep(dotRadius - fwidth(dotDistance), dotRadius + fwidth(dotDistance), dotDistance);
    float3 field = float3(.048, .060, .086) + beat * float3(.35, .75, 1);
    return dotMask * (inside ? art * (.65 + .18 * wave) : field) + (1 - dotMask) * float3(.002, .004, .01);
}

float3 hexMorph(float2 uv)
{
    float2 g = uv * float2(31, 18), id = floor(g), f = frac(g) - .5;
    if (((uint)id.y & 1) != 0) f.x -= .5;
    float pulse = .5 + .5 * sin(time * .65 + id.x * .23 + id.y * .29);
    float edge = smoothstep(.48, .39, abs(length(f) - .38));
    float b = bandAt(abs(id.x * 5 + id.y * 11));
    return (float3(.16, .43, .92) + float3(.55, .18, .55) * frac(id.x + id.y) * .4) * edge * (.12 + pulse * .12 + b * 1.5);
}

float4 wallpaperPS(VSOut input) : SV_Target
{
    float3 color;
    if (effectIndex == 1) color = tyndall(input.uv);
    else if (effectIndex == 2) color = coverDots(input.uv);
    else if (effectIndex == 3) color = hexMorph(input.uv);
    else color = cellular(input.uv);
    return float4(saturate(color), 1);
}
