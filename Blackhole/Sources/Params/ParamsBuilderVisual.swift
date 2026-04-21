import Foundation
import simd

struct CameraCalibration {
    var profileName: String
    var profileID: UInt32
    var jsonPath: String
    var sceneR: SIMD4<Float>
    var sceneG: SIMD4<Float>
    var sceneB: SIMD4<Float>
    var displayR: SIMD4<Float>
    var displayG: SIMD4<Float>
    var displayB: SIMD4<Float>
    var sensorParams: SIMD4<Float>
    var noiseParams: SIMD4<Float>
    var colorParams: SIMD4<Float>
    var psfSigmaPixels: Float?
    var readNoise: Float?
    var shotNoise: Float?
    var flareStrength: Float?
}

private struct CameraCalibrationJSON: Decodable {
    var name: String?
    var sceneMatrix: [[Double]]?
    var displayMatrix: [[Double]]?
    var sensorGain: Double?
    var fullWell: Double?
    var shoulderMix: Double?
    var blackLevel: Double?
    var vignette: Double?
    var chromaNoiseMix: Double?
    var rowNoise: Double?
    var toeStrength: Double?
    var saturation: Double?
    var displayShoulder: Double?
    var fullWellElectrons: Double?
    var readNoiseElectrons: Double?
    var darkCurrentElectronsPerSecond: Double?
    var exposureSeconds: Double?
    var dsnuElectrons: Double?
    var prnuPercent: Double?
    var peakQuantumEfficiency: Double?
    var pixelPitchMicrons: Double?
    var lensFNumber: Double?
    var lensVignettingStops: Double?
    var psfSigmaPixels: Double?
    var flareStrength: Double?
}

private enum CameraCalibrationFactory {
    static func identity(profileName: String, profileID: UInt32, jsonPath: String = "") -> CameraCalibration {
        CameraCalibration(
            profileName: profileName,
            profileID: profileID,
            jsonPath: jsonPath,
            sceneR: SIMD4<Float>(1, 0, 0, 0),
            sceneG: SIMD4<Float>(0, 1, 0, 0),
            sceneB: SIMD4<Float>(0, 0, 1, 0),
            displayR: SIMD4<Float>(1, 0, 0, 0),
            displayG: SIMD4<Float>(0, 1, 0, 0),
            displayB: SIMD4<Float>(0, 0, 1, 0),
            sensorParams: SIMD4<Float>(1, 0, 0, 0),
            noiseParams: .zero,
            colorParams: SIMD4<Float>(1, 0, 0, 0),
            psfSigmaPixels: nil,
            readNoise: nil,
            shotNoise: nil,
            flareStrength: nil
        )
    }

    static func builtin(profileName: String, profileID: UInt32) -> CameraCalibration {
        switch profileID {
        case 1:
            var c = identity(profileName: profileName, profileID: profileID)
            c.sceneR = SIMD4<Float>(0.992, 0.006, 0.002, 0)
            c.sceneG = SIMD4<Float>(0.006, 0.991, 0.003, 0)
            c.sceneB = SIMD4<Float>(0.002, 0.010, 0.988, 0)
            c.displayR = SIMD4<Float>(0.985, 0.012, 0.003, 0)
            c.displayG = SIMD4<Float>(0.010, 0.985, 0.005, 0)
            c.displayB = SIMD4<Float>(0.004, 0.016, 0.980, 0)
            c.noiseParams = SIMD4<Float>(0.045, 0.12, 0.08, 0.0)
            c.colorParams = SIMD4<Float>(0.98, 0.0, 0, 0)
            return c
        case 2:
            var c = identity(profileName: profileName, profileID: profileID)
            c.sceneR = SIMD4<Float>(1.020, 0.000, 0.000, 0)
            c.sceneG = SIMD4<Float>(0.000, 0.995, 0.000, 0)
            c.sceneB = SIMD4<Float>(0.000, 0.000, 0.970, 0)
            c.displayR = SIMD4<Float>(1.035, 0.014, -0.012, 0)
            c.displayG = SIMD4<Float>(0.012, 0.995, 0.004, 0)
            c.displayB = SIMD4<Float>(-0.006, 0.026, 0.965, 0)
            c.sensorParams = SIMD4<Float>(1.0, 7.0, 0.20, 0.0)
            c.noiseParams = SIMD4<Float>(0.10, 0.24, 0.08, 0.0)
            c.colorParams = SIMD4<Float>(1.035, 0.55, 0, 0)
            return c
        case 3:
            var c = identity(profileName: profileName, profileID: profileID)
            c.sceneR = SIMD4<Float>(1.030, 0.000, 0.000, 0)
            c.sceneG = SIMD4<Float>(0.000, 1.005, 0.000, 0)
            c.sceneB = SIMD4<Float>(0.000, 0.000, 0.985, 0)
            c.displayR = SIMD4<Float>(1.055, 0.010, -0.018, 0)
            c.displayG = SIMD4<Float>(0.006, 1.008, 0.000, 0)
            c.displayB = SIMD4<Float>(-0.010, 0.020, 0.990, 0)
            c.sensorParams = SIMD4<Float>(1.0, 8.5, 0.14, 0.0)
            c.noiseParams = SIMD4<Float>(0.18, 0.42, 0.20, 0.16)
            c.colorParams = SIMD4<Float>(1.08, 0.0, 0, 0)
            return c
        default:
            return identity(profileName: profileName, profileID: profileID)
        }
    }

