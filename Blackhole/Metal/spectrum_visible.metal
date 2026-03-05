// Auto-split from integral.metal (Phase 2 refactor).
#if defined(BH_INCLUDE_SPECTRUM_VISIBLE) && (BH_INCLUDE_SPECTRUM_VISIBLE)
struct ComposeParams {
    uint  tileWidth;
    uint  tileHeight;
    uint  downsample;
    uint  outTileWidth;
    uint  outTileHeight;
    uint  srcOffsetX;
    uint  srcOffsetY;
    uint  outOffsetX;
    uint  outOffsetY;
    uint  fullInputWidth;
    uint  fullInputHeight;
    float exposure;
    float dither;
    float innerEdgeMult;
    float spectralStep;
    float cloudQ10;
    float cloudInvSpan;
    uint  look;
    uint  spectralEncoding;
    uint  precisionMode;
    uint  analysisMode;
    uint  cloudBins;
    uint  lumBins;
    float lumLogMin;
    float lumLogMax;
    uint  cameraModel; // 0=legacy, 1=scientific, 2=cinematic
    float cameraPsfSigmaPx;
    float cameraReadNoise;
    float cameraShotNoise;
    float cameraFlareStrength;
    uint  backgroundMode; // 0=off, 1=stars
    float backgroundStarDensity;
    float backgroundStarStrength;
    float backgroundNebulaStrength;
    uint  preserveHighlightColor; // 1=reduce highlight desaturation to keep visible chroma
};

constant ushort BAYER8_LUT[64] = {
     0,48,12,60, 3,51,15,63,
    32,16,44,28,35,19,47,31,
     8,56, 4,52,11,59, 7,55,
    40,24,36,20,43,27,39,23,
     2,50,14,62, 1,49,13,61,
    34,18,46,30,33,17,45,29,
    10,58, 6,54, 9,57, 5,53,
    42,26,38,22,41,25,37,21
};

static inline float3 comp_xyz_to_rgb(float3 xyz) {
    float3 r;
    r.x =  3.2406 * xyz.x + -1.5372 * xyz.y + -0.4986 * xyz.z;
    r.y = -0.9689 * xyz.x +  1.8758 * xyz.y +  0.0415 * xyz.z;
    r.z =  0.0557 * xyz.x + -0.2040 * xyz.y +  1.0570 * xyz.z;
    return max(r, 0.0);
}


static inline float comp_aces(float x) {
    const float a = 2.51;
    const float b = 0.03;
    const float c = 2.43;
    const float d = 0.59;
    const float e = 0.14;
    return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
}

static inline float comp_agx_like(float x) {
    float xb = min(max(x, 0.0), 1e12);
    float logv = log2(1.0 + xb);
    if (!isfinite(logv)) return 1.0;
    float t = logv / max(1.0 + logv, 1e-6);
    // smooth shoulder in display domain
    return clamp(t * t * (3.0 - 2.0 * t), 0.0, 1.0);
}

static inline float comp_hdr_like(float x) {
    float xb = min(max(x, 0.0), 1e12);
    // Slightly wider shoulder than ACES to preserve highlight color separation.
    const float a = 2.00;
    const float b = 0.020;
    const float c = 1.80;
    const float d = 0.240;
    const float e = 0.020;
    float y = (xb * (a * xb + b)) / max(xb * (c * xb + d) + e, 1e-8);
    y = clamp(y, 0.0, 1.0);
    // Keep mid-high contrast gentle while retaining brightness.
    return clamp(precise::pow(y, 0.92), 0.0, 1.0);
}

static inline float comp_tonemap_luma(float x, uint look) {
    if (look == 5u) return comp_hdr_like(x); // --look hdr
    if (look == 3u) return comp_agx_like(x); // --look agx
    if (look == 4u) return clamp(x, 0.0, 1.0); // --look none
    return comp_aces(x); // default
}

