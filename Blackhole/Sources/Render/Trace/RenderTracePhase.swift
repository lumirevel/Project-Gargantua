import Foundation
import Metal

struct RenderTracePhaseInput {
    let queue: MTLCommandQueue
    let params: PackedParams
    let width: Int
    let height: Int
    let effectiveTile: Int
    let traceTileTotal: Int
    let traceTilesX: Int
    let traceTilesY: Int
    let tg: MTLSize
    let tgLinearTile1D: MTLSize
    let traceSlots: [InFlightTraceSlot]
    let maxInFlight: Int
    let totalPixels: Int
    let totalOps: Int
    let progressStep: Int
    let useLinear32Intermediate: Bool
    let useInMemoryCollisions: Bool
    let directLinearEnabled: Bool
    let collisionLite32Enabled: Bool
    let discardCollisionOutput: Bool
    let traceStride: Int
    let linearStride: Int
    let linearCloudBins: Int
    let linearLumBins: Int
    let linearLumLogMin: Float
    let linearLumLogMax: Float
    let composeExposure: Float
    let composeDitherArg: Float
    let composeInnerEdgeArg: Float
    let composeSpectralStepArg: Float
    let composeLookID: UInt32
    let spectralEncodingID: UInt32
    let composePrecisionID: UInt32
    let composeAnalysisMode: UInt32
    let composeCameraModelID: UInt32
    let composeCameraPsfSigmaArg: Float
    let composeCameraReadNoiseArg: Float
    let composeCameraShotNoiseArg: Float
    let composeCameraFlareStrengthArg: Float
    let backgroundModeID: UInt32
    let backgroundStarDensityArg: Float
    let backgroundStarStrengthArg: Float
    let backgroundNebulaStrengthArg: Float
    let preserveHighlightColor: UInt32
    let directLinearParamBuf: MTLBuffer?
    let directLinearTraceBuf: MTLBuffer?
    let directLinearHitCountBuf: MTLBuffer?
    let composeBaseBufForLinear: MTLBuffer?
    let collisionBuffer: MTLBuffer?
    let collisionBase: UnsafeMutableRawPointer?
    let outHandle: FileHandle?
    let linearOutHandle: FileHandle?
    let tracePipeline: MTLComputePipelineState
    let composeLinearTilePipeline: MTLComputePipelineState
    let diskAtlasTex: MTLTexture
    let diskVol0Tex: MTLTexture
    let diskVol1Tex: MTLTexture
}

struct RenderTracePhaseResult {
    let hitCount: Int
    let donePixels: Int
    let nextProgressMark: Int
    let lastProgressPrint: TimeInterval
    let linearCloudHistGlobal: [UInt32]
    let linearCloudSampleCount: UInt64
}

enum RenderTracePhase {
    static func execute(_ input: RenderTracePhaseInput) throws -> RenderTracePhaseResult {
        let runtime = RenderTraceRuntime(
            linearCloudBins: input.linearCloudBins,
            totalOps: input.totalOps,
            totalPixels: input.totalPixels,
            progressStep: input.progressStep,
            useLinear32Intermediate: input.useLinear32Intermediate
        )

        emitETAProgress(0, input.totalOps, "swift_trace", "task=trace tile=0/\(input.traceTileTotal)")

        let inFlightSemaphore = DispatchSemaphore(value: input.maxInFlight)
        let traceDispatchGroup = DispatchGroup()
        let ioQueue = DispatchQueue(label: "blackhole.trace.io")
        try RenderTraceTraversal.forEachTile(
            input: input,
            runtime: runtime,
            inFlightSemaphore: inFlightSemaphore,
            traceDispatchGroup: traceDispatchGroup,
            ioQueue: ioQueue
        )

        traceDispatchGroup.wait()
        if let e = runtime.currentError() {
            throw e
        }
        let finalHitCount = runtime.finalizeHitCount(from: input.directLinearHitCountBuf)
        return runtime.makeResult(overridingHitCount: finalHitCount)
    }
}