    static func loadJSON(path: String, fallback: CameraCalibration) -> CameraCalibration {
        do {
            let url = URL(fileURLWithPath: path)
            let data = try Data(contentsOf: url)
            let raw = try JSONDecoder().decode(CameraCalibrationJSON.self, from: data)
            var c = fallback
            c.profileName = raw.name ?? "json"
            c.profileID = 4
            c.jsonPath = path
            if let m = raw.sceneMatrix {
                (c.sceneR, c.sceneG, c.sceneB) = rows(from: m)
            }
            if let m = raw.displayMatrix {
                (c.displayR, c.displayG, c.displayB) = rows(from: m)
            }
            c.sensorParams.x = Float(raw.sensorGain ?? Double(c.sensorParams.x))
            c.sensorParams.y = Float(raw.fullWell ?? Double(c.sensorParams.y))
            c.sensorParams.z = Float(raw.shoulderMix ?? Double(c.sensorParams.z))
            c.sensorParams.w = Float(raw.blackLevel ?? Double(c.sensorParams.w))
            c.noiseParams.x = Float(raw.vignette ?? Double(c.noiseParams.x))
            c.noiseParams.y = Float(raw.chromaNoiseMix ?? Double(c.noiseParams.y))
            c.noiseParams.z = Float(raw.rowNoise ?? Double(c.noiseParams.z))
            c.noiseParams.w = Float(raw.toeStrength ?? Double(c.noiseParams.w))
            c.colorParams.x = Float(raw.saturation ?? Double(c.colorParams.x))
            c.colorParams.y = Float(raw.displayShoulder ?? Double(c.colorParams.y))
            applyPhysicalSensorModel(raw, to: &c)
            return c
        } catch {
            fail("failed to read --camera-profile-json \(path): \(error.localizedDescription)")
        }
    }

    private static func rows(from matrix: [[Double]]) -> (SIMD4<Float>, SIMD4<Float>, SIMD4<Float>) {
        guard matrix.count == 3, matrix.allSatisfy({ $0.count == 3 }) else {
            fail("camera matrix must be a 3x3 array")
        }
        return (
            SIMD4<Float>(Float(matrix[0][0]), Float(matrix[0][1]), Float(matrix[0][2]), 0),
            SIMD4<Float>(Float(matrix[1][0]), Float(matrix[1][1]), Float(matrix[1][2]), 0),
            SIMD4<Float>(Float(matrix[2][0]), Float(matrix[2][1]), Float(matrix[2][2]), 0)
        )
    }

