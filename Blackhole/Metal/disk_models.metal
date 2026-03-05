// Auto-split from integral.metal (Phase 2 refactor).
#if defined(BH_INCLUDE_DISK_MODELS) && (BH_INCLUDE_DISK_MODELS)
static inline float disk_kerr_isco_M(float a) {
    float aSafe = clamp(a, -0.999, 0.999);
    float a2 = aSafe * aSafe;
    float z1 = 1.0 + pow(max(1.0 - a2, 0.0), 1.0 / 3.0) * (pow(1.0 + aSafe, 1.0 / 3.0) + pow(1.0 - aSafe, 1.0 / 3.0));
    float z2 = sqrt(max(3.0 * a2 + z1 * z1, 0.0));
    float sgn = (aSafe >= 0.0) ? 1.0 : -1.0;
    return 3.0 + z2 - sgn * sqrt(max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0));
}

static inline float disk_horizon_radius_m(constant Params& P);

static inline float disk_inner_radius_m(constant Params& P) {
    if (FC_METRIC == 0) {
        // Schwarzschild prograde ISCO = 6M = 3rs.
        return 3.0 * P.rs;
    }
    float massLen = 0.5 * P.rs;
    float rI = disk_kerr_isco_M(clamp(P.spin, -0.999, 0.999)) * massLen;
    float rH = disk_horizon_radius_m(P);
    // Keep ISCO physically valid even when r_isco < rs at high prograde spin.
    return max(rI, rH * (1.0 + 16.0 * P.eps));
}

static inline float disk_horizon_radius_m(constant Params& P) {
    if (FC_METRIC == 0) return P.rs;
    float a = clamp(abs(P.spin), 0.0, 0.999);
    float massLen = 0.5 * P.rs;
    float rPlusM = 1.0 + sqrt(max(1.0 - a * a, 0.0));
    return max(rPlusM * massLen, 0.25 * P.rs);
}

static inline float disk_emit_min_radius_m(constant Params& P) {
    float rIn = disk_inner_radius_m(P);
    if (FC_PHYSICS_MODE == 2u) {
        float plungeFloor = clamp(P.diskPlungeFloor, 0.0, 1.0);
        if (!(plungeFloor > 1e-6)) return rIn;
        float rH = disk_horizon_radius_m(P);
        float rPlungeMin = max(rH * (1.0 + 6.0 * P.eps), 0.90 * P.rs);
        float w = clamp(plungeFloor * 1.8, 0.0, 1.0);
        return mix(rIn, rPlungeMin, w);
    }
    if (FC_PHYSICS_MODE != 1u) return rIn;
    float rH = disk_horizon_radius_m(P);
    // Thick mode can emit inside ISCO, but avoid pushing too close to horizon by default.
    return max(rH * (1.0 + 6.0 * P.eps), 0.80 * P.rs);
}

static inline float disk_half_thickness_m(float rEmitM, constant Params& P) {
    if (FC_PHYSICS_MODE != 1u && FC_PHYSICS_MODE != 2u) return P.he;
    float rr = rEmitM / max(P.rs, 1e-6);
    // Thicker around inner/mid disk, taper near horizon and far outer edge.
    float innerRamp = smoothstep(0.9, 1.6, rr);
    float outerRamp = 1.0 - smoothstep(4.0, 9.0, rr);
    float band = clamp(innerRamp * outerRamp, 0.0, 1.0);
    float thickMul = 1.0 + (max(P.diskThickScale, 1.0) - 1.0) * band;
    if (FC_PHYSICS_MODE == 2u) {
        // Precision mode uses a continuous thin->thick blend keyed by geometric H/rs.
        float hOverRs = clamp(P.he / max(P.rs, 1e-6), 0.0, 0.5);
        float geomBlend = smoothstep(0.015, 0.11, hOverRs);
        thickMul = mix(1.0, thickMul, geomBlend);
    }
    return max(P.he * thickMul, P.he);
}

static inline float disk_nt_flux_shape(float rM, float rMsM, float a) {
    if (!(rM > rMsM)) return 0.0;
    float aSafe = clamp(a, -0.999, 0.999);
    float x = sqrt(max(rM, 1e-12));
    float x0 = sqrt(max(rMsM, 1e-12));
    float psi = acos(clamp(aSafe, -0.999999, 0.999999)) / 3.0;
    float x1 =  2.0 * cos(psi - M_PI / 3.0);
    float x2 =  2.0 * cos(psi + M_PI / 3.0);
    float x3 = -2.0 * cos(psi);
    float f0 = x - x0 - 1.5 * aSafe * log(max(x / max(x0, 1e-12), 1e-12));
    float d1 = x1 * (x1 - x2) * (x1 - x3);
    float d2 = x2 * (x2 - x1) * (x2 - x3);
    float d3 = x3 * (x3 - x1) * (x3 - x2);
    d1 = (abs(d1) > 1e-12) ? d1 : copysign(1e-12, d1);
    d2 = (abs(d2) > 1e-12) ? d2 : copysign(1e-12, d2);
    d3 = (abs(d3) > 1e-12) ? d3 : copysign(1e-12, d3);
    float t1 = 3.0 * pow(x1 - aSafe, 2.0) / d1;
    float t2 = 3.0 * pow(x2 - aSafe, 2.0) / d2;
    float t3 = 3.0 * pow(x3 - aSafe, 2.0) / d3;
    float e1 = (abs(x0 - x1) > 1e-12) ? (x0 - x1) : copysign(1e-12, x0 - x1);
    float e2 = (abs(x0 - x2) > 1e-12) ? (x0 - x2) : copysign(1e-12, x0 - x2);
    float e3 = (abs(x0 - x3) > 1e-12) ? (x0 - x3) : copysign(1e-12, x0 - x3);
    float l1 = log(max((x - x1) / e1, 1e-12));
    float l2 = log(max((x - x2) / e2, 1e-12));
    float l3 = log(max((x - x3) / e3, 1e-12));
    float q = f0 - t1 * l1 - t2 * l2 - t3 * l3;
    float den = max(4.0 * M_PI * rM * x * x * (x * x * x - 3.0 * x + 2.0 * aSafe), 1e-12);
    float fpt = 1.5 * q / den;
    return (isfinite(fpt) && (fpt > 0.0)) ? fpt : 0.0;
}

