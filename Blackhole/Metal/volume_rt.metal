// Auto-split from integral.metal (Phase 2 refactor).
#if defined(BH_INCLUDE_VOLUME_RT) && (BH_INCLUDE_VOLUME_RT)
struct VolumeAccum {
    float I;
    float3 IVisNu; // observed-frame I_nu at CIE-fit anchors {650nm, 520nm, 425nm}
    float3 QVisNu;
    float3 UVisNu;
    float3 VVisNu;
    float w;
    float temp4;
    float g;
    float r;
    float vr;
    float noise;
    float x;
    float y;
    float z;
    float ox;
    float oy;
    float oz;
    float tau;
    float maxRho;
    float maxB2;
    float maxJ;
    float maxI;
    float maxAlpha;
    float maxSource;
    float maxEpsAbs;
    float maxABase;
    float maxACool;
    float maxJThermal;
    float maxJThermalBody;
    float maxJThin;
    float maxJThermalCloud;
    float maxJThermalCorona;
    float intJThermal;
    float intJThermalBody;
    float intJThin;
    float intJThermalCloud;
    float intJThermalCorona;
    float intJThermalWeighted;
    float intAlphaThermalPre;
    float intAlphaThermalPost;
    float intIThermal;
    float intIThermalBody;
    float intIThin;
    float intIThermalCloud;
    float intIThermalCorona;
    float maxThinWeight;
    float maxCoronaWeight;
    float maxSourceThermal;
    float maxSourceThin;
    float tauOneSource;
    float maxThetae;
    float maxSigmaProxy;
    float maxBetaInvProxy;
    float maxSpeed;
    float maxGamma;
    float tauOneRNorm;
    float tauOnePathRs;
    float pathRs;
    float maxFlowResidual;
    float emissHeight;
    float emissLayer;
    float emissWeight;
    float emissBodyLayerGate;
    float maxBodyProxy;
    float3 tauVis;
    uint  tauSurfaceMask;
    uint  samples;
    uint  invalidSamples;
    uint  surfaceHit;
    uint  visibleSpectrumMode; // 0=three CIE-fit I_nu anchors, 1=9-band CIE quadrature packed to XYZ
};

static inline void volume_accum_init(thread VolumeAccum& A) {
    A.I = 0.0;
    A.IVisNu = float3(0.0);
    A.QVisNu = float3(0.0);
    A.UVisNu = float3(0.0);
    A.VVisNu = float3(0.0);
    A.w = 0.0;
    A.temp4 = 0.0;
    A.g = 0.0;
    A.r = 0.0;
    A.vr = 0.0;
    A.noise = 0.0;
    A.x = 0.0;
    A.y = 0.0;
    A.z = 0.0;
    A.ox = 0.0;
    A.oy = 0.0;
    A.oz = 0.0;
    A.tau = 0.0;
    A.maxRho = 0.0;
    A.maxB2 = 0.0;
    A.maxJ = 0.0;
    A.maxI = 0.0;
    A.maxAlpha = 0.0;
    A.maxSource = 0.0;
    A.maxEpsAbs = 0.0;
    A.maxABase = 0.0;
    A.maxACool = 0.0;
    A.maxJThermal = 0.0;
    A.maxJThermalBody = 0.0;
    A.maxJThin = 0.0;
    A.maxJThermalCloud = 0.0;
    A.maxJThermalCorona = 0.0;
    A.intJThermal = 0.0;
    A.intJThermalBody = 0.0;
    A.intJThin = 0.0;
    A.intJThermalCloud = 0.0;
    A.intJThermalCorona = 0.0;
    A.intJThermalWeighted = 0.0;
    A.intAlphaThermalPre = 0.0;
    A.intAlphaThermalPost = 0.0;
    A.intIThermal = 0.0;
    A.intIThermalBody = 0.0;
    A.intIThin = 0.0;
    A.intIThermalCloud = 0.0;
    A.intIThermalCorona = 0.0;
    A.maxThinWeight = 0.0;
    A.maxCoronaWeight = 0.0;
    A.maxSourceThermal = 0.0;
    A.maxSourceThin = 0.0;
    A.tauOneSource = 0.0;
    A.maxThetae = 0.0;
    A.maxSigmaProxy = 0.0;
    A.maxBetaInvProxy = 0.0;
    A.maxSpeed = 0.0;
    A.maxGamma = 1.0;
    A.tauOneRNorm = 0.0;
    A.tauOnePathRs = 0.0;
    A.pathRs = 0.0;
    A.maxFlowResidual = 0.0;
    A.emissHeight = 0.0;
    A.emissLayer = 0.0;
    A.emissWeight = 0.0;
    A.emissBodyLayerGate = 0.0;
    A.maxBodyProxy = 0.0;
    A.tauVis = float3(0.0);
    A.tauSurfaceMask = 0u;
    A.samples = 0u;
    A.invalidSamples = 0u;
    A.surfaceHit = 0u;
    A.visibleSpectrumMode = 0u;
}

static inline void volume_accum_note_transfer(thread VolumeAccum& A,
                                              float jObs,
                                              float aObs,
                                              float tauBefore,
                                              float dTau,
                                              float r,
                                              float ds,
                                              constant Params& P)
{
    float source = 0.0;
    if (aObs > 1e-30 && isfinite(jObs) && isfinite(aObs)) {
        source = max(jObs / max(aObs, 1e-30), 0.0);
        A.maxSource = max(A.maxSource, source);
    }
    if (A.tauOneRNorm <= 0.0 && tauBefore < 1.0 && tauBefore + dTau >= 1.0) {
        float f = clamp((1.0 - tauBefore) / max(dTau, 1e-12), 0.0, 1.0);
        A.tauOneRNorm = r / max(P.rs, 1e-6);
        A.tauOnePathRs = A.pathRs + f * ds / max(P.rs, 1e-6);
        A.tauOneSource = source;
    }
}

static inline void volume_cie_xyz_bar(float lam, thread float& x_bar, thread float& y_bar, thread float& z_bar) {
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

static inline float volume_visible_band_lambda_nm(uint k) {
    return 380.0 + (float(k) + 0.5) * (400.0 / 9.0);
}

static inline float volume_visible_band_get(thread const VolumeAccum& A, uint k) {
    if (k < 3u) return A.IVisNu[k];
    if (k < 6u) return A.QVisNu[k - 3u];
    return A.UVisNu[k - 6u];
}

static inline void volume_visible_band_set(thread VolumeAccum& A, uint k, float value) {
    if (k < 3u) {
        A.IVisNu[k] = value;
    } else if (k < 6u) {
        A.QVisNu[k - 3u] = value;
    } else {
        A.UVisNu[k - 6u] = value;
    }
}

static inline float3 volume_visible_bands_to_xyz(thread const VolumeAccum& A,
                                                 constant Params& P)
{
    float3 xyz = float3(0.0);
    const float dLamM = (400.0 / 9.0) * 1e-9;
    for (uint k = 0u; k < 9u; ++k) {
        float lamNm = volume_visible_band_lambda_nm(k);
        float lamM = lamNm * 1e-9;
        float iNu = max(volume_visible_band_get(A, k), 0.0);
        float iLam = iNu * P.c / max(lamM * lamM, 1e-30);
        float xBar, yBar, zBar;
        volume_cie_xyz_bar(lamNm, xBar, yBar, zBar);
        xyz += iLam * float3(xBar, yBar, zBar) * dLamM;
    }
    return max(xyz, float3(0.0));
}

static inline float volume_planck_nu(float nuHz, float tempK, constant Params& P) {
    const float H = 6.62607015e-34;
    float x = (H * nuHz) / max(P.k * tempK, 1e-30);
    x = clamp(x, 1e-8, 700.0);
    if (x > 80.0) return 0.0;
    float denom = max(precise::exp(x) - 1.0, 1e-20);
    return (2.0 * H * nuHz * nuHz * nuHz / max(P.c * P.c, 1e-30)) / denom;
}

static inline float3 volume_blackbody_observed_xyz(float tempK,
                                                   float g,
                                                   constant Params& P)
{
    // Current precision-volume bridge uses grey opacity. Under that assumption
    // the wavelength-dependent source function can be integrated directly in XYZ:
    // I_nu,obs = g^3 B_nu(nu_obs / g, T). This avoids storing a full per-band
    // volume state while preserving spectral color better than three RGB anchors.
    float3 xyz = float3(0.0);
    const uint bandCount = 12u;
    const float lamMinNm = 380.0;
    const float lamMaxNm = 750.0;
    const float dLamNm = (lamMaxNm - lamMinNm) / float(bandCount);
    const float dLamM = dLamNm * 1e-9;
    float gSafe = clamp(g, 1e-6, 1e6);
    float g3 = gSafe * gSafe * gSafe;
    for (uint k = 0u; k < bandCount; ++k) {
        float lamNm = lamMinNm + (float(k) + 0.5) * dLamNm;
        float lamM = lamNm * 1e-9;
        float nuObs = P.c / max(lamM, 1e-30);
        float nuEm = max(nuObs / gSafe, 1e3);
        float iNuObs = g3 * volume_planck_nu(nuEm, max(tempK, 1.0), P);
        float iLamObs = iNuObs * P.c / max(lamM * lamM, 1e-30);
        float xBar, yBar, zBar;
        volume_cie_xyz_bar(lamNm, xBar, yBar, zBar);
        xyz += iLamObs * float3(xBar, yBar, zBar) * dLamM;
    }
    return max(xyz, float3(0.0));
}

static inline void volume_accum_add_sample(thread VolumeAccum& A,
                                           float weight,
                                           float tempKelvin,
                                           float g,
                                           float r,
                                           float vr,
                                           float noise,
                                           float3 pos,
                                           float3 obs)
{
    if (!(weight > 0.0)) return;
    A.w += weight;
    A.temp4 += weight * pow(max(tempKelvin, 1.0), 4.0);
    A.g += weight * g;
    A.r += weight * r;
    A.vr += weight * vr;
    A.noise += weight * noise;
    A.x += weight * pos.x;
    A.y += weight * pos.y;
    A.z += weight * pos.z;
    A.ox += weight * obs.x;
    A.oy += weight * obs.y;
    A.oz += weight * obs.z;
    A.samples += 1u;
}

#define BH_INCLUDE_VOLUME_TRANSPORT_LEGACY 1
#include "VolumeTransport/legacy.metal"
#undef BH_INCLUDE_VOLUME_TRANSPORT_LEGACY

#define BH_INCLUDE_VOLUME_TRANSPORT_GRMHD 1
#include "VolumeTransport/grmhd.metal"
#undef BH_INCLUDE_VOLUME_TRANSPORT_GRMHD

static inline float3 disk_sample_probe_pos(float3 hitPos,
                                           float3 segStart,
                                           float3 segEnd,
                                           constant Params& P);
static inline void disk_set_noise_and_bridge(thread CollisionInfo& info,
                                             float3 samplePos,
                                             float ctLen,
                                             constant Params& P,
                                             texture2d<float, access::sample> diskAtlasTex);
static inline void volume_integrate_segment(float3 p0,
                                            float3 p1,
                                            float3 obsDir,
                                            float diskInner,
                                            constant Params& P,
                                            texture3d<float, access::sample> diskVol0Tex,
                                            texture3d<float, access::sample> diskVol1Tex,
                                            thread VolumeAccum& A,
                                            float4 rayV0,
                                            float4 rayV1,
                                            float LzConst,
                                            float pr0,
                                            float pr1);
static inline bool disk_volume_mode_enabled_fc(constant Params& P);
static inline bool trace_commit_volume_hit(thread const VolumeAccum& volumeA,
                                           bool volumeMode,
                                           float diskInner,
                                           float3 volumeObsDir,
                                           float ctLen,
                                           float impactRs,
                                           constant Params& P,
                                           thread CollisionInfo& info);
static inline bool trace_kerr_surface_ray(constant Params& P,
                                          float3 dir,
                                          texture2d<float, access::sample> diskAtlasTex,
                                          thread CollisionInfo& info);
static inline bool trace_kerr_volume_ray(constant Params& P,
                                         float3 dir,
                                         texture3d<float, access::sample> diskVol0Tex,
                                         texture3d<float, access::sample> diskVol1Tex,
                                         thread CollisionInfo& info);

struct SurfaceHitSegment {
    bool entered;
    float tEnter;
    int segment;
};

struct SchwarzschildSurfaceHitState {
    bool valid;
    float4 pHit;
    float4 vHit;
    float3 hitPos;
    float3 segStart;
    float3 segEnd;
    float dxy;
    float phiHit;
};

struct KerrSurfaceHitState {
    bool valid;
    KerrState hitState;
    float3 hitPos;
    float3 segStart;
    float3 segEnd;
    float dxy;
    float r_M;
    float phiHit;
};

static inline SurfaceHitSegment trace_find_surface_hit_segment(float3 world0,
                                                               float3 worldMid,
                                                               float3 worldPos,
                                                               constant Params& P)
{
    float tEnter = 0.0;
    if (segment_enter_disk(world0, worldMid, P, tEnter)) {
        return SurfaceHitSegment{true, tEnter, 0};
    }
    if (segment_enter_disk(worldMid, worldPos, P, tEnter)) {
        return SurfaceHitSegment{true, tEnter, 1};
    }
    if (segment_enter_disk(world0, worldPos, P, tEnter)) {
        return SurfaceHitSegment{true, tEnter, 2};
    }
    return SurfaceHitSegment{false, 0.0, -1};
}

static inline SchwarzschildSurfaceHitState trace_refine_schwarzschild_surface_hit_state(float3 world0,
                                                                                         float3 worldPos,
                                                                                         float3 newX,
                                                                                         float3 newY,
                                                                                         float3 newZ,
                                                                                         float4 pPrev,
                                                                                         float4 vPrev,
                                                                                         float4 p,
                                                                                         float4 v,
                                                                                         float diskEmitMin,
                                                                                         constant Params& P)
{
    SchwarzschildSurfaceHitState result;
    result.valid = false;
    result.pHit = p;
    result.vHit = v;
    result.hitPos = float3(0.0);
    result.segStart = world0;
    result.segEnd = worldPos;
    result.dxy = 0.0;
    result.phiHit = 0.0;

    float4 pMid = pPrev;
    float4 vMid = vPrev;
    rk4_step_h(pMid, vMid, P, 0.5 * P.h);
    float3 localMid = conv(pMid.y, pMid.z, pMid.w);
    float3 worldMid = localMid.x * newX + localMid.y * newY + localMid.z * newZ;
    SurfaceHitSegment hitSeg = trace_find_surface_hit_segment(world0, worldMid, worldPos, P);
    if (!hitSeg.entered) return result;

    if (hitSeg.segment == 0) {
        result.pHit = pPrev;
        result.vHit = vPrev;
        rk4_step_h(result.pHit, result.vHit, P, 0.5 * P.h * clamp(hitSeg.tEnter, 0.0, 1.0));
        result.segEnd = worldMid;
    } else if (hitSeg.segment == 1) {
        result.pHit = pMid;
        result.vHit = vMid;
        rk4_step_h(result.pHit, result.vHit, P, 0.5 * P.h * clamp(hitSeg.tEnter, 0.0, 1.0));
        result.segStart = worldMid;
    } else if (hitSeg.segment == 2) {
        result.pHit = pPrev;
        result.vHit = vPrev;
        rk4_step_h(result.pHit, result.vHit, P, P.h * clamp(hitSeg.tEnter, 0.0, 1.0));
    }

    float3 localHit = conv(result.pHit.y, result.pHit.z, result.pHit.w);
    result.hitPos = localHit.x * newX + localHit.y * newY + localHit.z * newZ;
    result.dxy = length(float2(result.hitPos.x, result.hitPos.y));
    if (!(result.dxy > diskEmitMin && result.dxy < P.re)) return result;

    result.phiHit = atan2(result.hitPos.y, result.hitPos.x);
    result.valid = true;
    return result;
}

static inline KerrSurfaceHitState trace_refine_kerr_surface_hit_state(float3 world0,
                                                                      float3 worldPos,
                                                                      thread const KerrState& prevState,
                                                                      thread const KerrState& state,
                                                                      float hUsed,
                                                                      float a,
                                                                      float Lz,
                                                                      float massLen,
                                                                      float diskEmitMin,
                                                                      constant Params& P)
{
    KerrSurfaceHitState result;
    result.valid = false;
    result.hitState = state;
    result.hitPos = float3(0.0);
    result.segStart = world0;
    result.segEnd = worldPos;
    result.dxy = 0.0;
    result.r_M = 0.0;
    result.phiHit = 0.0;

    KerrState midState;
    float midErr = 0.0;
    float midNull = 0.0;
    float3 midWorld = worldPos;
    kerr_dp45_trial(prevState, 0.5 * hUsed, a, Lz, midState, midErr, midNull);
    if (isfinite(midState.r) && isfinite(midState.theta) && isfinite(midState.phi)) {
        midState.theta = clamp(midState.theta, 1e-4, M_PI - 1e-4);
        midState.phi = fmod(midState.phi, 2.0 * M_PI);
        if (midState.phi < 0.0) midState.phi += 2.0 * M_PI;
        midWorld = conv(max(midState.r, 0.0) * massLen, midState.theta, midState.phi);
    }
    SurfaceHitSegment hitSeg = trace_find_surface_hit_segment(world0, midWorld, worldPos, P);
    if (!hitSeg.entered) return result;

    if (hitSeg.segment == 0) {
        float hitErr = 0.0;
        float hitNull = 0.0;
        result.hitState = prevState;
        kerr_dp45_trial(prevState, 0.5 * hUsed * clamp(hitSeg.tEnter, 0.0, 1.0), a, Lz, result.hitState, hitErr, hitNull);
        result.segEnd = midWorld;
    } else if (hitSeg.segment == 1) {
        float hitErr = 0.0;
        float hitNull = 0.0;
        result.hitState = midState;
        kerr_dp45_trial(midState, 0.5 * hUsed * clamp(hitSeg.tEnter, 0.0, 1.0), a, Lz, result.hitState, hitErr, hitNull);
        result.segStart = midWorld;
    } else if (hitSeg.segment == 2) {
        float hitErr = 0.0;
        float hitNull = 0.0;
        result.hitState = prevState;
        kerr_dp45_trial(prevState, hUsed * clamp(hitSeg.tEnter, 0.0, 1.0), a, Lz, result.hitState, hitErr, hitNull);
    }

    result.hitState.theta = clamp(result.hitState.theta, 1e-4, M_PI - 1e-4);
    result.hitState.phi = fmod(result.hitState.phi, 2.0 * M_PI);
    if (result.hitState.phi < 0.0) result.hitState.phi += 2.0 * M_PI;
    result.hitPos = conv(max(result.hitState.r, 0.0) * massLen, result.hitState.theta, result.hitState.phi);
    result.dxy = length(float2(result.hitPos.x, result.hitPos.y));
    result.r_M = result.dxy / max(massLen, 1e-12);
    float rEmitMinM = diskEmitMin / max(massLen, 1e-12);
    if (!(result.r_M > rEmitMinM && result.dxy < P.re)) return result;

    result.phiHit = atan2(result.hitPos.y, result.hitPos.x);
    result.valid = true;
    return result;
}

static inline void trace_store_schwarzschild_surface_hit(thread CollisionInfo& info,
                                                         thread const SchwarzschildSurfaceHitState& hitState,
                                                         float g_factor,
                                                         float vrRatio,
                                                         float T,
                                                         float3 obsDir,
                                                         float3 world0,
                                                         float3 worldPos,
                                                         constant Params& P,
                                                         texture2d<float, access::sample> diskAtlasTex)
{
    float ctLen = P.c * hitState.pHit.x;
    info.hit = 1;
    info.ct  = ctLen;
    info.T   = T;
    info.v_disk = float4(g_factor, hitState.dxy, vrRatio, 0.0);
    info.direct_world = float4(obsDir, 0.0);
    if (FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u && P.diskAtlasMode != 0u) {
        // Thin visible reference is a ray/disk-intersection source model. Store
        // the actual geodesic hit coordinates, not the legacy probe offset used
        // for procedural cloud texture. If an atlas is present, it is only a
        // positive hot-skin source perturbation on this clean photosphere.
        info.noise = 0.0;
        if (P.diskAtlasMode != 0u && P.diskAtlasDensityBlend > 1e-6) {
            float4 atlasSample = disk_sample_atlas_source_filtered(
                hitState.dxy,
                hitState.phiHit,
                abs(ctLen) / max(P.rs, 1e-6),
                P,
                diskAtlasTex
            );
            info.noise = clamp(atlasSample.y, 0.0, 1.0);
            // The atlas temperature channel is a positive hot-skin activity
            // proxy in thin-visible-reference mode. It is not allowed to lower
            // the analytic body photosphere; compose uses it only for additive
            // skin temperature/activity.
            info.T = T * clamp(atlasSample.x, 0.65, 1.80);
        }
        info.emit_r_norm = hitState.dxy / max(P.rs, 1e-6);
        info.emit_phi = hitState.phiHit;
        info.emit_z_norm = hitState.hitPos.z / max(P.rs, 1e-6);
        return;
    }
    float3 samplePos = disk_sample_probe_pos(hitState.hitPos, world0, worldPos, P);
    disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlasTex);
    if (P.diskAtlasMode != 0u) {
        // For GRMHD-derived surface atlases, preserve the source/column
        // structure at the actual geodesic hit. The probe position is useful for
        // procedural volume clouds, but it can over-smooth a thin photosphere
        // atlas and hide the data-driven flow structure.
        info.noise = clamp(disk_sample_atlas(hitState.dxy, hitState.phiHit, P, diskAtlasTex).y, 0.0, 1.0);
    }
}

