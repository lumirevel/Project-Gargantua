import Foundation
import Metal

struct RenderRuntime {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let diskAtlasTex: MTLTexture
    let diskVol0Tex: MTLTexture
    let diskVol1Tex: MTLTexture
    let tracePipeline: MTLComputePipelineState
    let composePipeline: MTLComputePipelineState
    let composeLinearPipeline: MTLComputePipelineState
    let composeLinearTilePipeline: MTLComputePipelineState
    let composeBHLinearPipeline: MTLComputePipelineState
    let composeBHLinearTilePipeline: MTLComputePipelineState
    let cloudHistPipeline: MTLComputePipelineState
    let lumHistPipeline: MTLComputePipelineState
    let lumHistLinearPipeline: MTLComputePipelineState
    let lumHistLinearTileCloudPipeline: MTLComputePipelineState
}

enum RenderSetup {
    static func prepare(config: ResolvedRenderConfig, params: PackedParams) throws -> RenderRuntime {
        guard let device = MTLCreateSystemDefaultDevice() else {
            fail("no Metal device available (check permissions/runtime context)")
        }
        guard let queue = device.makeCommandQueue() else {
            fail("failed to create Metal command queue")
        }
        guard let library = device.makeDefaultLibrary() else {
            fail("failed to load default Metal library")
        }

        let diskAtlasTex = makeFloat4Texture2D(
            device: device,
            width: Int(max(params.diskAtlasWidth, 1)),
            height: Int(max(params.diskAtlasHeight, 1)),
            data: config.diskAtlasData,
            label: "diskAtlas"
        )
        let diskVol0Tex = makeFloat4Texture3D(
            device: device,
            width: Int(max(params.diskVolumeR0, 1)),
            height: Int(max(params.diskVolumePhi0, 1)),
            depth: Int(max(params.diskVolumeZ0, 1)),
            data: config.diskVolume0Data,
            label: "diskVol0"
        )
        let diskVol1Tex = makeFloat4Texture3D(
            device: device,
            width: Int(max(params.diskVolumeR1, 1)),
            height: Int(max(params.diskVolumePhi1, 1)),
            depth: Int(max(params.diskVolumeZ1, 1)),
            data: config.diskVolume1Data,
            label: "diskVol1"
        )

        let collisionLite32Enabled =
            config.useLinear32Intermediate &&
            !config.gpuFullCompose &&
            !config.rayBundleActive &&
            config.diskPhysicsModeID <= 1 &&
            !config.visibleModeEnabled &&
            config.composeAnalysisMode == 0 &&
            config.diskGrmhdDebugID == 0
        let useInMemoryCollisions = config.composeGPU && config.gpuFullCompose
        let traceKernelBase: String
        if collisionLite32Enabled {
            traceKernelBase = "renderBHClassicLite"
        } else {
            traceKernelBase = config.rayBundleActive ? "renderBHBundle" : "renderBHClassic"
        }
        let traceKernelName = useInMemoryCollisions ? "\(traceKernelBase)Global" : traceKernelBase
        let composeLinearTileKernelName = collisionLite32Enabled ? "composeLinearRGBTileLite" : "composeLinearRGBTile"
        let pipelines = try MetalPipelines.makeRenderPipelines(
            device: device,
            library: library,
            traceKernelName: traceKernelName,
            composeLinearTileKernelName: composeLinearTileKernelName,
            metric: config.metricArg,
            physicsMode: config.diskPhysicsModeID,
            visibleMode: UInt32((config.diskPhysicsModeID == 3 && config.visibleModeEnabled) ? 1 : 0),
            traceDebugOff: UInt32(config.diskGrmhdDebugID == 0 ? 1 : 0)
        )

        return RenderRuntime(
            device: device,
            queue: queue,
            diskAtlasTex: diskAtlasTex,
            diskVol0Tex: diskVol0Tex,
            diskVol1Tex: diskVol1Tex,
            tracePipeline: pipelines.tracePipeline,
            composePipeline: pipelines.composePipeline,
            composeLinearPipeline: pipelines.composeLinearPipeline,
            composeLinearTilePipeline: pipelines.composeLinearTilePipeline,
            composeBHLinearPipeline: pipelines.composeBHLinearPipeline,
            composeBHLinearTilePipeline: pipelines.composeBHLinearTilePipeline,
            cloudHistPipeline: pipelines.cloudHistPipeline,
            lumHistPipeline: pipelines.lumHistPipeline,
            lumHistLinearPipeline: pipelines.lumHistLinearPipeline,
            lumHistLinearTileCloudPipeline: pipelines.lumHistLinearTileCloudPipeline
        )
    }
}
