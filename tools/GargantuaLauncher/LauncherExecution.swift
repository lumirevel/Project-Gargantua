import AppKit
import Combine
import SwiftUI

@MainActor
final class LauncherModel: ObservableObject {
    let sourceModels: [SourceModelOption]
    let renderIntents: [RenderIntentOption]

    @Published var blackHoleMetric: BlackHoleMetric = .kerr
    @Published var spin = 0.6
    @Published var selectedSourceID = "canonical-visible-disk-v1"
    @Published var observerMode: ObserverMode = .eye
    @Published var renderIntentID = "rendered"
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
    @Published var useCustomCamera = false
    @Published var camX = 0.0
    @Published var camY = -18.0
    @Published var camZ = 5.5
    @Published var fov = 58.0
    @Published var roll = 0.0
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
    @Published var eyePhotometric: EyePhotometricMode = .auto
    @Published var useEyeND = false
    @Published var eyeND = 4.0
    @Published var useEyeAdaptation = false
    @Published var eyeAdaptation = 2000.0
    @Published var diskHDF5Path = "/private/tmp/bh_real_grmhd_sequence/SANE_a0_torus.out0.05010.h5"
    @Published var outputPath = "/private/tmp/gargantua_gui_render.png"
    @Published var livePreviewPath = "/private/tmp/gargantua_gui_live_preview.png"
    @Published var livePreviewWidth = 384
    @Published var livePreviewHeight = 216
    @Published var autoLivePreview = false
    @Published var logText = "Ready."
    @Published var progressFraction = 0.0
    @Published var progressLabel = "Ready"
    @Published var progressWorkLabel = ""
    @Published var resultImage: NSImage?
    @Published var resultStatus = "No final render loaded."
    @Published var livePreviewImage: NSImage?
    @Published var livePreviewStatus = "No live preview rendered."
    @Published var isRunning = false
    @Published var isPreviewRunning = false
    @Published var previewProgressFraction = 0.0

    private var runningProcess: Process?
    private var runningReadHandle: FileHandle?
    private var previewProcess: Process?
    private var previewReadHandle: FileHandle?
    private var previewDebounce: Timer?

    init() {
        let manifest = LauncherOptionsManifest.load()
        self.sourceModels = manifest.sourceModels
        self.renderIntents = manifest.renderIntents
        refreshResult()
        refreshLivePreview()
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

    var livePreviewPlan: RenderCommandPlan {
        RenderCommandPlanner.livePreviewPlan(for: commandInputs)
    }

    var commandPreview: String {
        commandPlan.commandPreview
    }

    var livePreviewCommandPreview: String {
        livePreviewPlan.commandPreview
    }

    func runRender() {
        guard !isRunning else { return }
        let plan = commandPlan
        isRunning = true
        progressFraction = 0.01
        progressLabel = "Preparing final render"
        progressWorkLabel = workLabel(for: plan)
        logText = "Running final render...\n\n\(plan.commandPreview)"
        startProcess(plan: plan, isPreview: false)
    }

    func runLivePreview() {
        guard !isPreviewRunning else { return }
        let plan = livePreviewPlan
        isPreviewRunning = true
        previewProgressFraction = 0.02
        livePreviewStatus = "Rendering live preview..."
        appendLog("Running live preview: \(plan.commandPreview)")
        startProcess(plan: plan, isPreview: true)
    }

    func scheduleLivePreview() {
        guard autoLivePreview else { return }
        previewDebounce?.invalidate()
        previewDebounce = Timer.scheduledTimer(withTimeInterval: 0.65, repeats: false) { [weak self] _ in
            Task { @MainActor [weak self] in
                guard let model = self, !model.isPreviewRunning else { return }
                model.runLivePreview()
            }
        }
    }

    func stopRender() {
        guard isRunning else { return }
        appendLog("Stopping final render...")
        runningProcess?.terminate()
    }

    func stopLivePreview() {
        guard isPreviewRunning else { return }
        appendLog("Stopping live preview...")
        previewProcess?.terminate()
    }

    func copyCommandToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(commandPreview, forType: .string)
    }