static inline void trace_store_kerr_surface_hit(thread CollisionInfo& info,
                                                thread const KerrSurfaceHitState& hitState,
                                                float massLen,
                                                float g_factor,
                                                float vrRatio,
                                                float T,
                                                float3 obsDir,
                                                float3 world0,
                                                float3 worldPos,
                                                constant Params& P,
                                                texture2d<float, access::sample> diskAtlasTex)
{
    float ctLen = hitState.hitState.t * massLen;
    info.hit = 1;
    info.ct  = ctLen;
    info.T   = T;
    info.v_disk = float4(g_factor, hitState.dxy, vrRatio, 0.0);
    info.direct_world = float4(obsDir, 0.0);
    if (FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u && P.diskAtlasMode != 0u) {
        // Thin visible reference is a ray/disk-intersection source model. Store
        // the actual geodesic hit coordinates, not the legacy probe offset used
        // for procedural cloud texture. If an atlas is present, it is only a
        // positive hot-skin source perturbation on this clean photosphere.
        info.noise = 0.0;
        if (P.diskAtlasMode != 0u && P.diskAtlasDensityBlend > 1e-6) {
            float4 atlasSample = disk_sample_atlas_source_filtered(
                hitState.dxy,
                hitState.phiHit,
                abs(ctLen) / max(P.rs, 1e-6),
                P,
                diskAtlasTex
            );
            info.noise = clamp(atlasSample.y, 0.0, 1.0);
            // The atlas temperature channel is a positive hot-skin activity
            // proxy in thin-visible-reference mode. It is not allowed to lower
            // the analytic body photosphere; compose uses it only for additive
            // skin temperature/activity.
            info.T = T * clamp(atlasSample.x, 0.65, 1.80);
        }
        info.emit_r_norm = hitState.dxy / max(P.rs, 1e-6);
        info.emit_phi = hitState.phiHit;
        info.emit_z_norm = hitState.hitPos.z / max(P.rs, 1e-6);
        return;
    }
    float3 samplePos = disk_sample_probe_pos(hitState.hitPos, world0, worldPos, P);
    disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlasTex);
    if (P.diskAtlasMode != 0u) {
        // For GRMHD-derived surface atlases, preserve the source/column
        // structure at the actual geodesic hit. The probe position is useful for
        // procedural volume clouds, but it can over-smooth a thin photosphere
        // atlas and hide the data-driven flow structure.
        info.noise = clamp(disk_sample_atlas(hitState.dxy, hitState.phiHit, P, diskAtlasTex).y, 0.0, 1.0);
    }
}

struct SchwarzschildSurfacePrepared {
    float vrRatio;
    float vphiScale;
    float tempScale;
    float3 obsDir;
};

struct KerrSurfacePrepared {
    float vrRatio;
    float vphiScale;
    float tempScale;
    float3 obsDir;
};

static inline bool trace_commit_schwarzschild_surface_hit_impl(constant Params& P,
                                                               float3 world0,
                                                               float3 worldPos,
                                                               float3 dir,
                                                               float3 newX,
                                                               float3 newY,
                                                               float3 newZ,
                                                               float4 pPrev,
                                                               float4 vPrev,
                                                               float4 p,
                                                               float4 v,
                                                               float diskInner,
                                                               float diskEmitMin,
                                                               float rObs,
                                                               texture2d<float, access::sample> diskAtlasTex,
                                                               bool allowAtlasOverrides,
                                                               bool allowPlunge,
                                                               thread CollisionInfo& info);

static inline bool trace_commit_kerr_surface_hit_impl(constant Params& P,
                                                      float3 world0,
                                                      float3 worldPos,
                                                      float3 dir,
                                                      thread const KerrState& prevState,
                                                      thread const KerrState& state,
                                                      float hUsed,
                                                      float a,
                                                      float Lz,
                                                      float massLen,
                                                      float diskInner,
                                                      float diskInnerM,
                                                      float diskEmitMin,
                                                      texture2d<float, access::sample> diskAtlasTex,
                                                      bool allowAtlasOverrides,
                                                      bool allowPlunge,
                                                      thread CollisionInfo& info);

static inline SchwarzschildSurfacePrepared trace_prepare_schwarzschild_surface(thread const SchwarzschildSurfaceHitState& hitState,
                                                                               float3 dir,
                                                                               constant Params& P,
                                                                               texture2d<float, access::sample> diskAtlasTex,
                                                                               bool allowAtlasOverrides)
{
    float4 atlas = disk_sample_atlas(hitState.dxy, hitState.phiHit, P, diskAtlasTex);
    float vrRatio = 0.0;
    float vphiScale = 1.0;
    float tempScale = 1.0;
    bool useAtlasKinematics = allowAtlasOverrides && !(FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u);
    if (useAtlasKinematics) {
        vrRatio = clamp(atlas.z * P.diskAtlasVrScale, -1.0, 1.0);
        vphiScale = clamp(atlas.w * P.diskAtlasVphiScale, 0.0, 4.0);
        tempScale = clamp(atlas.x * P.diskAtlasTempScale, 0.05, 20.0);
    }

    float3 segDir = hitState.segEnd - hitState.segStart;
    float segLen2 = dot(segDir, segDir);
    float3 obsDir = -((segLen2 > 1e-20) ? normalize(segDir) : normalize(dir));
    return { vrRatio, vphiScale, tempScale, obsDir };
}

static inline KerrSurfacePrepared trace_prepare_kerr_surface(thread const KerrSurfaceHitState& hitState,
                                                             float3 dir,
                                                             constant Params& P,
                                                             texture2d<float, access::sample> diskAtlasTex,
                                                             bool allowAtlasOverrides)
{
    float4 atlas = disk_sample_atlas(hitState.dxy, hitState.phiHit, P, diskAtlasTex);
    float vrRatio = 0.0;
    float vphiScale = 1.0;
    float tempScale = 1.0;
    bool useAtlasKinematics = allowAtlasOverrides && !(FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u);
    if (useAtlasKinematics) {
        vrRatio = clamp(atlas.z * P.diskAtlasVrScale, -1.0, 1.0);
        vphiScale = clamp(atlas.w * P.diskAtlasVphiScale, 0.0, 4.0);
        tempScale = clamp(atlas.x * P.diskAtlasTempScale, 0.05, 20.0);
    }

    float3 segDir = hitState.segEnd - hitState.segStart;
    float segLen2 = dot(segDir, segDir);
    float3 obsDir = -((segLen2 > 1e-20) ? normalize(segDir) : normalize(dir));
    return { vrRatio, vphiScale, tempScale, obsDir };
}


static inline bool trace_commit_schwarzschild_surface_hit_legacy_thin(constant Params& P,
                                                                      float3 world0,
                                                                      float3 worldPos,
                                                                      float3 dir,
                                                                      float3 newX,
                                                                      float3 newY,
                                                                      float3 newZ,
                                                                      float4 pPrev,
                                                                      float4 vPrev,
                                                                      float4 p,
                                                                      float4 v,
                                                                      float diskInner,
                                                                      float diskEmitMin,
                                                                      float rObs,
                                                                      texture2d<float, access::sample> diskAtlasTex,
                                                                      thread CollisionInfo& info)
{
    return trace_commit_schwarzschild_surface_hit_impl(P, world0, worldPos, dir, newX, newY, newZ,
                                                       pPrev, vPrev, p, v, diskInner, diskEmitMin, rObs,
                                                       diskAtlasTex,
                                                       (FC_PHYSICS_MODE != 2u) && (FC_PHYSICS_MODE != 0u || P.diskAtlasMode != 0u),
                                                       FC_PHYSICS_MODE != 0u,
                                                       info);
}

static inline bool trace_commit_schwarzschild_surface_hit_thick(constant Params& P,
                                                                float3 world0,
                                                                float3 worldPos,
                                                                float3 dir,
                                                                float3 newX,
                                                                float3 newY,
                                                                float3 newZ,
                                                                float4 pPrev,
                                                                float4 vPrev,
                                                                float4 p,
                                                                float4 v,
                                                                float diskInner,
                                                                float diskEmitMin,
                                                                float rObs,
                                                                texture2d<float, access::sample> diskAtlasTex,
                                                                thread CollisionInfo& info)
{
    return trace_commit_schwarzschild_surface_hit_impl(P, world0, worldPos, dir, newX, newY, newZ,
                                                       pPrev, vPrev, p, v, diskInner, diskEmitMin, rObs,
                                                       diskAtlasTex, true, true, info);
}

static inline bool trace_commit_schwarzschild_surface_hit_impl(constant Params& P,
                                                               float3 world0,
                                                               float3 worldPos,
                                                               float3 dir,
                                                               float3 newX,
                                                               float3 newY,
                                                               float3 newZ,
                                                               float4 pPrev,
                                                               float4 vPrev,
                                                               float4 p,
                                                               float4 v,
                                                               float diskInner,
                                                               float diskEmitMin,
                                                               float rObs,
                                                               texture2d<float, access::sample> diskAtlasTex,
                                                               bool allowAtlasOverrides,
                                                               bool allowPlunge,
                                                               thread CollisionInfo& info)
{
    SchwarzschildSurfaceHitState hitState = trace_refine_schwarzschild_surface_hit_state(world0, worldPos,
                                                                                          newX, newY, newZ,
                                                                                          pPrev, vPrev, p, v,
                                                                                          diskEmitMin, P);
    if (!hitState.valid) return false;

    float absV = sqrt(P.G * P.M / hitState.dxy);
    float invDxy = 1.0 / max(hitState.dxy, 1e-6);
    float3 er = float3(hitState.hitPos.x * invDxy, hitState.hitPos.y * invDxy, 0.0);
    float3 ephi = float3(hitState.hitPos.y * invDxy, -hitState.hitPos.x * invDxy, 0.0);
    SchwarzschildSurfacePrepared prepared = trace_prepare_schwarzschild_surface(
        hitState, dir, P, diskAtlasTex, allowAtlasOverrides
    );
    float vrRatio = prepared.vrRatio;
    float vphiScale = prepared.vphiScale;
    float tempScale = prepared.tempScale;
    float massLen = 0.5 * P.rs;
    float rM = hitState.dxy / max(massLen, 1e-12);
    float betaRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
    float betaRCoord = vrRatio * betaRef;
    float betaPhiCoord = -vphiScale * betaRef;
    float3 v_disk = absV * (vrRatio * er + vphiScale * ephi);
    if (allowPlunge && hitState.dxy < diskInner * (1.0 - 1e-4)) {
        float rMsM = diskInner / max(massLen, 1e-12);
        float betaR = 0.0;
        float betaPhi = 0.0;
        if (disk_schwarzschild_plunge_local_beta(rM, rMsM, betaR, betaPhi)) {
            v_disk = P.c * (betaR * er + betaPhi * ephi);
            betaRCoord = betaR;
            betaPhiCoord = betaPhi;
            float vrRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
            vrRatio = clamp(betaR / max(vrRef, 1e-6), -1.0, 1.0);
        }
    }
    float vMag = length(v_disk);
    float vCap = 0.999 * P.c;
    if (vMag > vCap && vMag > 1e-9) v_disk *= (vCap / vMag);

    float4 rayDerivHit = hitState.vHit;
    float g_factor = disk_schwarzschild_direct_gfactor(hitState.dxy,
                                                       rObs,
                                                       rayDerivHit,
                                                       betaRCoord,
                                                       betaPhiCoord,
                                                       P);

    float T = (FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u)
        ? disk_visible_teff(hitState.dxy, P)
        : disk_effective_temperature(hitState.dxy, diskInner, P);
    T *= tempScale;
    if (FC_PHYSICS_MODE == 2u) {
        // Physical atmospheric temperature profile replacing Perlin texture.
        // Eddington T(τ) with MRI magnetic surface heating at τ ~ 0.3–1
        // (see disk_eddington_atmosphere_temp in disk_models.metal).
        float hNorm_hit  = abs(hitState.hitPos.z) / max(P.he, 1e-6);
        float tauMid_hit = max(P.diskCloudOpticalDepth * max(P.diskVolumeTauScale, 1.0), 0.5);
        T = disk_eddington_atmosphere_temp(hNorm_hit, tauMid_hit, T);
        // MRI turbulent heating: use diskPrecisionTexture (precision-mode texture parameter)
        float mriAmp_s = max(P.diskPrecisionTexture, P.diskTurbulence);
        T *= disk_mri_heating_factor_amp(hitState.dxy, hitState.phiHit, hitState.hitPos.z, mriAmp_s, P);
    }

    trace_store_schwarzschild_surface_hit(info, hitState, g_factor, vrRatio, T, prepared.obsDir, world0, worldPos, P, diskAtlasTex);
    return true;
}

static inline bool trace_commit_schwarzschild_surface_hit(constant Params& P,
                                                          float3 world0,
                                                          float3 worldPos,
                                                          float3 dir,
                                                          float3 newX,
                                                          float3 newY,
                                                          float3 newZ,
                                                          float4 pPrev,
                                                          float4 vPrev,
                                                          float4 p,
                                                          float4 v,
                                                          float diskInner,
                                                          float diskEmitMin,
                                                          float rObs,
                                                          texture2d<float, access::sample> diskAtlasTex,
                                                          thread CollisionInfo& info)
{
    if (FC_PHYSICS_MODE == 1u) {
        return trace_commit_schwarzschild_surface_hit_thick(P, world0, worldPos, dir, newX, newY, newZ,
                                                            pPrev, vPrev, p, v, diskInner, diskEmitMin, rObs,
                                                            diskAtlasTex, info);
    }
    return trace_commit_schwarzschild_surface_hit_legacy_thin(P, world0, worldPos, dir, newX, newY, newZ,
                                                              pPrev, vPrev, p, v, diskInner, diskEmitMin, rObs,
                                                              diskAtlasTex, info);
}

static inline bool trace_commit_kerr_surface_hit_legacy_thin(constant Params& P,
                                                             float3 world0,
                                                             float3 worldPos,
                                                             float3 dir,
                                                             thread const KerrState& prevState,
                                                             thread const KerrState& state,
                                                             float hUsed,
                                                             float a,
                                                             float Lz,
                                                             float massLen,
                                                             float diskInner,
                                                             float diskInnerM,
                                                             float diskEmitMin,
                                                             texture2d<float, access::sample> diskAtlasTex,
                                                             thread CollisionInfo& info)
{
    return trace_commit_kerr_surface_hit_impl(P, world0, worldPos, dir, prevState, state, hUsed, a, Lz,
                                              massLen, diskInner, diskInnerM, diskEmitMin, diskAtlasTex,
                                              (FC_PHYSICS_MODE != 2u) && (FC_PHYSICS_MODE != 0u || P.diskAtlasMode != 0u),
                                              FC_PHYSICS_MODE != 0u, info);
}

static inline bool trace_commit_kerr_surface_hit_thick(constant Params& P,
                                                       float3 world0,
                                                       float3 worldPos,
                                                       float3 dir,
                                                       thread const KerrState& prevState,
                                                       thread const KerrState& state,
                                                       float hUsed,
                                                       float a,
                                                       float Lz,
                                                       float massLen,
                                                       float diskInner,
                                                       float diskInnerM,
                                                       float diskEmitMin,
                                                       texture2d<float, access::sample> diskAtlasTex,
                                                       thread CollisionInfo& info)
{
    return trace_commit_kerr_surface_hit_impl(P, world0, worldPos, dir, prevState, state, hUsed, a, Lz,
                                              massLen, diskInner, diskInnerM, diskEmitMin, diskAtlasTex,
                                              true, true, info);
}

static inline bool trace_commit_kerr_surface_hit_impl(constant Params& P,
                                                      float3 world0,
                                                      float3 worldPos,
                                                      float3 dir,
                                                      thread const KerrState& prevState,
                                                      thread const KerrState& state,
                                                      float hUsed,
                                                      float a,
                                                      float Lz,
                                                      float massLen,
                                                      float diskInner,
                                                      float diskInnerM,
                                                      float diskEmitMin,
                                                      texture2d<float, access::sample> diskAtlasTex,
                                                      bool allowAtlasOverrides,
                                                      bool allowPlunge,
                                                      thread CollisionInfo& info)
{
    KerrSurfaceHitState hitState = trace_refine_kerr_surface_hit_state(world0, worldPos,
                                                                       prevState, state, hUsed,
                                                                       a, Lz, massLen, diskEmitMin, P);
    if (!hitState.valid) return false;

    KerrSurfacePrepared prepared = trace_prepare_kerr_surface(
        hitState, dir, P, diskAtlasTex, allowAtlasOverrides
    );
    float vrRatio = prepared.vrRatio;
    float vphiScale = prepared.vphiScale;
    float tempScale = prepared.tempScale;
    float omegaK = 1.0 / max(pow_1p5(hitState.r_M) + a, 1e-8);
    float omega = omegaK * vphiScale;
    float drdt = vrRatio * sqrt(1.0 / max(hitState.r_M, 1.0));
    if (allowPlunge && hitState.r_M < diskInnerM * (1.0 - 1e-4)) {
        float plungeOmega = omega;
        float plungeDrdt = drdt;
        float plungeVrRatio = vrRatio;
        if (disk_kerr_plunge_kinematics(hitState.r_M, diskInnerM, a, plungeOmega, plungeDrdt, plungeVrRatio)) {
            omega = plungeOmega;
            drdt = plungeDrdt;
            vrRatio = plungeVrRatio;
        }
    }
    float prRay = hitState.hitState.pr;
    float g_factor = 1.0;
    if (!disk_kerr_flow_gfactor(hitState.r_M, a, omega, drdt, Lz, prRay, g_factor)) {
        omega = omegaK;
        drdt = 0.0;
        if (!disk_kerr_flow_gfactor(hitState.r_M, a, omega, drdt, Lz, prRay, g_factor)) {
            g_factor = 1.0;
        }
    }

    float T = (FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u)
        ? disk_visible_teff(hitState.dxy, P)
        : disk_effective_temperature(hitState.dxy, diskInner, P);
    T *= tempScale;
    if (FC_PHYSICS_MODE == 2u) {
        float hNorm_hit  = abs(hitState.hitPos.z) / max(P.he, 1e-6);
        float tauMid_hit = max(P.diskCloudOpticalDepth * max(P.diskVolumeTauScale, 1.0), 0.5);
        T = disk_eddington_atmosphere_temp(hNorm_hit, tauMid_hit, T);
        float mriAmp_k = max(P.diskPrecisionTexture, P.diskTurbulence);
        T *= disk_mri_heating_factor_amp(hitState.dxy, hitState.phiHit, hitState.hitPos.z, mriAmp_k, P);
    }

    trace_store_kerr_surface_hit(info, hitState, massLen, g_factor, vrRatio, T, prepared.obsDir, world0, worldPos, P, diskAtlasTex);
    return true;
}

static inline bool trace_commit_kerr_surface_hit(constant Params& P,
                                                 float3 world0,
                                                 float3 worldPos,
                                                 float3 dir,
                                                 thread const KerrState& prevState,
                                                 thread const KerrState& state,
                                                 float hUsed,
                                                 float a,
                                                 float Lz,
                                                 float massLen,
                                                 float diskInner,
                                                 float diskInnerM,
                                                 float diskEmitMin,
                                                 texture2d<float, access::sample> diskAtlasTex,
                                                 thread CollisionInfo& info)
{
    if (FC_PHYSICS_MODE == 1u) {
        return trace_commit_kerr_surface_hit_thick(P, world0, worldPos, dir, prevState, state, hUsed, a, Lz,
                                                   massLen, diskInner, diskInnerM, diskEmitMin, diskAtlasTex, info);
    }
    return trace_commit_kerr_surface_hit_legacy_thin(P, world0, worldPos, dir, prevState, state, hUsed, a, Lz,
                                                     massLen, diskInner, diskInnerM, diskEmitMin, diskAtlasTex, info);
}

static inline bool trace_schwarzschild_surface_legacy_thin_ray(constant Params& P,
                                                               float3 dir,
                                                               float3 newX,
                                                               float3 newY,
                                                               float3 newZ,
                                                               float r0,
                                                               texture2d<float, access::sample> diskAtlasTex,
                                                               thread CollisionInfo& info)
{
    float3 local = P.c * float3(dot(newX, dir), dot(newY, dir), dot(newZ, dir));
    bool hasPrev = false;
    float3 world0 = float3(0.0);

    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);
    float4 v = float4(0.1, local.x, 0.0, local.y / max(r0, 1e-6));

    float horizonRadius = P.rs * (1.0 + P.eps);
    float diskInner = disk_inner_radius_m(P);
    float diskEmitMin = disk_emit_min_radius_m(P);
    float rObs = max(length(P.camPos), 1.0001 * P.rs);

    for (int i = 0; i < P.maxSteps; ++i) {
        float4 pPrev = p;
        float4 vPrev = v;
        float rPrev = max(pPrev.y, horizonRadius + 1e-6);
        float nearH = clamp((3.2 * P.rs - rPrev) / max(2.2 * P.rs, 1e-6), 0.0, 1.0);
        float vRadFrac = clamp(abs(vPrev.y) / max(P.c, 1e-6), 0.0, 1.0);
        int localSubsteps = 1 + int(round(nearH * 6.0)) + int(round(nearH * 2.0 * vRadFrac));
        localSubsteps = clamp(localSubsteps, 1, 8);
        float hSub = P.h / float(localSubsteps);
        for (int s = 0; s < 8; ++s) {
            if (s >= localSubsteps) break;
            rk4_step_h(p, v, P, hSub);
        }

        float3 localPos = conv(p.y, p.z, p.w);
        float3 worldPos = localPos.x * newX + localPos.y * newY + localPos.z * newZ;

        if (hasPrev) {
            if (trace_commit_schwarzschild_surface_hit_legacy_thin(P,
                                                       world0,
                                                       worldPos,
                                                       dir,
                                                       newX,
                                                       newY,
                                                       newZ,
                                                       pPrev,
                                                       vPrev,
                                                       p,
                                                       v,
                                                       diskInner,
                                                       diskEmitMin,
                                                       rObs,
                                                       diskAtlasTex,
                                                       info)) {
                return true;
            }
        }

        hasPrev = true;
        world0 = worldPos;

        float dxy = length(float2(worldPos.x, worldPos.y));
        if (dxy > max(P.kerrEscapeMult, 1.0) * P.re) break;
        if (p.y < horizonRadius) break;
        if (!(isfinite(p.x) && isfinite(p.y) && isfinite(p.w))) break;
    }

    return false;
}