static inline float disk_nt_flux_correction(float rM, float rMsM, float a) {
    if (!(rM > rMsM)) return 0.0;
    float fpt = disk_nt_flux_shape(rM, rMsM, a);
    if (!(fpt > 0.0)) return 0.0;
    float fnt = (3.0 / (8.0 * M_PI)) * pow(max(rM, 1e-9), -3.0) * max(1.0 - sqrt(rMsM / rM), 0.0);
    if (!(fnt > 0.0)) return 0.0;
    float corr = fpt / fnt;
    if (!isfinite(corr)) return 0.0;
    return clamp(corr, 0.0, 8.0);
}

static inline float thin_teff(float r_norm, constant Params& P) {
    const float sigmaSB = 5.670374419e-8;
    const float kappaEs = 0.04;

    float rr = max(r_norm, 1.0 + 1e-6);
    float rsSafe = max(P.rs, 1e-6);
    float rInNorm = max(disk_inner_radius_m(P) / rsSafe, 1.0 + 1e-6);
    if (!(rr > rInNorm)) return 0.0;

    float eta = clamp(P.diskRadiativeEfficiency, 0.01, 0.42);
    float mdotNorm = max(P.diskMdotEdd, 1e-5);
    float pref = (3.0 / 8.0) * (mdotNorm / eta) * (P.c * P.c * P.c) / max(kappaEs * rsSafe, 1e-20);
    float boundary = max(1.0 - sqrt(rInNorm / rr), 0.0);
    float flux = pref * pow(rr, -3.0) * boundary;

    float massLen = max(0.5 * rsSafe, 1e-12);
    float rM = rr * rsSafe / massLen;
    float rMsM = rInNorm * rsSafe / massLen;
    float a = (FC_METRIC == 0) ? 0.0 : clamp(P.spin, -0.999, 0.999);
    float rel = disk_nt_flux_correction(rM, rMsM, a);
    if (rel > 0.0) flux *= rel;

    float t4 = flux / sigmaSB;
    if (!(t4 > 0.0) || !isfinite(t4)) return 0.0;
    return max(pow(t4, 0.25), 1.0);
}

static inline float thin_tcol(float r_norm, constant Params& P) {
    return max(P.diskColorFactor, 1.0) * thin_teff(r_norm, P);
}

static inline float disk_effective_temperature(float rEmitM, float rInnerM, constant Params& P) {
    const float sigmaSB = 5.670374419e-8;
    const float kappaEs = 0.04;
    // Evaluate F(r) in dimensionless r/rs form to avoid float overflow.
    // F = (3/8) * (mdotEdd/eta) * c^3/(kappa_es * rs) * rr^-3 * (1 - sqrt(rr_in/rr))
    float eta = clamp(P.diskRadiativeEfficiency, 0.01, 0.42);
    float mdotNorm = max(P.diskMdotEdd, 1e-5);
    float rsSafe = max(P.rs, 1e-6);
    float rr = max(rEmitM / rsSafe, 1.0 + 1e-6);
    float rrIn = max(rInnerM / rsSafe, 1.0);
    float pref = (3.0 / 8.0) * (mdotNorm / eta) * (P.c * P.c * P.c) / max(kappaEs * rsSafe, 1e-20);
    if (rr > rrIn) {
        float boundary = max(1.0 - sqrt(rrIn / rr), 0.0);
        float flux = pref * pow(rr, -3.0) * boundary;
        if (FC_PHYSICS_MODE == 2u) {
            // Thin NT profile opt-in path (keeps legacy precision behavior when
            // precision texture is enabled).
            if (!(P.diskPrecisionTexture > 1e-6)) {
                return thin_tcol(rr, P);
            }
            float massLen = 0.5 * rsSafe;
            float rM = rEmitM / max(massLen, 1e-12);
            float rMsM = rInnerM / max(massLen, 1e-12);
            float a = (FC_METRIC == 0) ? 0.0 : clamp(P.spin, -0.999, 0.999);
            float rel = disk_nt_flux_correction(rM, rMsM, a);
            flux *= rel;
        }
        float t4 = flux / sigmaSB;
        if (!(t4 > 0.0) || !isfinite(t4)) return 0.0;
        float tEff = pow(t4, 0.25);
        if (FC_PHYSICS_MODE == 2u) {
            float fCol = max(P.diskColorFactor, 1.0);
            return tEff * fCol;
        }
        return tEff;
    }
    if (FC_PHYSICS_MODE == 2u) {
        float plungeFloor = clamp(P.diskPlungeFloor, 0.0, 1.0);
        if (!(plungeFloor > 1e-6)) return 0.0;

        // Precision mode: allow weak plunging emission continuation inside ISCO.
        // This keeps NT-like behavior outside ISCO while avoiding an artificial hard void.
        float rH = disk_horizon_radius_m(P) * (1.0 + 2.0 * P.eps);
        float rrH = max(rH / rsSafe, 0.2);
        float rrAnchor = rrIn * 1.02;
        float boundaryAnchor = max(1.0 - sqrt(rrIn / rrAnchor), 0.0);
        float fluxAnchor = pref * pow(rrAnchor, -3.0) * boundaryAnchor;
        float tAnchor = pow(max(fluxAnchor / sigmaSB, 1e-20), 0.25);
        if (!isfinite(tAnchor)) tAnchor = 0.0;

        float x = clamp((rr - rrH) / max(rrIn - rrH, 1e-6), 0.0, 1.0);
        float xSoft = smoothstep(0.0, 1.0, x);
        float captureProfile = pow(max(xSoft, 1e-4), 2.8);
        float floorProfile = pow(max(xSoft, 1e-4), 1.1);
        float plungeMix = plungeFloor * floorProfile + (1.0 - plungeFloor) * captureProfile;
        float advectiveCool = pow(max(rr / max(rrIn, 1e-4), 1e-4), 1.35);
        float captureFade = smoothstep(0.20, 0.90, xSoft);

        float fCol = max(P.diskColorFactor, 1.0);
        float tPlunge = max(tAnchor * plungeMix * advectiveCool * captureFade * fCol, 0.0);
        return isfinite(tPlunge) ? tPlunge : 0.0;
    }

    if (FC_PHYSICS_MODE != 1u) return 0.0;

    // Thick mode: finite but smooth plunging emissivity continuation inside ISCO.
    float rH = disk_horizon_radius_m(P) * (1.0 + 2.0 * P.eps);
    float rrH = max(rH / rsSafe, 0.2);
    float rrAnchor = rrIn * 1.03;
    float boundaryAnchor = max(1.0 - sqrt(rrIn / rrAnchor), 0.0);
    float fluxAnchor = pref * pow(rrAnchor, -3.0) * boundaryAnchor;
    float tAnchor = pow(max(fluxAnchor / sigmaSB, 1e-20), 0.25);
    if (!isfinite(tAnchor)) tAnchor = 0.0;

    float x = clamp((rr - rrH) / max(rrIn - rrH, 1e-6), 0.0, 1.0);
    float xSoft = smoothstep(0.0, 1.0, x);
    float plungeFloor = clamp(P.diskPlungeFloor, 0.0, 1.0);
    // Suppress horizon-proximate emission more strongly, while keeping a tunable floor.
    float captureProfile = pow(max(xSoft, 1e-4), 2.3);
    float floorProfile = max(xSoft, 1e-4);
    float plungeMix = plungeFloor * floorProfile + (1.0 - plungeFloor) * captureProfile;
    float advectiveCool = pow(max(rr / max(rrIn, 1e-4), 1e-4), 1.1);
    float captureFade = smoothstep(0.15, 0.80, xSoft);
    float thickT = max(tAnchor * plungeMix * advectiveCool * captureFade, 0.0);
    return isfinite(thickT) ? thickT : 0.0;
}

