#if defined(BH_INCLUDE_VOLUME_RT_BUNDLE) && (BH_INCLUDE_VOLUME_RT_BUNDLE)
static inline bool ray_bundle_can_use_emit_pos(constant Params& P) {
    bool grmhdRawDebug = grmhd_raw_debug_enabled(P);
    bool grmhdPolDebug = grmhd_pol_debug_enabled(P);
    bool grmhdVisibleVolumetric = (FC_PHYSICS_MODE == 3u &&
                                   visible_mode_enabled_fc() &&
                                   P.visiblePhotosphereRhoThreshold <= 0.0);
    return !(grmhdRawDebug || grmhdPolDebug || grmhdVisibleVolumetric);
}

static inline float3 ray_bundle_view_dir(constant Params& P, float x, float y) {
    return normalize(x * P.planeX + y * P.planeY - P.d * P.z);
}

static inline float ray_bundle_apply_magnification_controls(constant Params& P,
                                                            float magnification) {
    if (!(magnification > 0.0) || !isfinite(magnification)) return 1.0;
    float clampStops = max(P.rayBundleFootprintClamp, 0.0);
    if (clampStops > 0.0) {
        float logMag = clamp(log2(max(magnification, 1e-20)), -clampStops, clampStops);
        magnification = exp2(logMag);
    }

    float strength = max(P.rayBundleJacobianStrength, 0.0);
    if (strength <= 0.0) return 1.0;
    float weight = pow(max(magnification, 1e-20), strength);
    if (!isfinite(weight)) return 1.0;
    return clamp(weight, 1e-4, 1e4);
}

static inline float ray_bundle_weight_from_hits(constant Params& P,
                                                float3 hitCenter,
                                                float3 hitDx,
                                                float3 hitDy,
                                                float diffOffset) {
    float3 eX = hitDx - hitCenter;
    float3 eY = hitDy - hitCenter;
    float footprintArea = length(cross(eX, eY));
    if (!(footprintArea > 1e-30) || !isfinite(footprintArea)) return 1.0;

    float rEmit = max(length(float2(hitCenter.x, hitCenter.y)), max(P.rs, 1e-6));
    float ang = max(abs(diffOffset) / max(P.d, 1e-6), 1e-8);
    float referenceArea = max((rEmit * ang) * (rEmit * ang), 1e-24);
    float magnification = footprintArea / referenceArea;
    return ray_bundle_apply_magnification_controls(P, magnification);
}

static inline float3 ray_bundle_sch_world_pos(float4 p,
                                              float3 basisX,
                                              float3 basisY,
                                              float3 basisZ) {
    float3 localPos = conv(p.y, p.z, p.w);
    return localPos.x * basisX + localPos.y * basisY + localPos.z * basisZ;
}

static inline void ray_bundle_init_sch_state(constant Params& P,
                                             float x,
                                             float y,
                                             float3 basisX,
                                             thread float3& dir,
                                             thread float3& basisY,
                                             thread float3& basisZ,
                                             thread float4& p,
                                             thread float4& v) {
    dir = ray_bundle_view_dir(P, x, y);
    float3 zCand = cross(basisX, dir);
    float zLen2 = dot(zCand, zCand);
    if (zLen2 <= 1e-20) {
        zCand = cross(basisX, float3(0.0, 0.0, 1.0));
        if (dot(zCand, zCand) <= 1e-20) {
            zCand = cross(basisX, float3(0.0, 1.0, 0.0));
        }
    }
    basisZ = normalize(zCand);
    basisY = cross(basisZ, basisX);

    float r0 = length(P.camPos);
    float3 local = P.c * float3(dot(basisX, dir), dot(basisY, dir), dot(basisZ, dir));
    p = float4(0.0, r0, 0.5 * M_PI, 0.0);
    v = float4(0.1, local.x, 0.0, local.y / max(r0, 1e-6));
}

struct SchVarState {
    float4 p;
    float4 v;
};

