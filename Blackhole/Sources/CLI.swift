import Foundation

var cliArguments: [String] = CommandLine.arguments

@inline(__always)
func setCLIArguments(_ args: [String]) {
    cliArguments = args
}

enum CLI {
    static func parse(arguments: [String]) -> LogicalParams {
        LogicalParams(rawArguments: arguments)
    }
}
