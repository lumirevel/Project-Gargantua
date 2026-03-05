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

    float3 beta = P.diskGrmhdVelScale * float3(vR, vPhi, vZ);
    float betaMax = max(max(abs(beta.x), abs(beta.y)), abs(beta.z));
    if (betaMax > 1.5) {
        beta /= max(P.c, 1e-6);
    }
    float betaMag = length(beta);
    if (betaMag > 0.999) {
        beta *= (0.999 / max(betaMag, 1e-12));
        betaMag = 0.999;
    }
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

    KerrCovMetric cov = kerr_cov_metric(rM, 0.5 * M_PI, a);
    float uDen = -(cov.gtt
                 + 2.0 * omega * cov.gtphi
                 + omega * omega * cov.gphiphi
                 + cov.grr * drdt * drdt);
    if (!(uDen > 1e-12) || !isfinite(uDen)) return 1.0;

    float u_t = 1.0 / sqrt(uDen);
    float prRay = mix(pr0, pr1, clamp(segT, 0.0, 1.0));
    float E_emit = u_t * (1.0 - omega * LzConst - drdt * prRay);
    if (!(E_emit > 1e-12) || !isfinite(E_emit)) return 1.0;
    return clamp(1.0 / E_emit, 1e-4, 1e4);
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
    float teGas = max(5.930e9 * max(thetae, 1e-6), 10.0); // K
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

