import Foundation
import Metal

struct RenderExecutionFlags {
    let preferLegacyRuntimeLinear: Bool
    let effectiveGpuFullCompose: Bool
    let effectiveUseDirectLinear: Bool
    let effectiveUseLinear32Intermediate: Bool
    let effectiveUseInMemoryCollisions: Bool
    let effectiveDiscardCollisionOutput: Bool
}

enum RenderIntermediateKind: String {
    case hdr32DirectFullFrame
    case collisionLite32FullFrame
    case collision64FullFrame
    case collisionLite32TileToHDRFile
    case collision64TileToHDRFile
    case collisionLite32TileToCollisionFile
    case collision64TileToCollisionFile
}

struct RenderIntermediatePlan {
    let kind: RenderIntermediateKind
    let summary: String
    let persistentIntermediateBytes: Int
    let fullFrameCollisionBytes: Int
    let fullFrameLinearBytes: Int
    let fullFrameOutputBytes: Int
    let assetTextureBytes: Int
    let traceSlotBytes: Int
    let maxInFlight: Int
    let estimatedPeakBytes: Int
    let workingSetCapBytes: Int
}

struct RenderExecutionPlan {
    let flags: RenderExecutionFlags
    let intermediatePlan: RenderIntermediatePlan
    let directLinearEnabled: Bool
    let inMemoryCollisionLiteEnabled: Bool
    let collisionLite32Enabled: Bool
    let tracePathSummary: String
    let effectiveTile: Int
    let traceTilesX: Int
    let traceTilesY: Int
    let traceTileTotal: Int
    let activeTracePipeline: MTLComputePipelineState
    let activeComposeLinearTilePipeline: MTLComputePipelineState
    let tg: MTLSize
    let tgLinearTile1D: MTLSize
    let totalPixels: Int
    let composePrepassOpsTarget: Int
    let composeOps: Int
    let totalOps: Int
    let progressStep: Int
}

enum RenderExecutionPlanning {
    static func makeFlags(
        config: ResolvedRenderConfig,
        policy: RenderResourcePolicy
    ) -> RenderExecutionFlags {
        let preferLegacyRuntimeLinear =
            !policy.directLinearAllowed() &&
            policy.composeStrategyPreference == .tileFirst &&
            config.composeGPU &&
            !config.visibleModeEnabled &&
            !config.rayBundleActive &&
            config.composeAnalysisMode == 0

        let effectiveUseDirectLinear = policy.directLinearAllowed()
        let effectiveGpuFullCompose = (config.gpuFullCompose && !preferLegacyRuntimeLinear) || effectiveUseDirectLinear
        let effectiveUseLinear32Intermediate = config.useLinear32Intermediate && !effectiveUseDirectLinear
        let effectiveUseInMemoryCollisions =
            policy.useInMemoryCollisions && !effectiveUseDirectLinear && !effectiveUseLinear32Intermediate && !preferLegacyRuntimeLinear
        let effectiveDiscardCollisionOutput = config.discardCollisionOutput && (!preferLegacyRuntimeLinear || effectiveUseDirectLinear)

        return RenderExecutionFlags(
            preferLegacyRuntimeLinear: preferLegacyRuntimeLinear,
            effectiveGpuFullCompose: effectiveGpuFullCompose,
            effectiveUseDirectLinear: effectiveUseDirectLinear,
            effectiveUseLinear32Intermediate: effectiveUseLinear32Intermediate,
            effectiveUseInMemoryCollisions: effectiveUseInMemoryCollisions,
            effectiveDiscardCollisionOutput: effectiveDiscardCollisionOutput
        )
    }