    func copyLivePreviewCommandToPasteboard() {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(livePreviewCommandPreview, forType: .string)
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
            scheduleLivePreview()
        }
    }

    func revealOutput() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: outputPath)])
    }

    func revealLivePreview() {
        NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: livePreviewPath)])
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

    func refreshLivePreview() {
        let url = URL(fileURLWithPath: livePreviewPath)
        if let image = NSImage(contentsOf: url) {
            livePreviewImage = image
            livePreviewStatus = url.lastPathComponent
        } else {
            livePreviewImage = nil
            livePreviewStatus = FileManager.default.fileExists(atPath: livePreviewPath)
                ? "Live preview exists but could not be decoded."
                : "No live preview rendered."
        }
    }

    func orbitCamera(deltaX: CGFloat, deltaY: CGFloat) {
        let radius = max(2.0, sqrt(camX * camX + camY * camY))
        let angle = atan2(camY, camX) + Double(deltaX) * 0.008
        camX = cos(angle) * radius
        camY = sin(angle) * radius
        camZ = min(max(camZ - Double(deltaY) * 0.035, -20.0), 20.0)
        useCustomCamera = true
        scheduleLivePreview()
    }

    func markCameraEdited() {
        useCustomCamera = true
        scheduleLivePreview()
    }

    func setFNumberStop(index: Double) {
        let idx = min(max(Int(index.rounded()), 0), CameraStopTables.fNumbers.count - 1)
        fNumber = CameraStopTables.fNumbers[idx]
        scheduleLivePreview()
    }

    func setISOStop(index: Double) {
        let idx = min(max(Int(index.rounded()), 0), CameraStopTables.isoValues.count - 1)
        iso = CameraStopTables.isoValues[idx]
        scheduleLivePreview()
    }

    func setShutterStop(index: Double) {
        let idx = min(max(Int(index.rounded()), 0), CameraStopTables.shutters.count - 1)
        shutter = CameraStopTables.shutters[idx]
        scheduleLivePreview()
    }

    private var commandInputs: RenderCommandInputs {
        RenderCommandInputs(
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
            outputPath: outputPath,
            previewOutputPath: livePreviewPath,
            previewWidth: livePreviewWidth,
            previewHeight: livePreviewHeight
        )
    }

    private func startProcess(plan: RenderCommandPlan, isPreview: Bool) {
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

        if isPreview {
            previewProcess = process
            previewReadHandle = readHandle
        } else {
            runningProcess = process
            runningReadHandle = readHandle
        }

        readHandle.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
            DispatchQueue.main.async {
                self?.appendLog(text)
                self?.updateProgress(from: text, plan: plan, isPreview: isPreview)
            }
        }

        process.terminationHandler = { [weak self] proc in
            readHandle.readabilityHandler = nil
            let data = readHandle.readDataToEndOfFile()
            let text = String(data: data, encoding: .utf8) ?? ""
            DispatchQueue.main.async {
                self?.finishProcess(plan: plan, isPreview: isPreview, status: proc.terminationStatus, trailingText: text)
            }
        }

        do {
            try process.run()
            if isPreview {
                previewProgressFraction = max(previewProgressFraction, 0.05)
            } else {
                progressFraction = max(progressFraction, 0.05)
                progressLabel = "Process started"
            }
        } catch {
            if isPreview {
                isPreviewRunning = false
                previewProcess = nil
                previewReadHandle = nil
                livePreviewStatus = "Failed to start live preview: \(error.localizedDescription)"
            } else {
                isRunning = false
                runningProcess = nil
                runningReadHandle = nil
                progressFraction = 0
                progressLabel = "Failed to start"
                logText = "Failed to start render: \(error.localizedDescription)"
            }
        }
    }

    private func appendLog(_ text: String) {
        logText += "\n" + text
    }

    private func finishProcess(plan: RenderCommandPlan, isPreview: Bool, status: Int32, trailingText: String) {
        if !trailingText.isEmpty {
            appendLog(trailingText)
            updateProgress(from: trailingText, plan: plan, isPreview: isPreview)
        }
        if isPreview {
            isPreviewRunning = false
            previewProcess = nil
            previewReadHandle = nil
            previewProgressFraction = status == 0 ? 1.0 : previewProgressFraction
            livePreviewStatus = status == 0 ? "Live preview finished." : "Live preview exited with status \(status)."
            refreshLivePreview()
        } else {
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
    }

    private func updateProgress(from text: String, plan: RenderCommandPlan, isPreview: Bool) {
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
            if isPreview {
                previewProgressFraction = max(previewProgressFraction, fraction)
            } else if fraction > progressFraction {
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
