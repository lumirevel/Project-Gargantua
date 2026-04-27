#if defined(BH_INCLUDE_VOLUME_TRANSPORT_GRMHD) && (BH_INCLUDE_VOLUME_TRANSPORT_GRMHD)
struct GrmhdDiagnosticState {
    float rhoEff;
    float b2Eff;
    float thetae;
    float sigmaProxy;
    float betaInvProxy;
    float betaMag;
    float gamma;
};

struct GrmhdRtComponents {
    float epsAbs;
    float aBase;
    float aCool;
    float aThin;
    float jThermal;
    float jThin;
    float jTotal;
    float aTotal;
    float sourceThermal;
    float sourceThin;
};

static inline float3 disk_grmhd_beta_vector(float vR,
                                            float vPhi,
                                            float vZ,
                                            constant Params& P)
{
    float3 beta = P.diskGrmhdVelScale * float3(vR, vPhi, vZ);
    float betaMax = max(max(abs(beta.x), abs(beta.y)), abs(beta.z));
    if (betaMax > 1.5) {
        beta /= max(P.c, 1e-6);
    }
    float betaMag = length(beta);
    if (betaMag > 0.999) {
        beta *= (0.999 / max(betaMag, 1e-12));
    }
    return beta;
}

static inline GrmhdDiagnosticState disk_grmhd_diagnostic_state(float rho,
                                                               float thetae,
                                                               float3 bVec,
                                                               float vR,
                                                               float vPhi,
                                                               float vZ,
                                                               constant Params& P)
{
    GrmhdDiagnosticState s;
    s.rhoEff = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);
    float bEff = length(bVec) * max(P.diskGrmhdBScale, 0.0);
    s.b2Eff = bEff * bEff;
    s.thetae = max(thetae, 1e-12);

    // Code-unit proxies: these are diagnostic indicators, not covariant GRMHD sigma/beta.
    // True sigma/beta need metric-aware b^mu, enthalpy, and pressure from the snapshot.
    s.sigmaProxy = s.b2Eff / max(s.rhoEff, 1e-30);
    s.betaInvProxy = s.b2Eff / max(s.rhoEff * s.thetae, 1e-30);

    float3 beta = disk_grmhd_beta_vector(vR, vPhi, vZ, P);
    s.betaMag = clamp(length(beta), 0.0, 0.999);
    s.gamma = 1.0 / sqrt(max(1.0 - s.betaMag * s.betaMag, 1e-12));
    return s;
}

static inline void disk_grmhd_accum_diagnostics(float rho,
                                                float thetae,
                                                float3 bVec,
                                                float vR,
                                                float vPhi,
                                                float vZ,
                                                constant Params& P,
                                                thread VolumeAccum& A)
{
    float rhoEff = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);
    float bEff = length(bVec) * max(P.diskGrmhdBScale, 0.0);
    A.maxRho = max(A.maxRho, rhoEff);
    A.maxB2 = max(A.maxB2, bEff * bEff);

    if (!(FC_TRACE_DEBUG_OFF == 0u &&
          ((P.diskGrmhdDebugView >= 10u && P.diskGrmhdDebugView <= 19u) ||
           (P.diskGrmhdDebugView >= 23u && P.diskGrmhdDebugView <= 25u)))) {
        return;
    }

    GrmhdDiagnosticState s = disk_grmhd_diagnostic_state(rho, thetae, bVec, vR, vPhi, vZ, P);
    A.maxThetae = max(A.maxThetae, s.thetae);
    A.maxSigmaProxy = max(A.maxSigmaProxy, s.sigmaProxy);
    A.maxBetaInvProxy = max(A.maxBetaInvProxy, s.betaInvProxy);
    A.maxSpeed = max(A.maxSpeed, s.betaMag);
    A.maxGamma = max(A.maxGamma, s.gamma);
}

static inline float disk_grmhd_approx_gfactor(float r,
                                              float phi,
                                              float3 obsDir,
                                              float vR,
                                              float vPhi,
                                              float vZ,
                                              constant Params& P)
{
    float rObs = max(length(P.camPos), 1.0001 * P.rs);
    float gravNum = max(1.0 - P.rs / max(r, 1.0001 * P.rs), 1e-8);
    float gravDen = max(1.0 - P.rs / max(rObs, 1.0001 * P.rs), 1e-8);
    float gGrav = sqrt(clamp(gravNum / gravDen, 1e-8, 4.0));

    float3 obs = (dot(obsDir, obsDir) > 1e-20) ? normalize(obsDir) : float3(0.0, 0.0, 1.0);
    float3 eR = float3(cos(phi), sin(phi), 0.0);
    float3 ePhi = float3(-sin(phi), cos(phi), 0.0);
    float3 eZ = float3(0.0, 0.0, 1.0);

    float3 beta = disk_grmhd_beta_vector(vR, vPhi, vZ, P);
    float betaMag = length(beta);
    float betaLos = dot(beta, float3(dot(obs, eR), dot(obs, ePhi), dot(obs, eZ)));
    betaLos = clamp(betaLos, -0.999, 0.999);
    float gamma = 1.0 / sqrt(max(1.0 - betaMag * betaMag, 1e-12));
    float doppler = 1.0 / max(gamma * (1.0 - betaLos), 1e-8);
    return clamp(gGrav * doppler, 1e-4, 1e4);
}

static inline float disk_visible_kerr_ku_gfactor(float rEmit,
                                                 float segT,
                                                 float LzConst,
                                                 float pr0,
                                                 float pr1,
                                                 constant Params& P)
{
    float massLen = max(0.5 * P.rs, 1e-12);
    float rM = max(rEmit / massLen, 1.0001);
    float a = (FC_METRIC == 0) ? 0.0 : clamp(P.spin, -0.999, 0.999);
    float omega = 1.0 / max(pow_1p5(rM) + a, 1e-8);
    float drdt = 0.0;
    float prRay = mix(pr0, pr1, clamp(segT, 0.0, 1.0));
    float g = 1.0;
    if (!disk_kerr_flow_gfactor(rM, a, omega, drdt, LzConst, prRay, g)) return 1.0;
    return g;
}

static inline float disk_planck_nu(float nuHz, float T, constant Params& P)
{
    const float H = 6.62607015e-34;
    float nu = max(nuHz, 1e6);
    float te = max(T, 1.0);
    float x = (H * nu) / max(P.k * te, 1e-30);
    x = clamp(x, 1e-8, 700.0);
    if (x > 80.0) return 0.0;
    float num = 2.0 * H * nu * nu * nu / max(P.c * P.c, 1e-20);
    float den = precise::exp(x) - 1.0;
    return num / max(den, 1e-30);
}

static inline float disk_grmhd_thetae_kelvin(float thetae)
{
    return max(5.930e9 * max(thetae, 1e-12), 1.0);
}

static inline float disk_grmhd_thetae_reference(constant Params& P)
{
    // Keep the GRMHD code-unit electron-temperature proxy reference separate from
    // the visible color-temperature anchor. Otherwise lowering T0 for a cooler
    // physical thin-disk calibration artificially inflates theta_e/theta_ref and
    // makes the volume bluer/hotter again.
    float referenceK = max(P.visibleTeffT0, 12000.0);
    return max(referenceK / 5.930e9, 1e-10);
}

