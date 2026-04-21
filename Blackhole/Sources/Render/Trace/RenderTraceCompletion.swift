import Foundation
import Metal

struct RenderTraceCompletionResult {
    let localHits: Int
    let linearCloudHist: [UInt32]
    let linearCloudSampleCount: UInt64
}

enum RenderTraceCompletion {
    static func processTile(
        input: RenderTracePhaseInput,
        slot: InFlightTraceSlot,
        tile: RenderTraceTile
    ) throws -> RenderTraceCompletionResult {
        var localHits = 0
        var linearCloudHist = [UInt32](repeating: 0, count: input.linearCloudBins)
        var linearCloudSampleCount: UInt64 = 0

        if input.directLinearEnabled {
            // hitCount is accumulated on GPU for direct-linear trace path.
        } else if input.useInMemoryCollisions {
            if let collisionBase = input.collisionBase {
                let fullPtr = collisionBase.bindMemory(to: CollisionInfo.self, capacity: input.totalPixels)
                for row in 0..<tile.height {
                    let rowBase = (tile.originY + row) * input.width + tile.originX
                    for col in 0..<tile.width {
                        if fullPtr[rowBase + col].hit != 0 { localHits += 1 }
                    }
                }
            }
        } else if let traceTileBuf = slot.traceTileBuf {
            if input.collisionLite32Enabled {
                let ptr = traceTileBuf.contents().bindMemory(to: CollisionLite32.self, capacity: tile.pixelCount)
                for i in 0..<tile.pixelCount where ptr[i].noise_dirOct_hit.w > 0.5 { localHits += 1 }
            } else {
                let ptr = traceTileBuf.contents().bindMemory(to: CollisionInfo.self, capacity: tile.pixelCount)
                for i in 0..<tile.pixelCount where ptr[i].hit != 0 { localHits += 1 }
            }
        }

        if input.useLinear32Intermediate {
            guard let linearOutHandle = input.linearOutHandle, let linearTileBuf = slot.linearTileBuf else {
                throw NSError(domain: "Blackhole", code: 71, userInfo: [NSLocalizedDescriptionKey: "linear32 output buffers missing"])
            }
            let linearPtr = linearTileBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: tile.pixelCount)
            for i in 0..<tile.pixelCount {
                let w = linearPtr[i].w
                if w < 0 { continue }
                let cloud = min(max(Double(w), 0.0), 1.0)
                let bin = min(max(Int(floor(cloud * Double(input.linearCloudBins - 1) + 0.5)), 0), input.linearCloudBins - 1)
                linearCloudHist[bin] = linearCloudHist[bin] &+ 1
                linearCloudSampleCount += 1
            }
            for row in 0..<tile.height {
                let rowBytes = tile.width * input.linearStride
                let src = linearTileBuf.contents().advanced(by: row * rowBytes)
                let dstOffset = ((tile.originY + row) * input.width + tile.originX) * input.linearStride
                try linearOutHandle.seek(toOffset: UInt64(dstOffset))
                try linearOutHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
            }
        } else if !input.useInMemoryCollisions {
            if let traceTileBuf = slot.traceTileBuf {
                for row in 0..<tile.height {
                    let rowBytes = tile.width * input.traceStride
                    let src = traceTileBuf.contents().advanced(by: row * rowBytes)
                    let dstOffset = ((tile.originY + row) * input.width + tile.originX) * input.traceStride
                    if let outHandle = input.outHandle {
                        try outHandle.seek(toOffset: UInt64(dstOffset))
                        try outHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                    } else if input.discardCollisionOutput {
                        // intentionally skip collision writes when output is marked disposable
                    } else {
                        throw NSError(domain: "Blackhole", code: 72, userInfo: [NSLocalizedDescriptionKey: "no collision output sink available"])
                    }
                }
            }
        }

        return RenderTraceCompletionResult(
            localHits: localHits,
            linearCloudHist: linearCloudHist,
            linearCloudSampleCount: linearCloudSampleCount
        )
    }
}