static inline bool ray_bundle_sch_var_finite(thread const SchVarState& s) {
    return isfinite(s.p.x) && isfinite(s.p.y) && isfinite(s.p.z) && isfinite(s.p.w) &&
           isfinite(s.v.x) && isfinite(s.v.y) && isfinite(s.v.z) && isfinite(s.v.w);
}

static inline float ray_bundle_sch_var_maxabs(thread const SchVarState& s) {
    float m = max(abs(s.p.x), abs(s.p.y));
    m = max(m, abs(s.p.z));
    m = max(m, abs(s.p.w));
    m = max(m, abs(s.v.x));
    m = max(m, abs(s.v.y));
    m = max(m, abs(s.v.z));
    m = max(m, abs(s.v.w));
    return m;
}

static inline SchVarState ray_bundle_sch_var_delta(float4 pA,
                                                   float4 vA,
                                                   float4 pB,
                                                   float4 vB) {
    SchVarState d;
    d.p = pA - pB;
    d.v = vA - vB;
    return d;
}

static inline SchVarState ray_bundle_sch_var_rhs(float4 baseP,
                                                 float4 baseV,
                                                 thread const SchVarState& dState,
                                                 constant Params& P) {
    float mag = max(ray_bundle_sch_var_maxabs(dState), 1e-8);
    float eps = clamp(1e-4 / mag, 1e-6, 2e-2);
    float4 pPlus = baseP + eps * dState.p;
    float4 vPlus = baseV + eps * dState.v;
    float4 pMinus = baseP - eps * dState.p;
    float4 vMinus = baseV - eps * dState.v;
    float4 aPlus = metric_accel(pPlus, vPlus, P);
    float4 aMinus = metric_accel(pMinus, vMinus, P);
    float inv = 1.0 / (2.0 * eps);
    SchVarState out;
    out.p = (vPlus - vMinus) * inv;
    out.v = (aPlus - aMinus) * inv;
    return out;
}

static inline void ray_bundle_sch_var_step(float4 baseP0,
                                           float4 baseV0,
                                           float4 baseP1,
                                           float4 baseV1,
                                           float h,
                                           thread SchVarState& dState,
                                           constant Params& P) {
    SchVarState k0 = ray_bundle_sch_var_rhs(baseP0, baseV0, dState, P);
    SchVarState pred;
    pred.p = dState.p + h * k0.p;
    pred.v = dState.v + h * k0.v;
    SchVarState k1 = ray_bundle_sch_var_rhs(baseP1, baseV1, pred, P);
    dState.p += 0.5 * h * (k0.p + k1.p);
    dState.v += 0.5 * h * (k0.v + k1.v);
}