static inline bool trace_schwarzschild_surface_thick_ray(constant Params& P,
                                                         float3 dir,
                                                         float3 newX,
                                                         float3 newY,
                                                         float3 newZ,
                                                         float r0,
                                                         texture2d<float, access::sample> diskAtlasTex,
                                                         thread CollisionInfo& info)
{
    float3 local = P.c * float3(dot(newX, dir), dot(newY, dir), dot(newZ, dir));
    bool hasPrev = false;
    float3 world0 = float3(0.0);

    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);
    float4 v = float4(0.1, local.x, 0.0, local.y / max(r0, 1e-6));

    float horizonRadius = P.rs * (1.0 + P.eps);
    float diskInner = disk_inner_radius_m(P);
    float diskEmitMin = disk_emit_min_radius_m(P);
    float rObs = max(length(P.camPos), 1.0001 * P.rs);

    for (int i = 0; i < P.maxSteps; ++i) {
        float4 pPrev = p;
        float4 vPrev = v;
        float rPrev = max(pPrev.y, horizonRadius + 1e-6);
        float nearH = clamp((3.2 * P.rs - rPrev) / max(2.2 * P.rs, 1e-6), 0.0, 1.0);
        float vRadFrac = clamp(abs(vPrev.y) / max(P.c, 1e-6), 0.0, 1.0);
        int localSubsteps = 1 + int(round(nearH * 6.0)) + int(round(nearH * 2.0 * vRadFrac));
        localSubsteps = clamp(localSubsteps, 1, 8);
        float hSub = P.h / float(localSubsteps);
        for (int s = 0; s < 8; ++s) {
            if (s >= localSubsteps) break;
            rk4_step_h(p, v, P, hSub);
        }

        float3 localPos = conv(p.y, p.z, p.w);
        float3 worldPos = localPos.x * newX + localPos.y * newY + localPos.z * newZ;
        if (hasPrev) {
            if (trace_commit_schwarzschild_surface_hit_thick(P,
                                                             world0,
                                                             worldPos,
                                                             dir,
                                                             newX,
                                                             newY,
                                                             newZ,
                                                             pPrev,
                                                             vPrev,
                                                             p,
                                                             v,
                                                             diskInner,
                                                             diskEmitMin,
                                                             rObs,
                                                             diskAtlasTex,
                                                             info)) {
                return true;
            }
        }

        hasPrev = true;
        world0 = worldPos;

        float dxy = length(float2(worldPos.x, worldPos.y));
        if (dxy > max(P.kerrEscapeMult, 1.0) * P.re) break;
        if (p.y < horizonRadius) break;
        if (!(isfinite(p.x) && isfinite(p.y) && isfinite(p.w))) break;
    }

    return false;
}

static inline bool trace_schwarzschild_surface_ray(constant Params& P,
                                                   float3 dir,
                                                   float3 newX,
                                                   float3 newY,
                                                   float3 newZ,
                                                   float r0,
                                                   texture2d<float, access::sample> diskAtlasTex,
                                                   thread CollisionInfo& info)
{
    if (FC_PHYSICS_MODE == 1u) {
        return trace_schwarzschild_surface_thick_ray(P, dir, newX, newY, newZ, r0, diskAtlasTex, info);
    }
    return trace_schwarzschild_surface_legacy_thin_ray(P, dir, newX, newY, newZ, r0, diskAtlasTex, info);
}

static inline void trace_update_volume_obs_dir(float3 world0,
                                               float3 worldPos,
                                               thread float3& volumeObsDir,
                                               thread CollisionInfo& info)
{
    float3 segDir = worldPos - world0;
    float segLen2 = dot(segDir, segDir);
    if (segLen2 > 1e-20) {
        volumeObsDir = -normalize(segDir);
        info.direct_world = float4(volumeObsDir, 0.0);
    }
}

static inline bool trace_schwarzschild_volume_ray(constant Params& P,
                                                  float3 dir,
                                                  float3 newX,
                                                  float3 newY,
                                                  float3 newZ,
                                                  float r0,
                                                  texture3d<float, access::sample> diskVol0Tex,
                                                  texture3d<float, access::sample> diskVol1Tex,
                                                  thread CollisionInfo& info)
{
    float3 local = P.c * float3(dot(newX, dir), dot(newY, dir), dot(newZ, dir));
    bool hasPrev = false;
    float3 world0 = float3(0.0);

    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);
    float4 v = float4(0.1, local.x, 0.0, local.y / max(r0, 1e-6));

    float horizonRadius = P.rs * (1.0 + P.eps);
    float diskInner = disk_inner_radius_m(P);
    VolumeAccum volumeA;
    volume_accum_init(volumeA);
    float3 volumeObsDir = -normalize(dir);

    for (int i = 0; i < P.maxSteps; ++i) {
        float4 pPrev = p;
        float4 vPrev = v;
        float rPrev = max(pPrev.y, horizonRadius + 1e-6);
        float nearH = clamp((3.2 * P.rs - rPrev) / max(2.2 * P.rs, 1e-6), 0.0, 1.0);
        float vRadFrac = clamp(abs(vPrev.y) / max(P.c, 1e-6), 0.0, 1.0);
        int localSubsteps = 1 + int(round(nearH * 6.0)) + int(round(nearH * 2.0 * vRadFrac));
        localSubsteps = clamp(localSubsteps, 1, 8);
        float hSub = P.h / float(localSubsteps);
        for (int s = 0; s < 8; ++s) {
            if (s >= localSubsteps) break;
            rk4_step_h(p, v, P, hSub);
        }

        float3 localPos = conv(p.y, p.z, p.w);
        float3 worldPos = localPos.x * newX + localPos.y * newY + localPos.z * newZ;

        if (hasPrev) {
            trace_update_volume_obs_dir(world0, worldPos, volumeObsDir, info);
            volume_integrate_segment(world0, worldPos, volumeObsDir, diskInner, P, diskVol0Tex, diskVol1Tex, volumeA,
                                     vPrev, v, 0.0, 0.0, 0.0);
        }

        hasPrev = true;
        world0 = worldPos;

        float dxy = length(float2(worldPos.x, worldPos.y));
        if (dxy > max(P.kerrEscapeMult, 1.0) * P.re) break;
        if (p.y < horizonRadius) break;
        if (!(isfinite(p.x) && isfinite(p.y) && isfinite(p.w))) break;
    }

    float impactRs = length(cross(P.camPos, dir)) / max(P.rs, 1e-6);
    return trace_commit_volume_hit(volumeA, true, diskInner, volumeObsDir, P.c * p.x, impactRs, P, info);
}

static inline bool trace_schwarzschild_ray(constant Params& P,
                                           float3 dir,
                                           float3 newX,
                                           float3 newY,
                                           float3 newZ,
                                           float r0,
                                           texture2d<float, access::sample> diskAtlasTex,
                                           texture3d<float, access::sample> diskVol0Tex,
                                           texture3d<float, access::sample> diskVol1Tex,
                                           thread CollisionInfo& info)
{
    if (disk_volume_mode_enabled_fc(P)) {
        return trace_schwarzschild_volume_ray(P, dir, newX, newY, newZ, r0, diskVol0Tex, diskVol1Tex, info);
    }
    return trace_schwarzschild_surface_ray(P, dir, newX, newY, newZ, r0, diskAtlasTex, info);
}

static inline bool trace_kerr_ray(constant Params& P,
                                  float3 dir,
                                  texture2d<float, access::sample> diskAtlasTex,
                                  texture3d<float, access::sample> diskVol0Tex,
                                  texture3d<float, access::sample> diskVol1Tex,
                                  thread CollisionInfo& info)
{
    if (disk_volume_mode_enabled_fc(P)) {
        return trace_kerr_volume_ray(P, dir, diskVol0Tex, diskVol1Tex, info);
    }
    return trace_kerr_surface_ray(P, dir, diskAtlasTex, info);
}

static inline bool trace_kerr_surface_legacy_thin_ray(constant Params& P,
                                                      float3 dir,
                                                      texture2d<float, access::sample> diskAtlasTex,
                                                      thread CollisionInfo& info)
{
    float massLen = 0.5 * P.rs;
    float a = clamp(P.spin, -0.999, 0.999);
    float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
    float diskInner = disk_inner_radius_m(P);
    float diskInnerM = diskInner / max(massLen, 1e-12);
    float diskEmitMin = disk_emit_min_radius_m(P);
    KerrState state;
    float Lz = 0.0;
    float horizonGeom = 0.0;
    if (!kerr_init_hamiltonian(P.camPos, dir, a, P, state, Lz, horizonGeom)) {
        return false;
    }

    float hStep = max(P.h, 1e-6);
    float hMin = max(P.h * 0.005, 1e-7);
    float hMax = max(P.h * 2.0, hMin);
    float tol = max(P.kerrTol, 1e-6);
    int stepMul = max(P.kerrSubsteps, 1);
    int targetSteps = min(P.maxSteps * stepMul, 40000);
    int accepted = 0;
    int guard = 0;
    bool hasPrev = false;
    float3 world0 = float3(0.0);

    while (accepted < targetSteps && guard < targetSteps * 12) {
        guard += 1;
        float distH = max(state.r - horizonGeom, 0.0);
        float nearH = clamp(distH / 0.8, 0.0, 1.0);
        float hMaxLocal = max(hMin, hMax * mix(0.08, 1.0, nearH * nearH));
        hStep = clamp(hStep, hMin, hMaxLocal);

        KerrState trial;
        float errNorm = 0.0;
        float nullResidual = 0.0;
        kerr_dp45_trial(state, hStep, a, Lz, trial, errNorm, nullResidual);

        if (!(isfinite(errNorm) && isfinite(trial.r) && isfinite(trial.theta) && isfinite(trial.phi) && isfinite(trial.t))) {
            break;
        }

        float drJump = abs(trial.r - state.r);
        float dThetaJump = abs(trial.theta - state.theta);
        float dPhiJump = abs(trial.phi - state.phi);
        float rScale = max(state.r, 1.0);
        bool jumpBad = (drJump > 0.20 * rScale) || (dThetaJump > 0.12) || (dPhiJump > 0.8);
        if (jumpBad) {
            errNorm = max(errNorm, tol * 32.0);
        }

        if (errNorm <= tol || hStep <= hMin * 1.01) {
            KerrState prevState = state;
            float hUsed = hStep;
            state = trial;
            accepted += 1;

            float thetaMin = 1e-4;
            if (state.theta < thetaMin) {
                state.theta = thetaMin;
                state.ptheta = abs(state.ptheta);
            } else if (state.theta > M_PI - thetaMin) {
                state.theta = M_PI - thetaMin;
                state.ptheta = -abs(state.ptheta);
            }

            state.phi = fmod(state.phi, 2.0 * M_PI);
            if (state.phi < 0.0) state.phi += 2.0 * M_PI;

            float ratio = max(errNorm / tol, 1e-8);
            float grow = clamp(0.9 * pow(ratio, -0.2), 0.25, 2.5);
            hStep = clamp(hStep * grow, hMin, hMaxLocal);
            if (abs(nullResidual) > 1e-6) {
                hStep = max(hMin, hStep * 0.5);
            }

            float radiusMeters = max(state.r, 0.0) * massLen;
            float3 worldPos = conv(radiusMeters, state.theta, state.phi);

            if (hasPrev) {
                if (trace_commit_kerr_surface_hit_legacy_thin(P,
                                                  world0,
                                                  worldPos,
                                                  dir,
                                                  prevState,
                                                  state,
                                                  hUsed,
                                                  a,
                                                  Lz,
                                                  massLen,
                                                  diskInner,
                                                  diskInnerM,
                                                  diskEmitMin,
                                                  diskAtlasTex,
                                                  info)) {
                    return true;
                }
            }

            hasPrev = true;
            world0 = worldPos;

            float dxy = length(float2(worldPos.x, worldPos.y));
            if (dxy > escapeRadius) break;
            if (state.r <= horizonGeom * (1.0 + P.eps)) break;
            if (!(isfinite(state.r) && isfinite(state.theta) && isfinite(state.phi) && isfinite(state.t))) break;
        } else {
            float ratio = max(errNorm / tol, 1e-8);
            float shrink = clamp(0.9 * pow(ratio, -0.25), 0.1, 0.5);
                hStep = max(hMin, hStep * shrink);
            }
        }

    return false;
}

static inline bool trace_kerr_surface_thick_ray(constant Params& P,
                                                float3 dir,
                                                texture2d<float, access::sample> diskAtlasTex,
                                                thread CollisionInfo& info)
{
    float massLen = 0.5 * P.rs;
    float a = clamp(P.spin, -0.999, 0.999);
    float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
    float diskInner = disk_inner_radius_m(P);
    float diskInnerM = diskInner / max(massLen, 1e-12);
    float diskEmitMin = disk_emit_min_radius_m(P);
    KerrState state;
    float Lz = 0.0;
    float horizonGeom = 0.0;
    if (!kerr_init_hamiltonian(P.camPos, dir, a, P, state, Lz, horizonGeom)) {
        return false;
    }

    float hStep = max(P.h, 1e-6);
    float hMin = max(P.h * 0.005, 1e-7);
    float hMax = max(P.h * 2.0, hMin);
    float tol = max(P.kerrTol, 1e-6);
    int stepMul = max(P.kerrSubsteps, 1);
    int targetSteps = min(P.maxSteps * stepMul, 40000);
    int accepted = 0;
    int guard = 0;
    bool hasPrev = false;
    float3 world0 = float3(0.0);

    while (accepted < targetSteps && guard < targetSteps * 12) {
        guard += 1;
        float distH = max(state.r - horizonGeom, 0.0);
        float nearH = clamp(distH / 0.8, 0.0, 1.0);
        float hMaxLocal = max(hMin, hMax * mix(0.08, 1.0, nearH * nearH));
        hStep = clamp(hStep, hMin, hMaxLocal);

        KerrState trial;
        float errNorm = 0.0;
        float nullResidual = 0.0;
        kerr_dp45_trial(state, hStep, a, Lz, trial, errNorm, nullResidual);
        if (!(isfinite(errNorm) && isfinite(trial.r) && isfinite(trial.theta) && isfinite(trial.phi) && isfinite(trial.t))) {
            break;
        }

        float drJump = abs(trial.r - state.r);
        float dThetaJump = abs(trial.theta - state.theta);
        float dPhiJump = abs(trial.phi - state.phi);
        float rScale = max(state.r, 1.0);
        bool jumpBad = (drJump > 0.20 * rScale) || (dThetaJump > 0.12) || (dPhiJump > 0.8);
        if (jumpBad) {
            errNorm = max(errNorm, tol * 32.0);
        }

        if (errNorm <= tol || hStep <= hMin * 1.01) {
            KerrState prevState = state;
            float hUsed = hStep;
            state = trial;
            accepted += 1;

            float thetaMin = 1e-4;
            if (state.theta < thetaMin) {
                state.theta = thetaMin;
                state.ptheta = abs(state.ptheta);
            } else if (state.theta > M_PI - thetaMin) {
                state.theta = M_PI - thetaMin;
                state.ptheta = -abs(state.ptheta);
            }
            state.phi = fmod(state.phi, 2.0 * M_PI);
            if (state.phi < 0.0) state.phi += 2.0 * M_PI;

            float ratio = max(errNorm / tol, 1e-8);
            float grow = clamp(0.9 * pow(ratio, -0.2), 0.25, 2.5);
            hStep = clamp(hStep * grow, hMin, hMaxLocal);
            if (abs(nullResidual) > 1e-6) {
                hStep = max(hMin, hStep * 0.5);
            }

            float radiusMeters = max(state.r, 0.0) * massLen;
            float3 worldPos = conv(radiusMeters, state.theta, state.phi);
            if (hasPrev) {
                if (trace_commit_kerr_surface_hit_thick(P,
                                                        world0,
                                                        worldPos,
                                                        dir,
                                                        prevState,
                                                        state,
                                                        hUsed,
                                                        a,
                                                        Lz,
                                                        massLen,
                                                        diskInner,
                                                        diskInnerM,
                                                        diskEmitMin,
                                                        diskAtlasTex,
                                                        info)) {
                    return true;
                }
            }

            hasPrev = true;
            world0 = worldPos;
            float dxy = length(float2(worldPos.x, worldPos.y));
            if (dxy > escapeRadius) break;
            if (state.r <= horizonGeom * (1.0 + P.eps)) break;
            if (!(isfinite(state.r) && isfinite(state.theta) && isfinite(state.phi) && isfinite(state.t))) break;
        } else {
            float ratio = max(errNorm / tol, 1e-8);
            float shrink = clamp(0.9 * pow(ratio, -0.25), 0.1, 0.5);
            hStep = max(hMin, hStep * shrink);
        }
    }

    return false;
}

static inline bool trace_kerr_surface_ray(constant Params& P,
                                          float3 dir,
                                          texture2d<float, access::sample> diskAtlasTex,
                                          thread CollisionInfo& info)
{
    if (FC_PHYSICS_MODE == 1u) {
        return trace_kerr_surface_thick_ray(P, dir, diskAtlasTex, info);
    }
    return trace_kerr_surface_legacy_thin_ray(P, dir, diskAtlasTex, info);
}

static inline bool trace_kerr_volume_ray(constant Params& P,
                                         float3 dir,
                                         texture3d<float, access::sample> diskVol0Tex,
                                         texture3d<float, access::sample> diskVol1Tex,
                                         thread CollisionInfo& info)
{
    float massLen = 0.5 * P.rs;
    float a = clamp(P.spin, -0.999, 0.999);
    float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
    float diskInner = disk_inner_radius_m(P);
    VolumeAccum volumeA;
    volume_accum_init(volumeA);
    float3 volumeObsDir = -normalize(dir);
    KerrState state;
    float Lz = 0.0;
    float horizonGeom = 0.0;
    if (!kerr_init_hamiltonian(P.camPos, dir, a, P, state, Lz, horizonGeom)) {
        return false;
    }

    float hStep = max(P.h, 1e-6);
    float hMin = max(P.h * 0.005, 1e-7);
    float hMax = max(P.h * 2.0, hMin);
    float tol = max(P.kerrTol, 1e-6);
    int stepMul = max(P.kerrSubsteps, 1);
    int targetSteps = min(P.maxSteps * stepMul, 40000);
    int accepted = 0;
    int guard = 0;
    bool hasPrev = false;
    float3 world0 = float3(0.0);

    while (accepted < targetSteps && guard < targetSteps * 12) {
        guard += 1;
        float distH = max(state.r - horizonGeom, 0.0);
        float nearH = clamp(distH / 0.8, 0.0, 1.0);
        float hMaxLocal = max(hMin, hMax * mix(0.08, 1.0, nearH * nearH));
        hStep = clamp(hStep, hMin, hMaxLocal);

        KerrState trial;
        float errNorm = 0.0;
        float nullResidual = 0.0;
        kerr_dp45_trial(state, hStep, a, Lz, trial, errNorm, nullResidual);

        if (!(isfinite(errNorm) && isfinite(trial.r) && isfinite(trial.theta) && isfinite(trial.phi) && isfinite(trial.t))) {
            break;
        }

        float drJump = abs(trial.r - state.r);
        float dThetaJump = abs(trial.theta - state.theta);
        float dPhiJump = abs(trial.phi - state.phi);
        float rScale = max(state.r, 1.0);
        bool jumpBad = (drJump > 0.20 * rScale) || (dThetaJump > 0.12) || (dPhiJump > 0.8);
        if (jumpBad) {
            errNorm = max(errNorm, tol * 32.0);
        }

        if (errNorm <= tol || hStep <= hMin * 1.01) {
            KerrState prevState = state;
            state = trial;
            accepted += 1;

            float thetaMin = 1e-4;
            if (state.theta < thetaMin) {
                state.theta = thetaMin;
                state.ptheta = abs(state.ptheta);
            } else if (state.theta > M_PI - thetaMin) {
                state.theta = M_PI - thetaMin;
                state.ptheta = -abs(state.ptheta);
            }

            state.phi = fmod(state.phi, 2.0 * M_PI);
            if (state.phi < 0.0) state.phi += 2.0 * M_PI;

            float ratio = max(errNorm / tol, 1e-8);
            float grow = clamp(0.9 * pow(ratio, -0.2), 0.25, 2.5);
            hStep = clamp(hStep * grow, hMin, hMaxLocal);
            if (abs(nullResidual) > 1e-6) {
                hStep = max(hMin, hStep * 0.5);
            }

            float radiusMeters = max(state.r, 0.0) * massLen;
            float3 worldPos = conv(radiusMeters, state.theta, state.phi);

            if (hasPrev) {
                trace_update_volume_obs_dir(world0, worldPos, volumeObsDir, info);
                volume_integrate_segment(world0, worldPos, volumeObsDir, diskInner, P, diskVol0Tex, diskVol1Tex, volumeA,
                                         float4(0.0), float4(0.0), Lz, prevState.pr, state.pr);
            }

            hasPrev = true;
            world0 = worldPos;

            float dxy = length(float2(worldPos.x, worldPos.y));
            if (dxy > escapeRadius) break;
            if (state.r <= horizonGeom * (1.0 + P.eps)) break;
            if (!(isfinite(state.r) && isfinite(state.theta) && isfinite(state.phi) && isfinite(state.t))) break;
        } else {
            float ratio = max(errNorm / tol, 1e-8);
            float shrink = clamp(0.9 * pow(ratio, -0.25), 0.1, 0.5);
            hStep = max(hMin, hStep * shrink);
        }
    }

    float impactRs = length(cross(P.camPos, dir)) / max(P.rs, 1e-6);
    return trace_commit_volume_hit(volumeA, true, diskInner, volumeObsDir, state.t * massLen, impactRs, P, info);
}

static inline bool disk_volume_mode_enabled_fc(constant Params& P) {
    if (P.diskVolumeMode == 0u) return false;
    if (FC_PHYSICS_MODE == 3u) return true;
    if (FC_PHYSICS_MODE == 2u) return true;
    if (FC_PHYSICS_MODE == 1u) {
        float tauCtrl = max(P.diskCloudOpticalDepth, 0.0) * max(P.diskVolumeTauScale, 0.0);
        return (tauCtrl > 1e-8);
    }
    return false;
}

static inline float volume_radial_edge_gate(float rNorm,
                                            float rNormMin,
                                            float rNormMax)
{
    float span = max(rNormMax - rNormMin, 1e-6);
    float innerWidth = max(0.50, 0.025 * span);
    float outerWidth = max(3.00, 0.14 * span);
    float inner = smoothstep(rNormMin, rNormMin + innerWidth, rNorm);
    float outer = 1.0 - smoothstep(rNormMax - outerWidth, rNormMax, rNorm);
    return clamp(inner * outer, 0.0, 1.0);
}

