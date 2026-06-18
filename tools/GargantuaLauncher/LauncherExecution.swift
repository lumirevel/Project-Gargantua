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

    // MARK: Interactive preview (persistent "warm" instance of the real renderer)
    let camera = OrbitCameraController()
    let previewServer = PreviewServer()
    @Published var previewQuality: PreviewQuality = .medium
    @Published var autoPreview = true
    @Published var previewImage: NSImage?
    @Published var isPreviewRendering = false
    @Published var isPreviewInteracting = false
    @Published var previewStatus = "Drag to orbit · scroll to zoom"
    @Published var previewPixelSize = ""
    let previewOutputPath = "/private/tmp/gargantua_gui_preview.png"
    private let previewCmdFile = "/private/tmp/gargantua_gui_serve_cmd.txt"

    // Progressive refine ladder. After the camera settles the preview climbs a
    // few increasing resolutions (rough -> sharp) instead of jumping straight to
    // full width. Each step is dispatched only after the previous frame arrives,
    // and a step is recognised by the rendered frame's pixel width (not a raw
    // frame counter) so the server's initial launch frame can't desync it.
    private var refineLadderWidths: [Int] = []
    private var ladderStep = 0
    private var ladderActive = false
    private var ladderPendingWidth = 0

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
        previewServer.onFrame = { [weak self] image in
            guard let self else { return }
            self.previewImage = image
            self.advanceLadder(renderedWidth: Self.pixelWidth(of: image))
        }
        previewServer.onStatus = { [weak self] rendering, status in
            self?.isPreviewRendering = rendering
            self?.previewStatus = status
        }
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

    var commandPlan: RenderCommandPlan { RenderCommandPlanner.plan(for: commandInputs(noBuild: noBuild)) }
    var commandPreview: String { commandPlan.commandPreview }

    /// Path to the cached Release binary the pipeline reuses with `--no-build`.
    static var blackholeBinaryPath: String {
        let dd = ProcessInfo.processInfo.environment["BH_DERIVED_DATA_PATH"] ?? "/tmp/BlackholeDD_rebuild"
        return "\(dd)/Build/Products/Release/Blackhole"
    }

    // MARK: - Interactive preview (persistent warm renderer)

    func setPreviewRadius(_ value: Double) { camera.setRadius(value); cameraEdited() }
    func setPreviewAzimuth(_ value: Double) { camera.setAzimuthDegrees(value); cameraEdited() }
    func setPreviewElevation(_ value: Double) { camera.setElevationDegrees(value); cameraEdited() }
    func setPreviewFov(_ value: Double) { camera.setFov(value); cameraEdited() }
    func resetPreviewCamera() { camera.reset(); cameraEdited() }

    private func cameraEdited() {
        objectWillChange.send()
        refinePreview()
    }

    func setPreviewInteracting(_ value: Bool) {
        if isPreviewInteracting != value { isPreviewInteracting = value }
    }

    func previewCameraDidCommit() { objectWillChange.send() }

    /// Stream the current pose to the warm renderer at the fast (low) resolution —
    /// called continuously while the camera is being dragged (renders coalesce).
    /// A live camera move abandons any in-progress refine climb.
    func streamPreviewCamera() {
        ladderActive = false
        sendPreview(width: previewQuality.fastWidth)
    }

    /// Render the current pose progressively — used when the camera settles, on a
    /// settings change, or as the manual trigger. Starts the resolution ladder at
    /// its first (intermediate) step; `advanceLadder` climbs to full width as each
    /// frame arrives.
    func requestPreviewRender() { refinePreview() }
    func renderPreviewNow() { refinePreview() }
    func refinePreview() {
        refineLadderWidths = previewQuality.refineLadder
        guard let first = refineLadderWidths.first else {
            ladderActive = false
            sendPreview(width: previewQuality.refineWidth)
            return
        }
        ladderStep = 0
        ladderActive = true
        ladderPendingWidth = previewSize(width: first).width
        sendPreview(width: first)
    }

    /// Called for every frame the warm renderer delivers. When a refine climb is
    /// active and the arriving frame matches the width we last requested, dispatch
    /// the next-higher rung; the initial launch frame and any stale drag frames
    /// have a different width and are ignored.
    private func advanceLadder(renderedWidth: Int) {
        guard ladderActive, renderedWidth == ladderPendingWidth else { return }
        ladderStep += 1
        guard ladderStep < refineLadderWidths.count else {
            ladderActive = false
            return
        }
        let next = refineLadderWidths[ladderStep]
        ladderPendingWidth = previewSize(width: next).width
        sendPreview(width: next)
    }

    /// Pixel width of a decoded preview frame (used to identify its ladder rung).
    private static func pixelWidth(of image: NSImage) -> Int {
        if let rep = image.representations.first as? NSBitmapImageRep { return rep.pixelsWide }
        return Int(image.size.width.rounded())
    }

    /// (Re)configure the warm serve process for the current setup and send the
    /// current camera pose at the given resolution.
    private func sendPreview(width baseWidth: Int) {
        guard autoPreview, !isRunning else { return }
        let size = previewSize(width: baseWidth)
        previewPixelSize = "\(size.width)x\(size.height)"
        let invocation = previewPipelineInvocation()
        let cmdFile = previewCmdFile
        previewServer.configure(token: previewSetupToken, imageOut: previewOutputPath) {
            LauncherModel.fetchServeCommand(invocation: invocation, cmdFile: cmdFile)
        }
        let eye = camera.state.eye
        let roll = Double(camera.state.roll) * 180.0 / .pi
        let line = "\(Double(eye.x)) \(Double(eye.y)) \(Double(eye.z)) \(Double(camera.state.fov)) \(roll) \(size.width) \(size.height)"
        previewServer.render(camera: line)
    }

    /// Everything except the camera pose + resolution. When this changes the warm
    /// serve process must relaunch (new disk atlas / pipelines / exposure setup).
    private var previewSetupToken: String {
        [
            selectedSourceID, String(describing: blackHoleMetric), String(spin),
            String(describing: observerMode), renderIntentID,
            String(describing: exposureProgram), String(exposureEV),
            String(fNumber), String(iso), shutter,
            String(enableColorGrade), String(enableCinematicEffects), String(enableDepthOfField),
            String(describing: eyePhotometric), String(useEyeND), String(eyeND),
            diskHDF5Path, "\(outputSize.width)x\(outputSize.height)"
        ].joined(separator: "|")
    }

    /// The run_pipeline.sh + BH_PRINT_CMD invocation that yields the translated
    /// binary argv for the current setup (built on the main actor; run off it).
    private func previewPipelineInvocation() -> PreviewPipelineInvocation {
        let binaryExists = FileManager.default.isExecutableFile(atPath: Self.blackholeBinaryPath)
        let inputs = commandInputs(noBuild: binaryExists)
        let launch = previewSize(width: previewQuality.fastWidth)
        let plan = RenderCommandPlanner.previewPlan(for: inputs, width: launch.width, height: launch.height, output: previewOutputPath)
        // Bake a preview-specific collisions path into the emitted binary command
        // so the warm serve never clashes with a final render's collisions file.
        var env = processEnvironment(
            root: plan.repositoryRoot.path,
            collisionsOut: "/private/tmp/gargantua_gui_serve_collisions.bin",
            etaHistory: nil
        )
        env["BH_PRINT_CMD"] = previewCmdFile
        return PreviewPipelineInvocation(
            executable: "/bin/bash",
            arguments: [plan.executablePath] + plan.arguments,
            currentDirectory: plan.repositoryRoot.path,
            environment: env
        )
    }

    /// Runs run_pipeline.sh in BH_PRINT_CMD mode (off the main actor) and returns
    /// the translated binary argv, building the renderer first if it is missing.
    nonisolated static func fetchServeCommand(invocation: PreviewPipelineInvocation, cmdFile: String) -> [String]? {
        try? FileManager.default.removeItem(atPath: cmdFile)
        let process = Process()
        process.executableURL = URL(fileURLWithPath: invocation.executable)
        process.arguments = invocation.arguments
        process.currentDirectoryURL = URL(fileURLWithPath: invocation.currentDirectory)
        process.environment = invocation.environment
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard let text = try? String(contentsOfFile: cmdFile, encoding: .utf8) else { return nil }
        let lines = text.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
        return lines.count >= 2 ? lines : nil
    }

    private func previewSize(width baseWidth: Int) -> (width: Int, height: Int) {
        let out = outputSize
        let w = max(16, baseWidth)
        let h = max(16, Int((Double(w) * Double(out.height) / Double(max(out.width, 1))).rounded()))
        return (w - (w % 2), h - (h % 2))
    }

    // MARK: - Final render

    func runRender() {
        guard !isRunning else { return }
        ladderActive = false
        previewServer.shutdown() // free the GPU for the full-resolution render
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
            requestPreviewRender()
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

    private func commandInputs(noBuild noBuildValue: Bool) -> RenderCommandInputs {
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
            noBuild: noBuildValue,
            rayBundleMode: showAdvancedPhysics ? rayBundleMode : .off,
            rayBundleJacobianStrength: rayBundleJacobianStrength,
            rayBundleFootprintClamp: rayBundleFootprintClamp,
            useCustomCamera: true, // the orbit camera always drives both preview and final
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

    private func processEnvironment(root: String, collisionsOut: String?, etaHistory: String?) -> [String: String] {
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
        environment["BH_PROJECT_ROOT"] = root
        if let collisionsOut { environment["BH_COLLISIONS_OUT"] = collisionsOut }
        if let etaHistory {
            // Separate ETA history + no relay: avoids clashing with the final
            // render's file and trims the pipeline's per-launch bookkeeping.
            environment["BH_ETA_HISTORY"] = etaHistory
            environment["BH_ETA_RELAY"] = "none"
        }
        return environment
    }

    private func startProcess(plan: RenderCommandPlan) {
        let process = Process()
        let pipe = Pipe()
        let readHandle = pipe.fileHandleForReading
        process.executableURL = URL(fileURLWithPath: "/bin/bash")
        process.arguments = [plan.executablePath] + plan.arguments
        process.currentDirectoryURL = plan.repositoryRoot
        process.environment = processEnvironment(root: plan.repositoryRoot.path, collisionsOut: nil, etaHistory: nil)
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
        // A final render builds/refreshes the binary; refresh the preview too.
        requestPreviewRender()
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
