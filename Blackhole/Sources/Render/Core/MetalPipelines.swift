import Foundation
import Metal

struct RenderPipelines {
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

enum MetalPipelines {
    static func makeFunctionConstants(
        metric: Int32,
        physicsMode: UInt32,
        visibleMode: UInt32,
        traceDebugOff: UInt32,
        grmhdWeightMode: UInt32,
        visibleEmissionMode: UInt32
    ) -> MTLFunctionConstantValues {
        let fc = MTLFunctionConstantValues()
        var m = metric
        var p = physicsMode
        var v = visibleMode
        var d = traceDebugOff
        var w = grmhdWeightMode
        var e = visibleEmissionMode
        fc.setConstantValue(&m, type: .int, index: 0)
        fc.setConstantValue(&p, type: .uint, index: 1)
        fc.setConstantValue(&v, type: .uint, index: 2)
        fc.setConstantValue(&d, type: .uint, index: 3)
        fc.setConstantValue(&w, type: .uint, index: 4)
        fc.setConstantValue(&e, type: .uint, index: 5)
        return fc
    }

    static func makeRenderPipelines(
        device: MTLDevice,
        library: MTLLibrary,
        traceKernelName: String,
        composeLinearTileKernelName: String,
        metric: Int32,
        physicsMode: UInt32,
        visibleMode: UInt32,
        traceDebugOff: UInt32,
        grmhdWeightMode: UInt32,
        visibleEmissionMode: UInt32,
        compileCollisionCompose: Bool = true,
        compileCollisionFinalCompose: Bool = true,
        compileBHLinearTileCompose: Bool = true
    ) throws -> RenderPipelines {
        let fc = makeFunctionConstants(
            metric: metric,
            physicsMode: physicsMode,
            visibleMode: visibleMode,
            traceDebugOff: traceDebugOff,
            grmhdWeightMode: grmhdWeightMode,
            visibleEmissionMode: visibleEmissionMode
        )

        func specializedFunction(_ name: String) -> MTLFunction {
            guard let fn = try? library.makeFunction(name: name, constantValues: fc) else {
                fail("Metal function \(name) with function constants not found")
            }
            return fn
        }

        let tracePipelines = ProcessInfo.processInfo.environment["BH_TRACE_PIPELINES"] == "1"
        func makePipeline(_ name: String) throws -> MTLComputePipelineState {
            if tracePipelines {
                FileHandle.standardError.write(Data("pipeline-start \(name)\n".utf8))
            }
            let pipeline = try device.makeComputePipelineState(function: specializedFunction(name))
            if tracePipelines {
                FileHandle.standardError.write(Data("pipeline-done \(name)\n".utf8))
            }
            return pipeline
        }

        let tracePipeline = try makePipeline(traceKernelName)
        let traceLiteName = traceKernelName.hasSuffix("Global") ? "renderBHClassicLiteGlobal" : "renderBHClassicLite"
        let traceLitePipeline = try makePipeline(traceLiteName)
        let traceLinearPipeline = try makePipeline("renderBHLinearGlobal")
        let composeLinearPipeline = try makePipeline("composeLinearRGB")
        let composeLinearLitePipeline = try makePipeline("composeLinearRGBLite")
        let composeLinearTilePipeline = try makePipeline(composeLinearTileKernelName)
        let composeLinearTileLitePipeline = try makePipeline("composeLinearRGBTileLite")
        let composeBHLinearPipeline = try makePipeline("composeBHLinear")
        let composeBHLinearTilePipeline = compileBHLinearTileCompose
            ? try makePipeline("composeBHLinearTile")
            : composeBHLinearPipeline
        let cloudHistLinearPipeline = try makePipeline("composeCloudHistLinear")
        let lumHistLinearPipeline = try makePipeline("composeLumHistLinear")
        let lumHistLinearTileCloudPipeline = try makePipeline("composeLumHistLinearTileCloud")
        let solveCloudStatsPipeline = try makePipeline("composeSolveCloudStats")
        let solveExposurePipeline = try makePipeline("composeSolveExposure")

        // The full collision compose kernel pulls in the entire legacy/material
        // shader surface. Direct-linear HDR paths never call it, and compiling it
        // with the current thin visible reference constants can dominate startup
        // or hang Metal specialization. Use valid placeholder pipelines when the
        // execution plan cannot reach collision-compose kernels.
        let composePipeline = compileCollisionFinalCompose ? try makePipeline("composeBH") : composeBHLinearPipeline
        let cloudHistPipeline = compileCollisionCompose ? try makePipeline("composeCloudHist") : cloudHistLinearPipeline
        let cloudHistLitePipeline = compileCollisionCompose ? try makePipeline("composeCloudHistLite") : cloudHistLinearPipeline
        let lumHistPipeline = compileCollisionCompose ? try makePipeline("composeLumHist") : lumHistLinearPipeline

        return RenderPipelines(
            tracePipeline: tracePipeline,
            traceLitePipeline: traceLitePipeline,
            traceLinearPipeline: traceLinearPipeline,
            composePipeline: composePipeline,
            composeLinearPipeline: composeLinearPipeline,
            composeLinearLitePipeline: composeLinearLitePipeline,
            composeLinearTilePipeline: composeLinearTilePipeline,
            composeLinearTileLitePipeline: composeLinearTileLitePipeline,
            composeBHLinearPipeline: composeBHLinearPipeline,
            composeBHLinearTilePipeline: composeBHLinearTilePipeline,
            cloudHistPipeline: cloudHistPipeline,
            cloudHistLitePipeline: cloudHistLitePipeline,
            cloudHistLinearPipeline: cloudHistLinearPipeline,
            lumHistPipeline: lumHistPipeline,
            lumHistLinearPipeline: lumHistLinearPipeline,
            lumHistLinearTileCloudPipeline: lumHistLinearTileCloudPipeline,
            solveCloudStatsPipeline: solveCloudStatsPipeline,
            solveExposurePipeline: solveExposurePipeline
        )
    }
}
