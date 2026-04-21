import Foundation
import Metal

struct RenderComposeFullGPUPhaseResult {
    let composeExposure: Float
    let nextProgressMark: Int
    let lastProgressPrint: TimeInterval
}

enum RenderComposeFullGPUPhase {
    static func execute(
        _ input: RenderComposePhaseInput,
        composeExposure initialComposeExposure: Float,
        nextProgressMark initialNextProgressMark: Int,
        lastProgressPrint initialLastProgressPrint: TimeInterval
    ) throws -> RenderComposeFullGPUPhaseResult {
        let config = input.config
        let params = input.params
        let runtime = input.runtime
        let policy = input.policy
        let frameResources = input.frameResources
        let device = runtime.device
        let queue = runtime.queue

        let width = config.width
        let height = config.height
        let downsampleArg = config.downsampleArg
        let composeChunkArg = config.composeChunkArg
        let autoExposureEnabled = config.autoExposureEnabled
        let composeLookID = config.composeLookID
        let composeDitherArg = config.composeDitherArg
        let composeInnerEdgeArg = config.composeInnerEdgeArg
        let composeSpectralStepArg = config.composeSpectralStepArg
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
        let diskVolumeEnabled = config.diskVolumeEnabled
        let diskPhysicsModeID = config.diskPhysicsModeID
        let composeLumLogMin: Float = (diskPhysicsModeID == 3) ? -36.0 : 8.0
        let composeLumLogMax: Float = (diskPhysicsModeID == 3) ? 4.0 : 20.0
        let outWidth = policy.outWidth
        let outHeight = policy.outHeight
        let count = policy.count
        let stride = policy.stride
        let outSize = policy.outSize
        let fullComposeOutBytes = policy.fullComposeOutBytes
        let approxTextureBytes = policy.approxTextureBytes

        let composePipeline = runtime.composePipeline
        let composeLinearPipeline = runtime.composeLinearPipeline
        let composeLinearLitePipeline = runtime.composeLinearLitePipeline
        let composeLinearTilePipeline = runtime.composeLinearTilePipeline
        let composeLinearTileLitePipeline = runtime.composeLinearTileLitePipeline
        let composeBHLinearPipeline = runtime.composeBHLinearPipeline
        let composeBHLinearTilePipeline = runtime.composeBHLinearTilePipeline
        let cloudHistPipeline = runtime.cloudHistPipeline
        let cloudHistLitePipeline = runtime.cloudHistLitePipeline
        let cloudHistLinearPipeline = runtime.cloudHistLinearPipeline
        let lumHistPipeline = runtime.lumHistPipeline
        let lumHistLinearPipeline = runtime.lumHistLinearPipeline
        let lumHistLinearTileCloudPipeline = runtime.lumHistLinearTileCloudPipeline
        let solveCloudStatsPipeline = runtime.solveCloudStatsPipeline
        let solveExposurePipeline = runtime.solveExposurePipeline

        let activeComposeLinearPipeline = input.collisionLite32Enabled ? composeLinearLitePipeline : composeLinearPipeline
        let activeComposeLinearTilePipeline = input.collisionLite32Enabled ? composeLinearTileLitePipeline : composeLinearTilePipeline
        let activeCloudHistPipeline = input.collisionLite32Enabled ? cloudHistLitePipeline : cloudHistPipeline

        var composeExposure = initialComposeExposure
        var nextProgressMark = initialNextProgressMark
        var lastProgressPrint = initialLastProgressPrint

        let tg = RenderThreadgroups.twoDimensional(composePipeline)
        let tgLinearTile1D = RenderThreadgroups.oneDimensional(activeComposeLinearTilePipeline)
        let composePrepassOpsTarget = autoExposureEnabled ? (2 * count) : 0

        let collisionBufferForCompose = frameResources.collisionBuffer
        if !input.directLinearEnabled && collisionBufferForCompose == nil {
            fail("gpu-full-compose requires in-memory collision buffer")
        }

        let cloudBins = 8192
        let lumBins = 4096
        let lumLogMin: Float = composeLumLogMin
        let lumLogMax: Float = composeLumLogMax
        let cloudHistBytes = cloudBins * MemoryLayout<UInt32>.stride
        let lumHistBytes = lumBins * MemoryLayout<UInt32>.stride
        let tgCloud1D = RenderThreadgroups.oneDimensional(activeCloudHistPipeline)
        let tgLinear1D = RenderThreadgroups.oneDimensional(activeComposeLinearPipeline)
        let tgLum1D = RenderThreadgroups.oneDimensional(lumHistPipeline)
        let tgLumTile1D = RenderThreadgroups.oneDimensional(lumHistLinearTileCloudPipeline)
        var globalCloudQ10: Float = 0.0
        var globalCloudQ90: Float = 1.0
        var globalCloudInvSpan: Float = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
        var composeParamsBase = params
        let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])!

        var composeParamsTemplate = ComposeParams(
            tileWidth: UInt32(width),
            tileHeight: UInt32(height),
            downsample: UInt32(downsampleArg),
            outTileWidth: UInt32(outWidth),
            outTileHeight: UInt32(outHeight),
            srcOffsetX: 0,
            srcOffsetY: 0,
            outOffsetX: 0,
            outOffsetY: 0,
            fullInputWidth: UInt32(width),
            fullInputHeight: UInt32(height),
            exposure: composeExposure,
            dither: composeDitherArg,
            innerEdgeMult: composeInnerEdgeArg,
            spectralStep: composeSpectralStepArg,
            cloudQ10: globalCloudQ10,
            cloudInvSpan: globalCloudInvSpan,
            look: composeLookID,
            spectralEncoding: spectralEncodingID,
            precisionMode: composePrecisionID,
            analysisMode: composeAnalysisMode,
            cloudBins: UInt32(cloudBins),
            lumBins: UInt32(lumBins),
            lumLogMin: lumLogMin,
            lumLogMax: lumLogMax,
            cameraModel: composeCameraModelID,
            cameraPsfSigmaPx: composeCameraPsfSigmaArg,
            cameraReadNoise: composeCameraReadNoiseArg,
            cameraShotNoise: composeCameraShotNoiseArg,
            cameraFlareStrength: composeCameraFlareStrengthArg,
            backgroundMode: backgroundModeID,
            backgroundStarDensity: backgroundStarDensityArg,
            backgroundStarStrength: backgroundStarStrengthArg,
            backgroundNebulaStrength: backgroundNebulaStrengthArg,
            preserveHighlightColor: preserveHighlightColor,
            diskNoiseModel: params.diskNoiseModel,
            _pad0: 0,
            _pad1: 0,
            _pad2: 0
        )

        guard let composeParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
            fail("failed to allocate compose param buffer")
        }
        updateBuffer(composeParamBuf, with: &composeParamsTemplate)

        var solveParams = ComposeSolveParams(
            cloudQuantileLow: 0.08,
            cloudQuantileHigh: 0.92,
            lumQuantile: 0.995,
            targetWhite: {
                var v = composeTargetWhite(composeLookID)
                if diskVolumeEnabled && diskPhysicsModeID != 3 { v *= 2.2 }
                return v
            }(),
            pFloor: (diskPhysicsModeID == 3) ? 1e-30 : 1e-12,
            _pad0: 0,
            _pad1: 0,
            _pad2: 0
        )
        guard let solveParamBuf = device.makeBuffer(bytes: &solveParams, length: MemoryLayout<ComposeSolveParams>.stride, options: []) else {
            fail("failed to allocate compose solve param buffer")
        }
        guard let solveResultBuf = device.makeBuffer(length: MemoryLayout<ComposeSolveResult>.stride, options: .storageModeShared) else {
            fail("failed to allocate compose solve result buffer")
        }
        memset(solveResultBuf.contents(), 0, MemoryLayout<ComposeSolveResult>.stride)

        let rawComposeRows = max(1, composeChunkArg / max(width, 1))
        var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
        if composeRows <= 0 { composeRows = downsampleArg }
        if composeRows > height { composeRows = height }
        let maxComposeOutTileCount = (width / downsampleArg) * (composeRows / downsampleArg)
        let maxComposeLinearTileCount = width * composeRows

        let fullLinearBytes = count * MemoryLayout<SIMD4<Float>>.stride
        let tiledLinearBytes = maxComposeLinearTileCount * MemoryLayout<SIMD4<Float>>.stride
        let collisionWorkingSetBytes = input.directLinearEnabled ? 0 : (input.collisionLite32Enabled ? frameResources.collisionStorageSize : outSize)
        let estimatedWorkingSet = collisionWorkingSetBytes + frameResources.slotBytes * frameResources.maxInFlight + approxTextureBytes + cloudHistBytes + lumHistBytes + fullComposeOutBytes
        let tileFirstCompose = (policy.composeStrategyPreference == .tileFirst) && !input.directLinearEnabled
        let preferFullLinear = !tileFirstCompose &&
            (input.directLinearEnabled || (autoExposureEnabled || input.collisionLite32Enabled))
            && (policy.workingSetCap <= 0 || (estimatedWorkingSet + fullLinearBytes) <= Int(Double(policy.workingSetCap) * 0.92))
        let preferSingleReadback = !tileFirstCompose &&
            (policy.workingSetCap <= 0 || estimatedWorkingSet <= Int(Double(policy.workingSetCap) * 0.92))
        let fullComposeOutBuf: MTLBuffer? = (preferSingleReadback && (!input.collisionLite32Enabled || preferFullLinear))
            ? device.makeBuffer(length: fullComposeOutBytes, options: .storageModeShared)
            : nil
        let composeLinearFullBuf: MTLBuffer? = input.directLinearEnabled
            ? frameResources.directLinearTraceBuf
            : (preferFullLinear ? device.makeBuffer(length: fullLinearBytes, options: .storageModePrivate) : nil)
        let preferTiledLinear = autoExposureEnabled && composeLinearFullBuf == nil
        let composeLinearTileBuf: MTLBuffer? = preferTiledLinear
            ? device.makeBuffer(length: tiledLinearBytes, options: .storageModePrivate)
            : nil
        if tileFirstCompose {
            print("info: gpu-full-compose using tiled compose path because this render mode prefers tile-based HDR compose")
        } else if !preferSingleReadback {
            print("info: gpu-full-compose using tiled compose fallback to stay within GPU working-set budget")
        } else if input.collisionLite32Enabled && !preferFullLinear {
            print("info: gpu-full-compose using tiled compose fallback because lite collision path requires a GPU HDR intermediate")
        } else if fullComposeOutBuf == nil {
            print("info: gpu-full-compose falling back to tiled compose because full-frame output buffer allocation failed (\(fullComposeOutBytes) bytes)")
        }
        if autoExposureEnabled && preferFullLinear && composeLinearFullBuf == nil {
            print("info: gpu-full-compose full-frame HDR intermediate allocation failed (\(fullLinearBytes) bytes); trying tiled GPU HDR intermediate")
        }
        if preferTiledLinear && composeLinearTileBuf == nil {
            print("info: gpu-full-compose falling back to direct luminance histogram because tiled HDR intermediate allocation failed (\(tiledLinearBytes) bytes)")
        }
        if input.collisionLite32Enabled && composeLinearFullBuf == nil && composeLinearTileBuf == nil {
            fail("lite32 gpu-full-compose requires a GPU HDR intermediate buffer")
        }

        let composePathSummary: String = {
            let readback = (fullComposeOutBuf != nil) ? "single-readback" : "tiled-readback"
            let source: String
            if input.directLinearEnabled {
                source = "source=hdr32-direct"
            } else if composeLinearFullBuf != nil {
                source = input.collisionLite32Enabled ? "source=lite32->hdr32 full-frame" : "source=collision->hdr32 full-frame"
            } else if composeLinearTileBuf != nil {
                source = input.collisionLite32Enabled ? "source=lite32->hdr32 tiled" : "source=collision->hdr32 tiled"
            } else {
                source = "source=collision direct-luma"
            }
            return "gpu-full-compose \(readback), \(source)"
        }()
        print("compose path=\(composePathSummary)")

        if autoExposureEnabled {
            guard let cloudHistBuf = device.makeBuffer(length: cloudHistBytes, options: .storageModeShared) else {
                fail("failed to allocate cloud histogram buffer")
            }
            guard let lumHistBuf = device.makeBuffer(length: lumHistBytes, options: .storageModeShared) else {
                fail("failed to allocate luminance histogram buffer")
            }

            memset(cloudHistBuf.contents(), 0, cloudHistBytes)
            let cloudCmd = queue.makeCommandBuffer()!
            let cloudEnc = cloudCmd.makeComputeCommandEncoder()!
            if input.directLinearEnabled {
                guard let composeLinearFullBuf else {
                    fail("direct linear gpu-full-compose missing full linear buffer")
                }
                cloudEnc.setComputePipelineState(cloudHistLinearPipeline)
                cloudEnc.setBuffer(composeParamBuf, offset: 0, index: 0)
                cloudEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                cloudEnc.setBuffer(cloudHistBuf, offset: 0, index: 2)
            } else {
                guard let collisionBufferForCompose else {
                    fail("gpu-full-compose cloud histogram missing collision buffer")
                }
                cloudEnc.setComputePipelineState(activeCloudHistPipeline)
                cloudEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                cloudEnc.setBuffer(composeParamBuf, offset: 0, index: 1)
                cloudEnc.setBuffer(collisionBufferForCompose, offset: 0, index: 2)
                cloudEnc.setBuffer(cloudHistBuf, offset: 0, index: 3)
            }
            cloudEnc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: tgCloud1D)
            cloudEnc.endEncoding()
            let cloudSolveEnc = cloudCmd.makeComputeCommandEncoder()!
            cloudSolveEnc.setComputePipelineState(solveCloudStatsPipeline)
            cloudSolveEnc.setBuffer(solveParamBuf, offset: 0, index: 0)
            cloudSolveEnc.setBuffer(cloudHistBuf, offset: 0, index: 1)
            cloudSolveEnc.setBuffer(composeParamBuf, offset: 0, index: 2)
            cloudSolveEnc.setBuffer(solveResultBuf, offset: 0, index: 3)
            cloudSolveEnc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
            cloudSolveEnc.endEncoding()
            cloudCmd.commit()
            cloudCmd.waitUntilCompleted()

            let cloudResult = solveResultBuf.contents().bindMemory(to: ComposeSolveResult.self, capacity: 1).pointee
            globalCloudQ10 = cloudResult.cloudQ10
            globalCloudQ90 = cloudResult.cloudQ90
            globalCloudInvSpan = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
            let cloudDone = input.totalPixels + count
            let cloudNow = Date().timeIntervalSince1970
            if cloudDone >= nextProgressMark || (cloudNow - lastProgressPrint) >= 0.5 {
                emitETAProgress(min(cloudDone, input.totalOps), input.totalOps, "gpu_prepass", "task=cloud_hist_full_frame")
                lastProgressPrint = cloudNow
                while nextProgressMark <= cloudDone { nextProgressMark += input.progressStep }
            }

            memset(lumHistBuf.contents(), 0, lumHistBytes)
            if let composeLinearFullBuf {
                let lumCmd = queue.makeCommandBuffer()!
                if !input.directLinearEnabled {
                    guard let collisionBufferForCompose else {
                        fail("gpu-full-compose linear prepass missing collision buffer")
                    }
                    let linearEnc = lumCmd.makeComputeCommandEncoder()!
                    linearEnc.setComputePipelineState(activeComposeLinearPipeline)
                    linearEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    linearEnc.setBuffer(composeParamBuf, offset: 0, index: 1)
                    linearEnc.setBuffer(collisionBufferForCompose, offset: 0, index: 2)
                    linearEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 3)
                    linearEnc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: tgLinear1D)
                    linearEnc.endEncoding()
                }
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(lumHistLinearPipeline)
                lumEnc.setBuffer(composeParamBuf, offset: 0, index: 0)
                lumEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                lumEnc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: tgLum1D)
                lumEnc.endEncoding()
                let lumSolveEnc = lumCmd.makeComputeCommandEncoder()!
                lumSolveEnc.setComputePipelineState(solveExposurePipeline)
                lumSolveEnc.setBuffer(solveParamBuf, offset: 0, index: 0)
                lumSolveEnc.setBuffer(lumHistBuf, offset: 0, index: 1)
                lumSolveEnc.setBuffer(composeParamBuf, offset: 0, index: 2)
                lumSolveEnc.setBuffer(solveResultBuf, offset: 0, index: 3)
                lumSolveEnc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                lumSolveEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()
            } else if let composeLinearTileBuf {
                guard let lumTileParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                    fail("failed to allocate tiled luminance prepass param buffer")
                }
                var pty = 0
                var prepassTileIndex = 0
                var prepassPixels = 0
                let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
                while pty < height {
                    let tileH = min(composeRows, height - pty)
                    let tileW = width
                    let tileCount = tileW * tileH
                    let srcOffsetBytes = pty * width * stride
                    composeParamsTemplate.tileWidth = UInt32(tileW)
                    composeParamsTemplate.tileHeight = UInt32(tileH)
                    composeParamsTemplate.srcOffsetX = 0
                    composeParamsTemplate.srcOffsetY = UInt32(pty)
                    composeParamsTemplate.outTileWidth = UInt32(tileW / downsampleArg)
                    composeParamsTemplate.outTileHeight = UInt32(tileH / downsampleArg)
                    composeParamsTemplate.outOffsetX = 0
                    composeParamsTemplate.outOffsetY = UInt32((height - pty - tileH) / downsampleArg)
                    composeParamsTemplate.cloudQ10 = globalCloudQ10
                    composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
                    updateBuffer(lumTileParamBuf, with: &composeParamsTemplate)

                    let tileCmd = queue.makeCommandBuffer()!
                    let linearEnc = tileCmd.makeComputeCommandEncoder()!
                    linearEnc.setComputePipelineState(activeComposeLinearTilePipeline)
                    linearEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    linearEnc.setBuffer(lumTileParamBuf, offset: 0, index: 1)
                    linearEnc.setBuffer(frameResources.collisionBuffer, offset: srcOffsetBytes, index: 2)
                    linearEnc.setBuffer(composeLinearTileBuf, offset: 0, index: 3)
                    linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinearTile1D)
                    linearEnc.endEncoding()

                    let lumEnc = tileCmd.makeComputeCommandEncoder()!
                    lumEnc.setComputePipelineState(lumHistLinearTileCloudPipeline)
                    lumEnc.setBuffer(lumTileParamBuf, offset: 0, index: 0)
                    lumEnc.setBuffer(composeLinearTileBuf, offset: 0, index: 1)
                    lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                    lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLumTile1D)
                    lumEnc.endEncoding()
                    tileCmd.commit()
                    tileCmd.waitUntilCompleted()

                    prepassPixels += tileCount
                    prepassTileIndex += 1
                    let doneAll = input.totalPixels + count + prepassPixels
                    let now = Date().timeIntervalSince1970
                    if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(min(doneAll, input.totalOps), input.totalOps, "gpu_prepass", "task=hdr32_luma_hist tile=\(prepassTileIndex)/\(composeTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= doneAll { nextProgressMark += input.progressStep }
                    }
                    pty += tileH
                }
                let lumSolveCmd = queue.makeCommandBuffer()!
                let lumSolveEnc = lumSolveCmd.makeComputeCommandEncoder()!
                lumSolveEnc.setComputePipelineState(solveExposurePipeline)
                lumSolveEnc.setBuffer(solveParamBuf, offset: 0, index: 0)
                lumSolveEnc.setBuffer(lumHistBuf, offset: 0, index: 1)
                lumSolveEnc.setBuffer(composeParamBuf, offset: 0, index: 2)
                lumSolveEnc.setBuffer(solveResultBuf, offset: 0, index: 3)
                lumSolveEnc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                lumSolveEnc.endEncoding()
                lumSolveCmd.commit()
                lumSolveCmd.waitUntilCompleted()
            } else {
                let lumCmd = queue.makeCommandBuffer()!
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(lumHistPipeline)
                lumEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                lumEnc.setBuffer(composeParamBuf, offset: 0, index: 1)
                lumEnc.setBuffer(frameResources.collisionBuffer, offset: 0, index: 2)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 3)
                lumEnc.dispatchThreads(MTLSize(width: count, height: 1, depth: 1), threadsPerThreadgroup: tgLum1D)
                lumEnc.endEncoding()
                let lumSolveEnc = lumCmd.makeComputeCommandEncoder()!
                lumSolveEnc.setComputePipelineState(solveExposurePipeline)
                lumSolveEnc.setBuffer(solveParamBuf, offset: 0, index: 0)
                lumSolveEnc.setBuffer(lumHistBuf, offset: 0, index: 1)
                lumSolveEnc.setBuffer(composeParamBuf, offset: 0, index: 2)
                lumSolveEnc.setBuffer(solveResultBuf, offset: 0, index: 3)
                lumSolveEnc.dispatchThreads(MTLSize(width: 1, height: 1, depth: 1), threadsPerThreadgroup: MTLSize(width: 1, height: 1, depth: 1))
                lumSolveEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()
            }

            let lumResult = solveResultBuf.contents().bindMemory(to: ComposeSolveResult.self, capacity: 1).pointee
            composeExposure = lumResult.exposure
            print("lum(hist) p50=\(lumResult.p50), p99.5=\(lumResult.p995), samples=\(lumResult.lumSamples)")
            let lumDone = input.totalPixels + composePrepassOpsTarget
            let lumNow = Date().timeIntervalSince1970
            if lumDone >= nextProgressMark || (lumNow - lastProgressPrint) >= 0.5 {
                emitETAProgress(min(lumDone, input.totalOps), input.totalOps, "gpu_prepass", "task=luma_hist_full_frame")
                lastProgressPrint = lumNow
                while nextProgressMark <= lumDone { nextProgressMark += input.progressStep }
            }
        }

        let solvedComposeParams = composeParamBuf.contents().bindMemory(to: ComposeParams.self, capacity: 1).pointee
        globalCloudQ10 = solvedComposeParams.cloudQ10
        globalCloudInvSpan = solvedComposeParams.cloudInvSpan
        globalCloudQ90 = globalCloudQ10 + (globalCloudInvSpan > 0 ? (1.0 / globalCloudInvSpan) : 1.0)
        composeExposure = solvedComposeParams.exposure
        composeParamsTemplate = solvedComposeParams
        print("compose cloud normalization q10=\(globalCloudQ10) q90=\(globalCloudQ90)")
        print("exposure=\(composeExposure) (auto=\(autoExposureEnabled), mode=gpu-full-compose)")

        var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        let composePixelOps = outWidth * outHeight

        if let fullComposeOutBuf {
            let composeCmd = queue.makeCommandBuffer()!
            let composeEnc = composeCmd.makeComputeCommandEncoder()!
            if let composeLinearFullBuf {
                composeEnc.setComputePipelineState(composeBHLinearPipeline)
                composeEnc.setBuffer(composeParamBuf, offset: 0, index: 0)
                composeEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                composeEnc.setBuffer(fullComposeOutBuf, offset: 0, index: 2)
            } else {
                composeEnc.setComputePipelineState(composePipeline)
                composeEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                composeEnc.setBuffer(composeParamBuf, offset: 0, index: 1)
                composeEnc.setBuffer(collisionBufferForCompose, offset: 0, index: 2)
                composeEnc.setBuffer(fullComposeOutBuf, offset: 0, index: 3)
            }
            composeEnc.dispatchThreads(MTLSize(width: outWidth, height: outHeight, depth: 1), threadsPerThreadgroup: tg)
            composeEnc.endEncoding()
            composeCmd.commit()
            composeCmd.waitUntilCompleted()
            let outPtr = fullComposeOutBuf.contents().bindMemory(to: UInt8.self, capacity: outWidth * outHeight * 4)
            var src = 0
            var dst = 0
            while dst < rgb.count {
                rgb[dst + 0] = outPtr[src + 0]
                rgb[dst + 1] = outPtr[src + 1]
                rgb[dst + 2] = outPtr[src + 2]
                src += 4
                dst += 3
            }
            emitETAProgress(input.totalOps, input.totalOps, "gpu_compose", "task=compose_full_frame")
        } else {
            guard let composeTileParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                fail("failed to allocate tiled compose param buffer")
            }
            guard let composeTileOutBuf = device.makeBuffer(length: maxComposeOutTileCount * 4, options: .storageModeShared) else {
                fail("failed to allocate tiled compose output buffer")
            }
            let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
            var composed = 0
            var cty = 0
            var composeTileIndex = 0
            while cty < height {
                let tileH = min(composeRows, height - cty)
                let tileW = width
                let srcOffsetBytes = cty * width * stride
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
                composeParamsTemplate.cloudQ10 = globalCloudQ10
                composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
                composeParamsTemplate.exposure = composeExposure
                updateBuffer(composeTileParamBuf, with: &composeParamsTemplate)

                let composeCmd = queue.makeCommandBuffer()!
                let composeEnc: MTLComputeCommandEncoder
                if let composeLinearFullBuf {
                    composeEnc = composeCmd.makeComputeCommandEncoder()!
                    composeEnc.setComputePipelineState(composeBHLinearPipeline)
                    composeEnc.setBuffer(composeTileParamBuf, offset: 0, index: 0)
                    composeEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                    composeEnc.setBuffer(composeTileOutBuf, offset: 0, index: 2)
                } else if let composeLinearTileBuf {
                    let tileCount = tileW * tileH
                    let linearEnc = composeCmd.makeComputeCommandEncoder()!
                    linearEnc.setComputePipelineState(activeComposeLinearTilePipeline)
                    linearEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    linearEnc.setBuffer(composeTileParamBuf, offset: 0, index: 1)
                    linearEnc.setBuffer(frameResources.collisionBuffer, offset: srcOffsetBytes, index: 2)
                    linearEnc.setBuffer(composeLinearTileBuf, offset: 0, index: 3)
                    linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinearTile1D)
                    linearEnc.endEncoding()

                    composeEnc = composeCmd.makeComputeCommandEncoder()!
                    composeEnc.setComputePipelineState(composeBHLinearTilePipeline)
                    composeEnc.setBuffer(composeTileParamBuf, offset: 0, index: 0)
                    composeEnc.setBuffer(composeLinearTileBuf, offset: 0, index: 1)
                    composeEnc.setBuffer(composeTileOutBuf, offset: 0, index: 2)
                } else {
                    composeEnc = composeCmd.makeComputeCommandEncoder()!
                    composeEnc.setComputePipelineState(composePipeline)
                    composeEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    composeEnc.setBuffer(composeTileParamBuf, offset: 0, index: 1)
                    composeEnc.setBuffer(frameResources.collisionBuffer, offset: srcOffsetBytes, index: 2)
                    composeEnc.setBuffer(composeTileOutBuf, offset: 0, index: 3)
                }
                composeEnc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
                composeEnc.endEncoding()
                composeCmd.commit()
                composeCmd.waitUntilCompleted()

                let outPtr = composeTileOutBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
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
                if composed >= composePixelOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                    emitETAProgress(min(doneAll, input.totalOps), input.totalOps, "gpu_compose", "task=compose_gpu_tile tile=\(composeTileIndex)/\(composeTileTotal)")
                    lastProgressPrint = now
                    while nextProgressMark <= doneAll { nextProgressMark += input.progressStep }
                }
                cty += tileH
            }
        }

        try RenderOutputs.writeImage(path: config.imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
        print("Saved image at: \(config.imageOutPath)")

        return RenderComposeFullGPUPhaseResult(
            composeExposure: composeExposure,
            nextProgressMark: nextProgressMark,
            lastProgressPrint: lastProgressPrint
        )
    }
}
