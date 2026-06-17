import AppKit
import Combine
import SwiftUI

@MainActor
final class LauncherModel: ObservableObject {
    let sourceModels: [SourceModelOption]
    let renderIntents: [RenderIntentOption]

    // MARK: Black hole / source / observer
    @Published var blackHoleMetric: BlackHoleMetric = .kerr
    @Published var spin = 0.6
    @Published var selectedSourceID = "canonical-visible-disk-v1"
    @Published var observerMode: ObserverMode = .eye
    @Published var renderIntentID = "rendered"

    // MARK: Final render setup
    @Published var quality: RenderQuality = .preview
    @Published var aspect: OutputAspect = .hd
    @Published var customWidth = 1536
    @Published var customHeight = 864
    @Published var ssaa: RenderSampling = .one
    @Published var noBuild = true
    @Published var showAdvancedPhysics = false
    @Published var rayBundleMode: RayBundleMode = .off
    @Published var rayBundleJacobianStrength = 1.0
    @Published var rayBundleFootprintClamp = 6.0

    // MARK: Interactive preview camera + settings
    let camera = OrbitCameraController()
    let previewStats = PreviewStats()
    @Published var linkPreviewCameraToRender = true
    @Published var previewQuality: PreviewQuality = .medium

    // MARK: Camera interpreter
    @Published var exposureProgram: CameraExposureProgram = .manual
    @Published var exposureGranularity: ExposureControlGranularity = .stops
    @Published var exposureEV = 0.0
    @Published var enableColorGrade = false
    @Published var allowExperimentalCinematicControls = false
    @Published var enableCinematicEffects = false
    @Published var enableDepthOfField = false
    @Published var flareStrength = 0.2
    @Published var diffractionStrength = 0.02
    @Published var fNumber = 4.0
    @Published var iso = 100.0
    @Published var shutter = "1/60"
    @Published var focusDepth = 20.0
    @Published var motionBlurSamples = 1.0
    @Published var motionBlurTimeLapse = 1.0
    @Published var cameraPhotonNoise: CameraPhotonNoiseMode = .auto
    @Published var cameraPhotonScale = 1.0
    @Published var psfSigma = 0.0
    @Published var readNoise = 0.0
    @Published var shotNoise = 0.0

    // MARK: Eye interpreter
    @Published var eyePhotometric: EyePhotometricMode = .auto
    @Published var useEyeND = false
    @Published var eyeND = 4.0
    @Published var useEyeAdaptation = false
    @Published var eyeAdaptation = 2000.0

    // MARK: Output / execution
    @Published var diskHDF5Path = "/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5"
    @Published var outputPath = "/private/tmp/gargantua_gui_render.png"
    @Published var logText = "Ready."
    @Published var progressFraction = 0.0
    @Published var progressLabel = "Ready"
    @Published var progressWorkLabel = ""
    @Published var resultImage: NSImage?
    @Published var resultStatus = "No final render loaded."
    @Published var isRunning = false

    private var runningProcess: Process?
    private var runningReadHandle: FileHandle?

    init() {
        let manifest = LauncherOptionsManifest.load()
        self.sourceModels = manifest.sourceModels
        self.renderIntents = manifest.renderIntents
        refreshResult()
    }

    var selectedSource: SourceModelOption {
        sourceModels.first { $0.id == selectedSourceID } ?? sourceModels[0]
    }

    var selectedIntent: RenderIntentOption {
        renderIntents.first { $0.id == renderIntentID } ?? renderIntents[1]
    }

    var isCameraMode: Bool { observerMode == .camera }
    var isRawLikeCamera: Bool { isCameraMode && renderIntentID == "raw-like" }
    var isCameraAdjustmentEnabled: Bool { isCameraMode && renderIntentID != "raw-like" }
    var selectedSourceRequiresDiskHDF5: Bool { selectedSource.requiresDiskHDF5 ?? false }