static inline float disk_grmhd_photosphere_flux_mod(float rho,
                                                    float thetae,
                                                    float3 bVec,
                                                    constant Params& P)
{
    if (P.visibleTeffModel != 3u) {
        return 1.0;
    }

    // GRMHD-informed photosphere driver. This is still a code-unit closure, but
    // it is not an image-space texture: the modulation is derived from local
    // density, electron-temperature proxy, magnetic pressure and a Maxwell-stress
    // proxy. In an ideal future pipeline this should be replaced by a vertically
    // integrated q+ or radiation field from a radiative GRMHD dump.
    float stateContrast = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (stateContrast <= 1e-5) {
        return 1.0;
    }

    float rhoEff = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);
    float th = max(thetae, 1e-12);
    float3 bEff = bVec * max(P.diskGrmhdBScale, 0.0);
    float b2 = max(dot(bEff, bEff), 0.0);

    float thetaRef = disk_grmhd_thetae_reference(P);
    float rhoRatio = clamp(rhoEff / 1.0e-9, 1.0e-7, 1.0e7);
    float thetaRatio = clamp(th / thetaRef, 1.0e-4, 1.0e4);
    float pressureProxy = max(rhoEff * th, 1e-30);
    float betaInv = clamp(b2 / pressureProxy, 0.0, 1.0e8);

    // Maxwell stress proxy in the disk coordinate basis. The physically relevant
    // angular-momentum transport term is roughly -B_r B_phi; keep a small
    // absolute component because coordinate/sign conventions in public primitive
    // dumps are not guaranteed to match a single stress sign.
    float stressRaw = max(-bEff.x * bEff.y, 0.0) + 0.20 * abs(bEff.x * bEff.y);
    float stressRatio = clamp(stressRaw / max(pressureProxy + 0.10 * b2, 1e-30),
                              1e-6, 1e6);

    float heatGate = smoothstep(1e-5, 0.08, betaInv)
                   * smoothstep(1e-6, 0.45, stressRatio);
    float compression = clamp(log(rhoRatio), -10.0, 10.0);
    float electronHeat = clamp(log(thetaRatio), -8.0, 8.0);
    float stressHeat = log(1.0 + stressRatio);
    float magneticHeat = log(1.0 + betaInv);

    // Treat this as a flux modulation, not a direct RGB/tint term. The thermal
    // color later follows from T_eff ~ F^(1/4) and the spectral transport path.
    // MRI-heating proxy: turbulent disk dissipation is tied more closely to
    // Maxwell stress than to density alone. Weight stress/B structure strongly
    // enough that evolved GRMHD flow morphology survives into the thermal
    // source function instead of collapsing to a radial color-temperature map.
    float logFlux = 0.14 * compression
                  + 0.24 * electronHeat
                  + 0.46 * stressHeat
                  + 0.16 * magneticHeat;
    float flowFlux = exp(stateContrast * logFlux);
    float gatedFlux = mix(1.0, flowFlux, 0.18 + 0.82 * heatGate);
    return clamp(gatedFlux, mix(0.72, 0.12, stateContrast), mix(1.35, 32.0, stateContrast));
}

static inline void disk_grmhd_visible_thin_tail_coeffs(float rho,
                                                       float thetae,
                                                       float3 bVec,
                                                       float nuComov,
                                                       constant Params& P,
                                                       thread float& jThin,
                                                       thread float& aThin)
{
    float ne = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);
    float bRaw = length(bVec) * max(P.diskGrmhdBScale, 0.0);
    float th = clamp(thetae, 1e-4, 1e3);
    float nu = max(nuComov, 1e3);
    float bFloor = 0.02 * sqrt(max(ne * th, 1e-20));
    float bMag = max(max(bRaw, bFloor), 1e-8);

    // Code-unit optically thin visible/NIR tail. This is a diagnostic electron
    // prescription for preserving GRMHD rho/B/thetae structure, not a full
    // covariant synchrotron emissivity model.
    float alpha = clamp(P.visibleEmissionAlpha, 0.1, 3.0);
    float nuPivot = max(P.diskNuObsHz, 1e6);
    float nuRatio = max(nu / nuPivot, 1e-8);
    float rhoRef = 1.0e-9;
    float bRef = 1.0e-6;
    float thetaRef = 1.0e-3;
    float rhoState = pow(max(ne / rhoRef, 1e-6), 1.0);
    float bRatio = max(bMag / bRef, 1e-6);
    float thetaRatio = max(th / thetaRef, 1e-6);
    float sigmaProxy = (bMag * bMag) / max(ne, 1e-30);
    float betaInvProxy = (bMag * bMag) / max(ne * th, 1e-30);
    float hotElectronWeight = smoothstep(0.01, 0.45, betaInvProxy)
                            * smoothstep(1.0e-6, 8.0e-4, sigmaProxy);
    float thetaTailWeight = smoothstep(6.0e-4, 2.5e-2, th);
    float tailActivation = pow(clamp(hotElectronWeight * thetaTailWeight, 0.0, 1.0), 0.75);
    float spectralHardness = clamp(0.52 * thetaTailWeight
                                 + 0.32 * hotElectronWeight
                                 + 0.16 * smoothstep(0.18, 6.0, bRatio),
                                   0.0, 1.0);
    // Local nonthermal electron slope proxy. Hotter / more magnetized cells get
    // a harder tail; cooler cells remain steeper and redder. This is a
    // state-driven approximation to p(r,theta,phi), not a display tint.
    float alphaLocal = clamp(alpha + mix(0.38, -0.30, spectralHardness), 0.25, 2.4);
    // Power-law synchrotron scales approximately as n_e B^((p+1)/2).  For
    // alpha=(p-1)/2 this is B^(1+alpha), which preserves magnetic turbulence
    // better than the older, too-flat B^(1+0.5 alpha) proxy.
    float bState = pow(bRatio, 1.0 + alphaLocal);
    float thetaState = pow(thetaRatio, 0.95);
    // Keep only a tiny numerical floor for continuity. This optically thin
    // plasma diagnostic should be selected by hot/magnetized cells; a larger
    // floor makes the whole dense volume glow and hides turbulent state.
    float nonthermalFraction = 0.004 + 0.996 * tailActivation;
    // Let the visible/NIR roll-off vary with local plasma state. A fixed cutoff
    // makes the GRMHD fields affect only brightness, so the render becomes
    // nearly monochrome even when rho/B/theta_e structure is present. This is a
    // code-unit proxy for nu_syn ~ B * gamma_e^2, not a calibrated electron
    // distribution function.
    float nuCutLocal = 6.2e14
                     * pow(bRatio, 0.16)
                     * pow(thetaRatio, 1.05)
                     * (0.72 + 1.15 * spectralHardness);
    nuCutLocal = clamp(nuCutLocal, 2.2e14, 8.0e15);
    float cutoffSharpness = mix(0.72, 0.36, spectralHardness);
    float cutoff = exp(-pow(max(nu / nuCutLocal, 1e-8), cutoffSharpness));
    float tailShape = pow(nuRatio, -alphaLocal) * cutoff;
    // Synch-only diagnostics use raw optically thin I_nu without a thermal
    // photosphere to anchor scale. Public KHARMA/IHARM primitive dumps otherwise
    // saturate the display by many orders of magnitude, so keep a separate
    // code-unit calibration from the hybrid visible branch.
    float jNorm = (P.visibleEmissionModel == 1u) ? 4.5e-33 : 4.5e-13;
    float jRaw = jNorm * max(P.visibleSynchScale, 0.0)
               * nonthermalFraction
               * rhoState * bState * thetaState * tailShape;

    jThin = max(P.diskGrmhdEmissionScale, 0.0) * max(jRaw, 0.0);

    // This branch is explicitly the hot, optically thin visible/NIR tail.
    // Do not close it with a Kirchhoff a_nu = j_nu / B_nu(T) proxy: that makes
    // S_nu = j_nu/a_nu nearly Planck/Rayleigh-Jeans again and erases the
    // rho/B/theta_e structure we are trying to inspect. A future synchrotron
    // self-absorption model should add a physically calibrated aThin here.
    aThin = 0.0;
}