static inline void volume_integrate_segment(float3 p0,
                                            float3 p1,
                                            float3 obsDir,
                                            float diskInner,
                                            constant Params& P,
                                            texture3d<float, access::sample> diskVol0Tex,
                                            texture3d<float, access::sample> diskVol1Tex,
                                            thread VolumeAccum& A,
                                            float4 rayV0,
                                            float4 rayV1,
                                            float LzConst,
                                            float pr0,
                                            float pr1)
{
    if (!disk_volume_mode_enabled_fc(P)) return;
    // Optional photosphere shortcut for visible mode.
    // Keep it disabled by default so GRMHD uses volumetric RT integration.
    bool visibleSurfaceMode = (FC_PHYSICS_MODE == 3u &&
                               visible_mode_enabled_fc() &&
                               P.visiblePhotosphereRhoThreshold > 0.0);
    if (visibleSurfaceMode && A.surfaceHit != 0u) return;
    float3 seg = p1 - p0;
    float segLen = length(seg);
    if (!(segLen > 1e-9)) return;
    if (!(A.tau < 48.0)) return;

    float targetStep = max(0.18 * P.rs, 1e-6);
    int nMax = 6;
    bool thinImportedVolume = ((FC_PHYSICS_MODE == 3u) ||
                               (FC_PHYSICS_MODE == 2u &&
                                P.diskVolumeFormat == 0u &&
                                P.diskVolumeMode != 0u));
    if (thinImportedVolume) {
        // Thin GRMHD volumes are easy to miss with coarse segment sampling.
        // Tie step size to vertical extent so visible-surface / scalar-RT both remain stable.
        // The precision dngr-volume bridge uses the same finite photospheric
        // geometry, so it needs the same sampling density to preserve structure.
        float zScale = max(P.diskVolumeZNormMax * P.rs, 0.01 * P.rs);
        float thinStep = max(0.12 * zScale, 0.005 * P.rs);
        targetStep = min(targetStep, thinStep);
        nMax = 24;
    }
    int n = clamp((int)ceil(segLen / targetStep), 1, nMax);
    float ds = segLen / float(max(n, 1));
    float3 obs = (dot(obsDir, obsDir) > 1e-20) ? normalize(obsDir) : float3(0.0, 0.0, 1.0);
    float tauScaleLegacy = volume_legacy_tau_scale(P);
    float rhoThreshold = max(P.visiblePhotosphereRhoThreshold, 0.0);
    bool havePrevVisibleSample = false;
    float prevRho = 0.0;
    float prevT = 0.0;
    float3 prevPos = float3(0.0);
    bool havePrevVolumeSample = false;
    float prevRhoVolume = 0.0;
    float prevThetaeVolume = 0.0;
    float prevBVolume = 0.0;

    for (int i = 0; i < 24; ++i) {
        if (i >= n) break;
        float t = (float(i) + 0.5) / float(max(n, 1));
        float3 pos = p0 + seg * t;
        float r = length(pos.xy);
        if (!(r > P.rs * 1.0001 && r < P.re * 1.25)) continue;

        float phi = atan2(pos.y, pos.x);
        float rNorm = r / max(P.rs, 1e-6);
        float zNorm = pos.z / max(P.rs, 1e-6);
        float rNormMin = max(P.diskVolumeRNormMin, 0.2);
        float rNormMax = max(P.diskVolumeRNormMax, rNormMin + 1e-6);
        float zNormMax = max(P.diskVolumeZNormMax, 1e-6);
        if (!(rNorm >= rNormMin && rNorm <= rNormMax && abs(zNorm) <= zNormMax)) {
            continue;
        }
        float verticalEdgeGate = volume_vertical_edge_gate(zNorm, zNormMax);
        if (!(verticalEdgeGate > 1e-5)) continue;
        // Finite imported volumes are cropped for memory/performance. Fade the
        // transport coefficients at the crop boundary so the selected rMax does
        // not appear as a hard geometric sheet in the final image. This does not
        // change the sampled GRMHD state; it only apodizes the rendering domain.
        float radialEdgeGate = volume_radial_edge_gate(rNorm, rNormMin, rNormMax);
        if (!(radialEdgeGate > 1e-5)) continue;

        if (FC_PHYSICS_MODE == 1u) {
            if (volume_integrate_thick_sample(
                pos, obs, r, phi, t, diskInner, verticalEdgeGate * radialEdgeGate, ds, tauScaleLegacy,
                P, rayV0, rayV1, LzConst, pr0, pr1, A
            )) break;
            continue;
        }

        // Choke-point #3: explicit mode-3 GRMHD emissivity routing.
        if (FC_PHYSICS_MODE == 3u && P.diskVolumeFormat == 1u) {
            float4 vol0 = disk_sample_vol0(rNorm, phi, zNorm, P, diskVol0Tex);
            float4 vol1 = disk_sample_vol1(rNorm, phi, zNorm, P, diskVol1Tex);

            float rho = exp(clamp(vol0.x, -40.0, 40.0));
            float thetae = exp(clamp(vol0.y, -30.0, 20.0));
            float vR = vol0.z;
            float vPhi = vol0.w;
            float vZ = vol1.x;
            float3 bVec = float3(vol1.y, vol1.z, vol1.w);

            disk_grmhd_accum_diagnostics(rho, thetae, bVec, vR, vPhi, vZ, P, A);

            if (visibleSurfaceMode) {
                if (volume_commit_grmhd_visible_surface_hit(
                    pos, obs, r, phi, zNorm, t, rNormMin, rNormMax, rhoThreshold, rho, vR,
                    LzConst, pr0, pr1, P, diskVol0Tex, diskVol1Tex,
                    A, havePrevVisibleSample, prevRho, prevT, prevPos
                )) return;
            }

            if (!(rho > 1e-24) || !(thetae > 1e-5)) continue;
            A.pathRs += ds / max(P.rs, 1e-6);
            float texLocal = 0.5;
            float texStrength = clamp(P.diskPrecisionTexture, 0.0, 1.0);
            if (texStrength > 1e-5 && havePrevVolumeSample) {
                float bNow = max(length(bVec), 1e-30);
                float logRhoStep = log(clamp(rho / max(prevRhoVolume, 1e-30), 1e-4, 1e4));
                float logThetaeStep = log(clamp(thetae / max(prevThetaeVolume, 1e-30), 1e-4, 1e4));
                float logBStep = log(clamp(bNow / max(prevBVolume, 1e-30), 1e-4, 1e4));
                float texArg = 0.60 * logRhoStep + 0.28 * logThetaeStep + 0.12 * logBStep;
                texLocal = 0.5 + 0.5 * tanh(texArg);
            }
            // Data-driven unresolved contrast: optically thick thermal RT tends to wash out
            // density structure because j/alpha -> B_nu(T). Use only local GRMHD field
            // gradients, not random/image-space noise, and keep the correction bounded.
            float flowContrast = 1.0;
            if (texStrength > 1e-5) {
                flowContrast = clamp(exp(texStrength * 0.20 * (2.0 * texLocal - 1.0)), 0.84, 1.22);
            }
            float dataFlowMod = 1.0;
            float dataFlowResidualLog = 0.0;
            float dataFlowResidualAmp = 0.0;
            if (texStrength > 1e-5 && P.visibleTeffModel == 3u && P.visibleEmissionModel == 0u) {
                // Preserve actual GRMHD azimuthal structure in the thermal visible
                // branch. Use fixed-(r,z) phi residuals rather than r/z high-pass
                // terms: r/z differencing turns smooth axisymmetric stratification
                // into screen-visible rings, while phi residuals represent genuine
                // non-axisymmetric flow structure when the snapshot contains it.
                float dPhi = max(6.28318530718 / max(float(P.diskVolumePhi), 1.0), 0.012);
                float4 vol0PP = disk_sample_vol0(rNorm, phi + dPhi, zNorm, P, diskVol0Tex);
                float4 vol0PM = disk_sample_vol0(rNorm, phi - dPhi, zNorm, P, diskVol0Tex);
                float4 vol1PP = disk_sample_vol1(rNorm, phi + dPhi, zNorm, P, diskVol1Tex);
                float4 vol1PM = disk_sample_vol1(rNorm, phi - dPhi, zNorm, P, diskVol1Tex);
                float4 vol0Opp = disk_sample_vol0(rNorm, phi + 3.14159265359, zNorm, P, diskVol0Tex);
                float4 vol1Opp = disk_sample_vol1(rNorm, phi + 3.14159265359, zNorm, P, diskVol1Tex);
                float logRhoLocalMean = 0.5 * (vol0PP.x + vol0PM.x);
                float logThetaLocalMean = 0.5 * (vol0PP.y + vol0PM.y);
                float logRhoResidual = vol0.x - logRhoLocalMean;
                float logThetaResidual = vol0.y - logThetaLocalMean;
                float logB = log(max(length(bVec), 1e-30));
                float logBPP = log(max(length(float3(vol1PP.y, vol1PP.z, vol1PP.w)), 1e-30));
                float logBPM = log(max(length(float3(vol1PM.y, vol1PM.z, vol1PM.w)), 1e-30));
                float logBLocalMean = 0.5 * (logBPP + logBPM);
                float logBResidual = logB - logBLocalMean;
                float logBOpp = log(max(length(float3(vol1Opp.y, vol1Opp.z, vol1Opp.w)), 1e-30));
                float logRhoAz = vol0.x - vol0Opp.x;
                float logThetaAz = vol0.y - vol0Opp.y;
                float logBAz = logB - logBOpp;
                float localResidual = 0.46 * logRhoResidual + 0.18 * logThetaResidual + 0.36 * logBResidual;
                float azResidual = 0.42 * logRhoAz + 0.18 * logThetaAz + 0.40 * logBAz;
                float residual = clamp(0.86 * localResidual + 0.14 * azResidual, -2.0, 2.0);
	                dataFlowResidualLog = residual;
	                dataFlowResidualAmp = abs(residual);
	                dataFlowMod = clamp(exp(texStrength * 1.05 * residual), 0.28, 3.40);
	            }
	            A.maxFlowResidual = max(A.maxFlowResidual, dataFlowResidualAmp);
            float g = disk_grmhd_approx_gfactor(r, phi, obs, vR, vPhi, vZ, P);
            if (!isfinite(g)) g = 1.0;

            // Visible GRMHD: integrate three CIE-fit wavelength anchors directly in the
            // RT loop instead of post-colorizing a single I_nu channel. The anchors are
            // optimized for blackbody chromaticity reconstruction with spectrum_visible.metal's
            // CIE approximation; exposure absorbs the small luminance scale error.
            bool useVisibleMultispectral = (visible_mode_enabled_fc() && !visibleSurfaceMode);
            float dI = 0.0;
            if (useVisibleMultispectral) {
                const float3 lamNm = float3(650.0, 520.0, 425.0);
                bool expressiveVisible = ((P.visiblePad0 & 1u) != 0u);
                float3 iPrevNu = A.IVisNu;
                float3 qPrevNu = A.QVisNu;
                float3 uPrevNu = A.UVisNu;
                float3 vPrevNu = A.VVisNu;
                float maxJObs = 0.0;
                bool polarized = (P.diskPolarizedRT != 0u);
                bool tauSurfaceVisible = (!expressiveVisible &&
                                          !polarized &&
                                          P.visibleEmissionModel == 0u &&
                                          P.visibleThermalTransferMode == 1u &&
                                          P.visiblePhotosphereRhoThreshold <= 0.0);
                // Use direct visible-band quadrature for all non-expressive GRMHD
                // visible models. The old synchrotron path used only three
                // anchors, which was adequate for scalar diagnostics but muted
                // physically meaningful spectral curvature.
                bool cieQuadratureVisible = (!tauSurfaceVisible &&
                                             !expressiveVisible &&
                                             !polarized &&
                                             P.visiblePhotosphereRhoThreshold <= 0.0);
                if (cieQuadratureVisible) {
                    A.visibleSpectrumMode = 1u;
                }

                float invR = 1.0 / max(r, 1e-8);
                float3 eR = float3(pos.x * invR, pos.y * invR, 0.0);
                float3 ePhi = float3(-eR.y, eR.x, 0.0);
                float3 eZ = float3(0.0, 0.0, 1.0);
                float3 bCart = bVec.x * eR + bVec.y * ePhi + bVec.z * eZ;
                float bMag = max(length(bCart), 1e-20);
                float bPar = dot(bCart, obs);
                float3 bProj = bCart - bPar * obs;
                float bProjMag = max(length(bProj), 1e-20);

                float3 refAxis = (abs(obs.z) < 0.95) ? float3(0.0, 0.0, 1.0) : float3(1.0, 0.0, 0.0);
                float3 skyE1 = normalize(cross(obs, refAxis));
                float3 skyE2 = normalize(cross(obs, skyE1));
                float psi = 0.0;
                if (bProjMag > 1e-18) {
                    psi = atan2(dot(bProj, skyE2), dot(bProj, skyE1));
                }
                float sinPitch = sqrt(max(1.0 - (bPar / bMag) * (bPar / bMag), 0.0));
                float aniso = mix(1.0, 0.25 + 0.75 * sinPitch, polarized ? 1.0 : 0.0);
                float p0 = clamp(P.diskPolarizationFrac, 0.0, 0.9) * sinPitch;
                float cos2psi = cos(2.0 * psi);
                float sin2psi = sin(2.0 * psi);
                float nuObsRef = max(P.diskNuObsHz, 1e6);
                float nuComovRef = max(nuObsRef / max(g, 1e-8), 1e3);
                float jComRef = 0.0;
                float aComRef = 0.0;
                float thermalThinWeight = disk_grmhd_visible_photosphere_weight(r, zNorm, P);
                float thermalEmissionWeight = disk_grmhd_weight_power(thermalThinWeight, P.thinWeightPowerEmission);
                float thermalAbsorptionWeight = disk_grmhd_weight_power(thermalThinWeight, P.thinWeightPowerAbsorption);
                float coronaLayerWeight = disk_grmhd_weight_power(
                    disk_grmhd_visible_corona_weight(r, zNorm, P),
                    P.coronaWeightPower
                ) * disk_grmhd_visible_corona_radial_weight(r, P);
                thermalEmissionWeight *= radialEdgeGate;
                thermalAbsorptionWeight *= radialEdgeGate;
                coronaLayerWeight *= radialEdgeGate;
                float visibleAlpha = clamp(P.visibleEmissionAlpha, 0.0, 4.0);
                float dIRef = 0.0;
                if (expressiveVisible) {
                    // Expressive visible mode:
                    // derive RGB-band I_nu from a physically-traced reference I_nu at nu_obs,
                    // then map to visible via a spectral slope instead of forcing synthetic hits.
                    disk_grmhd_synch_coeffs(rho, thetae, bVec, nuComovRef, P, jComRef, aComRef);
                    float aCoolRef = max(P.diskGrmhdAbsorptionScale, 0.0)
                                   * disk_cool_absorber_alpha(rho, thetae, bVec, nuComovRef, P);
                    jComRef *= radialEdgeGate;
                    aComRef = (aComRef + aCoolRef) * radialEdgeGate;

                    float jObsRef = (jComRef * g * g) * aniso;
                    float aObsRef = aComRef / max(g, 1e-8);
                    float iPrevRef = A.I;
                    if (aObsRef > 1e-12) {
                        float dTauRef = min(aObsRef * ds, 40.0);
                        float tauBeforeRef = A.tau;
                        volume_accum_note_transfer(A, jObsRef, aObsRef, tauBeforeRef, dTauRef, r, ds, P);
                        float transRef = exp(-dTauRef);
                        float srcRef = jObsRef / max(aObsRef, 1e-30);
                        A.I = iPrevRef * transRef + srcRef * (1.0 - transRef);
                        A.tau += dTauRef;
                    } else {
                        volume_accum_note_transfer(A, jObsRef, aObsRef, 0.0, 0.0, r, ds, P);
                        A.I = iPrevRef + jObsRef * ds;
                    }
                    dIRef = max(A.I - iPrevRef, 0.0);
                    maxJObs = max(maxJObs, jObsRef);
                }

                uint spectralBandCount = cieQuadratureVisible ? 9u : 3u;
                float dYVis = 0.0;
                for (uint k = 0u; k < spectralBandCount; ++k) {
                    if (tauSurfaceVisible && ((A.tauSurfaceMask & (1u << k)) != 0u)) {
                        continue;
                    }
                    float lamNmK = cieQuadratureVisible ? volume_visible_band_lambda_nm(k) : lamNm[k];
                    float lamMK = lamNmK * 1e-9;
                    float nuObs = P.c / max(lamMK, 1e-30);
                    float jCom = 0.0;
                    float aCom = 0.0;
                    float jThermalEff = 0.0;
                    float jThermalBodyEff = 0.0;
                    float jThinEff = 0.0;
                    float jThermalCloudEff = 0.0;
                    float jThermalCoronaEff = 0.0;
                    float jThermalSmoothEff = 0.0;
                    float smoothBodyLayerGate = 1.0;
                    float bodyProxy = 0.0;
                    float nuComov = max(nuObs / max(g, 1e-8), 1e3);
                    if (expressiveVisible) {
                        float ratio = max(nuObs / max(nuObsRef, 1e6), 1e-8);
                        jCom = jComRef * pow(ratio, -visibleAlpha);
                        aCom = aComRef;
                        jThinEff = jCom;
                    } else {
                        GrmhdRtComponents comps = disk_visible_rt_components(r, rho, thetae, bVec, vR, vPhi, vZ, nuComov, P);
                        jCom = comps.jTotal;
                        aCom = comps.aTotal;
                        jThermalEff = comps.jThermal;
                        jThinEff = comps.jThin;
                        A.maxEpsAbs = max(A.maxEpsAbs, comps.epsAbs);
                        A.maxABase = max(A.maxABase, comps.aBase);
                        A.maxACool = max(A.maxACool, comps.aCool);
                        A.maxJThermal = max(A.maxJThermal, comps.jThermal);
                        A.maxJThin = max(A.maxJThin, comps.jThin);
                        A.maxThinWeight = max(A.maxThinWeight, thermalThinWeight);
                        A.maxCoronaWeight = max(A.maxCoronaWeight, coronaLayerWeight);
                        if (k == 0u) {
                            A.intJThermal += max(comps.jThermal, 0.0) * ds;
                            A.intJThin += max(comps.jThin, 0.0) * ds;
                            A.intAlphaThermalPre += max(comps.aBase + comps.aCool, 0.0) * ds;
                        }
                        A.maxSourceThermal = max(A.maxSourceThermal, comps.sourceThermal);
                        A.maxSourceThin = max(A.maxSourceThin, comps.sourceThin);
                        if (P.visibleEmissionModel == 2u) {
                            // Hybrid GRMHD visible transport:
                            // keep the optically thick thermal photosphere, but
                            // do not let its smooth j/alpha source function erase
                            // the magnetized optically thin branch. visibleSynchScale
                            // is already the explicit calibration knob for that
                            // non-thermal diagnostic tail, so use it only to shift
                            // branch weights, not to paint image-space texture.
                            float tailMix = smoothstep(8.0, 80.0, max(P.visibleSynchScale, 0.0));
                            float thermalWeight = mix(1.0, 0.58, tailMix);
                            float thinWeight = mix(1.0, 2.65, tailMix);
                            float thermalOpacityWeight = mix(1.0, 0.70, tailMix);
                            float opacityContrast = mix(1.0, flowContrast, 0.35);
                            jThermalEff = comps.jThermal * thermalEmissionWeight * thermalWeight;
                            jThinEff = comps.jThin * flowContrast * thinWeight * coronaLayerWeight;
                            jCom = jThermalEff + jThinEff;
                            float aBaseEff = comps.aBase * thermalAbsorptionWeight * opacityContrast * thermalOpacityWeight;
                            float aCoolEff = comps.aCool * thermalAbsorptionWeight;
                            aCom = aBaseEff
                                 + aCoolEff
                                 + comps.aThin * coronaLayerWeight;
                            if (k == 0u) {
                                A.intJThermalWeighted += max(jThermalEff, 0.0) * ds;
                                A.intAlphaThermalPost += max(aBaseEff + aCoolEff, 0.0) * ds;
                            }
	                        } else {
	                            if (P.visibleEmissionModel == 0u) {
	                                float cloudOpacityMod = disk_grmhd_thermal_cloud_opacity_mod(rho, thetae, bVec, P);
	                                float cloudSourceMod = 1.0;
	                                float thermalFillingMod = 1.0;
	                                float emissionFilamentMod = 1.0;
	                                float flowTextureStrength = texStrength;
	                                float radialThermalWeight = disk_grmhd_visible_thermal_radial_weight(r, P) * radialEdgeGate;
	                                GrmhdDiagnosticState residualState = disk_grmhd_diagnostic_state(rho, thetae, bVec, vR, vPhi, vZ, P);
	                                float residualRNorm = max(r / max(P.rs, 1e-6), 1.0);
		                                float residualThetaRef = disk_grmhd_thetae_reference(P);
	                                float residualThetaRatio = clamp(max(thetae, 1e-12) / residualThetaRef, 1.0e-4, 1.0e4);
	                                float3 residualBEff = bVec * max(P.diskGrmhdBScale, 0.0);
	                                float residualPressure = max(residualState.rhoEff * max(thetae, 1e-12), 1e-30);
	                                float residualB2 = max(residualState.b2Eff, 0.0);
	                                float residualStressRaw = max(-residualBEff.x * residualBEff.y, 0.0)
	                                                        + 0.22 * abs(residualBEff.x * residualBEff.y);
	                                float residualStressRatio = clamp(
	                                    residualStressRaw / max(residualPressure + 0.08 * residualB2, 1e-30),
	                                    1.0e-7,
	                                    1.0e7
	                                );
	                                float residualHotGate = smoothstep(0.22, 4.8, residualThetaRatio);
	                                float residualStressGate = smoothstep(1.0e-5, 0.48, residualStressRatio);
	                                float residualMagGate = smoothstep(2.0e-5, 0.55, clamp(residualState.betaInvProxy, 0.0, 1.0e8));
	                                float residualDynamicGate = clamp(0.50 + 0.50 * max(residualStressGate, residualMagGate), 0.0, 1.0);
	                                float residualRadialGate = 1.0 / (1.0 + pow(max(residualRNorm / 58.0, 0.0), 1.55));
	                                // Suppress high-pass residuals in locally thermalized slabs. The residual still
	                                // drives hot/stressed optically-thin thermal cloud emission, but coarse dense cells
	                                // no longer stamp ring-like boundaries into every lensed image order.
	                                float residualTauRaw = max(comps.aBase * thermalAbsorptionWeight * radialThermalWeight * ds * 0.010, 0.0);
	                                float residualThermalizedDamp = rsqrt(1.0 + 0.35 * min(residualTauRaw, 12.0));
	                                float residualRtGate = clamp(
	                                    (0.45 + 0.55 * residualHotGate)
	                                    * residualDynamicGate
	                                    * residualRadialGate
	                                    * residualThermalizedDamp,
	                                    0.38,
	                                    1.0
	                                );
	                                float gatedDataFlowMod = mix(1.0, dataFlowMod, residualRtGate);
	                                if (flowTextureStrength > 1e-5) {
	                                    // Data-space subgrid closure: use only the
		                                    // local fixed-(r,z) azimuthal GRMHD residual computed above.
	                                    // Positive residuals are compressed/hotter
	                                    // cells; negative residuals are underdense
	                                    // gaps. No periodic or image-space texture is
	                                    // introduced here.
	                                    float localFieldGate = 0.35 + 0.65 * smoothstep(0.0, 0.9, abs(bVec.x) + abs(bVec.y));
	                                    float residualAmp = smoothstep(0.035, 0.90, dataFlowResidualAmp);
	                                    float residual = clamp(dataFlowResidualLog, -1.05, 2.5);
	                                    float sourceResidual = flowTextureStrength * residualRtGate * localFieldGate * residualAmp * residual;
		                                    cloudOpacityMod *= clamp(exp(0.08 * sourceResidual), 0.86, 1.30);
		                                    emissionFilamentMod = clamp(exp(0.48 * sourceResidual), 0.66, 2.55);
		                                    // Compression/reconnection-like heating proxy.
		                                    // This changes the local thermal source
		                                    // function, so structure can survive even when
		                                    // the volume is locally optically thick.
			                                    cloudSourceMod = clamp(exp(0.48 * sourceResidual), 0.62, 2.35);
				                                    thermalFillingMod = clamp(exp(0.48 * sourceResidual), 0.60, 2.75);
			                                }
		                                cloudSourceMod *= clamp(pow(gatedDataFlowMod, 0.72), 0.34, 3.05);
		                                thermalFillingMod *= clamp(pow(gatedDataFlowMod, 0.82), 0.28, 3.20);
		                                emissionFilamentMod *= clamp(pow(gatedDataFlowMod, 0.52), 0.46, 2.45);
	                                float emissiveOpacityMod = mix(1.0, cloudOpacityMod, 0.62);
	                                float absorptionOpacityMod = mix(1.0, cloudOpacityMod, 0.16);
	                                float aBaseEmit = comps.aBase
	                                     * thermalAbsorptionWeight
	                                     * emissiveOpacityMod
	                                     * radialThermalWeight;
	                                float aBaseEff = comps.aBase
                                     * thermalAbsorptionWeight
                                     * absorptionOpacityMod
                                     * radialThermalWeight;
                                float aCoolEff = comps.aCool
                                     * thermalAbsorptionWeight
                                     * radialThermalWeight;
                                // Temperature-flow mode: thermal density changes
                                // should change optical depth and local emissive
                                // weight, not create a separate cold occluder.
                                // Keep j/alpha tied to the same source function
                                // so hot, thick GRMHD gas emits rather than
                                // blacking out the image.
                                float flowOpacity = mix(1.0, flowContrast, 0.18);
                                // Visible thermal-flow mode treats the public
                                // GRMHD dump as a hot emitting volume, not a
                                // calibrated LTE photosphere. Only a small
                                // fraction of the code-unit thermal coefficient
                                // is allowed to extinguish the ray; emission
                                // remains tied to local rho/theta_e/B heating
                                // below. This is an escape-probability closure
                                // for unresolved clumpy gas, preventing the
                                // foreground disk plane from becoming a cold
                                // black slab when cool absorption is disabled.
                                float rawThermalAlpha = (aBaseEff + aCoolEff) * flowOpacity;
                                float thermalEscape = 0.010;
                                aCom = rawThermalAlpha * thermalEscape;
                                float sourceThermal = comps.sourceThermal * cloudSourceMod;
                                float jThermalBaseRef = max(P.diskGrmhdEmissionScale, 0.0)
                                     * aBaseEmit
                                     * sourceThermal
                                     * thermalEmissionWeight
                                     * mix(1.0, flowContrast, 0.45);
                                float jThermalContinuum = jThermalBaseRef
                                     * thermalFillingMod
                                     * emissionFilamentMod;
                                float jCloudThin = disk_grmhd_thermal_thin_cloud_emissivity(
                                    r, zNorm, rho, thetae, bVec, sourceThermal, jThermalBaseRef,
                                    gatedDataFlowMod, dataFlowResidualAmp, P
                                );
                                float cloudPatternMod = 1.0;
	                                if (flowTextureStrength > 1e-5) {
	                                    // High-pass GRMHD residual/stress modulation for the
	                                    // optically-thin thermal cloud term. The smooth
	                                    // continuum stays broad, while this branch carries
	                                    // unresolved flow inhomogeneity into RT radiance.
		                                    cloudPatternMod = clamp(pow(max(gatedDataFlowMod, 1e-6), 1.72)
			                                                          * pow(max(emissionFilamentMod, 1e-6), 2.95)
			                                                          * pow(max(thermalFillingMod, 1e-6), 1.35),
			                                                          0.018, 8.40);
		                                }
                                jThermalCloudEff = max(jCloudThin * cloudPatternMod, 0.0);
                                bool plasmaBodySkinMode = (P.grmhdSmoothWeightMode == 4u);
                                bool positivePlasmaMode = (P.grmhdSmoothWeightMode == 5u);
	                                bool hotSkinMode = (P.grmhdSmoothWeightMode >= 6u && P.grmhdSmoothWeightMode <= 9u);
	                                bool hotSkinCoronaMode = (P.grmhdSmoothWeightMode == 9u);
	                                bool hybridVisibleDiskMode = (P.grmhdSmoothWeightMode >= 10u && P.grmhdSmoothWeightMode <= 13u);
	                                bool hybridVisibleCoronaMode = (P.grmhdSmoothWeightMode == 13u);
	                                bool referenceSkinMode = (P.grmhdSmoothWeightMode == 14u || P.grmhdSmoothWeightMode == 15u);
	                                bool referenceSkinCoronaMode = (P.grmhdSmoothWeightMode == 15u);
	                                bool analyticBodySkinMode = hybridVisibleDiskMode || referenceSkinMode;
	                                if (analyticBodySkinMode) {
                                    // The hybrid body is a visible photosphere
                                    // experiment, not a full thick RIAF occluder.
                                    // Keep GRMHD absorption as a weak screen so it
                                    // can attenuate skin/corona without blackening
                                    // the analytic luminous disk body.
                                    aCom *= 0.45;
                                }
                                // Reduce only the smooth continuum fraction. The
                                // cloud branch still uses the same local thermal
                                // source spectrum, but carries GRMHD pressure/stress
                                // contrast as emissivity before RT.
		                                // Keep the smooth LTE-like continuum as a
		                                // radiance floor only. Evolved GRMHD flow
		                                // morphology should enter through the
		                                // residual/stress-selected cloud branch,
		                                // not through image-space compositing.
		                                //
		                                // The smooth branch is therefore weighted by
		                                // bounded local state gates rather than a
		                                // single global floor. This keeps the
		                                // continuum strongest in dense, thermalized,
		                                // low-residual, weakly magnetized disk slabs,
		                                // while allowing structured thermal-cloud
		                                // emission to dominate in turbulent or coronal
		                                // regions.
		                                float thermalContinuumBaseWeight = mix(0.008, 0.0008, clamp(P.diskPrecisionTexture, 0.0, 1.0));
		                                float residualActivity = clamp((residualRtGate - 0.38) / 0.62, 0.0, 1.0);
		                                float lowResidualGate = 1.0 - smoothstep(0.18, 0.82, residualActivity);
		                                float thermalizedGate = smoothstep(0.12, 0.92, clamp(comps.epsAbs, 0.0, 1.0));
		                                float lowMagGate = 1.0 - smoothstep(2.0e-5, 0.24, clamp(residualState.betaInvProxy, 0.0, 1.0e8));
		                                float diskLikeGate = smoothstep(0.08, 0.55, radialThermalWeight);
		                                float smoothStateWeight = clamp(
		                                    0.05
		                                    + 0.95
		                                    * pow(max(thermalizedGate, 1.0e-4), 0.90)
		                                    * pow(max(lowResidualGate, 1.0e-4), 0.85)
		                                    * pow(max(lowMagGate, 1.0e-4), 0.75)
		                                    * pow(max(diskLikeGate, 1.0e-4), 0.60),
		                                    0.05,
		                                    1.0
		                                );
                                float rRs = r / max(P.rs, 1e-6);
                                float bodyHOverR = clamp(
                                    mix(0.16, 0.070, thermalizedGate) * mix(1.0, 0.90, residualMagGate),
                                    0.050,
                                    0.18
                                );
                                float bodyLayerCoord = abs(zNorm) / max(rRs * bodyHOverR, 1.0e-4);
                                float midplaneBodyGate = exp(-0.5 * bodyLayerCoord * bodyLayerCoord);
                                float bodyTauProxy = max(rawThermalAlpha * ds * 0.12, residualTauRaw * 8.0);
                                float opticalBodyGate = sqrt(max(1.0 - exp(-18.0 * max(bodyTauProxy, 0.0)), 0.0));
                                float denseBodyGate = sqrt(max(thermalizedGate * diskLikeGate, 0.0));
                                float calmBodyGate = 0.40 + 0.60 * lowResidualGate;
                                bodyProxy = clamp(
                                    0.03
                                    + 0.97
                                    * pow(max(thermalizedGate, 1.0e-4), 0.90)
                                    * pow(max(diskLikeGate, 1.0e-4), 0.70)
                                    * pow(max(midplaneBodyGate, 1.0e-4), 0.85)
                                    * (0.25 + 0.75 * opticalBodyGate)
                                    * calmBodyGate,
                                    0.03,
                                    1.0
                                );
                                smoothBodyLayerGate = bodyProxy;
                                float hybridBodyUnit = 0.0;
                                float hybridSkinUnit = 0.0;
                                float hybridBodyGate = 0.0;
                                float hybridSkinGate = 0.0;
                                float hybridCoronaGate = 0.0;
                                if (analyticBodySkinMode) {
                                    // Analytic visible disk body modes:
                                    // the broad photospheric body is an analytic
                                    // thin-disk-like source, while the GRMHD dump
                                    // supplies only local hot-skin/corona structure.
                                    // The local opacity coefficient is used as a
                                    // path-length calibration anchor, not as the
                                    // primary morphology of the luminous body.
                                    float hybridRIn = max((P.visibleRIn > 0.0) ? P.visibleRIn : disk_inner_radius_m(P),
                                                          P.rs * 1.0001);
                                    float hybridX = max(r / max(hybridRIn, 1.0e-6), 1.0001);
                                    float hybridP = clamp(P.visibleTeffP, 0.55, 0.85);
                                    if (P.grmhdSmoothWeightMode == 11u) {
                                        hybridP = 0.60;
                                    } else if (P.grmhdSmoothWeightMode == 12u || P.grmhdSmoothWeightMode == 13u) {
                                        hybridP = 0.72;
                                    } else if (referenceSkinMode) {
                                        hybridP = clamp(P.visibleTeffP, 0.58, 0.82);
                                    }
                                    float hybridR0 = max(P.visibleTeffR0, hybridRIn * 1.35);
                                    float hybridBoundary = pow(clamp(1.0 - rsqrt(hybridX), 0.0, 1.0), 0.20);
                                    float hybridParamT = max(P.visibleTeffT0, 100.0)
                                                       * pow(max(r / max(hybridR0, 1.0e-6), 1.0e-6), -hybridP)
                                                       * (0.42 + 0.58 * hybridBoundary);
                                    float hybridNtT = disk_visible_teff(r, P);
                                    float hybridBodyT = max(hybridParamT, hybridNtT);
                                    float hybridBodySource = volume_planck_nu(nuComov, hybridBodyT, P);
                                    float hybridSkinT = hybridBodyT * (1.18 + 0.62 * residualHotGate + 0.18 * residualMagGate);
                                    float hybridSkinSource = volume_planck_nu(nuComov, hybridSkinT, P);
                                    // Visible-reference body should not render
                                    // the cool outer photosphere as a gray slab.
                                    // Let physically visible-temperature gas carry
                                    // the body, while cooler radii contribute only
                                    // a weak continuum floor.
                                    float hybridVisibleTempGate = referenceSkinMode
                                        ? smoothstep(3600.0, 7200.0, hybridBodyT)
                                        : 1.0;
                                    float hybridBodyVisibleSupport = referenceSkinMode
                                        ? mix(0.12, 1.0, hybridVisibleTempGate)
                                        : 1.0;
                                    float hybridSkinVisibleSupport = referenceSkinMode
                                        ? mix(0.35, 1.0, hybridVisibleTempGate)
                                        : 1.0;

                                    float hybridEdgeGate = smoothstep(1.02, 1.24, hybridX);
                                    float hybridOuterGate = 1.0 / (1.0 + pow(max(rRs / 72.0, 0.0), 2.15));
                                    float hybridHOverR = referenceSkinMode
                                        ? mix(0.038, 0.070, smoothstep(6.0, 52.0, rRs))
                                        : mix(0.026, 0.052, smoothstep(7.0, 58.0, rRs));
                                    float hybridLayerCoord = abs(zNorm) / max(rRs * hybridHOverR, 1.0e-4);
                                    float hybridMidplane = exp(-0.5 * hybridLayerCoord * hybridLayerCoord);
                                    float hybridBodySupport = hybridEdgeGate * hybridOuterGate * hybridMidplane * hybridBodyVisibleSupport;
                                    float hybridOpacityAnchor = max(comps.aBase * thermalAbsorptionWeight * radialThermalWeight, 1.0e-30);
                                    hybridBodyGate = clamp(hybridBodySupport, 0.0, 1.0);
                                    bodyProxy = hybridBodyGate;
                                    smoothBodyLayerGate = hybridBodyGate;
                                    hybridBodyUnit = max(P.diskGrmhdEmissionScale, 0.0)
                                                   * hybridOpacityAnchor
                                                   * hybridBodySource
                                                   * thermalEmissionWeight;

                                    float hybridResidualAmp = smoothstep(0.025, 0.82, dataFlowResidualAmp);
                                    float hybridPositiveResidual = smoothstep(0.015, 0.92, max(dataFlowResidualLog, 0.0) * hybridResidualAmp);
                                    float hybridSkinLayer = smoothstep(0.35, 1.25, hybridLayerCoord)
                                                          * (1.0 - smoothstep(4.2, 7.4, hybridLayerCoord));
                                    if (referenceSkinMode) {
                                        // A positive emitting transition layer around
                                        // the photosphere. This is deliberately not
                                        // a dark residual multiplier on the body.
                                        float skinShell = exp(-0.5 * pow((hybridLayerCoord - 1.25) / 0.92, 2.0));
                                        hybridSkinLayer = clamp(0.12 + 0.88 * skinShell, 0.12, 1.0);
                                    } else {
                                        hybridSkinLayer = clamp(0.16 + 0.84 * hybridSkinLayer, 0.16, 1.0);
                                    }
                                    float hybridInnerGate = 1.0 / (1.0 + pow(max(rRs / 46.0, 0.0), 1.65));
                                    float hybridRhoProxy = clamp(sqrt(max(thermalizedGate * diskLikeGate, 0.0)), 0.0, 1.0);
                                    float hybridBProxy = clamp(0.12 + 0.88 * residualMagGate, 0.0, 1.0);
                                    float hybridThetaProxy = clamp(0.10 + 0.90 * residualHotGate, 0.0, 1.0);
                                    float hybridHeating = referenceSkinMode
                                        ? clamp(
                                            0.16
                                            + 0.26 * hybridPositiveResidual
                                            + 0.34 * residualStressGate
                                            + 0.34 * residualMagGate
                                            + 0.30 * residualHotGate,
                                            0.0,
                                            1.34
                                        )
                                        : clamp(
                                            0.16
                                            + 0.48 * hybridPositiveResidual
                                            + 0.30 * residualStressGate
                                            + 0.28 * residualMagGate
                                            + 0.18 * residualHotGate,
                                            0.0,
                                            1.36
                                        );
                                    float hybridBExp = (P.grmhdSmoothWeightMode == 12u || P.grmhdSmoothWeightMode == 13u) ? 1.70 : 1.36;
                                    float hybridThetaExp = (P.grmhdSmoothWeightMode == 12u || P.grmhdSmoothWeightMode == 13u) ? 2.30 : 1.92;
                                    if (referenceSkinMode) {
                                        hybridBExp = 1.62;
                                        hybridThetaExp = 2.18;
                                    }
                                    hybridSkinGate = clamp(
                                        pow(max(hybridRhoProxy, 1.0e-4), 0.55)
                                        * pow(max(hybridBProxy, 1.0e-4), hybridBExp)
                                        * pow(max(hybridThetaProxy, 1.0e-4), hybridThetaExp)
                                        * hybridHeating
                                        * hybridSkinLayer
                                        * hybridInnerGate,
                                        0.0,
                                        1.0
                                    ) * hybridSkinVisibleSupport;
                                    float hybridSkinOpacityAnchor = max(comps.aBase * thermalAbsorptionWeight * radialThermalWeight, 1.0e-30);
                                    hybridSkinUnit = max(P.diskGrmhdEmissionScale, 0.0)
                                                   * hybridSkinOpacityAnchor
                                                   * hybridSkinSource
                                                   * thermalEmissionWeight;
                                    float hybridCoronaLayer = smoothstep(0.75, 2.0, hybridLayerCoord);
                                    float hybridCoronaInner = 1.0 / (1.0 + pow(max(rRs / 20.0, 0.0), 2.5));
                                    hybridCoronaGate = clamp(
                                        pow(max(residualMagGate, 1.0e-4), 0.92)
                                        * pow(max(residualHotGate, 1.0e-4), 0.82)
                                        * (0.20 + 0.80 * hybridPositiveResidual)
                                        * hybridCoronaLayer
                                        * hybridCoronaInner
                                        * coronaLayerWeight,
                                        0.0,
                                        1.0
                                    );
                                    if (referenceSkinMode) {
                                        hybridCoronaGate = clamp(
                                            pow(max(residualMagGate, 1.0e-4), 0.95)
                                            * pow(max(residualHotGate, 1.0e-4), 0.85)
                                            * (0.16 + 0.84 * hybridPositiveResidual)
                                            * hybridCoronaLayer
                                            * hybridCoronaInner
                                            * coronaLayerWeight,
                                            0.0,
                                            1.0
                                        );
                                    }
                                }
                                float smoothBodyFloorWeight = 0.08 * bodyProxy * denseBodyGate;
                                float thermalContinuumLocalWeight = 1.0;
                                switch (P.grmhdSmoothWeightMode) {
                                    case 1u:
                                        thermalContinuumLocalWeight = smoothStateWeight;
                                        break;
                                    case 2u:
                                        thermalContinuumLocalWeight = 0.0;
                                        break;
                                    case 3u:
                                        thermalContinuumLocalWeight = smoothBodyFloorWeight + 0.12 * smoothStateWeight * bodyProxy;
                                        break;
                                    case 4u:
                                        // Plasma-body mode keeps the old LTE-like
                                        // continuum only as a very weak disk-body
                                        // support term. Most broad luminosity comes
                                        // from the explicit photospheric body branch
                                        // below, so this cannot become a global
                                        // white wash.
                                        thermalContinuumLocalWeight = 0.22 * smoothBodyFloorWeight + 0.022 * smoothStateWeight * bodyProxy;
                                        break;
                                    case 5u:
                                        // Positive-emissive mode keeps the old
                                        // continuum even weaker: broad brightness
                                        // should come from body photons and
                                        // positive hot-skin emission, not from a
                                        // material-like smooth wash.
                                        thermalContinuumLocalWeight = 0.15 * smoothBodyFloorWeight + 0.015 * smoothStateWeight * bodyProxy;
                                        break;
                                    case 6u:
                                    case 7u:
                                    case 8u:
	                                    case 9u:
	                                        // Hot-skin modes use an independent
	                                        // optically-thin emissivity proxy for
	                                        // filament structure. Keep the historical
	                                        // smooth branch as weak body support only.
	                                        thermalContinuumLocalWeight = 0.16 * smoothBodyFloorWeight + 0.016 * smoothStateWeight * bodyProxy;
	                                        break;
		                                    case 10u:
		                                    case 11u:
		                                    case 12u:
		                                    case 13u:
		                                    case 14u:
		                                    case 15u:
		                                        // Hybrid visible disk mode replaces the
		                                        // historical smooth GRMHD continuum with
		                                        // an explicit analytic photospheric body.
	                                        thermalContinuumLocalWeight = 0.0;
	                                        break;
	                                    default:
	                                        thermalContinuumLocalWeight = 1.0;
	                                        break;
	                                }
                                float smoothContinuumScale = (P.grmhdSmoothWeightMode >= 2u)
                                    ? 1.0
                                    : max(P.grmhdSmoothEmissionScale, 0.0);
                                jThermalSmoothEff = jThermalContinuum * thermalContinuumBaseWeight * thermalContinuumLocalWeight;
                                jThermalSmoothEff *= smoothContinuumScale;
		                                float skinScale = (P.grmhdSmoothWeightMode == 2u || P.grmhdSmoothWeightMode == 3u || plasmaBodySkinMode || positivePlasmaMode || hotSkinMode || analyticBodySkinMode)
	                                    ? 1.12
	                                    : 1.0;
		                                if (plasmaBodySkinMode || positivePlasmaMode || hotSkinMode || analyticBodySkinMode) {
                                    // Structured skin is an emitting hot/shear layer,
                                    // not an albedo texture. These bounded factors
                                    // are all local GRMHD-state proxies: hot electron
                                    // support, magnetic/dynamic residual support, and
                                    // vertical transition-layer support.
                                    float skinLayerGate = clamp(0.58 + 0.42 * smoothstep(0.18, 1.25, bodyLayerCoord), 0.58, 1.0);
                                    float skinHotSupport = 0.58 + 0.42 * residualHotGate;
                                    float skinStressSupport = 0.62 + 0.38 * max(residualMagGate, residualDynamicGate);
                                    float skinEmissionSupport = clamp(skinLayerGate * skinHotSupport * skinStressSupport, 0.44, 1.28);
                                    float skinPatternSoftener = clamp(
                                        pow(max(gatedDataFlowMod, 1.0e-6), 1.50)
                                        * pow(max(emissionFilamentMod, 1.0e-6), 2.58)
                                        * pow(max(thermalFillingMod, 1.0e-6), 1.12),
                                        0.035,
                                        7.20
                                    );
	                                    if (analyticBodySkinMode) {
	                                        // GRMHD-driven hot skin in hybrid visible
	                                        // disk mode. This is an independent
	                                        // optically-thin emissivity term, not a
	                                        // texture multiplier on the analytic
	                                        // photospheric body.
	                                        float hybridFilamentBoost = referenceSkinMode
	                                            ? clamp(
	                                                0.86
	                                                + 0.52 * smoothstep(0.04, 0.92, max(dataFlowResidualLog, 0.0) * smoothstep(0.025, 0.82, dataFlowResidualAmp))
	                                                + 0.52 * max(residualStressGate, residualMagGate)
	                                                + 0.22 * residualHotGate,
	                                                0.84,
	                                                1.85
	                                            )
	                                            : clamp(
	                                                0.92
	                                                + 1.18 * smoothstep(0.04, 0.92, max(dataFlowResidualLog, 0.0) * smoothstep(0.025, 0.82, dataFlowResidualAmp))
	                                                + 0.44 * max(residualStressGate, residualMagGate),
	                                                0.88,
	                                                2.25
	                                            );
	                                        float hybridSkinCoeff = referenceSkinMode ? 0.072 : ((P.grmhdSmoothWeightMode == 12u || P.grmhdSmoothWeightMode == 13u) ? 0.052 : 0.040);
	                                        jThermalCloudEff = max(hybridSkinUnit * hybridSkinCoeff * hybridSkinGate * hybridFilamentBoost, 0.0);
	                                    } else if (hotSkinMode) {
	                                        // Independent optically-thin hot-skin
	                                        // emissivity proxy:
	                                        // j_skin_hot ∝ rho^a B^b thetae^c heating layer.
                                        // This branch is additive and weakly
                                        // absorbed by the common transfer only;
                                        // it does not modulate or subtract from
                                        // the photospheric body.
                                        float residualAmp = smoothstep(0.035, 0.90, dataFlowResidualAmp);
                                        float positiveResidual = smoothstep(0.02, 0.92, max(dataFlowResidualLog, 0.0) * residualAmp);
                                        float skinLayer = smoothstep(0.16, 0.82, bodyLayerCoord)
                                                        * (1.0 - smoothstep(3.20, 5.80, bodyLayerCoord));
                                        skinLayer = clamp(0.20 + 0.80 * skinLayer, 0.20, 1.0);
                                        float innerSkinGate = 1.0 / (1.0 + pow(max(rRs / 48.0, 0.0), 1.55));
                                        float rhoProxy = clamp(sqrt(max(thermalizedGate * diskLikeGate, 0.0)), 0.0, 1.0);
                                        float bProxy = clamp(0.18 + 0.82 * residualMagGate, 0.0, 1.0);
                                        float thetaProxy = clamp(0.16 + 0.84 * residualHotGate, 0.0, 1.0);
                                        float heatingProxy = clamp(
                                            0.20
                                            + 0.40 * positiveResidual
                                            + 0.28 * residualStressGate
                                            + 0.22 * residualMagGate
                                            + 0.16 * residualHotGate,
                                            0.0,
                                            1.24
                                        );
                                        float aExp = 0.58;
                                        float bExp = 1.35;
                                        float cExp = 2.05;
                                        if (P.grmhdSmoothWeightMode == 7u) {
                                            bExp = 1.85;
                                            cExp = 1.75;
                                        } else if (P.grmhdSmoothWeightMode == 8u) {
                                            bExp = 1.18;
                                            cExp = 2.85;
                                        } else if (P.grmhdSmoothWeightMode == 9u) {
                                            bExp = 1.42;
                                            cExp = 2.10;
                                        }
                                        float hotSkinProxy = clamp(
                                            pow(max(rhoProxy, 1.0e-4), aExp)
                                            * pow(max(bProxy, 1.0e-4), bExp)
                                            * pow(max(thetaProxy, 1.0e-4), cExp)
                                            * heatingProxy
                                            * skinLayer
                                            * innerSkinGate,
                                            0.0,
                                            0.95
                                        );
                                        float hotFilamentBoost = clamp(
                                            1.0
                                            + 1.25 * positiveResidual
                                            + 0.42 * max(residualStressGate, residualMagGate),
                                            0.90,
                                            2.20
                                        );
                                        jThermalCloudEff = max(
                                            jThermalBaseRef
                                            * 0.0042
                                            * hotSkinProxy
                                            * hotFilamentBoost,
                                            0.0
                                        );
                                    } else if (positivePlasmaMode) {
                                        // Positive-only skin: underdense/negative
                                        // residuals should not carve dark grooves
                                        // into the body. They simply fail to add
                                        // skin light. Compression, magnetic stress,
                                        // and hot-electron support add photons.
                                        float residualAmp = smoothstep(0.035, 0.90, dataFlowResidualAmp);
                                        float positiveResidual = smoothstep(0.02, 0.88, max(dataFlowResidualLog, 0.0) * residualAmp);
                                        float positiveStress = max(max(residualMagGate, residualDynamicGate), residualHotGate);
                                        float positiveSkinGate = clamp(
                                            (0.35 + 0.65 * positiveResidual)
                                            * (0.55 + 0.45 * positiveStress)
                                            * skinLayerGate,
                                            0.22,
                                            1.24
                                        );
                                        float positivePattern = clamp(1.0 + 0.45 * max(skinPatternSoftener - 1.0, 0.0), 1.0, 3.20);
                                        float positiveFilamentBoost = clamp(
                                            1.0
                                            + 1.65 * positiveResidual * positiveStress
                                            + 0.38 * max(residualHotGate, residualMagGate),
                                            0.85,
                                            2.85
                                        );
                                        float positiveSkinSource = comps.sourceThermal * max(1.0, cloudSourceMod);
                                        float positiveJCloudThin = disk_grmhd_thermal_thin_cloud_emissivity(
                                            r, zNorm, rho, thetae, bVec, positiveSkinSource, jThermalBaseRef,
                                            max(gatedDataFlowMod, 1.0), dataFlowResidualAmp, P
                                        );
                                        float positiveHotFilament = jThermalBaseRef
                                            * 0.0048
                                            * positiveResidual
                                            * positiveStress
                                            * skinLayerGate
                                            * (0.65 + 0.35 * residualHotGate);
                                        jThermalCloudEff = max(
                                            positiveJCloudThin * positiveSkinGate * positivePattern * positiveFilamentBoost
                                            + positiveHotFilament,
                                            0.0
                                        );
                                    } else {
                                        jThermalCloudEff = max(jCloudThin * skinPatternSoftener * skinEmissionSupport, 0.0);
                                    }
                                }
	                                float nuRefVisible = P.c / max(550.0e-9, 1e-30);
	                                float branchNuRatio = clamp(nuObs / max(nuRefVisible, 1e6), 0.35, 2.10);
	                                float bodySpectralTilt = positivePlasmaMode ? pow(branchNuRatio, -0.04) : 1.0;
	                                float skinSpectralTilt = (positivePlasmaMode || hotSkinMode || analyticBodySkinMode) ? pow(branchNuRatio, 0.20 + 0.16 * residualHotGate + ((hotSkinMode || analyticBodySkinMode) ? 0.10 : 0.0)) : 1.0;
	                                float coronaSpectralTilt = (positivePlasmaMode || hotSkinMode || analyticBodySkinMode) ? pow(branchNuRatio, (hotSkinMode || analyticBodySkinMode) ? 0.58 : 0.44) : 1.0;
	                                jThermalCloudEff *= skinScale * max(P.grmhdCloudEmissionScale, 0.0) * skinSpectralTilt;
	                                if (P.grmhdSmoothWeightMode == 2u || P.grmhdSmoothWeightMode == 3u || plasmaBodySkinMode || positivePlasmaMode || hotSkinMode || analyticBodySkinMode) {
                                    float bodyScaleArg = max(P.grmhdSmoothEmissionScale, 0.0);
                                    float bodyRadianceScale = hotSkinMode ? 0.0124 : (positivePlasmaMode ? 0.0128 : (plasmaBodySkinMode ? 0.0127 : ((P.grmhdSmoothWeightMode == 3u) ? 0.012 : 0.010)));
                                    float bodyStateSupport = (P.grmhdSmoothWeightMode == 3u)
                                        ? (0.68 + 0.20 * smoothStateWeight)
                                        : ((plasmaBodySkinMode || positivePlasmaMode || hotSkinMode) ? (0.70 + 0.20 * smoothStateWeight) : 1.0);
                                    float skinCompetition = clamp(
                                        smoothstep(0.95, 2.20, gatedDataFlowMod)
                                        * (0.30 + 0.70 * residualDynamicGate)
                                        * (0.25 + 0.75 * residualMagGate),
                                        0.0,
                                        1.0
                                    );
                                    float bodyGap = clamp(1.0 - 0.72 * skinCompetition, 0.18, 1.0);
                                    if (plasmaBodySkinMode) {
                                        bodyGap = clamp(1.0 - 0.58 * skinCompetition, 0.30, 1.0);
                                    }
                                    if (positivePlasmaMode) {
                                        // Skin is additive emission in this mode;
                                        // keep the photospheric body from being
                                        // carved away where skin activity is high.
                                        bodyGap = clamp(1.0 - 0.10 * skinCompetition, 0.88, 1.0);
                                    }
	                                    if (hotSkinMode) {
	                                        // The hot skin is an independent emitter,
	                                        // not a displacement map on the body.
	                                        bodyGap = clamp(1.0 - 0.08 * skinCompetition, 0.90, 1.0);
	                                    }
		                                    if (analyticBodySkinMode) {
	                                        // The analytic body is not carved by GRMHD
	                                        // residuals; skin adds photons above it.
	                                        bodyGap = 1.0;
	                                    }
                                    float bodyOpticalSupport = sqrt(max(opticalBodyGate * (0.55 + 0.45 * thermalizedGate), 0.0));
                                    float bodyThermalStructure = 1.0;
                                    if (plasmaBodySkinMode) {
                                        bodyThermalStructure = clamp(
                                            pow(max(gatedDataFlowMod, 1.0e-6), 0.18)
                                            * pow(max(cloudSourceMod, 1.0e-6), 0.16)
                                            * pow(max(thermalFillingMod, 1.0e-6), 0.13)
                                            * (0.86 + 0.14 * residualHotGate),
                                            0.72,
                                            1.42
                                        );
                                    }
                                    if (positivePlasmaMode) {
                                        bodyThermalStructure = clamp(
                                            pow(max(gatedDataFlowMod, 1.0), 0.08)
                                            * pow(max(cloudSourceMod, 1.0), 0.08)
                                            * (0.94 + 0.06 * residualHotGate),
                                            0.92,
                                            1.24
                                        );
                                    }
	                                    if (hotSkinMode) {
	                                        bodyThermalStructure = clamp(
	                                            pow(max(gatedDataFlowMod, 1.0), 0.045)
	                                            * (0.97 + 0.03 * residualHotGate),
	                                            0.94,
	                                            1.16
	                                        );
	                                    }
	                                    if (analyticBodySkinMode) {
	                                        bodyThermalStructure = 1.0;
	                                    }
	                                    float bodyBaseRef = jThermalBaseRef;
	                                    if (positivePlasmaMode || hotSkinMode) {
                                        // Body color/intensity should be a deep
                                        // local photospheric source, not a dimmed
                                        // negative-residual texture. Use the
                                        // uncarved thermal source and only allow
                                        // positive flow contrast to raise it.
                                        bodyBaseRef = max(P.diskGrmhdEmissionScale, 0.0)
                                            * aBaseEmit
                                            * comps.sourceThermal
	                                            * thermalEmissionWeight
	                                            * mix(1.0, max(flowContrast, 1.0), hotSkinMode ? 0.12 : 0.25);
	                                    }
		                                    if (analyticBodySkinMode) {
		                                        float hybridBodyCoeff = referenceSkinMode ? 0.215
		                                                              : ((P.grmhdSmoothWeightMode == 11u) ? 0.205
		                                                              : ((P.grmhdSmoothWeightMode == 12u || P.grmhdSmoothWeightMode == 13u) ? 0.175 : 0.190));
	                                        jThermalBodyEff = max(
	                                            hybridBodyUnit
	                                            * hybridBodyCoeff
	                                            * hybridBodyGate
	                                            * bodyScaleArg,
	                                            0.0
	                                        );
	                                    } else {
	                                        jThermalBodyEff = bodyBaseRef
	                                            * bodyRadianceScale
	                                            * bodyProxy
	                                            * bodyGap
	                                            * bodyOpticalSupport
	                                            * bodyStateSupport
	                                            * bodyThermalStructure
	                                            * bodySpectralTilt
	                                            * bodyScaleArg;
	                                    }
                                    float coronaHotGate = smoothstep(0.30, 5.5, residualThetaRatio);
                                    float coronaOffMidplaneGate = smoothstep(0.45, 1.30, bodyLayerCoord);
                                    float coronaGate = clamp(
                                        pow(max(residualMagGate, 1.0e-4), 0.80)
                                        * pow(max(coronaHotGate, 1.0e-4), 0.70)
                                        * (0.12 + 0.88 * coronaOffMidplaneGate)
                                        * coronaLayerWeight,
                                        0.0,
                                        1.0
                                    );
                                    if (positivePlasmaMode || hotSkinMode) {
                                        float innerCoronaGate = 1.0 / (1.0 + pow(max(rRs / 18.0, 0.0), 2.40));
                                        float coronaThinSupport = clamp(0.18 + 0.82 * (1.0 - bodyProxy), 0.08, 1.0);
                                        float coronaSourceBoost = clamp(max(residualHotGate, residualMagGate), 0.0, 1.0);
                                        coronaGate = clamp(coronaGate * innerCoronaGate * coronaThinSupport * coronaSourceBoost, 0.0, 1.0);
                                    }
		                                    if (analyticBodySkinMode) {
		                                        float hybridCoronaCoeff = referenceSkinMode ? (referenceSkinCoronaMode ? 0.0032 : 0.0)
		                                                                                  : (hybridVisibleCoronaMode ? 0.0060 : 0.0);
	                                        jThermalCoronaEff = max(
	                                            hybridSkinUnit
	                                            * hybridCoronaCoeff
	                                            * hybridCoronaGate
	                                            * max(P.grmhdCloudEmissionScale, 0.0)
	                                            * coronaSpectralTilt,
	                                            0.0
	                                        );
	                                    } else {
	                                        jThermalCoronaEff = comps.jThin * coronaGate * (hotSkinMode ? (hotSkinCoronaMode ? 0.10 : 0.0) : (positivePlasmaMode ? 0.08 : (plasmaBodySkinMode ? 0.20 : 0.28))) * coronaSpectralTilt;
	                                    }
                                    if (positivePlasmaMode) {
                                        float coronaThermalAccent = jThermalBaseRef
                                            * 0.00022
                                            * coronaGate
                                            * (0.35 + 0.65 * max(residualHotGate, residualMagGate))
                                            * max(P.grmhdCloudEmissionScale, 0.0)
                                            * coronaSpectralTilt;
                                        jThermalCoronaEff += max(coronaThermalAccent, 0.0);
                                    }
                                    if (hotSkinCoronaMode) {
                                        float coronaThermalAccent = jThermalBaseRef
                                            * 0.00018
                                            * coronaGate
                                            * (0.25 + 0.75 * max(residualHotGate, residualMagGate))
                                            * max(P.grmhdCloudEmissionScale, 0.0)
                                            * coronaSpectralTilt;
                                        jThermalCoronaEff += max(coronaThermalAccent, 0.0);
                                    }
                                    jCom = jThermalBodyEff + jThermalCloudEff + jThermalCoronaEff + jThermalSmoothEff;
                                    jThermalEff = jThermalBodyEff + jThermalCloudEff;
                                    jThinEff = jThermalCoronaEff;
                                } else {
                                    jThermalBodyEff = 0.0;
                                    jThermalCoronaEff = 0.0;
                                    jCom = jThermalSmoothEff + jThermalCloudEff;
                                    jThermalEff = jCom;
                                    jThinEff = 0.0;
                                }
                                if (P.grmhdBranchIsolationMode == 1u) {
                                    jCom = jThermalSmoothEff;
                                    jThermalEff = jThermalSmoothEff;
                                    jThinEff = 0.0;
                                    jThermalBodyEff = 0.0;
                                    jThermalCloudEff = 0.0;
                                    jThermalCoronaEff = 0.0;
                                } else if (P.grmhdBranchIsolationMode == 2u) {
                                    jCom = jThermalCloudEff;
                                    jThermalEff = jThermalCloudEff;
                                    jThinEff = 0.0;
                                    jThermalSmoothEff = 0.0;
                                    jThermalBodyEff = 0.0;
                                    jThermalCoronaEff = 0.0;
                                } else if (P.grmhdBranchIsolationMode == 3u) {
                                    jCom = jThermalBodyEff;
                                    jThermalEff = jThermalBodyEff;
                                    jThinEff = 0.0;
                                    jThermalSmoothEff = 0.0;
                                    jThermalCloudEff = 0.0;
                                    jThermalCoronaEff = 0.0;
                                } else if (P.grmhdBranchIsolationMode == 4u) {
                                    jCom = jThermalCloudEff;
                                    jThermalEff = jThermalCloudEff;
                                    jThinEff = 0.0;
                                    jThermalSmoothEff = 0.0;
                                    jThermalBodyEff = 0.0;
                                    jThermalCoronaEff = 0.0;
                                } else if (P.grmhdBranchIsolationMode == 5u) {
                                    jCom = jThermalCoronaEff;
                                    jThermalEff = 0.0;
                                    jThinEff = jThermalCoronaEff;
                                    jThermalSmoothEff = 0.0;
                                    jThermalBodyEff = 0.0;
                                    jThermalCloudEff = 0.0;
                                }
                                A.maxBodyProxy = max(A.maxBodyProxy, bodyProxy);
                                A.maxJThermalBody = max(A.maxJThermalBody, jThermalBodyEff);
                                A.maxJThermalCloud = max(A.maxJThermalCloud, jThermalCloudEff);
                                A.maxJThermalCorona = max(A.maxJThermalCorona, jThermalCoronaEff);
                                if (k == 0u) {
                                    A.intJThermalBody += jThermalBodyEff * ds;
                                    A.intJThermalCloud += jThermalCloudEff * ds;
                                    A.intJThermalCorona += jThermalCoronaEff * ds;
                                    A.intJThermalWeighted += max(jThermalEff, 0.0) * ds;
                                    A.intAlphaThermalPost += max(aCom, 0.0) * ds;
                                }
                            } else {
                                jCom = comps.jTotal * flowContrast * coronaLayerWeight;
                                aCom = comps.aTotal * mix(1.0, flowContrast, 0.35) * coronaLayerWeight;
                                jThermalEff = 0.0;
                                jThinEff = jCom;
                            }
                        }
                    }

                    aCom *= max(P.grmhdTransportAlphaScale, 0.0);

                    float jObs = (jCom * g * g) * aniso;
                    float aObs = aCom / max(g, 1e-8);
                    float iPrev = cieQuadratureVisible ? volume_visible_band_get(A, k) : A.IVisNu[k];
                    float qPrev = cieQuadratureVisible ? 0.0 : A.QVisNu[k];
                    float uPrev = cieQuadratureVisible ? 0.0 : A.UVisNu[k];
                    float vPrev = cieQuadratureVisible ? 0.0 : A.VVisNu[k];
                    if (!(isfinite(jObs) && isfinite(aObs) && isfinite(iPrev))) {
                        A.invalidSamples += 1u;
                        continue;
                    }
                    maxJObs = max(maxJObs, jObs);
                    A.maxAlpha = max(A.maxAlpha, max(aObs, 0.0));
                    volume_accum_note_transfer(A, jObs, aObs, 0.0, 0.0, r, ds, P);
                    float jQ = polarized ? (p0 * jObs * cos2psi) : 0.0;
                    float jU = polarized ? (p0 * jObs * sin2psi) : 0.0;
                    float jV = 0.0;
                    float iNext = iPrev;
                    float qNext = qPrev;
                    float uNext = uPrev;
                    float vNext = vPrev;
                    if (aObs > 1e-12) {
                        float dTau = min(aObs * ds, 40.0);
                        float srcI = jObs / max(aObs, 1e-30);
                        float srcQ = jQ / max(aObs, 1e-30);
                        float srcU = jU / max(aObs, 1e-30);
                        float srcV = jV / max(aObs, 1e-30);
                        if (tauSurfaceVisible) {
                            float tauBefore = A.tauVis[k];
                            volume_accum_note_transfer(A, jObs, aObs, tauBefore, dTau, r, ds, P);
                            if (tauBefore < 1.0 && tauBefore + dTau >= 1.0) {
                                // Eddington-Barbier-style surface approximation:
                                // once a wavelength reaches tau~=1, use the local
                                // source function as the emergent photospheric I_nu.
                                iNext = max(srcI, 0.0);
                                qNext = srcQ;
                                uNext = srcU;
                                vNext = srcV;
                                A.tauSurfaceMask |= (1u << k);
                                A.tauVis[k] = max(tauBefore + dTau, 1.0);
                            } else {
                                float trans = exp(-dTau);
                                iNext = iPrev * trans + srcI * (1.0 - trans);
                                qNext = qPrev * trans + srcQ * (1.0 - trans);
                                uNext = uPrev * trans + srcU * (1.0 - trans);
                                vNext = vPrev * trans + srcV * (1.0 - trans);
                                A.tauVis[k] += dTau;
                            }
                        } else if (cieQuadratureVisible) {
                            float trans = exp(-dTau);
                            iNext = iPrev * trans + srcI * (1.0 - trans);
                            qNext = qPrev * trans + srcQ * (1.0 - trans);
                            uNext = uPrev * trans + srcU * (1.0 - trans);
                            vNext = vPrev * trans + srcV * (1.0 - trans);
                            if (k == 4u) {
                                float tauBeforeY = A.tauVis.y;
                                volume_accum_note_transfer(A, jObs, aObs, tauBeforeY, dTau, r, ds, P);
                                A.tauVis.y += dTau;
                            }
                            A.tau = max(A.tau, A.tauVis.y);
                        } else {
                            float trans = exp(-dTau);
                            iNext = iPrev * trans + srcI * (1.0 - trans);
                            qNext = qPrev * trans + srcQ * (1.0 - trans);
                            uNext = uPrev * trans + srcU * (1.0 - trans);
                            vNext = vPrev * trans + srcV * (1.0 - trans);
                            if (k == 1u) {
                                float tauBeforeG = A.tauVis[k];
                                volume_accum_note_transfer(A, jObs, aObs, tauBeforeG, dTau, r, ds, P);
                            }
                            A.tauVis[k] += dTau;
                        }
                    } else {
                        iNext = iPrev + jObs * ds;
                        qNext = qPrev + jQ * ds;
                        uNext = uPrev + jU * ds;
                        vNext = vPrev + jV * ds;
                    }

	                    if (cieQuadratureVisible) {
	                        volume_visible_band_set(A, k, iNext);
	                        float xBar, yBar, zBar;
	                        volume_cie_xyz_bar(lamNmK, xBar, yBar, zBar);
	                        float dINu = max(iNext - iPrev, 0.0);
	                        if (k == 4u) {
	                            float denomBranch = max(jThermalBodyEff + jThermalCloudEff + jThermalCoronaEff + jThermalSmoothEff, 1e-30);
	                            A.intIThermal += dINu * clamp((jThermalBodyEff + jThermalCloudEff + jThermalSmoothEff) / denomBranch, 0.0, 1.0);
	                            A.intIThermalBody += dINu * clamp(jThermalBodyEff / denomBranch, 0.0, 1.0);
	                            A.intIThin += dINu * clamp(jThinEff / denomBranch, 0.0, 1.0);
	                            A.intIThermalCloud += dINu * clamp(jThermalCloudEff / denomBranch, 0.0, 1.0);
	                            A.intIThermalCorona += dINu * clamp(jThermalCoronaEff / denomBranch, 0.0, 1.0);
                                float rRs = r / max(P.rs, 1e-6);
                                float layer = abs(zNorm) / max(rRs, 1e-4);
                                A.emissHeight += dINu * abs(zNorm);
                                A.emissLayer += dINu * layer;
                                A.emissWeight += dINu;
                                A.emissBodyLayerGate += dINu * bodyProxy;
		                        }
	                        float dILam = dINu * P.c / max(lamMK * lamMK, 1e-30);
	                        dYVis += dILam * yBar * ((400.0 / 9.0) * 1e-9);
	                    } else {
                        A.IVisNu[k] = iNext;
                        A.QVisNu[k] = qNext;
                        A.UVisNu[k] = uNext;
                        A.VVisNu[k] = vNext;
	                        if (k == 1u) {
	                            float dINu = max(iNext - iPrev, 0.0);
	                            float denomBranch = max(jThermalBodyEff + jThermalCloudEff + jThermalCoronaEff + jThermalSmoothEff, 1e-30);
	                            A.intIThermal += dINu * clamp((jThermalBodyEff + jThermalCloudEff + jThermalSmoothEff) / denomBranch, 0.0, 1.0);
	                            A.intIThermalBody += dINu * clamp(jThermalBodyEff / denomBranch, 0.0, 1.0);
	                            A.intIThin += dINu * clamp(jThinEff / denomBranch, 0.0, 1.0);
	                            A.intIThermalCloud += dINu * clamp(jThermalCloudEff / denomBranch, 0.0, 1.0);
	                            A.intIThermalCorona += dINu * clamp(jThermalCoronaEff / denomBranch, 0.0, 1.0);
                                float rRs = r / max(P.rs, 1e-6);
                                float layer = abs(zNorm) / max(rRs, 1e-4);
                                A.emissHeight += dINu * abs(zNorm);
                                A.emissLayer += dINu * layer;
                                A.emissWeight += dINu;
                                A.emissBodyLayerGate += dINu * bodyProxy;
		                        }
	                    }

                    if (polarized && !cieQuadratureVisible) {
                        float nuSafe = max(nuComov, 1e6);
                        float rhoV = P.diskFaradayRotScale * rho * bPar / (nuSafe * nuSafe);
                        float chi = clamp(rhoV * ds, -0.6, 0.6);
                        float cr = cos(2.0 * chi);
                        float sr = sin(2.0 * chi);
                        float qNow = A.QVisNu[k];
                        float uNow = A.UVisNu[k];
                        A.QVisNu[k] = qNow * cr - uNow * sr;
                        A.UVisNu[k] = qNow * sr + uNow * cr;

                        float rhoQ = P.diskFaradayConvScale * rho * bProjMag / max(nuSafe * nuSafe * nuSafe, 1e12);
                        float eta = clamp(rhoQ * ds, -0.5, 0.5);
                        float cc = cos(2.0 * eta);
                        float sc = sin(2.0 * eta);
                        float uMix = A.UVisNu[k];
                        float vMix = A.VVisNu[k];
                        A.UVisNu[k] = uMix * cc - vMix * sc;
                        A.VVisNu[k] = uMix * sc + vMix * cc;
                    }
                }
                if (cieQuadratureVisible) {
                    dI = dYVis;
                    A.I += max(dYVis, 0.0);
                }
                A.maxJ = max(A.maxJ, maxJObs);
                if (!cieQuadratureVisible) {
                    float3 dINuVis = max(A.IVisNu - iPrevNu, float3(0.0));
                    float dIVis = dot(dINuVis, float3(0.13344, 0.85742, 0.00914));
                    dI = expressiveVisible ? dIRef : dIVis;
                }
                if (!cieQuadratureVisible && volume_finalize_grmhd_visible_sample(
                        expressiveVisible, polarized, rho, thetae, bVec, g, r, vR,
                        pos, obs, P,
                        iPrevNu, qPrevNu, uPrevNu, vPrevNu, A, dI)) {
                    break;
                }
            } else {
                volume_integrate_grmhd_scalar_sample(rho, thetae, bVec, g, r, ds, P, A, dI);
            }

            if (volume_finalize_grmhd_sample_tail(
                    rho, thetae, length(bVec), g, r, vR,
                    texLocal, texStrength, pos, obs, A,
                    prevRhoVolume, prevThetaeVolume, prevBVolume, havePrevVolumeSample, dI)) {
                break;
            }
            continue;
        }

        float4 vol = disk_sample_volume_legacy(rNorm, phi, zNorm, P, diskVol0Tex);
        float tempScale = clamp(vol.x, 0.02, 40.0);
        float density = pow(clamp(vol.y, 0.0, 1.0), 0.65);
        float vrRatio = clamp(vol.z, -1.0, 1.0);
        float vphiScale = clamp(vol.w, 0.0, 4.0);
        if (!(density > 1e-5)) continue;

        float transportGate = verticalEdgeGate * radialEdgeGate;
        float coverage = clamp(P.diskCloudCoverage, 0.0, 1.0);
        float porosity = clamp(P.diskCloudPorosity, 0.0, 1.0);
        // In physical-flow volume mode, the imported/procedural volume is the
        // transport state. Avoid adding a second layer of random cloud/perlin
        // modulation that would turn disk-space fluid structure into a texture.
        bool dataDrivenVolume = (FC_PHYSICS_MODE == 2u && P.diskVolumeFormat == 0u && P.diskVolumeMode != 0u);
        float cloudSharp = clamp(density, 0.0, 1.0);
        float clumpGate = cloudSharp;
        float densityEff = density * transportGate;
        if (!dataDrivenVolume) {
            float cloudFlow = disk_cloud_noise(r, phi, pos.z, P.c * P.diskFlowTime + 0.12 * r, P);
            float cloudPerlin = 0.5 + 0.5 * disk_perlin_texture_noise(r, phi + 0.19 * P.diskFlowTime, pos.z, P);
            float cloudLocal = clamp(0.58 * cloudFlow + 0.42 * cloudPerlin, 0.0, 1.0);
            cloudSharp = pow(cloudLocal, mix(2.0, 1.15, coverage));
            clumpGate = smoothstep(max(0.0, 1.0 - coverage), 1.0, cloudSharp);
            float sparseGate = smoothstep(0.68 - 0.30 * coverage,
                                          0.96 - 0.18 * coverage,
                                          cloudSharp);
            float voidGate = porosity * (1.0 - clumpGate);
            densityEff = density
                       * mix(0.30, 1.08, clumpGate * clumpGate)
                       * mix(0.22, 1.0, sparseGate * sparseGate * sparseGate)
                       * (1.0 - 0.40 * voidGate)
                       * transportGate;
        }
        float innerX = clamp((r - diskInner) / max(0.45 * diskInner, 1e-6), 0.0, 1.0);
        float innerGate = smoothstep(0.0, 1.0, innerX);
        densityEff *= (0.25 + 0.75 * innerGate);
        if (!dataDrivenVolume) {
            float voidNoise = fbm(float3(rNorm * 4.6, phi * 10.8, zNorm * 6.2 + 0.45 * P.diskFlowTime));
            float coherentVoid = smoothstep(0.46, 0.83, voidNoise);
            densityEff *= mix(1.0, coherentVoid, 0.30 * porosity);
            float spiral = 0.5 + 0.5 * sin(12.0 * phi + 5.0 * log(max(rNorm, 1.0)));
            float filament = smoothstep(0.56, 0.92, spiral);
            densityEff *= mix(1.0, 0.52 + 0.48 * filament, 0.18);
            densityEff = max(densityEff, 0.06 * density);
        }
        if (!(densityEff > 1e-5)) continue;

        float g = 1.0;
        if (FC_METRIC == 0) {
            float massLen = 0.5 * P.rs;
            float rM = r / max(massLen, 1e-12);
            float betaRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
            float betaRCoord = vrRatio * betaRef;
            float betaPhiCoord = -vphiScale * betaRef;
            if (FC_PHYSICS_MODE != 0u && r < diskInner * (1.0 - 1e-4)) {
                float rMsM = diskInner / max(massLen, 1e-12);
                float betaR = 0.0;
                float betaPhi = 0.0;
                if (disk_schwarzschild_plunge_local_beta(rM, rMsM, betaR, betaPhi)) {
                    betaRCoord = betaR;
                    betaPhiCoord = betaPhi;
                }
            }
            float4 rayDeriv = mix(rayV0, rayV1, t);
            float rObs = max(length(P.camPos), 1.0001 * P.rs);
            g = disk_schwarzschild_direct_gfactor(r,
                                                  rObs,
                                                  rayDeriv,
                                                  betaRCoord,
                                                  betaPhiCoord,
                                                  P);
        } else {
            float massLen = 0.5 * P.rs;
            float rM = r / max(massLen, 1e-12);
            float a = clamp(P.spin, -0.999, 0.999);
            float diskInnerM = diskInner / max(massLen, 1e-12);

            float omegaK = 1.0 / max(pow_1p5(rM) + a, 1e-8);
            float omega = omegaK * vphiScale;
            float drdt = vrRatio * sqrt(1.0 / max(rM, 1.0));
            if (FC_PHYSICS_MODE != 0u && rM < diskInnerM * (1.0 - 1e-4)) {
                float plungeOmega = omega;
                float plungeDrdt = drdt;
                float plungeVrRatio = vrRatio;
                if (disk_kerr_plunge_kinematics(rM, diskInnerM, a, plungeOmega, plungeDrdt, plungeVrRatio)) {
                    omega = plungeOmega;
                    drdt = plungeDrdt;
                }
            }

            float prRay = mix(pr0, pr1, t);
            if (!disk_kerr_flow_gfactor(rM, a, omega, drdt, LzConst, prRay, g)) {
                drdt = 0.0;
                if (!disk_kerr_flow_gfactor(rM, a, omega, drdt, LzConst, prRay, g)) {
                    g = 1.0;
                }
            }
        }
        if (!isfinite(g)) g = 1.0;

        float TBackbone = dataDrivenVolume ? disk_visible_teff(r, P)
                                           : disk_effective_temperature(r, diskInner, P);
        float T = TBackbone * tempScale;
        if (FC_PHYSICS_MODE == 2u && !dataDrivenVolume) {
            // Eddington vertical atmosphere + MRI turbulent heating fluctuation.
            // Together these replace the Perlin noise texture: the Eddington profile
            // sets T(τ) from the disk photosphere inward, while MRI heating adds
            // α-disk-scaled spatial fluctuations with correlation length ~ H.
            float hNorm_vol  = abs(pos.z) / max(P.he, 1e-6);
            float tauMid_vol = max(P.diskCloudOpticalDepth * max(P.diskVolumeTauScale, 1.0), 0.5);
            T = disk_eddington_atmosphere_temp(hNorm_vol, tauMid_vol, T);
            float mriAmp_v = max(P.diskPrecisionTexture, P.diskTurbulence);
            T *= disk_mri_heating_factor_amp(r, phi, pos.z, mriAmp_v, P);
        }

        if (dataDrivenVolume) {
            // Direct visible photosphere-volume RT.  This surrogate volume is
            // not an LTE opacity table, so keep visible self-absorption weaker
            // than thermal emission. Dense flow structures should contribute
            // light through the volume instead of collapsing to one smooth tau~1
            // surface. Replace this split with physical j_nu/alpha_nu when an
            // evolved fluid opacity model is available.
            A.visibleSpectrumMode = 1u;
            A.pathRs += ds / max(P.rs, 1e-6);
            float aComGrey = tauScaleLegacy * densityEff * 0.22;
            // Keep emission tied to the participating photospheric gas rather
            // than only the hottest/densest clumps. The surrogate visible model
            // is closer to a thermal photosphere continuum than pure optically
            // thin free-free emission, so use sub-quadratic density/temperature
            // sensitivity and let the volume field carry coherent flow contrast.
            float jDensity = pow(max(densityEff, 0.0), 1.18);
            float tempEmission = pow(clamp(T / max(TBackbone, 1.0), 0.12, 8.0), 1.45);
            float jComGrey = tauScaleLegacy * jDensity * tempEmission * 2.40;
            float dTauGrey = min((aComGrey / max(g, 1e-8)) * ds, 4.0);
            float dEmitGrey = min((jComGrey / max(g, 1e-8)) * ds, 4.0);
            float transGrey = exp(-dTauGrey);
            float emitWeight = 1.0 - exp(-dEmitGrey);
            float3 sourceXYZ = volume_blackbody_observed_xyz(T, g, P);
            float jGreyY = max(sourceXYZ.y * max(jComGrey, 0.0), 0.0);
            float tauBefore = A.tau;
            float3 xyzPrev = A.IVisNu;
            float3 xyzNext = xyzPrev * transGrey + sourceXYZ * emitWeight;
            if (!(isfinite(xyzNext.x) && isfinite(xyzNext.y) && isfinite(xyzNext.z))) {
                A.invalidSamples += 1u;
                continue;
            }
            A.IVisNu = max(xyzNext, float3(0.0)); // In precision direct-volume mode this stores linear XYZ.
            float3 dXYZ = max(sourceXYZ * emitWeight, float3(0.0));
            A.tau += dTauGrey;
            A.tauVis = float3(A.tau);
            volume_accum_note_transfer(A, jGreyY, max(aComGrey, 0.0), tauBefore, dTauGrey, r, ds, P);
            A.maxRho = max(A.maxRho, densityEff);
            A.maxThetae = max(A.maxThetae, T);
            A.maxEpsAbs = 1.0;
            A.maxABase = max(A.maxABase, max(aComGrey, 0.0));
            A.maxACool = 0.0;
            A.maxSource = max(A.maxSource, max(sourceXYZ.y, 0.0));
            A.maxSourceThermal = max(A.maxSourceThermal, max(sourceXYZ.y, 0.0));
            A.maxJThermal = max(A.maxJThermal, jGreyY);
            A.intJThermal += jGreyY * ds;
            A.intJThermalWeighted += jGreyY * densityEff * ds;
            A.intAlphaThermalPre += max(aComGrey, 0.0) * ds;
            A.intAlphaThermalPost += dTauGrey;
            A.maxThinWeight = max(A.maxThinWeight, clamp(densityEff, 0.0, 1.0));
            A.maxAlpha = max(A.maxAlpha, max(aComGrey, 0.0));
            A.maxJ = max(A.maxJ, jGreyY);
            A.maxI = max(A.maxI, max(A.IVisNu.y, 0.0));
            A.intIThermal = max(A.intIThermal, max(A.IVisNu.y, 0.0));
            if (dXYZ.y > 0.0) {
                volume_accum_add_sample(A, dXYZ.y, T, g, r, vrRatio, cloudSharp, pos, obs);
            }
            A.I = max(A.IVisNu.y, 0.0);
            if (!(A.tau < 24.0)) break;
            continue;
        }

        // Physical vertical opacity: Gaussian density ρ(z) ∝ exp(-z²/2H²).
        // This gives an optically thick midplane and optically thin corona,
        // replacing the top-hat from verticalEdgeGate that was used previously.
        float H_sigma   = max(P.he, 1e-6);
        float zOverH_sq = (pos.z / H_sigma) * (pos.z / H_sigma);
        float gaussVertical = exp(-0.5 * zOverH_sq);

        float emiss = densityEff
                    * mix(0.95, 2.10, clumpGate)
                    * pow(max(T / 6000.0, 1e-4), 2.4)
                    * 1.35;
        float dTau = min(tauScaleLegacy * densityEff * gaussVertical * ds, 2.4);
        float trans = exp(-A.tau);
        float contrib = trans * emiss * ds;
        if (contrib > 0.0) {
            volume_accum_add_sample(A, contrib, T, g, r, vrRatio, cloudSharp, pos, obs);
            A.I += contrib;
        }
        A.tau += dTau;
        if (!(A.tau < 24.0)) break;
    }
}