static inline float disk_visible_teff(float rEmitM, constant Params& P) {
    const float sigmaSB = 5.670374419e-8;
    float r = max(rEmitM, P.rs * 1.0001);
    float rInAuto = max(disk_inner_radius_m(P), P.rs * 1.0001);
    float rIn = (P.visibleRIn > 0.0) ? max(P.visibleRIn, P.rs * 1.0001) : rInAuto;

    if (P.visibleTeffModel == 0u) {
        float t0 = max(P.visibleTeffT0, 100.0);
        float r0 = max(P.visibleTeffR0, P.rs * 1.0001);
        float p = clamp(P.visibleTeffP, 0.05, 3.0);
        float ratio = max(r / r0, 1e-6);
        return max(t0 * pow(ratio, -p), 1.0);
    }

    // Simplified thin-disk Teff profile:
    // Teff ~ [ 3 G M dotM / (8 pi sigma r^3) * (1 - sqrt(r_in / r)) ]^(1/4)
    float m = max(P.visibleBhMass, 1e20);
    float mdot = max(P.visibleMdot, 0.0);
    if (!(r > rIn) || !(mdot > 0.0)) return 0.0;
    float boundary = max(1.0 - sqrt(rIn / r), 0.0);
    float flux = (3.0 * P.G * m * mdot) / max(8.0 * M_PI * sigmaSB * pow(r, 3.0), 1e-30);
    flux *= boundary;

    if (P.visibleTeffModel == 2u) {
        float massLen = max(0.5 * P.rs, 1e-12);
        float rM = r / massLen;
        float rInM = rIn / massLen;
        float a = (FC_METRIC == 0) ? 0.0 : clamp(P.spin, -0.999, 0.999);
        float rel = disk_nt_flux_correction(rM, rInM, a);
        flux *= rel;
    }

    float teff4 = max(flux, 0.0);
    if (!(teff4 > 0.0) || !isfinite(teff4)) return 0.0;
    return max(pow(teff4, 0.25), 1.0);
}

static inline bool disk_schwarzschild_circular_constants(float rM,
                                                         thread float& E,
                                                         thread float& L)
{
    if (!(rM > 3.01)) return false;
    float den = sqrt(max(rM * (rM - 3.0), 1e-12));
    E = (rM - 2.0) / den;
    L = rM / sqrt(max(rM - 3.0, 1e-12));
    return isfinite(E) && isfinite(L) && (E > 0.0);
}

static inline bool disk_schwarzschild_plunge_local_beta(float rM,
                                                        float rMsM,
                                                        thread float& betaR,
                                                        thread float& betaPhi)
{
    betaR = 0.0;
    betaPhi = 0.0;
    float Ems = 0.0;
    float Lms = 0.0;
    if (!disk_schwarzschild_circular_constants(rMsM, Ems, Lms)) return false;
    float w = 1.0 - 2.0 / max(rM, 1e-6);
    if (!(w > 1e-8)) return false;
    float ur2 = Ems * Ems - w * (1.0 + (Lms * Lms) / max(rM * rM, 1e-12));
    if (!(ur2 >= 0.0)) ur2 = 0.0;
    float ur = -sqrt(max(ur2, 0.0)); // inward plunge
    float ut = Ems / w;
    if (!(ut > 1e-8)) return false;
    float uphi = Lms / max(rM * rM, 1e-12);
    float drdt = ur / ut;
    betaR = drdt / w;
    betaPhi = (rM * uphi / ut) / sqrt(max(w, 1e-12));
    float beta2 = betaR * betaR + betaPhi * betaPhi;
    if (!isfinite(beta2)) return false;
    if (beta2 > 0.999 * 0.999) {
        float scale = 0.999 / sqrt(max(beta2, 1e-12));
        betaR *= scale;
        betaPhi *= scale;
    }
    return true;
}