static inline float disk_grmhd_visible_temperature(float rEmitM,
                                                   float rho,
                                                   float thetae,
                                                   float3 bVec,
                                                   constant Params& P)
{
    float teK = disk_visible_teff(rEmitM, P);
    if (!(teK > 1.0) || !isfinite(teK)) {
        teK = disk_grmhd_thetae_kelvin(thetae);
    }

    if (P.visibleTeffModel != 3u) {
        return max(teK, 1.0);
    }

    // GRMHD-hybrid visible photosphere model:
    // preserve the radiative-flux color scale from Teff and use GRMHD state as
    // a bounded color-correction. Raw theta_e is often corona/X-ray-hot and must
    // not be treated as a visible blackbody temperature, but suppressing it too
    // hard makes S_nu nearly radial and erases genuine snapshot structure.
    float thetaRef = disk_grmhd_thetae_reference(P);
    float thetaRatio = clamp(max(thetae, 1e-12) / thetaRef, 0.10, 20.0);
    float stateContrast = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    float thetaExp = mix(0.08, 0.42, stateContrast);
    float thetaMod = pow(thetaRatio, thetaExp);

    GrmhdDiagnosticState state = disk_grmhd_diagnostic_state(rho, thetae, bVec, 0.0, 0.0, 0.0, P);
    float rhoRatio = clamp(state.rhoEff / 1.0e-9, 1.0e-4, 1.0e4);
    float bRatio = clamp(sqrt(max(state.b2Eff, 0.0)) / 1.0e-6, 1.0e-4, 1.0e4);
    float pressureProxy = clamp(rhoRatio * thetaRatio, 1.0e-4, 1.0e4);

    // Code-unit proxy, not a full electron thermodynamics closure: pressure and
    // magnetic compression raise the local color correction modestly, while very
    // magnetized/coronal cells are prevented from becoming a visible blackbody.
    float pressureMod = pow(pressureProxy, mix(0.0, 0.045, stateContrast));
    float magneticMod = pow(bRatio, mix(0.0, 0.070, stateContrast));
    float magThermalSuppress = rsqrt(1.0 + 0.004 * max(state.betaInvProxy, 0.0));
    float tempLo = mix(0.86, 0.48, stateContrast);
    float tempHi = mix(1.22, 2.55, stateContrast);
    float flowFluxMod = disk_grmhd_photosphere_flux_mod(rho, thetae, bVec, P);
    float flowTempMod = pow(max(flowFluxMod, 1e-6), 0.25);
    float tempMod = clamp(thetaMod * pressureMod * magneticMod * magThermalSuppress * flowTempMod,
                          tempLo,
                          tempHi);
    float teffState = max(teK * tempMod, 1.0);

    // Temperature-flow rendering keeps the Novikov/thermal Teff backbone as the
    // color-temperature scale. theta_e is a code-unit electron proxy in this
    // public dump, so using it as a direct visible blackbody temperature makes
    // the whole flow converge to the same blue-white source function. Use it
    // only as a bounded inner-flow color correction tied to magnetic/stress
    // structure.
    if (P.visibleEmissionModel == 0u) {
        float stressRaw = max(-bVec.x * bVec.y, 0.0) + 0.25 * abs(bVec.x * bVec.y);
        stressRaw *= max(P.diskGrmhdBScale * P.diskGrmhdBScale, 0.0);
        float stressGate = smoothstep(1e-6, 0.65, stressRaw / max(state.rhoEff * max(thetae, 1e-12) + 0.08 * state.b2Eff, 1e-30));
        float magnetizedGate = smoothstep(1e-5, 0.35, max(state.betaInvProxy, 0.0));
        float hotGate = smoothstep(0.45, 6.0, thetaRatio)
                      * (0.45 + 0.55 * max(stressGate, magnetizedGate));
        float rNorm = max(rEmitM / max(P.rs, 1e-6), 1.0);
        float innerThermalGate = 1.0 / (1.0 + pow(max(rNorm / 30.0, 0.0), 1.7));
        float thetaLift = clamp(log(1.0 + thetaRatio) / log(121.0), 0.0, 1.0);
        float plasmaLift = 1.0
                          + stateContrast
                          * hotGate
                          * innerThermalGate
                          * (0.72 * thetaLift + 0.22 * stressGate + 0.16 * magnetizedGate);
        float plasmaColorK = teK
                           * plasmaLift
                           * pow(max(flowFluxMod, 1e-6), 0.035)
                           * pow(max(bRatio, 1e-4), 0.018);
        float localCap = min(26000.0, max(teK * 2.35, teK + 4200.0));
        plasmaColorK = clamp(plasmaColorK, max(1200.0, teK * 0.65), localCap);
        teffState = mix(teffState, max(teffState, plasmaColorK), clamp(stateContrast * hotGate, 0.0, 0.72));
    }
    return max(teffState, 1.0);
}

static inline float disk_grmhd_thermal_source_mod(float rho,
                                                  float thetae,
                                                  float3 bVec,
                                                  constant Params& P)
{
    if (P.visibleTeffModel != 3u) {
        return 1.0;
    }

    // Unresolved photospheric filling/color-correction proxy from GRMHD state.
    // This is not image-space texture: it uses only local rho, theta_e and |B|.
    // It deliberately modulates thermal emissivity/source more than extinction so
    // the diagnostic thermal branch does not collapse to a featureless S_nu(r).
    float stateContrast = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (stateContrast <= 1e-5) {
        return 1.0;
    }

    GrmhdDiagnosticState state = disk_grmhd_diagnostic_state(rho, thetae, bVec, 0.0, 0.0, 0.0, P);
    float thetaRef = disk_grmhd_thetae_reference(P);
    float rhoRatio = clamp(state.rhoEff / 1.0e-9, 1.0e-6, 1.0e6);
    float thetaRatio = clamp(max(thetae, 1e-12) / thetaRef, 1.0e-3, 1.0e3);
    float bRatio = clamp(sqrt(max(state.b2Eff, 0.0)) / 1.0e-6, 1.0e-6, 1.0e6);
    float betaInv = clamp(state.betaInvProxy, 0.0, 1.0e8);

    float flowFluxMod = disk_grmhd_photosphere_flux_mod(rho, thetae, bVec, P);
    float logContrast = 0.10 * log(rhoRatio)
                      + 0.14 * log(thetaRatio)
                      + 0.18 * log(bRatio)
                      - 0.035 * log(1.0 + betaInv)
                      + 0.72 * log(max(flowFluxMod, 1e-6));
    float mod = exp(stateContrast * logContrast);
    return clamp(mod, mix(0.82, 0.35, stateContrast), mix(1.18, 4.80, stateContrast));
}

static inline float disk_grmhd_local_dissipation_mod(float rEmitM,
                                                     float rho,
                                                     float thetae,
                                                     float3 bVec,
                                                     float vR,
                                                     float vPhi,
                                                     float vZ,
                                                     constant Params& P)
{
    if (P.visibleTeffModel != 3u || P.visibleEmissionModel != 0u) {
        return 1.0;
    }

    // MRI-like local heating proxy for the visible thermal source. In accretion
    // disks, dissipated heat tracks turbulent stress times orbital shear
    // (schematically q+ ~ -B_r B_phi * r dOmega/dr). Public primitive dumps do
    // not provide a calibrated radiation field, so this is a bounded code-unit
    // source modulation, not an absolute luminosity model.
    float stateContrast = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (stateContrast <= 1e-5) {
        return 1.0;
    }

    GrmhdDiagnosticState state = disk_grmhd_diagnostic_state(rho, thetae, bVec, vR, vPhi, vZ, P);
    float pressureProxy = max(state.rhoEff * max(thetae, 1e-12), 1e-30);
    float b2 = max(state.b2Eff, 0.0);
    float3 bEff = bVec * max(P.diskGrmhdBScale, 0.0);
    float stressRaw = max(-bEff.x * bEff.y, 0.0) + 0.18 * abs(bEff.x * bEff.y);
    float stressRatio = clamp(stressRaw / max(pressureProxy + 0.08 * b2, 1e-30), 1e-7, 1e7);

    float rNorm = max(rEmitM / max(P.rs, 1e-6), 1.0);
    float omegaK = rsqrt(max(rNorm * rNorm * rNorm, 1e-6));
    float omegaData = abs(vPhi) / max(rNorm, 1e-4);
    float shearNorm = clamp(mix(1.0, omegaData / max(omegaK, 1e-6), 0.35), 0.35, 3.0);
    float innerGate = 1.0 / (1.0 + pow(max(rNorm / 42.0, 0.0), 1.5));
    float stressGate = smoothstep(1e-5, 0.30, stressRatio);
    float betaGate = smoothstep(2e-5, 0.60, clamp(state.betaInvProxy, 0.0, 1.0e8));
    float heatingGate = innerGate * (0.30 + 0.70 * max(stressGate, betaGate));

    float thetaRef = disk_grmhd_thetae_reference(P);
    float thetaRatio = clamp(max(thetae, 1e-12) / thetaRef, 1e-4, 1e4);
    float logQ = 0.74 * log(1.0 + stressRatio)
               + 0.18 * log(1.0 + clamp(state.betaInvProxy, 0.0, 1.0e8))
               + 0.10 * clamp(log(thetaRatio), -6.0, 6.0)
               + 0.42 * log(shearNorm);
    float mod = exp(stateContrast * heatingGate * 0.46 * logQ);
    return clamp(mod, mix(0.88, 0.42, stateContrast), mix(1.16, 3.10, stateContrast));
}