static inline void init_collision_info(thread CollisionInfo& info) {
    info.hit = 0;
    info.ct  = 0.0;
    info.T   = 0.0;
    info.v_disk = float4(0);
    info.direct_world = float4(0);
    info.noise = 0.0;
    info.emit_r_norm = 0.0;
    info.emit_phi = 0.0;
    info.emit_z_norm = 0.0;
}

static inline float2 oct_encode_unit(float3 n) {
    float3 v = n / max(abs(n.x) + abs(n.y) + abs(n.z), 1e-12);
    float2 e = v.xy;
    if (v.z < 0.0) {
        float2 s = float2((e.x >= 0.0) ? 1.0 : -1.0,
                          (e.y >= 0.0) ? 1.0 : -1.0);
        e = (1.0 - abs(float2(e.y, e.x))) * s;
    }
    return e;
}

static inline float3 oct_decode_unit(float2 e) {
    float3 v = float3(e.x, e.y, 1.0 - abs(e.x) - abs(e.y));
    if (v.z < 0.0) {
        float2 s = float2((v.x >= 0.0) ? 1.0 : -1.0,
                          (v.y >= 0.0) ? 1.0 : -1.0);
        v.xy = (1.0 - abs(float2(v.y, v.x))) * s;
    }
    float len2 = dot(v, v);
    return (len2 > 1e-20) ? normalize(v) : float3(0.0, 0.0, 1.0);
}

