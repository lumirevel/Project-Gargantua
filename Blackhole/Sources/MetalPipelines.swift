import Foundation
import Metal

enum MetalPipelines {
    static func makeFunctionConstants(metric: Int32, physicsMode: UInt32) -> MTLFunctionConstantValues {
        let fc = MTLFunctionConstantValues()
        var m = metric
        var p = physicsMode
        fc.setConstantValue(&m, type: .int, index: 0)
        fc.setConstantValue(&p, type: .uint, index: 1)
        return fc
    }
}
