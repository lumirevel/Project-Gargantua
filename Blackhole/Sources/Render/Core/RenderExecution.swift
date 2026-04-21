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
        if config.traceHDRDirectMode == "on" && !policy.directLinearTraceSafe {
            print("warn: --trace-hdr-direct on ignored: \(policy.directLinearUnsafeReason)")
        }
        let flags = RenderExecutionPlanning.makeFlags(config: config, policy: policy)
        let frameResources = Resources.makeFrameResources(
            device: device,
            config: config,
            params: params,
            policy: policy,
            useDirectLinear: flags.effectiveUseDirectLinear,
            useInMemoryCollisions: flags.effectiveUseInMemoryCollisions,
            useLinear32Intermediate: flags.effectiveUseLinear32Intermediate,
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

        let plan = RenderExecutionPlanning.makePlan(
            config: config,
            params: params,
            runtime: runtime,
            policy: policy,
            frameResources: frameResources
        )

        if plan.flags.effectiveDiscardCollisionOutput && !(plan.directLinearEnabled || plan.flags.effectiveUseInMemoryCollisions || plan.flags.effectiveUseLinear32Intermediate) {
            fail("--discard-collisions/--skip-collision-dump is only supported with --gpu-full-compose/--compose-in-memory or --linear32-intermediate/--hdr-intermediate")
        }

        print("trace path=\(plan.tracePathSummary)")
        print(memoryPlanSummary(plan.intermediatePlan))

        var linearOutHandle: FileHandle? = nil
        if plan.flags.effectiveUseLinear32Intermediate {
            _ = FileManager.default.createFile(atPath: frameResources.linearOutputURL.path, contents: nil)
            linearOutHandle = try FileHandle(forWritingTo: frameResources.linearOutputURL)
            try linearOutHandle?.truncate(atOffset: UInt64(policy.linearOutSize))
        }
        var outHandle: FileHandle? = nil
        if !plan.flags.effectiveUseInMemoryCollisions && !plan.flags.effectiveDiscardCollisionOutput && !plan.flags.effectiveUseLinear32Intermediate {
            _ = FileManager.default.createFile(atPath: frameResources.outputURL.path, contents: nil)
            outHandle = try FileHandle(forWritingTo: frameResources.outputURL)
            try outHandle?.truncate(atOffset: UInt64(frameResources.collisionStorageSize))
        }
        defer {
            try? outHandle?.close()
            try? linearOutHandle?.close()
        }

        if plan.effectiveTile < max(config.width, config.height) {
            print("tile rendering enabled: \(plan.effectiveTile)x\(plan.effectiveTile)")
        }
        print("trace in-flight=\(frameResources.maxInFlight), slotBytes=\(frameResources.slotBytes), tiles=\(plan.traceTileTotal)")

        let traceResult = try RenderTracePhase.execute(
            RenderTracePhaseInput(
                queue: queue,
                params: params,
                width: config.width,
                height: config.height,
                effectiveTile: plan.effectiveTile,
                traceTileTotal: plan.traceTileTotal,
                traceTilesX: plan.traceTilesX,
                traceTilesY: plan.traceTilesY,
                tg: plan.tg,
                tgLinearTile1D: plan.tgLinearTile1D,
                traceSlots: frameResources.traceSlots,
                maxInFlight: frameResources.maxInFlight,
                totalPixels: plan.totalPixels,
                totalOps: plan.totalOps,
                progressStep: plan.progressStep,
                useLinear32Intermediate: plan.flags.effectiveUseLinear32Intermediate,
                useInMemoryCollisions: plan.flags.effectiveUseInMemoryCollisions,
                directLinearEnabled: plan.directLinearEnabled,
                collisionLite32Enabled: plan.collisionLite32Enabled,
                discardCollisionOutput: plan.flags.effectiveDiscardCollisionOutput,
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
                tracePipeline: plan.activeTracePipeline,
                composeLinearTilePipeline: plan.activeComposeLinearTilePipeline,
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
                directLinearEnabled: plan.directLinearEnabled,
                collisionLite32Enabled: plan.collisionLite32Enabled,
                traceResult: traceResult,
                effectiveTile: plan.effectiveTile,
                totalPixels: plan.totalPixels,
                totalOps: plan.totalOps,
                progressStep: plan.progressStep,
                effectiveGpuFullCompose: plan.flags.effectiveGpuFullCompose,
                effectiveUseLinear32Intermediate: plan.flags.effectiveUseLinear32Intermediate,
                effectiveUseInMemoryCollisions: plan.flags.effectiveUseInMemoryCollisions
            )
        )

        if plan.flags.effectiveUseInMemoryCollisions && !plan.flags.effectiveDiscardCollisionOutput && !plan.flags.effectiveUseLinear32Intermediate {
            guard let collisionBase = frameResources.collisionBase else {
                fail("in-memory collision buffer unexpectedly missing at flush")
            }
            try writeRawBuffer(to: frameResources.outputURL, sourceBase: UnsafeRawPointer(collisionBase), byteCount: frameResources.collisionStorageSize)
        }

        let meta = RenderOutputs.makeMeta(
            config: config,
            composeExposure: composeResult.composeExposure,
            effectiveTile: plan.effectiveTile,
            outWidth: policy.outWidth,
            outHeight: policy.outHeight,
            collisionStride: frameResources.traceStride
        )
        try RenderOutputs.writeMetadata(
            meta: meta,
            outPath: config.outPath,
            linear32OutPath: config.linear32OutPath,
            useLinear32Intermediate: plan.flags.effectiveUseLinear32Intermediate,
            discardCollisionOutput: plan.flags.effectiveDiscardCollisionOutput,
            outSize: frameResources.collisionStorageSize,
            linearOutSize: policy.linearOutSize,
            hitCount: traceResult.hitCount
        )
    }

    private static func memoryPlanSummary(_ plan: RenderIntermediatePlan) -> String {
        let cap = plan.workingSetCapBytes > 0 ? formatBytes(plan.workingSetCapBytes) : "unknown"
        return [
            "memory plan=\(plan.kind.rawValue)",
            "persistentIntermediate=\(formatBytes(plan.persistentIntermediateBytes))",
            "collisionFull=\(formatBytes(plan.fullFrameCollisionBytes))",
            "hdrFull=\(formatBytes(plan.fullFrameLinearBytes))",
            "rgbaOut=\(formatBytes(plan.fullFrameOutputBytes))",
            "assets=\(formatBytes(plan.assetTextureBytes))",
            "traceSlots=\(plan.maxInFlight)x\(formatBytes(plan.traceSlotBytes))",
            "estimatedPeak=\(formatBytes(plan.estimatedPeakBytes))",
            "workingSetCap=\(cap)"
        ].joined(separator: ", ")
    }

    private static func formatBytes(_ bytes: Int) -> String {
        if bytes <= 0 { return "0 B" }
        let units = ["B", "KiB", "MiB", "GiB"]
        var value = Double(bytes)
        var unitIndex = 0
        while value >= 1024.0 && unitIndex < units.count - 1 {
            value /= 1024.0
            unitIndex += 1
        }
        if unitIndex == 0 {
            return "\(bytes) B"
        }
        return String(format: "%.1f %@", value, units[unitIndex])
    }
}