static inline CollisionLite32 pack_collision_lite32(const CollisionInfo rec) {
    CollisionLite32 out;
    float3 dir = rec.direct_world.xyz;
    float len2 = dot(dir, dir);
    if (!(len2 > 1e-20)) dir = float3(0.0, 0.0, 1.0);
    else dir = normalize(dir);
    float2 dirOct = oct_encode_unit(dir);
    out.vDiskXYZ_T = float4(rec.v_disk.x, rec.v_disk.y, rec.v_disk.z, rec.T);
    out.noise_dirOct_hit = float4(rec.noise, dirOct.x, dirOct.y, (rec.hit != 0u) ? 1.0 : 0.0);
    return out;
}

static inline CollisionInfo unpack_collision_lite32(const CollisionLite32 recLite) {
    CollisionInfo rec;
    rec.hit = (recLite.noise_dirOct_hit.w > 0.5) ? 1u : 0u;
    rec.ct = 0.0;
    rec.T = max(recLite.vDiskXYZ_T.w, 0.0);
    rec._pad0 = 0.0;
    rec.v_disk = float4(recLite.vDiskXYZ_T.xyz, 0.0);
    rec.direct_world = float4(oct_decode_unit(recLite.noise_dirOct_hit.yz), 0.0);
    rec.noise = recLite.noise_dirOct_hit.x;
    rec.emit_r_norm = 0.0;
    rec.emit_phi = 0.0;
    rec.emit_z_norm = 0.0;
    return rec;
}

