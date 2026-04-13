import Foundation
import Metal

struct RenderTracePhaseInput {
    let queue: MTLCommandQueue
    let params: PackedParams
    let width: Int
    let height: Int
    let effectiveTile: Int
    let traceTileTotal: Int
    let traceTilesX: Int
    let traceTilesY: Int
    let tg: MTLSize
    let tgLinearTile1D: MTLSize
    let traceSlots: [InFlightTraceSlot]
    let maxInFlight: Int
    let totalPixels: Int
    let totalOps: Int
    let progressStep: Int
    let useLinear32Intermediate: Bool
    let useInMemoryCollisions: Bool
    let directLinearEnabled: Bool
    let collisionLite32Enabled: Bool
    let discardCollisionOutput: Bool
    let traceStride: Int
    let linearStride: Int
    let linearCloudBins: Int
    let linearLumBins: Int
    let linearLumLogMin: Float
    let linearLumLogMax: Float
    let composeExposure: Float
    let composeDitherArg: Float
    let composeInnerEdgeArg: Float
    let composeSpectralStepArg: Float
    let composeLookID: UInt32
    let spectralEncodingID: UInt32
    let composePrecisionID: UInt32
    let composeAnalysisMode: UInt32
    let composeCameraModelID: UInt32
    let composeCameraPsfSigmaArg: Float
    let composeCameraReadNoiseArg: Float
    let composeCameraShotNoiseArg: Float
    let composeCameraFlareStrengthArg: Float
    let backgroundModeID: UInt32
    let backgroundStarDensityArg: Float
    let backgroundStarStrengthArg: Float
    let backgroundNebulaStrengthArg: Float
    let preserveHighlightColor: UInt32
    let directLinearParamBuf: MTLBuffer?
    let directLinearTraceBuf: MTLBuffer?
    let directLinearHitCountBuf: MTLBuffer?
    let composeBaseBufForLinear: MTLBuffer?
    let collisionBuffer: MTLBuffer?
    let collisionBase: UnsafeMutableRawPointer?
    let outHandle: FileHandle?
    let linearOutHandle: FileHandle?
    let tracePipeline: MTLComputePipelineState
    let composeLinearTilePipeline: MTLComputePipelineState
    let diskAtlasTex: MTLTexture
    let diskVol0Tex: MTLTexture
    let diskVol1Tex: MTLTexture
}

struct RenderTracePhaseResult {
    let hitCount: Int
    let donePixels: Int
    let nextProgressMark: Int
    let lastProgressPrint: TimeInterval
    let linearCloudHistGlobal: [UInt32]
    let linearCloudSampleCount: UInt64
}

