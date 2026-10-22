// Metal source for the CRT pass, compiled at runtime (the Command Line Tools
// ship no offline Metal compiler, and this keeps the build SwiftPM-only).
//
// Model of the picture tube:
//  - Barrel warp that keeps the edge midpoints in place: the picture keeps its
//    size, only the corners leave the glass (no shrinking, no black frame).
//  - Electron beam scanlines whose width grows with brightness, normalised so
//    the average brightness is preserved.
//  - Phosphor mask (aperture grille, slot or dot triads) in screen pixels.
//  - Halo (glow), RGB convergence error, vignette, noise and rolling band.
//  - Tube mode: rounded glass, inner edge shadow, specular reflection, and a
//    satin bezel lit by the picture spilling over its lip.
enum CRTShaderSource {
    static let metal = #"""
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float2 viewport;
    float2 rectOrigin;      // the glass (tube)
    float2 rectSize;
    float2 contentOrigin;   // the picture inside it (smaller when letterboxed in the tube)
    float2 contentSize;
    float time;
    float enabled;
    float scanlines;
    float mask;
    float maskType;
    float curvature;
    float glow;
    float vignette;
    float noise;
    float brightness;
    float tube;
    float lines;
    float pixelScale;
    float frame;
};

struct VOut { float4 pos [[position]]; };

vertex VOut crt_vertex(uint vid [[vertex_id]]) {
    float2 p = float2(float((vid << 1) & 2), float(vid & 2));
    VOut o;
    o.pos = float4(p * 2.0 - 1.0, 0.0, 1.0);
    return o;
}

static float3 toLinear(float3 c) { return pow(max(c, 0.0), 2.2); }
static float3 toGamma(float3 c) { return pow(max(c, 0.0), 1.0 / 2.2); }
static float luma(float3 c) { return dot(c, float3(0.2126, 0.7152, 0.0722)); }

