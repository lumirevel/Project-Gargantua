import Foundation

@inline(__always)
func diskKerrISCOM(_ a: Double) -> Double {
    let aSafe = min(max(a, -0.999), 0.999)
    let a2 = aSafe * aSafe
    let z1 = 1.0 + pow(max(1.0 - a2, 0.0), 1.0 / 3.0) * (pow(1.0 + aSafe, 1.0 / 3.0) + pow(1.0 - aSafe, 1.0 / 3.0))
    let z2 = sqrt(max(3.0 * a2 + z1 * z1, 0.0))
    let sgn = (aSafe >= 0.0) ? 1.0 : -1.0
    return 3.0 + z2 - sgn * sqrt(max((3.0 - z1) * (3.0 + z1 + 2.0 * z2), 0.0))
}

@inline(__always)
func diskInnerRadiusM(metric: Int32, spin: Double, rs: Double) -> Double {
    if metric == 0 {
        return 3.0 * rs
    }
    let massLen = 0.5 * rs
    let rI = diskKerrISCOM(spin) * massLen
    let rH = diskHorizonRadiusM(metric: metric, spin: spin, rs: rs)
    return max(rI, rH * (1.0 + 16.0e-5))
}

@inline(__always)
func diskHorizonRadiusM(metric: Int32, spin: Double, rs: Double) -> Double {
    if metric == 0 { return rs }
    let a = min(max(abs(spin), 0.0), 0.999)
    let massLen = 0.5 * rs
    let rPlusM = 1.0 + sqrt(max(1.0 - a * a, 0.0))
    return max(rPlusM * massLen, 0.25 * rs)
}
