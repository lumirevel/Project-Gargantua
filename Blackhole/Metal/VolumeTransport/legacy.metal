#if defined(BH_INCLUDE_VOLUME_TRANSPORT_LEGACY) && (BH_INCLUDE_VOLUME_TRANSPORT_LEGACY)
static inline float volume_vertical_edge_gate(float zNorm, float zNormMax) {
    float edge = abs(zNorm) / max(zNormMax, 1e-6);
    return 1.0 - smoothstep(0.72, 1.0, edge);
}

static inline float volume_thick_vertical_weight(float z,
                                                 float r,
                                                 constant Params& P)
{
    float halfH = max(disk_half_thickness_m(r, P), 0.035 * max(P.rs, 1e-6));
    float zeta = z / max(halfH, 1e-6);
    return exp(-1.6 * zeta * zeta);
}

static inline float volume_legacy_tau_scale(constant Params& P) {
    float tauScale = max(P.diskVolumeTauScale, 0.0)
                   * (0.22 + 0.28 * max(P.diskCloudOpticalDepth, 0.25))
                   / max(P.rs, 1e-6);
    if (!(tauScale > 0.0)) tauScale = 0.6 / max(P.rs, 1e-6);
    if (FC_PHYSICS_MODE == 1u) {
        tauScale *= 0.72;
    }
    return tauScale;
}

static inline bool volume_integrate_thick_sample(float3 pos,
                                                 float3 obs,
                                                 float r,
                                                 float phi,
                                                 float t,
                                                 float diskInner,
                                                 float verticalEdgeGate,
                                                 float ds,
                                                 float tauScaleLegacy,
                                                 constant Params& P,
                                                 float4 rayV0,
                                                 float4 rayV1,
                                                 float LzConst,
                                                 float pr0,
                                                 float pr1,
                                                 thread VolumeAccum& A)
{
    float tauCtrl = max(P.diskCloudOpticalDepth, 0.0) * max(P.diskVolumeTauScale, 0.0);
    if (!(tauCtrl > 1e-8)) return false;

    float coverage = clamp(P.diskCloudCoverage, 0.0, 1.0);
    float porosity = clamp(P.diskCloudPorosity, 0.0, 1.0);
    float shadow = clamp(P.diskCloudShadowStrength, 0.0, 1.0);
    float vertical = volume_thick_vertical_weight(pos.z, r, P) * verticalEdgeGate;
    float rMinEmit = max(disk_emit_min_radius_m(P), 1.0001 * P.rs);
    float radial = pow(max(r / max(rMinEmit, 1e-6), 1.0), -0.9);
    float cloudNoise = 0.5 + 0.5 * disk_cloud_noise(r, phi, pos.z, P.c * P.diskFlowTime + 0.11 * r, P);
    float porousMask = smoothstep(0.35, 0.95, cloudNoise);
    float fill = mix(1.0, porousMask, porosity);
    float densityEff = tauCtrl
                     * vertical
                     * radial
                     * mix(0.35, 1.05, coverage)
                     * fill;
    float innerX = clamp((r - diskInner) / max(0.45 * diskInner, 1e-6), 0.0, 1.0);
    float innerGate = smoothstep(0.0, 1.0, innerX);
    densityEff *= mix(0.25, 1.0, innerGate);
    if (!(densityEff > 1e-6)) return false;

    float vrRatio = -0.10 * (0.5 + 0.5 * (1.0 - innerGate));
    float vphiScale = mix(0.55, 1.0, innerGate);
    float g = 1.0;
    if (FC_METRIC == 0) {
        float massLen = 0.5 * P.rs;
        float rM = r / max(massLen, 1e-12);
        float betaRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
        float betaRCoord = vrRatio * betaRef;
        float betaPhiCoord = -vphiScale * betaRef;
        if (r < diskInner * (1.0 - 1e-4)) {
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
        g = disk_schwarzschild_direct_gfactor(r, rObs, rayDeriv, betaRCoord, betaPhiCoord, P);
    } else {
        float massLen = 0.5 * P.rs;
        float rM = r / max(massLen, 1e-12);
        float a = clamp(P.spin, -0.999, 0.999);
        float diskInnerM = diskInner / max(massLen, 1e-12);
        float omega = (1.0 / max(pow_1p5(rM) + a, 1e-8)) * vphiScale;
        float drdt = vrRatio * sqrt(1.0 / max(rM, 1.0));
        if (rM < diskInnerM * (1.0 - 1e-4)) {
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

    float T = disk_effective_temperature(r, diskInner, P);
    float emiss = densityEff
                * mix(0.75, 1.85, coverage)
                * pow(max(T / 5500.0, 1e-4), 2.1);
    float dTau = min(densityEff * (1.0 + 0.8 * shadow) * ds / max(P.rs, 1e-6), 2.8);
    float trans = exp(-A.tau);
    float contrib = trans * emiss * ds;
    if (contrib > 0.0) {
        volume_accum_add_sample(A, contrib, T, g, r, vrRatio, cloudNoise, pos, obs);
        A.I += contrib;
    }
    A.tau += dTau;
    return !(A.tau < 24.0);
}

#endif