static inline float3 comp_apply_look(float3 rgb, uint look) {
    if (look == 1u) { // interstellar
        float3 out;
        out.x = 1.08 * rgb.x + 0.03 * rgb.y - 0.03 * rgb.z;
        out.y = 0.02 * rgb.x + 1.02 * rgb.y - 0.01 * rgb.z;
        out.z = -0.03 * rgb.x + 0.00 * rgb.y + 0.90 * rgb.z;
        out = clamp(out, 0.0, 1.0);
        out = precise::pow(out, float3(0.95));
        return clamp(out, 0.0, 1.0);
    }
    if (look == 2u) { // eht
        float3 out;
        out.x = 1.30 * rgb.x + 0.22 * rgb.y - 0.02 * rgb.z;
        out.y = 0.18 * rgb.x + 1.03 * rgb.y - 0.07 * rgb.z;
        out.z = -0.06 * rgb.x + 0.02 * rgb.y + 0.52 * rgb.z;
        out = clamp(out, 0.0, 1.0);
        float y = dot(out, float3(0.2126, 0.7152, 0.0722));
        out = 0.75 * out + 0.25 * float3(y);
        out = precise::pow(out, float3(1.05));
        return clamp(out, 0.0, 1.0);
    }
    if (look == 5u) { // hdr
        float y = dot(rgb, float3(0.2126, 0.7152, 0.0722));
        float satBoost = 1.18 + 0.10 * smoothstep(0.05, 0.55, y) - 0.08 * smoothstep(0.82, 1.0, y);
        float3 out = mix(float3(y), rgb, satBoost);
        // Mild warm-cool separation for richer perceptual depth.
        out.x *= 1.03;
        out.z *= 0.98;
        out = clamp(out, 0.0, 1.0);
        out = precise::pow(out, float3(0.97));
        return clamp(out, 0.0, 1.0);
    }
    return clamp(rgb, 0.0, 1.0);
}

static inline void comp_cie_xyz_bar(float lam, thread float& x_bar, thread float& y_bar, thread float& z_bar) {
    float t1 = (lam - 442.0) * ((lam < 442.0) ? 0.0624 : 0.0374);
    float t2 = (lam - 599.8) * ((lam < 599.8) ? 0.0264 : 0.0323);
    float t3 = (lam - 501.1) * ((lam < 501.1) ? 0.0490 : 0.0382);
    x_bar = 0.362 * precise::exp(-0.5 * t1 * t1) + 1.056 * precise::exp(-0.5 * t2 * t2) - 0.065 * precise::exp(-0.5 * t3 * t3);

    t1 = (lam - 568.8) * ((lam < 568.8) ? 0.0213 : 0.0247);
    t2 = (lam - 530.9) * ((lam < 530.9) ? 0.0613 : 0.0322);
    y_bar = 0.821 * precise::exp(-0.5 * t1 * t1) + 0.286 * precise::exp(-0.5 * t2 * t2);

    t1 = (lam - 437.0) * ((lam < 437.0) ? 0.0845 : 0.0278);
    t2 = (lam - 459.0) * ((lam < 459.0) ? 0.0385 : 0.0725);
    z_bar = 1.217 * precise::exp(-0.5 * t1 * t1) + 0.681 * precise::exp(-0.5 * t2 * t2);

    x_bar = max(x_bar, 0.0);
    y_bar = max(y_bar, 0.0);
    z_bar = max(z_bar, 0.0);
}


static inline float comp_planck_lambda(float lam_m, float T) {
    const float C1 = 1.1910429e-16;
    const float C2 = 1.4387769e-2;
    float x = C2 / max(lam_m * T, 1e-30);
    x = clamp(x, 1e-8, 700.0);
    if (x > 80.0) {
        // For large x, exp(x) is enormous and radiance is effectively zero.
        return 0.0;
    }
    float denom = max(precise::exp(x) - 1.0, 1e-20);
    return C1 / (pow(lam_m, 5.0) * denom);
}

static inline float comp_planck_nu(float nu_hz, float T, constant Params& P) {
    const float H = 6.62607015e-34;
    float x = (H * nu_hz) / max(P.k * T, 1e-30);
    x = clamp(x, 1e-8, 700.0);
    if (x > 80.0) {
        return 0.0;
    }
    float denom = max(precise::exp(x) - 1.0, 1e-20);
    float num = 2.0 * H * nu_hz * nu_hz * nu_hz / max(P.c * P.c, 1e-30);
    return num / denom;
}

static inline float comp_visible_iNu_emit(float nuEm, float te, constant Params& P) {
    if (P.visibleEmissionModel == 1u) {
        // Synchrotron-inspired power-law spectrum:
        // I_nu ~ nu^{-alpha}, anchored to thermal scale at a visible pivot.
        float alpha = clamp(P.visibleEmissionAlpha, 0.0, 4.0);
        float nuPivot = 5.0e14;
        float pivot = comp_planck_nu(nuPivot, te, P);
        float ratio = max(nuEm / nuPivot, 1e-8);
        return pivot * pow(ratio, -alpha);
    }
    return comp_planck_nu(nuEm, te, P);
}