static float hash12(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static float sdRoundBox(float2 p, float2 b, float r) {
    float2 q = abs(p) - b + r;
    return length(max(q, 0.0)) + min(max(q.x, q.y), 0.0) - r;
}

// Edge midpoints stay where they are; corners bend outward.
static float2 warp(float2 p, float k) {
    return p * (1.0 + k * float2(p.y * p.y, p.x * p.x));
}

static float3 maskWeights(float2 frag, int type, float strength, float scale) {
    float w = max(1.0, round(scale));
    float3 m = float3(1.0 - strength);
    if (type == 1) {
        float block = 4.0 * w;
        int row = int(floor(frag.y / block));
        float x = frag.x + ((row & 1) != 0 ? 1.5 * w : 0.0);
        m[int(floor(x / w)) % 3] = 1.0;
        float gap = fmod(frag.y, block) < w ? 1.0 - 0.5 * strength : 1.0;
        return m * gap;
    }
    if (type == 2) {
        m[(int(floor(frag.x / w)) + int(floor(frag.y / w))) % 3] = 1.0;
        return m;
    }
    m[int(floor(frag.x / w)) % 3] = 1.0;
    return m;
}

static float3 sampleLinear(texture2d<float> tex, sampler s, float2 uv) {
    return toLinear(tex.sample(s, uv).rgb);
}

/// Tube coordinates → picture coordinates (they differ when the picture is
/// letterboxed inside a wider glass).
static float2 contentUV(constant Uniforms &u, float2 tuv) {
    return (u.rectOrigin + tuv * u.rectSize - u.contentOrigin) / u.contentSize;
}

/// The picture, black outside it (with a soft one-pixel edge).
static float3 sampleContent(texture2d<float> video, sampler s, float2 cuv, float2 px) {
    float2 inside = smoothstep(-px, px, cuv) * (1.0 - smoothstep(1.0 - px, 1.0 + px, cuv));
    return video.sample(s, clamp(cuv, 0.0, 1.0)).rgb * inside.x * inside.y;
}

static float3 screenColor(texture2d<float> video, constant Uniforms &u,
                          float2 frag, float2 p, float2 tuv) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float tube = u.tube;

    float2 cuv = contentUV(u, tuv);
    float2 px = u.pixelScale / u.contentSize;
    float conv = (0.35 + tube * (0.3 + 1.1 * dot(p, p))) * u.pixelScale / u.contentSize.x;
    float3 col = float3(sampleContent(video, smp, cuv + float2(conv, 0.0), px).r,
                        sampleContent(video, smp, cuv, px).g,
                        sampleContent(video, smp, cuv - float2(conv, 0.0), px).b);
    col = toLinear(col);

    if (u.glow > 0.001) {
        float2 o = (4.0 * u.pixelScale) / u.contentSize;
        float3 halo = float3(0.0);
        halo += toLinear(sampleContent(video, smp, cuv + float2( o.x, 0.0), px));
        halo += toLinear(sampleContent(video, smp, cuv + float2(-o.x, 0.0), px));
        halo += toLinear(sampleContent(video, smp, cuv + float2(0.0,  o.y), px));
        halo += toLinear(sampleContent(video, smp, cuv + float2(0.0, -o.y), px));
        halo += toLinear(sampleContent(video, smp, cuv + o * 1.6, px));
        halo += toLinear(sampleContent(video, smp, cuv - o * 1.6, px));
        halo += toLinear(sampleContent(video, smp, cuv + float2(o.x, -o.y) * 1.6, px));
        halo += toLinear(sampleContent(video, smp, cuv + float2(-o.x, o.y) * 1.6, px));
        halo /= 8.0;
        col += halo * u.glow * (0.25 + 0.6 * luma(halo));
    }

    if (u.scanlines > 0.001) {
        float l = saturate(luma(col));
        float f = fract(tuv.y * u.lines) - 0.5;
        float sigma = mix(0.16, 0.4, sqrt(l));
        float beam = exp(-(f * f) / (2.0 * sigma * sigma));
        float scan = min(beam / (sigma * 2.5066), 1.8);
        col *= mix(1.0, scan, u.scanlines);
    }

    if (u.mask > 0.001) {
        float3 m = maskWeights(frag, int(u.maskType), u.mask, u.pixelScale);
        col *= m / (1.0 - u.mask * 0.45);
    }

    if (u.vignette > 0.001) {
        float2 vv = tuv * (1.0 - tuv);
        col *= pow(saturate(vv.x * vv.y * 16.0), 0.35 * u.vignette);
    }

    if (u.noise > 0.001) {
        float grain = hash12(floor(frag / max(1.0, u.pixelScale)) + fract(u.time * 7.13) * 917.0) - 0.5;
        col += grain * u.noise * 0.05;
        col *= 1.0 - u.noise * 0.06 * (0.5 + 0.5 * sin(tuv.y * 5.0 - u.time * 1.4));
        col *= 1.0 - u.noise * 0.02 * hash12(float2(floor(u.time * 30.0), 3.7));
    }

    col = toGamma(col * u.brightness);

    if (tube > 0.5) {
        float2 hp = (p - float2(-0.42, -0.58)) * float2(1.1, 2.3);
        float spec = exp(-dot(hp, hp) * 2.4) * 0.075;
        float sheen = 0.025 * saturate(1.0 - length(p - float2(0.55, 0.65)) * 1.4);
        col += (spec + sheen) * float3(0.9, 0.95, 1.0);
    }
    return col;
}

// MARK: Cabinet ("TV com Gabinete"): a piano-black set around the picture.
//  - Wide pillarbox (4:3 on a wide screen): the whole viewport is the cabinet,
//    with a speaker grille, two knobs and a standby LED in the side panels.
//  - Otherwise (16:9 and wider): a thin lacquered bezel hugging the picture,
//    pure black beyond it.
// Realism comes from one implied room light (upper left): the lacquer carries
// its reflection as soft diagonal streaks, horizontal polishing marks and fine
// grain; the picture itself is mirrored into the gloss around the glass; every
// raised or recessed part gets a contact shadow and a lit edge.

