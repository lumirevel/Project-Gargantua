import Foundation

enum AppMain {
    static func run(arguments: [String]) throws {
        let logical = CLI.parse(arguments: arguments)
        var built = ParamsBuilder.build(from: logical)

        if built.runRegression {
            try RegressionRunner.run(arguments: built.rawArguments)
            return
        }
        if built.printPackedLayout {
            printPackedParamsLayout()
            return
        }
        if built.validatePackedABI {
            try validatePackedParamsABIOrThrow()
            print("PackedParams ABI validation passed")
            return
        }

        guard var resolvedConfig = built.resolvedConfig, var packedParams = built.packedParams else {
            fail("missing resolved render configuration")
        }
        if !built.dumpPackedParamsPath.isEmpty {
            try dumpPackedParams(&packedParams, to: built.dumpPackedParamsPath)
            print("dumped packed params to: \(built.dumpPackedParamsPath)")
        }
        built.resolvedConfig = nil
        built.packedParams = nil
        try Renderer.render(config: &resolvedConfig, params: packedParams)
    }
}
