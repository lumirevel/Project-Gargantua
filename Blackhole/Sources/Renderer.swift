import Foundation

func normalize(_ v: SIMD3<Float>) -> SIMD3<Float> {
    let len = sqrt(v.x * v.x + v.y * v.y + v.z * v.z)
    return v / len
}

func cross(_ a: SIMD3<Float>, _ b: SIMD3<Float>) -> SIMD3<Float> {
    SIMD3<Float>(a.y * b.z - a.z * b.y, a.z * b.x - a.x * b.z, a.x * b.y - a.y * b.x)
}

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

@inline(__always)
func emitETAProgress(_ done: Int, _ total: Int, _ phase: String, _ extra: String = "") {
    let safeTotal = max(total, 1)
    let suffix = extra.isEmpty ? "" : " " + extra
    let line = "ETA_PROGRESS \(done) \(safeTotal) \(phase)\(suffix)\n"
    FileHandle.standardError.write(Data(line.utf8))
}

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
    if lookID == 1 { return 0.9 }   // interstellar
    if lookID == 2 { return 0.6 }   // eht
    if lookID == 3 { return 1.25 }  // agx/filmic: avoid chronic underexposure vs ACES-tuned default
    if lookID == 5 { return 1.40 }  // hdr: keep richer highlight headroom before display rolloff
    return 0.8
}

func cieXYZBar(_ wavelengthNm: Double) -> (Double, Double, Double) {
    let lam = wavelengthNm
    let t1x = (lam - 442.0) * (lam < 442.0 ? 0.0624 : 0.0374)
    let t2x = (lam - 599.8) * (lam < 599.8 ? 0.0264 : 0.0323)
    let t3x = (lam - 501.1) * (lam < 501.1 ? 0.0490 : 0.0382)
    let x = 0.362 * exp(-0.5 * t1x * t1x) + 1.056 * exp(-0.5 * t2x * t2x) - 0.065 * exp(-0.5 * t3x * t3x)

    let t1y = (lam - 568.8) * (lam < 568.8 ? 0.0213 : 0.0247)
    let t2y = (lam - 530.9) * (lam < 530.9 ? 0.0613 : 0.0322)
    let y = 0.821 * exp(-0.5 * t1y * t1y) + 0.286 * exp(-0.5 * t2y * t2y)

    let t1z = (lam - 437.0) * (lam < 437.0 ? 0.0845 : 0.0278)
    let t2z = (lam - 459.0) * (lam < 459.0 ? 0.0385 : 0.0725)
    let z = 1.217 * exp(-0.5 * t1z * t1z) + 0.681 * exp(-0.5 * t2z * t2z)
    return (max(x, 0.0), max(y, 0.0), max(z, 0.0))
}

func planckLambda(_ lambdaMeters: Double, _ temp: Double) -> Double {
    let c1 = 2.0 * 6.62607015e-34 * 299_792_458.0 * 299_792_458.0
    let c2 = 6.62607015e-34 * 299_792_458.0 / 1.380649e-23
    let x = min(max(c2 / max(lambdaMeters * temp, 1e-30), 1e-8), 700.0)
    return c1 / (pow(lambdaMeters, 5.0) * expm1(x))
}

func planckNu(_ nuHz: Double, _ temp: Double) -> Double {
    let h = 6.62607015e-34
    let c = 299_792_458.0
    let k = 1.380649e-23
    let x = min(max((h * nuHz) / max(k * temp, 1e-30), 1e-8), 700.0)
    let num = 2.0 * h * nuHz * nuHz * nuHz / (c * c)
    return num / max(expm1(x), 1e-30)
}

func visibleINuEmit(_ nuHz: Double, _ temp: Double, _ emissionModel: UInt32, _ alpha: Double) -> Double {
    if emissionModel == 1 {
        // Synchrotron-like power-law shape anchored to thermal scale at a pivot frequency.
        let nuPivot = 5.0e14
        let ratio = max(nuHz / nuPivot, 1e-8)
        let slope = min(max(alpha, 0.0), 4.0)
        let pivot = planckNu(nuPivot, temp)
        return pivot * pow(ratio, -slope)
    }
    return planckNu(nuHz, temp)
}

func estimateGRMHDRhoMax(vol0Data: Data) -> Double {
    let floatCount = vol0Data.count / MemoryLayout<Float>.stride
    if floatCount < 4 { return 0.0 }
    let sampleCount = floatCount / 4
    var rhoMax = 0.0
    vol0Data.withUnsafeBytes { raw in
        guard let base = raw.bindMemory(to: Float.self).baseAddress else { return }
        var idx = 0
        for _ in 0..<sampleCount {
            let logRho = Double(base[idx])
            let rho = exp(min(max(logRho, -40.0), 40.0))
            if rho > rhoMax { rhoMax = rho }
            idx += 4
        }
    }
    return rhoMax
}

func fail(_ message: String, code: Int32 = 3) -> Never {
    FileHandle.standardError.write(Data(("error: " + message + "\n").utf8))
    exit(code)
}


enum Renderer {
    static func render(config: ResolvedRenderConfig, params: PackedParams) throws {
        let runtime = try RenderSetup.prepare(config: config, params: params)
        try RenderExecution.execute(config: config, params: params, runtime: runtime)
    }
}
