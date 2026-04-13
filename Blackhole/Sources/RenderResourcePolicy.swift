import Foundation
import Metal

enum ComposeStrategyPreference {
    case fullFrameFirst
    case tileFirst
}

struct RenderResourcePolicy {
    let count: Int
    let stride: Int
    let liteStride: Int
    let linearStride: Int
    let useInMemoryCollisions: Bool
    let collisionLite32Safe: Bool
    let directLinearTraceSafe: Bool
    let workingSetCap: Int
    let outWidth: Int
    let outHeight: Int
    let linearOutSize: Int
    let outSize: Int
    let fullComposeOutBytes: Int
    let approxTextureBytes: Int
    let directLinearThresholdBytes: Int
    let directLinearPreferred: Bool
    let projectedDirectLinearBytes: Int
    let projectedFullComposeBytes: Int
    let composeStrategyPreference: ComposeStrategyPreference

    init(config: ResolvedRenderConfig, params: PackedParams, device: MTLDevice) {
        count = config.width * config.height
        stride = MemoryLayout<CollisionInfo>.stride
        liteStride = MemoryLayout<CollisionLite32>.stride
        linearStride = MemoryLayout<SIMD4<Float>>.stride
        useInMemoryCollisions = config.composeGPU && config.gpuFullCompose
        collisionLite32Safe =
            !config.rayBundleActive &&
            config.diskPhysicsModeID == 0 &&
            !config.visibleModeEnabled &&
            config.composeAnalysisMode == 0 &&
            config.diskGrmhdDebugID == 0
        directLinearTraceSafe =
            useInMemoryCollisions &&
            config.discardCollisionOutput &&
            !config.rayBundleActive &&
            !config.visibleModeEnabled &&
            config.composeAnalysisMode == 0 &&
            config.diskGrmhdDebugID == 0 &&
            (
                config.diskPhysicsModeID <= 2 ||
                (config.diskPhysicsModeID == 3 && params.diskVolumeFormat == 1 && params.diskVolumeMode != 0)
            )
        workingSetCap = Int(min(device.recommendedMaxWorkingSetSize, UInt64(Int.max)))
        outWidth = config.width / config.downsampleArg
        outHeight = config.height / config.downsampleArg
        linearOutSize = count * linearStride
        outSize = count * stride
        fullComposeOutBytes = outWidth * outHeight * MemoryLayout<UInt32>.stride
        approxTextureBytes = config.diskAtlasData.count + config.diskVolume0Data.count + config.diskVolume1Data.count
        directLinearThresholdBytes = 512 * 1024 * 1024
        let grmhdScalarDirectDefault =
            (config.diskPhysicsModeID == 3 && !config.visibleModeEnabled && config.diskGrmhdDebugID == 0)
        directLinearPreferred =
            directLinearTraceSafe &&
            (
                config.traceHDRDirectMode == "on" ||
                (config.traceHDRDirectMode == "auto" && (grmhdScalarDirectDefault || outSize >= directLinearThresholdBytes))
            )
        projectedDirectLinearBytes = approxTextureBytes + linearOutSize + fullComposeOutBytes
        projectedFullComposeBytes = approxTextureBytes + outSize + linearOutSize + fullComposeOutBytes
        composeStrategyPreference = {
            if config.diskPhysicsModeID == 3 || config.rayBundleActive {
                return .fullFrameFirst
            }
            if config.diskPhysicsModeID == 1 {
                return .tileFirst
            }
            if config.diskPhysicsModeID == 0 && config.diskModelResolved.hasPrefix("perlin") {
                return .tileFirst
            }
            return .fullFrameFirst
        }()
    }

    func directLinearAllowed() -> Bool {
        directLinearPreferred &&
        (workingSetCap <= 0 || projectedDirectLinearBytes <= Int(Double(workingSetCap) * 0.92))
    }

    func inMemoryCollisionLiteEnabled(directLinearEnabled: Bool) -> Bool {
        useInMemoryCollisions &&
        !directLinearEnabled &&
        collisionLite32Safe &&
        ((workingSetCap > 0 && projectedFullComposeBytes > Int(Double(workingSetCap) * 0.92)) ||
         outSize >= (512 * 1024 * 1024))
    }

    func collisionLite32Enabled(directLinearEnabled: Bool, useLinear32Intermediate: Bool) -> Bool {
        (useLinear32Intermediate && !useInMemoryCollisions && collisionLite32Safe) ||
        inMemoryCollisionLiteEnabled(directLinearEnabled: directLinearEnabled)
    }

    func traceStride(collisionLite32Enabled: Bool) -> Int {
        collisionLite32Enabled ? liteStride : stride
    }

    func collisionStorageSize(collisionLite32Enabled: Bool) -> Int {
        count * traceStride(collisionLite32Enabled: collisionLite32Enabled)
    }

    func tracePathSummary(
        directLinearEnabled: Bool,
        collisionLite32Enabled: Bool,
        inMemoryCollisionLiteEnabled: Bool,
        useLinear32Intermediate: Bool
    ) -> String {
        if directLinearEnabled {
            return "hdr32 direct full-frame (collision buffer elided)"
        }
        if collisionLite32Enabled {
            if inMemoryCollisionLiteEnabled {
                return "lite32 full-frame collision + gpu linear compose"
            }
            if useLinear32Intermediate {
                return "lite32 tile trace + hdr32 file intermediate"
            }
            return "lite32 tiled trace"
        }
        if useInMemoryCollisions {
            return "collision64 full-frame"
        }
        if useLinear32Intermediate {
            return "collision64 tile trace + hdr32 file intermediate"
        }
        return "collision64 tile trace + collision file"
    }

    func inFlightBudget() -> Int {
        max(64 * 1024 * 1024, min(workingSetCap / 8, 768 * 1024 * 1024))
    }
}
