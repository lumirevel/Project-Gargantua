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
    if (!(volumeMode &&
          (grmhdVisibleSurfaceHit ||
           ((FC_PHYSICS_MODE == 3u) && volumeA.I > 0.0) ||
           ((FC_PHYSICS_MODE != 3u) && volumeA.w > 0.0)))) {
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
        float iVisWeighted = dot(max(volumeA.IVisNu, float3(0.0)), float3(0.30, 0.40, 0.30));
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
    float iVisTotRaw = dot(volumeA.IVisNu, float3(1.0));
    float iVisTot = max(iVisTotRaw, 1e-30);
    float qVisTot = dot(volumeA.QVisNu, float3(1.0));
    float uVisTot = dot(volumeA.UVisNu, float3(1.0));
    float vVisTot = dot(volumeA.VVisNu, float3(1.0));
    float polFrac = clamp(sqrt(max(qVisTot*qVisTot + uVisTot*uVisTot + vVisTot*vVisTot, 0.0)) / iVisTot, 0.0, 1.0);
    bool grmhdVisibleVolumetric = (grmhd_visible_mode_enabled() &&
                                   P.visiblePhotosphereRhoThreshold <= 0.0 &&
                                   !grmhdVisibleSurfaceHit);

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
    } else if (grmhd_raw_debug_enabled(P)) {
        info.noise = max(volumeA.maxI, 0.0);
        info.emit_r_norm = max(volumeA.maxRho, 0.0);
        info.emit_phi = max(volumeA.maxB2, 0.0);
        info.emit_z_norm = max(volumeA.maxJ, 0.0);
    } else if (prepared.grmhdVisibleVolumetric) {
        info.noise = (P.diskPolarizedRT != 0u) ? prepared.polFrac : clamp(prepared.noiseMean, 0.0, 1.0);
        info.emit_r_norm = max(volumeA.IVisNu.x, 0.0);
        info.emit_phi = max(volumeA.IVisNu.y, 0.0);
        info.emit_z_norm = max(volumeA.IVisNu.z, 0.0);
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
