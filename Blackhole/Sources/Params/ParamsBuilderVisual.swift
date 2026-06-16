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
    var lensFNumber: Float?
    var lensFocusDepth: Float?
    var lensDofStrength: Float?
    var apertureBlades: UInt32?
    var apertureRotation: Float?
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
    var lensFocusDepth: Double?
    var lensDofStrength: Double?
    var apertureBlades: Int?
    var apertureRotation: Double?
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
            lensFNumber: nil,
            lensFocusDepth: nil,
            lensDofStrength: nil,
            apertureBlades: nil,
            apertureRotation: nil,
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
            c.lensFNumber = 2.8
            c.lensFocusDepth = 4.35
            c.lensDofStrength = 1.0
            c.apertureBlades = 7
            c.apertureRotation = 0.10
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
            c.lensFNumber = 4.0
            c.lensFocusDepth = 4.35
            c.lensDofStrength = 0.75
            c.apertureBlades = 9
            c.apertureRotation = 0.0
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
            if let f = raw.lensFNumber {
                c.lensFNumber = Float(max(f, 0.1))
            }
            if let focus = raw.lensFocusDepth {
                c.lensFocusDepth = Float(max(focus, 0.0))
            }
            if let strength = raw.lensDofStrength {
                c.lensDofStrength = Float(clamp(strength, 0.0, 4.0))
            }
            if let blades = raw.apertureBlades {
                c.apertureBlades = UInt32(max(0, min(blades, 16)))
            }
            if let rotation = raw.apertureRotation {
                c.apertureRotation = Float(rotation)
            }
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
    let presentationModeName: String
    let presentationModeID: UInt32
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
    let cameraFlags: UInt32
    let cameraPsfSigmaArg: Float
    let cameraReadNoiseArg: Float
    let cameraShotNoiseArg: Float
    let cameraFlareStrengthArg: Float
    let cameraFNumberArg: Float
    let cameraISOArg: Float
    let cameraShutterSecondsArg: Float
    let photographicExposureScale: Float
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
    private static func positiveSecondsArg(_ name: String, default defaultValue: Double) -> Double {
        let raw = stringArg(name, default: "")
        guard !raw.isEmpty else { return defaultValue }
        if raw.contains("/") {
            let parts = raw.split(separator: "/", omittingEmptySubsequences: false)
            if parts.count == 2, let numerator = Double(String(parts[0])), let denominator = Double(String(parts[1])), denominator > 0 {
                return max(1e-6, numerator / denominator)
            }
            fail("invalid \(name) \(raw). use seconds or a fraction like 1/60")
        }
        guard let seconds = Double(raw), seconds > 0 else {
            fail("invalid \(name) \(raw). use seconds or a fraction like 1/60")
        }
        return seconds
    }

    static func resolveVisualSettings(
        diskModelArg: String,
        diskPhysicsModeID: UInt32,
        diskPrecisionCloudsEnabled: Bool,
        precisionVolumeEnabled: Bool,
        diskGrmhdDebugID: UInt32,
        composeLookID: UInt32,
        composeGPU: Bool,
        gpuFullCompose: Bool,
        linear32Intermediate: Bool
    ) -> VisualSettings {
        let composeDitherDefault: Double = {
            if composeLookID == 4 { return 0.0 }
            switch diskModelArg {
            case "perlin", "perlin-ec7", "perlin-legacy", "perlin-classic", "perlin-f552":
                return 0.0
            default:
                break
            }
            return (diskPhysicsModeID == 2 || diskPhysicsModeID == 3) ? 0.0 : 0.75
        }()
        let composeDitherArg = Float(doubleArg("--dither", default: composeDitherDefault))

        let presentationModeRaw = stringArg("--presentation-mode", default: {
            if composeLookID == 6 { return "eye" }
            return "legacy"
        }()).lowercased()
        let presentationModeName: String
        let presentationModeID: UInt32
        switch presentationModeRaw {
        case "legacy", "auto", "off":
            presentationModeName = "legacy"
            presentationModeID = 0
        case "scientific", "science", "master":
            presentationModeName = "scientific"
            presentationModeID = 1
        case "eye", "human", "experience", "observational":
            presentationModeName = "eye"
            presentationModeID = 2
        case "cinema", "cinematic", "camera":
            presentationModeName = "cinema"
            presentationModeID = 3
        case "camera-raw", "camera_raw", "raw", "raw-like", "rawlike":
            presentationModeName = "camera-raw"
            presentationModeID = 4
        case "camera-rendered", "camera_rendered", "rendered-camera", "rendered", "photo", "photographic":
            presentationModeName = "camera-rendered"
            presentationModeID = 5
        default:
            fail("invalid --presentation-mode \(presentationModeRaw). use one of: legacy, scientific, eye, camera-raw, camera-rendered, cinema")
        }

        let cameraModelName = stringArg("--camera-model", default: {
            switch presentationModeID {
            case 1: return "legacy"
            case 2: return "eye"
            case 3: return "cinematic"
            case 4: return "legacy"
            case 5: return "cinematic"
            default: break
            }
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
        case "eye", "human", "vision":
            cameraModelID = 3
        default:
            fail("invalid --camera-model \(cameraModelName). use one of: legacy, scientific, cinematic, eye")
        }

        let cameraProfileName = stringArg("--camera-profile", default: {
            switch presentationModeID {
            case 1: return "ideal"
            case 2: return "ideal"
            case 3: return "cinema-digital"
            case 4: return "ideal"
            case 5: return "full-frame"
            default: break
            }
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
        if presentationModeID == 4 && (cameraModelID != 0 || cameraProfileID != 0 || !cameraProfileJSONPath.isEmpty) {
            fail("camera-raw is a RAW-like identity audit route; use --camera-model legacy/none and --camera-profile ideal/none, with no --camera-profile-json")
        }
        var cameraCalibration = CameraCalibrationFactory.builtin(profileName: cameraProfileName, profileID: cameraProfileID)
        if !cameraProfileJSONPath.isEmpty {
            cameraCalibration = CameraCalibrationFactory.loadJSON(path: cameraProfileJSONPath, fallback: cameraCalibration)
        }

        let realismProfileName = stringArg("--realism-profile", default: {
            switch presentationModeID {
            case 1: return "physical"
            case 2: return "observational"
            case 3: return "cinematic"
            case 4: return "physical"
            case 5: return "observational"
            default: break
            }
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
        case "physical-flow", "photosphere-flow", "flow-photosphere", "thin-flow":
            realismProfileID = 4
        case "canonical-visible-disk-v1", "canonical-visible-disk", "plausible-disk-v1", "plausible-disk", "source-plausible-disk-v1", "mri-skin":
            realismProfileID = 5
        case "physics-constrained-cinematic-disk-v1", "physics-constrained-cinematic-disk", "plausible-cinematic-disk-v1", "plausible-cinematic-disk", "pcd-v1":
            realismProfileID = 6
        default:
            fail("invalid --realism-profile \(realismProfileName). use one of: off, physical, observational, cinematic, physical-flow, canonical-visible-disk-v1, physics-constrained-cinematic-disk-v1")
        }

        let cameraPsfSigmaDefault: Double = {
            if presentationModeID == 4 { return 0.0 }
            switch cameraProfileID {
            case 1: return (composeLookID == 6) ? 0.42 : 0.55
            case 2: return 0.38
            case 3: return 0.32
            default:
                switch cameraModelID {
                case 1: return (composeLookID == 6) ? 0.42 : 0.55
                case 2: return 0.35
                case 3: return 0.38
                default: return 0.0
                }
            }
        }()
        let cameraPsfSigmaArg = Float(max(0.0, doubleArg(
            "--camera-psf-sigma",
            default: presentationModeID == 4 ? cameraPsfSigmaDefault : Double(cameraCalibration.psfSigmaPixels ?? Float(cameraPsfSigmaDefault))
        )))
        let cameraReadNoiseDefault: Double = {
            if presentationModeID == 4 { return 0.0 }
            switch cameraProfileID {
            case 1: return (composeLookID == 6) ? 0.0013 : 0.0023
            case 2: return 0.0011
            case 3: return 0.0018
            default: return 0.0
            }
        }()
        let cameraReadNoiseExplicit = cliArguments.contains("--camera-read-noise")
        var cameraReadNoiseArg = Float(max(0.0, doubleArg(
            "--camera-read-noise",
            default: presentationModeID == 4 ? cameraReadNoiseDefault : Double(cameraCalibration.readNoise ?? Float(cameraReadNoiseDefault))
        )))
        let cameraShotNoiseDefault: Double = {
            if presentationModeID == 4 { return 0.0 }
            switch cameraProfileID {
            case 1: return (composeLookID == 6) ? 0.0055 : 0.009
            case 2: return 0.006
            case 3: return 0.008
            default: return 0.0
            }
        }()
        let cameraShotNoiseExplicit = cliArguments.contains("--camera-shot-noise")
        var cameraShotNoiseArg = Float(max(0.0, doubleArg(
            "--camera-shot-noise",
            default: presentationModeID == 4 ? cameraShotNoiseDefault : Double(cameraCalibration.shotNoise ?? Float(cameraShotNoiseDefault))
        )))
        let cameraFlareDefault: Double = {
            if presentationModeID == 4 { return 0.0 }
            switch cameraProfileID {
            case 2: return 0.16
            case 3: return 0.05
            default: return (cameraModelID == 2 ? 0.20 : 0.0)
            }
        }()
        let cameraFlareStrengthArg = Float(max(0.0, min(1.0, doubleArg(
            "--camera-flare",
            default: presentationModeID == 4 ? cameraFlareDefault : Double(cameraCalibration.flareStrength ?? Float(cameraFlareDefault))
        ))))
        if cameraProfileID < 2 && cameraModelID != 2 && cameraFlareStrengthArg > 1e-6 {
            FileHandle.standardError.write(Data("warn: --camera-flare is only active for cinematic/photo camera profiles\n".utf8))
        }

        let lensFNumberDefault: Double = {
            if let f = cameraCalibration.lensFNumber { return Double(f) }
            if cameraModelID == 2 || cameraProfileID == 2 { return 2.8 }
            if cameraProfileID == 3 { return 4.0 }
            return 8.0
        }()
        let lensFNumberArg = Float(max(0.7, doubleArg("--camera-f-number", default: lensFNumberDefault)))
        let cameraISOArg = Float(max(1.0, min(409600.0, doubleArg("--camera-iso", default: 100.0))))
        let cameraShutterSecondsArg = Float(max(1e-6, min(3600.0, Self.positiveSecondsArg("--camera-shutter", default: 1.0 / 60.0))))
        let lensFocusDefault = Double(cameraCalibration.lensFocusDepth ?? 4.35)
        let lensFocusDepthArg = Float(max(0.0, doubleArg("--camera-focus-depth", default: lensFocusDefault)))
        let lensDofDefault: Double = {
            if presentationModeID == 4 { return 0.0 }
            if let s = cameraCalibration.lensDofStrength { return Double(s) }
            return (cameraModelID == 2 || cameraProfileID >= 2) ? 1.0 : 0.0
        }()
        let lensDofStrengthArg = Float(max(0.0, min(4.0, doubleArg("--camera-dof-strength", default: lensDofDefault))))
        let apertureBladesArg = UInt32(max(0, min(16, intArg("--camera-aperture-blades", default: Int(cameraCalibration.apertureBlades ?? 7)))))
        let apertureRotationTurns = Float(doubleArg("--camera-aperture-rotation", default: Double(cameraCalibration.apertureRotation ?? 0.0)))
        let dofByte = UInt32(max(0, min(255, Int(round(Double(lensDofStrengthArg) / 4.0 * 255.0)))))
        let rotationTurns = apertureRotationTurns - floor(apertureRotationTurns)
        let rotationByte = UInt32(max(0, min(255, Int(round(Double(rotationTurns) * 255.0)))))
        let cameraFlags = (apertureBladesArg & 0xff) | ((rotationByte & 0xff) << 8) | ((dofByte & 0xff) << 16)
        var cameraColorParams = cameraCalibration.colorParams
        cameraColorParams.z = lensFNumberArg
        cameraColorParams.w = lensFocusDepthArg

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
            switch presentationModeID {
            case 1: return "off"
            case 4: return "off"
            case 2, 3: return "stars"
            default: break
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
            if presentationModeID == 2 { return 0.24 }
            return (composeLookID == 6) ? 0.72 : 1.0
        }()))))
        let backgroundStarStrengthArg = Float(max(0.0, min(4.0, doubleArg("--bg-star-strength", default: {
            if backgroundModeID == 0 { return 0.0 }
            if presentationModeID == 2 { return 0.22 }
            return (composeLookID == 6) ? 0.70 : 1.0
        }()))))
        let backgroundNebulaStrengthArg = Float(max(0.0, min(2.0, doubleArg("--bg-nebula-strength", default: {
            if backgroundModeID == 0 { return 0.0 }
            if presentationModeID == 2 { return 0.18 }
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
        let exposureModeName = stringArg("--exposure-mode", default: presentationModeID == 4 ? "fixed" : "auto").lowercased()
        let exposureModeID: UInt32
        switch exposureModeName {
        case "auto":
            exposureModeID = 0
        case "fixed":
            exposureModeID = 1
        case "photographic", "photo", "camera", "manual-camera":
            exposureModeID = 2
        default:
            fail("invalid --exposure-mode \(exposureModeName). use one of: auto, fixed, photographic")
        }
        if presentationModeID == 4 {
            if composeLookID != 4 {
                fail("camera-raw requires --look linear/none so the RAW-like audit path stays display-neutral")
            }
            if abs(composeDitherArg) > 1e-6 {
                fail("camera-raw requires --dither 0 so display dithering cannot enter the RAW-like audit path")
            }
            if cameraPsfSigmaArg > 1e-6 || cameraReadNoiseArg > 1e-6 || cameraShotNoiseArg > 1e-6 || cameraFlareStrengthArg > 1e-6 || lensDofStrengthArg > 1e-6 {
                fail("camera-raw requires PSF, read noise, shot noise, flare, and depth of field disabled")
            }
            if backgroundModeID != 0 {
                fail("camera-raw requires --background off so background presentation does not enter the RAW-like audit path")
            }
            if exposureModeID != 1 {
                fail("camera-raw requires --exposure-mode fixed for reproducible RAW-like audit output")
            }
        }
        let exposureEVArg = doubleArg("--exposure-ev", default: 0.0)
        let photographicExposureScale = Float(max(
            0.0,
            100.0
                * Double(cameraShutterSecondsArg)
                * (Double(cameraISOArg) / 100.0)
                / max(0.49, Double(lensFNumberArg * lensFNumberArg))
                * pow(2.0, exposureEVArg)
        ))
        if exposureModeID == 2 {
            let referencePhotonTerm = (1.0 / 60.0) / (2.8 * 2.8)
            let photonTerm = Double(cameraShutterSecondsArg) / max(0.49, Double(lensFNumberArg * lensFNumberArg))
            let photonRatio = max(1e-4, photonTerm / referencePhotonTerm)
            let isoGain = max(0.01, Double(cameraISOArg) / 100.0)
            if !cameraReadNoiseExplicit {
                cameraReadNoiseArg = Float(min(Double(cameraReadNoiseArg) * sqrt(isoGain), 0.05))
            }
            if !cameraShotNoiseExplicit {
                cameraShotNoiseArg = Float(min(Double(cameraShotNoiseArg) * sqrt(isoGain / photonRatio), 0.08))
            }
        }
        let composePrecisionName = stringArg("--compose-precision", default: "precise").lowercased()
        let composePrecisionID: UInt32 = (composePrecisionName == "fast") ? 0 : 1

        let composePolicy = ParamsBuilderPolicy.resolveComposePolicy(
            diskPhysicsModeID: diskPhysicsModeID,
            diskPrecisionCloudsEnabled: diskPrecisionCloudsEnabled,
            precisionVolumeEnabled: precisionVolumeEnabled,
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
        case "raw-g", "g-raw", "gfactor-raw", "raw-gfactor", "raw-redshift", "redshift-raw":
            realismDebugID = 43
        case "same-tetrad-g", "same-tetrad-redshift", "local-g", "local-redshift", "static-local-g":
            realismDebugID = 44
        case "emissivity", "emissivity-pre-transfer", "source-emissivity", "radial", "nt":
            realismDebugID = 32
        case "beaming", "asymmetry", "approach":
            realismDebugID = 33
        case "photosphere", "body", "surface":
            realismDebugID = 34
        case "atmosphere", "absorption", "skin", "hot-skin", "grmhd-skin", "perturbation-only":
            realismDebugID = 35
        case "corona", "atlas-activity":
            realismDebugID = 36
        case "perturbation", "turbulence", "disk-noise", "perturbation-ratio", "skin-ratio", "branch-ratio", "branch-ratios":
            realismDebugID = 37
        case "hdr", "raw-radiance", "radiance-post-transfer", "pretonemap", "pre-tone", "pre-tone-map":
            realismDebugID = 38
        case "temperature", "temp", "teff", "observed-temperature":
            realismDebugID = 39
        case "tau", "optical-depth", "opticaldepth":
            realismDebugID = 40
        case "density", "rho":
            realismDebugID = 41
        case "activity", "heating", "heating-field":
            realismDebugID = 42
        case "opacity", "alpha", "radial-tau", "radialtau", "opacity-baseline", "tau-baseline":
            realismDebugID = 42
        case "transfer-saturation", "saturation":
            realismDebugID = 42
        case "spiral", "spiral-wave":
            realismDebugID = 42
        case "clump", "clumps", "cloud", "clouds":
            realismDebugID = 42
        case "hot-crescent", "crescent":
            realismDebugID = 42
        case "final-rgb", "final":
            realismDebugID = 38
        default:
            fail("invalid --realism-debug \(realismDebugName). use one of: off, g, raw-g, same-tetrad-g, beaming, emissivity-pre-transfer, body, skin, corona, branch-ratio, raw-radiance, final-rgb, temperature, density, opacity, optical-depth, transfer-saturation, activity, spiral, clump, hot-crescent")
        }
        if realismDebugID != 0 && composeLookID != 6 && presentationModeID != 1 {
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
            if composeAnalysisMode != 0 && composeAnalysisMode != 31 && composeAnalysisMode != 32 { return false }
            if exposureArg > 0 { return false }
            if exposureModeID == 1 { return false }
            if exposureModeID == 2 { return false }
            return true
        }()
        let composeExposureBase: Float = {
            // Canonical branch-isolated radiance debug modes are absolute source
            // outputs. Honor the requested fixed/manual exposure so body/skin/corona
            // can be compared on the same display scale as the total scientific
            // image. Unit diagnostic maps such as ratios/activity keep exposure=1.
            if composeAnalysisMode == 34 || composeAnalysisMode == 35 || composeAnalysisMode == 36 || composeAnalysisMode == 38 {
                if exposureArg > 0 { return exposureArg }
                if exposureModeID == 1 { return Float(pow(2.0, exposureEVArg)) }
                if exposureModeID == 2 { return photographicExposureScale }
            }
            if composeAnalysisMode != 0 { return 1.0 }
            if exposureArg > 0 { return exposureArg }
            if exposureModeID == 1 { return Float(pow(2.0, exposureEVArg)) }
            if exposureModeID == 2 { return photographicExposureScale }
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
            presentationModeName: presentationModeName,
            presentationModeID: presentationModeID,
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
            cameraColorParams: cameraColorParams,
            cameraFlags: cameraFlags,
            cameraPsfSigmaArg: cameraPsfSigmaArg,
            cameraReadNoiseArg: cameraReadNoiseArg,
            cameraShotNoiseArg: cameraShotNoiseArg,
            cameraFlareStrengthArg: cameraFlareStrengthArg,
            cameraFNumberArg: lensFNumberArg,
            cameraISOArg: cameraISOArg,
            cameraShutterSecondsArg: cameraShutterSecondsArg,
            photographicExposureScale: photographicExposureScale,
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
