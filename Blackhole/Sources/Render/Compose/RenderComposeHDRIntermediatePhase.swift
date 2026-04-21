import Foundation
import Metal

struct RenderComposeHDRIntermediatePhaseResult {
    let composeExposure: Float
    let nextProgressMark: Int
    let lastProgressPrint: TimeInterval
}

enum RenderComposeHDRIntermediatePhase {
    static func execute(
        _ input: RenderComposePhaseInput,
        composeExposure: Float,
        nextProgressMark initialNextProgressMark: Int,
        lastProgressPrint initialLastProgressPrint: TimeInterval
    ) throws -> RenderComposeHDRIntermediatePhaseResult {
        let config = input.config
        let runtime = input.runtime
        let policy = input.policy
        let frameResources = input.frameResources
        let device = runtime.device
        let queue = runtime.queue

        let width = config.width
        let height = config.height
        let downsampleArg = config.downsampleArg
        let composeChunkArg = config.composeChunkArg
        let composeDitherArg = config.composeDitherArg
        let composeInnerEdgeArg = config.composeInnerEdgeArg
        let composeSpectralStepArg = config.composeSpectralStepArg
        let composeLookID = config.composeLookID
        let spectralEncodingID = config.spectralEncodingID
        let composePrecisionID = config.composePrecisionID
        let composeAnalysisMode = config.composeAnalysisMode
        let composeCameraModelID = config.composeCameraModelID
        let composeCameraPsfSigmaArg = config.composeCameraPsfSigmaArg
        let composeCameraReadNoiseArg = config.composeCameraReadNoiseArg
        let composeCameraShotNoiseArg = config.composeCameraShotNoiseArg
        let composeCameraFlareStrengthArg = config.composeCameraFlareStrengthArg
        let backgroundModeID = config.backgroundModeID
        let backgroundStarDensityArg = config.backgroundStarDensityArg
        let backgroundStarStrengthArg = config.backgroundStarStrengthArg
        let backgroundNebulaStrengthArg = config.backgroundNebulaStrengthArg
        let preserveHighlightColor = config.preserveHighlightColor
        let linearStride = policy.linearStride
        let outWidth = policy.outWidth
        let outHeight = policy.outHeight
        let linearCloudBins: UInt32 = 2048
        let linearLumBins: UInt32 = 4096
        let linearLumLogMin: Float = (config.diskPhysicsModeID == 3) ? -36.0 : 8.0
        let linearLumLogMax: Float = (config.diskPhysicsModeID == 3) ? 4.0 : 20.0

        let composeBHLinearTilePipeline = runtime.composeBHLinearTilePipeline
        let lumHistLinearTileCloudPipeline = runtime.lumHistLinearTileCloudPipeline
        let solveExposurePipeline = runtime.solveExposurePipeline
        let linearURL = frameResources.linearOutputURL
        var resolvedComposeExposure = composeExposure

        print("compose path=hdr32 file intermediate (\(linearURL.path))")

        var linearGlobalCloudQ10: Float = 0.0
        var linearGlobalCloudQ90: Float = 1.0
        var linearGlobalCloudInvSpan: Float = 1.0
        if input.traceResult.linearCloudSampleCount > 0 {
            linearGlobalCloudQ10 = input.traceResult.linearCloudHistGlobal.withUnsafeBufferPointer {
                quantileFromUniformHistogram($0, 0.08, 0.0, 1.0)
            }
            linearGlobalCloudQ90 = input.traceResult.linearCloudHistGlobal.withUnsafeBufferPointer {
                quantileFromUniformHistogram($0, 0.92, 0.0, 1.0)
            }
            linearGlobalCloudInvSpan = 1.0 / max(linearGlobalCloudQ90 - linearGlobalCloudQ10, 1e-6)
        }

        var composeParamsTemplate = ComposeParams(
            tileWidth: 0, tileHeight: 0, downsample: UInt32(downsampleArg), outTileWidth: 0, outTileHeight: 0,
            srcOffsetX: 0, srcOffsetY: 0, outOffsetX: 0, outOffsetY: 0,
            fullInputWidth: UInt32(width), fullInputHeight: UInt32(height), exposure: resolvedComposeExposure,
            dither: composeDitherArg, innerEdgeMult: composeInnerEdgeArg, spectralStep: composeSpectralStepArg,
            cloudQ10: linearGlobalCloudQ10, cloudInvSpan: linearGlobalCloudInvSpan,
            look: composeLookID, spectralEncoding: spectralEncodingID, precisionMode: composePrecisionID,
            analysisMode: composeAnalysisMode, cloudBins: linearCloudBins, lumBins: linearLumBins,
            lumLogMin: linearLumLogMin, lumLogMax: linearLumLogMax,
            cameraModel: composeCameraModelID, cameraPsfSigmaPx: composeCameraPsfSigmaArg,
            cameraReadNoise: composeCameraReadNoiseArg, cameraShotNoise: composeCameraShotNoiseArg,
            cameraFlareStrength: composeCameraFlareStrengthArg, backgroundMode: backgroundModeID,
            backgroundStarDensity: backgroundStarDensityArg, backgroundStarStrength: backgroundStarStrengthArg,
            backgroundNebulaStrength: backgroundNebulaStrengthArg, preserveHighlightColor: preserveHighlightColor,
            diskNoiseModel: input.params.diskNoiseModel,
            _pad0: 0,
            _pad1: 0,
            _pad2: 0
        )

        let rawComposeRows = max(1, composeChunkArg / max(width, 1))
        var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
        if composeRows <= 0 { composeRows = downsampleArg }
        if composeRows > height { composeRows = height }
        let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
        let maxComposeTileCount = width * composeRows
        let maxComposeOutTileCount = (width / downsampleArg) * (composeRows / downsampleArg)

        guard let linearTileInBuf = device.makeBuffer(length: maxComposeTileCount * linearStride, options: .storageModeShared) else {
            fail("failed to allocate linear32 compose input tile buffer")
        }
        guard let composeParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
            fail("failed to allocate linear32 compose param buffer")
        }
        guard let outBuf = device.makeBuffer(length: maxComposeOutTileCount * 4, options: .storageModeShared) else {
            fail("failed to allocate linear32 compose output tile buffer")
        }

