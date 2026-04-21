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
    return 0.8
}
