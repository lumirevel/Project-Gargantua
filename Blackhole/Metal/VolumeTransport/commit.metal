#if defined(BH_INCLUDE_VOLUME_TRANSPORT_COMMIT) && (BH_INCLUDE_VOLUME_TRANSPORT_COMMIT)
struct PreparedVolumeHit {
    bool valid;
    bool grmhdVisibleSurfaceHit;
    bool grmhdVisibleVolumetric;
    float3 pos;
    float3 obsDir;
    float rEmit;
    float scalarI;
    float brightnessT;
    float gMean;
    float vrMean;
    float noiseMean;
    float polFrac;
};

static inline PreparedVolumeHit trace_prepare_volume_hit(thread const VolumeAccum& volumeA,
                                                         bool volumeMode,
                                                         float diskInner,
                                                         float3 volumeObsDir,
                                                         constant Params& P)
{
    PreparedVolumeHit out;
    out.valid = false;
    out.grmhdVisibleSurfaceHit = false;
    out.grmhdVisibleVolumetric = false;
    out.pos = float3(0.0);
    out.obsDir = volumeObsDir;
    out.rEmit = max(diskInner, P.rs * 1.0001);
    out.scalarI = 0.0;
    out.brightnessT = 1.0;
    out.gMean = 1.0;
    out.vrMean = 0.0;
    out.noiseMean = 0.0;
    out.polFrac = 0.0;

    bool expressiveVisible = (grmhd_visible_mode_enabled() && (P.visiblePad0 & 1u) != 0u);
    bool grmhdVisibleSurfaceHit = (grmhd_visible_mode_enabled() && volumeA.surfaceHit != 0u);
    float legacyVolumeHitThreshold = (FC_PHYSICS_MODE == 2u && P.diskVolumeMode != 0u) ? 0.25 : 0.0;
    bool precisionVisibleVolume = (FC_PHYSICS_MODE == 2u &&
                                   P.diskVolumeMode != 0u &&
                                   volumeA.visibleSpectrumMode == 1u &&
                                   volumeA.I > 0.0);
    if (!(volumeMode &&
          (grmhdVisibleSurfaceHit ||
           precisionVisibleVolume ||
           ((FC_PHYSICS_MODE == 3u) && volumeA.I > 0.0) ||
           ((FC_PHYSICS_MODE != 3u) && volumeA.w > legacyVolumeHitThreshold)))) {
        return out;
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
    if (FC_PHYSICS_MODE == 3u) {
        float iVisWeighted = 0.0;
        if (volumeA.visibleSpectrumMode == 1u) {
            iVisWeighted = (FC_PHYSICS_MODE == 2u)
                ? max(volumeA.IVisNu.y, 0.0)
                : volume_visible_bands_to_xyz(volumeA, P).y;
        } else {
            // Photopic-luminance weights sampled at the GRMHD visible anchors
            // {650nm, 520nm, 425nm}; used only for scalar diagnostics/fallback intensity.
            iVisWeighted = dot(max(volumeA.IVisNu, float3(0.0)), float3(0.13344, 0.85742, 0.00914));
        }
        scalarI = max(scalarI, iVisWeighted);
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
    float iVisTotRaw = (volumeA.visibleSpectrumMode == 1u)
        ? ((FC_PHYSICS_MODE == 2u) ? max(volumeA.IVisNu.y, 0.0) : max(volume_visible_bands_to_xyz(volumeA, P).y, 0.0))
        : dot(volumeA.IVisNu, float3(1.0));
    float iVisTot = max(iVisTotRaw, 1e-30);
    float qVisTot = dot(volumeA.QVisNu, float3(1.0));
    float uVisTot = dot(volumeA.UVisNu, float3(1.0));
    float vVisTot = dot(volumeA.VVisNu, float3(1.0));
    float polFrac = clamp(sqrt(max(qVisTot*qVisTot + uVisTot*uVisTot + vVisTot*vVisTot, 0.0)) / iVisTot, 0.0, 1.0);
    bool grmhdVisibleVolumetric = ((grmhd_visible_mode_enabled() &&
                                    P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                    !grmhdVisibleSurfaceHit) ||
                                   precisionVisibleVolume);

    out.valid = true;
    out.grmhdVisibleSurfaceHit = grmhdVisibleSurfaceHit;
    out.grmhdVisibleVolumetric = grmhdVisibleVolumetric;
    out.pos = pos;
    out.obsDir = obsDir;
    out.rEmit = rEmit;
    out.scalarI = scalarI;
    out.brightnessT = brightnessT;
    out.gMean = gMean;
    out.vrMean = vrMean;
    out.noiseMean = noiseMean;
    out.polFrac = polFrac;
    return out;
}

static inline void trace_store_volume_hit(thread const VolumeAccum& volumeA,
                                          thread const PreparedVolumeHit& prepared,
                                          constant Params& P,
                                          thread CollisionInfo& info)
{
    info.hit = 1;
    info.T   = prepared.brightnessT;
    info.v_disk = float4(clamp(prepared.gMean, 1e-4, 1e4),
                         prepared.rEmit,
                         clamp(prepared.vrMean, -1.0, 1.0),
                         prepared.scalarI);
    info.direct_world = float4(prepared.obsDir, 0.0);

    if (grmhd_pol_debug_enabled(P)) {
        info.noise = prepared.polFrac;
        info.emit_r_norm = max(volumeA.maxRho, 0.0);
        info.emit_phi = max(volumeA.maxB2, 0.0);
        info.emit_z_norm = max(volumeA.maxJ, 0.0);
    } else if (grmhd_state_debug_enabled(P)) {
        float raw = 0.0;
        if (P.diskGrmhdDebugView == 10u) {
            raw = max(volumeA.maxThetae, 0.0);
        } else if (P.diskGrmhdDebugView == 11u) {
            raw = max(volumeA.maxSigmaProxy, 0.0);
        } else if (P.diskGrmhdDebugView == 12u) {
            raw = max(volumeA.maxBetaInvProxy, 0.0);
        } else if (P.diskGrmhdDebugView == 13u) {
            raw = clamp(volumeA.maxSpeed, 0.0, 0.999);
        } else if (P.diskGrmhdDebugView == 14u) {
            raw = max(volumeA.maxGamma, 1.0);
        } else if (P.diskGrmhdDebugView == 15u) {
            raw = max(volumeA.tau, max(max(volumeA.tauVis.x, volumeA.tauVis.y), volumeA.tauVis.z));
        } else if (P.diskGrmhdDebugView == 16u) {
            raw = max(volumeA.maxAlpha, 0.0);
        } else if (P.diskGrmhdDebugView == 17u) {
            raw = float(volumeA.samples);
        } else if (P.diskGrmhdDebugView == 18u) {
            raw = float(volumeA.invalidSamples);
        } else if (P.diskGrmhdDebugView == 19u) {
            raw = pow(clamp(prepared.gMean, 1e-4, 1e4), 3.0);
        } else if (P.diskGrmhdDebugView == 20u) {
            // Raw radiance should expose the integrated observed signal, not a
            // per-sample peak or scalar fallback. For visible GRMHD, use the
            // same accumulated visible luminance that the normal volumetric path
            // stores as XYZ, before interpreter/camera effects.
            if (volumeA.visibleSpectrumMode == 1u) {
                raw = (FC_PHYSICS_MODE == 2u)
                    ? max(volumeA.IVisNu.y, 0.0)
                    : max(volume_visible_bands_to_xyz(volumeA, P).y, 0.0);
            } else {
                raw = max(dot(max(volumeA.IVisNu, float3(0.0)), float3(0.13344, 0.85742, 0.00914)), 0.0);
            }
        } else if (P.diskGrmhdDebugView == 23u) {
            raw = (volumeA.tauOneSource > 0.0) ? volumeA.tauOneSource : max(volumeA.maxSource, 0.0);
        } else if (P.diskGrmhdDebugView == 24u) {
            raw = max(volumeA.tauOneRNorm, 0.0);
        } else if (P.diskGrmhdDebugView == 25u) {
            raw = max(volumeA.tauOnePathRs, 0.0);
        } else if (P.diskGrmhdDebugView == 26u) {
            raw = max(volumeA.tau, max(max(volumeA.tauVis.x, volumeA.tauVis.y), volumeA.tauVis.z));
        } else if (P.diskGrmhdDebugView == 27u) {
            raw = max(volumeA.maxAlpha, 0.0);
        } else if (P.diskGrmhdDebugView == 28u) {
            raw = (volumeA.w > 1e-18) ? max(volumeA.r / volumeA.w / max(P.rs, 1e-6), 0.0) : 0.0;
        } else if (P.diskGrmhdDebugView == 29u) {
            raw = sqrt(max(volumeA.maxB2, 0.0));
        } else if (P.diskGrmhdDebugView == 30u) {
            raw = clamp(volumeA.maxEpsAbs, 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 31u) {
            raw = max(volumeA.maxABase, 0.0);
        } else if (P.diskGrmhdDebugView == 32u) {
            raw = max(volumeA.maxACool, 0.0);
        } else if (P.diskGrmhdDebugView == 33u) {
            raw = (volumeA.intJThermal > 0.0) ? volumeA.intJThermal : max(volumeA.maxJThermal, 0.0);
        } else if (P.diskGrmhdDebugView == 34u) {
            raw = (volumeA.intJThin > 0.0) ? volumeA.intJThin : max(volumeA.maxJThin, 0.0);
        } else if (P.diskGrmhdDebugView == 35u) {
            raw = max(volumeA.maxSourceThermal, 0.0);
        } else if (P.diskGrmhdDebugView == 36u) {
            raw = max(volumeA.maxSourceThin, 0.0);
        } else if (P.diskGrmhdDebugView == 37u) {
            float branchTotal = max(volumeA.intIThermal + volumeA.intIThin, 1e-30);
            raw = clamp(volumeA.intIThin / branchTotal, 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 38u) {
            raw = clamp(volumeA.maxThinWeight, 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 39u) {
            raw = (volumeA.intJThermalWeighted > 0.0) ? volumeA.intJThermalWeighted : max(volumeA.maxJThermal, 0.0);
        } else if (P.diskGrmhdDebugView == 40u) {
            raw = max(volumeA.intAlphaThermalPre, 0.0);
        } else if (P.diskGrmhdDebugView == 41u) {
            raw = max(volumeA.intAlphaThermalPost, 0.0);
        } else if (P.diskGrmhdDebugView == 42u) {
            raw = clamp(volumeA.maxCoronaWeight, 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 43u) {
            raw = (volumeA.intJThermalCloud > 0.0)
                ? volumeA.intJThermalCloud
                : max(volumeA.maxJThermalCloud, 0.0);
        } else if (P.diskGrmhdDebugView == 44u) {
            float branchTotal = max(volumeA.intIThermal + volumeA.intIThin, 1e-30);
            raw = clamp(volumeA.intIThermalCloud / branchTotal, 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 48u) {
            if (volumeA.visibleSpectrumMode == 1u) {
                raw = (FC_PHYSICS_MODE == 2u)
                    ? max(volumeA.IVisNu.y, 0.0)
                    : max(volume_visible_bands_to_xyz(volumeA, P).y, 0.0);
            } else {
                raw = max(volumeA.intIThermal, 0.0);
            }
        } else if (P.diskGrmhdDebugView == 49u) {
            raw = max(volumeA.intIThermalCloud, 0.0);
        } else if (P.diskGrmhdDebugView == 50u) {
            raw = max(volumeA.intIThermalBody, 0.0);
        } else if (P.diskGrmhdDebugView == 51u) {
            raw = (volumeA.emissWeight > 1e-30) ? max(volumeA.emissLayer / volumeA.emissWeight, 0.0) : 0.0;
        } else if (P.diskGrmhdDebugView == 52u) {
            raw = (volumeA.emissWeight > 1e-30) ? clamp(volumeA.emissBodyLayerGate / volumeA.emissWeight, 0.0, 1.0) : 0.0;
        } else if (P.diskGrmhdDebugView == 53u) {
            raw = max(volumeA.intIThermalCorona, 0.0);
        } else if (P.diskGrmhdDebugView == 54u) {
            raw = clamp(volumeA.maxBodyProxy, 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 56u) {
            float tauMax = max(volumeA.tau, max(max(volumeA.tauVis.x, volumeA.tauVis.y), volumeA.tauVis.z));
            raw = clamp(1.0 - exp(-max(tauMax, 0.0)), 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 57u) {
            float thermalTotal = max(
                volumeA.intIThermalBody + volumeA.intIThermalCloud + volumeA.intIThermalCorona,
                volumeA.intIThermal
            );
            raw = clamp(volumeA.intIThermalBody / max(thermalTotal + volumeA.intIThin, 1e-30), 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 58u) {
            float body = max(volumeA.intIThermalBody, 0.0);
            float skin = max(volumeA.intIThermalCloud + volumeA.intIThermalCorona, 0.0);
            raw = clamp(skin / max(body + skin, 1e-30), 0.0, 1.0);
        } else if (P.diskGrmhdDebugView == 59u) {
            if (volumeA.visibleSpectrumMode == 1u) {
                raw = (FC_PHYSICS_MODE == 2u)
                    ? max(volumeA.IVisNu.y, 0.0)
                    : max(volume_visible_bands_to_xyz(volumeA, P).y, 0.0);
            } else {
                raw = max(dot(max(volumeA.IVisNu, float3(0.0)), float3(0.13344, 0.85742, 0.00914)), 0.0);
            }
        } else if (P.diskGrmhdDebugView == 47u) {
            raw = max(volumeA.maxFlowResidual, 0.0);
        }
        info.noise = raw;
        info.emit_r_norm = raw;
        info.emit_phi = max(volumeA.maxRho, 0.0);
        info.emit_z_norm = max(volumeA.maxB2, 0.0);
    } else if (grmhd_raw_debug_enabled(P)) {
        info.noise = max(volumeA.maxI, 0.0);
        info.emit_r_norm = max(volumeA.maxRho, 0.0);
        info.emit_phi = max(volumeA.maxB2, 0.0);
        info.emit_z_norm = max(volumeA.maxJ, 0.0);
    } else if (prepared.grmhdVisibleVolumetric) {
        if (volumeA.visibleSpectrumMode == 1u) {
            float3 xyz = (FC_PHYSICS_MODE == 2u)
                ? max(volumeA.IVisNu, float3(0.0))
                : volume_visible_bands_to_xyz(volumeA, P);
            info.noise = -60.0; // sentinel: emit_{r,phi,z} stores linear XYZ, not I_nu anchors.
            info.emit_r_norm = xyz.x;
            info.emit_phi = xyz.y;
            info.emit_z_norm = xyz.z;
        } else {
            info.noise = (P.diskPolarizedRT != 0u) ? prepared.polFrac : clamp(prepared.noiseMean, 0.0, 1.0);
            info.emit_r_norm = max(volumeA.IVisNu.x, 0.0);
            info.emit_phi = max(volumeA.IVisNu.y, 0.0);
            info.emit_z_norm = max(volumeA.IVisNu.z, 0.0);
        }
        if (P.rayBundleJacobian != 0u) {
            info.ct = prepared.pos.x;
            info._pad0 = prepared.pos.y;
            info.direct_world.w = prepared.pos.z;
        }
    } else {
        info.noise = clamp(prepared.noiseMean, 0.0, 1.0);
        info.emit_r_norm = prepared.rEmit / max(P.rs, 1e-6);
        info.emit_phi = atan2(prepared.pos.y, prepared.pos.x);
        info.emit_z_norm = prepared.pos.z / max(P.rs, 1e-6);
    }
}
#endif