        let tg = RenderThreadgroups.twoDimensional(composeBHLinearTilePipeline)
        let lumTg = RenderThreadgroups.oneDimensional(lumHistLinearTileCloudPipeline)
        var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        var composed = 0
        var cty = 0
        var composeTileIndex = 0
        var nextProgressMark = initialNextProgressMark
        var lastProgressPrint = initialLastProgressPrint
        let composeOps = outWidth * outHeight
        let composePrepassOpsTarget = input.totalPixels

        if config.autoExposureEnabled {
            let lumHistBytes = Int(linearLumBins) * MemoryLayout<UInt32>.stride
            guard let lumHistBuf = device.makeBuffer(length: lumHistBytes, options: .storageModeShared) else {
                fail("failed to allocate linear32 luminance histogram buffer")
            }
            var solveParams = ComposeSolveParams(
                cloudQuantileLow: 0.08,
                cloudQuantileHigh: 0.92,
                lumQuantile: 0.995,
                targetWhite: {
                    var v = composeTargetWhite(composeLookID)
                    if config.diskVolumeEnabled && config.diskPhysicsModeID != 3 { v *= 2.2 }
                    return v
                }(),
                pFloor: (config.diskPhysicsModeID == 3) ? 1e-30 : 1e-12,
                _pad0: 0,
                _pad1: 0,
                _pad2: 0
            )
            guard let solveParamBuf = device.makeBuffer(bytes: &solveParams, length: MemoryLayout<ComposeSolveParams>.stride, options: []) else {
                fail("failed to allocate linear32 exposure solve param buffer")
            }
            guard let solveResultBuf = device.makeBuffer(length: MemoryLayout<ComposeSolveResult>.stride, options: .storageModeShared) else {
                fail("failed to allocate linear32 exposure solve result buffer")
            }
            memset(lumHistBuf.contents(), 0, lumHistBytes)
            memset(solveResultBuf.contents(), 0, MemoryLayout<ComposeSolveResult>.stride)

            let prepassReadHandle = try FileHandle(forReadingFrom: linearURL)
            defer { try? prepassReadHandle.close() }
            var pty = 0
            var prepassTileIndex = 0
            var prepassPixels = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                let rowBytes = tileW * linearStride
                for row in 0..<tileH {
                    let offset = ((pty + row) * width) * linearStride
                    try prepassReadHandle.seek(toOffset: UInt64(offset))
                    let rowData = try prepassReadHandle.read(upToCount: rowBytes) ?? Data()
                    if rowData.count != rowBytes {
                        throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while computing linear32 exposure"])
                    }
                    _ = rowData.withUnsafeBytes { raw in
                        memcpy(linearTileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                    }
                }

                composeParamsTemplate.tileWidth = UInt32(tileW)
                composeParamsTemplate.tileHeight = UInt32(tileH)
                composeParamsTemplate.outTileWidth = UInt32(tileW / downsampleArg)
                composeParamsTemplate.outTileHeight = UInt32(tileH / downsampleArg)
                composeParamsTemplate.srcOffsetX = 0
                composeParamsTemplate.srcOffsetY = UInt32(pty)
                composeParamsTemplate.outOffsetX = 0
                composeParamsTemplate.outOffsetY = UInt32((height - pty - tileH) / downsampleArg)
                composeParamsTemplate.exposure = resolvedComposeExposure
                updateBuffer(composeParamBuf, with: &composeParamsTemplate)

                let lumCmd = queue.makeCommandBuffer()!
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(lumHistLinearTileCloudPipeline)
                lumEnc.setBuffer(composeParamBuf, offset: 0, index: 0)
                lumEnc.setBuffer(linearTileInBuf, offset: 0, index: 1)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: lumTg)
                lumEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()

                prepassPixels += tileCount
                prepassTileIndex += 1
                let doneAll = input.totalPixels + prepassPixels
                let now = Date().timeIntervalSince1970
                if prepassPixels >= input.totalPixels || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    emitETAProgress(min(doneAll, input.totalOps), input.totalOps, "gpu_prepass", "task=hdr32_luma_hist_file tile=\(prepassTileIndex)/\(composeTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll { nextProgressMark += input.progressStep }
                }
                pty += tileH
            }