static inline bool disk_kerr_circular_constants(float rM,
                                                float a,
                                                thread float& E,
                                                thread float& L)
{
    float rr = max(rM, 1e-6);
    float x = sqrt(rr);
    float denTerm = rr * x - 3.0 * x + 2.0 * a;
    if (!(denTerm > 1e-10)) return false;
    float den = pow(rr, 0.75) * sqrt(denTerm);
    if (!(den > 1e-12)) return false;
    E = (rr * x - 2.0 * x + a) / den;
    L = (rr * rr - 2.0 * a * x + a * a) / den;
    return isfinite(E) && isfinite(L) && (E > 0.0);
}

static inline bool disk_kerr_plunge_kinematics(float rM,
                                               float rMsM,
                                               float a,
                                               thread float& omega,
                                               thread float& drdt,
                                               thread float& vrRatioOut)
{
    float Ems = 0.0;
    float Lms = 0.0;
    if (!disk_kerr_circular_constants(rMsM, a, Ems, Lms)) return false;
    KerrCovMetric cov = kerr_cov_metric(rM, 0.5 * M_PI, a);
    float det = cov.gtphi * cov.gtphi - cov.gtt * cov.gphiphi;
    if (!(det > 1e-12)) return false;
    float ut = (Ems * cov.gphiphi + Lms * cov.gtphi) / det;
    float uphi = (-Ems * cov.gtphi - Lms * cov.gtt) / det;
    if (!(ut > 1e-8) || !isfinite(uphi)) return false;
    float ur2Num = -1.0
                 - cov.gtt * ut * ut
                 - 2.0 * cov.gtphi * ut * uphi
                 - cov.gphiphi * uphi * uphi;
    float ur2 = ur2Num / max(cov.grr, 1e-12);
    float ur = -sqrt(max(ur2, 0.0)); // inward plunge
    omega = uphi / ut;
    drdt = ur / ut;
    if (!isfinite(omega) || !isfinite(drdt)) return false;
    float vrRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
    vrRatioOut = clamp(drdt / max(vrRef, 1e-6), -1.0, 1.0);
    return true;
}

// Invariant g-factor evaluation for Schwarzschild using direct 4-vector contraction:
// g = (u_obs · k) / (u_emit · k), with k_t conserved and static observer at camera radius.
static inline float disk_schwarzschild_direct_gfactor(float rEmit,
                                                      float rObs,
                                                      float4 rayDeriv,
                                                      float betaRCoord,
                                                      float betaPhiCoord,
                                                      constant Params& P)
{
    float rE = max(rEmit, 1.0001 * P.rs);
    float rO = max(rObs, 1.0001 * P.rs);
    float wE = clamp(1.0 - P.rs / rE, 1e-8, 1.0);
    float wO = clamp(1.0 - P.rs / rO, 1e-8, 1.0);

    float br = clamp(betaRCoord, -0.9999, 0.9999);
    float bp = clamp(betaPhiCoord, -0.9999, 0.9999);
    float b2 = br * br + bp * bp;
    if (b2 > 0.999999) {
        float scale = 0.999999 / sqrt(max(b2, 1e-12));
        br *= scale;
        bp *= scale;
        b2 = br * br + bp * bp;
    }
    float gamma = 1.0 / sqrt(max(1.0 - b2, 1e-12));

    float u_t = gamma / sqrt(wE);
    float u_r = gamma * (br * P.c) * sqrt(wE);
    float u_phi = gamma * (bp * P.c) / max(rE, 1e-9);

    float k_t = -wE * P.c * P.c * rayDeriv.x;
    float k_r = rayDeriv.y / wE;
    float k_phi = rE * rE * rayDeriv.w;

    float eObs = -k_t / sqrt(wO);
    float eEmit = -(u_t * k_t + u_r * k_r + u_phi * k_phi);
    if (!(eObs > 1e-20) || !(eEmit > 1e-20) || !isfinite(eObs) || !isfinite(eEmit)) {
        return 1.0;
    }
    return clamp(eObs / eEmit, 1e-4, 1e4);
}

static inline bool inside_disk_volume(float3 pos, constant Params& P) {
    float dxy = length(float2(pos.x, pos.y));
    float rMin = disk_emit_min_radius_m(P);
    float rMax = P.re;
    float halfH = disk_half_thickness_m(dxy, P);
    if (P.diskVolumeMode != 0u && (FC_PHYSICS_MODE == 2u || FC_PHYSICS_MODE == 3u)) {
        float rs = max(P.rs, 1e-6);
        float volHalfH = max(P.diskVolumeZNormMax * rs, 1e-6);
        float volRMin = max(P.diskVolumeRNormMin * rs, rMin);
        float volRMax = max(P.diskVolumeRNormMax * rs, volRMin + 1e-6);
        rMin = max(rMin, volRMin);
        rMax = min(P.re, volRMax);
        halfH = max(halfH, volHalfH);
    }
    return (dxy > rMin && dxy < rMax && abs(pos.z) < halfH);
}