    var outputSize: (width: Int, height: Int) {
        aspect.size(customWidth: customWidth, customHeight: customHeight)
    }

    var commandPlan: RenderCommandPlan { RenderCommandPlanner.plan(for: commandInputs) }
    var commandPreview: String { commandPlan.commandPreview }

    // MARK: - Interactive preview bindings

    /// GUI option panels gathered into the renderer-facing settings struct.
    var previewRenderSettings: PreviewRenderSettings {
        let metric: PreviewMetric = blackHoleMetric == .kerr ? .kerr : .schwarzschild
        let spinValue: Float = blackHoleMetric == .kerr ? Float(spin) : 0
        let inner = PreviewPhysics.diskInnerRadius(metric: metric, spin: spinValue)
        // The disk appearance is derived entirely from the selected accretion
        // source model and the physics — there are no preview-only disk knobs,
        // so the preview matches the final render's inputs (only quality differs).
        let style = PreviewDiskStyle.preset(forSourceID: selectedSourceID)
        let outer = max(style.outer, inner + 2.0)
        return PreviewRenderSettings(
            metric: metric,
            spin: spinValue,
            diskInner: inner,
            diskOuter: outer,
            diskThickness: style.thickness,
            diskDensity: style.density,
            diskBrightness: style.brightnessScale,
            diskTempScale: style.tempScale,
            diskTurbulence: style.turbulence,
            diskNoiseScale: style.noiseScale,
            diskSpiralArms: style.spiralArms,
            diskSpiralStrength: style.spiralStrength,
            exposure: previewExposureGain,
            toneMap: previewToneMapDerived,
            saturation: previewSaturation,
            backgroundStars: isRawLikeCamera ? 0.0 : 1.0,
            quality: previewQuality
        )
    }

    /// Scene exposure inferred from the observer / camera-interpreter options,
    /// so changing exposure mode, ISO, shutter, aperture or EV is reflected in
    /// the preview (the preview mirrors the final look at lower quality).
    var previewExposureGain: Float {
        if observerMode == .eye {
            var e = 1.0
            if useEyeND { e *= pow(2.0, -eyeND) }
            return Float(min(max(e, 0.03), 12.0))
        }
        if isRawLikeCamera { return 1.0 }
        var gain: Double
        switch exposureProgram {
        case .manual:
            let reference = 100.0 * (1.0 / 60.0) / (4.0 * 4.0) // ISO100, 1/60s, f/4
            gain = (iso * shutterSeconds(shutter) / (fNumber * fNumber)) / reference
        case .auto:
            gain = 1.0 // auto-exposure normalizes brightness
        case .aperturePriority, .shutterPriority, .fixedEV:
            gain = pow(2.0, exposureEV)
        }
        return Float(min(max(gain, 0.02), 16.0))
    }

    /// Tone-mapping operator inferred from the observer mode and camera look.
    var previewToneMapDerived: PreviewToneMap {
        if isRawLikeCamera { return .linear }
        if observerMode == .eye { return .aces }
        if renderIntentID == "cinematic" { return .aces }
        return enableColorGrade ? .aces : .reinhard
    }

    /// Saturation inferred from the camera look / colour grade.
    var previewSaturation: Float {
        if isRawLikeCamera { return 1.0 }
        if observerMode == .camera && (enableColorGrade || renderIntentID == "cinematic") {
            return 1.32
        }
        return 1.12
    }

    private func shutterSeconds(_ text: String) -> Double {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        if trimmed.contains("/") {
            let parts = trimmed.split(separator: "/")
            if parts.count == 2, let a = Double(parts[0]), let b = Double(parts[1]), b != 0 {
                return a / b
            }
        }
        return Double(trimmed) ?? (1.0 / 60.0)
    }

