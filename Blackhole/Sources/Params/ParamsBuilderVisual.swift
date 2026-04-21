import Foundation

struct VisualSettings {
    let composeDitherArg: Float
    let cameraModelName: String
    let cameraModelID: UInt32
    let cameraPsfSigmaArg: Float
    let cameraReadNoiseArg: Float
    let cameraShotNoiseArg: Float
    let cameraFlareStrengthArg: Float
    let backgroundModeName: String
    let backgroundModeID: UInt32
    let backgroundStarDensityArg: Float
    let backgroundStarStrengthArg: Float
    let backgroundNebulaStrengthArg: Float
    let composeInnerEdgeArg: Float
    let composeSpectralStepArg: Float
    let composeChunkArg: Int
    let exposureSamplesArg: Int
    let exposureArg: Float
    let exposureModeName: String
    let exposureModeID: UInt32
    let exposureEVArg: Double
    let composePrecisionName: String
    let composePrecisionID: UInt32
    let composeAnalysisMode: UInt32
    let composeCameraModelID: UInt32
    let composeCameraPsfSigmaArg: Float
    let composeCameraReadNoiseArg: Float
    let composeCameraShotNoiseArg: Float
    let composeCameraFlareStrengthArg: Float
    let autoExposureEnabled: Bool
    let composeExposureBase: Float
    let spectralEncodingID: UInt32
    let composeExposure: Float
    let useLinear32Intermediate: Bool
}

