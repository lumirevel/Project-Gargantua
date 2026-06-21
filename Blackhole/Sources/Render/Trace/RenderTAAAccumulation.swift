import Foundation
import Metal

/// Sub-pixel-jitter temporal anti-aliasing.
///
/// The renderer is a deterministic deferred GPU pipeline (trace -> linear HDR ->
/// tone map). Temporal AA here is offline temporal supersampling: trace the scene
/// N times, each with a deterministic Halton(2,3) sub-pixel camera jitter, and
/// average the *linear* HDR radiance before the single tone-map/compose pass.
///
/// This is purely an observation-pipeline sampling choice. Per-ray geodesic
/// integration, hit logic, and radiative transfer are unchanged; only the camera
/// sample positions move (via `motionBlurParams.zw`, which default to 0 so an
/// unjittered render is byte-identical). Averaging happens in linear light, so it
/// is physically correct supersampling rather than a tone-mapping trick.
enum RenderTAAAccumulation {
    /// Van der Corput / Halton radical inverse in the given base.
    private static func radicalInverse(_ index: Int, base: Int) -> Float {
        let invBase = 1.0 / Float(base)
        var result: Float = 0
        var f = invBase
        var i = index
        while i > 0 {
            result += Float(i % base) * f
            i /= base
            f *= invBase
        }
        return result
    }

    /// Deterministic sub-pixel offset in pixel units, centered on the pixel:
    /// each component lies in [-0.5, 0.5). Sample 0 is offset by 1 so the
    /// sequence does not start at the degenerate (0,0) center.
    static func jitter(forSample sample: Int) -> (Float, Float) {
        let jx = radicalInverse(sample + 1, base: 2) - 0.5
        let jy = radicalInverse(sample + 1, base: 3) - 0.5
        return (jx, jy)
    }

    /// Run `samples` jittered trace passes, averaging the linear HDR intermediate
    /// in place. The averaged radiance is written back to `linearURL` so the
    /// existing HDR compose path tone-maps the converged image exactly once.
    /// Returns the first pass's trace result (used only for histogram/metadata).
    static func run(
        samples: Int,
        params: PackedParams,
        width: Int,
        height: Int,
        linearStride: Int,
        linearURL: URL,
        linearOutHandle: FileHandle?,
        makeTraceInput: (PackedParams) -> RenderTracePhaseInput
    ) throws -> RenderTracePhaseResult {
        guard samples > 1, let linearOutHandle else {
            return try RenderTracePhase.execute(makeTraceInput(params))
        }
        guard linearStride == MemoryLayout<SIMD4<Float>>.stride else {
            throw NSError(domain: "Blackhole", code: 121, userInfo: [NSLocalizedDescriptionKey:
                "TAA accumulation requires the float4 linear HDR layout (stride \(linearStride))"])
        }

        let floatCount = width * height * 4
        let expectedBytes = floatCount * MemoryLayout<Float>.size
        var accum = [Float](repeating: 0, count: floatCount)
        var firstResult: RenderTracePhaseResult?

        for sample in 0..<samples {
            var passParams = params
            let (jx, jy) = jitter(forSample: sample)
            passParams.motionBlurParams.z = jx
            passParams.motionBlurParams.w = jy

            let result = try RenderTracePhase.execute(makeTraceInput(passParams))
            if firstResult == nil { firstResult = result }

            // The trace wrote this pass's linear HDR through linearOutHandle.
            // Flush it and fold it into the running sum.
            try linearOutHandle.synchronize()
            let data = try Data(contentsOf: linearURL)
            guard data.count >= expectedBytes else {
                throw NSError(domain: "Blackhole", code: 122, userInfo: [NSLocalizedDescriptionKey:
                    "TAA pass \(sample + 1) produced \(data.count) bytes, expected \(expectedBytes)"])
            }
            data.withUnsafeBytes { raw in
                let f = raw.bindMemory(to: Float.self)
                for i in 0..<floatCount { accum[i] += f[i] }
            }
            print("taa pass \(sample + 1)/\(samples) jitter=(\(String(format: "%+.3f", jx)), \(String(format: "%+.3f", jy)))")
        }

        let inv = 1.0 / Float(samples)
        for i in 0..<floatCount { accum[i] *= inv }

        let outData = accum.withUnsafeBufferPointer { Data(buffer: $0) }
        try linearOutHandle.seek(toOffset: 0)
        try linearOutHandle.write(contentsOf: outData)
        try linearOutHandle.synchronize()
        print("taa: averaged \(samples) jittered passes into linear HDR; tone-mapping once")

        guard let firstResult else {
            return try RenderTracePhase.execute(makeTraceInput(params))
        }
        return firstResult
    }
}
