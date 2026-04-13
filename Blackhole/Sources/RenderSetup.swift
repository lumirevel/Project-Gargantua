import Foundation
import Metal

struct RenderRuntime {
    let device: MTLDevice
    let queue: MTLCommandQueue
    let diskAtlasTex: MTLTexture
    let diskVol0Tex: MTLTexture
    let diskVol1Tex: MTLTexture
    let tracePipeline: MTLComputePipelineState
    let traceLitePipeline: MTLComputePipelineState
    let traceLinearPipeline: MTLComputePipelineState
    let composePipeline: MTLComputePipelineState
    let composeLinearPipeline: MTLComputePipelineState
    let composeLinearLitePipeline: MTLComputePipelineState
    let composeLinearTilePipeline: MTLComputePipelineState
    let composeLinearTileLitePipeline: MTLComputePipelineState
    let composeBHLinearPipeline: MTLComputePipelineState
    let composeBHLinearTilePipeline: MTLComputePipelineState
    let cloudHistPipeline: MTLComputePipelineState
    let cloudHistLitePipeline: MTLComputePipelineState
    let cloudHistLinearPipeline: MTLComputePipelineState
    let lumHistPipeline: MTLComputePipelineState
    let lumHistLinearPipeline: MTLComputePipelineState
    let lumHistLinearTileCloudPipeline: MTLComputePipelineState
    let solveCloudStatsPipeline: MTLComputePipelineState
    let solveExposurePipeline: MTLComputePipelineState
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

        let useInMemoryCollisions = config.composeGPU && config.gpuFullCompose
        let traceKernelBase: String
        traceKernelBase = config.rayBundleActive ? "renderBHBundle" : "renderBHClassic"
        let traceKernelName = useInMemoryCollisions ? "\(traceKernelBase)Global" : traceKernelBase
        let pipelines = try MetalPipelines.makeRenderPipelines(
            device: device,
            library: library,
            traceKernelName: traceKernelName,
            composeLinearTileKernelName: "composeLinearRGBTile",
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
            traceLitePipeline: pipelines.traceLitePipeline,
            traceLinearPipeline: pipelines.traceLinearPipeline,
            composePipeline: pipelines.composePipeline,
            composeLinearPipeline: pipelines.composeLinearPipeline,
            composeLinearLitePipeline: pipelines.composeLinearLitePipeline,
            composeLinearTilePipeline: pipelines.composeLinearTilePipeline,
            composeLinearTileLitePipeline: pipelines.composeLinearTileLitePipeline,
            composeBHLinearPipeline: pipelines.composeBHLinearPipeline,
            composeBHLinearTilePipeline: pipelines.composeBHLinearTilePipeline,
            cloudHistPipeline: pipelines.cloudHistPipeline,
            cloudHistLitePipeline: pipelines.cloudHistLitePipeline,
            cloudHistLinearPipeline: pipelines.cloudHistLinearPipeline,
            lumHistPipeline: pipelines.lumHistPipeline,
            lumHistLinearPipeline: pipelines.lumHistLinearPipeline,
            lumHistLinearTileCloudPipeline: pipelines.lumHistLinearTileCloudPipeline,
            solveCloudStatsPipeline: pipelines.solveCloudStatsPipeline,
            solveExposurePipeline: pipelines.solveExposurePipeline
        )
    }
}
