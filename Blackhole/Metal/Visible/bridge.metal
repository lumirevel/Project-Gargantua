#if defined(BH_INCLUDE_VISIBLE_TRANSPORT_BRIDGE) && (BH_INCLUDE_VISIBLE_TRANSPORT_BRIDGE)
static inline float comp_visible_iNu_emit(float nuEm, float te, constant Params& P);
static inline void comp_visible_xyz_from_spectrum(float T_emit,
                                                  float g_total,
                                                  constant Params& P,
                                                  thread float& X,
                                                  thread float& Y,
                                                  thread float& Z,
                                                  thread float& yLum,
                                                  thread float& peakLamNm);
static inline void comp_visible_xyz_from_three_band_inu(float3 iNuVisObs,
                                                        float colorDilution,
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
            comp_visible_xyz_from_three_band_inu(iNuVis, colorDilution, P, X, Y, Z, yLum, peakLam);
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
#endif
