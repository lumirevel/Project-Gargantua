// Auto-split from integral.metal (Phase 2 refactor).
#if defined(BH_INCLUDE_VOLUME_RT) && (BH_INCLUDE_VOLUME_RT)
struct VolumeAccum {
    float I;
    float3 IVisNu; // observed-frame I_nu at {650nm, 550nm, 450nm}
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
    float3 tauVis;
    uint  samples;
    uint  surfaceHit;
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
    A.tauVis = float3(0.0);
    A.samples = 0u;
    A.surfaceHit = 0u;
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
    float3 samplePos = disk_sample_probe_pos(hitState.hitPos, world0, worldPos, P);
    disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlasTex);
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
    float3 samplePos = disk_sample_probe_pos(hitState.hitPos, world0, worldPos, P);
    disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlasTex);
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
    if (allowAtlasOverrides) {
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
    if (allowAtlasOverrides) {
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
                                                       diskAtlasTex, FC_PHYSICS_MODE != 2u, FC_PHYSICS_MODE != 0u,
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

    float T = disk_effective_temperature(hitState.dxy, diskInner, P);
    T *= tempScale;
    if (FC_PHYSICS_MODE == 2u) {
        T *= disk_precision_texture_factor(hitState.dxy, hitState.phiHit, hitState.hitPos.z, P);
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
                                              FC_PHYSICS_MODE != 2u, FC_PHYSICS_MODE != 0u, info);
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
    KerrCovMetric diskCov = kerr_cov_metric(hitState.r_M, 0.5 * M_PI, a);
    float uDen = -(diskCov.gtt
                 + 2.0 * omega * diskCov.gtphi
                 + omega * omega * diskCov.gphiphi
                 + diskCov.grr * drdt * drdt);
    if (!(uDen > 1e-12)) {
        omega = omegaK;
        drdt = 0.0;
        uDen = -(diskCov.gtt
               + 2.0 * omega * diskCov.gtphi
               + omega * omega * diskCov.gphiphi);
    }
    float u_t = 1.0 / sqrt(max(uDen, 1e-12));
    float E_emit = u_t * (1.0 - omega * Lz - drdt * hitState.hitState.pr);
    if (!(E_emit > 1e-8)) {
        E_emit = u_t * max(1.0 - omega * Lz, 1e-8);
    }
    float g_factor = 1.0 / max(E_emit, 1e-8);
    if (!isfinite(g_factor)) g_factor = 1.0;
    g_factor = clamp(g_factor, 1e-4, 1e4);

    float T = disk_effective_temperature(hitState.dxy, diskInner, P);
    T *= tempScale;
    if (FC_PHYSICS_MODE == 2u) {
        T *= disk_precision_texture_factor(hitState.dxy, hitState.phiHit, hitState.hitPos.z, P);
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

    return trace_commit_volume_hit(volumeA, true, diskInner, volumeObsDir, P.c * p.x, P, info);
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

    return trace_commit_volume_hit(volumeA, true, diskInner, volumeObsDir, state.t * massLen, P, info);
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
    if (FC_PHYSICS_MODE == 3u) {
        // Thin GRMHD volumes are easy to miss with coarse segment sampling.
        // Tie step size to vertical extent so visible-surface / scalar-RT both remain stable.
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

        if (FC_PHYSICS_MODE == 1u) {
            if (volume_integrate_thick_sample(
                pos, obs, r, phi, t, diskInner, verticalEdgeGate, ds, tauScaleLegacy,
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

            float rhoEff = rho * max(P.diskGrmhdDensityScale, 0.0);
            float bEff = length(bVec) * max(P.diskGrmhdBScale, 0.0);
            A.maxRho = max(A.maxRho, rhoEff);
            A.maxB2 = max(A.maxB2, bEff * bEff);

            if (visibleSurfaceMode) {
                if (volume_commit_grmhd_visible_surface_hit(
                    pos, obs, r, phi, zNorm, t, rNormMin, rNormMax, rhoThreshold, rho, vR,
                    LzConst, pr0, pr1, P, diskVol0Tex, diskVol1Tex,
                    A, havePrevVisibleSample, prevRho, prevT, prevPos
                )) return;
            }

            if (!(rho > 1e-24) || !(thetae > 1e-5)) continue;
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
            float g = disk_grmhd_approx_gfactor(r, phi, obs, vR, vPhi, vZ, P);
            if (!isfinite(g)) g = 1.0;

            // Visible GRMHD: integrate three representative wavelength bins directly in the
            // RT loop (R/G/B anchors) instead of post-colorizing a single I_nu channel.
            bool useVisibleMultispectral = (visible_mode_enabled_fc() && !visibleSurfaceMode);
            float dI = 0.0;
            if (useVisibleMultispectral) {
                const float3 lamNm = float3(650.0, 550.0, 450.0);
                const float3 lamM = lamNm * 1e-9;
                bool expressiveVisible = ((P.visiblePad0 & 1u) != 0u);
                float3 iPrevNu = A.IVisNu;
                float3 qPrevNu = A.QVisNu;
                float3 uPrevNu = A.UVisNu;
                float3 vPrevNu = A.VVisNu;
                float maxJObs = 0.0;
                bool polarized = (P.diskPolarizedRT != 0u);

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
                float visibleAlpha = clamp(P.visibleEmissionAlpha, 0.0, 4.0);
                float dIRef = 0.0;
                if (expressiveVisible) {
                    // Expressive visible mode:
                    // derive RGB-band I_nu from a physically-traced reference I_nu at nu_obs,
                    // then map to visible via a spectral slope instead of forcing synthetic hits.
                    disk_grmhd_synch_coeffs(rho, thetae, bVec, nuComovRef, P, jComRef, aComRef);
                    float aCoolRef = max(P.diskGrmhdAbsorptionScale, 0.0)
                                   * disk_cool_absorber_alpha(rho, thetae, bVec, nuComovRef, P);
                    aComRef += aCoolRef;

                    float jObsRef = (jComRef * g * g) * aniso;
                    float aObsRef = aComRef / max(g, 1e-8);
                    float iPrevRef = A.I;
                    if (aObsRef > 1e-12) {
                        float dTauRef = min(aObsRef * ds, 40.0);
                        float transRef = exp(-dTauRef);
                        float srcRef = jObsRef / max(aObsRef, 1e-30);
                        A.I = iPrevRef * transRef + srcRef * (1.0 - transRef);
                        A.tau += dTauRef;
                    } else {
                        A.I = iPrevRef + jObsRef * ds;
                    }
                    dIRef = max(A.I - iPrevRef, 0.0);
                    maxJObs = max(maxJObs, jObsRef);
                }

                for (uint k = 0u; k < 3u; ++k) {
                    float nuObs = P.c / max(lamM[k], 1e-30);
                    float jCom = 0.0;
                    float aCom = 0.0;
                    float nuComov = max(nuObs / max(g, 1e-8), 1e3);
                    if (expressiveVisible) {
                        float ratio = max(nuObs / max(nuObsRef, 1e6), 1e-8);
                        jCom = jComRef * pow(ratio, -visibleAlpha);
                        aCom = aComRef;
                    } else {
                        disk_visible_rt_coeffs(r, rho, thetae, bVec, nuComov, P, jCom, aCom);
                    }

                    float jObs = (jCom * g * g) * aniso;
                    float aObs = aCom / max(g, 1e-8);
                    maxJObs = max(maxJObs, jObs);

                    float iPrev = A.IVisNu[k];
                    float qPrev = A.QVisNu[k];
                    float uPrev = A.UVisNu[k];
                    float vPrev = A.VVisNu[k];
                    float jQ = polarized ? (p0 * jObs * cos2psi) : 0.0;
                    float jU = polarized ? (p0 * jObs * sin2psi) : 0.0;
                    float jV = 0.0;
                    if (aObs > 1e-12) {
                        float dTau = min(aObs * ds, 40.0);
                        float trans = exp(-dTau);
                        float srcI = jObs / max(aObs, 1e-30);
                        float srcQ = jQ / max(aObs, 1e-30);
                        float srcU = jU / max(aObs, 1e-30);
                        float srcV = jV / max(aObs, 1e-30);
                        A.IVisNu[k] = iPrev * trans + srcI * (1.0 - trans);
                        A.QVisNu[k] = qPrev * trans + srcQ * (1.0 - trans);
                        A.UVisNu[k] = uPrev * trans + srcU * (1.0 - trans);
                        A.VVisNu[k] = vPrev * trans + srcV * (1.0 - trans);
                        A.tauVis[k] += dTau;
                    } else {
                        A.IVisNu[k] = iPrev + jObs * ds;
                        A.QVisNu[k] = qPrev + jQ * ds;
                        A.UVisNu[k] = uPrev + jU * ds;
                        A.VVisNu[k] = vPrev + jV * ds;
                    }

                    if (polarized) {
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
                A.maxJ = max(A.maxJ, maxJObs);
                dI = dIRef;
                if (volume_finalize_grmhd_visible_sample(
                        expressiveVisible, polarized, rho, thetae, g, r, vR,
                        pos, obs, P,
                        iPrevNu, qPrevNu, uPrevNu, vPrevNu, A, dI)) {
                    break;
                }
            } else {
                volume_integrate_grmhd_scalar_sample(rho, thetae, bVec, g, ds, P, A, dI);
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

        float cloudFlow = disk_cloud_noise(r, phi, pos.z, P.c * P.diskFlowTime + 0.12 * r, P);
        float cloudPerlin = 0.5 + 0.5 * disk_perlin_texture_noise(r, phi + 0.19 * P.diskFlowTime, pos.z, P);
        float cloudLocal = clamp(0.58 * cloudFlow + 0.42 * cloudPerlin, 0.0, 1.0);
        float coverage = clamp(P.diskCloudCoverage, 0.0, 1.0);
        float porosity = clamp(P.diskCloudPorosity, 0.0, 1.0);
        float cloudSharp = pow(cloudLocal, mix(2.0, 1.15, coverage));
        float clumpGate = smoothstep(max(0.0, 1.0 - coverage), 1.0, cloudSharp);
        float sparseGate = smoothstep(0.68 - 0.30 * coverage,
                                      0.96 - 0.18 * coverage,
                                      cloudSharp);
        float voidGate = porosity * (1.0 - clumpGate);
        float densityEff = density
                         * mix(0.30, 1.08, clumpGate * clumpGate)
                         * mix(0.22, 1.0, sparseGate * sparseGate * sparseGate)
                         * (1.0 - 0.40 * voidGate)
                         * verticalEdgeGate;
        float innerX = clamp((r - diskInner) / max(0.45 * diskInner, 1e-6), 0.0, 1.0);
        float innerGate = smoothstep(0.0, 1.0, innerX);
        densityEff *= (0.25 + 0.75 * innerGate);
        float voidNoise = fbm(float3(rNorm * 4.6, phi * 10.8, zNorm * 6.2 + 0.45 * P.diskFlowTime));
        float coherentVoid = smoothstep(0.46, 0.83, voidNoise);
        densityEff *= mix(1.0, coherentVoid, 0.30 * porosity);
        float spiral = 0.5 + 0.5 * sin(12.0 * phi + 5.0 * log(max(rNorm, 1.0)));
        float filament = smoothstep(0.56, 0.92, spiral);
        densityEff *= mix(1.0, 0.52 + 0.48 * filament, 0.18);
        densityEff = max(densityEff, 0.06 * density);
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
            KerrCovMetric diskCov = kerr_cov_metric(rM, 0.5 * M_PI, a);
            float uDen = -(diskCov.gtt
                         + 2.0 * omega * diskCov.gtphi
                         + omega * omega * diskCov.gphiphi
                         + diskCov.grr * drdt * drdt);
            if (!(uDen > 1e-12)) {
                drdt = 0.0;
                uDen = -(diskCov.gtt
                       + 2.0 * omega * diskCov.gtphi
                       + omega * omega * diskCov.gphiphi);
            }
            float u_t = 1.0 / sqrt(max(uDen, 1e-12));
            float E_emit = u_t * (1.0 - omega * LzConst - drdt * prRay);
            if (!(E_emit > 1e-8)) {
                E_emit = u_t * max(1.0 - omega * LzConst, 1e-8);
            }
            g = clamp(1.0 / max(E_emit, 1e-8), 1e-4, 1e4);
        }
        if (!isfinite(g)) g = 1.0;

        float T = disk_effective_temperature(r, diskInner, P) * tempScale;
        if (FC_PHYSICS_MODE == 2u) {
            T *= disk_precision_texture_factor(r, phi, pos.z, P);
        }

        float emiss = densityEff
                    * mix(0.95, 2.10, clumpGate)
                    * pow(max(T / 6000.0, 1e-4), 2.4)
                    * 1.35;
        float dTau = min(tauScaleLegacy * densityEff * ds, 2.4);
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
                                           constant Params& P,
                                           thread CollisionInfo& info)
{
    PreparedVolumeHit prepared = trace_prepare_volume_hit(volumeA, volumeMode, diskInner, volumeObsDir, P);
    if (!prepared.valid) {
        return false;
    }
    info.ct  = ctLen;
    trace_store_volume_hit(volumeA, prepared, P, info);
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
    bool bundleLinearAnchors = (FC_PHYSICS_MODE == 3u &&
                                FC_VISIBLE_MODE != 0u &&
                                P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                FC_TRACE_DEBUG_OFF != 0u);
    bool bundleVisibleSpectrum = (FC_PHYSICS_MODE == 3u &&
                                  FC_VISIBLE_MODE != 0u &&
                                  FC_TRACE_DEBUG_OFF != 0u);
    float sumTemp4 = 0.0;
    float sumI = 0.0;
    float sumEmitR = 0.0;
    float sumEmitPhi = 0.0;
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
        sumTemp4 += t4Raw * weightedW;
        sumI += scalarIRaw * weightedW;
        if (bundleLinearAnchors) {
            sumEmitR += max(subInfo.emit_r_norm, 0.0) * weightedW;
            sumEmitPhi += max(subInfo.emit_phi, 0.0) * weightedW;
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
        if (bundleLinearAnchors) {
            sumEmitR = max(centerInfo.emit_r_norm, 0.0);
            sumEmitPhi = max(centerInfo.emit_phi, 0.0);
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
            FC_PHYSICS_MODE == 3u &&
            FC_VISIBLE_MODE != 0u &&
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