static inline float3 disk_sample_probe_pos(float3 hitPos,
                                           float3 world0,
                                           float3 worldPos,
                                           constant Params& P)
{
    if (P.diskNoiseModel == 1u || P.diskNoiseModel == 2u) {
        // Perlin modes sample exactly at hit position for stable streak texture.
        return hitPos;
    }
    float3 segProbe = worldPos - world0;
    float segProbeLen2 = dot(segProbe, segProbe);
    float3 samplePos = hitPos;
    if (segProbeLen2 > 1e-20) {
        float3 probe = hitPos + normalize(segProbe) * (0.35 * P.he);
        if (inside_disk_volume(probe, P)) samplePos = probe;
    }
    return samplePos;
}

static inline void disk_set_noise_and_bridge(thread CollisionInfo& info,
                                             float3 samplePos,
                                             float ctLen,
                                             constant Params& P,
                                             texture2d<float, access::sample> diskAtlasTex)
{
    float sampleR = length(float2(samplePos.x, samplePos.y));
    float phiPos = atan2(samplePos.y, samplePos.x);
    float baseNoise = 0.0;
    if (P.diskNoiseModel == 1u) {
        // Perlin mode: wide local smoothing and gentle contrast to keep a soft,
        // cloud-like streak texture rather than hard ring banding.
        float n0 = disk_perlin_texture_noise(sampleR, phiPos, samplePos.z, P);
        float dPhi = 0.030;
        float dR = max(0.020 * P.rs, 1e-6);
        float nPhiF = disk_perlin_texture_noise(sampleR, phiPos + dPhi, samplePos.z, P);
        float nPhiB = disk_perlin_texture_noise(sampleR, phiPos - dPhi, samplePos.z, P);
        float nRF = disk_perlin_texture_noise(sampleR + dR, phiPos, samplePos.z, P);
        float nRB = disk_perlin_texture_noise(max(sampleR - dR, 1.0001 * P.rs), phiPos, samplePos.z, P);
        float smooth = 0.36 * n0 + 0.22 * nPhiF + 0.22 * nPhiB + 0.10 * nRF + 0.10 * nRB;
        float flowSoft = 2.0 * disk_cloud_noise(sampleR, phiPos, samplePos.z, ctLen, P) - 1.0;
        smooth = mix(smooth, flowSoft, 0.22);
        float centered = smooth / (1.0 + 0.75 * abs(smooth));
        float soft = 0.5 + 0.5 * centered;
        baseNoise = clamp(0.5 + (soft - 0.5) * 0.64, 0.0, 1.0);
    } else if (P.diskNoiseModel == 2u) {
        baseNoise = clamp(disk_perlin_texture_noise(sampleR, phiPos, samplePos.z, P), 0.0, 1.0);
    } else if (P.diskNoiseModel == 3u) {
        baseNoise = disk_classic_stripe_noise(sampleR, phiPos, samplePos.z, P);
    } else {
        baseNoise = disk_cloud_noise(sampleR, phiPos, samplePos.z, ctLen, P);
    }
    float atlasDensity = clamp(disk_sample_atlas(sampleR, phiPos, P, diskAtlasTex).y, 0.0, 1.0);
    float densityBlend = (P.diskAtlasMode != 0u) ? clamp(P.diskAtlasDensityBlend, 0.0, 1.0) : 0.0;
    if (FC_PHYSICS_MODE == 1u) {
        float rH = disk_horizon_radius_m(P);
        float rIn = disk_inner_radius_m(P);
        float x = clamp((sampleR - rH) / max(rIn - rH, 1e-6), 0.0, 1.0);
        float xSoft = smoothstep(0.0, 1.0, x);
        float plungeKeep = smoothstep(0.20, 0.95, xSoft);
        // Reduce high-contrast texture inside plunging region to avoid stitched center look.
        baseNoise = mix(0.12, baseNoise, plungeKeep);
        densityBlend *= plungeKeep;
    }
    info.noise = mix(baseNoise, atlasDensity, densityBlend);
    info.emit_r_norm = sampleR / max(P.rs, 1e-6);
    info.emit_phi = phiPos;
    info.emit_z_norm = samplePos.z / max(P.rs, 1e-6);
}