    private static func applyPhysicalSensorModel(_ raw: CameraCalibrationJSON, to c: inout CameraCalibration) {
        let fullWellElectrons = raw.fullWellElectrons.map { max($0, 1.0) }
        let readNoiseElectrons = raw.readNoiseElectrons.map { max($0, 0.0) }
        let qePeak = raw.peakQuantumEfficiency.map { clamp($0, 0.05, 1.0) }

        if raw.sensorGain == nil, let qePeak {
            c.sensorParams.x = Float(clamp(Double(c.sensorParams.x) * qePeak / 0.68, 0.35, 1.5))
        }

        if raw.fullWell == nil, let fullWellElectrons {
            let noiseFloor = max(readNoiseElectrons ?? 2.0, 0.25)
            let dynamicRange = max(fullWellElectrons / noiseFloor, 1.0)
            c.sensorParams.y = Float(clamp(log10(dynamicRange) * 2.35, 6.0, 11.0))
        }

        if raw.blackLevel == nil, let fullWellElectrons {
            let exposure = max(raw.exposureSeconds ?? 1.0, 0.0)
            let dark = max((raw.darkCurrentElectronsPerSecond ?? 0.0) * exposure, 0.0)
            let dsnu = max(raw.dsnuElectrons ?? 0.0, 0.0)
            c.sensorParams.w = Float(clamp((dark + dsnu) / fullWellElectrons * 16.0, 0.0, 0.025))
        }

        if raw.rowNoise == nil, let prnuPercent = raw.prnuPercent {
            c.noiseParams.z = Float(clamp(prnuPercent * 0.45, 0.0, 0.45))
        }

        if raw.vignette == nil, let stops = raw.lensVignettingStops {
            let cornerTransmission = pow(2.0, -max(stops, 0.0))
            c.noiseParams.x = Float(clamp((1.0 - cornerTransmission) / 0.555, 0.0, 0.65))
        }

        if let fullWellElectrons {
            let qe = max(qePeak ?? 0.68, 0.05)
            c.shotNoise = Float(clamp(0.75 / sqrt(fullWellElectrons * qe), 0.0015, 0.014))
            if let readNoiseElectrons {
                let dsnu = max(raw.dsnuElectrons ?? 0.0, 0.0)
                c.readNoise = Float(clamp((readNoiseElectrons / fullWellElectrons) * 6.0 + (dsnu / fullWellElectrons) * 1.5, 0.00005, 0.008))
            }
        }

        if let psf = raw.psfSigmaPixels {
            c.psfSigmaPixels = Float(max(psf, 0.0))
        } else if let fNumber = raw.lensFNumber, let pitch = raw.pixelPitchMicrons, pitch > 0 {
            let airyRadiusPixels = 1.22 * 0.55 * max(fNumber, 0.1) / pitch
            c.psfSigmaPixels = Float(clamp(0.5 * airyRadiusPixels, 0.08, 1.2))
        }

        if let flare = raw.flareStrength {
            c.flareStrength = Float(clamp(flare, 0.0, 1.0))
        }
    }

    private static func clamp(_ value: Double, _ lo: Double, _ hi: Double) -> Double {
        min(max(value, lo), hi)
    }
}

struct VisualSettings {
    let composeDitherArg: Float
    let cameraModelName: String
    let cameraModelID: UInt32
    let cameraProfileName: String
    let cameraProfileID: UInt32
    let realismProfileName: String
    let realismProfileID: UInt32
    let cameraProfileJSONPath: String
    let cameraSceneR: SIMD4<Float>
    let cameraSceneG: SIMD4<Float>
    let cameraSceneB: SIMD4<Float>
    let cameraDisplayR: SIMD4<Float>
    let cameraDisplayG: SIMD4<Float>
    let cameraDisplayB: SIMD4<Float>
    let cameraSensorParams: SIMD4<Float>
    let cameraNoiseParams: SIMD4<Float>
    let cameraColorParams: SIMD4<Float>
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

        let cameraProfileName = stringArg("--camera-profile", default: {
            if composeLookID == 6 { return "scientific" }
            switch cameraModelID {
            case 1: return "scientific"
            case 2: return "cinema-digital"
            default: return "ideal"
            }
        }()).lowercased()
        let cameraProfileID: UInt32
        switch cameraProfileName {
        case "ideal", "none", "off":
            cameraProfileID = 0
        case "scientific", "science", "linear-sensor":
            cameraProfileID = 1
        case "cinema", "cinematic", "cinema-digital", "arri-like":
            cameraProfileID = 2
        case "photo", "full-frame", "fullframe", "dslr", "mirrorless":
            cameraProfileID = 3
        default:
            fail("invalid --camera-profile \(cameraProfileName). use one of: ideal, scientific, cinema-digital, full-frame")
        }
        let cameraProfileJSONPath = stringArg("--camera-profile-json", default: "")
        var cameraCalibration = CameraCalibrationFactory.builtin(profileName: cameraProfileName, profileID: cameraProfileID)
        if !cameraProfileJSONPath.isEmpty {
            cameraCalibration = CameraCalibrationFactory.loadJSON(path: cameraProfileJSONPath, fallback: cameraCalibration)
        }

