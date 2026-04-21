import Foundation
import Metal

struct RenderTraceTile {
    let originX: Int
    let originY: Int
    let width: Int
    let height: Int
    let ordinal: Int

    var pixelCount: Int { width * height }
}

enum RenderTraceTileSupport {
    static func configureSlot(
        input: RenderTracePhaseInput,
        slot: InFlightTraceSlot,
        tile: RenderTraceTile
    ) {
        var tileParams = input.params
        tileParams.width = UInt32(tile.width)
        tileParams.height = UInt32(tile.height)
        tileParams.fullWidth = UInt32(input.width)
        tileParams.fullHeight = UInt32(input.height)
        tileParams.offsetX = UInt32(tile.originX)
        tileParams.offsetY = UInt32(tile.originY)
        updateBuffer(slot.traceParamBuf, with: &tileParams)

        guard input.useLinear32Intermediate else { return }
        guard let linearParamBuf = slot.linearParamBuf else {
            fail("linear32 slot param buffer missing")
        }

        var linearTileParams = ComposeParams(
            tileWidth: UInt32(tile.width),
            tileHeight: UInt32(tile.height),
            downsample: 1,
            outTileWidth: 0,
            outTileHeight: 0,
            srcOffsetX: UInt32(tile.originX),
            srcOffsetY: UInt32(tile.originY),
            outOffsetX: 0,
            outOffsetY: 0,
            fullInputWidth: UInt32(input.width),
            fullInputHeight: UInt32(input.height),
            exposure: input.composeExposure,
            dither: input.composeDitherArg,
            innerEdgeMult: input.composeInnerEdgeArg,
            spectralStep: input.composeSpectralStepArg,
            cloudQ10: 0.0,
            cloudInvSpan: 1.0,
            look: input.composeLookID,
            spectralEncoding: input.spectralEncodingID,
            precisionMode: input.composePrecisionID,
            analysisMode: input.composeAnalysisMode,
            cloudBins: UInt32(input.linearCloudBins),
            lumBins: UInt32(input.linearLumBins),
            lumLogMin: input.linearLumLogMin,
            lumLogMax: input.linearLumLogMax,
            cameraModel: input.composeCameraModelID,
            cameraPsfSigmaPx: input.composeCameraPsfSigmaArg,
            cameraReadNoise: input.composeCameraReadNoiseArg,
            cameraShotNoise: input.composeCameraShotNoiseArg,
            cameraFlareStrength: input.composeCameraFlareStrengthArg,
            backgroundMode: input.backgroundModeID,
            backgroundStarDensity: input.backgroundStarDensityArg,
            backgroundStarStrength: input.backgroundStarStrengthArg,
            backgroundNebulaStrength: input.backgroundNebulaStrengthArg,
            preserveHighlightColor: input.preserveHighlightColor,
            diskNoiseModel: input.params.diskNoiseModel,
            _pad0: 0,
            _pad1: 0,
            _pad2: 0
        )
        updateBuffer(linearParamBuf, with: &linearTileParams)
    }

    static func makeCommandBuffer(
        input: RenderTracePhaseInput,
        slot: InFlightTraceSlot,
        tile: RenderTraceTile
    ) -> MTLCommandBuffer {
        let cmd = input.queue.makeCommandBuffer()!
        let enc = cmd.makeComputeCommandEncoder()!
        enc.setComputePipelineState(input.tracePipeline)
        enc.setBuffer(slot.traceParamBuf, offset: 0, index: 0)
        if input.directLinearEnabled {
            guard let directLinearParamBuf = input.directLinearParamBuf,
                  let directLinearTraceBuf = input.directLinearTraceBuf,
                  let directLinearHitCountBuf = input.directLinearHitCountBuf else {
                fail("direct linear trace buffers are missing")
            }
            enc.setBuffer(directLinearParamBuf, offset: 0, index: 1)
            enc.setBuffer(directLinearTraceBuf, offset: 0, index: 2)
            enc.setBuffer(directLinearHitCountBuf, offset: 0, index: 3)
        } else if input.useInMemoryCollisions {
            guard let collisionBuffer = input.collisionBuffer else {
                fail("in-memory collision buffer missing for global trace path")
            }
            enc.setBuffer(collisionBuffer, offset: 0, index: 1)
        } else {
            guard let traceTileBuf = slot.traceTileBuf else {
                fail("trace tile buffer missing for local trace path")
            }
            enc.setBuffer(traceTileBuf, offset: 0, index: 1)
        }
        enc.setTexture(input.diskAtlasTex, index: 0)
        enc.setTexture(input.diskVol0Tex, index: 1)
        enc.setTexture(input.diskVol1Tex, index: 2)
        enc.dispatchThreads(
            MTLSize(width: tile.width, height: tile.height, depth: 1),
            threadsPerThreadgroup: input.tg
        )
        enc.endEncoding()

        if input.useLinear32Intermediate {
            guard let composeBaseBufForLinear = input.composeBaseBufForLinear,
                  let linearParamBuf = slot.linearParamBuf,
                  let traceTileBuf = slot.traceTileBuf,
                  let linearTileBuf = slot.linearTileBuf else {
                fail("linear32 slot buffers are not available")
            }
            let linearEnc = cmd.makeComputeCommandEncoder()!
            linearEnc.setComputePipelineState(input.composeLinearTilePipeline)
            linearEnc.setBuffer(composeBaseBufForLinear, offset: 0, index: 0)
            linearEnc.setBuffer(linearParamBuf, offset: 0, index: 1)
            linearEnc.setBuffer(traceTileBuf, offset: 0, index: 2)
            linearEnc.setBuffer(linearTileBuf, offset: 0, index: 3)
            linearEnc.dispatchThreads(
                MTLSize(width: tile.pixelCount, height: 1, depth: 1),
                threadsPerThreadgroup: input.tgLinearTile1D
            )
            linearEnc.endEncoding()
        }

        return cmd
    }
}
