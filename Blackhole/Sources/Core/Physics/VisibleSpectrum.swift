import Foundation

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