static inline float ray_bundle_lockstep_weight_schwarzschild(constant Params& P,
                                                             float x,
                                                             float y,
                                                             float diffOffset) {
    float3 basisX = normalize(P.camPos);

    float3 dirC, basisYC, basisZC;
    float3 dirDx, basisYDx, basisZDx;
    float3 dirDy, basisYDy, basisZDy;
    float4 pC, vC;
    float4 pDx, vDx;
    float4 pDy, vDy;
    ray_bundle_init_sch_state(P, x, y, basisX, dirC, basisYC, basisZC, pC, vC);
    ray_bundle_init_sch_state(P, x + diffOffset, y, basisX, dirDx, basisYDx, basisZDx, pDx, vDx);
    ray_bundle_init_sch_state(P, x, y + diffOffset, basisX, dirDy, basisYDy, basisZDy, pDy, vDy);
    SchVarState dX = ray_bundle_sch_var_delta(pDx, vDx, pC, vC);
    SchVarState dY = ray_bundle_sch_var_delta(pDy, vDy, pC, vC);

    bool hasPrev = false;
    float3 prevWC = float3(0.0);
    float3 prevWDx = float3(0.0);
    float3 prevWDy = float3(0.0);
    float horizonRadius = P.rs * (1.0 + P.eps);
    float diskEmitMin = disk_emit_min_radius_m(P);

    for (int i = 0; i < P.maxSteps; ++i) {
        float4 pPrevC = pC;
        float4 vPrevC = vC;
        SchVarState dPrevX = dX;
        SchVarState dPrevY = dY;

        float rPrev = max(pPrevC.y, horizonRadius + 1e-6);
        float nearH = clamp((3.2 * P.rs - rPrev) / max(2.2 * P.rs, 1e-6), 0.0, 1.0);
        float vRadFrac = clamp(abs(vPrevC.y) / max(P.c, 1e-6), 0.0, 1.0);
        int localSubsteps = 1 + int(round(nearH * 6.0)) + int(round(nearH * 2.0 * vRadFrac));
        localSubsteps = clamp(localSubsteps, 1, 8);
        float hSub = P.h / float(localSubsteps);
        for (int s = 0; s < 8; ++s) {
            if (s >= localSubsteps) break;
            float4 p0 = pC;
            float4 v0 = vC;
            rk4_step_h(pC, vC, P, hSub);
            ray_bundle_sch_var_step(p0, v0, pC, vC, hSub, dX, P);
            ray_bundle_sch_var_step(p0, v0, pC, vC, hSub, dY, P);
        }
        if (!ray_bundle_sch_var_finite(dX) || !ray_bundle_sch_var_finite(dY)) {
            break;
        }

        float4 pDxApprox = pC + dX.p;
        float4 pDyApprox = pC + dY.p;
        float3 worldC = ray_bundle_sch_world_pos(pC, basisX, basisYC, basisZC);
        float3 worldDx = ray_bundle_sch_world_pos(pDxApprox, basisX, basisYDx, basisZDx);
        float3 worldDy = ray_bundle_sch_world_pos(pDyApprox, basisX, basisYDy, basisZDy);

        if (hasPrev) {
            float tEnter = 0.0;
            int hitSegment = -1;

            float4 pMidC = pPrevC;
            float4 vMidC = vPrevC;
            rk4_step_h(pMidC, vMidC, P, 0.5 * P.h);
            SchVarState midDX = dPrevX;
            SchVarState midDY = dPrevY;
            ray_bundle_sch_var_step(pPrevC, vPrevC, pMidC, vMidC, 0.5 * P.h, midDX, P);
            ray_bundle_sch_var_step(pPrevC, vPrevC, pMidC, vMidC, 0.5 * P.h, midDY, P);
            float4 pMidDx = pMidC + midDX.p;
            float4 pMidDy = pMidC + midDY.p;
            float3 worldMidC = ray_bundle_sch_world_pos(pMidC, basisX, basisYC, basisZC);
            float3 worldMidDx = ray_bundle_sch_world_pos(pMidDx, basisX, basisYDx, basisZDx);
            float3 worldMidDy = ray_bundle_sch_world_pos(pMidDy, basisX, basisYDy, basisZDy);

            if (segment_enter_disk(prevWC, worldMidC, P, tEnter)) {
                hitSegment = 0;
            } else if (segment_enter_disk(worldMidC, worldC, P, tEnter)) {
                hitSegment = 1;
            } else if (segment_enter_disk(prevWC, worldC, P, tEnter)) {
                hitSegment = 2;
            }

            if (hitSegment >= 0) {
                float3 c0 = prevWC;
                float3 c1 = worldC;
                float3 dx0 = prevWDx;
                float3 dx1 = worldDx;
                float3 dy0 = prevWDy;
                float3 dy1 = worldDy;
                if (hitSegment == 0) {
                    c1 = worldMidC;
                    dx1 = worldMidDx;
                    dy1 = worldMidDy;
                } else if (hitSegment == 1) {
                    c0 = worldMidC;
                    dx0 = worldMidDx;
                    dy0 = worldMidDy;
                }
                float3 hitC = mix(c0, c1, tEnter);
                float dxy = length(float2(hitC.x, hitC.y));
                if (dxy > diskEmitMin && dxy < P.re) {
                    float3 hitDx = mix(dx0, dx1, tEnter);
                    float3 hitDy = mix(dy0, dy1, tEnter);
                    return ray_bundle_weight_from_hits(P, hitC, hitDx, hitDy, diffOffset);
                }
            }
        }

        hasPrev = true;
        prevWC = worldC;
        prevWDx = worldDx;
        prevWDy = worldDy;

        float dxy = length(float2(worldC.x, worldC.y));
        if (dxy > max(P.kerrEscapeMult, 1.0) * P.re) break;
        if (pC.y < horizonRadius) break;
        if (!(isfinite(pC.x) && isfinite(pC.y) && isfinite(pC.w))) break;
    }

    return 1.0;
}