static inline float disk_grmhd_visible_thermal_radial_weight(float rEmitM,
                                                             constant Params& P)
{
    if (P.visibleTeffModel != 3u || P.visibleEmissionModel != 0u) {
        return 1.0;
    }

    // The GRMHD primitive density is a mass column proxy, not a calibrated
    // visible luminosity. Weight the thermal RT coefficient by the local
    // radiative-temperature flux scale so cold outer mass does not dominate as
    // a flat gray slab. This changes j/alpha before transport and preserves the
    // local Planck source color.
    float rNorm = max(rEmitM / max(P.rs, 1e-6), 1.0);
    float teff = max(disk_visible_teff(rEmitM, P), 1.0);
    float tRef = max(P.visibleTeffT0, 100.0);
    float fluxWeight = pow(clamp(teff / tRef, 0.0, 1.15), 5.2);
    float innerGate = smoothstep(1.55, 2.45, rNorm);
    float outerFade = 1.0 / (1.0 + pow(max(rNorm / 30.0, 0.0), 3.3));
    return clamp(innerGate * outerFade * fluxWeight, 0.0, 1.0);
}

static inline float disk_grmhd_thermal_cloud_opacity_mod(float rho,
                                                         float thetae,
                                                         float3 bVec,
                                                         constant Params& P)
{
    if (P.visibleTeffModel != 3u || P.visibleEmissionModel != 0u) {
        return 1.0;
    }

    // Thermal visible cloud structure from the imported GRMHD state. This is
    // not a screen-space texture and not a separate RGB paint layer: it changes
    // the local thermal emissivity/opacity coefficient before RT. In the
    // optically thin limit, I_nu follows the GRMHD density/B/theta_e structure;
    // in the optically thick limit, the same coefficient still converges toward
    // the local Planck source rather than becoming a dark occluder.
    float stateContrast = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (stateContrast <= 1e-5) {
        return 1.0;
    }

    GrmhdDiagnosticState state = disk_grmhd_diagnostic_state(rho, thetae, bVec, 0.0, 0.0, 0.0, P);
    float thetaRef = disk_grmhd_thetae_reference(P);
    float rhoRatio = clamp(state.rhoEff / 1.0e-9, 1.0e-7, 1.0e7);
    float thetaRatio = clamp(max(thetae, 1e-12) / thetaRef, 1.0e-4, 1.0e4);
    float bRatio = clamp(sqrt(max(state.b2Eff, 0.0)) / 1.0e-6, 1.0e-6, 1.0e6);
    float betaInv = clamp(state.betaInvProxy, 0.0, 1.0e8);

    float magnetizedGate = smoothstep(1e-4, 0.35, betaInv);
    float stressProxy = log(1.0 + abs(bVec.x * bVec.y) * max(P.diskGrmhdBScale, 0.0));
    float logCloud = 0.42 * log(rhoRatio)
                   + 0.18 * log(thetaRatio)
                   + 0.30 * log(bRatio)
                   + 0.10 * stressProxy;
    float mod = exp(stateContrast * logCloud);
    float gated = mix(mod, mod * (1.0 + 0.55 * magnetizedGate), 0.45);
    return clamp(gated, mix(0.74, 0.12, stateContrast), mix(1.35, 10.0, stateContrast));
}

static inline float disk_grmhd_thermal_thin_cloud_emissivity(float rEmitM,
                                                             float zNorm,
                                                             float rho,
                                                             float thetae,
                                                             float3 bVec,
                                                             float sourceNu,
                                                             float thermalRefEmissivity,
                                                             float residualMod,
                                                             float residualAmp,
                                                             constant Params& P)
{
    if (P.visibleTeffModel != 3u || P.visibleEmissionModel != 0u) {
        return 0.0;
    }

    // Optically thin thermal/scattering-like cloud emissivity. Density, Maxwell
    // stress, and magnetic compression decide where the gas glows, but the
    // spectrum remains the local thermal source B_nu(T). The calibration is a
    // fraction of the local LTE thermal emissivity, so this branch is in the RT
    // source term rather than a post-composite texture.
    float stateContrast = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (stateContrast <= 1e-5 ||
        !(sourceNu > 0.0) ||
        !(thermalRefEmissivity > 0.0) ||
        !isfinite(thermalRefEmissivity)) {
        return 0.0;
    }

    GrmhdDiagnosticState state = disk_grmhd_diagnostic_state(rho, thetae, bVec, 0.0, 0.0, 0.0, P);
    float rhoRatio = clamp(state.rhoEff / 1.0e-9, 1e-7, 1e7);
    float thetaRef = disk_grmhd_thetae_reference(P);
    float thetaRatio = clamp(max(thetae, 1e-12) / thetaRef, 1e-4, 1e4);
    float b2 = max(state.b2Eff, 0.0);
    float bRatio = clamp(sqrt(b2) / 1.0e-6, 1e-6, 1e6);
    float pressureProxy = max(state.rhoEff * max(thetae, 1e-12), 1e-30);
    float stressRaw = max(-bVec.x * bVec.y, 0.0) + 0.35 * abs(bVec.x * bVec.y) + 0.04 * dot(bVec, bVec);
    stressRaw *= max(P.diskGrmhdBScale * P.diskGrmhdBScale, 0.0);
    float stressRatio = clamp(stressRaw / max(pressureProxy + 0.08 * b2, 1e-30), 1e-7, 1e7);
    // Keep the emitting cloud component across the resolved volume. The earlier
    // inner-only taper was useful for avoiding halos, but it made the foreground
    // disk plane read as a non-emitting slab. A gentler radial falloff still
    // favors the energetic inner flow while allowing hot outer GRMHD structure
    // to contribute visible thermal emission.
    float rNorm = max(rEmitM / max(P.rs, 1e-6), 0.0);
    float innerWeight = 1.0 / (1.0 + pow(max(rNorm / 90.0, 0.0), 1.15));

    float logCloud = 0.50 * log(rhoRatio)
                   + 0.24 * log(thetaRatio)
                   + 0.42 * log(bRatio)
                   + 0.58 * log(1.0 + stressRatio);
    float structure = exp(stateContrast * logCloud);
    structure = clamp(structure, 0.0, 80.0);

    // Weak volume-filling thermal atmosphere floor. Keep this deliberately small:
    // if it dominates, the branch becomes a smooth replacement disk instead of a
    // GRMHD-structure carrier. Strong emission must come from resolved azimuthal
    // residual/stress below.
    float hNorm = max((0.18 + 0.10 * smoothstep(8.0, 45.0, rNorm)) * max(rNorm, 1.0), 1e-4);
    float zeta = zNorm / hNorm;
    float midplaneFill = exp(-0.5 * zeta * zeta);
    float floorState = pow(rhoRatio, 0.16)
                     * pow(thetaRatio, 0.10)
                     * pow(bRatio, 0.08)
                     * (0.55 + 0.45 * clamp(midplaneFill, 0.0, 1.0));
    float magnetizedFloor = smoothstep(1e-4, 0.55, clamp(state.betaInvProxy, 0.0, 1.0e8));
    float stressFloor = smoothstep(0.02, 1.20, stressRatio);
    float activeFloorGate = 0.08 + 0.42 * magnetizedFloor + 0.50 * stressFloor;
    float floorStructure = 0.0014 * stateContrast * clamp(floorState * activeFloorGate, 0.0, 2.2);

    // Use the local fixed-(r,z) azimuthal residual as the selector for turbulent
    // flow contrast. Absolute rho/theta/B state sets the possible emissivity, but
    // it should not make every cell glow equally; the selected branch is for
    // unresolved compressed/hot/stressed flow structure.
    float residualSelect = smoothstep(0.045, 0.70, max(residualAmp, 0.0))
                         * smoothstep(1.03, 1.72, max(residualMod, 1e-6));
    float dynamicGate = clamp(0.16 + 0.46 * stressFloor + 0.38 * magnetizedFloor, 0.0, 1.0);

    // Map code-unit contrast into a bounded fraction of the local thermal
    // emissivity. The low floor avoids reintroducing the old black slab, while
    // the residual-selected excess carries GRMHD flow morphology into RT before
    // spectral/display conversion.
    float cloudStructure = clamp(pow(max(structure, 1e-8), 0.56), 0.0, 5.8);
    float cloudExcess = clamp(cloudStructure - 1.08, 0.0, 3.4);
    float selectedExcess = residualSelect * dynamicGate * cloudExcess;
    float cloudFraction = stateContrast * innerWeight
                        * (floorStructure + 1.08 * selectedExcess);
    return max(thermalRefEmissivity, 0.0) * clamp(cloudFraction, 0.0, 2.60);
}

static inline float disk_grmhd_thin_h_over_r(float rNorm, constant Params& P)
{
    float hBase = clamp(P.thinHOverRBase, 0.002, 0.5);
    if (P.thinRadialTaperEnabled == 0u) {
        return hBase;
    }
    float hInner = clamp(P.thinHOverRInner, 0.002, 0.5);
    float hOuter = clamp(P.thinHOverROuter, 0.002, 0.5);
    float t = smoothstep(3.0, 18.0, max(rNorm, 0.0));
    return clamp(mix(hInner, hOuter, t), 0.002, 0.5);
}