    static func makePlan(
        config: ResolvedRenderConfig,
        params: PackedParams,
        runtime: RenderRuntime,
        policy: RenderResourcePolicy,
        frameResources: RenderFrameResources
    ) -> RenderExecutionPlan {
        let flags = makeFlags(config: config, policy: policy)

        let directLinearEnabled = frameResources.directLinearTraceBuf != nil
        let inMemoryCollisionLiteEnabled = policy.inMemoryCollisionLiteEnabled(directLinearEnabled: directLinearEnabled)
        let collisionLite32Enabled = policy.collisionLite32Enabled(
            directLinearEnabled: directLinearEnabled,
            useLinear32Intermediate: flags.effectiveUseLinear32Intermediate
        )
        let tracePathSummary = policy.tracePathSummary(
            directLinearEnabled: directLinearEnabled,
            collisionLite32Enabled: collisionLite32Enabled,
            inMemoryCollisionLiteEnabled: inMemoryCollisionLiteEnabled,
            effectiveUseInMemoryCollisions: flags.effectiveUseInMemoryCollisions,
            useLinear32Intermediate: flags.effectiveUseLinear32Intermediate
        )
        let intermediatePlan = makeIntermediatePlan(
            policy: policy,
            frameResources: frameResources,
            flags: flags,
            directLinearEnabled: directLinearEnabled,
            collisionLite32Enabled: collisionLite32Enabled,
            inMemoryCollisionLiteEnabled: inMemoryCollisionLiteEnabled,
            tracePathSummary: tracePathSummary
        )

        let dsForTile = config.composeGPU ? config.downsampleArg : 1
        let alignedTile = max(dsForTile, (max(1, config.tileSize) / dsForTile) * dsForTile)
        let effectiveTile = alignedTile
        let traceTilesX = max(1, (config.width + effectiveTile - 1) / effectiveTile)
        let traceTilesY = max(1, (config.height + effectiveTile - 1) / effectiveTile)
        let traceTileTotal = max(1, traceTilesX * traceTilesY)

        let activeTracePipeline: MTLComputePipelineState = {
            if directLinearEnabled { return runtime.traceLinearPipeline }
            if collisionLite32Enabled { return runtime.traceLitePipeline }
            return runtime.tracePipeline
        }()
        // Threadgroup shape for the register-heavy geodesic trace. A square 8×8
        // (two SIMD groups on Apple silicon) was best-or-tied at every real GUI
        // resolution (112→480) in the ground-truth sweep; other small shapes each
        // collapse somewhere (16×2 ~20% on the smallest frames, 16×4 ~9% at 480),
        // and the previous 32×8 left 20-40% on the table. The shape is pure work
        // partitioning — it never enters per-pixel math, so output bytes are
        // identical for any shape (a warm-up autotune probe was prototyped and
        // dropped: at real resolutions the 1-3% shape effect sits well under the
        // ~20% thermal/DVFS noise of any in-process measurement, so it tuned on
        // noise). BH_TRACE_TG_WIDTH/HEIGHT override the shape for benchmarking.
        let traceThreadWidth = max(1, activeTracePipeline.threadExecutionWidth)
        let traceMaxThreads = max(1, activeTracePipeline.maxTotalThreadsPerThreadgroup)
        var tgWidth = max(1, min(traceThreadWidth / 4, traceMaxThreads))
        var tgHeight = max(1, min(traceThreadWidth / 4, traceMaxThreads / tgWidth))
        if let ws = ProcessInfo.processInfo.environment["BH_TRACE_TG_WIDTH"], let w = Int(ws), w >= 1 {
            tgWidth = w
        }
        if let hs = ProcessInfo.processInfo.environment["BH_TRACE_TG_HEIGHT"], let h = Int(hs), h >= 1 {
            tgHeight = h
        }
        if tgWidth * tgHeight > traceMaxThreads { tgHeight = max(1, traceMaxThreads / max(tgWidth, 1)) }
        let tg = MTLSize(width: tgWidth, height: tgHeight, depth: 1)

        let activeComposeLinearTilePipeline =
            collisionLite32Enabled ? runtime.composeLinearTileLitePipeline : runtime.composeLinearTilePipeline
        let tgLinearTile1D = MTLSize(
            width: max(1, min(256, activeComposeLinearTilePipeline.maxTotalThreadsPerThreadgroup)),
            height: 1,
            depth: 1
        )

        let totalPixels = policy.count
        let composePrepassOpsTarget: Int
        if config.composeGPU && flags.effectiveGpuFullCompose && config.autoExposureEnabled {
            composePrepassOpsTarget = 2 * policy.count
        } else if config.composeGPU && flags.effectiveUseLinear32Intermediate && config.autoExposureEnabled {
            composePrepassOpsTarget = policy.count
        } else {
            composePrepassOpsTarget = 0
        }
        let composeOps = config.composeGPU ? (composePrepassOpsTarget + policy.outWidth * policy.outHeight) : 0
        let totalOps = totalPixels + composeOps
        let progressStep = max(1, totalOps / 256)

        return RenderExecutionPlan(
            flags: flags,
            intermediatePlan: intermediatePlan,
            directLinearEnabled: directLinearEnabled,
            inMemoryCollisionLiteEnabled: inMemoryCollisionLiteEnabled,
            collisionLite32Enabled: collisionLite32Enabled,
            tracePathSummary: tracePathSummary,
            effectiveTile: effectiveTile,
            traceTilesX: traceTilesX,
            traceTilesY: traceTilesY,
            traceTileTotal: traceTileTotal,
            activeTracePipeline: activeTracePipeline,
            activeComposeLinearTilePipeline: activeComposeLinearTilePipeline,
            tg: tg,
            tgLinearTile1D: tgLinearTile1D,
            totalPixels: totalPixels,
            composePrepassOpsTarget: composePrepassOpsTarget,
            composeOps: composeOps,
            totalOps: totalOps,
            progressStep: progressStep
        )
    }

