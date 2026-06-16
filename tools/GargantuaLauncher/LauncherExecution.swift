import AppKit
import Combine
import SwiftUI

@MainActor
final class LauncherModel: ObservableObject {
    let sourceModels: [SourceModelOption]
    let renderIntents: [RenderIntentOption]

    @Published var selectedSourceID = "canonical-visible-disk-v1"
    @Published var observerMode: ObserverMode = .eye
    @Published var renderIntentID = "rendered"
    @Published var quality: RenderQuality = .preview
    @Published var aspect: OutputAspect = .hd
    @Published var customWidth = 1536
    @Published var customHeight = 864
    @Published var ssaa: RenderSampling = .one
    @Published var noBuild = true
    @Published var metricKerr = true
    @Published var showAdvancedPhysics = false
    @Published var spin = 0.6
    @Published var rayBundleMode: RayBundleMode = .off
    @Published var rayBundleJacobianStrength = 1.0
    @Published var rayBundleFootprintClamp = 6.0
    @Published var useCustomCamera = false
    @Published var camX = 0.0
    @Published var camY = -18.0
    @Published var camZ = 5.5
    @Published var fov = 58.0
    @Published var roll = 0.0
    @Published var exposureProgram: CameraExposureProgram = .manual
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
    @Published var eyePhotometric: EyePhotometricMode = .auto
    @Published var useEyeND = false
    @Published var eyeND = 4.0
    @Published var useEyeAdaptation = false
    @Published var eyeAdaptation = 2000.0
    @Published var diskHDF5Path = "/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5"
    @Published var outputPath = "/private/tmp/gargantua_gui_render.png"
    @Published var logText = "Ready."
    @Published var progressFraction = 0.0
    @Published var progressLabel = "Ready"
    @Published var previewImage: NSImage?
    @Published var previewStatus = "No render loaded."
    @Published var isRunning = false

    private var runningProcess: Process?
    private var runningReadHandle: FileHandle?
    private var previewTimer: Timer?

    init() {
        let manifest = LauncherOptionsManifest.load()
        self.sourceModels = manifest.sourceModels
        self.renderIntents = manifest.renderIntents
        refreshPreview()
    }

    var selectedSource: SourceModelOption {
        sourceModels.first { $0.id == selectedSourceID } ?? sourceModels[0]
    }

    var selectedIntent: RenderIntentOption {
        renderIntents.first { $0.id == renderIntentID } ?? renderIntents[1]
    }

    var isCameraMode: Bool {
        observerMode == .camera
    }

    var isRawLikeCamera: Bool {
        isCameraMode && renderIntentID == "raw-like"
    }

    var isCameraAdjustmentEnabled: Bool {
        isCameraMode && renderIntentID != "raw-like"
    }

    var selectedSourceRequiresDiskHDF5: Bool {
        selectedSource.requiresDiskHDF5 ?? false
    }

    var outputSize: (width: Int, height: Int) {
        aspect.size(customWidth: customWidth, customHeight: customHeight)
    }

    var commandPlan: RenderCommandPlan {
        RenderCommandPlanner.plan(for: commandInputs)
    }

    var commandPreview: String {
        commandPlan.commandPreview
    }

    func runRender() {
        guard !isRunning else { return }
        isRunning = true
        progressFraction = 0.04
        progressLabel = "Preparing command"
        let plan = commandPlan
        logText = "Running...\n\n\(plan.commandPreview)"
        startPreviewTimer()

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
            }
        }

        process.terminationHandler = { [weak self] proc in
            readHandle.readabilityHandler = nil
            let data = readHandle.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.finishRender(status: proc.terminationStatus, trailingText: text)
            }
        }

        do {
            try process.run()
            progressLabel = "Process started"
            progressFraction = max(progressFraction, 0.10)
        } catch {
            isRunning = false
            runningProcess = nil
            runningReadHandle = nil
            stopPreviewTimer()
            progressFraction = 0
            progressLabel = "Failed to start"
            logText = "Failed to start render: \(error.localizedDescription)"
        }
    }

    func stopRender() {
        guard isRunning else { return }
        appendLog("Stopping render...")
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

    func refreshPreview() {
        let url = URL(fileURLWithPath: outputPath)
        if let image = NSImage(contentsOf: url) {
            previewImage = image
            previewStatus = url.lastPathComponent
        } else {
            previewImage = nil
            previewStatus = FileManager.default.fileExists(atPath: outputPath)
                ? "Output exists but could not be decoded."
                : "No render loaded."
        }
    }

    func orbitCamera(deltaX: CGFloat, deltaY: CGFloat) {
        let radius = max(2.0, sqrt(camX * camX + camY * camY))
        let angle = atan2(camY, camX) + Double(deltaX) * 0.008
        camX = cos(angle) * radius
        camY = sin(angle) * radius
        camZ = min(max(camZ - Double(deltaY) * 0.035, -20.0), 20.0)
        useCustomCamera = true
    }

    private var commandInputs: RenderCommandInputs {
        RenderCommandInputs(
            source: selectedSource,
            observerMode: observerMode,
            renderIntentID: renderIntentID,
            quality: quality,
            aspect: aspect,
            customWidth: customWidth,
            customHeight: customHeight,
            ssaa: ssaa,
            noBuild: noBuild,
            showAdvancedPhysics: showAdvancedPhysics,
            metricKerr: metricKerr,
            spin: spin,
            rayBundleMode: rayBundleMode,
            rayBundleJacobianStrength: rayBundleJacobianStrength,
            rayBundleFootprintClamp: rayBundleFootprintClamp,
            useCustomCamera: useCustomCamera,
            camX: camX,
            camY: camY,
            camZ: camZ,
            fov: fov,
            roll: roll,
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

    private func appendLog(_ text: String) {
        logText += "\n" + text
        updateProgress(from: text)
    }

    private func finishRender(status: Int32, trailingText: String) {
        isRunning = false
        runningProcess = nil
        runningReadHandle = nil
        stopPreviewTimer()
        if !trailingText.isEmpty {
            appendLog(trailingText)
        }
        if status == 0 {
            progressFraction = 1.0
            progressLabel = "Finished"
        } else {
            progressLabel = "Exited with status \(status)"
        }
        logText += "\nRender finished with status \(status)."
        refreshPreview()
    }

    private func updateProgress(from text: String) {
        let lower = text.lowercased()
        let staged: [(String, Double, String)] = [
            ("build", 0.20, "Building renderer"),
            ("render config", 0.30, "Resolving configuration"),
            ("trace", 0.48, "Tracing rays"),
            ("collisions", 0.56, "Writing ray data"),
            ("compose", 0.74, "Composing presentation"),
            ("linear32", 0.82, "Writing diagnostics"),
            ("output", 0.90, "Writing output"),
            ("wrote", 0.92, "Writing output")
        ]
        for (needle, fraction, label) in staged where lower.contains(needle) {
            if fraction > progressFraction {
                progressFraction = fraction
                progressLabel = label
            }
        }
    }

    private func startPreviewTimer() {
        stopPreviewTimer()
        previewTimer = Timer.scheduledTimer(withTimeInterval: 1.5, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.refreshPreview()
            }
        }
    }

    private func stopPreviewTimer() {
        previewTimer?.invalidate()
        previewTimer = nil
    }
}