static inline void ray_bundle_wrap_kerr_state(thread KerrState& s) {
    float thetaMin = 1e-4;
    if (s.theta < thetaMin) {
        s.theta = thetaMin;
        s.ptheta = abs(s.ptheta);
    } else if (s.theta > M_PI - thetaMin) {
        s.theta = M_PI - thetaMin;
        s.ptheta = -abs(s.ptheta);
    }
    s.phi = fmod(s.phi, 2.0 * M_PI);
    if (s.phi < 0.0) s.phi += 2.0 * M_PI;
}

static inline float3 ray_bundle_kerr_world_pos(thread const KerrState& s, float massLen) {
    return conv(max(s.r, 0.0) * massLen, s.theta, s.phi);
}

static inline bool ray_bundle_kerr_state_finite(thread const KerrState& s) {
    return isfinite(s.t) && isfinite(s.r) && isfinite(s.theta) && isfinite(s.phi) &&
           isfinite(s.pr) && isfinite(s.ptheta);
}

static inline float ray_bundle_kerr_state_maxabs(thread const KerrState& s) {
    float m = abs(s.t);
    m = max(m, abs(s.r));
    m = max(m, abs(s.theta));
    m = max(m, abs(s.phi));
    m = max(m, abs(s.pr));
    m = max(m, abs(s.ptheta));
    return m;
}

static inline KerrState ray_bundle_kerr_state_delta(thread const KerrState& a,
                                                    thread const KerrState& b) {
    KerrState d;
    d.t = a.t - b.t;
    d.r = a.r - b.r;
    d.theta = a.theta - b.theta;
    d.phi = a.phi - b.phi;
    d.pr = a.pr - b.pr;
    d.ptheta = a.ptheta - b.ptheta;
    return d;
}

static inline KerrDeriv ray_bundle_kerr_variational_rhs(thread const KerrState& base,
                                                        float a,
                                                        float Lz,
                                                        thread const KerrState& dState,
                                                        float dLz) {
    float mag = max(ray_bundle_kerr_state_maxabs(dState), abs(dLz));
    float eps = clamp(1e-4 / max(mag, 1e-6), 1e-6, 2e-2);

    KerrState sPlus = base;
    sPlus.t += eps * dState.t;
    sPlus.r += eps * dState.r;
    sPlus.theta += eps * dState.theta;
    sPlus.phi += eps * dState.phi;
    sPlus.pr += eps * dState.pr;
    sPlus.ptheta += eps * dState.ptheta;
    ray_bundle_wrap_kerr_state(sPlus);

    KerrState sMinus = base;
    sMinus.t -= eps * dState.t;
    sMinus.r -= eps * dState.r;
    sMinus.theta -= eps * dState.theta;
    sMinus.phi -= eps * dState.phi;
    sMinus.pr -= eps * dState.pr;
    sMinus.ptheta -= eps * dState.ptheta;
    ray_bundle_wrap_kerr_state(sMinus);

    KerrDeriv kPlus;
    KerrDeriv kMinus;
    float nr = 0.0;
    kerr_rhs_hamiltonian(sPlus, a, Lz + eps * dLz, kPlus, nr);
    kerr_rhs_hamiltonian(sMinus, a, Lz - eps * dLz, kMinus, nr);

    float inv = 1.0 / (2.0 * eps);
    KerrDeriv out;
    out.t = (kPlus.t - kMinus.t) * inv;
    out.r = (kPlus.r - kMinus.r) * inv;
    out.theta = (kPlus.theta - kMinus.theta) * inv;
    out.phi = (kPlus.phi - kMinus.phi) * inv;
    out.pr = (kPlus.pr - kMinus.pr) * inv;
    out.ptheta = (kPlus.ptheta - kMinus.ptheta) * inv;
    return out;
}

