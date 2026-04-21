import Foundation
import Metal

struct RenderComposePhaseInput {
    let config: ResolvedRenderConfig
    let params: PackedParams
    let runtime: RenderRuntime
    let policy: RenderResourcePolicy
    let frameResources: RenderFrameResources
    let directLinearEnabled: Bool
    let collisionLite32Enabled: Bool
    let traceResult: RenderTracePhaseResult
    let effectiveTile: Int
    let totalPixels: Int
    let totalOps: Int
    let progressStep: Int
    let effectiveGpuFullCompose: Bool
    let effectiveUseLinear32Intermediate: Bool
    let effectiveUseInMemoryCollisions: Bool
}

struct RenderComposePhaseResult {
    let composeExposure: Float
    let nextProgressMark: Int
    let lastProgressPrint: TimeInterval
}

enum RenderComposePhase {
    static func execute(_ input: RenderComposePhaseInput) throws -> RenderComposePhaseResult {
        let config = input.config
        let composeGPU = config.composeGPU
        let gpuFullCompose = input.effectiveGpuFullCompose
        let useLinear32Intermediate = input.effectiveUseLinear32Intermediate
        var composeExposure = config.composeExposure
        var nextProgressMark = input.traceResult.nextProgressMark
        var lastProgressPrint = input.traceResult.lastProgressPrint

        if composeGPU {
            if useLinear32Intermediate {
                let linearSyncHandle = try FileHandle(forUpdating: input.frameResources.linearOutputURL)
                try linearSyncHandle.synchronize()
                try linearSyncHandle.close()
            } else if !input.effectiveUseInMemoryCollisions {
                let url = input.frameResources.outputURL
                if FileManager.default.fileExists(atPath: url.path) {
                    let handle = try FileHandle(forUpdating: url)
                    try handle.synchronize()
                    try handle.close()
                }
            }

            if gpuFullCompose {
                let fullGPUResult = try RenderComposeFullGPUPhase.execute(
                    input,
                    composeExposure: composeExposure,
                    nextProgressMark: nextProgressMark,
                    lastProgressPrint: lastProgressPrint
                )
                composeExposure = fullGPUResult.composeExposure
                nextProgressMark = fullGPUResult.nextProgressMark
                lastProgressPrint = fullGPUResult.lastProgressPrint
            } else if useLinear32Intermediate {
                let hdrResult = try RenderComposeHDRIntermediatePhase.execute(
                    input,
                    composeExposure: composeExposure,
                    nextProgressMark: nextProgressMark,
                    lastProgressPrint: lastProgressPrint
                )
                composeExposure = hdrResult.composeExposure
                nextProgressMark = hdrResult.nextProgressMark
                lastProgressPrint = hdrResult.lastProgressPrint
            } else {
                let legacyResult = try RenderComposeLegacyPhase.execute(
                    input,
                    composeExposure: composeExposure,
                    nextProgressMark: nextProgressMark,
                    lastProgressPrint: lastProgressPrint
                )
                composeExposure = legacyResult.composeExposure
                nextProgressMark = legacyResult.nextProgressMark
                lastProgressPrint = legacyResult.lastProgressPrint
            }
        }

        return RenderComposePhaseResult(
            composeExposure: composeExposure,
            nextProgressMark: nextProgressMark,
            lastProgressPrint: lastProgressPrint
        )
    }
}