static inline void disk_visible_rt_coeffs(float rEmitM,
                                          float rho,
                                          float thetae,
                                          float3 bVec,
                                          float nuComov,
                                          constant Params& P,
                                          thread float& jNu,
                                          thread float& aNu)
{
    if (P.visibleEmissionModel == 0u) {
        // Visible blackbody path should use photospheric effective temperature
        // rather than GRMHD electron temperature (which is often X-ray-hot).
        float teK = max(disk_visible_teff(rEmitM, P), 1.0);
        if (!(teK > 1.0) || !isfinite(teK)) {
            teK = max(5.930e9 * thetae, 1.0);
        }
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
        float epsAbs = clamp(kappaFf / kappaTot, 0.01, 1.0); // thermalization fraction

        // Convert rho*kappa [cm^-1] -> [m^-1]
        float alphaTot = (rhoCgs * kappaTot) * 100.0;
        float kappaScale = (P.visibleKappa > 0.0) ? P.visibleKappa : 0.12;
        float aComBase = max(P.diskGrmhdAbsorptionScale, 0.0) * alphaTot * kappaScale;
        float aCool = max(P.diskGrmhdAbsorptionScale, 0.0)
                    * disk_cool_absorber_alpha(rho, thetae, bVec, nuComov, P);
        float aCom = aComBase + aCool;

        // In optically thick, scattering-dominated media, thermal source is reduced by epsAbs.
        float sNu = epsAbs * bNu;
        float jCom = max(P.diskGrmhdEmissionScale, 0.0) * aComBase * sNu;
        jNu = max(jCom, 0.0);
        aNu = max(aCom, 0.0);
        return;
    }
    disk_grmhd_synch_coeffs(rho, thetae, bVec, nuComov, P, jNu, aNu);
    float aCool = max(P.diskGrmhdAbsorptionScale, 0.0)
                * disk_cool_absorber_alpha(rho, thetae, bVec, nuComov, P);
    aNu += aCool;
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
    float jCom = max(P.diskGrmhdEmissionScale, 0.0) * ne * bMag * kernVal;

    // Kirchhoff closure with Rayleigh-Jeans source function.
    float teK = max(5.930e9 * th, 1.0);
    float bNuRJ = (2.0 * P.k * teK * nu * nu) / max(P.c * P.c, 1e-20);
    float aCom = 0.0;
    if (bNuRJ > 1e-30) {
        aCom = jCom / bNuRJ;
    }
    aCom *= max(P.diskGrmhdAbsorptionScale, 0.0);

    jNu = max(jCom, 0.0);
    aNu = max(aCom, 0.0);
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
    if (P.diskVolumeMode == 0u) return;
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
    float tauScaleLegacy = max(P.diskVolumeTauScale, 0.0)
                         * (0.22 + 0.28 * max(P.diskCloudOpticalDepth, 0.25))
                         / max(P.rs, 1e-6);
    if (!(tauScaleLegacy > 0.0)) tauScaleLegacy = 0.6 / max(P.rs, 1e-6);
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

        if (P.diskVolumeFormat == 1u) {
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

                if (crossing) {
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

                    float rhoContrast = 1.0;
                    float thetaeContrast = 1.0;
                    float bContrast = 1.0;
                    float textureStrength = clamp(P.diskPrecisionTexture, 0.0, 1.0);
                    if (textureStrength > 1e-5) {
                        // Use local GRMHD gradients around the photosphere crossing to recover
                        // physically plausible unresolved clump/void texture in visible mode.
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

                    float teff = disk_visible_teff(rHit, P);
                    if (!(teff > 1.0) || !isfinite(teff)) {
                        // Visible-surface safety fallback:
                        // if NT/thin-disk branch collapses to near-zero in display units,
                        // use the configured parametric Teff profile to avoid fully black output.
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
                    if (teff > 1.0 && isfinite(teff)) {
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
                        return;
                    }
                    // If Teff is non-visible (or invalid) at this crossing, do not terminate.
                    // Continue marching so volumetric RT can still contribute instead of hard black.
                }

                havePrevVisibleSample = true;
                prevRho = rho;
                prevPos = pos;
                prevT = t;
                // No threshold crossing yet: fall back to volumetric RT integration below.
            }

            if (!(rho > 1e-24) || !(thetae > 1e-5)) continue;
            float texLocal = 0.5;
            float texStrength = clamp(P.diskPrecisionTexture, 0.0, 1.0);
            if (havePrevVolumeSample) {
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

                for (uint k = 0u; k < 3u; ++k) {
                    float nuObs = P.c / max(lamM[k], 1e-30);
                    float nuComov = max(nuObs / max(g, 1e-8), 1e3);
                    float jCom = 0.0;
                    float aCom = 0.0;
                    disk_visible_rt_coeffs(r, rho, thetae, bVec, nuComov, P, jCom, aCom);

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

                float3 dINu = max(A.IVisNu - iPrevNu, float3(0.0));
                dI = dot(dINu, float3(0.30, 0.40, 0.30));

                A.I = dot(A.IVisNu, float3(0.30, 0.40, 0.30));
                A.tau = max(max(A.tauVis.x, A.tauVis.y), A.tauVis.z);
                if (polarized) {
                    // Keep Q/U/V bounded by I to avoid numeric blow-up.
                    A.QVisNu = clamp(A.QVisNu, -A.IVisNu, A.IVisNu);
                    A.UVisNu = clamp(A.UVisNu, -A.IVisNu, A.IVisNu);
                    A.VVisNu = clamp(A.VVisNu, -A.IVisNu, A.IVisNu);
                } else {
                    A.QVisNu = qPrevNu;
                    A.UVisNu = uPrevNu;
                    A.VVisNu = vPrevNu;
                }
                // For visible blackbody mode, stop at thermal photosphere (tau~1)
                // to avoid over-thick "balloon" appearance from integrating deep layers.
                if (P.visibleEmissionModel == 0u && A.tauVis.y >= 0.9) {
                    A.tau = max(max(A.tauVis.x, A.tauVis.y), A.tauVis.z);
                    A.maxI = max(A.maxI, A.I);
                    if (dI > 0.0) {
                        float teK = max(5.930e9 * thetae, 1.0);
                        A.w += dI;
                        A.temp4 += dI * pow(teK, 4.0);
                        A.g += dI * g;
                        A.r += dI * r;
                        A.vr += dI * vR;
                        A.noise += dI * clamp(rho / (rho + 1.0), 0.0, 1.0);
                        A.x += dI * pos.x;
                        A.y += dI * pos.y;
                        A.z += dI * pos.z;
                        A.ox += dI * obs.x;
                        A.oy += dI * obs.y;
                        A.oz += dI * obs.z;
                        A.samples += 1u;
                    }
                    break;
                }
            } else {
                float nuComov = max(P.diskNuObsHz / max(g, 1e-8), 1e3);
                float jCom = 0.0;
                float aCom = 0.0;
                disk_grmhd_synch_coeffs(rho, thetae, bVec, nuComov, P, jCom, aCom);

                float jObs = jCom * g * g;
                float aObs = aCom / max(g, 1e-8);
                A.maxJ = max(A.maxJ, jObs);
                float IPrev = A.I;
                if (aObs > 1e-12) {
                    float dTau = min(aObs * ds, 40.0);
                    float trans = exp(-dTau);
                    float src = jObs / max(aObs, 1e-30);
                    A.I = IPrev * trans + src * (1.0 - trans);
                    A.tau += dTau;
                } else {
                    A.I = IPrev + jObs * ds;
                }
                dI = max(A.I - IPrev, 0.0);
            }
            A.maxI = max(A.maxI, A.I);

            if (dI > 0.0) {
                float teK = max(5.930e9 * thetae, 1.0);
                A.w += dI;
                A.temp4 += dI * pow(teK, 4.0);
                A.g += dI * g;
                A.r += dI * r;
                A.vr += dI * vR;
                float noiseSample = clamp(mix(0.5, texLocal, texStrength), 0.0, 1.0);
                A.noise += dI * noiseSample;
                A.x += dI * pos.x;
                A.y += dI * pos.y;
                A.z += dI * pos.z;
                A.ox += dI * obs.x;
                A.oy += dI * obs.y;
                A.oz += dI * obs.z;
                A.samples += 1u;
            }
            prevRhoVolume = max(rho, 1e-30);
            prevThetaeVolume = max(thetae, 1e-30);
            prevBVolume = max(length(bVec), 1e-30);
            havePrevVolumeSample = true;
            if (!(A.tau < 48.0)) break;
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
                         * (1.0 - 0.40 * voidGate);
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
            A.w += contrib;
            A.temp4 += contrib * pow(max(T, 1.0), 4.0);
            A.g += contrib * g;
            A.r += contrib * r;
            A.vr += contrib * vrRatio;
            A.noise += contrib * cloudSharp;
            A.x += contrib * pos.x;
            A.y += contrib * pos.y;
            A.z += contrib * pos.z;
            A.ox += contrib * obs.x;
            A.oy += contrib * obs.y;
            A.oz += contrib * obs.z;
            A.samples += 1u;
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

static inline bool trace_commit_volume_hit(thread const VolumeAccum& volumeA,
                                           bool volumeMode,
                                           float diskInner,
                                           float3 volumeObsDir,
                                           float ctLen,
                                           constant Params& P,
                                           thread CollisionInfo& info)
{
    bool expressiveVisible = (grmhd_visible_mode_enabled() && P.visiblePad0 != 0u);
    bool grmhdVisibleSurfaceHit = (grmhd_visible_mode_enabled() && volumeA.surfaceHit != 0u);
    bool grmhdVisibleExpressiveFallback =
        (FC_PHYSICS_MODE == 3u &&
         expressiveVisible &&
         volumeA.maxRho > 0.0 &&
         volumeA.maxB2 > 0.0);
    if (!(volumeMode &&
          (grmhdVisibleSurfaceHit ||
           ((FC_PHYSICS_MODE == 3u) && (volumeA.I > 0.0 || grmhdVisibleExpressiveFallback)) ||
           ((FC_PHYSICS_MODE != 3u) && volumeA.w > 0.0)))) {
        return false;
    }

    float weight = max(volumeA.w, 1e-20);
    float invW = 1.0 / weight;
    bool haveWeightedMoments = (volumeA.w > 1e-18);
    float3 pos = float3(volumeA.x, volumeA.y, volumeA.z) * invW;
    float rEmit = haveWeightedMoments ? max(volumeA.r * invW, P.rs * 1.0001) : max(diskInner, P.rs * 1.0001);
    float volAmp = 1.0 - exp(-0.9 * volumeA.w);
    float3 dirAvg = float3(volumeA.ox, volumeA.oy, volumeA.oz) * invW;
    float3 toCam = P.camPos - pos;
    float toCamLen2 = dot(toCam, toCam);
    float3 obsDir = (dot(dirAvg, dirAvg) > 1e-20)
        ? normalize(dirAvg)
        : ((toCamLen2 > 1e-20) ? normalize(toCam) : volumeObsDir);
    if (toCamLen2 > 1e-20 && dot(obsDir, toCam) < 0.0) {
        obsDir = -obsDir;
    }

    float scalarI = (FC_PHYSICS_MODE == 3u) ? max(volumeA.I, 0.0) : clamp(volAmp, 0.0, 1.0);
    if (FC_PHYSICS_MODE == 3u && expressiveVisible && !(scalarI > 0.0)) {
        float rhoRef = max(volumeA.maxRho, 1e-20);
        float b2Ref = max(volumeA.maxB2, 1e-20);
        float emissScale = max(P.diskGrmhdEmissionScale, 1e-6);
        // Expressive fallback proxy: keep strictly positive signal when
        // physically-mapped visible emissivity underflows to zero.
        scalarI = max(
            scalarI,
            5.0e-18 * emissScale
            * (pow(rhoRef, 0.70) + 0.35 * pow(b2Ref, 0.35))
        );
    }
    float brightnessT = pow(max(volumeA.temp4 * invW, 1e-20), 0.25);
    if (grmhdVisibleSurfaceHit) {
        brightnessT = max(pow(max(volumeA.temp4, 1e-20), 0.25), 1.0);
    } else if (FC_PHYSICS_MODE == 3u && (!haveWeightedMoments || !(volumeA.temp4 > 0.0))) {
        float nu = max(P.diskNuObsHz, 1e6);
        brightnessT = max((scalarI * P.c * P.c) / max(2.0 * P.k * nu * nu, 1e-30), 1.0);
        if (expressiveVisible) {
            float rhoRef = max(volumeA.maxRho, 1e-20);
            float b2Ref = max(volumeA.maxB2, 1e-20);
            float teProxy = 4800.0 * pow(rhoRef, 0.16) * pow(b2Ref, 0.08);
            brightnessT = max(brightnessT, clamp(teProxy, 2500.0, 24000.0));
        }
    }

    float gMean = haveWeightedMoments ? (volumeA.g * invW) : 1.0;
    float vrMean = haveWeightedMoments ? (volumeA.vr * invW) : 0.0;
    float noiseMean = haveWeightedMoments ? (volumeA.noise * invW) : 0.0;
    float iVisTot = max(dot(volumeA.IVisNu, float3(1.0)), 1e-30);
    float qVisTot = dot(volumeA.QVisNu, float3(1.0));
    float uVisTot = dot(volumeA.UVisNu, float3(1.0));
    float vVisTot = dot(volumeA.VVisNu, float3(1.0));
    float polFrac = clamp(sqrt(max(qVisTot*qVisTot + uVisTot*uVisTot + vVisTot*vVisTot, 0.0)) / iVisTot, 0.0, 1.0);
    bool grmhdVisibleVolumetric = (grmhd_visible_mode_enabled() &&
                                   P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                   !grmhdVisibleSurfaceHit);

    info.hit = 1;
    info.ct  = ctLen;
    info.T   = brightnessT;
    info.v_disk = float4(clamp(gMean, 1e-4, 1e4),
                         rEmit,
                         clamp(vrMean, -1.0, 1.0),
                         scalarI);
    info.direct_world = float4(obsDir, 0.0);

    if (grmhd_pol_debug_enabled(P)) {
        info.noise = polFrac;
        info.emit_r_norm = max(volumeA.maxRho, 0.0);
        info.emit_phi = max(volumeA.maxB2, 0.0);
        info.emit_z_norm = max(volumeA.maxJ, 0.0);
    } else if (grmhd_raw_debug_enabled(P)) {
        info.noise = max(volumeA.maxI, 0.0);
        info.emit_r_norm = max(volumeA.maxRho, 0.0);
        info.emit_phi = max(volumeA.maxB2, 0.0);
        info.emit_z_norm = max(volumeA.maxJ, 0.0);
    } else if (grmhdVisibleVolumetric) {
        info.noise = (P.diskPolarizedRT != 0u) ? polFrac : clamp(noiseMean, 0.0, 1.0);
        info.emit_r_norm = max(volumeA.IVisNu.x, 0.0);
        info.emit_phi = max(volumeA.IVisNu.y, 0.0);
        info.emit_z_norm = max(volumeA.IVisNu.z, 0.0);
    } else {
        info.noise = clamp(noiseMean, 0.0, 1.0);
        info.emit_r_norm = rEmit / max(P.rs, 1e-6);
        info.emit_phi = atan2(pos.y, pos.x);
        info.emit_z_norm = pos.z / max(P.rs, 1e-6);
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

    // Lux basis (newX,newY,newZ)
    float3 newX = normalize(P.camPos);           // p.unit
    float3 newZ = normalize(cross(newX, dir));   // newX.cross(direction).unit
    float3 newY = cross(newZ, newX);             // newZ.cross(newX).unit (이미 정규에 가까움)

    float r0 = length(P.camPos);

    // Python의 local = c * inverse * direction.unit 과 동일:
    // inverse rows = (newX,newY,newZ)
    float3 local = P.c * float3(dot(newX, dir), dot(newY, dir), dot(newZ, dir));

    bool hasPrev = false;
    float3 world0 = float3(0);

    init_collision_info(info);
    info.direct_world = float4(-normalize(dir), 0.0);

    float4 p = float4(0.0, r0, M_PI * 0.5, 0.0);
    float dt   = 0.1;
    float dr   = local.x;
    float dphi = local.y / max(r0, 1e-6);
    float4 v = float4(dt, dr, 0.0, dphi);

    if (FC_METRIC == 0) {
        float horizonRadius = P.rs * (1.0 + P.eps);
        float diskInner = disk_inner_radius_m(P);
        float diskEmitMin = disk_emit_min_radius_m(P);
        float rObs = max(length(P.camPos), 1.0001 * P.rs);
        bool volumeMode = (P.diskVolumeMode != 0u && (FC_PHYSICS_MODE == 2u || FC_PHYSICS_MODE == 3u));
        VolumeAccum volumeA;
        volume_accum_init(volumeA);
        float3 volumeObsDir = -normalize(dir);

        for (int i=0; i<P.maxSteps; ++i) {
            float4 pPrev = p;
            float4 vPrev = v;
            // Adaptive Schwarzschild stepping: shrink step near horizon / fast radial motion
            // to preserve thin photon-ring structure without globally reducing h.
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
                float3 segDir = worldPos - world0;
                float segLen2 = dot(segDir, segDir);
                if (segLen2 > 1e-20) {
                    volumeObsDir = -normalize(segDir);
                    info.direct_world = float4(volumeObsDir, 0.0);
                }

                if (volumeMode) {
                    volume_integrate_segment(world0, worldPos, volumeObsDir, diskInner, P, diskVol0Tex, diskVol1Tex, volumeA,
                                             vPrev, v, 0.0, 0.0, 0.0);
                } else {
                    float tEnter = 0.0;
                    float hitSegT = 0.0;
                    int hitSegment = -1; // 0=world0->mid, 1=mid->worldPos, 2=world0->worldPos(fallback)
                    bool entered = false;
                    float3 hitPos = float3(0.0);

                    // Curved-path guard: split one Schwarzschild RK step into two half steps.
                    float4 pMid = pPrev;
                    float4 vMid = vPrev;
                    rk4_step_h(pMid, vMid, P, 0.5 * P.h);
                    float3 localMid = conv(pMid.y, pMid.z, pMid.w);
                    float3 worldMid = localMid.x * newX + localMid.y * newY + localMid.z * newZ;
                    if (segment_enter_disk(world0, worldMid, P, tEnter)) {
                        hitPos = mix(world0, worldMid, tEnter);
                        hitSegT = tEnter;
                        hitSegment = 0;
                        entered = true;
                    } else if (segment_enter_disk(worldMid, worldPos, P, tEnter)) {
                        hitPos = mix(worldMid, worldPos, tEnter);
                        hitSegT = tEnter;
                        hitSegment = 1;
                        entered = true;
                    }
                    if (!entered && segment_enter_disk(world0, worldPos, P, tEnter)) {
                        hitPos = mix(world0, worldPos, tEnter);
                        hitSegT = tEnter;
                        hitSegment = 2;
                        entered = true;
                    }

                    if (entered) {
                        float dxy = length(float2(hitPos.x, hitPos.y));
                        if (dxy > diskEmitMin && dxy < P.re) {
                            float phiHit = atan2(hitPos.y, hitPos.x);
                            float4 atlas = disk_sample_atlas(dxy, phiHit, P, diskAtlasTex);
                            float absV = sqrt(P.G * P.M / dxy);
                            float invDxy = 1.0 / max(dxy, 1e-6);
                            float3 er = float3(hitPos.x * invDxy, hitPos.y * invDxy, 0.0);
                            float3 ephi = float3(hitPos.y * invDxy, -hitPos.x * invDxy, 0.0);
                            float vrRatio = 0.0;
                            float vphiScale = 1.0;
                            float tempScale = 1.0;
                            if (FC_PHYSICS_MODE != 2u) {
                                vrRatio = clamp(atlas.z * P.diskAtlasVrScale, -1.0, 1.0);
                                vphiScale = clamp(atlas.w * P.diskAtlasVphiScale, 0.0, 4.0);
                                tempScale = clamp(atlas.x * P.diskAtlasTempScale, 0.05, 20.0);
                            }
                            float massLen = 0.5 * P.rs;
                            float rM = dxy / max(massLen, 1e-12);
                            float betaRef = sqrt(max(1.0 / max(rM, 1e-6), 1e-8));
                            // Coordinate-basis local betas (phi basis follows +phi direction).
                            float betaRCoord = vrRatio * betaRef;
                            float betaPhiCoord = -vphiScale * betaRef;
                            float3 v_disk = absV * (vrRatio * er + vphiScale * ephi);
                            if (FC_PHYSICS_MODE != 0u && dxy < diskInner * (1.0 - 1e-4)) {
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

                            float3 segDir2 = worldPos - world0;
                            float segLen22 = dot(segDir2, segDir2);
                            float3 direct = (segLen22 > 1e-20) ? normalize(segDir2) : normalize(dir);
                            float3 obsDir = -direct;

                            float4 rayDerivHit = v;
                            if (hitSegment == 0) {
                                rayDerivHit = mix(vPrev, vMid, clamp(hitSegT, 0.0, 1.0));
                            } else if (hitSegment == 1) {
                                rayDerivHit = mix(vMid, v, clamp(hitSegT, 0.0, 1.0));
                            } else if (hitSegment == 2) {
                                rayDerivHit = mix(vPrev, v, clamp(hitSegT, 0.0, 1.0));
                            }
                            float g_factor = disk_schwarzschild_direct_gfactor(dxy,
                                                                               rObs,
                                                                               rayDerivHit,
                                                                               betaRCoord,
                                                                               betaPhiCoord,
                                                                               P);

                            float T = disk_effective_temperature(dxy, diskInner, P);
                            T *= tempScale;
                            if (FC_PHYSICS_MODE == 2u) {
                                T *= disk_precision_texture_factor(dxy, phiHit, hitPos.z, P);
                            }

                            float ctLen = P.c * p.x;
                            info.hit = 1;
                            info.ct  = ctLen;
                            info.T   = T;
                            info.v_disk = float4(g_factor, dxy, vrRatio, 0.0);
                            info.direct_world = float4(obsDir, 0.0);
                            float3 samplePos = disk_sample_probe_pos(hitPos, world0, worldPos, P);
                            disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlasTex);

                            return true;
                        }
                    }
                }
            }

            hasPrev = true;
            world0 = worldPos;

            float dxy = length(float2(worldPos.x, worldPos.y));
            if (dxy > max(P.kerrEscapeMult, 1.0) * P.re) break;
            if (p.y < horizonRadius) break;
            if (!(isfinite(p.x) && isfinite(p.y) && isfinite(p.w))) break;
        }
        if (trace_commit_volume_hit(volumeA, volumeMode, diskInner, volumeObsDir, P.c * p.x, P, info)) {
            return true;
        }
    } else {
        float massLen = 0.5 * P.rs;
        float a = clamp(P.spin, -0.999, 0.999);
        float escapeRadius = max(P.kerrEscapeMult, 1.0) * P.re;
        float diskInner = disk_inner_radius_m(P);
        float diskInnerM = diskInner / max(massLen, 1e-12);
        float diskEmitMin = disk_emit_min_radius_m(P);
        bool volumeMode = (P.diskVolumeMode != 0u && (FC_PHYSICS_MODE == 2u || FC_PHYSICS_MODE == 3u));
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

        while (accepted < targetSteps && guard < targetSteps * 12) {
            guard += 1;
            // Near the horizon, cap the local step size to preserve higher-order photon ring detail.
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
                    float3 segDir = worldPos - world0;
                    float segLen2 = dot(segDir, segDir);
                    if (segLen2 > 1e-20) {
                        volumeObsDir = -normalize(segDir);
                        info.direct_world = float4(volumeObsDir, 0.0);
                    }

                    if (volumeMode) {
                        volume_integrate_segment(world0, worldPos, volumeObsDir, diskInner, P, diskVol0Tex, diskVol1Tex, volumeA,
                                                 float4(0.0), float4(0.0), Lz, prevState.pr, state.pr);
                    } else {
                        float tEnter = 0.0;
                        bool entered = false;
                        float3 hitPos = float3(0.0);

                        // Curved-path guard: split one accepted Kerr segment into two half segments.
                        KerrState midState;
                        float midErr = 0.0;
                        float midNull = 0.0;
                        kerr_dp45_trial(prevState, 0.5 * hUsed, a, Lz, midState, midErr, midNull);
                        if (isfinite(midState.r) && isfinite(midState.theta) && isfinite(midState.phi)) {
                            midState.theta = clamp(midState.theta, 1e-4, M_PI - 1e-4);
                            midState.phi = fmod(midState.phi, 2.0 * M_PI);
                            if (midState.phi < 0.0) midState.phi += 2.0 * M_PI;
                            float3 midWorld = conv(max(midState.r, 0.0) * massLen, midState.theta, midState.phi);
                            if (segment_enter_disk(world0, midWorld, P, tEnter)) {
                                hitPos = mix(world0, midWorld, tEnter);
                                entered = true;
                            } else if (segment_enter_disk(midWorld, worldPos, P, tEnter)) {
                                hitPos = mix(midWorld, worldPos, tEnter);
                                entered = true;
                            }
                        }
                        if (!entered && segment_enter_disk(world0, worldPos, P, tEnter)) {
                            hitPos = mix(world0, worldPos, tEnter);
                            entered = true;
                        }

                        if (entered) {
                            float dxy = length(float2(hitPos.x, hitPos.y));
                            float r_M = dxy / max(massLen, 1e-12);
                            float rEmitMinM = diskEmitMin / max(massLen, 1e-12);

                            if (r_M > rEmitMinM && dxy < P.re) {
                                float phiHit = atan2(hitPos.y, hitPos.x);
                                float4 atlas = disk_sample_atlas(dxy, phiHit, P, diskAtlasTex);
                                float vrRatio = 0.0;
                                float vphiScale = 1.0;
                                float tempScale = 1.0;
                                if (FC_PHYSICS_MODE != 2u) {
                                    vrRatio = clamp(atlas.z * P.diskAtlasVrScale, -1.0, 1.0);
                                    vphiScale = clamp(atlas.w * P.diskAtlasVphiScale, 0.0, 4.0);
                                    tempScale = clamp(atlas.x * P.diskAtlasTempScale, 0.05, 20.0);
                                }
                                float omegaK = 1.0 / max(pow_1p5(r_M) + a, 1e-8);
                                float omega = omegaK * vphiScale;
                                float drdt = vrRatio * sqrt(1.0 / max(r_M, 1.0));
                                if (FC_PHYSICS_MODE != 0u && r_M < diskInnerM * (1.0 - 1e-4)) {
                                    float plungeOmega = omega;
                                    float plungeDrdt = drdt;
                                    float plungeVrRatio = vrRatio;
                                    if (disk_kerr_plunge_kinematics(r_M, diskInnerM, a, plungeOmega, plungeDrdt, plungeVrRatio)) {
                                        omega = plungeOmega;
                                        drdt = plungeDrdt;
                                        vrRatio = plungeVrRatio;
                                    }
                                }
                                KerrCovMetric diskCov = kerr_cov_metric(r_M, 0.5 * M_PI, a);
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
                                float E_emit = u_t * (1.0 - omega * Lz - drdt * state.pr);
                                if (!(E_emit > 1e-8)) {
                                    E_emit = u_t * max(1.0 - omega * Lz, 1e-8);
                                }
                                float g_factor = 1.0 / max(E_emit, 1e-8);
                                if (!isfinite(g_factor)) g_factor = 1.0;
                                g_factor = clamp(g_factor, 1e-4, 1e4);

                                float3 segDir2 = worldPos - world0;
                                float segLen22 = dot(segDir2, segDir2);
                                float3 direct = (segLen22 > 1e-20) ? normalize(segDir2) : normalize(dir);
                                float3 obsDir = -direct;

                                float T = disk_effective_temperature(dxy, diskInner, P);
                                T *= tempScale;
                                if (FC_PHYSICS_MODE == 2u) {
                                    T *= disk_precision_texture_factor(dxy, phiHit, hitPos.z, P);
                                }

                                float ctLen = state.t * massLen;
                                info.hit = 1;
                                info.ct  = ctLen;
                                info.T   = T;
                                info.v_disk = float4(g_factor, dxy, vrRatio, 0.0);
                                info.direct_world = float4(obsDir, 0.0);
                                float3 samplePos = disk_sample_probe_pos(hitPos, world0, worldPos, P);
                                disk_set_noise_and_bridge(info, samplePos, ctLen, P, diskAtlasTex);

                                return true;
                            }
                        }
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
        if (trace_commit_volume_hit(volumeA, volumeMode, diskInner, volumeObsDir, state.t * massLen, P, info)) {
            return true;
        }
    }

    return false;
}

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
                float midErr = 0.0;
                float midNull = 0.0;
                kerr_dp45_trial(prevC, 0.5 * hUsed, a, LzC, midC, midErr, midNull);
                bool validMid = isfinite(midC.r) && isfinite(midC.theta) && isfinite(midC.phi);
                float3 worldMidC = worldC;
                float3 worldMidDx = worldDx;
                float3 worldMidDy = worldDy;
                if (validMid) {
                    KerrState midDX = prevDX;
                    KerrState midDY = prevDY;
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

// Forward declarations used by in-kernel visible-spectrum SSAA averaging.
static inline void comp_cie_xyz_bar(float lam, thread float& x_bar, thread float& y_bar, thread float& z_bar);
static inline float comp_visible_iNu_emit(float nuEm, float te, constant Params& P);
static inline void comp_visible_xyz_from_spectrum(float T_emit,
                                                  float g_total,
                                                  constant Params& P,
                                                  thread float& X,
                                                  thread float& Y,
                                                  thread float& Z,
                                                  thread float& yLum,
                                                  thread float& peakLamNm);
static inline float comp_limb_factor(float mu, constant Params& P);

static inline float3 ray_bundle_visible_xyz_from_collision(thread const CollisionInfo& rec,
                                                           constant Params& P,
                                                           thread bool& ok) {
    ok = false;
    if (FC_PHYSICS_MODE != 3u || FC_VISIBLE_MODE == 0u) {
        return float3(0.0);
    }

    float g_total = clamp(rec.v_disk.x, 1e-4, 1e4);
    float tEmit = max(rec.T, 1.0);
    float colorDilution = 1.0;
    if (P.visibleTeffModel == 2u) {
        float fCol = max(P.diskColorFactor, 1.0);
        tEmit *= fCol;
        colorDilution = 1.0 / pow(fCol, 4.0);
    }

    float X = 0.0;
    float Y = 0.0;
    float Z = 0.0;
    float yLum = 0.0;
    float peakLam = 380.0;
    bool useInuAnchor = (P.visiblePhotosphereRhoThreshold <= 0.0);
    float scalarI = max(rec.v_disk.w, 0.0);
    bool usedSpectralAnchors = false;

    if (useInuAnchor) {
        float3 iNuVis = max(float3(rec.emit_r_norm, rec.emit_phi, rec.emit_z_norm), float3(0.0));
        if (dot(iNuVis, float3(1.0)) > 1e-30) {
            const float3 lamNm = float3(650.0, 550.0, 450.0);
            const float3 lamM = lamNm * 1e-9;
            const float3 bandNm = float3(130.0, 100.0, 120.0);
            for (uint k = 0u; k < 3u; ++k) {
                float iLam = iNuVis[k] * P.c / max(lamM[k] * lamM[k], 1e-30);
                float xBar, yBar, zBar;
                comp_cie_xyz_bar(lamNm[k], xBar, yBar, zBar);
                float dLamM = bandNm[k] * 1e-9;
                X += iLam * xBar * dLamM;
                Y += iLam * yBar * dLamM;
                Z += iLam * zBar * dLamM;
                yLum += iLam * dLamM;
            }
            X *= colorDilution;
            Y *= colorDilution;
            Z *= colorDilution;
            yLum *= colorDilution;
            usedSpectralAnchors = true;
        }
    }

    if (!usedSpectralAnchors) {
        comp_visible_xyz_from_spectrum(tEmit, g_total, P, X, Y, Z, yLum, peakLam);
        X *= colorDilution;
        Y *= colorDilution;
        Z *= colorDilution;

        if (useInuAnchor && scalarI > 1e-18) {
            float nuObsRef = max(P.diskNuObsHz, 1e6);
            float nuEmRef = nuObsRef / max(g_total, 1e-8);
            float iNuPred = pow(g_total, 3.0) * comp_visible_iNu_emit(nuEmRef, tEmit, P) * colorDilution;
            float amp = scalarI / max(iNuPred, 1e-38);
            amp = clamp(amp, 0.0, 1e12);
            X *= amp;
            Y *= amp;
            Z *= amp;
        }
    }

    float3 d_world = rec.direct_world.xyz;
    float mu = abs(d_world.z) / max(length(d_world), 1e-30);
    float limb = comp_limb_factor(mu, P);
    ok = true;
    return float3(X, Y, Z) * limb;
}

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

    CollisionInfo centerInfo;
    init_collision_info(centerInfo);
    bool centerHit = trace_single_ray(P, baseX, baseY, diskAtlasTex, diskVol0Tex, diskVol1Tex, centerInfo) && (centerInfo.hit != 0u);

    for (uint s = 0u; s < sampleCount; ++s) {
        float2 j = ssaaJitter[s];
        float x = baseX + j.x;
        float y = baseY + j.y;

        CollisionInfo subInfo;
        bool hit = trace_single_ray(P, x, y, diskAtlasTex, diskVol0Tex, diskVol1Tex, subInfo);
        if (!hit || subInfo.hit == 0u) continue;
        if (!haveFirstHitInfo) {
            firstHitInfo = subInfo;
            haveFirstHitInfo = true;
        }

        float jacW = 1.0;
        if (P.rayBundleJacobian != 0u) {
            jacW = ray_bundle_compute_jacobian_weight(P, x, y, diffOffset, subInfo);
        }

        float tSafe = clamp(subInfo.T, 0.0, 1e9);
        float t2 = tSafe * tSafe;
        float t4Raw = t2 * t2;
        float scalarIRaw = max(subInfo.v_disk.w, 0.0);
        if (!haveHit) {
            haveHit = true;
        }

        sumTemp4 += (t4Raw * jacW) * sampleW;
        sumI += (scalarIRaw * jacW) * sampleW;
        if (bundleLinearAnchors) {
            sumEmitR += max(subInfo.emit_r_norm, 0.0) * jacW * sampleW;
            sumEmitPhi += max(subInfo.emit_phi, 0.0) * jacW * sampleW;
            sumEmitZ += max(subInfo.emit_z_norm, 0.0) * jacW * sampleW;
        }
        if (bundleVisibleSpectrum) {
            bool xyzOk = false;
            float3 xyz = ray_bundle_visible_xyz_from_collision(subInfo, P, xyzOk);
            if (xyzOk) {
                sumVisibleXYZ += xyz * jacW * sampleW;
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
