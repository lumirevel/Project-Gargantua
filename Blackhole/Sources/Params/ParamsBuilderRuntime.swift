import Foundation

struct PresetDefaults {
    let camX: Double
    let camY: Double
    let camZ: Double
    let fov: Double
    let roll: Double
    let rcp: Double
    let diskH: Double
    let maxSteps: Int
}

struct MetricSettings {
    let metricName: String
    let metricArg: Int32
    let hArg: Double
    let spinArg: Double
    let kerrSubstepsArg: Int
    let kerrTolArg: Double
    let kerrEscapeMultArg: Double
    let kerrRadialScaleArg: Double
    let kerrAzimuthScaleArg: Double
    let kerrImpactScaleArg: Double
}

enum ParamsBuilderRuntime {
    static func resolvePresetDefaults(preset: String) -> PresetDefaults {
        switch preset {
        case "realistic", "natural", "observational":
            return PresetDefaults(camX: 15.0, camY: 0.0, camZ: 0.65, fov: 46.0, roll: -12.0, rcp: 8.2, diskH: 0.035, maxSteps: 1800)
        case "interstellar":
            return PresetDefaults(camX: 4.8, camY: 0.0, camZ: 0.55, fov: 58.0, roll: -18.0, rcp: 9.0, diskH: 0.08, maxSteps: 1600)
        case "eht":
            return PresetDefaults(camX: 8.4, camY: 0.0, camZ: 0.10, fov: 30.0, roll: 0.0, rcp: 4.4, diskH: 0.20, maxSteps: 2000)
        default:
            return PresetDefaults(camX: 22.0, camY: 0.0, camZ: 0.9, fov: 58.0, roll: -18.0, rcp: 9.0, diskH: 0.01, maxSteps: 1600)
        }
    }

    static func resolveMetricSettings() -> MetricSettings {
        let metricName = stringArg("--metric", default: "schwarzschild").lowercased()
        let defaultH = 0.01
        let defaultKerrSubsteps = 4
        let defaultKerrRadialScale = 1.0
        let defaultKerrAzimuthScale = 1.0
        let defaultKerrImpactScale = 1.0
        return MetricSettings(
            metricName: metricName,
            metricArg: (metricName == "kerr") ? 1 : 0,
            hArg: max(1e-6, doubleArg("--h", default: defaultH)),
            spinArg: max(-0.999, min(0.999, doubleArg("--spin", default: 0.0))),
            kerrSubstepsArg: max(1, min(8, intArg("--kerr-substeps", default: defaultKerrSubsteps))),
            kerrTolArg: max(1e-6, doubleArg("--kerr-tol", default: 1e-5)),
            kerrEscapeMultArg: max(1.0, doubleArg("--kerr-escape-mult", default: 3.0)),
            kerrRadialScaleArg: max(0.01, doubleArg("--kerr-radial-scale", default: defaultKerrRadialScale)),
            kerrAzimuthScaleArg: max(0.01, doubleArg("--kerr-azimuth-scale", default: defaultKerrAzimuthScale)),
            kerrImpactScaleArg: max(0.1, doubleArg("--kerr-impact-scale", default: defaultKerrImpactScale))
        )
    }

    static func validateDownsample(_ downsample: Int) {
        if !(downsample == 1 || downsample == 2 || downsample == 4) {
            FileHandle.standardError.write(Data("error: --downsample must be one of 1, 2, 4\n".utf8))
            exit(2)
        }
    }

    static func resolveTileSize(width: Int, height: Int, metricArg: Int32, explicitTileSize: Int) -> Int {
        let pixelCount = width * height
        let collision64Bytes = pixelCount * MemoryLayout<CollisionInfo>.stride
        let autoTile = collision64Bytes >= 192 * 1024 * 1024 || (metricArg == 1 && pixelCount >= 4_000_000)
        return (explicitTileSize > 0) ? explicitTileSize : (autoTile ? 1024 : max(width, height))
    }

    static func resolveComposeLookID(
        cliArguments: [String],
        preset: String,
        diskPhysicsModeID: UInt32
    ) -> (composeLook: String, composeLookID: UInt32) {
        let hasLookArg = cliArguments.contains("--look")
        let defaultLookName = ((diskPhysicsModeID == 2 || diskPhysicsModeID == 3) && !hasLookArg) ? "balanced" : preset
        let composeLook = stringArg("--look", default: defaultLookName).lowercased()
        let composeLookID: UInt32
        switch composeLook {
        case "interstellar": composeLookID = 1
        case "eht": composeLookID = 2
        case "agx", "filmic": composeLookID = 3
        case "none", "linear": composeLookID = 4
        case "hdr", "hdr-rich", "hdrrich": composeLookID = 5
        case "realistic", "natural", "observational": composeLookID = 6
        default: composeLookID = 0
        }
        return (composeLook, composeLookID)
    }
}
