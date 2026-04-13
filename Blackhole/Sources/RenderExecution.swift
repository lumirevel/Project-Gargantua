import Foundation
import Metal

enum RenderExecution {
    static func execute(config: ResolvedRenderConfig, params inputParams: PackedParams, runtime: RenderRuntime) throws {
        let device = runtime.device
        let queue = runtime.queue
        let params = inputParams

        print(config.renderConfigLine)
        if !config.grmhdConfigLine.isEmpty { print(config.grmhdConfigLine) }
        if !config.visibleConfigLine.isEmpty { print(config.visibleConfigLine) }

        let policy = RenderResourcePolicy(config: config, params: params, device: device)
        let preferLegacyRuntimeLinear =
            policy.composeStrategyPreference == .tileFirst &&
            config.composeGPU &&
            !config.visibleModeEnabled &&
            !config.rayBundleActive &&
            config.composeAnalysisMode == 0
        let effectiveGpuFullCompose = config.gpuFullCompose && !preferLegacyRuntimeLinear
        let effectiveUseLinear32Intermediate = config.useLinear32Intermediate
        let effectiveUseInMemoryCollisions = policy.useInMemoryCollisions && !effectiveUseLinear32Intermediate && !preferLegacyRuntimeLinear
        let effectiveDiscardCollisionOutput = config.discardCollisionOutput && !preferLegacyRuntimeLinear
        let frameResources = Resources.makeFrameResources(
            device: device,
            config: config,
            params: params,
            policy: policy,
            useInMemoryCollisions: effectiveUseInMemoryCollisions,
            useLinear32Intermediate: effectiveUseLinear32Intermediate,
            width: config.width,
            height: config.height,
            composeExposure: config.composeExposure,
            composeLookID: config.composeLookID,
            spectralEncodingID: config.spectralEncodingID,
            composePrecisionID: config.composePrecisionID,
            composeAnalysisMode: config.composeAnalysisMode,
            composeCameraModelID: config.composeCameraModelID,
            composeCameraPsfSigmaArg: config.composeCameraPsfSigmaArg,
            composeCameraReadNoiseArg: config.composeCameraReadNoiseArg,
            composeCameraShotNoiseArg: config.composeCameraShotNoiseArg,
            composeCameraFlareStrengthArg: config.composeCameraFlareStrengthArg,
            backgroundModeID: config.backgroundModeID,
            backgroundStarDensityArg: config.backgroundStarDensityArg,
            backgroundStarStrengthArg: config.backgroundStarStrengthArg,
            backgroundNebulaStrengthArg: config.backgroundNebulaStrengthArg,
            preserveHighlightColor: config.preserveHighlightColor,
            downsampleArg: config.downsampleArg,
            composeDitherArg: config.composeDitherArg,
            composeInnerEdgeArg: config.composeInnerEdgeArg,
            composeSpectralStepArg: config.composeSpectralStepArg,
            tileSize: config.tileSize,
            traceInFlightOverrideArg: config.traceInFlightOverrideArg
        )

        let directLinearEnabled = frameResources.directLinearTraceBuf != nil
        let inMemoryCollisionLiteEnabled = policy.inMemoryCollisionLiteEnabled(directLinearEnabled: directLinearEnabled)
        let collisionLite32Enabled = policy.collisionLite32Enabled(
            directLinearEnabled: directLinearEnabled,
            useLinear32Intermediate: effectiveUseLinear32Intermediate
        )

        if effectiveDiscardCollisionOutput && !(effectiveUseInMemoryCollisions || effectiveUseLinear32Intermediate) {
            fail("--discard-collisions/--skip-collision-dump is only supported with --gpu-full-compose/--compose-in-memory or --linear32-intermediate/--hdr-intermediate")
        }

        let tracePathSummary = policy.tracePathSummary(
            directLinearEnabled: directLinearEnabled,
            collisionLite32Enabled: collisionLite32Enabled,
            inMemoryCollisionLiteEnabled: inMemoryCollisionLiteEnabled,
            useLinear32Intermediate: effectiveUseLinear32Intermediate
        )
        print("trace path=\(tracePathSummary)")

        var linearOutHandle: FileHandle? = nil
        if effectiveUseLinear32Intermediate {
            _ = FileManager.default.createFile(atPath: frameResources.linearOutputURL.path, contents: nil)
            linearOutHandle = try FileHandle(forWritingTo: frameResources.linearOutputURL)
        }
        var outHandle: FileHandle? = nil
        if !effectiveUseInMemoryCollisions && !effectiveDiscardCollisionOutput && !effectiveUseLinear32Intermediate {
            _ = FileManager.default.createFile(atPath: frameResources.outputURL.path, contents: nil)
            outHandle = try FileHandle(forWritingTo: frameResources.outputURL)
            try outHandle?.truncate(atOffset: UInt64(policy.outSize))
        }
        defer {
            try? outHandle?.close()
            try? linearOutHandle?.close()
        }

        let tg = MTLSize(width: 16, height: 16, depth: 1)
        let dsForTile = config.composeGPU ? config.downsampleArg : 1
        let alignedTile = max(dsForTile, (max(1, config.tileSize) / dsForTile) * dsForTile)
        let effectiveTile = alignedTile
        if effectiveTile < max(config.width, config.height) {
            print("tile rendering enabled: \(effectiveTile)x\(effectiveTile)")
        }
        let traceTilesX = max(1, (config.width + effectiveTile - 1) / effectiveTile)
        let traceTilesY = max(1, (config.height + effectiveTile - 1) / effectiveTile)
        let traceTileTotal = max(1, traceTilesX * traceTilesY)

        let activeTracePipeline: MTLComputePipelineState = {
            if directLinearEnabled { return runtime.traceLinearPipeline }
            if collisionLite32Enabled { return runtime.traceLitePipeline }
            return runtime.tracePipeline
        }()
        let activeComposeLinearTilePipeline = collisionLite32Enabled ? runtime.composeLinearTileLitePipeline : runtime.composeLinearTilePipeline
        let tgLinearTile1D = MTLSize(width: max(1, min(256, activeComposeLinearTilePipeline.maxTotalThreadsPerThreadgroup)), height: 1, depth: 1)

        let totalPixels = policy.count
        let composePrepassOpsTarget: Int
        if config.composeGPU && effectiveGpuFullCompose && config.autoExposureEnabled {
            composePrepassOpsTarget = 2 * policy.count
        } else if config.composeGPU && effectiveUseLinear32Intermediate && config.autoExposureEnabled {
            composePrepassOpsTarget = policy.count
        } else {
            composePrepassOpsTarget = 0
        }
        let composeOps = config.composeGPU ? (composePrepassOpsTarget + policy.outWidth * policy.outHeight) : 0
        let totalOps = totalPixels + composeOps
        let progressStep = max(1, totalOps / 256)

        print("trace in-flight=\(frameResources.maxInFlight), slotBytes=\(frameResources.slotBytes), tiles=\(traceTileTotal)")

        let traceResult = try RenderTracePhase.execute(
            RenderTracePhaseInput(
                queue: queue,
                params: params,
                width: config.width,
                height: config.height,
                effectiveTile: effectiveTile,
                traceTileTotal: traceTileTotal,
                traceTilesX: traceTilesX,
                traceTilesY: traceTilesY,
                tg: tg,
                tgLinearTile1D: tgLinearTile1D,
                traceSlots: frameResources.traceSlots,
                maxInFlight: frameResources.maxInFlight,
                totalPixels: totalPixels,
                totalOps: totalOps,
                progressStep: progressStep,
                useLinear32Intermediate: effectiveUseLinear32Intermediate,
                useInMemoryCollisions: effectiveUseInMemoryCollisions,
                directLinearEnabled: directLinearEnabled,
                collisionLite32Enabled: collisionLite32Enabled,
                discardCollisionOutput: effectiveDiscardCollisionOutput,
                traceStride: frameResources.traceStride,
                linearStride: policy.linearStride,
                linearCloudBins: 2048,
                linearLumBins: 4096,
                linearLumLogMin: (config.diskPhysicsModeID == 3) ? -36.0 : 8.0,
                linearLumLogMax: (config.diskPhysicsModeID == 3) ? 4.0 : 20.0,
                composeExposure: config.composeExposure,
                composeDitherArg: config.composeDitherArg,
                composeInnerEdgeArg: config.composeInnerEdgeArg,
                composeSpectralStepArg: config.composeSpectralStepArg,
                composeLookID: config.composeLookID,
                spectralEncodingID: config.spectralEncodingID,
                composePrecisionID: config.composePrecisionID,
                composeAnalysisMode: config.composeAnalysisMode,
                composeCameraModelID: config.composeCameraModelID,
                composeCameraPsfSigmaArg: config.composeCameraPsfSigmaArg,
                composeCameraReadNoiseArg: config.composeCameraReadNoiseArg,
                composeCameraShotNoiseArg: config.composeCameraShotNoiseArg,
                composeCameraFlareStrengthArg: config.composeCameraFlareStrengthArg,
                backgroundModeID: config.backgroundModeID,
                backgroundStarDensityArg: config.backgroundStarDensityArg,
                backgroundStarStrengthArg: config.backgroundStarStrengthArg,
                backgroundNebulaStrengthArg: config.backgroundNebulaStrengthArg,
                preserveHighlightColor: config.preserveHighlightColor,
                directLinearParamBuf: frameResources.directLinearParamBuf,
                directLinearTraceBuf: frameResources.directLinearTraceBuf,
                directLinearHitCountBuf: frameResources.directLinearHitCountBuf,
                composeBaseBufForLinear: frameResources.composeBaseBufForLinear,
                collisionBuffer: frameResources.collisionBuffer,
                collisionBase: frameResources.collisionBase,
                outHandle: outHandle,
                linearOutHandle: linearOutHandle,
                tracePipeline: activeTracePipeline,
                composeLinearTilePipeline: activeComposeLinearTilePipeline,
                diskAtlasTex: runtime.diskAtlasTex,
                diskVol0Tex: runtime.diskVol0Tex,
                diskVol1Tex: runtime.diskVol1Tex
            )
        )

        let composeResult = try RenderComposePhase.execute(
            RenderComposePhaseInput(
                config: config,
                params: params,
                runtime: runtime,
                policy: policy,
                frameResources: frameResources,
                directLinearEnabled: directLinearEnabled,
                collisionLite32Enabled: collisionLite32Enabled,
                traceResult: traceResult,
                effectiveTile: effectiveTile,
                totalPixels: totalPixels,
                totalOps: totalOps,
                progressStep: progressStep,
                effectiveGpuFullCompose: effectiveGpuFullCompose,
                effectiveUseLinear32Intermediate: effectiveUseLinear32Intermediate,
                effectiveUseInMemoryCollisions: effectiveUseInMemoryCollisions
            )
        )

        if effectiveUseInMemoryCollisions && !effectiveDiscardCollisionOutput && !effectiveUseLinear32Intermediate {
            guard let collisionBase = frameResources.collisionBase else {
                fail("in-memory collision buffer unexpectedly missing at flush")
            }
            try writeRawBuffer(to: frameResources.outputURL, sourceBase: UnsafeRawPointer(collisionBase), byteCount: policy.outSize)
        }

        let meta = RenderOutputs.makeMeta(
            config: config,
            composeExposure: composeResult.composeExposure,
            effectiveTile: effectiveTile,
            outWidth: policy.outWidth,
            outHeight: policy.outHeight,
            collisionStride: frameResources.traceStride
        )
        try RenderOutputs.writeMetadata(
            meta: meta,
            outPath: config.outPath,
            linear32OutPath: config.linear32OutPath,
            useLinear32Intermediate: effectiveUseLinear32Intermediate,
            discardCollisionOutput: effectiveDiscardCollisionOutput,
            outSize: policy.outSize,
            linearOutSize: policy.linearOutSize,
            hitCount: traceResult.hitCount
        )
    }
}
