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

        let tracePipelines = ProcessInfo.processInfo.environment["BH_TRACE_PIPELINES"] == "1"
        let traceLiteName = traceKernelName.hasSuffix("Global") ? "renderBHClassicLiteGlobal" : "renderBHClassicLite"

        // Kernels to compile for this configuration. Disabled compose variants fall
        // back to an already-compiled pipeline below, so they are not listed here.
        // (The full collision compose kernel pulls in the entire legacy/material
        // shader surface; direct-linear HDR paths never call it, so it is only
        // compiled when the execution plan can actually reach it.)
        var names: Set<String> = [
            traceKernelName, traceLiteName, "renderBHLinearGlobal",
            "composeLinearRGB", "composeLinearRGBLite",
            composeLinearTileKernelName, "composeLinearRGBTileLite",
            "composeBHLinear",
            "composeCloudHistLinear", "composeLumHistLinear", "composeLumHistLinearTileCloud",
            "composeSolveCloudStats", "composeSolveExposure"
        ]
        if compileBHLinearTileCompose { names.insert("composeBHLinearTile") }
        if compileCollisionFinalCompose { names.insert("composeBH") }
        if compileCollisionCompose {
            names.insert("composeCloudHist")
            names.insert("composeCloudHistLite")
            names.insert("composeLumHist")
        }

        // Compile the unique kernels concurrently. Pipeline-state creation and
        // library function specialisation are thread-safe, so fanning the ~17 serial
        // compiles across cores cuts the dominant warm-up / serve-relaunch cost.
        let nameList = Array(names)
        var compiled = [String: MTLComputePipelineState]()
        let lock = NSLock()
        var firstError: Error?
        DispatchQueue.concurrentPerform(iterations: nameList.count) { idx in
            let name = nameList[idx]
            if tracePipelines {
                FileHandle.standardError.write(Data("pipeline-start \(name)\n".utf8))
            }
            do {
                guard let fn = try? library.makeFunction(name: name, constantValues: fc) else {
                    throw NSError(domain: "Blackhole", code: 130, userInfo: [NSLocalizedDescriptionKey:
                        "Metal function \(name) with function constants not found"])
                }
                let pipeline = try device.makeComputePipelineState(function: fn)
                lock.lock(); compiled[name] = pipeline; lock.unlock()
            } catch {
                lock.lock(); if firstError == nil { firstError = error }; lock.unlock()
            }
            if tracePipelines {
                FileHandle.standardError.write(Data("pipeline-done \(name)\n".utf8))
            }
        }
        if let firstError { throw firstError }
        func pipeline(_ name: String) -> MTLComputePipelineState {
            guard let p = compiled[name] else {
                fail("Metal pipeline \(name) missing after concurrent compile")
            }
            return p
        }

        let tracePipeline = pipeline(traceKernelName)
        let traceLitePipeline = pipeline(traceLiteName)
        let traceLinearPipeline = pipeline("renderBHLinearGlobal")
        let composeLinearPipeline = pipeline("composeLinearRGB")
        let composeLinearLitePipeline = pipeline("composeLinearRGBLite")
        let composeLinearTilePipeline = pipeline(composeLinearTileKernelName)
        let composeLinearTileLitePipeline = pipeline("composeLinearRGBTileLite")
        let composeBHLinearPipeline = pipeline("composeBHLinear")
        let composeBHLinearTilePipeline = compileBHLinearTileCompose ? pipeline("composeBHLinearTile") : composeBHLinearPipeline
        let cloudHistLinearPipeline = pipeline("composeCloudHistLinear")
        let lumHistLinearPipeline = pipeline("composeLumHistLinear")
        let lumHistLinearTileCloudPipeline = pipeline("composeLumHistLinearTileCloud")
        let solveCloudStatsPipeline = pipeline("composeSolveCloudStats")
        let solveExposurePipeline = pipeline("composeSolveExposure")

        let composePipeline = compileCollisionFinalCompose ? pipeline("composeBH") : composeBHLinearPipeline
        let cloudHistPipeline = compileCollisionCompose ? pipeline("composeCloudHist") : cloudHistLinearPipeline
        let cloudHistLitePipeline = compileCollisionCompose ? pipeline("composeCloudHistLite") : cloudHistLinearPipeline
        let lumHistPipeline = compileCollisionCompose ? pipeline("composeLumHist") : lumHistLinearPipeline

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
