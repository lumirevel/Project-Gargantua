import Foundation

struct RenderCommandInputs {
    let source: SourceModelOption
    let observerMode: ObserverMode
    let renderIntentID: String
    let quality: RenderQuality
    let aspect: OutputAspect
    let noBuild: Bool
    let showAdvancedPhysics: Bool
    let metricKerr: Bool
    let spin: Double
    let enableColorGrade: Bool
    let allowExperimentalCinematicControls: Bool
    let enableCinematicEffects: Bool
    let enableDepthOfField: Bool
    let flareStrength: Double
    let fNumber: Double
    let iso: Double
    let shutter: String
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

        let size = inputs.aspect.size
        args.append(contentsOf: ["--width", "\(size.width)", "--height", "\(size.height)"])

        if inputs.showAdvancedPhysics && inputs.metricKerr {
            args.append(contentsOf: ["--metric", "kerr", "--spin", formatted(inputs.spin)])
        }

        switch inputs.observerMode {
        case .eye:
            args.append(contentsOf: eyeArguments())
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

    private static func eyeArguments() -> [String] {
        [
            "--presentation", "eye",
            "--camera-model", "eye",
            "--realism-profile", "physical",
            "--look", "realistic"
        ]
    }

    private static func cameraArguments(_ inputs: RenderCommandInputs, outputPath: String) -> [String] {
        if inputs.renderIntentID == "raw-like" {
            return rawLikeCameraArguments(outputPath: outputPath)
        }

        var args: [String] = [
            "--presentation", inputs.renderIntentID == "cinematic" ? "cinema" : "camera-rendered",
            "--camera-model", "cinematic",
            "--exposure-mode", "photographic",
            "--camera-f-number", formatted(inputs.fNumber),
            "--camera-iso", formatted(inputs.iso),
            "--camera-shutter", inputs.shutter
        ]

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