static inline bool grmhd_visible_mode_enabled() {
    return (FC_PHYSICS_MODE == 3u && visible_mode_enabled_fc());
}

static inline bool grmhd_raw_debug_enabled(constant Params& P) {
    return (FC_PHYSICS_MODE == 3u &&
            FC_TRACE_DEBUG_OFF == 0u &&
            (P.diskGrmhdDebugView >= 1u && P.diskGrmhdDebugView <= 4u));
}

static inline bool grmhd_state_debug_enabled(constant Params& P) {
    bool physicsSupportsDebug = (FC_PHYSICS_MODE == 3u) ||
                                (FC_PHYSICS_MODE == 2u && P.diskVolumeMode != 0u);
    return (physicsSupportsDebug &&
            FC_TRACE_DEBUG_OFF == 0u &&
            ((P.diskGrmhdDebugView >= 10u && P.diskGrmhdDebugView <= 19u) ||
             P.diskGrmhdDebugView == 20u ||
             (P.diskGrmhdDebugView >= 23u && P.diskGrmhdDebugView <= 54u) ||
             (P.diskGrmhdDebugView >= 56u && P.diskGrmhdDebugView <= 58u)));
}

static inline bool grmhd_pol_debug_enabled(constant Params& P) {
    return (FC_PHYSICS_MODE == 3u &&
            FC_TRACE_DEBUG_OFF == 0u &&
            P.diskGrmhdDebugView == 9u);
}

#define BH_INCLUDE_VOLUME_TRANSPORT_COMMIT 1
#include "VolumeTransport/commit.metal"
#undef BH_INCLUDE_VOLUME_TRANSPORT_COMMIT

static inline bool trace_commit_volume_hit(thread const VolumeAccum& volumeA,
                                           bool volumeMode,
                                           float diskInner,
                                           float3 volumeObsDir,
                                           float ctLen,
                                           float impactRs,
                                           constant Params& P,
                                           thread CollisionInfo& info)
{
    PreparedVolumeHit prepared = trace_prepare_volume_hit(volumeA, volumeMode, diskInner, volumeObsDir, P);
    if (!prepared.valid) {
        return false;
    }
    info.ct  = ctLen;
    trace_store_volume_hit(volumeA, prepared, P, info);
    if (P.rayBundleJacobian == 0u &&
        (grmhd_visible_mode_enabled() ||
         (FC_PHYSICS_MODE == 2u && P.diskVolumeMode != 0u))) {
        // Original camera-ray impact parameter. Compose uses this only for
        // diagnostics and observer-side presentation; scientific/debug output
        // is not attenuated by it.
        info.direct_world.w = max(impactRs, 0.0);
    }
    return true;
}

static inline bool trace_single_ray(constant Params& P,
                                    float x,
                                    float y,
                                    texture2d<float, access::sample> diskAtlasTex,
                                    texture3d<float, access::sample> diskVol0Tex,
                                    texture3d<float, access::sample> diskVol1Tex,
                                    thread CollisionInfo& info)
{
    float3 dir = normalize(x * P.planeX + y * P.planeY - P.d * P.z);

    init_collision_info(info);
    info.direct_world = float4(-normalize(dir), 0.0);

    if (FC_METRIC == 0) {
        float3 newX = normalize(P.camPos);
        float3 newZ = normalize(cross(newX, dir));
        float3 newY = cross(newZ, newX);
        float r0 = length(P.camPos);
        return trace_schwarzschild_ray(P, dir, newX, newY, newZ, r0, diskAtlasTex, diskVol0Tex, diskVol1Tex, info);
    }

    return trace_kerr_ray(P, dir, diskAtlasTex, diskVol0Tex, diskVol1Tex, info);
}

#define BH_INCLUDE_VISIBLE_TRANSPORT_BRIDGE 1
#include "Visible/bridge.metal"
#undef BH_INCLUDE_VISIBLE_TRANSPORT_BRIDGE

#define BH_INCLUDE_VOLUME_RT_BUNDLE 1
#include "Bundle/ray_bundle.metal"
#undef BH_INCLUDE_VOLUME_RT_BUNDLE

static inline void renderBH_core_simple(constant Params& P,
                                        device CollisionInfo* outInfo,
                                        texture2d<float, access::sample> diskAtlasTex,
                                        texture3d<float, access::sample> diskVol0Tex,
                                        texture3d<float, access::sample> diskVol1Tex,
                                        uint2 gid,
                                        uint outIndex)
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = outIndex;

    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    float x = (float(gx) + 0.5) - float(P.fullWidth)  * 0.5;
    float y = (float(gy) + 0.5) - float(P.fullHeight) * 0.5;

    CollisionInfo out;
    bool hit = trace_single_ray(P, x, y, diskAtlasTex, diskVol0Tex, diskVol1Tex, out);
    if (!hit || out.hit == 0u) {
        init_collision_info(out);
    }
    outInfo[idx] = out;
}

static inline void renderBH_core_bundle(constant Params& P,
                                        device CollisionInfo* outInfo,
                                        texture2d<float, access::sample> diskAtlasTex,
                                        texture3d<float, access::sample> diskVol0Tex,
                                        texture3d<float, access::sample> diskVol1Tex,
                                        uint2 gid,
                                        uint outIndex)
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = outIndex;

    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    float baseX = (float(gx) + 0.5) - float(P.fullWidth)  * 0.5;
    float baseY = (float(gy) + 0.5) - float(P.fullHeight) * 0.5;

    const float2 ssaaJitter[4] = {
        float2(-0.25, -0.25),
        float2( 0.25, -0.25),
        float2(-0.25,  0.25),
        float2( 0.25,  0.25)
    };
    const uint sampleCount = 4u;
    const float sampleW = 1.0 / 4.0;
    const float diffOffset = 0.25;

    bool haveHit = false;
    bool thinReferenceBundle = (FC_PHYSICS_MODE == 0u &&
                                P.visibleTeffModel == 3u &&
                                FC_TRACE_DEBUG_OFF != 0u);
    bool bundleLinearAnchors = thinReferenceBundle ||
                               (FC_PHYSICS_MODE == 3u &&
                                FC_VISIBLE_MODE != 0u &&
                                P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                FC_TRACE_DEBUG_OFF != 0u);
    bool bundleVisibleSpectrum = (FC_PHYSICS_MODE == 3u &&
                                  FC_VISIBLE_MODE != 0u &&
                                  FC_TRACE_DEBUG_OFF != 0u);
    float sumTemp4 = 0.0;
    float sumI = 0.0;
    float sumHitWeight = 0.0;
    float hitCoverage = 0.0;
    float sumEmitR = 0.0;
    float sumEmitPhi = 0.0;
    float sumEmitPhiCos = 0.0;
    float sumEmitPhiSin = 0.0;
    float sumEmitZ = 0.0;
    float3 sumVisibleXYZ = float3(0.0);
    bool haveVisibleXYZ = false;
    CollisionInfo firstHitInfo;
    init_collision_info(firstHitInfo);
    bool haveFirstHitInfo = false;
    CollisionInfo sampleInfos[4];
    uint sampleHits[4] = {0u, 0u, 0u, 0u};
    for (uint s = 0u; s < sampleCount; ++s) {
        init_collision_info(sampleInfos[s]);
    }

    CollisionInfo centerInfo;
    init_collision_info(centerInfo);
    bool centerHit = trace_single_ray(P, baseX, baseY, diskAtlasTex, diskVol0Tex, diskVol1Tex, centerInfo) && (centerInfo.hit != 0u);
    CollisionInfo diffXInfo;
    CollisionInfo diffYInfo;
    init_collision_info(diffXInfo);
    init_collision_info(diffYInfo);
    bool diffXHit = false;
    bool diffYHit = false;
    if (P.rayBundleJacobian != 0u) {
        diffXHit = trace_single_ray(P, baseX + 0.5, baseY, diskAtlasTex, diskVol0Tex, diskVol1Tex, diffXInfo) && (diffXInfo.hit != 0u);
        diffYHit = trace_single_ray(P, baseX, baseY + 0.5, diskAtlasTex, diskVol0Tex, diskVol1Tex, diffYInfo) && (diffYInfo.hit != 0u);
    }

    for (uint s = 0u; s < sampleCount; ++s) {
        float2 j = ssaaJitter[s];
        float x = baseX + j.x;
        float y = baseY + j.y;

        CollisionInfo subInfo;
        init_collision_info(subInfo);
        bool hit = trace_single_ray(P, x, y, diskAtlasTex, diskVol0Tex, diskVol1Tex, subInfo);
        if (!hit || subInfo.hit == 0u) continue;
        sampleInfos[s] = subInfo;
        sampleHits[s] = 1u;
    }

    float bundleJacW = 1.0;
    bool haveBundleJacW = false;
    if (P.rayBundleJacobian != 0u) {
        if (centerHit && diffXHit && diffYHit) {
            haveBundleJacW = ray_bundle_compute_center_diff_weight(P, centerInfo, diffXInfo, diffYInfo, 0.5, bundleJacW);
        }
        if (!haveBundleJacW) {
            haveBundleJacW = ray_bundle_compute_emitpos_bundle_weight(P, sampleInfos, sampleHits, bundleJacW);
        }
    }

    for (uint s = 0u; s < sampleCount; ++s) {
        if (sampleHits[s] == 0u) continue;
        float2 j = ssaaJitter[s];
        float x = baseX + j.x;
        float y = baseY + j.y;
        CollisionInfo subInfo = sampleInfos[s];
        if (!haveFirstHitInfo) {
            firstHitInfo = subInfo;
            haveFirstHitInfo = true;
        }

        float jacW = 1.0;
        if (P.rayBundleJacobian != 0u) {
            jacW = haveBundleJacW
                ? bundleJacW
                : ray_bundle_compute_jacobian_weight(P, x, y, diffOffset, subInfo);
        }

        float tSafe = clamp(subInfo.T, 0.0, 1e9);
        float t2 = tSafe * tSafe;
        float t4Raw = t2 * t2;
        float scalarIRaw = max(subInfo.v_disk.w, 0.0);
        if (!haveHit) {
            haveHit = true;
        }

        float weightedW = jacW * sampleW;
        sumHitWeight += weightedW;
        hitCoverage += sampleW;
        sumTemp4 += t4Raw * weightedW;
        sumI += scalarIRaw * weightedW;
        if (bundleLinearAnchors) {
            sumEmitR += max(subInfo.emit_r_norm, 0.0) * weightedW;
            if (thinReferenceBundle) {
                sumEmitPhiCos += cos(subInfo.emit_phi) * weightedW;
                sumEmitPhiSin += sin(subInfo.emit_phi) * weightedW;
            } else {
                sumEmitPhi += max(subInfo.emit_phi, 0.0) * weightedW;
            }
            sumEmitZ += max(subInfo.emit_z_norm, 0.0) * weightedW;
        }
        if (bundleVisibleSpectrum) {
            bool xyzOk = false;
            float3 xyz = ray_bundle_visible_xyz_from_collision(subInfo, P, xyzOk);
            if (xyzOk) {
                sumVisibleXYZ += xyz * weightedW;
                haveVisibleXYZ = true;
            }
        }
    }

    if (!haveHit && centerHit) {
        haveHit = true;
        firstHitInfo = centerInfo;
        haveFirstHitInfo = true;

        float tSafe = clamp(centerInfo.T, 0.0, 1e9);
        float t2 = tSafe * tSafe;
        sumTemp4 = t2 * t2;
        sumI = max(centerInfo.v_disk.w, 0.0);
        sumHitWeight = 1.0;
        hitCoverage = 1.0;
        if (bundleLinearAnchors) {
            sumEmitR = max(centerInfo.emit_r_norm, 0.0);
            if (thinReferenceBundle) {
                sumEmitPhiCos = cos(centerInfo.emit_phi);
                sumEmitPhiSin = sin(centerInfo.emit_phi);
            } else {
                sumEmitPhi = max(centerInfo.emit_phi, 0.0);
            }
            sumEmitZ = max(centerInfo.emit_z_norm, 0.0);
        }
        if (bundleVisibleSpectrum) {
            bool xyzOk = false;
            float3 xyz = ray_bundle_visible_xyz_from_collision(centerInfo, P, xyzOk);
            if (xyzOk) {
                sumVisibleXYZ = xyz;
                haveVisibleXYZ = true;
            }
        }
    }

    CollisionInfo out;
    init_collision_info(out);
    if (!haveHit) {
        outInfo[idx] = out;
        return;
    }

    out = (centerHit ? centerInfo : firstHitInfo);
    if (!centerHit && haveFirstHitInfo) {
        out = firstHitInfo;
    }
    out.hit = 1u;
    if (sumTemp4 > 0.0 && isfinite(sumTemp4)) {
        out.T = pow(sumTemp4, 0.25);
    }
    out.v_disk.w = max(sumI, 0.0);
    if (bundleVisibleSpectrum && haveVisibleXYZ) {
        out.emit_r_norm = max(sumVisibleXYZ.x, 0.0);
        out.emit_phi = max(sumVisibleXYZ.y, 0.0);
        out.emit_z_norm = max(sumVisibleXYZ.z, 0.0);
        out.noise = -100.0; // Sentinel: visible XYZ pre-averaged in render stage.
    } else if (thinReferenceBundle && bundleLinearAnchors && sumHitWeight > 0.0) {
        // Thin visible reference may use the four traced sub-pixel hits as a
        // source-footprint sample, but only when they agree on one coherent disk
        // patch. Around caustics or partial disk silhouettes the source points
        // can be unrelated; keep the center/first-hit coordinate there and use
        // the bundle only as a coverage factor.
        float invW = 1.0 / max(sumHitWeight, 1e-6);
        float phiCoherence = length(float2(sumEmitPhiCos, sumEmitPhiSin)) * invW;
        bool coherentThinPatch = (hitCoverage > 0.999) && (phiCoherence > 0.965);
        if (coherentThinPatch) {
            out.emit_r_norm = max(sumEmitR * invW, 0.0);
            out.emit_phi = atan2(sumEmitPhiSin, sumEmitPhiCos);
            out.emit_z_norm = max(sumEmitZ * invW, 0.0);
        }
        out.v_disk.w = clamp(hitCoverage, 0.0, 1.0);
    } else if (bundleLinearAnchors) {
        out.emit_r_norm = max(sumEmitR, 0.0);
        out.emit_phi = max(sumEmitPhi, 0.0);
        out.emit_z_norm = max(sumEmitZ, 0.0);
    }
    if (P.rayBundleJacobian != 0u) {
        // Preserve the computed bundle Jacobian weight for collision-debug inspection.
        // Post compose only uses direct_world.xyz, so w is safe as an internal diagnostic.
        out.direct_world.w = bundleJacW;
    }

    outInfo[idx] = out;
}

static inline bool renderBH_use_bundle(constant Params& P) {
    return (P.rayBundleSSAA != 0u &&
            ((FC_PHYSICS_MODE == 3u && FC_VISIBLE_MODE != 0u) ||
             (FC_PHYSICS_MODE == 0u && P.visibleTeffModel == 3u)) &&
            FC_TRACE_DEBUG_OFF != 0u);
}

kernel void renderBH(constant Params& P [[buffer(0)]],
                     device CollisionInfo* outInfo [[buffer(1)]],
                     texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                     texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                     texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                     uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = gid.y * P.width + gid.x;
    if (renderBH_use_bundle(P)) {
        renderBH_core_bundle(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, idx);
    } else {
        renderBH_core_simple(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, idx);
    }
}

kernel void renderBHGlobal(constant Params& P [[buffer(0)]],
                           device CollisionInfo* outInfo [[buffer(1)]],
                           texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                           texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                           texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    if (gx >= P.fullWidth || gy >= P.fullHeight) return;
    uint gidx = gy * P.fullWidth + gx;
    if (renderBH_use_bundle(P)) {
        renderBH_core_bundle(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, gidx);
    } else {
        renderBH_core_simple(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, gidx);
    }
}

kernel void renderBHClassic(constant Params& P [[buffer(0)]],
                            device CollisionInfo* outInfo [[buffer(1)]],
                            texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                            texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                            texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                            uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = gid.y * P.width + gid.x;
    renderBH_core_simple(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, idx);
}

kernel void renderBHClassicLite(constant Params& P [[buffer(0)]],
                                device CollisionLite32* outInfo [[buffer(1)]],
                                texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                                texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                                texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                                uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    float x = (float(gx) + 0.5) - float(P.fullWidth)  * 0.5;
    float y = (float(gy) + 0.5) - float(P.fullHeight) * 0.5;

    CollisionInfo out;
    bool hit = trace_single_ray(P, x, y, diskAtlasTex, diskVol0Tex, diskVol1Tex, out);
    if (!hit || out.hit == 0u) {
        init_collision_info(out);
    }
    uint idx = gid.y * P.width + gid.x;
    outInfo[idx] = pack_collision_lite32(out);
}

kernel void renderBHClassicLiteGlobal(constant Params& P [[buffer(0)]],
                                      device CollisionLite32* outInfo [[buffer(1)]],
                                      texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                                      texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                                      texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                                      uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    if (gx >= P.fullWidth || gy >= P.fullHeight) return;
    float x = (float(gx) + 0.5) - float(P.fullWidth)  * 0.5;
    float y = (float(gy) + 0.5) - float(P.fullHeight) * 0.5;

    CollisionInfo out;
    bool hit = trace_single_ray(P, x, y, diskAtlasTex, diskVol0Tex, diskVol1Tex, out);
    if (!hit || out.hit == 0u) {
        init_collision_info(out);
    }
    uint gidx = gy * P.fullWidth + gx;
    outInfo[gidx] = pack_collision_lite32(out);
}

kernel void renderBHClassicGlobal(constant Params& P [[buffer(0)]],
                                  device CollisionInfo* outInfo [[buffer(1)]],
                                  texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                                  texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                                  texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                                  uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    if (gx >= P.fullWidth || gy >= P.fullHeight) return;
    uint gidx = gy * P.fullWidth + gx;
    renderBH_core_simple(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, gidx);
}

kernel void renderBHBundle(constant Params& P [[buffer(0)]],
                           device CollisionInfo* outInfo [[buffer(1)]],
                           texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                           texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                           texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                           uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint idx = gid.y * P.width + gid.x;
    renderBH_core_bundle(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, idx);
}

kernel void renderBHBundleGlobal(constant Params& P [[buffer(0)]],
                                 device CollisionInfo* outInfo [[buffer(1)]],
                                 texture2d<float, access::sample> diskAtlasTex [[texture(0)]],
                                 texture3d<float, access::sample> diskVol0Tex [[texture(1)]],
                                 texture3d<float, access::sample> diskVol1Tex [[texture(2)]],
                                 uint2 gid [[thread_position_in_grid]])
{
    if (gid.x >= P.width || gid.y >= P.height) return;
    uint gx = gid.x + P.offsetX;
    uint gy = gid.y + P.offsetY;
    if (gx >= P.fullWidth || gy >= P.fullHeight) return;
    uint gidx = gy * P.fullWidth + gx;
    renderBH_core_bundle(P, outInfo, diskAtlasTex, diskVol0Tex, diskVol1Tex, gid, gidx);
}

#endif
