import Foundation

struct RenderCommandInputs {
    let source: SourceModelOption
    let observerMode: ObserverMode
    let renderIntentID: String
    let quality: RenderQuality
    let aspect: OutputAspect
    let customWidth: Int
    let customHeight: Int
    let ssaa: RenderSampling
    let noBuild: Bool
    let showAdvancedPhysics: Bool
    let metricKerr: Bool
    let spin: Double
    let rayBundleMode: RayBundleMode
    let rayBundleJacobianStrength: Double
    let rayBundleFootprintClamp: Double
    let useCustomCamera: Bool
    let camX: Double
    let camY: Double
    let camZ: Double
    let fov: Double
    let roll: Double
    let exposureProgram: CameraExposureProgram
    let exposureEV: Double
    let enableColorGrade: Bool
    let allowExperimentalCinematicControls: Bool
    let enableCinematicEffects: Bool
    let enableDepthOfField: Bool
    let flareStrength: Double
    let diffractionStrength: Double
    let fNumber: Double
    let iso: Double
    let shutter: String
    let focusDepth: Double
    let motionBlurSamples: Int
    let motionBlurTimeLapse: Double
    let cameraPhotonNoise: CameraPhotonNoiseMode
    let cameraPhotonScale: Double
    let psfSigma: Double
    let readNoise: Double
    let shotNoise: Double
    let eyePhotometric: EyePhotometricMode
    let useEyeND: Bool
    let eyeND: Double
    let useEyeAdaptation: Bool
    let eyeAdaptation: Double
    let diskHDF5Path: String
    let outputPath: String
}

struct RenderCommandPlan {
    let executablePath: String
    let repositoryRoot: URL
    let arguments: [String]
    let outputPath: String

    var rawBufferPath: String {
        outputPath + ".raw.linear32f32"
    }

    var sensorRawBufferPath: String {
        outputPath + ".bayer-rggb-f32.raw"
    }

    var commandPreview: String {
        ([executablePath] + arguments).map(Self.shellQuoted).joined(separator: " ")
    }

