import Foundation

enum AppMain {
    static func run(arguments: [String]) throws {
        let logical = CLI.parse(arguments: arguments)
        let built = ParamsBuilder.build(from: logical)

        if built.runRegression {
            try RegressionRunner.run(arguments: built.rawArguments)
            return
        }
        if built.printPackedLayout {
            printPackedParamsLayout()
            return
        }

        try Renderer.render(arguments: built.rawArguments)
    }
}