static inline void ray_bundle_kerr_variational_step(thread const KerrState& base0,
                                                    thread const KerrState& base1,
                                                    float a,
                                                    float Lz,
                                                    float h,
                                                    thread KerrState& dState,
                                                    float dLz) {
    KerrDeriv k0 = ray_bundle_kerr_variational_rhs(base0, a, Lz, dState, dLz);
    KerrState pred = kerr_state_add(dState, k0, h);
    KerrDeriv k1 = ray_bundle_kerr_variational_rhs(base1, a, Lz, pred, dLz);
    dState.t += 0.5 * h * (k0.t + k1.t);
    dState.r += 0.5 * h * (k0.r + k1.r);
    dState.theta += 0.5 * h * (k0.theta + k1.theta);
    dState.phi += 0.5 * h * (k0.phi + k1.phi);
    dState.pr += 0.5 * h * (k0.pr + k1.pr);
    dState.ptheta += 0.5 * h * (k0.ptheta + k1.ptheta);
}

static inline float3 ray_bundle_kerr_world_offset(thread const KerrState& base,
                                                  thread const KerrState& dState,
                                                  float massLen) {
    float th = clamp(base.theta, 1e-5, M_PI - 1e-5);
    float ph = base.phi;
    float sth = sin(th);
    float cth = cos(th);
    float sph = sin(ph);
    float cph = cos(ph);
    float rWorld = max(base.r, 0.0) * massLen;
    float drWorld = dState.r * massLen;
    float dTh = dState.theta;
    float dPh = dState.phi;

    float3 eR = float3(sth * cph, sth * sph, cth);
    float3 eTh = float3(cth * cph, cth * sph, -sth);
    float3 ePh = float3(-sth * sph, sth * cph, 0.0);
    float3 dWorld = drWorld * eR + (rWorld * dTh) * eTh + (rWorld * dPh) * ePh;
    if (!(isfinite(dWorld.x) && isfinite(dWorld.y) && isfinite(dWorld.z))) return float3(0.0);
    return dWorld;
}

