import Foundation
import Metal

enum RenderExecution {
    static func composeHDRInput(config: ResolvedRenderConfig, params inputParams: PackedParams, runtime: RenderRuntime) throws {
        let params = inputParams
        let policy = RenderResourcePolicy(config: config, params: params, device: runtime.device)
        let expectedBytes = policy.linearOutSize
        let inputURL = URL(fileURLWithPath: config.composeHDRInputPath)
        let attrs = try FileManager.default.attributesOfItem(atPath: inputURL.path)
        let fileBytes = (attrs[.size] as? NSNumber)?.intValue ?? 0
        guard fileBytes == expectedBytes else {
            throw NSError(
                domain: "Blackhole",
                code: 82,
                userInfo: [NSLocalizedDescriptionKey: "--compose-hdr-in size mismatch: got \(fileBytes), expected \(expectedBytes) for \(config.width)x\(config.height) float4 linear32"]
            )
        }

        print(config.renderConfigLine)
        if !config.grmhdConfigLine.isEmpty { print(config.grmhdConfigLine) }
        if !config.visibleConfigLine.isEmpty { print(config.visibleConfigLine) }
        print("compose-only hdr input=\(inputURL.path)")

        let frameResources = Resources.makeFrameResources(
            device: runtime.device,
            config: config,
            params: params,
            policy: policy,
            useDirectLinear: false,
            useInMemoryCollisions: false,
            useLinear32Intermediate: true,
            width: config.width,
            height: config.height,
            composeExposure: config.composeExposure,
            composeLookID: config.composeLookID,
            spectralEncodingID: config.spectralEncodingID,
            composePrecisionID: config.composePrecisionID,
            composeAnalysisMode: config.composeAnalysisMode,
            composeCameraModelID: config.composeCameraModelID,
            cameraProfileID: (config.composeAnalysisMode == 0) ? config.cameraProfileID : 0,
            realismProfileID: config.realismProfileID,
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

        let totalPixels = policy.count
        let composePrepassOps = config.autoExposureEnabled ? totalPixels : 0
        let composeOps = composePrepassOps + policy.outWidth * policy.outHeight
        let totalOps = max(1, totalPixels + composeOps)
        let progressStep = max(1, totalOps / 256)
        let traceResult = RenderTracePhaseResult(
            hitCount: totalPixels,
            donePixels: totalPixels,
            nextProgressMark: progressStep,
            lastProgressPrint: Date().timeIntervalSince1970,
            linearCloudHistGlobal: [UInt32](repeating: 0, count: 2048),
            linearCloudSampleCount: 0
        )

        let result = try RenderComposeHDRIntermediatePhase.execute(
            RenderComposePhaseInput(
                config: config,
                params: params,
                runtime: runtime,
                policy: policy,
                frameResources: frameResources,
                directLinearEnabled: false,
                collisionLite32Enabled: false,
                traceResult: traceResult,
                effectiveTile: config.tileSize,
                totalPixels: totalPixels,
                totalOps: totalOps,
                progressStep: progressStep,
                effectiveGpuFullCompose: false,
                effectiveUseLinear32Intermediate: true,
                effectiveUseInMemoryCollisions: false
            ),
            composeExposure: config.composeExposure,
            nextProgressMark: progressStep,
            lastProgressPrint: Date().timeIntervalSince1970
        )
        print("compose-only exposure=\(result.composeExposure)")
        print("compose-only image=\(config.imageOutPath)")
    }

    /// Per-call render context: the policy / Metal resources / execution plan /
    /// file handles derived from a (config, resolution). The one-shot final render
    /// builds one, runs a single frame, and closes it. The warm `--serve` loop
    /// reuses one across frames while only the camera pose changes, rebuilding only
    /// when the frame dimensions change — for the preview path these resources do
    /// not depend on the camera (they are sized buffers + pipelines), so reuse is
    /// safe and skips the per-frame Metal allocation churn.
    struct RenderFrameContext {
        let policy: RenderResourcePolicy
        let frameResources: RenderFrameResources
        let plan: RenderExecutionPlan
        let outHandle: FileHandle?
        let linearOutHandle: FileHandle?
        let width: Int
        let height: Int
        func close() {
            try? outHandle?.close()
            try? linearOutHandle?.close()
        }
    }

    /// One-shot render: build a context, run a single frame, close. `quiet`
    /// suppresses the per-frame diagnostic prints (used by the warm serve loop so
    /// it does not spam the stdout pipe the GUI parses). Default `false` keeps the
    /// final render's output byte-for-byte and log-for-log identical.
    static func execute(config: ResolvedRenderConfig, params inputParams: PackedParams, runtime: RenderRuntime, quiet: Bool = false) throws {
        let context = try makeFrameContext(config: config, params: inputParams, runtime: runtime, quiet: quiet)
        defer { context.close() }
        try runFrame(context, config: config, params: inputParams, runtime: runtime, quiet: quiet)
    }

    /// Build the resolution-derived render context (policy, Metal resources, plan,
    /// output file handles). Invariant under camera-only changes.
    static func makeFrameContext(config: ResolvedRenderConfig, params inputParams: PackedParams, runtime: RenderRuntime, quiet: Bool = false) throws -> RenderFrameContext {
        let device = runtime.device
        let params = inputParams

        if !quiet {
            print(config.renderConfigLine)
            if !config.grmhdConfigLine.isEmpty { print(config.grmhdConfigLine) }
            if !config.visibleConfigLine.isEmpty { print(config.visibleConfigLine) }
        }

        let policy = RenderResourcePolicy(config: config, params: params, device: device)
        if config.traceHDRDirectMode == "on" && !policy.directLinearTraceSafe {
            if !quiet { print("warn: --trace-hdr-direct on ignored: \(policy.directLinearUnsafeReason)") }
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
            cameraProfileID: (config.composeAnalysisMode == 0) ? config.cameraProfileID : 0,
            realismProfileID: config.realismProfileID,
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

        if !quiet {
            print("trace path=\(plan.tracePathSummary)")
            print(memoryPlanSummary(plan.intermediatePlan))
        }

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

        if !quiet {
            if plan.effectiveTile < max(config.width, config.height) {
                print("tile rendering enabled: \(plan.effectiveTile)x\(plan.effectiveTile)")
            }
            print("trace in-flight=\(frameResources.maxInFlight), slotBytes=\(frameResources.slotBytes), tiles=\(plan.traceTileTotal)")
        }

        return RenderFrameContext(
            policy: policy,
            frameResources: frameResources,
            plan: plan,
            outHandle: outHandle,
            linearOutHandle: linearOutHandle,
            width: config.width,
            height: config.height
        )
    }

    /// Run a single frame against an existing context: trace + compose + write +
    /// metadata. The context (resources/plan) is reused across warm serve frames.
    static func runFrame(_ context: RenderFrameContext, config: ResolvedRenderConfig, params inputParams: PackedParams, runtime: RenderRuntime, quiet: Bool = false) throws {
        let queue = runtime.queue
        let params = inputParams
        let policy = context.policy
        let frameResources = context.frameResources
        let plan = context.plan
        let outHandle = context.outHandle
        let linearOutHandle = context.linearOutHandle

        let makeTraceInput: (PackedParams) -> RenderTracePhaseInput = { traceParams in
            RenderTracePhaseInput(
                queue: queue,
                params: traceParams,
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
                linearLumLogMin: composeLuminanceLogRange(diskPhysicsModeID: config.diskPhysicsModeID).min,
                linearLumLogMax: composeLuminanceLogRange(diskPhysicsModeID: config.diskPhysicsModeID).max,
                composeExposure: config.composeExposure,
                composeDitherArg: config.composeDitherArg,
                composeInnerEdgeArg: config.composeInnerEdgeArg,
                composeSpectralStepArg: config.composeSpectralStepArg,
                composeLookID: config.composeLookID,
                spectralEncodingID: config.spectralEncodingID,
                composePrecisionID: config.composePrecisionID,
                composeAnalysisMode: config.composeAnalysisMode,
                composeCameraModelID: config.composeCameraModelID,
                cameraProfileID: (config.composeAnalysisMode == 0) ? config.cameraProfileID : 0,
                realismProfileID: config.realismProfileID,
                cameraSceneR: config.cameraSceneR,
                cameraSceneG: config.cameraSceneG,
                cameraSceneB: config.cameraSceneB,
                cameraDisplayR: config.cameraDisplayR,
                cameraDisplayG: config.cameraDisplayG,
                cameraDisplayB: config.cameraDisplayB,
                cameraSensorParams: config.cameraSensorParams,
                cameraNoiseParams: config.cameraNoiseParams,
                cameraColorParams: config.cameraColorParams,
                cameraGlareParams: config.cameraGlareParams,
                cameraFlags: config.cameraFlags,
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
        }

        let traceResult: RenderTracePhaseResult
        if config.taaSamplesArg > 1 && plan.flags.effectiveUseLinear32Intermediate {
            print("taa: temporal anti-aliasing enabled, samples=\(config.taaSamplesArg) (sub-pixel jitter, linear-HDR accumulation)")
            traceResult = try RenderTAAAccumulation.run(
                samples: config.taaSamplesArg,
                params: params,
                width: config.width,
                height: config.height,
                linearStride: policy.linearStride,
                linearURL: frameResources.linearOutputURL,
                linearOutHandle: linearOutHandle,
                makeTraceInput: makeTraceInput
            )
        } else {
            if config.taaSamplesArg > 1 {
                print("warn: --taa-samples \(config.taaSamplesArg) ignored (requires the HDR intermediate compose path); rendering a single pass")
            }
            traceResult = try RenderTracePhase.execute(makeTraceInput(params))
        }

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