enum RenderTracePhase {
    static func execute(_ input: RenderTracePhaseInput) throws -> RenderTracePhaseResult {
        var linearCloudHistGlobal = [UInt32](repeating: 0, count: input.linearCloudBins)
        var linearCloudSampleCount: UInt64 = 0
        var hitCount = 0
        var donePixels = 0
        var nextProgressMark = input.progressStep
        var lastProgressPrint = Date().timeIntervalSince1970
        var traceTileIndex = 0

        emitETAProgress(0, input.totalOps, "swift_trace", "task=trace tile=0/\(input.traceTileTotal)")

        let inFlightSemaphore = DispatchSemaphore(value: input.maxInFlight)
        let traceDispatchGroup = DispatchGroup()
        let ioQueue = DispatchQueue(label: "blackhole.trace.io")
        var traceIOError: Error? = nil
        let traceIOErrorLock = NSLock()
        func traceGetError() -> Error? {
            traceIOErrorLock.lock()
            defer { traceIOErrorLock.unlock() }
            return traceIOError
        }
        func traceSetErrorIfNil(_ error: Error) {
            traceIOErrorLock.lock()
            if traceIOError == nil {
                traceIOError = error
            }
            traceIOErrorLock.unlock()
        }

        var traceDispatchIndex = 0
        var ty = 0
        while ty < input.height {
            let tileH = min(input.effectiveTile, input.height - ty)
            var tx = 0
            while tx < input.width {
                let tileW = min(input.effectiveTile, input.width - tx)
                let tileCount = tileW * tileH
                let tileOriginX = tx
                let tileOriginY = ty
                let tileOrdinal = traceTileIndex + 1
                traceTileIndex += 1

                inFlightSemaphore.wait()
                if let e = traceGetError() {
                    inFlightSemaphore.signal()
                    throw e
                }
                let slot = input.traceSlots[traceDispatchIndex % input.maxInFlight]
                traceDispatchIndex += 1

                var tileParams = input.params
                tileParams.width = UInt32(tileW)
                tileParams.height = UInt32(tileH)
                tileParams.fullWidth = UInt32(input.width)
                tileParams.fullHeight = UInt32(input.height)
                tileParams.offsetX = UInt32(tileOriginX)
                tileParams.offsetY = UInt32(tileOriginY)
                updateBuffer(slot.traceParamBuf, with: &tileParams)

                if input.useLinear32Intermediate {
                    guard let linearParamBuf = slot.linearParamBuf else {
                        fail("linear32 slot param buffer missing")
                    }
                    var linearTileParams = ComposeParams(
                        tileWidth: UInt32(tileW),
                        tileHeight: UInt32(tileH),
                        downsample: 1,
                        outTileWidth: 0,
                        outTileHeight: 0,
                        srcOffsetX: UInt32(tileOriginX),
                        srcOffsetY: UInt32(tileOriginY),
                        outOffsetX: 0,
                        outOffsetY: 0,
                        fullInputWidth: UInt32(input.width),
                        fullInputHeight: UInt32(input.height),
                        exposure: input.composeExposure,
                        dither: input.composeDitherArg,
                        innerEdgeMult: input.composeInnerEdgeArg,
                        spectralStep: input.composeSpectralStepArg,
                        cloudQ10: 0.0,
                        cloudInvSpan: 1.0,
                        look: input.composeLookID,
                        spectralEncoding: input.spectralEncodingID,
                        precisionMode: input.composePrecisionID,
                        analysisMode: input.composeAnalysisMode,
                        cloudBins: UInt32(input.linearCloudBins),
                        lumBins: UInt32(input.linearLumBins),
                        lumLogMin: input.linearLumLogMin,
                        lumLogMax: input.linearLumLogMax,
                        cameraModel: input.composeCameraModelID,
                        cameraPsfSigmaPx: input.composeCameraPsfSigmaArg,
                        cameraReadNoise: input.composeCameraReadNoiseArg,
                        cameraShotNoise: input.composeCameraShotNoiseArg,
                        cameraFlareStrength: input.composeCameraFlareStrengthArg,
                        backgroundMode: input.backgroundModeID,
                        backgroundStarDensity: input.backgroundStarDensityArg,
                        backgroundStarStrength: input.backgroundStarStrengthArg,
                        backgroundNebulaStrength: input.backgroundNebulaStrengthArg,
                        preserveHighlightColor: input.preserveHighlightColor
                    )
                    updateBuffer(linearParamBuf, with: &linearTileParams)
                }

                traceDispatchGroup.enter()
                let cmd = input.queue.makeCommandBuffer()!
                let enc = cmd.makeComputeCommandEncoder()!
                enc.setComputePipelineState(input.tracePipeline)
                enc.setBuffer(slot.traceParamBuf, offset: 0, index: 0)
                if input.directLinearEnabled {
                    guard let directLinearParamBuf = input.directLinearParamBuf,
                          let directLinearTraceBuf = input.directLinearTraceBuf,
                          let directLinearHitCountBuf = input.directLinearHitCountBuf else {
                        fail("direct linear trace buffers are missing")
                    }
                    enc.setBuffer(directLinearParamBuf, offset: 0, index: 1)
                    enc.setBuffer(directLinearTraceBuf, offset: 0, index: 2)
                    enc.setBuffer(directLinearHitCountBuf, offset: 0, index: 3)
                } else if input.useInMemoryCollisions {
                    guard let collisionBuffer = input.collisionBuffer else {
                        fail("in-memory collision buffer missing for global trace path")
                    }
                    enc.setBuffer(collisionBuffer, offset: 0, index: 1)
                } else {
                    guard let traceTileBuf = slot.traceTileBuf else {
                        fail("trace tile buffer missing for local trace path")
                    }
                    enc.setBuffer(traceTileBuf, offset: 0, index: 1)
                }
                enc.setTexture(input.diskAtlasTex, index: 0)
                enc.setTexture(input.diskVol0Tex, index: 1)
                enc.setTexture(input.diskVol1Tex, index: 2)
                enc.dispatchThreads(MTLSize(width: tileW, height: tileH, depth: 1), threadsPerThreadgroup: input.tg)
                enc.endEncoding()

                if input.useLinear32Intermediate {
                    guard let composeBaseBufForLinear = input.composeBaseBufForLinear,
                          let linearParamBuf = slot.linearParamBuf,
                          let traceTileBuf = slot.traceTileBuf,
                          let linearTileBuf = slot.linearTileBuf else {
                        fail("linear32 slot buffers are not available")
                    }
                    let linearEnc = cmd.makeComputeCommandEncoder()!
                    linearEnc.setComputePipelineState(input.composeLinearTilePipeline)
                    linearEnc.setBuffer(composeBaseBufForLinear, offset: 0, index: 0)
                    linearEnc.setBuffer(linearParamBuf, offset: 0, index: 1)
                    linearEnc.setBuffer(traceTileBuf, offset: 0, index: 2)
                    linearEnc.setBuffer(linearTileBuf, offset: 0, index: 3)
                    linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: input.tgLinearTile1D)
                    linearEnc.endEncoding()
                }

                cmd.addCompletedHandler { cmdBuf in
                    ioQueue.async {
                        defer {
                            inFlightSemaphore.signal()
                            traceDispatchGroup.leave()
                        }
                        if traceGetError() != nil { return }
                        if cmdBuf.status != .completed {
                            traceSetErrorIfNil(cmdBuf.error ?? NSError(domain: "Blackhole", code: 70, userInfo: [NSLocalizedDescriptionKey: "trace command buffer failed"]))
                            return
                        }
                        do {
                            if input.directLinearEnabled {
                                // hitCount is accumulated on GPU for direct-linear trace path.
                            } else if input.useInMemoryCollisions {
                                if let collisionBase = input.collisionBase {
                                    let fullPtr = collisionBase.bindMemory(to: CollisionInfo.self, capacity: input.totalPixels)
                                    var localHits = 0
                                    for row in 0..<tileH {
                                        let rowBase = (tileOriginY + row) * input.width + tileOriginX
                                        for col in 0..<tileW {
                                            if fullPtr[rowBase + col].hit != 0 { localHits += 1 }
                                        }
                                    }
                                    hitCount += localHits
                                }
                            } else if let traceTileBuf = slot.traceTileBuf {
                                var localHits = 0
                                if input.collisionLite32Enabled {
                                    let ptr = traceTileBuf.contents().bindMemory(to: CollisionLite32.self, capacity: tileCount)
                                    for i in 0..<tileCount where ptr[i].noise_dirOct_hit.w > 0.5 { localHits += 1 }
                                } else {
                                    let ptr = traceTileBuf.contents().bindMemory(to: CollisionInfo.self, capacity: tileCount)
                                    for i in 0..<tileCount where ptr[i].hit != 0 { localHits += 1 }
                                }
                                hitCount += localHits
                            }

                            if input.useLinear32Intermediate {
                                guard let linearOutHandle = input.linearOutHandle, let linearTileBuf = slot.linearTileBuf else {
                                    throw NSError(domain: "Blackhole", code: 71, userInfo: [NSLocalizedDescriptionKey: "linear32 output buffers missing"])
                                }
                                let linearPtr = linearTileBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: tileCount)
                                for i in 0..<tileCount {
                                    let w = linearPtr[i].w
                                    if w < 0 { continue }
                                    let cloud = min(max(Double(w), 0.0), 1.0)
                                    let bin = min(max(Int(floor(cloud * Double(input.linearCloudBins - 1) + 0.5)), 0), input.linearCloudBins - 1)
                                    linearCloudHistGlobal[bin] = linearCloudHistGlobal[bin] &+ 1
                                    linearCloudSampleCount += 1
                                }
                                for row in 0..<tileH {
                                    let rowBytes = tileW * input.linearStride
                                    let src = linearTileBuf.contents().advanced(by: row * rowBytes)
                                    let dstOffset = ((tileOriginY + row) * input.width + tileOriginX) * input.linearStride
                                    try linearOutHandle.seek(toOffset: UInt64(dstOffset))
                                    try linearOutHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                                }
                            } else if !input.useInMemoryCollisions {
                                if let traceTileBuf = slot.traceTileBuf {
                                    for row in 0..<tileH {
                                        let rowBytes = tileW * input.traceStride
                                        let src = traceTileBuf.contents().advanced(by: row * rowBytes)
                                        let dstOffset = ((tileOriginY + row) * input.width + tileOriginX) * input.traceStride
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
                        } catch {
                            traceSetErrorIfNil(error)
                            return
                        }

                        donePixels += tileCount
                        let now = Date().timeIntervalSince1970
                        if donePixels >= input.totalPixels || donePixels >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                            emitETAProgress(donePixels, input.totalOps, "swift_trace", "task=trace tile=\(tileOrdinal)/\(input.traceTileTotal)")
                            lastProgressPrint = now
                            while nextProgressMark <= donePixels {
                                nextProgressMark += input.progressStep
                            }
                        }
                    }
                }
                cmd.commit()
                tx += tileW
            }
            ty += tileH
        }

        traceDispatchGroup.wait()
        if let e = traceGetError() {
            throw e
        }
        if let directLinearHitCountBuf = input.directLinearHitCountBuf {
            hitCount = Int(directLinearHitCountBuf.contents().bindMemory(to: UInt32.self, capacity: 1).pointee)
        }

        return RenderTracePhaseResult(
            hitCount: hitCount,
            donePixels: donePixels,
            nextProgressMark: nextProgressMark,
            lastProgressPrint: lastProgressPrint,
            linearCloudHistGlobal: linearCloudHistGlobal,
            linearCloudSampleCount: linearCloudSampleCount
        )
    }
}