static inline float ray_bundle_lockstep_weight_kerr(constant Params& P,
                                                    float x,
                                                    float y,
                                                    float diffOffset) {
    float a = clamp(P.spin, -0.999, 0.999);
    float massLen = 0.5 * P.rs;
    float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
    float diskEmitMin = disk_emit_min_radius_m(P);

    float3 dirC = ray_bundle_view_dir(P, x, y);
    float3 dirDx = ray_bundle_view_dir(P, x + diffOffset, y);
    float3 dirDy = ray_bundle_view_dir(P, x, y + diffOffset);

    KerrState stateC, stateDx, stateDy;
    float LzC = 0.0, LzDx = 0.0, LzDy = 0.0;
    float horizonC = 0.0, horizonDx = 0.0, horizonDy = 0.0;
    if (!kerr_init_hamiltonian(P.camPos, dirC, a, P, stateC, LzC, horizonC)) return 1.0;
    if (!kerr_init_hamiltonian(P.camPos, dirDx, a, P, stateDx, LzDx, horizonDx)) return 1.0;
    if (!kerr_init_hamiltonian(P.camPos, dirDy, a, P, stateDy, LzDy, horizonDy)) return 1.0;
    KerrState dX = ray_bundle_kerr_state_delta(stateDx, stateC);
    KerrState dY = ray_bundle_kerr_state_delta(stateDy, stateC);
    float dLzX = LzDx - LzC;
    float dLzY = LzDy - LzC;

    bool hasPrev = false;
    float3 prevWC = float3(0.0);
    float3 prevWDx = float3(0.0);
    float3 prevWDy = float3(0.0);

    float hStep = max(P.h, 1e-6);
    float hMin = max(P.h * 0.005, 1e-7);
    float hMax = max(P.h * 2.0, hMin);
    float tol = max(P.kerrTol, 1e-6);
    int stepMul = max(P.kerrSubsteps, 1);
    int targetSteps = min(P.maxSteps * stepMul, 40000);
    int accepted = 0;
    int guard = 0;

    while (accepted < targetSteps && guard < targetSteps * 12) {
        guard += 1;
        float distH = max(stateC.r - horizonC, 0.0);
        float nearH = clamp(distH / 0.8, 0.0, 1.0);
        float hMaxLocal = max(hMin, hMax * mix(0.08, 1.0, nearH * nearH));
        hStep = clamp(hStep, hMin, hMaxLocal);

        KerrState trialC;
        float errNorm = 0.0;
        float nullResidual = 0.0;
        kerr_dp45_trial(stateC, hStep, a, LzC, trialC, errNorm, nullResidual);
        if (!(isfinite(errNorm) && isfinite(trialC.r) && isfinite(trialC.theta) && isfinite(trialC.phi) && isfinite(trialC.t))) {
            break;
        }

        float drJump = abs(trialC.r - stateC.r);
        float dThetaJump = abs(trialC.theta - stateC.theta);
        float dPhiJump = abs(trialC.phi - stateC.phi);
        float rScale = max(stateC.r, 1.0);
        bool jumpBad = (drJump > 0.20 * rScale) || (dThetaJump > 0.12) || (dPhiJump > 0.8);
        if (jumpBad) errNorm = max(errNorm, tol * 32.0);

        if (errNorm <= tol || hStep <= hMin * 1.01) {
            KerrState prevC = stateC;
            KerrState prevDX = dX;
            KerrState prevDY = dY;
            float hUsed = hStep;

            stateC = trialC;
            accepted += 1;

            ray_bundle_wrap_kerr_state(stateC);

            float ratio = max(errNorm / tol, 1e-8);
            float grow = clamp(0.9 * pow(ratio, -0.2), 0.25, 2.5);
            hStep = clamp(hStep * grow, hMin, hMaxLocal);
            if (abs(nullResidual) > 1e-6) hStep = max(hMin, hStep * 0.5);

            ray_bundle_kerr_variational_step(prevC, stateC, a, LzC, hUsed, dX, dLzX);
            ray_bundle_kerr_variational_step(prevC, stateC, a, LzC, hUsed, dY, dLzY);
            if (!ray_bundle_kerr_state_finite(dX) || !ray_bundle_kerr_state_finite(dY)) {
                break;
            }

            float3 worldC = ray_bundle_kerr_world_pos(stateC, massLen);
            float3 worldDx = worldC + ray_bundle_kerr_world_offset(stateC, dX, massLen);
            float3 worldDy = worldC + ray_bundle_kerr_world_offset(stateC, dY, massLen);

            if (hasPrev) {
                float tEnter = 0.0;
                int hitSegment = -1;

                KerrState midC;
                KerrState midDX = prevDX;
                KerrState midDY = prevDY;
                float midErr = 0.0;
                float midNull = 0.0;
                kerr_dp45_trial(prevC, 0.5 * hUsed, a, LzC, midC, midErr, midNull);
                bool validMid = isfinite(midC.r) && isfinite(midC.theta) && isfinite(midC.phi);
                float3 worldMidC = worldC;
                float3 worldMidDx = worldDx;
                float3 worldMidDy = worldDy;
                if (validMid) {
                    ray_bundle_wrap_kerr_state(midC);
                    ray_bundle_kerr_variational_step(prevC, midC, a, LzC, 0.5 * hUsed, midDX, dLzX);
                    ray_bundle_kerr_variational_step(prevC, midC, a, LzC, 0.5 * hUsed, midDY, dLzY);
                    worldMidC = ray_bundle_kerr_world_pos(midC, massLen);
                    worldMidDx = worldMidC + ray_bundle_kerr_world_offset(midC, midDX, massLen);
                    worldMidDy = worldMidC + ray_bundle_kerr_world_offset(midC, midDY, massLen);

                    if (segment_enter_disk(prevWC, worldMidC, P, tEnter)) {
                        hitSegment = 0;
                    } else if (segment_enter_disk(worldMidC, worldC, P, tEnter)) {
                        hitSegment = 1;
                    }
                }
                if (hitSegment < 0 && segment_enter_disk(prevWC, worldC, P, tEnter)) {
                    hitSegment = 2;
                }

                if (hitSegment >= 0) {
                    float3 c0 = prevWC;
                    float3 c1 = worldC;
                    float3 dx0 = prevWDx;
                    float3 dx1 = worldDx;
                    float3 dy0 = prevWDy;
                    float3 dy1 = worldDy;
                    if (hitSegment == 0 && validMid) {
                        c1 = worldMidC;
                        dx1 = worldMidDx;
                        dy1 = worldMidDy;
                    } else if (hitSegment == 1 && validMid) {
                        c0 = worldMidC;
                        dx0 = worldMidDx;
                        dy0 = worldMidDy;
                    }
                    float3 hitC = mix(c0, c1, tEnter);
                    float dxy = length(float2(hitC.x, hitC.y));
                    if (dxy > diskEmitMin && dxy < P.re) {
                        float3 hitDx = mix(dx0, dx1, tEnter);
                        float3 hitDy = mix(dy0, dy1, tEnter);
                        return ray_bundle_weight_from_hits(P, hitC, hitDx, hitDy, diffOffset);
                    }
                }
            }

            hasPrev = true;
            prevWC = worldC;
            prevWDx = worldDx;
            prevWDy = worldDy;

            float dxy = length(float2(worldC.x, worldC.y));
            if (dxy > escapeRadius) break;
            if (stateC.r <= horizonC * (1.0 + P.eps)) break;
            if (!(isfinite(stateC.r) && isfinite(stateC.theta) && isfinite(stateC.phi) && isfinite(stateC.t))) break;
        } else {
            float ratio = max(errNorm / tol, 1e-8);
            float shrink = clamp(0.9 * pow(ratio, -0.25), 0.1, 0.5);
            hStep = max(hMin, hStep * shrink);
        }
    }

    return 1.0;
}