static inline bool segment_enter_disk(float3 p0,
                                      float3 p1,
                                      constant Params& P,
                                      thread float& tEnter)
{
    bool in0 = inside_disk_volume(p0, P);
    bool in1 = inside_disk_volume(p1, P);

    if (!in0 && in1) {
        float lo = 0.0;
        float hi = 1.0;
        for (int i = 0; i < 10; ++i) {
            float mid = 0.5 * (lo + hi);
            bool inMid = inside_disk_volume(mix(p0, p1, mid), P);
            if (inMid) hi = mid;
            else lo = mid;
        }
        tEnter = hi;
        return true;
    }

    // Outside -> outside skip protection for thin disk crossings.
    const int coarse = 48;
    bool prevIn = in0;
    float prevT = 0.0;
    for (int i = 1; i <= coarse; ++i) {
        float t = float(i) / float(coarse);
        bool nowIn = inside_disk_volume(mix(p0, p1, t), P);
        if (!prevIn && nowIn) {
            float lo = prevT;
            float hi = t;
            for (int j = 0; j < 10; ++j) {
                float mid = 0.5 * (lo + hi);
                bool inMid = inside_disk_volume(mix(p0, p1, mid), P);
                if (inMid) hi = mid;
                else lo = mid;
            }
            tEnter = hi;
            return true;
        }
        prevIn = nowIn;
        prevT = t;
    }
    return false;
}

static inline float hash13(float3 p3) {
    p3 = fract(p3 * 0.1031);
    p3 += dot(p3, p3.yzx + 33.33);
    return fract((p3.x + p3.y) * p3.z);
}

static inline float2 hash23(float2 p) {
    float3 p3 = fract(float3(p.x, p.y, p.x) * float3(0.1031, 0.1030, 0.0973));
    p3 += dot(p3, p3.yzx + 33.33);
    return fract(float2((p3.x + p3.y) * p3.z,
                        (p3.x + p3.z) * p3.y));
}

static inline float noise3D(float3 p) {
    float3 i = floor(p);
    float3 f = fract(p);
    float3 u = f * f * (3.0 - 2.0 * f);

    float n000 = hash13(i + float3(0.0, 0.0, 0.0));
    float n100 = hash13(i + float3(1.0, 0.0, 0.0));
    float n010 = hash13(i + float3(0.0, 1.0, 0.0));
    float n110 = hash13(i + float3(1.0, 1.0, 0.0));
    float n001 = hash13(i + float3(0.0, 0.0, 1.0));
    float n101 = hash13(i + float3(1.0, 0.0, 1.0));
    float n011 = hash13(i + float3(0.0, 1.0, 1.0));
    float n111 = hash13(i + float3(1.0, 1.0, 1.0));

    float nx00 = mix(n000, n100, u.x);
    float nx10 = mix(n010, n110, u.x);
    float nx01 = mix(n001, n101, u.x);
    float nx11 = mix(n011, n111, u.x);
    float nxy0 = mix(nx00, nx10, u.y);
    float nxy1 = mix(nx01, nx11, u.y);
    return mix(nxy0, nxy1, u.z);
}

static inline float fbm(float3 p) {
    float total = 0.0;
    float amplitude = 0.5;
    float frequency = 1.0;
    for (int i = 0; i < 4; ++i) {
        total += noise3D(p * frequency) * amplitude;
        amplitude *= 0.5;
        frequency *= 2.0;
        p += float3(0.25);
    }
    return total;
}

static inline float2 disk_div_free_turbulence(float2 q, float phase) {
    const float eps = 0.07;
    float3 base = float3(q * 4.5, phase * 0.3);
    float psiXm = noise3D(base + float3(-eps, 0.0, 0.0));
    float psiXp = noise3D(base + float3( eps, 0.0, 0.0));
    float psiYm = noise3D(base + float3(0.0, -eps, 0.0));
    float psiYp = noise3D(base + float3(0.0,  eps, 0.0));
    float dpsiDx = (psiXp - psiXm) / (2.0 * eps);
    float dpsiDy = (psiYp - psiYm) / (2.0 * eps);
    return float2(dpsiDy, -dpsiDx);
}

static inline float disk_particle_cell_density(float2 uv, float phase) {
    float2 cell = floor(uv);
    float2 f = fract(uv);
    float bestD2 = 1e9;
    for (int oy = -1; oy <= 1; ++oy) {
        for (int ox = -1; ox <= 1; ++ox) {
            float2 g = float2(float(ox), float(oy));
            float2 id = cell + g;
            float2 jitter = hash23(id + float2(phase * 0.37, -phase * 0.23));
            float2 center = g + jitter;
            float2 d = f - center;
            bestD2 = min(bestD2, dot(d, d));
        }
    }
    float dist = sqrt(bestD2);
    return smoothstep(0.62, 0.10, dist);
}

static inline float perlin_fade(float t) {
    return t * t * t * (t * (t * 6.0 - 15.0) + 10.0);
}

static inline float perlin_lerp(float a, float b, float t) {
    return a + t * (b - a);
}

static inline uint perlin_hash2(uint x, uint y, uint seed) {
    uint h = x * 374761393u + y * 668265263u + seed * 2246822519u + 3266489917u;
    h ^= (h >> 13);
    h *= 1274126177u;
    h ^= (h >> 16);
    return h;
}

static inline float perlin_grad2(uint h, float x, float y) {
    switch (h & 7u) {
        case 0u: return  x + y;
        case 1u: return -x + y;
        case 2u: return  x - y;
        case 3u: return -x - y;
        case 4u: return  x;
        case 5u: return -x;
        case 6u: return  y;
        default: return -y;
    }
}

static inline int perlin_pos_mod(int x, int m) {
    int r = x % m;
    return (r < 0) ? (r + m) : r;
}

