import Foundation
import Metal

struct RenderPipelines {
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
        let composePipeline = try device.makeComputePipelineState(function: specializedFunction("composeBH"))
        let composeLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLinearRGB"))
        let composeLinearTilePipeline = try device.makeComputePipelineState(function: specializedFunction(composeLinearTileKernelName))
        let composeBHLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeBHLinear"))
        let composeBHLinearTilePipeline = try device.makeComputePipelineState(function: specializedFunction("composeBHLinearTile"))
        let cloudHistPipeline = try device.makeComputePipelineState(function: specializedFunction("composeCloudHist"))
        let lumHistPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLumHist"))
        let lumHistLinearPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLumHistLinear"))
        let lumHistLinearTileCloudPipeline = try device.makeComputePipelineState(function: specializedFunction("composeLumHistLinearTileCloud"))

        return RenderPipelines(
            tracePipeline: tracePipeline,
            composePipeline: composePipeline,
            composeLinearPipeline: composeLinearPipeline,
            composeLinearTilePipeline: composeLinearTilePipeline,
            composeBHLinearPipeline: composeBHLinearPipeline,
            composeBHLinearTilePipeline: composeBHLinearTilePipeline,
            cloudHistPipeline: cloudHistPipeline,
            lumHistPipeline: lumHistPipeline,
            lumHistLinearPipeline: lumHistLinearPipeline,
            lumHistLinearTileCloudPipeline: lumHistLinearTileCloudPipeline
        )
    }
}