static inline float ray_bundle_compute_jacobian_weight(constant Params& P,
                                                       float x,
                                                       float y,
                                                       float diffOffset,
                                                       thread const CollisionInfo& centerInfo) {
    if (P.rayBundleJacobian == 0u || centerInfo.hit == 0u) return 1.0;
    if (!ray_bundle_can_use_emit_pos(P)) return 1.0;
    if (FC_METRIC == 0) {
        return ray_bundle_lockstep_weight_schwarzschild(P, x, y, diffOffset);
    }
    return ray_bundle_lockstep_weight_kerr(P, x, y, diffOffset);
}

static inline bool ray_bundle_emit_pos_from_collision(constant Params& P,
                                                      thread const CollisionInfo& rec,
                                                      thread float3& emitPos) {
    bool useVolumetricEmitPos = (FC_PHYSICS_MODE == 3u &&
                                 FC_VISIBLE_MODE != 0u &&
                                 P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                 P.rayBundleJacobian != 0u);
    if (rec.hit == 0u || !(ray_bundle_can_use_emit_pos(P) || useVolumetricEmitPos)) return false;
    if (useVolumetricEmitPos) {
        emitPos = float3(rec.ct, rec._pad0, rec.direct_world.w);
        float rEmit = length(emitPos.xy);
        if (!(rEmit > 0.0) || !isfinite(rEmit) ||
            !isfinite(emitPos.x) || !isfinite(emitPos.y) || !isfinite(emitPos.z)) {
            return false;
        }
        return true;
    }
    float rEmit = rec.emit_r_norm * P.rs;
    float phiEmit = rec.emit_phi;
    float zEmit = rec.emit_z_norm * P.rs;
    if (!(rEmit > 0.0) || !isfinite(rEmit) || !isfinite(phiEmit) || !isfinite(zEmit)) return false;
    emitPos = float3(rEmit * cos(phiEmit), rEmit * sin(phiEmit), zEmit);
    if (!(isfinite(emitPos.x) && isfinite(emitPos.y) && isfinite(emitPos.z))) return false;
    return true;
}