// Visible-spectrum integration using invariant I_nu / nu^3 transport:
// nu_em = nu_obs / g, I_nu_obs = g^3 I_nu_em(nu_em).
static inline void comp_visible_xyz_from_spectrum(float T_emit,
                                                  float g_total,
                                                  constant Params& P,
                                                  thread float& X,
                                                  thread float& Y,
                                                  thread float& Z,
                                                  thread float& yLum,
                                                  thread float& peakLamNm)
{
    X = 0.0;
    Y = 0.0;
    Z = 0.0;
    yLum = 0.0;
    peakLamNm = 380.0;

    float g = clamp(g_total, 1e-4, 1e4);
    float te = max(T_emit, 1.0);
    uint n = clamp(P.visibleSamples, 8u, 128u);
    float lamMin = 380.0;
    float lamMax = 780.0;
    float dLamNm = (n > 1u) ? ((lamMax - lamMin) / float(n - 1u)) : 0.0;
    float dLamM = dLamNm * 1e-9;
    float g3 = g * g * g;
    float peakIlam = 0.0;

    for (uint i = 0u; i < 128u; ++i) {
        if (i >= n) break;
        float lamNm = lamMin + dLamNm * float(i);
        float lamM = lamNm * 1e-9;
        float nuObs = P.c / max(lamM, 1e-30);
        float nuEm = nuObs / max(g, 1e-8);
        float iNuEm = comp_visible_iNu_emit(nuEm, te, P);
        float iNuObs = g3 * iNuEm;
        float iLamObs = iNuObs * P.c / max(lamM * lamM, 1e-30);

        float xBar, yBar, zBar;
        comp_cie_xyz_bar(lamNm, xBar, yBar, zBar);
        X += iLamObs * xBar * dLamM;
        Y += iLamObs * yBar * dLamM;
        Z += iLamObs * zBar * dLamM;
        yLum += iLamObs * dLamM;
        if (iLamObs > peakIlam) {
            peakIlam = iLamObs;
            peakLamNm = lamNm;
        }
    }
}


static inline float comp_synthetic_noise(float3 v_disk, constant Params& P) {
    float2 vxy = v_disk.xy;
    float speed = length(vxy);
    float r_emit = (P.G * P.M) / max(speed * speed, 1e-30);
    float u = clamp((r_emit - P.rs) / max(P.re - P.rs, 1e-12), 0.0, 1.0);
    float phi = atan2(-vxy.x, vxy.y);
    float theta = phi + 1.9 * log(max(r_emit / max(P.rs, 1e-6), 1.0));
    float cloud = 0.65 * sin(18.0 * u + 3.0 * cos(theta)) + 0.35 * cos(11.0 * theta);
    return clamp(cloud, -1.0, 1.0);
}

static inline float comp_cloud_raw(const CollisionInfo rec, constant Params& P, constant ComposeParams& C) {
    float n = rec.noise;
    if (abs(n) < 1e-6 && C.spectralEncoding == 0u) {
        n = comp_synthetic_noise(rec.v_disk.xyz, P);
    }
    n = clamp(n, -1.0, 1.0);
    float raw = (n < -1e-6) ? clamp(0.5 + 0.5 * n, 0.0, 1.0) : clamp(n, 0.0, 1.0);
    if (P.diskNoiseModel == 1u) {
        // Keep perlin disk soft by compressing cloud contrast before histogram normalization.
        raw = 0.5 + (raw - 0.5) * 0.46;
        raw = smoothstep(0.10, 0.90, raw);
        raw = 0.5 + (raw - 0.5) * 0.55;
    }
    return raw;
}

static inline float comp_cloud_norm_from_raw(float cloudRaw, constant ComposeParams& C) {
    float cloud = clamp((cloudRaw - C.cloudQ10) * C.cloudInvSpan, 0.0, 1.0);
    return 0.18 + 0.82 * cloud;
}

static inline float3 comp_apply_cloud_to_rgb(float3 rgb, float cloudNorm) {
    float core = precise::pow(cloudNorm, 1.15);
    float clump = precise::pow(core, 2.2);
    float vvoid = precise::pow(1.0 - cloudNorm, 1.8);
    float density = 0.62 + 1.28 * core;
    rgb *= density;
    rgb *= (1.0 + 0.34 * clump);
    rgb *= (1.0 - 0.14 * vvoid);
    rgb.x *= (1.0 + 0.12 * clump);
    rgb.z *= (1.0 - 0.08 * clump);
    return rgb;
}

static inline float comp_hash13(float3 p) {
    float h = sin(dot(p, float3(12.9898, 78.233, 37.719)));
    return fract(h * 43758.5453);
}

static inline float comp_limb_factor(float mu, constant Params& P) {
    float m = clamp(mu, 0.0, 1.0);
    if (FC_PHYSICS_MODE == 2u) {
        // Scattering-dominated atmosphere (Chandrasekhar H-function linearized form).
        return (3.0 / 7.0) * (1.0 + 2.0 * m);
    }
    return 0.4 + 0.6 * m;
}
#endif
