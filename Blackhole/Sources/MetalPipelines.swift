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
        traceDebugOff: UInt32
    ) -> MTLFunctionConstantValues {
        let fc = MTLFunctionConstantValues()
        var m = metric
        var p = physicsMode
        var v = visibleMode
        var d = traceDebugOff
        fc.setConstantValue(&m, type: .int, index: 0)
        fc.setConstantValue(&p, type: .uint, index: 1)
        fc.setConstantValue(&v, type: .uint, index: 2)
        fc.setConstantValue(&d, type: .uint, index: 3)
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
        traceDebugOff: UInt32
    ) throws -> RenderPipelines {
        let fc = makeFunctionConstants(
            metric: metric,
            physicsMode: physicsMode,
            visibleMode: visibleMode,
            traceDebugOff: traceDebugOff
        )

        func specializedFunction(_ name: String) -> MTLFunction {
            guard let fn = try? library.makeFunction(name: name, constantValues: fc) else {
                fail("Metal function \(name) with function constants not found")
            }
            return fn
        }

        let tracePipeline = try device.makeComputePipelineState(function: specializedFunction(traceKernelName))
        let traceLiteName = traceKernelName.hasSuffix("Global") ? "renderBHClassicLiteGlobal" : "renderBHClassicLite"
        let traceLitePipeline = try device.makeComputePipelineState(function: specializedFunction(traceLiteName))
        let traceLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("renderBHLinearGlobal"))
        let composePipeline = try device.makeComputePipelineState(function: specializedFunction("composeBH"))
        let composeLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLinearRGB"))
        let composeLinearLitePipeline = try device.makeComputePipelineState(function: specializedFunction("composeLinearRGBLite"))
        let composeLinearTilePipeline = try device.makeComputePipelineState(function: specializedFunction(composeLinearTileKernelName))
        let composeLinearTileLitePipeline = try device.makeComputePipelineState(function: specializedFunction("composeLinearRGBTileLite"))
        let composeBHLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeBHLinear"))
        let composeBHLinearTilePipeline = try device.makeComputePipelineState(function: specializedFunction("composeBHLinearTile"))
        let cloudHistPipeline = try device.makeComputePipelineState(function: specializedFunction("composeCloudHist"))
        let cloudHistLitePipeline = try device.makeComputePipelineState(function: specializedFunction("composeCloudHistLite"))
        let cloudHistLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeCloudHistLinear"))
        let lumHistPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLumHist"))
        let lumHistLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLumHistLinear"))
        let lumHistLinearTileCloudPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLumHistLinearTileCloud"))
        let solveCloudStatsPipeline = try device.makeComputePipelineState(function: specializedFunction("composeSolveCloudStats"))
        let solveExposurePipeline = try device.makeComputePipelineState(function: specializedFunction("composeSolveExposure"))

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
