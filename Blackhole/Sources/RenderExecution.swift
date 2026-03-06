import Foundation
import Metal

enum RenderExecution {
    static func execute(config: ResolvedRenderConfig, params inputParams: PackedParams, runtime: RenderRuntime) throws {
        let device = runtime.device
        let queue = runtime.queue
        var params = inputParams
        let width = config.width
        let height = config.height
        let preset = config.preset
        let outPath = config.outPath
        let linear32OutPath = config.linear32OutPath
        let imageOutPath = config.imageOutPath
        let composeGPU = config.composeGPU
        let gpuFullCompose = config.gpuFullCompose
        let discardCollisionOutput = config.discardCollisionOutput
        let useLinear32Intermediate = config.useLinear32Intermediate
        let downsampleArg = config.downsampleArg
        let metricName = config.metricName
        let metricArg = config.metricArg
        let spectralEncoding = config.spectralEncoding
        let spectralEncodingID = config.spectralEncodingID
        let diskPhysicsModeID = config.diskPhysicsModeID
        let diskPhysicsModeArg = config.diskPhysicsModeArg
        let diskModelResolved = config.diskModelResolved
        let diskMdotEddArg = config.diskMdotEddArg
        let diskRadiativeEfficiencyArg = config.diskRadiativeEfficiencyArg
        let diskPlungeFloorArg = config.diskPlungeFloorArg
        let diskThickScaleArg = config.diskThickScaleArg
        let diskColorFactorArg = config.diskColorFactorArg
        let diskReturningRadArg = config.diskReturningRadArg
        let diskPrecisionTextureArg = config.diskPrecisionTextureArg
        let diskPrecisionCloudsEnabled = config.diskPrecisionCloudsEnabled
        let diskCloudCoverageArg = config.diskCloudCoverageArg
        let diskCloudOpticalDepthArg = config.diskCloudOpticalDepthArg
        let diskCloudPorosityArg = config.diskCloudPorosityArg
        let diskCloudShadowStrengthArg = config.diskCloudShadowStrengthArg
        let diskReturnBouncesArg = config.diskReturnBouncesArg
        let diskRTStepsArg = config.diskRTStepsArg
        let diskScatteringAlbedoArg = config.diskScatteringAlbedoArg
        let diskAtlasEnabled = config.diskAtlasEnabled
        let diskAtlasPathArg = config.diskAtlasPathArg
        let diskAtlasWidth = config.diskAtlasWidth
        let diskAtlasHeight = config.diskAtlasHeight
        let diskAtlasTempScaleArg = config.diskAtlasTempScaleArg
        let diskAtlasDensityBlendArg = config.diskAtlasDensityBlendArg
        let diskAtlasVrScaleArg = config.diskAtlasVrScaleArg
        let diskAtlasVphiScaleArg = config.diskAtlasVphiScaleArg
        let diskAtlasRMin = config.diskAtlasRMin
        let diskAtlasRMax = config.diskAtlasRMax
        let diskAtlasRWarp = config.diskAtlasRWarp
        let diskAtlasData = config.diskAtlasData
        let diskVolumeEnabled = config.diskVolumeEnabled
        let diskVolumeLegacyEnabled = config.diskVolumeLegacyEnabled
        let diskVolumeFormatArg = config.diskVolumeFormatArg
        let diskVolumeR = config.diskVolumeR
        let diskVolumePhi = config.diskVolumePhi
        let diskVolumeZ = config.diskVolumeZ
        let diskVolumeRMin = config.diskVolumeRMin
        let diskVolumeRMax = config.diskVolumeRMax
        let diskVolumeZMax = config.diskVolumeZMax
        let diskVolumeTauScaleArg = config.diskVolumeTauScaleArg
        let diskVolume0Data = config.diskVolume0Data
        let diskVolume1Data = config.diskVolume1Data
        let diskVolumePathArg = config.diskVolumePathArg
        let diskVol0PathResolved = config.diskVol0PathResolved
        let diskVol1PathResolved = config.diskVol1PathResolved
        let diskNuObsHzArg = config.diskNuObsHzArg
        let diskGrmhdDensityScaleArg = config.diskGrmhdDensityScaleArg
        let diskGrmhdBScaleArg = config.diskGrmhdBScaleArg
        let diskGrmhdEmissionScaleArg = config.diskGrmhdEmissionScaleArg
        let diskGrmhdAbsorptionScaleArg = config.diskGrmhdAbsorptionScaleArg
        let diskGrmhdVelScaleArg = config.diskGrmhdVelScaleArg
        let diskGrmhdDebugName = config.diskGrmhdDebugName
        let diskGrmhdDebugID = config.diskGrmhdDebugID
        let diskPolarizedRTEnabled = config.diskPolarizedRTEnabled
        let diskPolarizationFracArg = config.diskPolarizationFracArg
        let diskFaradayRotScaleArg = config.diskFaradayRotScaleArg
        let diskFaradayConvScaleArg = config.diskFaradayConvScaleArg
        let visibleModeEnabled = config.visibleModeEnabled
        let visibleSamplesArg = config.visibleSamplesArg
        let visibleTeffModelName = config.visibleTeffModelName
        let visibleTeffT0Arg = config.visibleTeffT0Arg
        let visibleTeffR0RsArg = config.visibleTeffR0RsArg
        let visibleTeffPArg = config.visibleTeffPArg
        let visibleBhMassArg = config.visibleBhMassArg
        let visibleMdotArg = config.visibleMdotArg
        let visibleRInRsArg = config.visibleRInRsArg
        let photosphereRhoThresholdResolved = config.photosphereRhoThresholdResolved
        let visiblePolicyName = config.visiblePolicyName
        let visibleEmissionModelName = config.visibleEmissionModelName
        let visibleEmissionModelID = config.visibleEmissionModelID
        let visibleSynchAlphaArg = config.visibleSynchAlphaArg
        let visibleKappaArg = config.visibleKappaArg
        let coolAbsorptionEnabled = config.coolAbsorptionEnabled
        let coolDustToGasArg = config.coolDustToGasArg
        let coolDustKappaVArg = config.coolDustKappaVArg
        let coolDustBetaArg = config.coolDustBetaArg
        let coolDustTSubArg = config.coolDustTSubArg
        let coolDustTWidthArg = config.coolDustTWidthArg
        let coolGasKappa0Arg = config.coolGasKappa0Arg
        let coolGasNuSlopeArg = config.coolGasNuSlopeArg
        let coolClumpStrengthArg = config.coolClumpStrengthArg
        let rayBundleEnabled = config.rayBundleEnabled
        let rayBundleActive = config.rayBundleActive
        let rayBundleJacobianActive = config.rayBundleJacobianActive
        let rayBundleJacobianStrengthArg = config.rayBundleJacobianStrengthArg
        let rayBundleFootprintClampArg = config.rayBundleFootprintClampArg
        let tileSize = config.tileSize
        let traceInFlightOverrideArg = config.traceInFlightOverrideArg
        let composeLook = config.composeLook
        let composeLookID = config.composeLookID
        let composeDitherArg = config.composeDitherArg
        let composeInnerEdgeArg = config.composeInnerEdgeArg
        let composeSpectralStepArg = config.composeSpectralStepArg
        let composeChunkArg = config.composeChunkArg
        let exposureSamplesArg = config.exposureSamplesArg
        let exposureModeName = config.exposureModeName
        let exposureEVArg = config.exposureEVArg
        let composePrecisionID = config.composePrecisionID
        let composeAnalysisMode = config.composeAnalysisMode
        let autoExposureEnabled = config.autoExposureEnabled
        var composeExposure = config.composeExposure
        let preserveHighlightColor = config.preserveHighlightColor
        let cameraModelName = config.cameraModelName
        let composeCameraModelID = config.composeCameraModelID
        let cameraPsfSigmaArg = config.cameraPsfSigmaArg
        let cameraReadNoiseArg = config.cameraReadNoiseArg
        let cameraShotNoiseArg = config.cameraShotNoiseArg
        let cameraFlareStrengthArg = config.cameraFlareStrengthArg
        let composeCameraPsfSigmaArg = config.composeCameraPsfSigmaArg
        let composeCameraReadNoiseArg = config.composeCameraReadNoiseArg
        let composeCameraShotNoiseArg = config.composeCameraShotNoiseArg
        let composeCameraFlareStrengthArg = config.composeCameraFlareStrengthArg
        let backgroundModeName = config.backgroundModeName
        let backgroundModeID = config.backgroundModeID
        let backgroundStarDensityArg = config.backgroundStarDensityArg
        let backgroundStarStrengthArg = config.backgroundStarStrengthArg
        let backgroundNebulaStrengthArg = config.backgroundNebulaStrengthArg
        let rsD = config.rsD
        let rcp = config.rcp
        let hArg = config.hArg
        let camXFactor = config.camXFactor
        let camYFactor = config.camYFactor
        let camZFactor = config.camZFactor
        let fovDeg = config.fovDeg
        let rollDeg = config.rollDeg
        let diskHFactor = config.diskHFactor
        let maxStepsArg = config.maxStepsArg
        let spinArg = config.spinArg
        let kerrTolArg = config.kerrTolArg
        let kerrEscapeMultArg = config.kerrEscapeMultArg
        let kerrSubstepsArg = config.kerrSubstepsArg
        let kerrRadialScaleArg = config.kerrRadialScaleArg
        let kerrAzimuthScaleArg = config.kerrAzimuthScaleArg
        let kerrImpactScaleArg = config.kerrImpactScaleArg
        let diskFlowTimeArg = config.diskFlowTimeArg
        let diskOrbitalBoostArg = config.diskOrbitalBoostArg
        let diskRadialDriftArg = config.diskRadialDriftArg
        let diskTurbulenceArg = config.diskTurbulenceArg
        let diskOrbitalBoostInnerArg = config.diskOrbitalBoostInnerArg
        let diskOrbitalBoostOuterArg = config.diskOrbitalBoostOuterArg
        let diskRadialDriftInnerArg = config.diskRadialDriftInnerArg
        let diskRadialDriftOuterArg = config.diskRadialDriftOuterArg
        let diskTurbulenceInnerArg = config.diskTurbulenceInnerArg
        let diskTurbulenceOuterArg = config.diskTurbulenceOuterArg
        let diskFlowStepArg = config.diskFlowStepArg
        let diskFlowStepsArg = config.diskFlowStepsArg
        let diskInnerRadiusCompose = config.diskInnerRadiusCompose
        let diskHorizonRadiusCompose = config.diskHorizonRadiusCompose
        let visibleTeffModelID = config.visibleTeffModelID
        let visibleTeffR0Meters = config.visibleTeffR0Meters
        let visibleRInMeters = config.visibleRInMeters

        print(config.renderConfigLine)
        if !config.grmhdConfigLine.isEmpty { print(config.grmhdConfigLine) }
        if !config.visibleConfigLine.isEmpty { print(config.visibleConfigLine) }
    let count = width * height
    let stride = MemoryLayout<CollisionInfo>.stride
    let useInMemoryCollisions = composeGPU && gpuFullCompose
    let collisionLite32Enabled =
        useLinear32Intermediate &&
        !useInMemoryCollisions &&
        !rayBundleActive &&
        diskPhysicsModeID <= 1 &&
        !visibleModeEnabled &&
        composeAnalysisMode == 0 &&
        diskGrmhdDebugID == 0
    let traceStride = collisionLite32Enabled ? MemoryLayout<CollisionLite32>.stride : stride
    let outSize = count * stride
    let url = URL(fileURLWithPath: outPath)
    let linearStride = MemoryLayout<SIMD4<Float>>.stride
    let linearOutSize = count * linearStride
    let linearURL = URL(fileURLWithPath: linear32OutPath)
    if discardCollisionOutput && !(useInMemoryCollisions || useLinear32Intermediate) {
        fail("--discard-collisions is only supported with --gpu-full-compose or --linear32-intermediate")
    }
    let collisionBuffer: MTLBuffer? = useInMemoryCollisions ? device.makeBuffer(length: outSize, options: .storageModeShared) : nil
    if useInMemoryCollisions, collisionBuffer == nil {
        fail("failed to allocate in-memory collision buffer (\(outSize) bytes)")
    }
    let collisionBase = collisionBuffer?.contents()
    if collisionLite32Enabled {
        print("collision layout=lite32 (2xfloat4) for linear32 trace tiles")
    }
    var linearOutHandle: FileHandle? = nil
    if useLinear32Intermediate {
        _ = FileManager.default.createFile(atPath: linearURL.path, contents: nil)
        linearOutHandle = try FileHandle(forWritingTo: linearURL)
    }
    var outHandle: FileHandle? = nil
    if !useInMemoryCollisions && !discardCollisionOutput && !useLinear32Intermediate {
        _ = FileManager.default.createFile(atPath: url.path, contents: nil)
        outHandle = try FileHandle(forWritingTo: url)
        try outHandle?.truncate(atOffset: UInt64(outSize))
    }
    defer {
        try? outHandle?.close()
        try? linearOutHandle?.close()
    }

    let tg = MTLSize(width: 16, height: 16, depth: 1)
    let dsForTile = composeGPU ? downsampleArg : 1
    let baseTile = max(1, tileSize)
    let alignedTile = max(dsForTile, (baseTile / dsForTile) * dsForTile)
    let effectiveTile = alignedTile
    if effectiveTile < max(width, height) {
        print("tile rendering enabled: \(effectiveTile)x\(effectiveTile)")
    }
    let maxTraceTilePixels = effectiveTile * effectiveTile
    let traceTilesX = max(1, (width + effectiveTile - 1) / effectiveTile)
    let traceTilesY = max(1, (height + effectiveTile - 1) / effectiveTile)
    let traceTileTotal = max(1, traceTilesX * traceTilesY)

        let diskAtlasTex = runtime.diskAtlasTex
        let diskVol0Tex = runtime.diskVol0Tex
        let diskVol1Tex = runtime.diskVol1Tex
        let tracePipeline = runtime.tracePipeline
        let composePipeline = runtime.composePipeline
        let composeLinearPipeline = runtime.composeLinearPipeline
        let composeLinearTilePipeline = runtime.composeLinearTilePipeline
        let composeBHLinearPipeline = runtime.composeBHLinearPipeline
        let composeBHLinearTilePipeline = runtime.composeBHLinearTilePipeline
        let cloudHistPipeline = runtime.cloudHistPipeline
        let lumHistPipeline = runtime.lumHistPipeline
        let lumHistLinearPipeline = runtime.lumHistLinearPipeline
        let lumHistLinearTileCloudPipeline = runtime.lumHistLinearTileCloudPipeline

    struct InFlightSlot {
        let traceParamBuf: MTLBuffer
        let traceTileBuf: MTLBuffer?
        let linearParamBuf: MTLBuffer?
        let linearTileBuf: MTLBuffer?
    }

    let slotTraceParamBytes = MemoryLayout<PackedParams>.stride
    let slotTraceTileBytes = maxTraceTilePixels * traceStride
    let slotLinearParamBytes = useLinear32Intermediate ? MemoryLayout<ComposeParams>.stride : 0
    let slotLinearTileBytes = useLinear32Intermediate ? (maxTraceTilePixels * linearStride) : 0
    let slotBytes = slotTraceParamBytes
        + ((useInMemoryCollisions && !useLinear32Intermediate) ? 0 : slotTraceTileBytes)
        + slotLinearParamBytes
        + slotLinearTileBytes
    let workingSetCap = Int(min(device.recommendedMaxWorkingSetSize, UInt64(Int.max)))
    let inFlightBudget = max(64 * 1024 * 1024, min(workingSetCap / 8, 768 * 1024 * 1024))
    var maxInFlight = 2
    if slotBytes > 0 && slotBytes * 3 <= inFlightBudget {
        maxInFlight = 3
    }
    if traceInFlightOverrideArg > 0 {
        maxInFlight = traceInFlightOverrideArg
    }
    maxInFlight = min(maxInFlight, traceTileTotal)
    maxInFlight = max(1, maxInFlight)
    print("trace in-flight=\(maxInFlight), slotBytes=\(slotBytes), tiles=\(traceTileTotal)")

    var traceSlots: [InFlightSlot] = []
    traceSlots.reserveCapacity(maxInFlight)
    for _ in 0..<maxInFlight {
        guard let traceParamBuf = device.makeBuffer(length: slotTraceParamBytes, options: .storageModeShared) else {
            fail("failed to allocate trace param buffer slot")
        }
        let needsTraceTile = !(useInMemoryCollisions && !useLinear32Intermediate)
        let traceTileBuf: MTLBuffer?
        if needsTraceTile {
            guard let buf = device.makeBuffer(length: slotTraceTileBytes, options: .storageModeShared) else {
                fail("failed to allocate trace tile buffer slot")
            }
            traceTileBuf = buf
        } else {
            traceTileBuf = nil
        }
        let linearParamBuf: MTLBuffer?
        let linearTileBuf: MTLBuffer?
        if useLinear32Intermediate {
            guard let lp = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                fail("failed to allocate linear32 compose param buffer slot")
            }
            guard let lt = device.makeBuffer(length: maxTraceTilePixels * linearStride, options: .storageModeShared) else {
                fail("failed to allocate linear32 tile buffer slot")
            }
            linearParamBuf = lp
            linearTileBuf = lt
        } else {
            linearParamBuf = nil
            linearTileBuf = nil
        }
        traceSlots.append(InFlightSlot(traceParamBuf: traceParamBuf, traceTileBuf: traceTileBuf, linearParamBuf: linearParamBuf, linearTileBuf: linearTileBuf))
    }