            updateBuffer(composeParamBuf, with: &composeParamsTemplate)
            let solveCmd = queue.makeCommandBuffer()!
            let solveEnc = solveCmd.makeComputeCommandEncoder()!
            solveEnc.setComputePipelineState(solveExposurePipeline)
            solveEnc.setBuffer(solveParamBuf, offset: 0, index: 0)
            solveEnc.setBuffer(lumHistBuf, offset: 0, index: 1)
            solveEnc.setBuffer(composeParamBuf, offset: 0, index: 2)
            solveEnc.setBuffer(solveResultBuf, offset: 0, index: 3)
            solveEnc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            solveEnc.endEncoding()
            solveCmd.commit()
            solveCmd.waitUntilCompleted()

            let solveResult = solveResultBuf.contents().bindMemory(to: ComposeSolveResult.self, capacity: 1).pointee
            resolvedComposeExposure = solveResult.exposure
            composeParamsTemplate.exposure = resolvedComposeExposure
            print("lum(hist) p50=\(solveResult.p50), p99.5=\(solveResult.p995), mode=hdr32-file")
        }

        print("exposure=\(resolvedComposeExposure) (auto=\(config.autoExposureEnabled), mode=hdr32-file)")

        let readHandle = try FileHandle(forReadingFrom: linearURL)
        defer { try? readHandle.close() }

        while cty < height {
            let tileH = min(composeRows, height - cty)
            let tileW = width
            let rowBytes = tileW * linearStride
            for row in 0..<tileH {
                let offset = ((cty + row) * width) * linearStride
                try readHandle.seek(toOffset: UInt64(offset))
                let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
                if rowData.count != rowBytes {
                    throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while composing from linear32"])
                }
                _ = rowData.withUnsafeBytes { raw in
                    memcpy(linearTileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                }
            }

            let outTileW = tileW / downsampleArg
            let outTileH = tileH / downsampleArg
            let outTileCount = outTileW * outTileH
            let outOffsetY = (height - cty - tileH) / downsampleArg
            composeParamsTemplate.tileWidth = UInt32(tileW)
            composeParamsTemplate.tileHeight = UInt32(tileH)
            composeParamsTemplate.outTileWidth = UInt32(outTileW)
            composeParamsTemplate.outTileHeight = UInt32(outTileH)
            composeParamsTemplate.srcOffsetX = 0
            composeParamsTemplate.srcOffsetY = UInt32(cty)
            composeParamsTemplate.outOffsetX = 0
            composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
            updateBuffer(composeParamBuf, with: &composeParamsTemplate)

            let cmd = queue.makeCommandBuffer()!
            let enc = cmd.makeComputeCommandEncoder()!
            enc.setComputePipelineState(composeBHLinearTilePipeline)
            enc.setBuffer(composeParamBuf, offset: 0, index: 0)
            enc.setBuffer(linearTileInBuf, offset: 0, index: 1)
            enc.setBuffer(outBuf, offset: 0, index: 2)
            enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()

            let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
            for row in 0..<outTileH {
                var dst = ((outOffsetY + row) * outWidth) * 3
                let srcBase = row * outTileW * 4
                for col in 0..<outTileW {
                    let s = srcBase + col * 4
                    rgb[dst + 0] = outPtr[s + 0]
                    rgb[dst + 1] = outPtr[s + 1]
                    rgb[dst + 2] = outPtr[s + 2]
                    dst += 3
                }
            }

            composed += outTileCount
            composeTileIndex += 1
            let doneAll = input.totalPixels + composePrepassOpsTarget + composed
            let now = Date().timeIntervalSince1970
            if composed >= composeOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                emitETAProgress(min(doneAll, input.totalOps), input.totalOps, "swift_compose", "task=hdr32_compose tile=\(composeTileIndex)/\(composeTileTotal)")
                lastProgressPrint = now
                while nextProgressMark <= doneAll { nextProgressMark += input.progressStep }
            }
            cty += tileH
        }

        try RenderOutputs.writeImage(path: config.imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
        print("Saved image at: \(config.imageOutPath)")

        return RenderComposeHDRIntermediatePhaseResult(
            composeExposure: resolvedComposeExposure,
            nextProgressMark: nextProgressMark,
            lastProgressPrint: lastProgressPrint
        )
    }
}
