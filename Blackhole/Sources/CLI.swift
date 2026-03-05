import Foundation

var cliArguments: [String] = CommandLine.arguments

@inline(__always)
func setCLIArguments(_ args: [String]) {
    cliArguments = args
}

enum CLI {
    static func parse(arguments: [String]) -> LogicalParams {
        setCLIArguments(arguments)
        var dumpPath = ""
        if let idx = arguments.firstIndex(of: "--dump-packed-params"), idx + 1 < arguments.count {
            dumpPath = arguments[idx + 1]
        }
        return LogicalParams(
            rawArguments: arguments,
            runRegression: arguments.contains("--regression-run"),
            printPackedLayout: arguments.contains("--print-packed-layout"),
            dumpPackedParamsPath: dumpPath
        )
    }
}

func intArg(_ name: String, default defaultValue: Int) -> Int {
    guard let idx = cliArguments.firstIndex(of: name), idx + 1 < cliArguments.count else {
        return defaultValue
    }
    return Int(cliArguments[idx + 1]) ?? defaultValue
}

func intArgAny(_ names: [String], default defaultValue: Int) -> Int {
    for name in names {
        if let idx = cliArguments.firstIndex(of: name), idx + 1 < cliArguments.count {
            return Int(cliArguments[idx + 1]) ?? defaultValue
        }
    }
    return defaultValue
}

func doubleArg(_ name: String, default defaultValue: Double) -> Double {
    guard let idx = cliArguments.firstIndex(of: name), idx + 1 < cliArguments.count else {
        return defaultValue
    }
    return Double(cliArguments[idx + 1]) ?? defaultValue
}

func doubleArgAny(_ names: [String], default defaultValue: Double) -> Double {
    for name in names {
        if let idx = cliArguments.firstIndex(of: name), idx + 1 < cliArguments.count {
            return Double(cliArguments[idx + 1]) ?? defaultValue
        }
    }
    return defaultValue
}

func stringArg(_ name: String, default defaultValue: String) -> String {
    guard let idx = cliArguments.firstIndex(of: name), idx + 1 < cliArguments.count else {
        return defaultValue
    }
    return cliArguments[idx + 1]
}

func parseDiskMode(_ raw: String) -> (id: UInt32, canonical: String)? {
    switch raw.lowercased() {
    case "thin", "nt", "strict":
        return (0, "thin")
    case "thick", "plasma", "riaf":
        return (1, "thick")
    case "precision", "analysis", "pt", "auto", "unified", "adaptive", "smart":
        return (2, "precision")
    case "grmhd", "rt", "volume-rt":
        return (3, "grmhd")
    default:
        return nil
    }
}

// Optional modern physics profile override.
// NOTE: for backward compatibility, internal mode IDs remain:
// 0=legacy(thin), 1=thick, 2=thinNT/precision, 3=eht(grmhd).
func parseDiskPhysicsProfile(_ raw: String) -> (id: UInt32, canonical: String)? {
    switch raw.lowercased() {
    case "legacy", "off", "default":
        return (0, "legacy")
    case "thin", "thinnt", "nt", "novikov-thorne", "novikov_thorne", "precision":
        return (2, "thin")
    case "thick", "plasma", "riaf-thick":
        return (1, "thick")
    case "eht", "eht-riaf", "riaf", "grmhd":
        return (3, "eht")
    default:
        return nil
    }
}

@inline(__always)
func smoothstepDouble(_ edge0: Double, _ edge1: Double, _ x: Double) -> Double {
    let den = max(edge1 - edge0, 1e-9)
    let t = min(max((x - edge0) / den, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)
}

@inline(__always)
func precisionThicknessBlend(diskH: Double) -> Double {
    // Blend thin -> thick behavior from geometric half-thickness ratio H/rs.
    // ~0 for very thin disks, ~1 for clearly puffed/plasma-like disks.
    return smoothstepDouble(0.015, 0.11, diskH)
}

@inline(__always)
func precisionAdaptiveDefaults(diskH: Double) -> (plungeFloor: Double, thickScale: Double) {
    let blend = precisionThicknessBlend(diskH: diskH)
    let plungeFloor = 0.12 * blend
    let thickScale = 1.0 + 0.8 * blend
    return (plungeFloor, thickScale)
}