    var composeParamsBase = params
    let composeBaseBufForLinear: MTLBuffer? = useLinear32Intermediate
        ? device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])
        : nil
    if useLinear32Intermediate, composeBaseBufForLinear == nil {
        fail("failed to allocate linear32 base param buffer")
    }
    let tgLinearTile1D = MTLSize(width: max(1, min(256, composeLinearTilePipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
    let linearCloudBins = 2048
    var linearCloudHistGlobal = [UInt32](repeating: 0, count: linearCloudBins)
    var linearCloudSampleCount: UInt64 = 0
    var linearGlobalCloudQ10: Float = 0.0
    var linearGlobalCloudQ90: Float = 1.0
    var linearGlobalCloudInvSpan: Float = 1.0
    let linearLumBins = 4096
    let composeLumLogMin: Float = (diskPhysicsModeID == 3) ? -36.0 : 8.0
    let composeLumLogMax: Float = (diskPhysicsModeID == 3) ? 4.0 : 20.0
    let linearLumLogMin: Float = composeLumLogMin
    let linearLumLogMax: Float = composeLumLogMax

    var hitCount = 0
    var donePixels = 0
    let totalPixels = count
    let outWidth = width / downsampleArg
    let outHeight = height / downsampleArg
    let composePrepassOpsTarget: Int
    if composeGPU && gpuFullCompose && autoExposureEnabled {
        composePrepassOpsTarget = 3 * count
    } else if composeGPU && useLinear32Intermediate && autoExposureEnabled {
        composePrepassOpsTarget = count
    } else {
        composePrepassOpsTarget = 0
    }
    let composeOps = composeGPU ? (composePrepassOpsTarget + outWidth * outHeight) : 0
    let totalOps = totalPixels + composeOps
    let progressStep = max(1, totalOps / 256)
    var nextProgressMark = progressStep
    var lastProgressPrint = Date().timeIntervalSince1970
    var traceTileIndex = 0
    emitETAProgress(0, totalOps, "swift_trace", "task=trace tile=0/\(traceTileTotal)")
    let inFlightSemaphore = DispatchSemaphore(value: maxInFlight)
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
    while ty < height {
        let tileH = min(effectiveTile, height - ty)
        var tx = 0
        while tx < width {
            let tileW = min(effectiveTile, width - tx)
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
            let slot = traceSlots[traceDispatchIndex % maxInFlight]
            traceDispatchIndex += 1

            var tileParams = params
            tileParams.width = UInt32(tileW)
            tileParams.height = UInt32(tileH)
            tileParams.fullWidth = UInt32(width)
            tileParams.fullHeight = UInt32(height)
            tileParams.offsetX = UInt32(tileOriginX)
            tileParams.offsetY = UInt32(tileOriginY)
            updateBuffer(slot.traceParamBuf, with: &tileParams)

            if useLinear32Intermediate {
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
                    fullInputWidth: UInt32(width),
                    fullInputHeight: UInt32(height),
                    exposure: composeExposure,
                    dither: composeDitherArg,
                    innerEdgeMult: composeInnerEdgeArg,
                    spectralStep: composeSpectralStepArg,
                    cloudQ10: 0.0,
                    cloudInvSpan: 1.0,
                    look: composeLookID,
                    spectralEncoding: spectralEncodingID,
                    precisionMode: composePrecisionID,
                    analysisMode: composeAnalysisMode,
                    cloudBins: UInt32(linearCloudBins),
                    lumBins: UInt32(linearLumBins),
                    lumLogMin: linearLumLogMin,
                    lumLogMax: linearLumLogMax,
                    cameraModel: composeCameraModelID,
                    cameraPsfSigmaPx: composeCameraPsfSigmaArg,
                    cameraReadNoise: composeCameraReadNoiseArg,
                    cameraShotNoise: composeCameraShotNoiseArg,
                    cameraFlareStrength: composeCameraFlareStrengthArg,
                    backgroundMode: backgroundModeID,
                    backgroundStarDensity: backgroundStarDensityArg,
                    backgroundStarStrength: backgroundStarStrengthArg,
                    backgroundNebulaStrength: backgroundNebulaStrengthArg,
                    preserveHighlightColor: preserveHighlightColor
                )
                updateBuffer(linearParamBuf, with: &linearTileParams)
            }

            traceDispatchGroup.enter()
            let cmd = queue.makeCommandBuffer()!
            let enc = cmd.makeComputeCommandEncoder()!
            enc.setComputePipelineState(tracePipeline)
            enc.setBuffer(slot.traceParamBuf, offset: 0, index: 0)
            if useInMemoryCollisions {
                guard let collisionBuffer else {
                    fail("in-memory collision buffer missing for global trace path")
                }
                enc.setBuffer(collisionBuffer, offset: 0, index: 1)
            } else {
                guard let traceTileBuf = slot.traceTileBuf else {
                    fail("trace tile buffer missing for local trace path")
                }
                enc.setBuffer(traceTileBuf, offset: 0, index: 1)
            }
            enc.setTexture(diskAtlasTex, index: 0)
            enc.setTexture(diskVol0Tex, index: 1)
            enc.setTexture(diskVol1Tex, index: 2)
            enc.dispatchThreads(MTLSize(width: tileW, height: tileH, depth: 1), threadsPerThreadgroup: tg)
            enc.endEncoding()

            if useLinear32Intermediate {
                guard let composeBaseBufForLinear,
                      let linearParamBuf = slot.linearParamBuf,
                      let traceTileBuf = slot.traceTileBuf,
                      let linearTileBuf = slot.linearTileBuf else {
                    fail("linear32 slot buffers are not available")
                }
                let linearEnc = cmd.makeComputeCommandEncoder()!
                linearEnc.setComputePipelineState(composeLinearTilePipeline)
                linearEnc.setBuffer(composeBaseBufForLinear, offset: 0, index: 0)
                linearEnc.setBuffer(linearParamBuf, offset: 0, index: 1)
                linearEnc.setBuffer(traceTileBuf, offset: 0, index: 2)
                linearEnc.setBuffer(linearTileBuf, offset: 0, index: 3)
                linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinearTile1D)
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
                        if useInMemoryCollisions {
                            if let collisionBase {
                                let fullPtr = collisionBase.bindMemory(to: CollisionInfo.self, capacity: count)
                                var localHits = 0
                                for row in 0..<tileH {
                                    let rowBase = (tileOriginY + row) * width + tileOriginX
                                    for col in 0..<tileW {
                                        if fullPtr[rowBase + col].hit != 0 { localHits += 1 }
                                    }
                                }
                                hitCount += localHits
                            }
                        } else if let traceTileBuf = slot.traceTileBuf {
                            var localHits = 0
                            if collisionLite32Enabled {
                                let ptr = traceTileBuf.contents().bindMemory(to: CollisionLite32.self, capacity: tileCount)
                                for i in 0..<tileCount where ptr[i].noise_dirOct_hit.w > 0.5 { localHits += 1 }
                            } else {
                                let ptr = traceTileBuf.contents().bindMemory(to: CollisionInfo.self, capacity: tileCount)
                                for i in 0..<tileCount where ptr[i].hit != 0 { localHits += 1 }
                            }
                            hitCount += localHits
                        }

                        if useLinear32Intermediate {
                            guard let linearOutHandle, let linearTileBuf = slot.linearTileBuf else {
                                throw NSError(domain: "Blackhole", code: 71, userInfo: [NSLocalizedDescriptionKey: "linear32 output buffers missing"])
                            }
                            let linearPtr = linearTileBuf.contents().bindMemory(to: SIMD4<Float>.self, capacity: tileCount)
                            for i in 0..<tileCount {
                                let w = linearPtr[i].w
                                if w < 0 { continue }
                                let cloud = min(max(Double(w), 0.0), 1.0)
                                let bin = min(max(Int(floor(cloud * Double(linearCloudBins - 1) + 0.5)), 0), linearCloudBins - 1)
                                linearCloudHistGlobal[bin] = linearCloudHistGlobal[bin] &+ 1
                                linearCloudSampleCount += 1
                            }
                            for row in 0..<tileH {
                                let rowBytes = tileW * linearStride
                                let src = linearTileBuf.contents().advanced(by: row * rowBytes)
                                let dstOffset = ((tileOriginY + row) * width + tileOriginX) * linearStride
                                try linearOutHandle.seek(toOffset: UInt64(dstOffset))
                                try linearOutHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                            }
                        } else if !useInMemoryCollisions {
                            if let traceTileBuf = slot.traceTileBuf {
                                for row in 0..<tileH {
                                    let rowBytes = tileW * traceStride
                                    let src = traceTileBuf.contents().advanced(by: row * rowBytes)
                                    let dstOffset = ((tileOriginY + row) * width + tileOriginX) * traceStride
                                    if let outHandle {
                                        try outHandle.seek(toOffset: UInt64(dstOffset))
                                        try outHandle.write(contentsOf: Data(bytes: src, count: rowBytes))
                                    } else if discardCollisionOutput {
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
                    if donePixels >= totalPixels || donePixels >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(donePixels, totalOps, "swift_trace", "task=trace tile=\(tileOrdinal)/\(traceTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= donePixels {
                            nextProgressMark += progressStep
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

    if composeGPU {
        if !useInMemoryCollisions && !useLinear32Intermediate {
            try outHandle?.synchronize()
        }
        if useLinear32Intermediate {
            try linearOutHandle?.synchronize()

            if linearCloudSampleCount > 0 {
                linearGlobalCloudQ10 = linearCloudHistGlobal.withUnsafeBufferPointer {
                    quantileFromUniformHistogram($0, 0.08, 0.0, 1.0)
                }
                linearGlobalCloudQ90 = linearCloudHistGlobal.withUnsafeBufferPointer {
                    quantileFromUniformHistogram($0, 0.92, 0.0, 1.0)
                }
                linearGlobalCloudInvSpan = 1.0 / max(linearGlobalCloudQ90 - linearGlobalCloudQ10, 1e-6)
            }
            print("compose cloud normalization q10=\(linearGlobalCloudQ10) q90=\(linearGlobalCloudQ90) (linear32)")

            if autoExposureEnabled {
                let rawComposeRows = max(1, composeChunkArg / max(width, 1))
                var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
                if composeRows <= 0 { composeRows = downsampleArg }
                if composeRows > height { composeRows = height }

                let maxComposeTileCount = width * composeRows
                let lumHistBytes = linearLumBins * MemoryLayout<UInt32>.stride
                let tgLumTile1D = MTLSize(
                    width: max(1, min(256, lumHistLinearTileCloudPipeline.maxTotalThreadsPerThreadgroup)),
                    height: 1,
                    depth: 1
                )
                guard let linearTileInBuf = device.makeBuffer(length: maxComposeTileCount * linearStride, options: .storageModeShared) else {
                    fail("failed to allocate linear32 exposure prepass input tile buffer")
                }
                guard let lumParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                    fail("failed to allocate linear32 exposure prepass param buffer")
                }
                guard let lumHistBuf = device.makeBuffer(length: lumHistBytes, options: .storageModeShared) else {
                    fail("failed to allocate linear32 exposure prepass histogram buffer")
                }

                var lumHistGlobal = [UInt32](repeating: 0, count: linearLumBins)
                var lumSampleCount: UInt64 = 0
                let readHandle = try FileHandle(forReadingFrom: linearURL)
                defer { try? readHandle.close() }

                var pty = 0
                var prepassDone = 0
                let prepassTileTotal = max(1, (height + composeRows - 1) / composeRows)
                var prepassTileIndex = 0
                while pty < height {
                    let tileH = min(composeRows, height - pty)
                    let tileW = width
                    let tileCount = tileW * tileH
                    let rowBytes = tileW * linearStride
                    for row in 0..<tileH {
                        let offset = ((pty + row) * width) * linearStride
                        try readHandle.seek(toOffset: UInt64(offset))
                        let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
                        if rowData.count != rowBytes {
                            throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while linear32 exposure prepass"])
                        }
                        _ = rowData.withUnsafeBytes { raw in
                            memcpy(linearTileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                        }
                    }

                    var lumParams = ComposeParams(
                        tileWidth: UInt32(tileW),
                        tileHeight: UInt32(tileH),
                        downsample: 1,
                        outTileWidth: 0,
                        outTileHeight: 0,
                        srcOffsetX: 0,
                        srcOffsetY: UInt32(pty),
                        outOffsetX: 0,
                        outOffsetY: 0,
                        fullInputWidth: UInt32(width),
                        fullInputHeight: UInt32(height),
                        exposure: composeExposure,
                        dither: composeDitherArg,
                        innerEdgeMult: composeInnerEdgeArg,
                        spectralStep: composeSpectralStepArg,
                        cloudQ10: linearGlobalCloudQ10,
                        cloudInvSpan: linearGlobalCloudInvSpan,
                        look: composeLookID,
                        spectralEncoding: spectralEncodingID,
                        precisionMode: composePrecisionID,
                        analysisMode: composeAnalysisMode,
                        cloudBins: UInt32(linearCloudBins),
                        lumBins: UInt32(linearLumBins),
                        lumLogMin: linearLumLogMin,
                        lumLogMax: linearLumLogMax,
                        cameraModel: composeCameraModelID,
                        cameraPsfSigmaPx: composeCameraPsfSigmaArg,
                        cameraReadNoise: composeCameraReadNoiseArg,
                        cameraShotNoise: composeCameraShotNoiseArg,
                        cameraFlareStrength: composeCameraFlareStrengthArg,
                        backgroundMode: backgroundModeID,
                        backgroundStarDensity: backgroundStarDensityArg,
                        backgroundStarStrength: backgroundStarStrengthArg,
                        backgroundNebulaStrength: backgroundNebulaStrengthArg,
                        preserveHighlightColor: preserveHighlightColor
                    )
                    updateBuffer(lumParamBuf, with: &lumParams)
                    memset(lumHistBuf.contents(), 0, lumHistBytes)

                    let lumCmd = queue.makeCommandBuffer()!
                    let lumEnc = lumCmd.makeComputeCommandEncoder()!
                    lumEnc.setComputePipelineState(lumHistLinearTileCloudPipeline)
                    lumEnc.setBuffer(lumParamBuf, offset: 0, index: 0)
                    lumEnc.setBuffer(linearTileInBuf, offset: 0, index: 1)
                    lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                    lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLumTile1D)
                    lumEnc.endEncoding()
                    lumCmd.commit()
                    lumCmd.waitUntilCompleted()

                    let lumPtr = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: linearLumBins)
                    for i in 0..<linearLumBins {
                        let c = lumPtr[i]
                        lumHistGlobal[i] = lumHistGlobal[i] &+ c
                        lumSampleCount += UInt64(c)
                    }

                    prepassDone += tileCount
                    prepassTileIndex += 1
                    let doneAll = totalPixels + prepassDone
                    let now = Date().timeIntervalSince1970
                    if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(min(doneAll, totalOps), totalOps, "swift_prepass", "task=linear32_lumhist tile=\(prepassTileIndex)/\(prepassTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= doneAll {
                            nextProgressMark += progressStep
                        }
                    }

                    pty += tileH
                }

                if lumSampleCount == 0 {
                    composeExposure = 1.0
                } else {
                    let p50Log = lumHistGlobal.withUnsafeBufferPointer {
                        quantileFromUniformHistogram($0, 0.50, linearLumLogMin, linearLumLogMax)
                    }
                    let p995Log = lumHistGlobal.withUnsafeBufferPointer {
                        quantileFromUniformHistogram($0, 0.995, linearLumLogMin, linearLumLogMax)
                    }
                    let p50 = pow(10.0, Double(p50Log))
                    let p995 = pow(10.0, Double(p995Log))
                    let targetWhite: Float = composeTargetWhite(composeLookID)
                    let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                    composeExposure = targetWhite / max(Float(p995), pFloor)
                    print("lum(linear32) p50=\(p50), p99.5=\(p995), samples=\(lumSampleCount)")
                }
            }
        }

        composeParamsBase = params
        if gpuFullCompose {
            guard let collisionBuffer else {
                fail("gpu-full-compose requires in-memory collision buffer")
            }
            let cloudBins = 8192
            let lumBins = 4096
            let lumLogMin: Float = composeLumLogMin
            let lumLogMax: Float = composeLumLogMax
            let cloudHistBytes = cloudBins * MemoryLayout<UInt32>.stride
            let lumHistBytes = lumBins * MemoryLayout<UInt32>.stride
            let tgCloud1D = MTLSize(width: max(1, min(256, cloudHistPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
            let tgLinear1D = MTLSize(width: max(1, min(256, composeLinearPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
            let tgLum1D = MTLSize(width: max(1, min(256, lumHistLinearPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)

            var globalCloudQ10: Float = 0.0
            var globalCloudQ90: Float = 1.0
            var globalCloudInvSpan = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
            let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])!
            var composePrepassOps = 0

            var composeParamsTemplate = ComposeParams(
                tileWidth: 0,
                tileHeight: 0,
                downsample: UInt32(downsampleArg),
                outTileWidth: 0,
                outTileHeight: 0,
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
                preserveHighlightColor: preserveHighlightColor
            )

            let rawComposeRows = max(1, composeChunkArg / max(width, 1))
            var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
            if composeRows <= 0 { composeRows = downsampleArg }
            if composeRows > height { composeRows = height }
            let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)
            let maxComposeOutTileCount = (width / downsampleArg) * (composeRows / downsampleArg)
            guard let composeParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                fail("failed to allocate compose param buffer")
            }
            guard let cloudParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                fail("failed to allocate cloud hist param buffer")
            }
            guard let lumParamBuf = device.makeBuffer(length: MemoryLayout<ComposeParams>.stride, options: .storageModeShared) else {
                fail("failed to allocate luminance hist param buffer")
            }
            guard let cloudHistBuf = device.makeBuffer(length: cloudHistBytes, options: .storageModeShared) else {
                fail("failed to allocate cloud histogram buffer")
            }
            guard let lumHistBuf = device.makeBuffer(length: lumHistBytes, options: .storageModeShared) else {
                fail("failed to allocate luminance histogram buffer")
            }
            guard let composeOutBuf = device.makeBuffer(length: maxComposeOutTileCount * 4, options: .storageModeShared) else {
                fail("failed to allocate compose output tile buffer")
            }
            let composeLinearFullBuf: MTLBuffer? = autoExposureEnabled
                ? device.makeBuffer(length: count * MemoryLayout<SIMD4<Float>>.stride, options: .storageModeShared)
                : nil
            if autoExposureEnabled, composeLinearFullBuf == nil {
                fail("failed to allocate full-frame linear RGB buffer")
            }

            if autoExposureEnabled {
                guard let composeLinearFullBuf else {
                    fail("full-frame linear RGB buffer missing in auto-exposure path")
                }
                var cloudHistGlobal = [UInt32](repeating: 0, count: cloudBins)
                var cloudSampleCount: UInt64 = 0
                var lumHistGlobal = [UInt32](repeating: 0, count: lumBins)
                var lumSampleCount: UInt64 = 0

                // Pass A: compute cloud histogram per tile and global cloud stats.
                var pty = 0
                var cloudHistTileIndex = 0
                while pty < height {
                    let tileH = min(composeRows, height - pty)
                    let tileW = width
                    let tileCount = tileW * tileH
                    let srcOffsetBytes = pty * width * stride

                    composeParamsTemplate.tileWidth = UInt32(tileW)
                    composeParamsTemplate.tileHeight = UInt32(tileH)
                    composeParamsTemplate.srcOffsetY = UInt32(pty)
                    composeParamsTemplate.outTileWidth = UInt32(tileW / downsampleArg)
                    composeParamsTemplate.outTileHeight = UInt32(tileH / downsampleArg)
                    composeParamsTemplate.outOffsetY = UInt32((height - pty - tileH) / downsampleArg)

                    memset(cloudHistBuf.contents(), 0, cloudHistBytes)
                    var cloudHistParams = composeParamsTemplate
                    updateBuffer(cloudParamBuf, with: &cloudHistParams)
                    let cloudCmd = queue.makeCommandBuffer()!
                    let cloudEnc = cloudCmd.makeComputeCommandEncoder()!
                    cloudEnc.setComputePipelineState(cloudHistPipeline)
                    cloudEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    cloudEnc.setBuffer(cloudParamBuf, offset: 0, index: 1)
                    cloudEnc.setBuffer(collisionBuffer, offset: srcOffsetBytes, index: 2)
                    cloudEnc.setBuffer(cloudHistBuf, offset: 0, index: 3)
                    cloudEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgCloud1D)
                    cloudEnc.endEncoding()
                    cloudCmd.commit()
                    cloudCmd.waitUntilCompleted()

                    let cloudPtr = cloudHistBuf.contents().bindMemory(to: UInt32.self, capacity: cloudBins)
                    for i in 0..<cloudBins {
                        let c = cloudPtr[i]
                        cloudHistGlobal[i] = cloudHistGlobal[i] &+ c
                        cloudSampleCount += UInt64(c)
                    }

                    composePrepassOps += tileCount
                    cloudHistTileIndex += 1
                    let doneAll = totalPixels + composePrepassOps
                    let now = Date().timeIntervalSince1970
                    if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(min(doneAll, totalOps), totalOps, "swift_prepass", "task=cloud_hist tile=\(cloudHistTileIndex)/\(composeTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= doneAll {
                            nextProgressMark += progressStep
                        }
                    }

                    pty += tileH
                }

                if cloudSampleCount > 0 {
                    globalCloudQ10 = cloudHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.08, 0.0, 1.0) }
                    globalCloudQ90 = cloudHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.92, 0.0, 1.0) }
                    globalCloudInvSpan = 1.0 / max(globalCloudQ90 - globalCloudQ10, 1e-6)
                }

                // Pass B: compute linear RGB once and reuse it for luminance histogram.
                pty = 0
                var prepassTileIndex = 0
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
                    // Use global cloud normalization to avoid tile-boundary banding artifacts.
                    composeParamsTemplate.cloudQ10 = globalCloudQ10
                    composeParamsTemplate.cloudInvSpan = globalCloudInvSpan

                    var linearParams = composeParamsTemplate
                    updateBuffer(lumParamBuf, with: &linearParams)
                    let linearCmd = queue.makeCommandBuffer()!
                    let linearEnc = linearCmd.makeComputeCommandEncoder()!
                    linearEnc.setComputePipelineState(composeLinearPipeline)
                    linearEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    linearEnc.setBuffer(lumParamBuf, offset: 0, index: 1)
                    linearEnc.setBuffer(collisionBuffer, offset: srcOffsetBytes, index: 2)
                    linearEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 3)
                    linearEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLinear1D)
                    linearEnc.endEncoding()
                    linearCmd.commit()
                    linearCmd.waitUntilCompleted()

                    memset(lumHistBuf.contents(), 0, lumHistBytes)
                    var lumHistParams = composeParamsTemplate
                    updateBuffer(lumParamBuf, with: &lumHistParams)
                    let lumCmd = queue.makeCommandBuffer()!
                    let lumEnc = lumCmd.makeComputeCommandEncoder()!
                    lumEnc.setComputePipelineState(lumHistLinearPipeline)
                    lumEnc.setBuffer(lumParamBuf, offset: 0, index: 0)
                    lumEnc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                    lumEnc.setBuffer(lumHistBuf, offset: 0, index: 2)
                    lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: tgLum1D)
                    lumEnc.endEncoding()
                    lumCmd.commit()
                    lumCmd.waitUntilCompleted()

                    let lumPtr = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: lumBins)
                    for i in 0..<lumBins {
                        let c = lumPtr[i]
                        lumHistGlobal[i] = lumHistGlobal[i] &+ c
                        lumSampleCount += UInt64(c)
                    }

                    composePrepassOps += tileCount * 2
                    let doneAll = totalPixels + composePrepassOps
                    let now = Date().timeIntervalSince1970
                    if doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        let tileNow = prepassTileIndex + 1
                        emitETAProgress(min(doneAll, totalOps), totalOps, "swift_prepass", "task=linear_lumhist tile=\(tileNow)/\(composeTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= doneAll {
                            nextProgressMark += progressStep
                        }
                    }

                    pty += tileH
                    prepassTileIndex += 1
                }

                if lumSampleCount == 0 {
                    composeExposure = 1.0
                } else {
                    let p50Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.50, lumLogMin, lumLogMax) }
                    let p995Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.995, lumLogMin, lumLogMax) }
                    let p50 = pow(10.0, Double(p50Log))
                    let p995 = pow(10.0, Double(p995Log))
                    var targetWhite: Float = composeTargetWhite(composeLookID)
                    if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }
                    let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                    composeExposure = targetWhite / max(Float(p995), pFloor)
                    print("lum(hist) p50=\(p50), p99.5=\(p995), samples=\(lumSampleCount)")
                }
            }

            composeParamsTemplate.exposure = composeExposure
            composeParamsTemplate.cloudQ10 = globalCloudQ10
            composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
            print("compose cloud normalization q10=\(globalCloudQ10) q90=\(globalCloudQ90)")
            print("exposure=\(composeExposure) (auto=\(autoExposureEnabled), gpuFullCompose=true)")

            var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
            let composePixelOps = outWidth * outHeight

            var composed = 0
            var cty = 0
            var composeTileIndex = 0
            if autoExposureEnabled {
                guard let composeLinearFullBuf else {
                    fail("linear RGB buffer missing before compose stage")
                }
                while cty < height {
                    let tileH = min(composeRows, height - cty)
                    let tileW = width
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
                    enc.setComputePipelineState(composeBHLinearPipeline)
                    enc.setBuffer(composeParamBuf, offset: 0, index: 0)
                    enc.setBuffer(composeLinearFullBuf, offset: 0, index: 1)
                    enc.setBuffer(composeOutBuf, offset: 0, index: 2)
                    enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
                    enc.endEncoding()
                    cmd.commit()
                    cmd.waitUntilCompleted()

                    let outPtr = composeOutBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
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
                    let doneAll = totalPixels + composePrepassOps + composed
                    let now = Date().timeIntervalSince1970
                    if composed >= composePixelOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=compose_linear tile=\(composeTileIndex)/\(composeTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= doneAll {
                            nextProgressMark += progressStep
                        }
                    }
                    cty += tileH
                }
            } else {
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
                    // Keep cloud normalization global to avoid horizontal/vertical seams.
                    composeParamsTemplate.cloudQ10 = globalCloudQ10
                    composeParamsTemplate.cloudInvSpan = globalCloudInvSpan
                    updateBuffer(composeParamBuf, with: &composeParamsTemplate)

                    let cmd = queue.makeCommandBuffer()!
                    let enc = cmd.makeComputeCommandEncoder()!
                    enc.setComputePipelineState(composePipeline)
                    enc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                    enc.setBuffer(composeParamBuf, offset: 0, index: 1)
                    enc.setBuffer(collisionBuffer, offset: srcOffsetBytes, index: 2)
                    enc.setBuffer(composeOutBuf, offset: 0, index: 3)
                    enc.dispatchThreads(MTLSize(width: outTileW, height: outTileH, depth: 1), threadsPerThreadgroup: tg)
                    enc.endEncoding()
                    cmd.commit()
                    cmd.waitUntilCompleted()

                    let outPtr = composeOutBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
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
                    let doneAll = totalPixels + composePrepassOps + composed
                    let now = Date().timeIntervalSince1970
                    if composed >= composePixelOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                        emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=compose_collision tile=\(composeTileIndex)/\(composeTileTotal)")
                        lastProgressPrint = now
                        while nextProgressMark <= doneAll {
                            nextProgressMark += progressStep
                        }
                    }
                    cty += tileH
                }
            }

            try RenderOutputs.writeImage(path: imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
            print("Saved image at: \(imageOutPath)")
        } else if useLinear32Intermediate {
        print("linear32 source=\(linearURL.path)")
        print("exposure=\(composeExposure) (auto=\(autoExposureEnabled), linear32=true)")

        var composeParamsTemplate = ComposeParams(
            tileWidth: 0,
            tileHeight: 0,
            downsample: UInt32(downsampleArg),
            outTileWidth: 0,
            outTileHeight: 0,
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
            cloudQ10: linearGlobalCloudQ10,
            cloudInvSpan: linearGlobalCloudInvSpan,
            look: composeLookID,
            spectralEncoding: spectralEncodingID,
            precisionMode: composePrecisionID,
            analysisMode: composeAnalysisMode,
            cloudBins: 2048,
            lumBins: UInt32(linearLumBins),
            lumLogMin: linearLumLogMin,
            lumLogMax: linearLumLogMax,
            cameraModel: composeCameraModelID,
            cameraPsfSigmaPx: composeCameraPsfSigmaArg,
            cameraReadNoise: composeCameraReadNoiseArg,
            cameraShotNoise: composeCameraShotNoiseArg,
            cameraFlareStrength: composeCameraFlareStrengthArg,
            backgroundMode: backgroundModeID,
            backgroundStarDensity: backgroundStarDensityArg,
            backgroundStarStrength: backgroundStarStrengthArg,
            backgroundNebulaStrength: backgroundNebulaStrengthArg,
            preserveHighlightColor: preserveHighlightColor
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

        var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        let readHandle = try FileHandle(forReadingFrom: linearURL)
        defer { try? readHandle.close() }

        var composed = 0
        var cty = 0
        var composeTileIndex = 0
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
            let doneAll = totalPixels + composePrepassOpsTarget + composed
            let now = Date().timeIntervalSince1970
            if composed >= composeOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=linear32_compose tile=\(composeTileIndex)/\(composeTileTotal)")
                lastProgressPrint = now
                while nextProgressMark <= doneAll {
                    nextProgressMark += progressStep
                }
            }

            cty += tileH
        }

        try RenderOutputs.writeImage(path: imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
        print("Saved image at: \(imageOutPath)")
        } else {
        let hitOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.hit) ?? 0
        let tOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.T) ?? 8
        let vDiskOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.v_disk) ?? 16
        let directOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.direct_world) ?? 32
        let noiseOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.noise) ?? 48
        let emitROffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_r_norm) ?? 52
        let emitPhiOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_phi) ?? 56
        let emitZOffset = MemoryLayout<CollisionInfo>.offset(of: \CollisionInfo.emit_z_norm) ?? 60
        let cloudQ10: Float = 0.0
        let cloudQ90: Float = 1.0
        let cloudInvSpan = 1.0 / max(cloudQ90 - cloudQ10, 1e-6)
        var cpuP995ForCompose: Float = 0.0
        var sampledHits = 0

        if autoExposureEnabled {
            var lumSamples: [Float] = []
            let sampleStride = (exposureSamplesArg > 0) ? max(1, count / max(exposureSamplesArg, 1)) : 1
            let stepNm = Double(max(composeSpectralStepArg, 0.25))
            let luma = SIMD3<Double>(0.2126, 0.7152, 0.0722)
            let rs = Double(params.rs)
            let ghM = 1.0e35
            let gg = 6.67430e-11
            let cc = 299_792_458.0
            let xyzRow0 = SIMD3<Double>(3.2406, -1.5372, -0.4986)
            let xyzRow1 = SIMD3<Double>(-0.9689, 1.8758, 0.0415)
            let xyzRow2 = SIMD3<Double>(0.0557, -0.2040, 1.0570)
            let camX = Double(params.camPos.x)
            let camY = Double(params.camPos.y)
            let camZ = Double(params.camPos.z)
            let rObs = max(sqrt(camX * camX + camY * camY + camZ * camZ), rs * 1.0001)
            let sampleHandle = try FileHandle(forReadingFrom: url)
            defer { try? sampleHandle.close() }
            let scanRecords = max(1, composeChunkArg)
            let scanBytes = scanRecords * stride
            var globalStart = 0
            while true {
                let data = try sampleHandle.read(upToCount: scanBytes) ?? Data()
                if data.isEmpty { break }

                let recCount = data.count / stride
                var chunkT: [Double] = []
                var chunkV: [SIMD3<Double>] = []
                var chunkD: [SIMD3<Double>] = []
                var chunkN: [Double] = []
                var chunkI: [Double] = []
                var chunkEmitR: [Double] = []
                var chunkEmitPhi: [Double] = []
                var chunkEmitZ: [Double] = []
                chunkT.reserveCapacity(min(recCount, 8192))
                chunkV.reserveCapacity(min(recCount, 8192))
                chunkD.reserveCapacity(min(recCount, 8192))
                chunkN.reserveCapacity(min(recCount, 8192))
                chunkI.reserveCapacity(min(recCount, 8192))
                chunkEmitR.reserveCapacity(min(recCount, 8192))
                chunkEmitPhi.reserveCapacity(min(recCount, 8192))
                chunkEmitZ.reserveCapacity(min(recCount, 8192))

                data.withUnsafeBytes { raw in
                    guard let basePtr = raw.baseAddress else { return }
                    for i in 0..<recCount {
                        let absIdx = globalStart + i
                        if exposureSamplesArg > 0 && ((absIdx % sampleStride) != 0) {
                            continue
                        }
                        let base = i * stride
                        var hit: UInt32 = 0
                        withUnsafeMutableBytes(of: &hit) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + hitOffset), count: MemoryLayout<UInt32>.size))
                        }
                        if hit == 0 { continue }

                        var t: Float = 0
                        withUnsafeMutableBytes(of: &t) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + tOffset), count: MemoryLayout<Float>.size))
                        }
                        var v4 = SIMD4<Float>(repeating: 0)
                        withUnsafeMutableBytes(of: &v4) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + vDiskOffset), count: MemoryLayout<SIMD4<Float>>.size))
                        }
                        var d4 = SIMD4<Float>(repeating: 0)
                        withUnsafeMutableBytes(of: &d4) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + directOffset), count: MemoryLayout<SIMD4<Float>>.size))
                        }
                        var n: Float = 0
                        withUnsafeMutableBytes(of: &n) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + noiseOffset), count: MemoryLayout<Float>.size))
                        }
                        var emitR: Float = 0
                        withUnsafeMutableBytes(of: &emitR) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitROffset), count: MemoryLayout<Float>.size))
                        }
                        var emitPhi: Float = 0
                        withUnsafeMutableBytes(of: &emitPhi) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitPhiOffset), count: MemoryLayout<Float>.size))
                        }
                        var emitZ: Float = 0
                        withUnsafeMutableBytes(of: &emitZ) { dst in
                            dst.copyMemory(from: UnsafeRawBufferPointer(start: basePtr.advanced(by: base + emitZOffset), count: MemoryLayout<Float>.size))
                        }

                        chunkT.append(max(Double(t), 1.0))
                        chunkV.append(SIMD3<Double>(Double(v4.x), Double(v4.y), Double(v4.z)))
                        chunkD.append(SIMD3<Double>(Double(d4.x), Double(d4.y), Double(d4.z)))
                        chunkN.append(Double(n))
                        chunkI.append(max(Double(v4.w), 0.0))
                        chunkEmitR.append(Double(emitR))
                        chunkEmitPhi.append(Double(emitPhi))
                        chunkEmitZ.append(Double(emitZ))
                    }
                }

                if !chunkT.isEmpty {
                    var procNoise = chunkN
                    if composeAnalysisMode == 0 && spectralEncodingID == 0 {
                        var maxAbsN = 0.0
                        for n in procNoise { maxAbsN = max(maxAbsN, abs(n)) }
                        if maxAbsN < 1e-6 {
                            let re = max(rcp, 1.2) * rs
                            for i in 0..<procNoise.count {
                                let vx = chunkV[i].x
                                let vy = chunkV[i].y
                                let speed = max(hypot(vx, vy), 1e-30)
                                let r = gg * ghM / max(speed * speed, 1e-30)
                                let u = min(max((r - rs) / max(re - rs, 1e-12), 0.0), 1.0)
                                let phi = atan2(-vx, vy)
                                let theta = phi + 1.9 * log(max(r / rs, 1.0))
                                procNoise[i] = min(max(0.65 * sin(18.0 * u + 3.0 * cos(theta)) + 0.35 * cos(11.0 * theta), -1.0), 1.0)
                            }
                        }
                    }

                    var cloudVals = [Float](repeating: 0, count: procNoise.count)
                    if composeAnalysisMode == 0 {
                        for i in 0..<procNoise.count {
                            let n = min(max(procNoise[i], -1.0), 1.0)
                            let c = (n < -1e-6) ? min(max(0.5 + 0.5 * n, 0.0), 1.0) : min(max(n, 0.0), 1.0)
                            cloudVals[i] = Float(c)
                        }
                    } else {
                        for i in 0..<cloudVals.count { cloudVals[i] = 0.5 }
                    }
                    var sortedCloud = cloudVals
                    sortedCloud.sort()
                    let q10 = percentileSorted(sortedCloud, 0.08)
                    let q90 = percentileSorted(sortedCloud, 0.92)
                    let invSpan = 1.0 / max(q90 - q10, 1e-6)

                    var chunkLum: [Float] = []
                    chunkLum.reserveCapacity(chunkT.count)
                    for i in 0..<chunkT.count {
                        if diskPhysicsModeID == 3 {
                            let rgb: SIMD3<Double>
                            if composeAnalysisMode >= 11 && composeAnalysisMode <= 14 {
                                var raw = 0.0
                                var lo = -30.0
                                var hi = 2.0
                                if composeAnalysisMode == 11 {
                                    raw = max(chunkEmitR[i], 0.0) // max_rho
                                    lo = -16.0
                                } else if composeAnalysisMode == 12 {
                                    raw = max(chunkEmitPhi[i], 0.0) // max_b2
                                    lo = -20.0
                                    hi = 4.0
                                } else if composeAnalysisMode == 13 {
                                    raw = max(chunkEmitZ[i], 0.0) // max_jnu
                                    lo = -40.0
                                    hi = -20.0
                                } else {
                                    raw = max(chunkN[i], 0.0) // max_inu
                                    lo = -40.0
                                    hi = -20.0
                                }
                                let lv = log10(max(raw, 1e-38))
                                let t = min(max((lv - lo) / max(hi - lo, 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if composeAnalysisMode == 15 {
                                let teff = max(chunkT[i], 1.0)
                                let lv = log10(teff)
                                let t = min(max((lv - 2.0) / max(7.0 - 2.0, 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if composeAnalysisMode == 16 {
                                let g = min(max(chunkV[i].x, 1e-6), 1e6)
                                let lv = log10(g)
                                let t = min(max((lv - (-2.0)) / max(2.0 - (-2.0), 1e-9), 0.0), 1.0)
                                rgb = SIMD3<Double>(repeating: t)
                            } else if visibleModeEnabled {
                                let g = min(max(chunkV[i].x, 1e-4), 1e4)
                                let tEmit = max(chunkT[i], 1.0)
                                let scalarI = max(chunkI[i], 0.0)
                                let fCol = (visibleTeffModelID == 2) ? max(diskColorFactorArg, 1.0) : 1.0
                                let tSpec = tEmit * fCol
                                let colorDilution = 1.0 / pow(fCol, 4.0)
                                let usePackedVisibleAnchors =
                                    (diskPhysicsModeID == 3 &&
                                     photosphereRhoThresholdResolved <= 0.0 &&
                                     chunkEmitR[i] > 0.0 &&
                                     chunkEmitPhi[i] > 0.0 &&
                                     chunkEmitZ[i] > 0.0)
                                let nLam = max(8, visibleSamplesArg)
                                let lamMin = 380.0
                                let lamMax = 780.0
                                let dLamNm = (lamMax - lamMin) / Double(max(nLam - 1, 1))
                                let dLamM = dLamNm * 1e-9
                                let g3 = g * g * g

                                var X = 0.0
                                var Y = 0.0
                                var Z = 0.0
                                var peakLamNm = lamMin
                                var peakIlam = 0.0

                                if usePackedVisibleAnchors {
                                    // GRMHD visible volumetric path already integrated three I_nu anchors
                                    // in Metal: {650nm, 550nm, 450nm}. Reconstruct a smooth spectrum here
                                    // instead of re-imposing a blackbody from T/g, which over-whitens output.
                                    let lamRnm = 650.0
                                    let lamGnm = 550.0
                                    let lamBnm = 450.0
                                    let lamRm = lamRnm * 1e-9
                                    let lamGm = lamGnm * 1e-9
                                    let lamBm = lamBnm * 1e-9

                                    let iNuR = max(chunkEmitR[i], 1e-38)
                                    let iNuG = max(chunkEmitPhi[i], 1e-38)
                                    let iNuB = max(chunkEmitZ[i], 1e-38)
                                    let iLamR = iNuR * cc / max(lamRm * lamRm, 1e-30)
                                    let iLamG = iNuG * cc / max(lamGm * lamGm, 1e-30)
                                    let iLamB = iNuB * cc / max(lamBm * lamBm, 1e-30)

                                    let xR = log(lamRnm)
                                    let xG = log(lamGnm)
                                    let xB = log(lamBnm)
                                    let yR = log(max(iLamR, 1e-38))
                                    let yG = log(max(iLamG, 1e-38))
                                    let yB = log(max(iLamB, 1e-38))
                                    let slopeBG = (yG - yB) / max(xG - xB, 1e-12)
                                    let slopeGR = (yR - yG) / max(xR - xG, 1e-12)

                                    for j in 0..<nLam {
                                        let lamNm = lamMin + dLamNm * Double(j)
                                        let xLam = log(max(lamNm, 1e-9))
                                        let logILam: Double
                                        if lamNm <= lamGnm {
                                            logILam = yB + slopeBG * (xLam - xB)
                                        } else {
                                            logILam = yG + slopeGR * (xLam - xG)
                                        }
                                        let iLamObs = exp(min(max(logILam, -90.0), 90.0))
                                        let (xb, yb, zb) = cieXYZBar(lamNm)
                                        X += iLamObs * xb * dLamM
                                        Y += iLamObs * yb * dLamM
                                        Z += iLamObs * zb * dLamM
                                        if iLamObs > peakIlam {
                                            peakIlam = iLamObs
                                            peakLamNm = lamNm
                                        }
                                    }

                                    // Keep flux consistency with scalar payload, but avoid massive re-scaling.
                                    let iNuRef = 0.30 * iNuR + 0.40 * iNuG + 0.30 * iNuB
                                    if scalarI > 1e-18 {
                                        let amp = min(max(scalarI / max(iNuRef, 1e-38), 0.1), 10.0)
                                        X *= amp
                                        Y *= amp
                                        Z *= amp
                                    }
                                } else {
                                    for j in 0..<nLam {
                                        let lamNm = lamMin + dLamNm * Double(j)
                                        let lamM = lamNm * 1e-9
                                        let nuObs = cc / max(lamM, 1e-30)
                                        let nuEm = nuObs / max(g, 1e-8)
                                        let iNuEm = visibleINuEmit(nuEm, tSpec, visibleEmissionModelID, visibleSynchAlphaArg)
                                        let iNuObs = g3 * iNuEm
                                        let iLamObs = iNuObs * cc / max(lamM * lamM, 1e-30) * colorDilution
                                        let (xb, yb, zb) = cieXYZBar(lamNm)
                                        X += iLamObs * xb * dLamM
                                        Y += iLamObs * yb * dLamM
                                        Z += iLamObs * zb * dLamM
                                        if iLamObs > peakIlam {
                                            peakIlam = iLamObs
                                            peakLamNm = lamNm
                                        }
                                    }

                                    if scalarI > 1e-18 {
                                        let nuObsRef = max(diskNuObsHzArg, 1e6)
                                        let nuEmRef = nuObsRef / max(g, 1e-8)
                                        let iNuPred = g3 * visibleINuEmit(nuEmRef, tSpec, visibleEmissionModelID, visibleSynchAlphaArg) * colorDilution
                                        let amp = min(max(scalarI / max(iNuPred, 1e-38), 0.0), 1e12)
                                        X *= amp
                                        Y *= amp
                                        Z *= amp
                                    }
                                }

                                if composeAnalysisMode == 17 {
                                    let lv = log10(max(Y, 1e-38))
                                    let t = min(max((lv - (-30.0)) / max(4.0 - (-30.0), 1e-9), 0.0), 1.0)
                                    rgb = SIMD3<Double>(repeating: t)
                                } else if composeAnalysisMode == 18 {
                                    let w = min(max((peakLamNm - 380.0) / (780.0 - 380.0), 0.0), 1.0)
                                    let r = min(max(1.5 - abs(4.0 * w - 3.0), 0.0), 1.0)
                                    let gch = min(max(1.5 - abs(4.0 * w - 2.0), 0.0), 1.0)
                                    let b = min(max(1.5 - abs(4.0 * w - 1.0), 0.0), 1.0)
                                    rgb = SIMD3<Double>(r, gch, b)
                                } else {
                                    var rgbLin = SIMD3<Double>(
                                        xyzRow0.x * X + xyzRow0.y * Y + xyzRow0.z * Z,
                                        xyzRow1.x * X + xyzRow1.y * Y + xyzRow1.z * Z,
                                        xyzRow2.x * X + xyzRow2.y * Y + xyzRow2.z * Z
                                    )
                                    rgbLin.x = max(rgbLin.x, 0.0)
                                    rgbLin.y = max(rgbLin.y, 0.0)
                                    rgbLin.z = max(rgbLin.z, 0.0)
                                    let d = chunkD[i]
                                    let mu = abs(d.z) / max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                                    let limb = 0.4 + 0.6 * min(max(mu, 0.0), 1.0)
                                    rgb = rgbLin * limb
                                }
                            } else {
                                let iNu = max(chunkI[i], 0.0)
                                rgb = SIMD3<Double>(repeating: iNu)
                            }
                            chunkLum.append(Float(rgb.x * luma.x + rgb.y * luma.y + rgb.z * luma.z))
                            continue
                        }

                        let v = chunkV[i]
                        let d = chunkD[i]
                        let colorDilution: Double = (diskPhysicsModeID == 2) ? (1.0 / pow(max(diskColorFactorArg, 1.0), 4.0)) : 1.0
                        let gTotal: Double
                        if spectralEncodingID == 1 {
                            gTotal = min(max(v.x, 1e-4), 1e4)
                        } else {
                            let vNorm = max(sqrt(v.x * v.x + v.y * v.y + v.z * v.z), 1e-30)
                            let dNorm = max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                            let beta = min(max(vNorm / cc, 0.0), 0.999999)
                            let gamma = 1.0 / sqrt(max(1.0 - beta * beta, 1e-18))
                            let vd = v.x * d.x + v.y * d.y + v.z * d.z
                            let cosTheta = min(max(vd / (vNorm * dNorm), -1.0), 1.0)
                            let delta = 1.0 / max(gamma * (1.0 - beta * cosTheta), 1e-9)
                            let rEmitLegacy = max(gg * ghM / max(vNorm * vNorm, 1e-30), rs * 1.0001)
                            let gravNum = min(max(1.0 - rs / rEmitLegacy, 1e-8), 1.0)
                            let gravDen = min(max(1.0 - rs / rObs, 1e-8), 1.0)
                            let gGr = sqrt(min(max(gravNum / gravDen, 1e-8), 4.0))
                            gTotal = min(max(delta * gGr, 1e-4), 1e4)
                        }

                        let tObs = max(chunkT[i] * gTotal, 1.0)
                        var X = 0.0
                        var Y = 0.0
                        var Z = 0.0
                        var lam = 380.0
                        while lam <= 750.001 {
                            let (xb, yb, zb) = cieXYZBar(lam)
                            let lamM = lam * 1e-9
                            let b = planckLambda(lamM, tObs) * colorDilution
                            X += b * xb
                            Y += b * yb
                            Z += b * zb
                            lam += stepNm
                        }
                        var rgb = SIMD3<Double>(
                            xyzRow0.x * X + xyzRow0.y * Y + xyzRow0.z * Z,
                            xyzRow1.x * X + xyzRow1.y * Y + xyzRow1.z * Z,
                            xyzRow2.x * X + xyzRow2.y * Y + xyzRow2.z * Z
                        )
                        rgb.x = max(rgb.x, 0.0)
                        rgb.y = max(rgb.y, 0.0)
                        rgb.z = max(rgb.z, 0.0)

                        let mu = abs(d.z) / max(sqrt(d.x * d.x + d.y * d.y + d.z * d.z), 1e-30)
                        let limb: Double
                        if diskPhysicsModeID == 2 {
                            limb = (3.0 / 7.0) * (1.0 + 2.0 * min(max(mu, 0.0), 1.0))
                        } else {
                            limb = 0.4 + 0.6 * min(max(mu, 0.0), 1.0)
                        }
                        rgb *= limb
                        if spectralEncodingID == 1 && diskPhysicsModeID == 1 {
                            let rEmit = max(v.y, rs * 1.0001)
                            let xDen = max(diskInnerRadiusCompose - diskHorizonRadiusCompose, 1e-9)
                            let x = min(max((rEmit - diskHorizonRadiusCompose) / xDen, 0.0), 1.0)
                            let xSoft = x * x * (3.0 - 2.0 * x)
                            let floor = 0.35 * min(max(diskPlungeFloorArg, 0.0), 1.0)
                            let gate = floor + (1.0 - floor) * pow(max(xSoft, 1e-4), 2.2)
                            rgb *= gate
                        }

                        if composeAnalysisMode == 0 {
                            var cloud = min(max((Double(cloudVals[i]) - Double(q10)) * Double(invSpan), 0.0), 1.0)
                            cloud = 0.18 + 0.82 * cloud
                            let core = pow(cloud, 1.15)
                            let clump = pow(core, 2.2)
                            let vvoid = pow(1.0 - cloud, 1.8)
                            let density = 0.62 + 1.28 * core
                            rgb *= density
                            rgb *= (1.0 + 0.34 * clump)
                            rgb *= (1.0 - 0.14 * vvoid)
                            rgb.x *= (1.0 + 0.12 * clump)
                            rgb.z *= (1.0 - 0.08 * clump)
                        }
                        chunkLum.append(Float(rgb.x * luma.x + rgb.y * luma.y + rgb.z * luma.z))
                    }

                    if !chunkLum.isEmpty {
                        let lumStride = max(1, chunkLum.count / 8192)
                        var j = 0
                        while j < chunkLum.count {
                            lumSamples.append(chunkLum[j])
                            sampledHits += 1
                            j += lumStride
                        }
                    }
                }

                globalStart += recCount
            }

            if lumSamples.isEmpty {
                composeExposure = 1.0
            } else {
                lumSamples.sort()
                let p50 = percentileSorted(lumSamples, 0.50)
                let p995 = percentileSorted(lumSamples, 0.995)
                var targetWhite: Float = composeTargetWhite(composeLookID)
                if diskVolumeEnabled && diskPhysicsModeID != 3 { targetWhite *= 2.2 }
                let pFloor: Float = (diskPhysicsModeID == 3) ? 1e-30 : 1e-12
                composeExposure = targetWhite / max(p995, pFloor)
                cpuP995ForCompose = p995
                print("lum p50=\(p50), p99.5=\(p995), exposureSamples=\(sampledHits)")
            }
        }
        print("compose cloud normalization q10=\(cloudQ10) q90=\(cloudQ90)")
        print("exposure=\(composeExposure) (auto=\(autoExposureEnabled))")

        var composeParamsTemplate = ComposeParams(
            tileWidth: 0,
            tileHeight: 0,
            downsample: UInt32(downsampleArg),
            outTileWidth: 0,
            outTileHeight: 0,
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
            cloudQ10: cloudQ10,
            cloudInvSpan: cloudInvSpan,
            look: composeLookID,
            spectralEncoding: spectralEncodingID,
            precisionMode: composePrecisionID,
            analysisMode: composeAnalysisMode,
            cloudBins: 2048,
            lumBins: 4096,
            lumLogMin: composeLumLogMin,
            lumLogMax: composeLumLogMax,
            cameraModel: composeCameraModelID,
            cameraPsfSigmaPx: composeCameraPsfSigmaArg,
            cameraReadNoise: composeCameraReadNoiseArg,
            cameraShotNoise: composeCameraShotNoiseArg,
            cameraFlareStrength: composeCameraFlareStrengthArg,
            backgroundMode: backgroundModeID,
            backgroundStarDensity: backgroundStarDensityArg,
            backgroundStarStrength: backgroundStarStrengthArg,
            backgroundNebulaStrength: backgroundNebulaStrengthArg,
            preserveHighlightColor: preserveHighlightColor
        )
        let composeBaseBuf = device.makeBuffer(bytes: &composeParamsBase, length: MemoryLayout<PackedParams>.stride, options: [])!

        let rawComposeRows = max(1, composeChunkArg / max(width, 1))
        var composeRows = max(downsampleArg, (rawComposeRows / downsampleArg) * downsampleArg)
        if composeRows <= 0 { composeRows = downsampleArg }
        if composeRows > height { composeRows = height }
        let composeTileTotal = max(1, (height + composeRows - 1) / composeRows)

        if cpuP995ForCompose > 0 && diskPhysicsModeID != 3 {
            var lumHistGlobal = [UInt32](repeating: 0, count: 4096)
            let lumTg = MTLSize(width: max(1, min(256, lumHistPipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)
            let corrHandle = try FileHandle(forReadingFrom: url)
            defer { try? corrHandle.close() }
            var pty = 0
            while pty < height {
                let tileH = min(composeRows, height - pty)
                let tileW = width
                let tileCount = tileW * tileH
                let rowBytes = tileW * stride
                let tileInBuf = device.makeBuffer(length: tileCount * stride, options: .storageModeShared)!
                for row in 0..<tileH {
                    let offset = ((pty + row) * width) * stride
                    try corrHandle.seek(toOffset: UInt64(offset))
                    let rowData = try corrHandle.read(upToCount: rowBytes) ?? Data()
                    if rowData.count != rowBytes {
                        throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while compose exposure correction"])
                    }
                    _ = rowData.withUnsafeBytes { raw in
                        memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                    }
                }

                var lumParams = composeParamsTemplate
                lumParams.tileWidth = UInt32(tileW)
                lumParams.tileHeight = UInt32(tileH)
                lumParams.srcOffsetX = 0
                lumParams.srcOffsetY = UInt32(pty)
                lumParams.cloudQ10 = cloudQ10
                lumParams.cloudInvSpan = cloudInvSpan
                let lumParamBuf = device.makeBuffer(bytes: &lumParams, length: MemoryLayout<ComposeParams>.stride, options: [])!
                let lumHistBuf = device.makeBuffer(length: 4096 * MemoryLayout<UInt32>.stride, options: .storageModeShared)!
                memset(lumHistBuf.contents(), 0, 4096 * MemoryLayout<UInt32>.stride)

                let lumCmd = queue.makeCommandBuffer()!
                let lumEnc = lumCmd.makeComputeCommandEncoder()!
                lumEnc.setComputePipelineState(lumHistPipeline)
                lumEnc.setBuffer(composeBaseBuf, offset: 0, index: 0)
                lumEnc.setBuffer(lumParamBuf, offset: 0, index: 1)
                lumEnc.setBuffer(tileInBuf, offset: 0, index: 2)
                lumEnc.setBuffer(lumHistBuf, offset: 0, index: 3)
                lumEnc.dispatchThreads(MTLSize(width: tileCount, height: 1, depth: 1), threadsPerThreadgroup: lumTg)
                lumEnc.endEncoding()
                lumCmd.commit()
                lumCmd.waitUntilCompleted()

                let lp = lumHistBuf.contents().bindMemory(to: UInt32.self, capacity: 4096)
                for i in 0..<4096 {
                    lumHistGlobal[i] = lumHistGlobal[i] &+ lp[i]
                }
                pty += tileH
            }

            let p995Log = lumHistGlobal.withUnsafeBufferPointer { quantileFromUniformHistogram($0, 0.995, 8.0, 20.0) }
            let gpuP995 = Float(pow(10.0, Double(p995Log)))
            if gpuP995 > 0 {
                let corr = cpuP995ForCompose / max(gpuP995, 1e-12)
                composeExposure *= corr
                print("compose exposure correction cpu_p99.5=\(cpuP995ForCompose), gpu_p99.5=\(gpuP995), gain=\(corr)")
            }
        }
        composeParamsTemplate.exposure = composeExposure

        var rgb = [UInt8](repeating: 0, count: outWidth * outHeight * 3)
        let readHandle = try FileHandle(forReadingFrom: url)
        defer { try? readHandle.close() }

        var composed = 0
        var cty = 0
        var composeTileIndex = 0
        while cty < height {
            let tileH = min(composeRows, height - cty)
            let ctx = 0
            let tileW = width
            let tileCount = tileW * tileH
            let rowBytes = tileW * stride

            let tileInBuf = device.makeBuffer(length: tileCount * stride, options: .storageModeShared)!
            for row in 0..<tileH {
                let offset = ((cty + row) * width + ctx) * stride
                try readHandle.seek(toOffset: UInt64(offset))
                let rowData = try readHandle.read(upToCount: rowBytes) ?? Data()
                if rowData.count != rowBytes {
                    throw NSError(domain: "Blackhole", code: 2, userInfo: [NSLocalizedDescriptionKey: "short read while composing"])
                }
                _ = rowData.withUnsafeBytes { raw in
                    memcpy(tileInBuf.contents().advanced(by: row * rowBytes), raw.baseAddress!, rowBytes)
                }
            }

            let outTileW = tileW / downsampleArg
            let outTileH = tileH / downsampleArg
            let outTileCount = outTileW * outTileH
            let outOffsetX = ctx / downsampleArg
            let outOffsetY = (height - cty - tileH) / downsampleArg

            composeParamsTemplate.tileWidth = UInt32(tileW)
            composeParamsTemplate.tileHeight = UInt32(tileH)
            composeParamsTemplate.outTileWidth = UInt32(outTileW)
            composeParamsTemplate.outTileHeight = UInt32(outTileH)
            composeParamsTemplate.srcOffsetX = UInt32(ctx)
            composeParamsTemplate.srcOffsetY = UInt32(cty)
            composeParamsTemplate.outOffsetX = UInt32(outOffsetX)
            composeParamsTemplate.outOffsetY = UInt32(outOffsetY)
            composeParamsTemplate.cloudQ10 = cloudQ10
            composeParamsTemplate.cloudInvSpan = cloudInvSpan

            let composeParamBuf = device.makeBuffer(bytes: &composeParamsTemplate, length: MemoryLayout<ComposeParams>.stride, options: [])!
            let outBuf = device.makeBuffer(length: outTileCount * 4, options: .storageModeShared)!

            let cmd = queue.makeCommandBuffer()!
            let enc = cmd.makeComputeCommandEncoder()!
            enc.setComputePipelineState(composePipeline)
            enc.setBuffer(composeBaseBuf, offset: 0, index: 0)
            enc.setBuffer(composeParamBuf, offset: 0, index: 1)
            enc.setBuffer(tileInBuf, offset: 0, index: 2)
            enc.setBuffer(outBuf, offset: 0, index: 3)
            let grid = MTLSize(width: outTileW, height: outTileH, depth: 1)
            enc.dispatchThreads(grid, threadsPerThreadgroup: tg)
            enc.endEncoding()
            cmd.commit()
            cmd.waitUntilCompleted()

            let outPtr = outBuf.contents().bindMemory(to: UInt8.self, capacity: outTileCount * 4)
            for row in 0..<outTileH {
                var dst = ((outOffsetY + row) * outWidth + outOffsetX) * 3
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
            let doneAll = totalPixels + composed
            let now = Date().timeIntervalSince1970
            if composed >= composeOps || doneAll >= nextProgressMark || (now - lastProgressPrint) >= 0.5 {
                emitETAProgress(min(doneAll, totalOps), totalOps, "swift_compose", "task=cpu_compose tile=\(composeTileIndex)/\(composeTileTotal)")
                lastProgressPrint = now
                while nextProgressMark <= doneAll {
                    nextProgressMark += progressStep
                }
            }
            cty += tileH
        }

        try RenderOutputs.writeImage(path: imageOutPath, width: outWidth, height: outHeight, rgb: rgb)
        print("Saved image at: \(imageOutPath)")
        }
    }

    if useInMemoryCollisions && !discardCollisionOutput {
        guard let collisionBase else {
            fail("in-memory collision buffer unexpectedly missing at flush")
        }
        try writeRawBuffer(to: url, sourceBase: UnsafeRawPointer(collisionBase), byteCount: outSize)
    }

    let meta = RenderOutputs.makeMeta(
        config: config,
        composeExposure: composeExposure,
        effectiveTile: effectiveTile,
        outWidth: outWidth,
        outHeight: outHeight,
        collisionStride: traceStride
    )
    try RenderOutputs.writeMetadata(
        meta: meta,
        outPath: outPath,
        linear32OutPath: linear32OutPath,
        useLinear32Intermediate: useLinear32Intermediate,
        discardCollisionOutput: discardCollisionOutput,
        outSize: outSize,
        linearOutSize: linearOutSize,
        hitCount: hitCount
    )
    }
}