static inline bool ray_bundle_compute_emitpos_bundle_weight(constant Params& P,
                                                            thread const CollisionInfo sampleInfos[4],
                                                            thread const uint sampleHits[4],
                                                            thread float& outWeight) {
    bool useVolumetricEmitPos = (FC_PHYSICS_MODE == 3u &&
                                 FC_VISIBLE_MODE != 0u &&
                                 P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                 P.rayBundleJacobian != 0u);
    if (P.rayBundleJacobian == 0u || !(ray_bundle_can_use_emit_pos(P) || useVolumetricEmitPos)) return false;
    float3 emitPos[4];
    for (uint i = 0u; i < 4u; ++i) {
        if (sampleHits[i] == 0u) return false;
        if (!ray_bundle_emit_pos_from_collision(P, sampleInfos[i], emitPos[i])) return false;
    }

    // The 4 bundle rays already sample the actual emissive surface. Use that quadrilateral
    // directly instead of re-estimating a separate thin-disk crossing Jacobian.
    float3 eX = 0.5 * ((emitPos[1] - emitPos[0]) + (emitPos[3] - emitPos[2]));
    float3 eY = 0.5 * ((emitPos[2] - emitPos[0]) + (emitPos[3] - emitPos[1]));
    float footprintArea = length(cross(eX, eY));
    if (!(footprintArea > 1e-30) || !isfinite(footprintArea)) return false;

    float rMean = 0.25 * (
        length(emitPos[0].xy) +
        length(emitPos[1].xy) +
        length(emitPos[2].xy) +
        length(emitPos[3].xy)
    );
    float bundleSpan = 0.5;
    float ang = max(bundleSpan / max(P.d, 1e-6), 1e-8);
    float referenceArea = max((rMean * ang) * (rMean * ang), 1e-24);
    float magnification = footprintArea / referenceArea;
    outWeight = ray_bundle_apply_magnification_controls(P, magnification);
    return isfinite(outWeight) && (outWeight > 0.0);
}

static inline bool ray_bundle_compute_center_diff_weight(constant Params& P,
                                                         thread const CollisionInfo& centerInfo,
                                                         thread const CollisionInfo& dxInfo,
                                                         thread const CollisionInfo& dyInfo,
                                                         float diffSpan,
                                                         thread float& outWeight) {
    if (P.rayBundleJacobian == 0u) return false;
    float3 emitCenter, emitDx, emitDy;
    if (!ray_bundle_emit_pos_from_collision(P, centerInfo, emitCenter)) return false;
    if (!ray_bundle_emit_pos_from_collision(P, dxInfo, emitDx)) return false;
    if (!ray_bundle_emit_pos_from_collision(P, dyInfo, emitDy)) return false;

    float3 eX = emitDx - emitCenter;
    float3 eY = emitDy - emitCenter;
    float footprintArea = length(cross(eX, eY));
    if (!(footprintArea > 1e-30) || !isfinite(footprintArea)) return false;

    float rMean = max(length(emitCenter.xy), 1e-6);
    float ang = max(diffSpan / max(P.d, 1e-6), 1e-8);
    float referenceArea = max((rMean * ang) * (rMean * ang), 1e-24);
    float magnification = footprintArea / referenceArea;
    outWeight = ray_bundle_apply_magnification_controls(P, magnification);
    return isfinite(outWeight) && (outWeight > 0.0);
}

#endif