static inline float disk_grmhd_visible_photosphere_weight(float rEmitM,
                                                          float zNorm,
                                                          constant Params& P)
{
    if (P.visibleTeffModel != 3u ||
        P.thinPhotosphereEnabled == 0u ||
        (P.visibleEmissionModel != 0u && P.visibleEmissionModel != 2u)) {
        return 1.0;
    }

    // Rendering-layer thermal photosphere weight only. Coordinates use the
    // renderer's disk frame: rNorm = cylindrical radius / rs and zNorm = z / rs,
    // so H/rs = (H/R) * rNorm. This does not alter the imported GRMHD state and
    // should not be applied to the optically thin kappa/coronal branch.
    float rNorm = max(rEmitM / max(P.rs, 1e-6), 1.0);
    float hOverR = disk_grmhd_thin_h_over_r(rNorm, P);
    float hNorm = max(hOverR * rNorm, 1e-4);
    float zeta = zNorm / hNorm;
    return clamp(exp(-0.5 * zeta * zeta), 0.0, 1.0);
}

// Inverse Compton corona: conservative spectral factor relative to a seed blackbody.
//
// Physical basis (Sunyaev & Titarchuk 1980, Rybicki & Lightman §7.6):
//   Compton y-parameter:  y = 4 (kT_e / m_e c²) × max(τ_es, τ_es²)
//   Unsaturated thermal Comptonization produces a weak high-frequency tail with
//   energy index approximately α = -3/2 + sqrt(9/4 + 4/y).  This diagnostic
//   helper keeps the tail amplitude proportional to y/(1+y), so y -> 0 returns
//   the seed blackbody instead of an unphysical large boost.
//
// thetae_dim:  dimensionless electron temperature kT_e / m_e c²  (≈ thetae from GRMHD)
// tau_es:      electron-scattering optical depth (estimated from density × κ_es × path)
// nu:          photon frequency in Hz (comoving)
// nu_seed:     seed blackbody peak frequency ≈ 2.82 kT_disk / h  (disk photosphere)
//
// Returns a bounded factor >= 1. This is a diagnostic visible/NIR corona proxy,
// not a replacement for a full Kompaneets or Monte-Carlo scattering solve.
static inline float disk_compton_spectral_factor(float nu,
                                                  float nu_seed,
                                                  float thetae_dim,
                                                  float tau_es)
{
    float y = 4.0 * max(thetae_dim, 1e-6) * max(tau_es, tau_es * tau_es);
    if (!(y > 1e-5)) return 1.0;

    float yEff = clamp(y, 1.0e-4, 3.0);
    float alpha_c = clamp(-1.5 + sqrt(2.25 + 4.0 / yEff), 0.45, 4.0);

    float nu_safe = max(nu, 1e9);
    float nu_s    = max(nu_seed, 1e9);
    float ratio   = max(nu_safe / nu_s, 1.0);

    // Thermal cutoff: ν_cut = 3 kT_e / h ≈ 3 × thetae_dim × m_e c² / h
    float nu_cut = 3.0 * max(thetae_dim, 1e-6) * 1.236e20;  // m_e c²/h ≈ 1.236e20 Hz
    nu_cut = clamp(nu_cut, 1e13, 1e18);
    float cutoff = exp(-max((nu_safe - nu_s) / nu_cut, 0.0));

    float tailAmplitude = clamp(y / (1.0 + y), 0.0, 0.55);
    float tailShape = pow(ratio, -alpha_c) * cutoff;
    return clamp(1.0 + tailAmplitude * tailShape, 1.0, 1.55);
}

static inline float disk_grmhd_weight_power(float w, float p)
{
    if (!(p > 1e-6)) {
        return 1.0;
    }
    return pow(clamp(w, 0.0, 1.0), clamp(p, 0.0, 8.0));
}

static inline float disk_grmhd_visible_corona_weight(float rEmitM,
                                                     float zNorm,
                                                     constant Params& P)
{
    if (P.visibleTeffModel != 3u ||
        P.coronaLayerEnabled == 0u ||
        (P.visibleEmissionModel != 1u && P.visibleEmissionModel != 2u)) {
        return 1.0;
    }

    // Rendering-layer corona envelope for radiatively efficient thin-disk views:
    // broader than the thermal photosphere, but not the full imported thick flow.
    // This preserves local GRMHD rho/theta_e/B weighting inside the allowed layer.
    float rNorm = max(rEmitM / max(P.rs, 1e-6), 1.0);
    float hOverR = clamp(P.coronaHOverR, 0.01, 2.0);
    float hNorm = max(hOverR * rNorm, 1e-4);
    float zeta = zNorm / hNorm;
    return clamp(exp(-0.5 * zeta * zeta), 0.0, 1.0);
}

static inline float disk_grmhd_visible_corona_radial_weight(float rEmitM,
                                                           constant Params& P)
{
    if (P.visibleTeffModel != 3u ||
        P.coronaLayerEnabled == 0u ||
        (P.visibleEmissionModel != 1u && P.visibleEmissionModel != 2u)) {
        return 1.0;
    }

    // Visible/NIR nonthermal corona proxy: favor the hot inner accretion flow
    // and fade the far outer volume so the render reads as a thin lensed disk,
    // not a full thick torus. This is a transfer/emissivity prior, not a change
    // to imported GRMHD density/velocity/B fields.
    float rNorm = max(rEmitM / max(P.rs, 1e-6), 1.0);
    float innerGate = smoothstep(1.6, 2.8, rNorm);
    float outerFade = 1.0 / (1.0 + pow(max(rNorm / 18.0, 0.0), 2.4));
    return clamp(innerGate * outerFade, 0.0, 1.0);
}

static inline float disk_cool_absorber_alpha(float rho,
                                             float thetae,
                                             float3 bVec,
                                             float nuComov,
                                             constant Params& P)
{
    if (P.coolAbsorptionMode == 0u) return 0.0;
    float rhoCode = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);
    if (!(rhoCode > 0.0) || !isfinite(rhoCode)) return 0.0;

    // Bridge code-units to cgs for phenomenological cool-phase absorption.
    float rhoCgs = clamp(rhoCode * 1.0e8, 1e-20, 1e2); // g cm^-3
    float teGas = max(disk_grmhd_thetae_kelvin(thetae), 10.0); // K
    float nu = max(nuComov, 1e9);

    float tSub = max(P.coolDustTSub, 300.0);
    float tWidth = max(P.coolDustTWidth, 10.0);
    float xSub = clamp((teGas - tSub) / tWidth, -40.0, 40.0);
    float dustSurvivalHot = 1.0 / (1.0 + exp(xSub));

    // Draine-like visible/NIR slope around V-band (550nm).
    float nuV = P.c / (550.0e-9);
    float xNu = max(nu / max(nuV, 1e6), 1e-6);
    float beta = clamp(P.coolDustBeta, 0.0, 4.0);
    float kappaDustDust = max(P.coolDustKappaV, 0.0) * pow(xNu, beta); // cm^2 / g_dust
    float kappaDustGas = max(P.coolDustToGas, 0.0) * kappaDustDust;    // cm^2 / g_gas

    float bMag = length(bVec) * max(P.diskGrmhdBScale, 0.0);
    float magSupp = 1.0 / (1.0 + 0.7 * pow(max(bMag / max(rhoCode, 1e-20), 0.0), 1.2));
    float rhoBoost = clamp(log(max(1.0 + 1.0e6 * rhoCgs, 1.0)), 0.0, 12.0) / 12.0;
    float coolClump = clamp(P.coolClumpStrength, 0.0, 2.0) * rhoBoost * (0.35 + 0.65 * magSupp);
    float dustPhase = clamp(max(dustSurvivalHot, coolClump), 0.0, 1.0);
    float clump = 1.0 + coolClump;

    float dustAlpha = rhoCgs * kappaDustGas * dustPhase * clump * 100.0; // m^-1

    // Cool neutral-gas opacity proxy (bound-free + molecular blend): rho*T^-3.5*nu^-s.
    float xCool = clamp((teGas - 9000.0) / 1600.0, -40.0, 40.0);
    float coolGasGate = max(1.0 / (1.0 + exp(xCool)), 0.75 * coolClump);
    float kappaGas = max(P.coolGasKappa0, 0.0)
                   * rhoCgs
                   * pow(max(teGas / 1000.0, 0.05), -3.5)
                   * pow(max(xNu, 1e-6), -max(P.coolGasNuSlope, 0.0));
    float gasAlpha = rhoCgs * kappaGas * coolGasGate * 100.0; // m^-1

    float alpha = max(dustAlpha + gasAlpha, 0.0);
    return isfinite(alpha) ? alpha : 0.0;
}

