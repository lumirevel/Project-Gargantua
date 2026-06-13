import Foundation

func percentileSorted(_ sorted: [Float], _ q: Float) -> Float {
    if sorted.isEmpty { return 0.0 }
    let qq = min(max(q, 0.0), 1.0)
    if sorted.count == 1 { return sorted[0] }
    let pos = Float(sorted.count - 1) * qq
    let lo = Int(floor(pos))
    let hi = min(lo + 1, sorted.count - 1)
    let t = pos - Float(lo)
    return sorted[lo] * (1.0 - t) + sorted[hi] * t
}

func histogramQuantileBin(_ hist: UnsafeBufferPointer<UInt32>, _ q: Float) -> Int {
    if hist.isEmpty { return 0 }
    var total: UInt64 = 0
    for c in hist { total += UInt64(c) }
    if total == 0 { return 0 }
    let qq = min(max(q, 0.0), 1.0)
    let target = UInt64(Double(max(total - 1, 0)) * Double(qq))
    var cum: UInt64 = 0
    for i in 0..<hist.count {
        cum += UInt64(hist[i])
        if cum > target { return i }
    }
    return hist.count - 1
}

func quantileFromUniformHistogram(_ hist: UnsafeBufferPointer<UInt32>, _ q: Float, _ minVal: Float, _ maxVal: Float) -> Float {
    if hist.isEmpty { return minVal }
    let idx = histogramQuantileBin(hist, q)
    if hist.count == 1 { return minVal }
    let t = Float(idx) / Float(hist.count - 1)
    return minVal + (maxVal - minVal) * t
}

func composeTargetWhite(_ lookID: UInt32) -> Float {
    if lookID == 1 { return 0.9 }
    if lookID == 2 { return 0.6 }
    if lookID == 3 { return 1.25 }
    if lookID == 5 { return 1.40 }
    if lookID == 7 { return 1.10 }
    if lookID == 8 { return 1.05 }
    return 0.8
}

func composeTargetWhite(_ lookID: UInt32, presentationModeID: UInt32, realismProfileID: UInt32) -> Float {
    var target = composeTargetWhite(lookID)
    if presentationModeID == 1 {
        // Scientific PNG output is still a display product. Keep substantial
        // highlight headroom so GRMHD radiance structure does not collapse into
        // a white p99.5 silhouette before diagnostics can be inspected.
        target *= (lookID == 4) ? 0.45 : 0.58
    } else if presentationModeID == 2 {
        // Human-eye mode should preserve highlight structure rather than expose
        // the p99.5 disk to near-white. This is a display adaptation choice, not
        // a change to the scientific radiance buffer.
        target *= (realismProfileID >= 2) ? 0.66 : 0.74
    } else if presentationModeID == 3 {
        target *= 0.82
    }
    return target
}

struct ComposeExposureSolveSettings {
    let highQuantile: Float
    let targetWhite: Float
    let midQuantile: Float
    let targetMid: Float
    let maxExposureBoost: Float
    let pFloor: Float
}

func composeExposureSolveSettings(
    lookID: UInt32,
    presentationModeID: UInt32,
    realismProfileID: UInt32,
    diskPhysicsModeID: UInt32,
    diskVolumeEnabled: Bool
) -> ComposeExposureSolveSettings {
    var targetWhite = composeTargetWhite(
        lookID,
        presentationModeID: presentationModeID,
        realismProfileID: realismProfileID
    )
    if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }

    let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
    if diskPhysicsModeID == 3 && presentationModeID == 2 {
        // GRMHD eye renders have a small high-luminance ring plus a broad,
        // physically nonzero foreground disk. A pure p99.5 solve preserves
        // highlights but can under-display the broad disk body. Use a bounded
        // mid-luminance solve only for the presentation exposure; raw/science
        // radiance and diagnostics remain unchanged.
        return ComposeExposureSolveSettings(
            highQuantile: 0.995,
            targetWhite: targetWhite,
            midQuantile: 0.88,
            targetMid: 0.24,
            maxExposureBoost: (realismProfileID >= 2) ? 1.85 : 1.45,
            pFloor: pFloor
        )
    }
    if diskVolumeEnabled && diskPhysicsModeID == 2 && presentationModeID == 2 {
        // Precision 3D visible-volume renders have the same exposure failure
        // mode as GRMHD eye renders: small caustics dominate high percentiles
        // while the extended participating disk body becomes unreadably dark.
        // This affects only presentation exposure, not scientific radiance.
        return ComposeExposureSolveSettings(
            highQuantile: 0.94,
            targetWhite: targetWhite,
            midQuantile: 0.76,
            targetMid: 0.22,
            maxExposureBoost: 64.0,
            pFloor: pFloor
        )
    }

    return ComposeExposureSolveSettings(
        highQuantile: 0.995,
        targetWhite: targetWhite,
        midQuantile: 0.0,
        targetMid: 0.0,
        maxExposureBoost: 1.0,
        pFloor: pFloor
    )
}

func composeExposureFromLuminanceStats(
    pHigh: Float,
    pMid: Float,
    settings: ComposeExposureSolveSettings
) -> Float {
    let base = settings.targetWhite / max(pHigh, settings.pFloor)
    guard settings.midQuantile > 0.0, settings.targetMid > 0.0, pMid > 0.0 else {
        return base
    }
    let mid = settings.targetMid / max(pMid, settings.pFloor)
    let cap = base * max(settings.maxExposureBoost, 1.0)
    return max(base, min(mid, cap))
}

func composeLuminanceLogRange(diskPhysicsModeID: UInt32) -> (min: Float, max: Float) {
    if diskPhysicsModeID == 3 {
        // GRMHD visible transport now carries physical-ish multi-band radiance.
        // Keep the histogram wide enough for both the calibrated thermal-flow
        // branch and brighter hot-flow diagnostics. A 1e2 lower bound clips
        // current thermal-flow frames at the first bin, making auto exposure
        // solve from a fake p50/p99.5 and hiding the broad disk body.
        return (-8.0, 8.0)
    }
    // Visible spectral paths integrate SI spectral radiance (W m^-2 sr^-1):
    // disk photospheres from a few thousand to a few million Kelvin span
    // roughly Y ~ 1e2..1e9. The old (8, 20) range predates the SI dLambda
    // normalization and pinned every SI-scale frame to the first bin.
    return (-2.0, 12.0)
}
