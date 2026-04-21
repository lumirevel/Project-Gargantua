import Foundation

enum ParamsBuilderDiagnostics {
    static func emitDeprecatedWarnings(kerrImpactScaleArg: Double) {
        if abs(kerrImpactScaleArg - 1.0) > 1e-6 {
            FileHandle.standardError.write(Data("warn: --kerr-impact-scale is deprecated in physics mode and is ignored\n".utf8))
        }
    }

    static func emit(lines: [String]) {
        for line in lines {
            FileHandle.standardError.write(Data((line + "\n").utf8))
        }
    }
}