static inline void disk_grmhd_synch_coeffs(float rho,
                                           float thetae,
                                           float3 bVec,
                                           float nuComov,
                                           constant Params& P,
                                           thread float& jNu,
                                           thread float& aNu);

static inline GrmhdRtComponents disk_visible_rt_components(float rEmitM,
                                                           float rho,
                                                           float thetae,
                                                           float3 bVec,
                                                           float vR,
                                                           float vPhi,
                                                           float vZ,
                                                           float nuComov,
                                                           constant Params& P)
{
    GrmhdRtComponents c;
    c.epsAbs = 0.0;
    c.aBase = 0.0;
    c.aCool = 0.0;
    c.aThin = 0.0;
    c.jThermal = 0.0;
    c.jThin = 0.0;
    c.jTotal = 0.0;
    c.aTotal = 0.0;
    c.sourceThermal = 0.0;
    c.sourceThin = 0.0;

    float teK = disk_grmhd_visible_temperature(rEmitM, rho, thetae, bVec, P);
    float bNu = disk_planck_nu(nuComov, teK, P); // SI: W m^-2 Hz^-1 sr^-1

    // Composition-informed opacity split:
    // - electron scattering (Thomson) ~ 0.2(1+X) cm^2/g
    // - free-free absorption ~ rho * T^{-3.5} with low-frequency enhancement.
    // X=0.70, Z=0.02 are standard H/He/metal mass fractions for ionized disk plasma.
    const float X = 0.70;
    const float Z = 0.02;
    float rhoCode = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);

    // Bridge from code density to cgs scale; default keeps FM sample in a visible range.
    float rhoCgs = clamp(rhoCode * 1.0e8, 1e-20, 1e2); // g cm^-3

    float kappaEs = 0.2 * (1.0 + X); // cm^2 g^-1
    float kappaFf = 3.7e22 * (1.0 - Z) * (1.0 + X) * rhoCgs * pow(max(teK, 100.0), -3.5); // cm^2 g^-1

    // Free-free is stronger at long wavelength; keep smooth around visible pivot.
    float nuRef = 5.0e14;
    float nuScale = pow(max(nuComov / nuRef, 1e-6), -2.0);
    kappaFf *= nuScale;
    kappaFf = max(kappaFf, 0.0);

    float kappaTot = max(kappaEs + kappaFf, 1e-30);
    c.epsAbs = clamp(kappaFf / kappaTot, 0.01, 1.0); // thermalization fraction
    float thermalization = sqrt(max(c.epsAbs, 1e-6));

    // Convert rho*kappa [cm^-1] -> [m^-1].
    float alphaTot = (rhoCgs * kappaTot) * 100.0;
    // The code-unit density bridge above is intentionally approximate. In the
    // hybrid visible path, using the thermal photosphere opacity default from
    // the pure blackbody path makes the flow close to a smooth tau~1 surface and
    // hides GRMHD structure. Keep blackbody conservative, but default hybrid to
    // a thinner effective visible opacity; --visible-kappa remains the explicit
    // calibration override.
    float kappaDefault = (P.visibleEmissionModel == 2u && P.visibleTeffModel == 3u) ? 0.036 : 0.12;
    float kappaScale = (P.visibleKappa > 0.0) ? P.visibleKappa : kappaDefault;
    // For the GRMHD visible thermal volume, do not model electron scattering as
    // a one-way dark absorber. Use an effective thermal absorption opacity and
    // close emission with the same local source function below. Then optically
    // thick, similarly hot gas approaches B_nu(T) instead of becoming a black
    // slab. Hybrid/nonthermal diagnostics keep the older thermalization opacity
    // to avoid overwhelming the optically thin branch.
    float opacityClosure = (P.visibleTeffModel == 3u && P.visibleEmissionModel == 0u)
        ? max(c.epsAbs, 0.018)
        : thermalization;
    c.aBase = max(P.diskGrmhdAbsorptionScale, 0.0) * alphaTot * kappaScale * opacityClosure;
    c.aCool = max(P.diskGrmhdAbsorptionScale, 0.0)
            * disk_cool_absorber_alpha(rho, thetae, bVec, nuComov, P);

    // Thermal source. The blackbody GRMHD volume path intentionally uses an
    // LTE-like closure S_nu ~= B_nu(T) times a bounded GRMHD heating/filling
    // correction. This is the key distinction from a cold absorbing cloud: if a
    // dense region is hot, increased opacity makes the ray converge toward its
    // local Planck source instead of extinguishing the disk behind it.
    float sourceMod = disk_grmhd_thermal_source_mod(rho, thetae, bVec, P);
    float dissipationMod = disk_grmhd_local_dissipation_mod(rEmitM, rho, thetae, bVec, vR, vPhi, vZ, P);
    float sourceClosure = (P.visibleTeffModel == 3u && P.visibleEmissionModel == 0u)
        ? 1.0
        : thermalization;
    c.sourceThermal = sourceClosure * bNu * sourceMod * dissipationMod;
    c.jThermal = max(P.diskGrmhdEmissionScale, 0.0) * c.aBase * c.sourceThermal;

    // Inverse Compton boost in optically thin plasma (corona / transition layer).
    //
    // Physical basis: when free-free opacity is small relative to electron scattering
    // (c.epsAbs → 0), the medium is an electron-scattering-dominated atmosphere.
    // Seed photons from the disk photosphere are Compton upscattered by hot electrons,
    // producing a power-law spectrum above the blackbody peak.
    //
    // This is gated to zero in the optically thick disk body (c.epsAbs → 1, LTE) and
    // peaks in the hot optically thin corona (c.epsAbs → 0, kT_e >> kT_disk).
    if (P.visibleEmissionModel == 0u || P.visibleEmissionModel == 2u) {
        float thinGate = clamp(1.0 - c.epsAbs, 0.0, 1.0);   // 1 in corona, 0 at midplane
        if (thinGate > 1e-4) {
            // Seed frequency: blackbody peak of the disk photosphere ≈ 2.82 kT_disk / h
            // Use teK as a proxy (slightly high in corona, but bounded by sourceMod weighting).
            float kB_over_h = 2.084e10; // k_B / h_Planck in Hz/K
            float nu_seed = max(2.82 * teK * kB_over_h, 1e10);
            // Electron-scattering τ proxy from local opacity × a representative path (0.5 m).
            float tau_es_proxy = clamp(c.aBase * 0.5 * kappaEs / max(kappaTot, 1e-30), 0.0, 2.0);
            float comptonFactor = disk_compton_spectral_factor(nuComov, nu_seed, thetae, tau_es_proxy);
            // Blend: conservative 40 % maximum boost to avoid overwhelming the thermal floor.
            float boost = mix(1.0, max(comptonFactor, 1.0), 0.40 * thinGate);
            c.jThermal    *= boost;
            c.sourceThermal *= boost;
        }
    }

    if (P.visibleEmissionModel == 2u) {
        disk_grmhd_visible_thin_tail_coeffs(rho, thetae, bVec, nuComov, P, c.jThin, c.aThin);
        c.sourceThin = (c.aThin > 1e-30) ? c.jThin / max(c.aThin, 1e-30) : c.jThin;
    }

    if (P.visibleEmissionModel == 0u || P.visibleEmissionModel == 2u) {
        c.jTotal = max(c.jThermal + c.jThin, 0.0);
        c.aTotal = max(c.aBase + c.aCool + c.aThin, 0.0);
        return c;
    }

    // Synchrotron-only branch for isolated inspection of the optically thin
    // contribution. Thermal coefficients above remain available for diagnostics.
    disk_grmhd_synch_coeffs(rho, thetae, bVec, nuComov, P, c.jTotal, c.aTotal);
    c.aTotal += c.aCool;
    c.jThin = c.jTotal;
    c.aThin = max(c.aTotal - c.aCool, 0.0);
    c.sourceThin = (c.aThin > 1e-30) ? c.jThin / max(c.aThin, 1e-30) : c.jThin;
    return c;
}