static float3 pianoSurface(float2 frag, float2 vp, float scale, float sdCab, bool outerEdge) {
    float yN = frag.y / vp.y;
    float xN = frag.x / vp.x;
    float3 col = float3(0.015, 0.015, 0.018);
    col += float3(0.011, 0.012, 0.015) * (1.0 - yN);               // sky light from above
    // the room reflected in the lacquer: one wide, one sharp diagonal streak
    float g1 = exp(-pow((xN + yN * 0.6 - 0.55) / 0.18, 2.0));
    float g2 = exp(-pow((xN + yN * 0.6 - 0.95) / 0.045, 2.0));
    col += (g1 * 0.014 + g2 * 0.010) * float3(0.85, 0.9, 1.0);
    // overhead light caught by the glossy lacquer: a soft band fading down from the top
    col += float3(0.020, 0.021, 0.025) * exp(-yN / 0.16);
    // horizontal polishing marks and fine grain against flat banding
    float streak = hash12(float2(floor(frag.x / (90.0 * scale)), floor(frag.y / (1.6 * scale)))) - 0.5;
    col *= 1.0 + streak * 0.045;
    col += (hash12(frag * 0.731) - 0.5) * 0.008;
    // Only a whole visible set (4:3 with side panels) shows its outer edge:
    // corners falling into shadow, then a rim catching the light. In
    // widescreen the window edge already is the edge of the TV.
    if (outerEdge) {
        col *= 1.0 - 0.3 * exp(sdCab / (14.0 * scale));
        col += exp(-pow((sdCab + 1.4 * scale) / (1.1 * scale), 2.0)) * mix(0.085, 0.01, yN);
    }
    return col;
}

/// Light from the picture falling on the lacquer around the tube. A convex
/// tube in a glossy surround does not mirror sharp content, it throws a soft
/// coloured glow; so this is a heavily blurred average of the nearby edge,
/// fading with the distance to the curved glass (sd), never to the flat
/// video rectangle — that is what kept the glow following the 3D tube.
static float3 screenGlow(texture2d<float> video, constant Uniforms &u, float2 tuv,
                         float sd, float minHalf, bool below) {
    constexpr sampler smp(filter::linear, address::clamp_to_edge);
    float d = max(sd, 0.0);
    float reach = minHalf * (below ? 0.09 : 0.06);
    float fall = exp(-d / reach);
    if (fall < 0.01) return float3(0.0);
    // Light comes from the nearby edge of the glass: black bars inside the tube emit none.
    float2 e = clamp(tuv, 0.03, 0.97);
    float2 px = u.pixelScale / u.contentSize;
    float3 acc = float3(0.0);
    // 3×3 wide taps: the glow is so diffuse that 9 samples match 25.
    for (int i = -1; i <= 1; i++) {
        for (int j = -1; j <= 1; j++) {
            float2 t = clamp(e + float2(i, j) * 0.07, 0.0, 1.0);
            acc += sampleContent(video, smp, contentUV(u, t), px);
        }
    }
    acc /= 9.0;
    return acc * acc * 0.3 * fall;                                // squared: only real light carries
}

static float3 grille(float3 col, float2 frag, float2 center, float2 size, float period) {
    float2 rel = frag - center;
    if (any(abs(rel) > size * 0.5)) return col;
    float2 edge = size * 0.5 - abs(rel);
    float fade = saturate(min(edge.x, edge.y) / (size.y * 0.08));
    float f = fract((rel.y + size.y * 0.5) / period);
    // each slot is a recess: dark against its top wall, opening up below
    float slot = smoothstep(0.30, 0.36, f) * (1.0 - smoothstep(0.64, 0.72, f));
    float depth = mix(0.12, 0.45, smoothstep(0.30, 0.72, f));
    col = mix(col, col * depth, slot * fade);
    // the lower lip of each slot catches the light…
    col += float3(0.045, 0.047, 0.052) * exp(-pow((f - 0.78) / 0.035, 2.0)) * fade;
    // …and shades the strip above the next one
    col *= 1.0 - 0.22 * exp(-pow((f - 0.26) / 0.04, 2.0)) * fade;
    return col;
}

