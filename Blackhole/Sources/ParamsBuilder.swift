import Foundation

struct BuiltParams {
    var rawArguments: [String]
    var runRegression: Bool
    var printPackedLayout: Bool
    var dumpPackedParamsPath: String
}

enum ParamsBuilder {
    @inline(__always)
    static func build(from logical: LogicalParams) -> BuiltParams {
        BuiltParams(
            rawArguments: logical.rawArguments,
            runRegression: logical.runRegression,
            printPackedLayout: logical.printPackedLayout,
            dumpPackedParamsPath: logical.dumpPackedParamsPath
        )
    }
}
