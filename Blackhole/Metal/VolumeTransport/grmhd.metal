#if defined(BH_INCLUDE_VOLUME_TRANSPORT_GRMHD) && (BH_INCLUDE_VOLUME_TRANSPORT_GRMHD)
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

    float teff = disk_visible_teff(rHit, P);
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
    float dIVis = dot(dINu, float3(0.30, 0.40, 0.30));
    dI = expressiveVisible ? dI : dIVis;
    if (!expressiveVisible) {
        A.I = dot(A.IVisNu, float3(0.30, 0.40, 0.30));
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

    if (P.visibleEmissionModel == 0u && A.tauVis.y >= 0.9) {
        A.tau = max(max(A.tauVis.x, A.tauVis.y), A.tauVis.z);
        A.maxI = max(A.maxI, A.I);
        if (dI > 0.0) {
            float teK = max(5.930e9 * thetae, 1.0);
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
        float teK = max(5.930e9 * thetae, 1.0);
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