static inline float perlin2_repeat(float x, float y, int repeatX, int repeatY, uint base) {
    int x0 = int(floor(x));
    int y0 = int(floor(y));
    int x1 = x0 + 1;
    int y1 = y0 + 1;

    float xf = x - float(x0);
    float yf = y - float(y0);

    int rx0 = perlin_pos_mod(x0, repeatX);
    int ry0 = perlin_pos_mod(y0, repeatY);
    int rx1 = perlin_pos_mod(x1, repeatX);
    int ry1 = perlin_pos_mod(y1, repeatY);

    float n00 = perlin_grad2(perlin_hash2(uint(rx0), uint(ry0), base), xf, yf);
    float n10 = perlin_grad2(perlin_hash2(uint(rx1), uint(ry0), base), xf - 1.0, yf);
    float n01 = perlin_grad2(perlin_hash2(uint(rx0), uint(ry1), base), xf, yf - 1.0);
    float n11 = perlin_grad2(perlin_hash2(uint(rx1), uint(ry1), base), xf - 1.0, yf - 1.0);

    float u = perlin_fade(xf);
    float v = perlin_fade(yf);
    float nx0 = perlin_lerp(n00, n10, u);
    float nx1 = perlin_lerp(n01, n11, u);
    return perlin_lerp(nx0, nx1, v);
}

static inline float disk_perlin_texture_noise(float dxy, float phi, float z, constant Params& P) {
    float denom = max(P.re - P.rs, 1e-6);
    float u = clamp((dxy - P.rs) / denom, 0.0, 1.0);

    float spiral = phi + 1.8 * log(max(dxy / P.rs, 1.0));
    float c = cos(spiral);
    float s = sin(spiral);

    if (P.diskNoiseModel == 2u) {
        // ec7c7cd legacy perlin path (returns [0,1]) for crisp stripe-like texture.
        float bx = 12.0 * u + 2.6 * c;
        float by = 2.6 * s;

        float w1 = perlin2_repeat(96.0 * bx, 96.0 * by, 8192, 8192, 23u);
        float w2 = perlin2_repeat(144.0 * bx + 1.6 * w1, 144.0 * by - 1.1 * w1, 8192, 8192, 71u);

        float fbmVal = 0.0;
        float amp = 1.0;
        float freq = 1.0;
        float ampSum = 0.0;
        for (int i = 0; i < 5; ++i) {
            float nx = (bx + 0.20 * w1) * freq;
            float ny = (by + 0.18 * w2) * freq;
            float n = perlin2_repeat(128.0 * nx, 128.0 * ny, 8192, 8192, 101u + uint(i * 53));
            fbmVal += amp * n;
            ampSum += amp;
            amp *= 0.55;
            freq *= 2.0;
        }
        fbmVal = (ampSum > 0.0) ? (fbmVal / ampSum) : 0.0;

        float zFade = exp(-abs(z) / max(1.25 * P.he, 1e-6));
        float edgeIn = smoothstep(0.01, 0.08, u);
        float edgeOut = 1.0 - smoothstep(0.94, 0.998, u);
        float radialFade = edgeIn * edgeOut;
        float n = clamp(3.2 * fbmVal * zFade * radialFade, -1.0, 1.0);
        return 0.5 + 0.5 * n;
    }

    float bx = 3.4 * u + 1.0 * c;
    float by = 1.0 * s;

    float w1 = perlin2_repeat(18.0 * bx, 18.0 * by, 4096, 4096, 23u);
    float w2 = perlin2_repeat(27.0 * bx + 0.9 * w1, 27.0 * by - 0.6 * w1, 4096, 4096, 71u);

    float fbmVal = 0.0;
    float amp = 1.0;
    float freq = 1.0;
    float ampSum = 0.0;
    for (int i = 0; i < 4; ++i) {
        float nx = (bx + 0.20 * w1 + 0.06 * w2) * freq;
        float ny = (by + 0.19 * w2 - 0.04 * w1) * freq;
        float n = perlin2_repeat(24.0 * nx, 24.0 * ny, 4096, 4096, 101u + uint(i * 53));
        fbmVal += amp * n;
        ampSum += amp;
        amp *= 0.60;
        freq *= 1.72;
    }
    fbmVal = (ampSum > 0.0) ? (fbmVal / ampSum) : 0.0;

    float laneCoord = 8.6 * u + 1.7 * spiral + 0.7 * w1 + 0.35 * w2;
    float filaments = 0.5 + 0.5 * sin(laneCoord);
    float coarse = 0.5 + 0.5 * fbmVal;
    float field = mix(coarse, filaments, 0.16);

    float zFade = exp(-abs(z) / max(1.25 * P.he, 1e-6));
    float edgeIn = smoothstep(0.01, 0.08, u);
    float edgeOut = 1.0 - smoothstep(0.94, 0.998, u);
    float radialFade = edgeIn * edgeOut;

    float centered = 2.0 * field - 1.0;
    centered *= 0.70 * zFade * radialFade;
    return clamp(centered, -1.0, 1.0);
}

// Classic stripe-style cloud texture from f552e72 era.
static inline float disk_classic_stripe_noise(float r, float phi, float z, constant Params& P) {
    float rNorm = (r - P.rs) / max(P.re - P.rs, 1e-6);
    float hNorm = z / max(P.he, 1e-6);

    float shearSpeed = 15.0 / (sqrt(max(rNorm, 0.0)) + 0.1);
    float angle = phi + shearSpeed;

    float3 pos = float3(rNorm * 4.0 * cos(angle),
                        rNorm * 4.0 * sin(angle),
                        hNorm * 1.5);

    float3 warp;
    warp.x = fbm(pos + float3(1.2, 3.4, 0.0));
    warp.y = fbm(pos + float3(8.3, 0.7, 0.0));
    warp.z = fbm(pos + float3(0.1, 5.2, 0.0));

    float n = fbm(pos + warp * 1.8);
    float radialEdge = smoothstep(0.0, 0.1, rNorm) * (1.0 - smoothstep(0.9, 1.0, rNorm));
    float verticalEdge = 1.0 - smoothstep(0.8, 1.6, abs(hNorm));
    n = (n - 0.4) * 2.5;
    return clamp(n * radialEdge * verticalEdge, 0.0, 1.0);
}