static inline void disk_visible_rt_coeffs(float rEmitM,
                                          float rho,
                                          float thetae,
                                          float3 bVec,
                                          float nuComov,
                                          constant Params& P,
                                          thread float& jNu,
                                          thread float& aNu)
{
    GrmhdRtComponents c = disk_visible_rt_components(rEmitM, rho, thetae, bVec, 0.0, 0.0, 0.0, nuComov, P);
    jNu = c.jTotal;
    aNu = c.aTotal;
}

static inline void disk_grmhd_synch_coeffs(float rho,
                                           float thetae,
                                           float3 bVec,
                                           float nuComov,
                                           constant Params& P,
                                           thread float& jNu,
                                           thread float& aNu)
{
    float ne = max(rho * max(P.diskGrmhdDensityScale, 0.0), 0.0);
    float bRaw = length(bVec) * max(P.diskGrmhdBScale, 0.0);
    float th = clamp(thetae, 1e-4, 1e3);
    float nu = max(nuComov, 1e3);
    float bFloor = 0.02 * sqrt(max(ne * th, 1e-20));
    float bMag = max(max(bRaw, bFloor), 1e-8);

    // Coarse thermal synchrotron shape for scalar I_nu (extensible to full polarized GRRT later).
    float nuCrit = max(2.8e11 * bMag * th * th, 1e6);
    float x = nu / nuCrit;
    float x13 = pow(max(x, 1e-8), 1.0 / 3.0);
    float kernVal = exp(-min(x13, 40.0)) / max(1.0 + x + x13, 1e-8);
    float jThermal = ne * bMag * kernVal;

    // Visible/NIR synchrotron from the current demo-scale GRMHD fields is far above
    // the thermal critical frequency. Model only this explicitly requested
    // synchrotron mode as an optically thin nonthermal tail; blackbody mode remains
    // the strict thermal photosphere path. This is a code-unit emissivity
    // prescription, not a replacement for a future electron distribution function.
    float jNonthermal = 0.0;
    float aNonthermal = 0.0;
    if (visible_mode_enabled_fc() && P.visibleEmissionModel == 1u) {
        disk_grmhd_visible_thin_tail_coeffs(rho, thetae, bVec, nuComov, P, jNonthermal, aNonthermal);
        jNu = max(jNonthermal, 0.0);
        aNu = max(aNonthermal, 0.0);
        return;
    }

    float jCom = max(P.diskGrmhdEmissionScale, 0.0) * max(jThermal, 0.0) + max(jNonthermal, 0.0);

    // Kirchhoff closure with Rayleigh-Jeans source function.
    float teK = max(5.930e9 * th, 1.0);
    float bNuRJ = (2.0 * P.k * teK * nu * nu) / max(P.c * P.c, 1e-20);
    float aCom = 0.0;
    if (bNuRJ > 1e-30) {
        aCom = max(P.diskGrmhdEmissionScale, 0.0) * jThermal / bNuRJ;
        aCom += aNonthermal / max(P.diskGrmhdAbsorptionScale, 1e-30);
    }
    aCom *= max(P.diskGrmhdAbsorptionScale, 0.0);

    jNu = max(jCom, 0.0);
    aNu = max(aCom, 0.0);
}


static inline bool volume_commit_grmhd_visible_surface_hit(float3 pos,
                                                           float3 obs,
                                                           float r,
                                                           float phi,
                                                           float zNorm,
                                                           float t,
                                                           float rNormMin,
                                                           float rNormMax,
                                                           float rhoThreshold,
                                                           float rho,
                                                           float vR,
                                                           float LzConst,
                                                           float pr0,
                                                           float pr1,
                                                           constant Params& P,
                                                           texture3d<float, access::sample> diskVol0Tex,
                                                           texture3d<float, access::sample> diskVol1Tex,
                                                           thread VolumeAccum& A,
                                                           thread bool& havePrevVisibleSample,
                                                           thread float& prevRho,
                                                           thread float& prevT,
                                                           thread float3& prevPos)
{
    bool crossing = false;
    float tHit = t;
    float3 hitPos = pos;
    float rhoHit = rho;
    float vRHit = vR;

    if (havePrevVisibleSample) {
        if (prevRho < rhoThreshold && rho >= rhoThreshold) {
            float den = rho - prevRho;
            float tCross = (abs(den) > 1e-30) ? clamp((rhoThreshold - prevRho) / den, 0.0, 1.0) : 1.0;
            tHit = mix(prevT, t, tCross);
            hitPos = mix(prevPos, pos, tCross);
            crossing = true;
        }
    } else if (rho >= rhoThreshold) {
        crossing = true;
    }

    if (!crossing) {
        havePrevVisibleSample = true;
        prevRho = rho;
        prevPos = pos;
        prevT = t;
        return false;
    }

    float rHit = length(hitPos.xy);
    float phiHit = atan2(hitPos.y, hitPos.x);
    float rNormHit = rHit / max(P.rs, 1e-6);
    float zNormHit = hitPos.z / max(P.rs, 1e-6);
    float4 vol0Hit = disk_sample_vol0(rNormHit, phiHit, zNormHit, P, diskVol0Tex);
    float4 vol1Hit = disk_sample_vol1(rNormHit, phiHit, zNormHit, P, diskVol1Tex);
    rhoHit = exp(clamp(vol0Hit.x, -40.0, 40.0));
    vRHit = vol0Hit.z;
    float thetaeHit = exp(clamp(vol0Hit.y, -30.0, 20.0));
    float3 bVecHit = float3(vol1Hit.y, vol1Hit.z, vol1Hit.w);
    disk_grmhd_accum_diagnostics(rhoHit, thetaeHit, bVecHit, vol0Hit.z, vol0Hit.w, vol1Hit.x, P, A);

    float rhoContrast = 1.0;
    float thetaeContrast = 1.0;
    float bContrast = 1.0;
    float textureStrength = clamp(P.diskPrecisionTexture, 0.0, 1.0);
    if (textureStrength > 1e-5) {
        float drNorm = max(0.012 * max(rNormHit, 1.0), 0.006);
        float dPhi = 0.018;
        float rNormP = min(rNormHit + drNorm, rNormMax);
        float rNormM = max(rNormHit - drNorm, rNormMin);
        float4 vol0RP = disk_sample_vol0(rNormP, phiHit, zNormHit, P, diskVol0Tex);
        float4 vol0RM = disk_sample_vol0(rNormM, phiHit, zNormHit, P, diskVol0Tex);
        float4 vol0PP = disk_sample_vol0(rNormHit, phiHit + dPhi, zNormHit, P, diskVol0Tex);
        float4 vol0PM = disk_sample_vol0(rNormHit, phiHit - dPhi, zNormHit, P, diskVol0Tex);
        float4 vol1RP = disk_sample_vol1(rNormP, phiHit, zNormHit, P, diskVol1Tex);
        float4 vol1RM = disk_sample_vol1(rNormM, phiHit, zNormHit, P, diskVol1Tex);
        float4 vol1PP = disk_sample_vol1(rNormHit, phiHit + dPhi, zNormHit, P, diskVol1Tex);
        float4 vol1PM = disk_sample_vol1(rNormHit, phiHit - dPhi, zNormHit, P, diskVol1Tex);

        float rhoAvg = 0.25 * (
            exp(clamp(vol0RP.x, -40.0, 40.0)) +
            exp(clamp(vol0RM.x, -40.0, 40.0)) +
            exp(clamp(vol0PP.x, -40.0, 40.0)) +
            exp(clamp(vol0PM.x, -40.0, 40.0))
        );
        float thetaeAvg = 0.25 * (
            exp(clamp(vol0RP.y, -30.0, 20.0)) +
            exp(clamp(vol0RM.y, -30.0, 20.0)) +
            exp(clamp(vol0PP.y, -30.0, 20.0)) +
            exp(clamp(vol0PM.y, -30.0, 20.0))
        );
        float bAvg = 0.25 * (
            length(float3(vol1RP.y, vol1RP.z, vol1RP.w)) +
            length(float3(vol1RM.y, vol1RM.z, vol1RM.w)) +
            length(float3(vol1PP.y, vol1PP.z, vol1PP.w)) +
            length(float3(vol1PM.y, vol1PM.z, vol1PM.w))
        );
        rhoContrast = rhoHit / max(rhoAvg, 1e-30);
        thetaeContrast = thetaeHit / max(thetaeAvg, 1e-30);
        bContrast = length(bVecHit) / max(bAvg, 1e-30);
    }

    float g = disk_grmhd_approx_gfactor(rHit, phiHit, obs, vol0Hit.z, vol0Hit.w, vol1Hit.x, P);
    if (FC_METRIC != 0) {
        g = disk_visible_kerr_ku_gfactor(rHit, tHit, LzConst, pr0, pr1, P);
    }
    if (!isfinite(g)) g = 1.0;

    float teff = disk_grmhd_visible_temperature(rHit, rhoHit, thetaeHit, bVecHit, P);
    if (!(teff > 1.0) || !isfinite(teff)) {
        float t0Fallback = max(P.visibleTeffT0, 100.0);
        float r0Fallback = max(P.visibleTeffR0, P.rs * 1.0001);
        float pFallback = clamp(P.visibleTeffP, 0.05, 3.0);
        float ratioFallback = max(rHit / r0Fallback, 1e-6);
        teff = max(t0Fallback * pow(ratioFallback, -pFallback), 1.0);
    }
    if (textureStrength > 1e-5) {
        float logRho = log(clamp(rhoContrast, 1e-4, 1e4));
        float logThetae = log(clamp(thetaeContrast, 1e-4, 1e4));
        float logB = log(clamp(bContrast, 1e-4, 1e4));
        float logTex = 0.68 * logRho + 0.22 * logThetae + 0.10 * logB;
        float texMod = exp(textureStrength * 0.42 * logTex);
        teff *= clamp(texMod, 0.55, 1.85);
    }
    if (!(teff > 1.0) || !isfinite(teff)) {
        havePrevVisibleSample = true;
        prevRho = rho;
        prevPos = pos;
        prevT = t;
        return false;
    }

    float logRho = log(clamp(rhoContrast, 1e-4, 1e4));
    float logThetae = log(clamp(thetaeContrast, 1e-4, 1e4));
    float logB = log(clamp(bContrast, 1e-4, 1e4));
    float texSignal = 0.5 + 0.5 * tanh(0.95 * (0.70 * logRho + 0.20 * logThetae + 0.10 * logB));
    float rhoOcc = clamp(rhoThreshold > 0.0 ? (rhoHit / max(rhoHit + rhoThreshold, 1e-30)) : (rhoHit / max(rhoHit + 1.0, 1e-30)), 0.0, 1.0);
    float texMix = clamp(textureStrength * 0.85, 0.0, 0.85);
    A.surfaceHit = 1u;
    A.w = 1.0;
    A.I = 1e-20;
    A.temp4 = pow(max(teff, 1.0), 4.0);
    A.g = clamp(g, 1e-4, 1e4);
    A.r = rHit;
    A.vr = vRHit;
    A.noise = clamp(mix(rhoOcc, texSignal, texMix), 0.0, 1.0);
    A.x = hitPos.x;
    A.y = hitPos.y;
    A.z = hitPos.z;
    A.ox = obs.x;
    A.oy = obs.y;
    A.oz = obs.z;
    A.maxJ = max(A.maxJ, 0.0);
    A.maxI = max(A.maxI, A.I);
    A.samples = 1u;
    return true;
}