enum ParamsBuilderVisual {
    static func resolveVisualSettings(
        diskModelArg: String,
        diskPhysicsModeID: UInt32,
        diskPrecisionCloudsEnabled: Bool,
        diskGrmhdDebugID: UInt32,
        composeLookID: UInt32,
        composeGPU: Bool,
        gpuFullCompose: Bool,
        linear32Intermediate: Bool
    ) -> VisualSettings {
        let composeDitherDefault: Double = {
            switch diskModelArg {
            case "perlin", "perlin-ec7", "perlin-legacy", "perlin-classic", "perlin-f552":
                return 0.0
            default:
                break
            }
            return (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? 0.0 : 0.75
        }()
        let composeDitherArg = Float(doubleArg("--dither", default: composeDitherDefault))

        let cameraModelName = stringArg("--camera-model", default: {
            if composeLookID == 6 { return "scientific" }
            return (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? "scientific" : "legacy"
        }()).lowercased()
        let cameraModelID: UInt32
        switch cameraModelName {
        case "legacy", "none":
            cameraModelID = 0
        case "scientific", "science":
            cameraModelID = 1
        case "cinematic", "cinema":
            cameraModelID = 2
        default:
            fail("invalid --camera-model \(cameraModelName). use one of: legacy, scientific, cinematic")
        }

        let cameraPsfSigmaArg = Float(max(0.0, doubleArg("--camera-psf-sigma", default: {
            switch cameraModelID {
            case 1: return (composeLookID == 6) ? 0.42 : 0.55
            case 2: return 0.35
            default: return 0.0
            }
        }())))
        let cameraReadNoiseArg = Float(max(0.0, doubleArg("--camera-read-noise", default: {
            switch cameraModelID {
            case 1: return (composeLookID == 6) ? 0.0015 : 0.0025
            case 2: return 0.0012
            default: return 0.0
            }
        }())))
        let cameraShotNoiseArg = Float(max(0.0, doubleArg("--camera-shot-noise", default: {
            switch cameraModelID {
            case 1: return (composeLookID == 6) ? 0.006 : 0.010
            case 2: return 0.006
            default: return 0.0
            }
        }())))
        let cameraFlareStrengthArg = Float(max(0.0, min(1.0, doubleArg("--camera-flare", default: (cameraModelID == 2 ? 0.20 : 0.0)))))
        if cameraModelID != 2 && cameraFlareStrengthArg > 1e-6 {
            FileHandle.standardError.write(Data("warn: --camera-flare is only active in --camera-model cinematic\n".utf8))
        }

        let backgroundRawArg = stringArg("--background", default: "").lowercased()
        let backgroundStarsRawArg = stringArg("--bg-stars", default: "").lowercased()
        let backgroundModeName: String = {
            if !backgroundRawArg.isEmpty { return backgroundRawArg }
            if !backgroundStarsRawArg.isEmpty {
                switch backgroundStarsRawArg {
                case "on", "true", "1", "yes":
                    return "stars"
                case "off", "false", "0", "no":
                    return "off"
                default:
                    fail("invalid --bg-stars \(backgroundStarsRawArg). use on|off")
                }
            }
            return (cameraModelID == 2 || composeLookID == 6) ? "stars" : "off"
        }()
        let backgroundModeID: UInt32
        switch backgroundModeName {
        case "off", "none", "black":
            backgroundModeID = 0
        case "stars", "starfield", "sky":
            backgroundModeID = 1
        default:
            fail("invalid --background \(backgroundModeName). use one of: off, stars")
        }
        let backgroundStarDensityArg = Float(max(0.0, min(4.0, doubleArg("--bg-star-density", default: {
            if backgroundModeID == 0 { return 0.0 }
            return (composeLookID == 6) ? 0.72 : 1.0
        }()))))
        let backgroundStarStrengthArg = Float(max(0.0, min(4.0, doubleArg("--bg-star-strength", default: {
            if backgroundModeID == 0 { return 0.0 }
            return (composeLookID == 6) ? 0.70 : 1.0
        }()))))
        let backgroundNebulaStrengthArg = Float(max(0.0, min(2.0, doubleArg("--bg-nebula-strength", default: {
            if backgroundModeID == 0 { return 0.0 }
            return (composeLookID == 6) ? 0.22 : 0.45
        }()))))
        if backgroundModeID == 0 && (backgroundStarDensityArg > 1e-6 || backgroundStarStrengthArg > 1e-6 || backgroundNebulaStrengthArg > 1e-6) {
            FileHandle.standardError.write(Data("warn: background intensity args are ignored when --background off\n".utf8))
        }

        let composeInnerEdgeArg = Float(max(1.0, doubleArg("--inner-edge-mult", default: 1.4)))
        let composeSpectralStepArg = Float(max(0.25, doubleArg("--spectral-step", default: 5.0)))
        let composeChunkArg = max(1, intArg("--chunk", default: 160000))
        let exposureSamplesArg = max(0, intArg("--exposure-samples", default: 200000))
        let exposureArg = Float(doubleArg("--exposure", default: -1.0))
        let exposureModeName = stringArg("--exposure-mode", default: "auto").lowercased()
        let exposureModeID: UInt32
        switch exposureModeName {
        case "auto":
            exposureModeID = 0
        case "fixed":
            exposureModeID = 1
        default:
            fail("invalid --exposure-mode \(exposureModeName). use one of: auto, fixed")
        }
        let exposureEVArg = doubleArg("--exposure-ev", default: 0.0)
        let composePrecisionName = stringArg("--compose-precision", default: "precise").lowercased()
        let composePrecisionID: UInt32 = (composePrecisionName == "fast") ? 0 : 1

        let composePolicy = ParamsBuilderPolicy.resolveComposePolicy(
            diskPhysicsModeID: diskPhysicsModeID,
            diskPrecisionCloudsEnabled: diskPrecisionCloudsEnabled,
            diskGrmhdDebugID: diskGrmhdDebugID,
            cameraModelID: cameraModelID,
            cameraPsfSigmaArg: cameraPsfSigmaArg,
            cameraReadNoiseArg: cameraReadNoiseArg,
            cameraShotNoiseArg: cameraShotNoiseArg,
            cameraFlareStrengthArg: cameraFlareStrengthArg
        )
        let realismDebugName = stringArg("--realism-debug", default: "off").lowercased()
        let realismDebugID: UInt32
        switch realismDebugName {
        case "off", "none":
            realismDebugID = 0
        case "g", "gfactor", "g-factor", "redshift":
            realismDebugID = 31
        case "emissivity", "radial", "nt":
            realismDebugID = 32
        case "beaming", "asymmetry", "approach":
            realismDebugID = 33
        case "photosphere", "surface":
            realismDebugID = 34
        case "atmosphere", "absorption":
            realismDebugID = 35
        case "corona":
            realismDebugID = 36
        case "perturbation", "turbulence", "disk-noise":
            realismDebugID = 37
        case "hdr", "pretonemap", "pre-tone", "pre-tone-map":
            realismDebugID = 38
        default:
            fail("invalid --realism-debug \(realismDebugName). use one of: off, g, emissivity, beaming, photosphere, atmosphere, corona, perturbation, hdr")
        }
        if realismDebugID != 0 && composeLookID != 6 {
            FileHandle.standardError.write(Data("warn: --realism-debug is intended for --look realistic; enabling the debug map anyway\n".utf8))
        }
        if realismDebugID != 0 && composePolicy.composeAnalysisMode != 0 {
            FileHandle.standardError.write(Data("warn: --realism-debug ignored because another analysis/debug mode is active\n".utf8))
        }
        let composeAnalysisMode = (composePolicy.composeAnalysisMode == 0) ? realismDebugID : composePolicy.composeAnalysisMode
        let composeCameraModelID = (composeAnalysisMode == 0) ? composePolicy.composeCameraModelID : 0
        let composeCameraPsfSigmaArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraPsfSigmaArg : 0.0
        let composeCameraReadNoiseArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraReadNoiseArg : 0.0
        let composeCameraShotNoiseArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraShotNoiseArg : 0.0
        let composeCameraFlareStrengthArg = (composeAnalysisMode == 0) ? composePolicy.composeCameraFlareStrengthArg : 0.0

        let autoExposureEnabled: Bool = {
            if composeAnalysisMode != 0 { return false }
            if exposureArg > 0 { return false }
            if exposureModeID == 1 { return false }
            return true
        }()
        let composeExposureBase: Float = {
            if composeAnalysisMode != 0 { return 1.0 }
            if exposureArg > 0 { return exposureArg }
            if exposureModeID == 1 { return Float(pow(2.0, exposureEVArg)) }
            switch composeLookID {
            case 1: return 7.0e-18
            case 2: return 5.2e-18
            default: return 6.8e-18
            }
        }()
        let spectralEncodingID: UInt32 = 1
        let useLinear32Intermediate = composeGPU && !gpuFullCompose && linear32Intermediate

        return VisualSettings(
            composeDitherArg: composeDitherArg,
            cameraModelName: cameraModelName,
            cameraModelID: cameraModelID,
            cameraPsfSigmaArg: cameraPsfSigmaArg,
            cameraReadNoiseArg: cameraReadNoiseArg,
            cameraShotNoiseArg: cameraShotNoiseArg,
            cameraFlareStrengthArg: cameraFlareStrengthArg,
            backgroundModeName: backgroundModeName,
            backgroundModeID: backgroundModeID,
            backgroundStarDensityArg: backgroundStarDensityArg,
            backgroundStarStrengthArg: backgroundStarStrengthArg,
            backgroundNebulaStrengthArg: backgroundNebulaStrengthArg,
            composeInnerEdgeArg: composeInnerEdgeArg,
            composeSpectralStepArg: composeSpectralStepArg,
            composeChunkArg: composeChunkArg,
            exposureSamplesArg: exposureSamplesArg,
            exposureArg: exposureArg,
            exposureModeName: exposureModeName,
            exposureModeID: exposureModeID,
            exposureEVArg: exposureEVArg,
            composePrecisionName: composePrecisionName,
            composePrecisionID: composePrecisionID,
            composeAnalysisMode: composeAnalysisMode,
            composeCameraModelID: composeCameraModelID,
            composeCameraPsfSigmaArg: composeCameraPsfSigmaArg,
            composeCameraReadNoiseArg: composeCameraReadNoiseArg,
            composeCameraShotNoiseArg: composeCameraShotNoiseArg,
            composeCameraFlareStrengthArg: composeCameraFlareStrengthArg,
            autoExposureEnabled: autoExposureEnabled,
            composeExposureBase: composeExposureBase,
            spectralEncodingID: spectralEncodingID,
            composeExposure: composeExposureBase,
            useLinear32Intermediate: useLinear32Intermediate
        )
    }
}