    private static func makeIntermediatePlan(
        policy: RenderResourcePolicy,
        frameResources: RenderFrameResources,
        flags: RenderExecutionFlags,
        directLinearEnabled: Bool,
        collisionLite32Enabled: Bool,
        inMemoryCollisionLiteEnabled: Bool,
        tracePathSummary: String
    ) -> RenderIntermediatePlan {
        let kind: RenderIntermediateKind
        if directLinearEnabled {
            kind = .hdr32DirectFullFrame
        } else if flags.effectiveUseInMemoryCollisions {
            kind = inMemoryCollisionLiteEnabled ? .collisionLite32FullFrame : .collision64FullFrame
        } else if flags.effectiveUseLinear32Intermediate {
            kind = collisionLite32Enabled ? .collisionLite32TileToHDRFile : .collision64TileToHDRFile
        } else {
            kind = collisionLite32Enabled ? .collisionLite32TileToCollisionFile : .collision64TileToCollisionFile
        }

        let fullFrameCollisionBytes = directLinearEnabled ? 0 : frameResources.collisionStorageSize
        let fullFrameLinearBytes = policy.linearOutSize
        let fullFrameOutputBytes = policy.fullComposeOutBytes
        let persistentIntermediateBytes: Int = {
            switch kind {
            case .hdr32DirectFullFrame:
                return policy.linearOutSize
            case .collisionLite32FullFrame, .collision64FullFrame:
                return frameResources.collisionStorageSize
            case .collisionLite32TileToHDRFile, .collision64TileToHDRFile:
                return 0
            case .collisionLite32TileToCollisionFile, .collision64TileToCollisionFile:
                return 0
            }
        }()
        let estimatedPeakBytes =
            persistentIntermediateBytes +
            policy.approxTextureBytes +
            policy.fullComposeOutBytes +
            frameResources.slotBytes * frameResources.maxInFlight

        return RenderIntermediatePlan(
            kind: kind,
            summary: tracePathSummary,
            persistentIntermediateBytes: persistentIntermediateBytes,
            fullFrameCollisionBytes: fullFrameCollisionBytes,
            fullFrameLinearBytes: fullFrameLinearBytes,
            fullFrameOutputBytes: fullFrameOutputBytes,
            assetTextureBytes: policy.approxTextureBytes,
            traceSlotBytes: frameResources.slotBytes,
            maxInFlight: frameResources.maxInFlight,
            estimatedPeakBytes: estimatedPeakBytes,
            workingSetCapBytes: policy.workingSetCap
        )
    }
}