static inline float disk_precision_texture_factor(float dxy, float phi, float z, constant Params& P) {
    float amp = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (!(amp > 1e-6)) return 1.0;
    float centered = disk_perlin_texture_noise(dxy, phi + 0.23 * P.diskFlowTime, z, P);
    float rsSafe = max(P.rs, 1e-6);
    float rr = dxy / rsSafe;
    float radial = smoothstep(1.05, 1.9, rr) * (1.0 - smoothstep(10.0, 18.0, rr));
    float vertical = exp(-abs(z) / max(1.5 * P.he, 1e-6));
    float phaseWave = sin(7.0 * phi + 0.55 * log(max(rr, 1.0)));
    float micro = 0.72 * centered + 0.28 * phaseWave;
    float fac = 1.0 + (0.48 * amp * radial * vertical) * micro;
    return clamp(fac, 0.20, 2.10);
}

static inline float disk_flow_radial_mix(float rRs, constant Params& P) {
    float reRs = max(P.re / max(P.rs, 1e-6), 1.02);
    float x = clamp((rRs - 1.0) / max(reRs - 1.0, 1e-6), 0.0, 1.0);
    return smoothstep(0.0, 1.0, x);
}

static inline float disk_orbital_boost_at_r(float rRs, constant Params& P) {
    float t = disk_flow_radial_mix(rRs, P);
    return mix(P.diskOrbitalBoostInner, P.diskOrbitalBoostOuter, t);
}

static inline float disk_radial_drift_at_r(float rRs, constant Params& P) {
    float t = disk_flow_radial_mix(rRs, P);
    return mix(P.diskRadialDriftInner, P.diskRadialDriftOuter, t);
}

static inline float disk_turbulence_at_r(float rRs, constant Params& P) {
    float t = disk_flow_radial_mix(rRs, P);
    return mix(P.diskTurbulenceInner, P.diskTurbulenceOuter, t);
}

static inline float disk_kepler_omega(float rRs, constant Params& P) {
    float rr = max(rRs, 1.0001);
    float omega = 1.0 / max(pow_1p5(rr), 1e-6);
    if (FC_METRIC == 1) {
        float a = clamp(P.spin, -0.999, 0.999);
        omega = 1.0 / max(pow_1p5(rr) + a, 1e-6);
    }
    return disk_orbital_boost_at_r(rr, P) * omega;
}

static inline float disk_cloud_noise(float r, float phi, float z, float ctLen, constant Params& P) {
    float rs = max(P.rs, 1e-6);
    float reRs = max(P.re / rs, 1.02);
    float heRs = max(P.he / rs, 1e-5);
    float heRsSafe = max(heRs, 1e-6);
    float spanRs = max(reRs - 1.0, 1e-6);

    float rRs = clamp(r / rs, 1.0005, reRs * 1.10);
    float phiFlow = phi;
    float zRs = z / rs;

    float accum = 0.0;
    float wsum = 0.0;
    float phase = P.diskFlowTime + 0.28 * (ctLen / rs);
    int streamSteps = clamp((int)round(P.diskFlowSteps), 2, 24);
    float baseDt = clamp(P.diskFlowStep, 0.02, 0.60);
    const float invTwoPi = 0.5 / M_PI;

    for (int i = 0; i < streamSteps; ++i) {
        float radialNorm = clamp((rRs - 1.0) / spanRs, 0.0, 1.0);
        float dt = baseDt * mix(0.55, 1.0, radialNorm);
        float2 er = float2(cos(phiFlow), sin(phiFlow));
        float2 ephi = float2(-er.y, er.x);
        float2 q = radialNorm * er;
        float localPhase = phase - float(i) * dt;

        float2 turbPlane = disk_div_free_turbulence(q + 0.35 * ephi, localPhase);
        float turbR = dot(turbPlane, er);
        float turbPhi = dot(turbPlane, ephi);
        float turbZ = 2.0 * noise3D(float3(q * 5.0, localPhase * 0.8 + 17.0)) - 1.0;
        float turbAmp = disk_turbulence_at_r(rRs, P);

        float omega = disk_kepler_omega(rRs, P);
        omega += (0.18 * turbAmp * turbPhi) / max(rRs, 1.0);

        float inward = disk_radial_drift_at_r(rRs, P) * (0.35 + 0.65 * sqrt(1.0 / max(rRs, 1.0)));
        float vR = -inward + 0.28 * turbAmp * turbR;
        float vZ = -0.30 * (zRs / heRsSafe) + 0.22 * turbAmp * turbZ;

        // Backtrace streamline so local density reflects particles flowing from upstream.
        rRs = clamp(rRs - vR * dt, 1.0005, reRs * 1.15);
        phiFlow -= omega * dt;
        zRs -= vZ * dt * heRs;

        float phiWrap = phiFlow * invTwoPi;
        float azCells = mix(48.0, 180.0, 1.0 - radialNorm);
        float2 uv = float2(radialNorm * 14.0,
                           phiWrap * azCells + localPhase * (2.0 + 3.0 * (1.0 - radialNorm)));
        float particle = disk_particle_cell_density(uv, localPhase + 19.3 * radialNorm);

        float3 filPos = float3(q * (8.0 + 4.0 * (1.0 - radialNorm)),
                               (zRs / heRsSafe) * 0.9);
        filPos.z += localPhase * 0.33;
        float fil = fbm(filPos);
        float ridge = 1.0 - abs(2.0 * fil - 1.0);
        float filament = smoothstep(0.38, 0.86, ridge);

        float radialEdge = smoothstep(0.01, 0.10, radialNorm) * (1.0 - smoothstep(0.90, 1.0, radialNorm));
        float verticalEdge = 1.0 - smoothstep(0.75, 1.9, abs(zRs) / heRsSafe);
        float sample = mix(particle, filament, 0.35) * radialEdge * verticalEdge;

        float w = pow(0.74, float(i));
        accum += sample * w;
        wsum += w;
    }

    if (!(wsum > 0.0)) return 0.0;
    float density = accum / wsum;
    density = pow(clamp(density, 0.0, 1.0), 0.85);
    return density;
}