static float3 knob(float3 col, float2 frag, float2 c, float r, float scale, float angle) {
    float2 rel = frag - c;
    float d = length(rel);
    float2 L = normalize(float2(-0.45, -0.89));                    // room light, upper left
    // contact shadow pooling under the body
    float sh = length(rel - float2(0.0, r * 0.25));
    col *= 1.0 - 0.45 * (1.0 - smoothstep(r * 0.85, r * 1.55, sh));
    float body = 1.0 - smoothstep(r - scale, r + scale, d);
    if (body <= 0.0) return col;
    float2 rn = rel / max(d, 0.001);
    float nd = d / r;
    float theta = atan2(rel.y, rel.x);
    // gently domed face with a radial brushed finish
    float brush = hash12(float2(floor(theta * 70.0), 7.1)) - 0.5;
    float3 k = float3(0.026, 0.026, 0.030)
             + float3(0.018, 0.019, 0.022) * saturate(dot(rn * nd, L) * 0.5 + 0.5)
             + brush * 0.018 * smoothstep(0.15, 0.6, nd);
    // glossy hotspot where the room light lands
    k += float3(0.9, 0.95, 1.0) * 0.12 * exp(-pow(length(rel / r - float2(-0.30, -0.38)) / 0.26, 2.0));
    // chamfered rim: a bright arc towards the light, faint floor bounce opposite
    float rim = smoothstep(0.74, 0.82, nd);
    float arc = saturate(dot(rn, L));
    float bounce = saturate(dot(rn, -L));
    float3 rimCol = float3(0.012, 0.012, 0.014)
                  + float3(0.95, 0.97, 1.0) * 0.10 * pow(arc, 3.0)
                  + float3(0.05, 0.055, 0.07) * 0.35 * pow(bounce, 2.0);
    k = mix(k, rimCol, rim);
    // recessed pointer groove; the light catches its far wall
    float2 dir = float2(sin(angle), -cos(angle));
    float along = dot(rel, dir) / r;
    float across = (rel.x * dir.y - rel.y * dir.x) / r;
    float inSlot = smoothstep(0.22, 0.28, along) * (1.0 - smoothstep(0.72, 0.8, along));
    float groove = (1.0 - smoothstep(0.035, 0.06, abs(across))) * inSlot;
    k = mix(k, float3(0.006, 0.006, 0.008), groove * 0.9);
    k += float3(0.08, 0.082, 0.088) * exp(-pow((across - 0.07) / 0.025, 2.0)) * inSlot;
    // the silhouette darkens where the side curves away
    k *= 1.0 - 0.5 * smoothstep(0.93, 1.0, nd);
    return mix(col, k, body);
}

static float3 powerLED(float3 col, float2 frag, float2 led, float ledR, float scale) {
    float ld = length(frag - led);
    float core = 1.0 - smoothstep(ledR * 0.7, ledR + scale, ld);
    col = mix(col, float3(0.9, 0.22, 0.12), core);
    col += float3(0.8, 0.18, 0.08) * 0.16 * exp(-pow(ld / (ledR * 2.6), 2.0));
    // its glow smeared down the lacquer
    float2 dl = frag - led;
    if (dl.y > 0.0) {
        col += float3(0.5, 0.1, 0.05) * 0.05 * exp(-pow(dl.x / (ledR * 1.4), 2.0)) * exp(-dl.y / (ledR * 7.0));
    }
    return col;
}

static float3 sidePanels(float3 col, float2 frag, constant Uniforms &u, float scale) {
    float2 vp = u.viewport;
    float h = vp.y;
    float left = u.rectOrigin.x;
    float rightEdge = u.rectOrigin.x + u.rectSize.x;
    float right = vp.x - rightEdge;
    float minPanel = vp.x * 0.07;
    float period = max(4.0 * scale, h * 0.009);
    if (left > minPanel && frag.x < left) {
        col = grille(col, frag, float2(left * 0.5, h * 0.52), float2(left * 0.4, h * 0.46), period);
    }
    if (right > minPanel && frag.x > rightEdge) {
        float cx = rightEdge + right * 0.5;
        float r = min(right * 0.16, h * 0.042);
        col = knob(col, frag, float2(cx, h * 0.3), r, scale, 0.6);
        col = knob(col, frag, float2(cx, h * 0.3 + r * 2.8), r, scale, -1.2);
        col = powerLED(col, frag, float2(cx, h * 0.86), max(1.5 * scale, r * 0.09), scale);
    }
    return col;
}