    func setPreviewRadius(_ value: Double) { camera.setRadius(value); objectWillChange.send() }
    func setPreviewAzimuth(_ value: Double) { camera.setAzimuthDegrees(value); objectWillChange.send() }
    func setPreviewElevation(_ value: Double) { camera.setElevationDegrees(value); objectWillChange.send() }
    func setPreviewFov(_ value: Double) { camera.setFov(value); objectWillChange.send() }
    func resetPreviewCamera() { camera.reset(); objectWillChange.send() }

    /// Called when an interactive drag/zoom finishes so dependent UI (camera
    /// sliders, generated command) refreshes to the committed pose.
    func previewCameraDidCommit() { objectWillChange.send() }

    // MARK: - Final render

    func runRender() {
        guard !isRunning else { return }
        let plan = commandPlan
        isRunning = true
        progressFraction = 0.01
        progressLabel = "Preparing final render"
        progressWorkLabel = workLabel(for: plan)
        logText = "Running final render...\n\n\(plan.commandPreview)"
        startProcess(plan: plan)
    }

    func stopRender() {
        guard isRunning else { return }
        appendLog("Stopping final render...")
        runningProcess?.terminate()
    }

    func copyCommandToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandPreview, forType: .string)
    }

    func chooseDiskHDF5() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.prompt = "Choose"
        if panel.runModal() == .OK, let url = panel.url {
            diskHDF5Path = url.path
        }
    }

    func revealOutput() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
    }

    func refreshResult() {
        let url = URL(fileURLWithPath: outputPath)
        if let image = NSImage(contentsOf: url) {
            resultImage = image
            resultStatus = url.lastPathComponent
        } else {
            resultImage = nil
            resultStatus = FileManager.default.fileExists(atPath: outputPath)
                ? "Final output exists but could not be decoded."
                : "No final render loaded."
        }
    }

    func setFNumberStop(index: Double) {
        let idx = min(max(Int(index.rounded()), 0), CameraStopTables.fNumbers.count - 1)
        fNumber = CameraStopTables.fNumbers[idx]
    }

    func setISOStop(index: Double) {
        let idx = min(max(Int(index.rounded()), 0), CameraStopTables.isoValues.count - 1)
        iso = CameraStopTables.isoValues[idx]
    }

    func setShutterStop(index: Double) {
        let idx = min(max(Int(index.rounded()), 0), CameraStopTables.shutters.count - 1)
        shutter = CameraStopTables.shutters[idx]
    }

    private var commandInputs: RenderCommandInputs {
        let eye = camera.state.eye
        let rollDegrees = Double(camera.state.roll) * 180.0 / .pi
        return RenderCommandInputs(
            source: selectedSource,
            blackHoleMetric: blackHoleMetric,
            spin: spin,
            observerMode: observerMode,
            renderIntentID: renderIntentID,
            quality: quality,
            aspect: aspect,
            customWidth: customWidth,
            customHeight: customHeight,
            outputWidth: outputSize.width,
            outputHeight: outputSize.height,
            ssaa: ssaa,
            noBuild: noBuild,
            rayBundleMode: showAdvancedPhysics ? rayBundleMode : .off,
            rayBundleJacobianStrength: rayBundleJacobianStrength,
            rayBundleFootprintClamp: rayBundleFootprintClamp,
            useCustomCamera: linkPreviewCameraToRender,
            camX: Double(eye.x),
            camY: Double(eye.y),
            camZ: Double(eye.z),
            fov: Double(camera.state.fov),
            roll: rollDegrees,
            exposureProgram: exposureProgram,
            exposureEV: exposureEV,
            enableColorGrade: enableColorGrade,
            allowExperimentalCinematicControls: allowExperimentalCinematicControls,
            enableCinematicEffects: enableCinematicEffects,
            enableDepthOfField: enableDepthOfField,
            flareStrength: flareStrength,
            diffractionStrength: diffractionStrength,
            fNumber: fNumber,
            iso: iso,
            shutter: shutter,
            focusDepth: focusDepth,
            motionBlurSamples: Int(motionBlurSamples.rounded()),
            motionBlurTimeLapse: motionBlurTimeLapse,
            cameraPhotonNoise: cameraPhotonNoise,
            cameraPhotonScale: cameraPhotonScale,
            psfSigma: psfSigma,
            readNoise: readNoise,
            shotNoise: shotNoise,
            eyePhotometric: eyePhotometric,
            useEyeND: useEyeND,
            eyeND: eyeND,
            useEyeAdaptation: useEyeAdaptation,
            eyeAdaptation: eyeAdaptation,
            diskHDF5Path: diskHDF5Path,
            outputPath: outputPath
        )
    }

    private func startProcess(plan: RenderCommandPlan) {
        let process = Process()
        let pipe = Pipe()
        let readHandle = pipe.fileHandleForReading
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [plan.executablePath] + plan.arguments
        process.currentDirectoryURL = plan.repositoryRoot
        var environment = ProcessInfo.processInfo.environment
        let guiPath = [
            environment["PATH"],
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
            "/Applications/Xcode.app/Contents/Developer/usr/bin"
        ].compactMap { $0 }.joined(separator: ":")
        environment["PATH"] = guiPath
        environment["BH_PROJECT_ROOT"] = plan.repositoryRoot.path
        process.environment = environment
        process.standardOutput = pipe
        process.standardError = pipe

        runningProcess = process
        runningReadHandle = readHandle

        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text)
                self?.updateProgress(from: text, plan: plan)
            }
        }

        process.terminationHandler = { [weak self] proc in
            readHandle.readabilityHandler = nil
            let data = readHandle.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.finishProcess(plan: plan, status: proc.terminationStatus, trailingText: text)
            }
        }

        do {
            try process.run()
            progressFraction = max(progressFraction, 0.05)
            progressLabel = "Process started"
        } catch {
            isRunning = false
            runningProcess = nil
            runningReadHandle = nil
            progressFraction = 0
            progressLabel = "Failed to start"
            logText = "Failed to start render: \(error.localizedDescription)"
        }
    }

    private func appendLog(_ text: String) {
        logText += "\n" + text
    }

    private func finishProcess(plan: RenderCommandPlan, status: Int32, trailingText: String) {
        if !trailingText.isEmpty {
            appendLog(trailingText)
            updateProgress(from: trailingText, plan: plan)
        }
        isRunning = false
        runningProcess = nil
        runningReadHandle = nil
        if status == 0 {
            progressFraction = 1.0
            progressLabel = "Finished"
        } else {
            progressLabel = "Exited with status \(status)"
        }
        logText += "\nFinal render finished with status \(status)."
        refreshResult()
    }

    private func updateProgress(from text: String, plan: RenderCommandPlan) {
        let lower = text.lowercased()
        let estimate = plan.progressEstimate
        let staged: [(String, Double, String)] = [
            ("build", estimate.buildEnd, "Building renderer"),
            ("render config", estimate.configEnd, "Resolving configuration"),
            ("trace", estimate.traceEnd, "Tracing rays"),
            ("collisions", estimate.traceEnd, "Writing ray data"),
            ("compose", estimate.composeEnd, "Composing presentation"),
            ("linear32", estimate.composeEnd, "Writing diagnostics"),
            ("output", min(0.96, estimate.outputEnd), "Writing output"),
            ("wrote", min(0.98, estimate.outputEnd), "Writing output")
        ]
        for (needle, fraction, label) in staged where lower.contains(needle) {
            if fraction > progressFraction {
                progressFraction = fraction
                progressLabel = label
            }
        }
    }

    private func workLabel(for plan: RenderCommandPlan) -> String {
        let units = plan.progressEstimate.workUnits
        if units >= 1_000_000 {
            return String(format: "%.1fM work units", units / 1_000_000)
        }
        if units >= 1_000 {
            return String(format: "%.0fk work units", units / 1_000)
        }
        return String(format: "%.0f work units", units)
    }
}