    private static func shellQuoted(_ value: String) -> String {
        if value.range(of: #"[^A-Za-z0-9_@%+=:,./-]"#, options: .regularExpression) == nil {
            return value
        }
        return "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}

enum RenderCommandPlanner {
    static func plan(for inputs: RenderCommandInputs) -> RenderCommandPlan {
        let outputPath = inputs.outputPath
        var args: [String] = []
        args.append(contentsOf: inputs.source.args)
        if inputs.source.requiresDiskHDF5 ?? false {
            args.append(contentsOf: ["--disk-hdf5", effectiveDiskHDF5Path(inputs)])
        }
        args.append(contentsOf: ["--quality", inputs.quality.rawValue])

        let size = inputs.aspect.size(customWidth: inputs.customWidth, customHeight: inputs.customHeight)
        args.append(contentsOf: ["--width", "\(size.width)", "--height", "\(size.height)"])
        args.append(contentsOf: ["--ssaa", inputs.ssaa.rawValue])

        if inputs.showAdvancedPhysics && inputs.metricKerr {
            args.append(contentsOf: ["--metric", "kerr", "--spin", formatted(inputs.spin)])
        }
        if inputs.showAdvancedPhysics {
            appendRayBundleArguments(inputs, to: &args)
        }
        if inputs.useCustomCamera {
            args.append(contentsOf: [
                "--camX", formatted(inputs.camX),
                "--camY", formatted(inputs.camY),
                "--camZ", formatted(inputs.camZ),
                "--fov", formatted(inputs.fov),
                "--roll", formatted(inputs.roll)
            ])
        }

        switch inputs.observerMode {
        case .eye:
            args.append(contentsOf: eyeArguments(inputs))
        case .camera:
            args.append(contentsOf: cameraArguments(inputs, outputPath: outputPath))
        }

        if inputs.noBuild {
            args.append("--no-build")
        }
        args.append(contentsOf: ["--output", outputPath])
        return RenderCommandPlan(
            executablePath: ProjectPaths.runPipelineURL.path,
            repositoryRoot: ProjectPaths.repositoryRoot,
            arguments: args,
            outputPath: outputPath
        )
    }

    private static func effectiveDiskHDF5Path(_ inputs: RenderCommandInputs) -> String {
        let explicit = inputs.diskHDF5Path.trimmingCharacters(in: .whitespacesAndNewlines)
        if !explicit.isEmpty {
            return explicit
        }
        return inputs.source.defaultDiskHDF5 ?? ""
    }

    private static func appendRayBundleArguments(_ inputs: RenderCommandInputs, to args: inout [String]) {
        guard inputs.rayBundleMode != .off else { return }
        args.append(contentsOf: ["--ray-bundle", inputs.rayBundleMode.rawValue])
        if inputs.rayBundleMode == .jacobian {
            args.append(contentsOf: [
                "--ray-bundle-jacobian-strength", formatted(inputs.rayBundleJacobianStrength),
                "--ray-bundle-footprint-clamp", formatted(inputs.rayBundleFootprintClamp)
            ])
        }
    }

    private static func eyeArguments(_ inputs: RenderCommandInputs) -> [String] {
        var args = [
            "--presentation", "eye",
            "--camera-model", "eye",
            "--realism-profile", "physical",
            "--look", "realistic"
        ]
        args.append(contentsOf: ["--eye-photometric", inputs.eyePhotometric.rawValue])
        if inputs.useEyeND {
            args.append(contentsOf: ["--eye-nd", formatted(inputs.eyeND)])
        }
        if inputs.useEyeAdaptation {
            args.append(contentsOf: ["--eye-adaptation", formatted(inputs.eyeAdaptation)])
        }
        return args
    }

    private static func cameraArguments(_ inputs: RenderCommandInputs, outputPath: String) -> [String] {
        if inputs.renderIntentID == "raw-like" {
            return rawLikeCameraArguments(outputPath: outputPath)
        }

        var args: [String] = [
            "--presentation", inputs.renderIntentID == "cinematic" ? "cinema" : "camera-rendered",
            "--camera-model", "cinematic"
        ]
        args.append(contentsOf: exposureArguments(inputs))

        if inputs.renderIntentID == "cinematic" {
            args.append(contentsOf: [
                "--camera-profile", "cinema-digital",
                "--look", inputs.enableColorGrade ? "sensor-filmic" : "linear",
                "--realism-profile", "cinematic",
                "--camera-flare", formatted((inputs.allowExperimentalCinematicControls && inputs.enableCinematicEffects) ? inputs.flareStrength : 0.0),
                "--camera-dof-strength", formatted((inputs.allowExperimentalCinematicControls && inputs.enableDepthOfField) ? 1.0 : 0.0),
                "--camera-aperture-blades", "7"
            ])
        } else {
            args.append(contentsOf: [
                "--camera-profile", "full-frame",
                "--look", inputs.enableColorGrade ? "agx" : "linear",
                "--realism-profile", "observational",
                "--camera-flare", formatted((inputs.allowExperimentalCinematicControls && inputs.enableCinematicEffects) ? inputs.flareStrength : 0.0),
                "--camera-dof-strength", formatted((inputs.allowExperimentalCinematicControls && inputs.enableDepthOfField) ? 0.6 : 0.0)
            ])
        }
        args.append(contentsOf: opticalAndSensorArguments(inputs))
        return args
    }

    private static func exposureArguments(_ inputs: RenderCommandInputs) -> [String] {
        switch inputs.exposureProgram {
        case .manual:
            return [
                "--exposure-mode", "photographic",
                "--camera-f-number", formatted(inputs.fNumber),
                "--camera-shutter", inputs.shutter,
                "--camera-iso", formatted(inputs.iso),
                "--photographic-calibration", "photometric"
            ]
        case .auto:
            return [
                "--exposure-mode", "auto",
                "--camera-f-number", formatted(inputs.fNumber),
                "--camera-iso", formatted(inputs.iso)
            ]
        case .aperturePriority:
            return [
                "--exposure-mode", "auto",
                "--exposure-ev", formatted(inputs.exposureEV),
                "--camera-f-number", formatted(inputs.fNumber),
                "--camera-iso", formatted(inputs.iso)
            ]
        case .shutterPriority:
            return [
                "--exposure-mode", "auto",
                "--exposure-ev", formatted(inputs.exposureEV),
                "--camera-shutter", inputs.shutter,
                "--camera-iso", formatted(inputs.iso)
            ]
        case .fixedEV:
            return [
                "--exposure-mode", "fixed",
                "--exposure-ev", formatted(inputs.exposureEV)
            ]
        }
    }

    private static func opticalAndSensorArguments(_ inputs: RenderCommandInputs) -> [String] {
        var args: [String] = [
            "--camera-diffraction", formatted(inputs.diffractionStrength),
            "--camera-psf-sigma", formatted(inputs.psfSigma),
            "--camera-read-noise", formatted(inputs.readNoise),
            "--camera-shot-noise", formatted(inputs.shotNoise),
            "--camera-photon-noise", inputs.cameraPhotonNoise.rawValue,
            "--camera-photon-scale", formatted(inputs.cameraPhotonScale)
        ]
        if inputs.allowExperimentalCinematicControls && inputs.enableDepthOfField {
            args.append(contentsOf: ["--camera-focus-depth", formatted(inputs.focusDepth)])
        }
        if inputs.motionBlurSamples > 1 {
            args.append(contentsOf: [
                "--motion-blur-samples", "\(min(max(inputs.motionBlurSamples, 1), 64))",
                "--motion-blur-time-lapse", formatted(inputs.motionBlurTimeLapse)
            ])
        }
        return args
    }

    private static func rawLikeCameraArguments(outputPath: String) -> [String] {
        [
            "--presentation", "camera-raw",
            "--camera-model", "legacy",
            "--camera-profile", "ideal",
            "--look", "linear",
            "--exposure-mode", "fixed",
            "--exposure-ev", "0",
            "--camera-psf-sigma", "0",
            "--camera-read-noise", "0",
            "--camera-shot-noise", "0",
            "--camera-flare", "0",
            "--camera-dof-strength", "0",
            "--background", "off",
            "--hdr-intermediate",
            "--hdr-out", outputPath + ".raw.linear32f32",
            "--camera-raw-out", outputPath + ".bayer-rggb-f32.raw"
        ]
    }

    private static func formatted(_ value: Double) -> String {
        String(format: "%.4g", value)
    }
}
