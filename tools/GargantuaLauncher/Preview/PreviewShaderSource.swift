import Foundation

/// Metal source for the interactive progressive black-hole preview.
///
/// Compiled at runtime (`device.makeLibrary(source:options:)`) so the launcher
/// app needs no `.metal` build rule. The physics is a reduced-cost
/// reimplementation of the offline pipeline's model:
///
///   * Schwarzschild null geodesics integrated with RK4 in Cartesian
///     coordinates (units M = 1, rs = 2): a = -3 M h^2 * r / |r|^5.
///   * Kerr is approximated by shifting the ISCO/horizon and adding a modest
///     Lense-Thirring frame-dragging term — enough to show photon-ring and
///     Doppler asymmetry in a preview, not a full Kerr geodesic solver.
///   * A thin equatorial accretion disk with a Novikov-Thorne-like temperature
///     profile, relativistic Doppler beaming and gravitational redshift.
///   * A procedural background star field so lensing is visible while orbiting.
///
/// Progressive refinement comes from per-frame sub-pixel jitter accumulated
/// into a float buffer; the image starts noisy and converges when idle.
enum PreviewShaderSource {
    static let metal = """
#include <metal_stdlib>
using namespace metal;

struct Uniforms {
    float4 camPos;
    float4 camForward;
    float4 camRight;
    float4 camUp;
    float4 resFov;   // x=resX, y=resY, z=tanHalfFov, w=aspect
    float4 disk0;    // x=spin, y=inner, z=outer, w=thickness
    float4 disk1;    // x=brightness, y=density, z=bgStars, w=stepScale
    float4 disk2;    // x=escapeR, y=horizon, z=photonR, w=tempScale
    float4 disk3;    // x=turbulence, y=noiseScale, z=spiralArms, w=spiralStrength
    uint4  u0;       // x=sampleIndex, y=frameSeed, z=maxSteps, w=metric
    uint4  u1;       // x=samplesPerFrame, y=flags, z=reserved, w=reserved
};

struct PresentParams {
    float exposure;
    float gamma;
    uint  toneMode;
    float saturation;
};

// ---------- hashing / RNG ----------------------------------------------------

inline uint hashU(uint x) {
    x ^= x >> 16;
    x *= 0x7feb352dU;
    x ^= x >> 15;
    x *= 0x846ca68bU;
    x ^= x >> 16;
    return x;
}

inline float rnd(thread uint& s) {
    s = hashU(s);
    return float(s) * (1.0 / 4294967296.0);
}

// ---------- color helpers ----------------------------------------------------

// Tanner Helland style color-temperature -> linear-ish RGB approximation.
inline float3 colorTempToRGB(float kelvin) {
    float t = clamp(kelvin, 1000.0, 40000.0) / 100.0;
    float3 c;
    if (t <= 66.0) {
        c.r = 1.0;
        c.g = clamp(0.3900815788 * log(max(t, 1.0)) - 0.6318414438, 0.0, 1.0);
    } else {
        float tt = t - 60.0;
        c.r = clamp(1.2929361861 * pow(tt, -0.1332047592), 0.0, 1.0);
        c.g = clamp(1.1298908609 * pow(tt, -0.0755148492), 0.0, 1.0);
    }
    if (t >= 66.0) {
        c.b = 1.0;
    } else if (t <= 19.0) {
        c.b = 0.0;
    } else {
        c.b = clamp(0.5432067891 * log(max(t - 10.0, 1.0)) - 1.1962540891, 0.0, 1.0);
    }
    return c;
}

// ---------- background star field -------------------------------------------

inline float3 starfield(float3 dir) {
    float3 d = normalize(dir);
    float u = atan2(d.y, d.x) * 0.1591549431 + 0.5; // [0,1)
    float v = acos(clamp(d.z, -1.0, 1.0)) * 0.3183098862; // [0,1]
    float2 uv = float2(u, v) * float2(620.0, 310.0);
    float2 cell = floor(uv);
    float2 f = fract(uv);
    float h = fract(sin(dot(cell, float2(127.1, 311.7))) * 43758.5453);
    // One soft, round star per occupied cell at a hashed sub-cell position, so
    // the field reads as random points rather than a regular grid. Soft + dim
    // stars avoid the sharp high-frequency content that gravitational lensing
    // turns into ring / moire (diffraction-like) fringes in the preview.
    float2 starPos = float2(fract(h * 57.0), fract(h * 191.0));
    float dist2 = dot(f - starPos, f - starPos);
    float star = smoothstep(0.0016, 0.0, dist2) * step(0.986, h);
    float3 starColor = mix(float3(0.72, 0.81, 1.0), float3(1.0, 0.93, 0.82), fract(h * 13.0));
    float3 col = starColor * star * 0.9;
    // Flat, very faint cool tint (no directional gradient to alias).
    col += float3(0.006, 0.008, 0.014);
    return col;
}

// ---------- geodesic integration --------------------------------------------

// Central Schwarzschild acceleration (M = 1, rs = 2): a = -3 h^2 r / |r|^5.
inline float3 accel(float3 p, float h2) {
    float r2 = dot(p, p);
    float r = sqrt(r2);
    float invR5 = 1.0 / (r2 * r2 * r + 1e-6);
    return -3.0 * h2 * p * invR5;
}

inline void rk4Step(thread float3& p, thread float3& v, float h, float h2) {
    float3 k1p = v;                float3 k1v = accel(p, h2);
    float3 k2p = v + 0.5 * h * k1v; float3 k2v = accel(p + 0.5 * h * k1p, h2);
    float3 k3p = v + 0.5 * h * k2v; float3 k3v = accel(p + 0.5 * h * k2p, h2);
    float3 k4p = v + h * k3v;        float3 k4v = accel(p + h * k3p, h2);
    p += (h / 6.0) * (k1p + 2.0 * k2p + 2.0 * k3p + k4p);
    v += (h / 6.0) * (k1v + 2.0 * k2v + 2.0 * k3v + k4v);
}

// ---------- disk surface texture --------------------------------------------

inline float vnoise(float2 p) {
    float2 i = floor(p);
    float2 f = fract(p);
    f = f * f * (3.0 - 2.0 * f);
    float a = fract(sin(dot(i + float2(0.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
    float b = fract(sin(dot(i + float2(1.0, 0.0), float2(127.1, 311.7))) * 43758.5453);
    float c = fract(sin(dot(i + float2(0.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
    float d = fract(sin(dot(i + float2(1.0, 1.0), float2(127.1, 311.7))) * 43758.5453);
    return mix(mix(a, b, f.x), mix(c, d, f.x), f.y);
}

inline float fbm(float2 p) {
    float v = 0.0;
    float amp = 0.5;
    for (int i = 0; i < 3; i++) {
        v += amp * vnoise(p);
        p *= 2.03;
        amp *= 0.5;
    }
    return v;
}

// Source-model-driven surface texture (turbulence + optional spiral banding),
// evaluated in disk-surface coordinates so it stays stable as the camera moves.
inline float diskTexture(float3 hit, float rHit, constant Uniforms& u) {
    float turbulence = u.disk3.x;
    float noiseScale = u.disk3.y;
    float spiralArms = u.disk3.z;
    float spiralStrength = u.disk3.w;

    float ang = atan2(hit.y, hit.x);
    float lr = log(max(rHit, 1.0));

    float n = fbm(float2(ang * (1.5 + noiseScale) + rHit * 0.18, lr * (2.0 + noiseScale)));
    float tex = mix(1.0, 0.55 + 0.9 * n, clamp(turbulence, 0.0, 1.0));

    if (spiralStrength > 0.0 && spiralArms > 0.0) {
        float s = 0.5 + 0.5 * sin(ang * spiralArms + lr * spiralArms * 1.6);
        tex *= mix(1.0, 0.6 + 0.8 * s, clamp(spiralStrength, 0.0, 1.0));
    }
    return max(tex, 0.0);
}

// Emission from a thin equatorial disk crossing at world point `hit`.
inline float3 diskEmission(float3 hit, float3 rayDir, float rHit, constant Uniforms& u) {
    const float rs = 2.0;
    float spin = u.disk0.x;
    float inner = u.disk0.y;
    float outer = u.disk0.z;
    float3 axis = float3(0.0, 0.0, 1.0);

    // Prograde Keplerian orbital velocity (M = 1), capped sub-luminal.
    float3 phiHat = normalize(cross(axis, hit));
    float sgn = (spin >= 0.0) ? 1.0 : -1.0;
    float speed = clamp(1.0 / sqrt(max(rHit, 1.0)), 0.0, 0.92);
    float3 beta = sgn * speed * phiHat;
    float b2 = clamp(dot(beta, beta), 0.0, 0.985);
    float gamma = 1.0 / sqrt(1.0 - b2);

    // Direction from emitter toward observer.
    float3 n = normalize(-rayDir);
    float doppler = 1.0 / (gamma * (1.0 - dot(beta, n)));
    float gGrav = sqrt(max(1.0 - rs / rHit, 1e-3));
    float g = doppler * gGrav;

    // Novikov-Thorne-like radial profile (relative units).
    float x = clamp(inner / max(rHit, inner), 0.0, 1.0);
    float profile = pow(x, 0.75) * pow(max(1.0 - sqrt(x), 0.0), 0.25);
    float tLocal = u.disk2.w * pow(x, 0.6);
    float tObs = clamp(tLocal * g, 700.0, 42000.0);
    float3 color = colorTempToRGB(tObs);

    // Relativistic beaming (bolometric ~ g^4), clamped to keep preview stable.
    float beaming = clamp(pow(g, 4.0), 0.02, 24.0);
    float edge = smoothstep(outer, outer * 0.72, rHit);
    // Fade the surface texture toward smooth at grazing / strongly foreshortened
    // views (ray nearly in the disk plane). There the texture's screen-space
    // frequency outruns the sample rate and aliases into diffraction-like
    // fringes; lensed images are seen through such grazing geometry too.
    float facing = abs(dot(normalize(rayDir), float3(0.0, 0.0, 1.0)));
    float texStrength = smoothstep(0.05, 0.34, facing);
    float texture = mix(1.0, diskTexture(hit, rHit, u), texStrength);
    float brightness = profile * beaming * edge * u.disk1.x * texture;
    return color * brightness;
}

// Trace one primary ray and return observed radiance.
inline float3 traceRay(float3 pos, float3 dir, constant Uniforms& u) {
    float escapeR = u.disk2.x;
    float horizon = u.disk2.y;
    float spin = u.disk0.x;
    float inner = u.disk0.y;
    float outer = u.disk0.z;
    uint metric = u.u0.w;
    uint maxSteps = u.u0.z;
    float3 axis = float3(0.0, 0.0, 1.0);

    float h2 = dot(cross(pos, dir), cross(pos, dir));
    float3 p = pos;
    float3 v = dir;
    float3 radiance = float3(0.0);
    float3 trans = float3(1.0);

    for (uint i = 0; i < maxSteps; i++) {
        float r = length(p);
        if (r < horizon) {
            return radiance; // captured: background blocked, keep disk in front
        }
        if (r > escapeR) {
            radiance += trans * starfield(v) * u.disk1.z;
            return radiance;
        }

        float h = clamp(r * 0.10, 0.02, 1.1) * u.disk1.w;
        float3 pNew = p;
        float3 vNew = v;
        rk4Step(pNew, vNew, h, h2);

        // Kerr frame-dragging approximation (Lense-Thirring ~ 2a/r^3).
        if (metric == 1u && abs(spin) > 1e-4) {
            float rr = max(length(pNew), 1e-3);
            float omega = 2.0 * spin / (rr * rr * rr);
            vNew += cross(axis * omega, pNew) * h * 0.5;
            vNew = normalize(vNew) * length(v);
        }

        // Finite-thickness accretion disk: integrate emission and absorption
        // over the portion of this ray segment inside the disk's vertical
        // extent. Works face-on (quick crossing) and edge-on (long grazing),
        // so a razor-thin plane no longer reads as black when viewed edge-on.
        float3 mid = 0.5 * (p + pNew);
        float rc = length(mid);
        if (rc >= inner && rc <= outer) {
            float halfH = max(u.disk0.w, 0.05) * (0.6 + 0.05 * rc);
            if (abs(mid.z) < halfH) {
                float vert = exp(-2.0 * mid.z * mid.z / (halfH * halfH));
                float pathInBand = min(length(pNew - p), 2.0 * halfH);
                float dens = clamp(u.disk1.y, 0.0, 1.0);
                float a = 1.0 - exp(-dens * vert * pathInBand * 1.6);
                float3 e = diskEmission(mid, normalize(vNew), rc, u);
                radiance += trans * e * a;
                trans *= (1.0 - a);
            }
        }

        p = pNew;
        v = vNew;
        if (trans.r < 0.01 && trans.g < 0.01 && trans.b < 0.01) {
            return radiance;
        }
    }
    return radiance;
}

// ---------- accumulation kernel ---------------------------------------------

kernel void accumulateKernel(texture2d<float, access::read>  prevTex [[texture(0)]],
                             texture2d<float, access::write> outTex  [[texture(1)]],
                             constant Uniforms& u                    [[buffer(0)]],
                             uint2 gid                                [[thread_position_in_grid]]) {
    uint w = outTex.get_width();
    uint h = outTex.get_height();
    if (gid.x >= w || gid.y >= h) { return; }

    float2 res = u.resFov.xy;
    float tanHalf = u.resFov.z;
    float aspect = u.resFov.w;
    uint spf = max(u.u1.x, 1u);

    uint seed = hashU(gid.x * 1973u + gid.y * 9277u + u.u0.y * 26699u + 1u);

    float3 sum = float3(0.0);
    for (uint s = 0; s < spf; s++) {
        float jx = rnd(seed);
        float jy = rnd(seed);
        float2 uv = (float2(gid) + float2(jx, jy)) / res;
        float2 ndc = uv * 2.0 - 1.0;
        ndc.y = -ndc.y;
        float3 dir = normalize(u.camForward.xyz
            + tanHalf * (ndc.x * aspect * u.camRight.xyz + ndc.y * u.camUp.xyz));
        // clamp sanitizes any NaN -> 0 / Inf -> ceiling and tames fireflies so a
        // single pathological sample can never poison the accumulation buffer.
        sum += clamp(traceRay(u.camPos.xyz, dir, u), 0.0, 256.0);
    }

    float4 prev = (u.u0.x == 0u) ? float4(0.0) : prevTex.read(gid);
    outTex.write(prev + float4(sum, float(spf)), gid);
}

// ---------- present pass -----------------------------------------------------

struct VOut {
    float4 position [[position]];
    float2 uv;
};

vertex VOut presentVert(uint vid [[vertex_id]]) {
    float2 pos[3] = { float2(-1.0, -1.0), float2(3.0, -1.0), float2(-1.0, 3.0) };
    VOut o;
    o.position = float4(pos[vid], 0.0, 1.0);
    float2 uv = pos[vid] * 0.5 + 0.5;
    uv.y = 1.0 - uv.y;
    o.uv = uv;
    return o;
}

inline float3 toneReinhard(float3 c) { return c / (1.0 + c); }

inline float3 toneACES(float3 x) {
    const float a = 2.51, b = 0.03, c = 2.43, d = 0.59, e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

fragment float4 presentFrag(VOut in [[stage_in]],
                            texture2d<float, access::read> accum [[texture(0)]],
                            constant PresentParams& p           [[buffer(0)]]) {
    float2 sz = float2(accum.get_width(), accum.get_height());
    // Bilinear upscale of the low-resolution accumulation buffer. rgba32Float
    // is not hardware-filterable, so fetch four texels and blend manually; this
    // removes the moire / fringe artefacts that nearest-neighbour upscaling left
    // on the photon ring and lensed background.
    float2 fp = clamp(in.uv * sz - 0.5, float2(0.0), sz - 1.0);
    float2 i0 = floor(fp);
    float2 fr = fp - i0;
    uint2 p00 = uint2(i0);
    uint2 p10 = uint2(min(i0 + float2(1.0, 0.0), sz - 1.0));
    uint2 p01 = uint2(min(i0 + float2(0.0, 1.0), sz - 1.0));
    uint2 p11 = uint2(min(i0 + float2(1.0, 1.0), sz - 1.0));
    float4 s = mix(mix(accum.read(p00), accum.read(p10), fr.x),
                   mix(accum.read(p01), accum.read(p11), fr.x), fr.y);
    float3 col = s.rgb / max(s.w, 1.0);
    col *= p.exposure;

    if (p.toneMode == 0u) {
        col = toneReinhard(col);
    } else if (p.toneMode == 1u) {
        col = toneACES(col);
    } else {
        col = clamp(col, 0.0, 1.0);
    }
    // Saturation (reflects the camera look / color grade).
    float luma = dot(col, float3(0.2126, 0.7152, 0.0722));
    col = max(mix(float3(luma), col, p.saturation), 0.0);
    col = pow(max(col, 0.0), float3(1.0 / max(p.gamma, 0.1)));
    return float4(col, 1.0);
}
"""
}