constexpr sampler ATLAS_CLAMP_SAMPLER(coord::normalized,
                                      s_address::clamp_to_edge,
                                      t_address::clamp_to_edge,
                                      filter::linear);
constexpr sampler ATLAS_REPEAT_PHI_SAMPLER(coord::normalized,
                                           s_address::repeat,
                                           t_address::clamp_to_edge,
                                           filter::linear);
constexpr sampler VOLUME_SAMPLER(coord::normalized,
                                 s_address::clamp_to_edge,
                                 t_address::repeat,
                                 r_address::clamp_to_edge,
                                 filter::linear);

static inline float4 disk_sample_atlas(float r,
                                       float phi,
                                       constant Params& P,
                                       texture2d<float, access::sample> diskAtlasTex) {
    if (P.diskAtlasMode == 0u || P.diskAtlasWidth == 0u || P.diskAtlasHeight == 0u) {
        return float4(1.0, 0.0, 0.0, 1.0);
    }

    float rs = max(P.rs, 1e-6);
    float reRs = max(P.re / rs, 1.0001);
    float atlasRMin = max(P.diskAtlasRNormMin, 0.0);
    float atlasRMax = max(P.diskAtlasRNormMax, atlasRMin + 1e-6);
    if (!(atlasRMax > atlasRMin)) {
        atlasRMin = 1.0;
        atlasRMax = reRs;
    }
    float r01 = clamp((r / rs - atlasRMin) / max(atlasRMax - atlasRMin, 1e-6), 0.0, 1.0);
    float rWarp = max(P.diskAtlasRNormWarp, 1e-3);
    float rNorm = pow(r01, rWarp);
    float phiNorm = phi * (0.5 / M_PI);
    if (P.diskAtlasWrapPhi != 0u) {
        phiNorm = fract(phiNorm);
    } else {
        phiNorm = clamp(phiNorm, 0.0, 1.0);
    }

    float atlasX = phiNorm * float(max(P.diskAtlasWidth - 1u, 0u));
    float atlasY = rNorm * float(max(P.diskAtlasHeight - 1u, 0u));
    // Keep +0.5 pixel-center mapping so texture filtering matches legacy manual bilinear.
    float u = (atlasX + 0.5) / max(float(P.diskAtlasWidth), 1.0);
    float v = (atlasY + 0.5) / max(float(P.diskAtlasHeight), 1.0);
    if (P.diskAtlasWrapPhi != 0u) {
        return diskAtlasTex.sample(ATLAS_REPEAT_PHI_SAMPLER, float2(u, v));
    }
    return diskAtlasTex.sample(ATLAS_CLAMP_SAMPLER, float2(u, v));
}

static inline float4 disk_sample_volume_grid(float rNorm,
                                             float phi,
                                             float zNorm,
                                             uint nr,
                                             uint nphi,
                                             uint nz,
                                             constant Params& P,
                                             texture3d<float, access::sample> diskVolumeTex)
{
    if (P.diskVolumeMode == 0u || nr == 0u || nphi == 0u || nz == 0u) {
        return float4(0.0);
    }
    if (nr == 1u || nphi == 1u || nz == 1u) {
        return diskVolumeTex.sample(VOLUME_SAMPLER, float3(0.5, 0.5, 0.5));
    }

    float rMin = max(P.diskVolumeRNormMin, 0.2);
    float rMax = max(P.diskVolumeRNormMax, rMin + 1e-6);
    float zMax = max(P.diskVolumeZNormMax, 1e-6);

    float ur = (rNorm - rMin) / max(rMax - rMin, 1e-6);
    float uz = (zNorm + zMax) / max(2.0 * zMax, 1e-6);
    if (!(ur >= 0.0 && ur <= 1.0 && uz >= 0.0 && uz <= 1.0)) {
        return float4(0.0);
    }
    float up = fract(phi * (0.5 / M_PI));

    float xr = ur * float(nr - 1u);
    float yp = up * float(nphi);
    float zz = uz * float(nz - 1u);

    // Keep +0.5 voxel-center mapping so texture filtering matches legacy manual trilinear.
    float u = (xr + 0.5) / max(float(nr), 1.0);
    float v = (yp + 0.5) / max(float(nphi), 1.0);
    float w = (zz + 0.5) / max(float(nz), 1.0);
    return diskVolumeTex.sample(VOLUME_SAMPLER, float3(u, v, w));
}

static inline float4 disk_sample_volume_legacy(float rNorm,
                                               float phi,
                                               float zNorm,
                                               constant Params& P,
                                               texture3d<float, access::sample> diskVolumeTex)
{
    return disk_sample_volume_grid(rNorm, phi, zNorm, P.diskVolumeR, P.diskVolumePhi, P.diskVolumeZ, P, diskVolumeTex);
}

static inline float4 disk_sample_vol0(float rNorm,
                                      float phi,
                                      float zNorm,
                                      constant Params& P,
                                      texture3d<float, access::sample> diskVol0Tex)
{
    return disk_sample_volume_grid(rNorm, phi, zNorm, P.diskVolumeR0, P.diskVolumePhi0, P.diskVolumeZ0, P, diskVol0Tex);
}

static inline float4 disk_sample_vol1(float rNorm,
                                      float phi,
                                      float zNorm,
                                      constant Params& P,
                                      texture3d<float, access::sample> diskVol1Tex)
{
    return disk_sample_volume_grid(rNorm, phi, zNorm, P.diskVolumeR1, P.diskVolumePhi1, P.diskVolumeZ1, P, diskVol1Tex);
}

#endif