static float3 cabinetColor(texture2d<float> video, constant Uniforms &u, float2 frag,
                           float sd, float2 tuv, float minHalf) {
    float2 vp = u.viewport;
    float scale = max(u.pixelScale, 1.0);
    // The set always fills the window: one cabinet, one bezel, nothing beyond.
    // 4:3 leaves wide side panels for the grille and knobs; wider pictures
    // get a glass that fills the window inside a thin, even bezel.
    bool panels = u.frame > 1.5;
    // Widescreen: the lacquer runs square into the window corners (no black
    // wedges, no extra outline); the 4:3 set keeps its rounded body.
    // The window (or the screen, in full screen) is the edge of the set: the
    // lacquer runs square into every corner, with no outline of its own.
    float sdCab = sdRoundBox(frag - vp * 0.5, vp * 0.5 + scale * 2.0, 0.0);

    float3 col = pianoSurface(frag, vp, scale, sdCab, false);
    col += screenGlow(video, u, tuv, sd, minHalf, frag.y > u.rectOrigin.y + u.rectSize.y * 0.5);

    // The glass sits in a recess: one soft shadow deepening towards the glass,
    // no separate lines — a single edge (the glass) is all the eye should find.
    float d = max(sd, 0.0);
    float bevelW = max(minHalf * 0.035, 6.0 * scale);
    col *= mix(0.4, 1.0, smoothstep(0.0, bevelW, d));
    // One soft highlight where the recess turns into the face, strongest on the
    // upper edge (it faces the room light) and fading away down the sides.
    float2 c = u.rectOrigin + u.rectSize * 0.5;
    float upper = saturate(0.5 - (frag.y - c.y) / u.rectSize.y);
    float lipD = (d - bevelW) / (2.5 * scale);
    col += float3(0.035, 0.037, 0.042) * exp(-lipD * lipD) * upper * upper;

    if (panels) {
        col = sidePanels(col, frag, u, scale);
    } else {
        // Standby LED in the chin, lower right.
        float chin = vp.y - (u.rectOrigin.y + u.rectSize.y);
        col = powerLED(col, frag, float2(vp.x - chin * 2.2, vp.y - chin * 0.5),
                       max(1.2 * scale, chin * 0.06), scale);
    }
    return col * (1.0 - smoothstep(-scale, scale, sdCab));
}

fragment float4 crt_fragment(VOut in [[stage_in]],
                             texture2d<float> video [[texture(0)]],
                             constant Uniforms &u [[buffer(0)]]) {
    constexpr sampler plain(filter::linear, address::clamp_to_edge);
    float2 frag = in.pos.xy;
    float2 uv = (frag - u.rectOrigin) / u.rectSize;

    if (u.enabled < 0.5) {
        if (any(uv < 0.0) || any(uv > 1.0)) return float4(0.0, 0.0, 0.0, 1.0);
        return float4(video.sample(plain, uv).rgb, 1.0);
    }

    float2 p = uv * 2.0 - 1.0;
    float2 q = warp(p, u.curvature * 0.14);
    float2 tuv = q * 0.5 + 0.5;

    float2 halfPx = u.rectSize * 0.5;
    float minHalf = min(halfPx.x, halfPx.y);
    float radius = u.tube > 0.5 ? minHalf * (0.05 + 0.07 * u.curvature) : 0.0;
    float sd = sdRoundBox(q * halfPx, halfPx, radius);
    float aa = u.pixelScale;
    float inside = 1.0 - smoothstep(-aa, aa, sd);

    float3 screen = float3(0.0);
    if (inside > 0.0) {
        screen = screenColor(video, u, frag, p, tuv);
        if (u.tube > 0.5) {
            float depth = smoothstep(0.0, minHalf * 0.11, -sd);
            screen *= mix(0.3, 1.0, depth);
            float rim = exp(-pow(-sd / (minHalf * 0.01), 2.0)) * 0.1 * saturate(0.6 - p.y * 0.6);
            screen += rim;
        }
    }

    if (u.frame > 0.5) {
        // The cabinet is invisible behind the glass: only shade it where it shows.
        if (inside >= 1.0) return float4(screen, 1.0);
        float3 cab = cabinetColor(video, u, frag, sd, tuv, minHalf);
        return float4(mix(cab, screen, inside), 1.0);
    }

    if (u.tube < 0.5) {
        return float4(screen * inside, 1.0);
    }

    // Bezel: satin plastic around the glass, lit by the picture.
    float d = max(sd, 0.0);
    float3 bezel = float3(0.05, 0.048, 0.046) * (1.05 - 0.3 * saturate(p.y * 0.5 + 0.5));
    float3 spill = (video.sample(plain, clamp(tuv, 0.02, 0.98)).rgb
                  + video.sample(plain, clamp(tuv * 0.9 + 0.05, 0.0, 1.0)).rgb) * 0.5;
    bezel += spill * 0.32 * exp(-d / (minHalf * 0.03));
    float lip = (d - minHalf * 0.014) / (minHalf * 0.006);
    bezel += 0.06 * exp(-lip * lip) * saturate(0.8 - p.y * 0.4);
    bezel *= 1.0 - smoothstep(minHalf * 0.05, minHalf * 0.3, d);
    return float4(mix(bezel, screen, inside), 1.0);
}
"""#
}