        let realismProfileName = stringArg("--realism-profile", default: {
            if composeLookID == 6 { return "physical" }
            return "off"
        }()).lowercased()
        let realismProfileID: UInt32
        switch realismProfileName {
        case "off", "none", "legacy":
            realismProfileID = 0
        case "physical", "science", "scientific":
            realismProfileID = 1
        case "observational", "observed", "hybrid":
            realismProfileID = 2
        case "cinematic", "cinema":
            realismProfileID = 3
        default:
            fail("invalid --realism-profile \(realismProfileName). use one of: off, physical, observational, cinematic")
        }

        let cameraPsfSigmaDefault: Double = {
            switch cameraProfileID {
            case 1: return (composeLookID == 6) ? 0.42 : 0.55
            case 2: return 0.38
            case 3: return 0.32
            default:
                switch cameraModelID {
                case 1: return (composeLookID == 6) ? 0.42 : 0.55
                case 2: return 0.35
                default: return 0.0
                }
            }
        }()
        let cameraPsfSigmaArg = Float(max(0.0, doubleArg(
            "--camera-psf-sigma",
            default: Double(cameraCalibration.psfSigmaPixels ?? Float(cameraPsfSigmaDefault))
        )))
        let cameraReadNoiseDefault: Double = {
            switch cameraProfileID {
            case 1: return (composeLookID == 6) ? 0.0013 : 0.0023
            case 2: return 0.0011
            case 3: return 0.0018
            default: return 0.0
            }
        }()
        let cameraReadNoiseArg = Float(max(0.0, doubleArg(
            "--camera-read-noise",
            default: Double(cameraCalibration.readNoise ?? Float(cameraReadNoiseDefault))
        )))
        let cameraShotNoiseDefault: Double = {
            switch cameraProfileID {
            case 1: return (composeLookID == 6) ? 0.0055 : 0.009
            case 2: return 0.006
            case 3: return 0.008
            default: return 0.0
            }
        }()
        let cameraShotNoiseArg = Float(max(0.0, doubleArg(
            "--camera-shot-noise",
            default: Double(cameraCalibration.shotNoise ?? Float(cameraShotNoiseDefault))
        )))
        let cameraFlareDefault: Double = {
            switch cameraProfileID {
            case 2: return 0.16
            case 3: return 0.05
            default: return (cameraModelID == 2 ? 0.20 : 0.0)
            }
        }()
        let cameraFlareStrengthArg = Float(max(0.0, min(1.0, doubleArg(
            "--camera-flare",
            default: Double(cameraCalibration.flareStrength ?? Float(cameraFlareDefault))
        ))))
        if cameraProfileID < 2 && cameraModelID != 2 && cameraFlareStrengthArg > 1e-6 {
            FileHandle.standardError.write(Data("warn: --camera-flare is only active for cinematic/photo camera profiles\n".utf8))
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
            cameraProfileName: cameraCalibration.profileName,
            cameraProfileID: cameraCalibration.profileID,
            realismProfileName: realismProfileName,
            realismProfileID: realismProfileID,
            cameraProfileJSONPath: cameraProfileJSONPath,
            cameraSceneR: cameraCalibration.sceneR,
            cameraSceneG: cameraCalibration.sceneG,
            cameraSceneB: cameraCalibration.sceneB,
            cameraDisplayR: cameraCalibration.displayR,
            cameraDisplayG: cameraCalibration.displayG,
            cameraDisplayB: cameraCalibration.displayB,
            cameraSensorParams: cameraCalibration.sensorParams,
            cameraNoiseParams: cameraCalibration.noiseParams,
            cameraColorParams: cameraCalibration.colorParams,
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
