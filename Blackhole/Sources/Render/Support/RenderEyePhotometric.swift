import Foundation
import simd

/// Resolves the physically anchored human-eye observer parameters once the
/// scene luminance statistics are known (after the exposure histogram solve).
///
/// The disk photosphere sits at solar-surface-order luminance, so the honest
/// "what the eye sees" chain is: a neutral-density safe-viewing filter (a pure
/// linear attenuation, carried through the existing exposure multiplier),
/// then retinal adaptation to the filtered scene. The GPU side
/// (comp_eye_physiological_display) applies the Naka-Rushton photoreceptor
/// response and mesopic rod/cone blending against the adaptation luminance
/// resolved here.
enum RenderEyePhotometric {
    struct Resolution {
        var ndDensity: Double
        var ndLinear: Double
        var adaptationLuminance: Double
        var pupilDiameterMm: Double
        var eyeParams: SIMD4<Float>
        var summary: String
    }

    static func resolve(config: ResolvedRenderConfig,
                        cameraModelID: UInt32,
                        p50: Double?,
                        p995: Double?) -> Resolution? {
        guard config.eyePhotometricEnabled,
              cameraModelID == 3,
              config.composeAnalysisMode == 0 else { return nil }
        let absPerY = 683.002 * max(config.cameraLuminanceScaleArg, 1e-12)

        var nd = config.eyeNDArg
        if nd < 0 {
            guard let p995, p995 > 0 else {
                FileHandle.standardError.write(Data(
                    "warn: eye photometric auto-ND needs the luminance histogram; pass --eye-nd explicitly. physiological eye disabled.\n".utf8))
                return nil
            }
            // Choose the filter so the near-peak scene luminance lands at the
            // photopic viewing target (default 8000 cd/m^2, bright sky). Note the
            // Naka-Rushton display below is invariant to this global attenuation
            // (scene and adaptation luminance scale together); the ND only sets
            // the absolute level for the mesopic rod/cone weighting.
            nd = max(0.0, log10(absPerY * p995 / max(config.eyeTargetLuminanceArg, 1.0)))
        }
        let ndLinear = pow(10.0, -nd)

        var adapt = config.eyeAdaptationArg
        if adapt <= 0 {
            if let p50, p50 > 0 {
                // Adaptation anchor. Pinning it to the scene median puts the median
                // pixel exactly at the Naka-Rushton half-response, and the white
                // normalization maps half-response to display ~0.68 — so the body of
                // a narrow-histogram disk (thermal photosphere: p99.5 within ~2.5x
                // of the median) is structurally pinned near white and its texture
                // compresses into a couple of 8-bit counts. Physiologically the
                // adaptation pool of an observer staring at a bright disk is driven
                // toward the bright field, not the scene median; anchoring at the
                // geometric mean of the median and near-peak luminance drops the
                // median below half-response (structure becomes visible) for narrow
                // scenes while barely moving wide-histogram scenes whose body spans
                // the response range anyway.
                let anchor = (p995 != nil && p995! > 0) ? sqrt(p50 * p995!) : p50
                adapt = absPerY * anchor * ndLinear
            } else {
                adapt = config.eyeTargetLuminanceArg * 0.125
            }
        }
        adapt = max(adapt, 1e-6)

        // Stanley & Davies (1995) pupil diameter for a ~30x30 degree adapting
        // field; reported for the record (the Naka-Rushton semi-saturation is
        // anchored in cd/m^2, which folds in the typical pupil response).
        let x = pow(adapt * 900.0 / 846.0, 0.41)
        let pupil = 7.75 - 5.75 * (x / (x + 2.0))

        let params = SIMD4<Float>(Float(adapt), Float(absPerY),
                                  Float(config.eyeWhiteMultipleArg), 0)
        let summary = String(
            format: "eye photometric: ND=%.2f adaptation=%.4g cd/m2 pupil=%.2f mm whiteMul=%.1f",
            nd, adapt, pupil, config.eyeWhiteMultipleArg)
        return Resolution(ndDensity: nd,
                          ndLinear: ndLinear,
                          adaptationLuminance: adapt,
                          pupilDiameterMm: pupil,
                          eyeParams: params,
                          summary: summary)
    }
}