static inline bool volume_finalize_grmhd_visible_sample(bool expressiveVisible,
                                                        bool polarized,
                                                        float rho,
                                                        float thetae,
                                                        float3 bVec,
                                                        float g,
                                                        float r,
                                                        float vR,
                                                        float3 pos,
                                                        float3 obs,
                                                        constant Params& P,
                                                        float3 iPrevNu,
                                                        float3 qPrevNu,
                                                        float3 uPrevNu,
                                                        float3 vPrevNu,
                                                        thread VolumeAccum& A,
                                                        thread float& dI)
{
    float3 dINu = max(A.IVisNu - iPrevNu, float3(0.0));
    float dIVis = dot(dINu, float3(0.13344, 0.85742, 0.00914));
    dI = expressiveVisible ? dI : dIVis;
    if (!expressiveVisible) {
        A.I = dot(A.IVisNu, float3(0.13344, 0.85742, 0.00914));
        A.tau = max(max(A.tauVis.x, A.tauVis.y), A.tauVis.z);
    }
    if (polarized) {
        A.QVisNu = clamp(A.QVisNu, -A.IVisNu, A.IVisNu);
        A.UVisNu = clamp(A.UVisNu, -A.IVisNu, A.IVisNu);
        A.VVisNu = clamp(A.VVisNu, -A.IVisNu, A.IVisNu);
    } else {
        A.QVisNu = qPrevNu;
        A.UVisNu = uPrevNu;
        A.VVisNu = vPrevNu;
    }

    if (P.visibleEmissionModel == 0u &&
        P.visibleThermalTransferMode == 1u &&
        (A.tauSurfaceMask & 0x7u) == 0x7u) {
        A.tau = max(max(A.tauVis.x, A.tauVis.y), A.tauVis.z);
        A.maxI = max(A.maxI, A.I);
        if (dI > 0.0) {
            float teK = disk_grmhd_visible_temperature(r, rho, thetae, bVec, P);
            volume_accum_add_sample(
                A, dI, teK, g, r, vR,
                clamp(rho / (rho + 1.0), 0.0, 1.0),
                pos, obs
            );
        }
        return true;
    }

    if (P.visibleEmissionModel == 0u && A.tauVis.y >= 0.9) {
        A.tau = max(max(A.tauVis.x, A.tauVis.y), A.tauVis.z);
        A.maxI = max(A.maxI, A.I);
        if (dI > 0.0) {
            float teK = disk_grmhd_visible_temperature(r, rho, thetae, bVec, P);
            volume_accum_add_sample(
                A, dI, teK, g, r, vR,
                clamp(rho / (rho + 1.0), 0.0, 1.0),
                pos, obs
            );
        }
        return true;
    }
    return false;
}

static inline void volume_integrate_grmhd_scalar_sample(float rho,
                                                        float thetae,
                                                        float3 bVec,
                                                        float g,
                                                        float r,
                                                        float ds,
                                                        constant Params& P,
                                                        thread VolumeAccum& A,
                                                        thread float& dI)
{
    float nuComov = max(P.diskNuObsHz / max(g, 1e-8), 1e3);
    float jCom = 0.0;
    float aCom = 0.0;
    disk_grmhd_synch_coeffs(rho, thetae, bVec, nuComov, P, jCom, aCom);

    float jObs = jCom * g * g;
    float aObs = aCom / max(g, 1e-8);
    if (!(isfinite(jObs) && isfinite(aObs))) {
        A.invalidSamples += 1u;
        dI = 0.0;
        return;
    }
    A.maxJ = max(A.maxJ, jObs);
    A.maxAlpha = max(A.maxAlpha, max(aObs, 0.0));
    float IPrev = A.I;
    if (aObs > 1e-12) {
        float dTau = min(aObs * ds, 40.0);
        float tauBefore = A.tau;
        volume_accum_note_transfer(A, jObs, aObs, tauBefore, dTau, r, ds, P);
        float trans = exp(-dTau);
        float src = jObs / max(aObs, 1e-30);
        A.I = IPrev * trans + src * (1.0 - trans);
        A.tau += dTau;
    } else {
        volume_accum_note_transfer(A, jObs, aObs, 0.0, 0.0, r, ds, P);
        A.I = IPrev + jObs * ds;
    }
    dI = max(A.I - IPrev, 0.0);
}

static inline bool volume_finalize_grmhd_sample_tail(float rho,
                                                     float thetae,
                                                     float bMag,
                                                     float g,
                                                     float r,
                                                     float vR,
                                                     float texLocal,
                                                     float texStrength,
                                                     float3 pos,
                                                     float3 obs,
                                                     thread VolumeAccum& A,
                                                     thread float& prevRhoVolume,
                                                     thread float& prevThetaeVolume,
                                                     thread float& prevBVolume,
                                                     thread bool& havePrevVolumeSample,
                                                     float dI)
{
    A.maxI = max(A.maxI, A.I);
    if (dI > 0.0) {
        float teK = disk_grmhd_thetae_kelvin(thetae);
        float noiseSample = clamp(mix(0.5, texLocal, texStrength), 0.0, 1.0);
        volume_accum_add_sample(A, dI, teK, g, r, vR, noiseSample, pos, obs);
    }
    prevRhoVolume = max(rho, 1e-30);
    prevThetaeVolume = max(thetae, 1e-30);
    prevBVolume = max(bMag, 1e-30);
    havePrevVolumeSample = true;
    return !(A.tau < 48.0);
}


#endif
